#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "ohos_init.h"
#include "cmsis_os2.h"
#include "iot_errno.h"
#include "iot_gpio.h"
#include "hi_io.h"
#include "hi_time.h"

#include "wifi_device.h"
#include "wifi_error_code.h"
#include "lwip/opt.h"
#include "lwip/netif.h"
#include "lwip/netifapi.h"
#include "lwip/api_shell.h"

#include "MQTTClient.h"
#include "mqtt_tls.h"

#include "sht20.h"
#include "oled_ssd1306.h"
#include "pcf8574.h"

/* ===== 部署前必须修改：以下凭据在仓库中为占位值，烧录前请换成现场真实配置 ===== */

/* ---------- WiFi（与中控网关同一热点） ---------- */
#define WIFI_SSID               "YOUR_WIFI_SSID"
#define WIFI_PSK                "YOUR_WIFI_PASSWORD"
#define WIFI_SCAN_TIMEOUT       15
#define WIFI_CONNECT_TIMEOUT    15
#define WIFI_HOSTNAME           "AGV-Node"

/* ---------- MQTT：上报给中控网关汇总 ---------- */
#define MQTT_BROKER_IP          "YOUR_BROKER_HOST.emqxsl.cn"
#define MQTT_BROKER_PORT        8883
#define MQTT_TOPIC_AGV          "sensor/qst/data"   /* 中控网关订阅此主题 */
#define MQTT_TOPIC_CMD          "plant/gateway/command" /* 控制台下发命令 */
#define MQTT_CLIENT_ID_PREFIX   "agv-"
#define MQTT_USERNAME           "YOUR_MQTT_USERNAME"
#define MQTT_PASSWORD           "YOUR_MQTT_PASSWORD"
#define MQTT_CMD_TIMEOUT        5000
#define MQTT_KEEP_ALIVE         60
#define MQTT_RECONNECT_INTERVAL 50  /* 约 10s（主循环 200ms） */

/* 蜂鸣器和板载灯已拆除 */

/* I2C0：OLED / SHT20 / 两块 PCF8574 共享 SDA=GPIO13, SCL=GPIO14 */
#define ALARM_FLASH_MS          100
#define US_TIMEOUT_US           30000
#define US_US_PER_CM            58
#define ENABLE_SHT20            0

/* 四路超声波命名顺序：前/后/左/右 */
#define US_FRONT  0
#define US_BACK   1
#define US_LEFT   2
#define US_RIGHT  3
#define US_CH_NUM 4

/* L298N：板载 GPIO 直接驱动 */
#define MOTOR_IN1_GPIO           1  /* 右轮 IN1 */
#define MOTOR_IN2_GPIO           0  /* 右轮 IN2 */
#define MOTOR_IN3_GPIO           2  /* 左轮 IN3 */
#define MOTOR_IN4_GPIO           10 /* 左轮 IN4 */
#define ULTRA_FRONT_ECHO_GPIO    8
#define ULTRA_FRONT_TRIG_GPIO    11
#define ULTRA_LEFT_ECHO_GPIO     9
#define ULTRA_LEFT_TRIG_GPIO     12
#define BUTTON1_GPIO             3  /* I2C拓展板P3 */
#define BUTTON1_ACTIVE_LEVEL      0
#define AVOID_THRESHOLD_CM       50
#define AVOID_ABNORMAL_CM       5000
#define AVOID_REVERSE_MS         500
#define AVOID_TURN_MS            500
#define AVOID_STOP_MS             20

/* 避障动作：0停止 1前进 2后退 3左转 4右转（非阻塞状态机，便于 OLED 刷新） */
#define DRIVE_ACT_STOP   0
#define DRIVE_ACT_FWD    1
#define DRIVE_ACT_BACK   2
#define DRIVE_ACT_LEFT   3
#define DRIVE_ACT_RIGHT  4

static volatile int g_driveEnabled = 0;
static volatile int g_button1PrevPressed = 0;
static volatile int g_driveAction = 0;
static volatile int g_agvEstop = 0;
/* 超声/避障任务共享数据 */
static volatile int g_ultraFront = -1;
static volatile int g_ultraBack = -1;
static volatile int g_ultraLeft = -1;
static volatile int g_ultraRight = -1;
static volatile int g_ultraReady = 0;
static volatile int g_ultraBusy = 0;
static osMutexId_t g_ultraMutex = NULL;

static volatile int g_flameAlarm = 0;
static volatile int g_smokeAlarm = 0;
static volatile int g_gasAlarm = 0;
static int g_pcfReady = 0;

static int g_wifiScanDone = 0;
static int g_wifiConnected = 0;
static int g_ssidCount = 0;
static int g_wifiNetId = -1;
static WifiEvent g_wifiEvent = {0};

static Network mqttNetwork;
static MQTTClient mqttClient;
static unsigned char mqttSendBuf[512];
static unsigned char mqttReadBuf[512];
static int g_mqttConnected = 0;
static char g_mqttClientId[32];
static int g_mqttReconnectAt = 0;
static int g_sht20Ready = 0;

static void Motor_Stop(void);
static void OnCommandMessage(MessageData *md);

static void MQTT_InitClientId(void)
{
    unsigned char mac[6] = {0};
    if (GetDeviceMacAddress(mac) == WIFI_SUCCESS) {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId),
                 "%s%02x%02x%02x%02x%02x%02x", MQTT_CLIENT_ID_PREFIX,
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    } else {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId),
                 "%s%08lx", MQTT_CLIENT_ID_PREFIX, (unsigned long)osKernelGetTickCount());
    }
    printf("[MQTT] clientID=%s\r\n", g_mqttClientId);
}

static void MQTT_CleanupDeadSession(void)
{
    g_mqttConnected = 0;
    MqttTlsDisconnect(&mqttNetwork);
}

static int MQTT_Connect(void)
{
    printf("[MQTT] 连接 %s:%d ...\r\n", MQTT_BROKER_IP, MQTT_BROKER_PORT);
    if (MqttTlsConnect(&mqttNetwork, MQTT_BROKER_IP, MQTT_BROKER_PORT) != 0) {
        printf("[MQTT] TLS失败\r\n");
        return -1;
    }

    MQTTClientInit(&mqttClient, &mqttNetwork, MQTT_CMD_TIMEOUT,
                   mqttSendBuf, sizeof(mqttSendBuf), mqttReadBuf, sizeof(mqttReadBuf));

    MQTTPacket_connectData connData = MQTTPacket_connectData_initializer;
    connData.clientID.cstring = g_mqttClientId;
    connData.keepAliveInterval = MQTT_KEEP_ALIVE;
    connData.cleansession = 1;
    connData.MQTTVersion = 4;
    connData.username.cstring = MQTT_USERNAME;
    connData.password.cstring = MQTT_PASSWORD;

    if (MQTTConnect(&mqttClient, &connData) != 0) {
        printf("[MQTT] 认证失败\r\n");
        MqttTlsDisconnect(&mqttNetwork);
        return -1;
    }
    g_mqttConnected = 1;
    g_mqttReconnectAt = 0;
    printf("[MQTT] 连接成功, 发布主题=%s\r\n", MQTT_TOPIC_AGV);
    if (MQTTSubscribe(&mqttClient, MQTT_TOPIC_CMD, QOS0, OnCommandMessage) != 0) {
        printf("[MQTT] 订阅控制主题失败: %s\r\n", MQTT_TOPIC_CMD);
    } else {
        printf("[MQTT] 已订阅控制主题: %s\r\n", MQTT_TOPIC_CMD);
    }
    return 0;
}

static int MQTT_Publish(const char *topic, const char *payload)
{
    if (!g_mqttConnected) {
        return -1;
    }
    MQTTMessage msg;
    msg.qos = QOS0;
    msg.retained = 0;
    msg.dup = 0;
    msg.payload = (void *)payload;
    msg.payloadlen = strlen(payload);
    if (MQTTPublish(&mqttClient, topic, &msg) != 0) {
        printf("[MQTT] 发布失败\r\n");
        MQTT_CleanupDeadSession();
        return -1;
    }
    return 0;
}

static int MQTT_Reconnect(void)
{
    printf("[MQTT] 重连...\r\n");
    MQTT_CleanupDeadSession();
    return MQTT_Connect();
}

static int MQTT_Maintain(void)
{
    if (!g_mqttConnected) {
        return -1;
    }
    if (MQTTYield(&mqttClient, 200) != 0) {
        printf("[MQTT] Yield失败，连接断开\r\n");
        MQTT_CleanupDeadSession();
        return -1;
    }
    return 0;
}

static int ParseJsonString(const char *json, const char *key, char *out, size_t outSize)
{
    char pattern[40];
    const char *p;
    const char *q;
    size_t len;
    if (json == NULL || key == NULL || out == NULL || outSize == 0) {
        return -1;
    }
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    p = strstr(json, pattern);
    if (p == NULL) {
        return -1;
    }
    p += strlen(pattern);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    if (*p == '\"') {
        p++;
        q = strchr(p, '\"');
        if (q == NULL) {
            return -1;
        }
        len = (size_t)(q - p);
    } else {
        q = p;
        while (*q != '\0' && *q != ',' && *q != '}' && *q != ' ' && *q != '\t') {
            q++;
        }
        len = (size_t)(q - p);
    }
    if (len >= outSize) {
        len = outSize - 1;
    }
    memcpy(out, p, len);
    out[len] = '\0';
    return 0;
}

static void OnCommandMessage(MessageData *md)
{
    char buf[256];
    char action[40] = {0};
    char params[160] = {0};
    int len;
    if (md == NULL || md->message == NULL || md->message->payload == NULL) {
        return;
    }
    len = (int)md->message->payloadlen;
    if (len <= 0) {
        return;
    }
    if (len >= (int)sizeof(buf)) {
        len = (int)sizeof(buf) - 1;
    }
    memcpy(buf, md->message->payload, len);
    buf[len] = '\0';
    if (ParseJsonString(buf, "action", action, sizeof(action)) != 0) {
        printf("[CMD] invalid payload: %s\r\n", buf);
        return;
    }
    (void)ParseJsonString(buf, "params", params, sizeof(params));
    printf("[CMD] action=%s params=%s\r\n", action, params[0] ? params : "{}");
    if (strcmp(action, "AGV_ESTOP") == 0) {
        g_agvEstop = 1;
        Motor_Stop();
        g_driveAction = DRIVE_ACT_STOP;
        printf("[CMD] AGV_ESTOP -> stop avoidance\r\n");
    } else if (strcmp(action, "AGV_RESUME") == 0) {
        g_agvEstop = 0;
        printf("[CMD] AGV_RESUME -> resume avoidance\r\n");
    } else {
        printf("[CMD] ignore action=%s\r\n", action);
    }
}

/* 超声波测距（GPIO 版本：前/左为板载GPIO；后/右暂时保留 PCF） */
static void BusyDelayUs(uint32_t delayUs)
{
    uint64_t start = hi_get_us();
    while ((hi_get_us() - start) < delayUs) {
    }
}

static int Ultrasonic_ReadGpio(int trigGpio, int echoGpio)
{
    uint64_t t0;
    uint64_t pulseUs;
    IotGpioValue val = IOT_GPIO_VALUE0;

    IoTGpioSetOutputVal(trigGpio, 0);
    BusyDelayUs(2);
    IoTGpioSetOutputVal(trigGpio, 1);
    BusyDelayUs(12);
    IoTGpioSetOutputVal(trigGpio, 0);

    t0 = hi_get_us();
    while (1) {
        IoTGpioGetInputVal(echoGpio, &val);
        if (val == IOT_GPIO_VALUE1) {
            break;
        }
        if ((hi_get_us() - t0) > US_TIMEOUT_US) {
            return -2; /* 没等到 Echo 上升沿 */
        }
    }

    t0 = hi_get_us();
    while (1) {
        IoTGpioGetInputVal(echoGpio, &val);
        if (val == IOT_GPIO_VALUE0) {
            break;
        }
        if ((hi_get_us() - t0) > US_TIMEOUT_US) {
            return -3; /* Echo 一直为高 */
        }
    }
    pulseUs = hi_get_us() - t0;
    if (pulseUs < (uint64_t)US_US_PER_CM) {
        return -4; /* 脉冲过短 */
    }
    return (int)(pulseUs / US_US_PER_CM);
}

static void Ultrasonic_GpioInit(void)
{
    IoTGpioInit(ULTRA_FRONT_TRIG_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_11, HI_IO_FUNC_GPIO_11_GPIO);
    IoTGpioSetDir(ULTRA_FRONT_TRIG_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(ULTRA_FRONT_TRIG_GPIO, 0);

    IoTGpioInit(ULTRA_FRONT_ECHO_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_8, HI_IO_FUNC_GPIO_8_GPIO);
    IoTGpioSetDir(ULTRA_FRONT_ECHO_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_8, HI_IO_PULL_DOWN);

    IoTGpioInit(ULTRA_LEFT_TRIG_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_12, HI_IO_FUNC_GPIO_12_GPIO);
    IoTGpioSetDir(ULTRA_LEFT_TRIG_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(ULTRA_LEFT_TRIG_GPIO, 0);

    IoTGpioInit(ULTRA_LEFT_ECHO_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_9, HI_IO_FUNC_GPIO_9_GPIO);
    IoTGpioSetDir(ULTRA_LEFT_ECHO_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_9, HI_IO_PULL_DOWN);
}

static int Ultrasonic_ReadPcf(int dev, unsigned int trigPin, unsigned int echoPin)
{
    uint64_t t0;
    uint64_t pulseUs;

    Pcf8574SetPin(dev, trigPin, 0);
    usleep(2);
    Pcf8574SetPin(dev, trigPin, 1);
    usleep(12);
    Pcf8574SetPin(dev, trigPin, 0);

    t0 = hi_get_us();
    while (Pcf8574ReadPin(dev, echoPin) == 0) {
        if ((hi_get_us() - t0) > US_TIMEOUT_US) {
            return -1;
        }
    }

    t0 = hi_get_us();
    while (Pcf8574ReadPin(dev, echoPin) != 0) {
        if ((hi_get_us() - t0) > US_TIMEOUT_US) {
            return -1;
        }
    }
    pulseUs = hi_get_us() - t0;
    if (pulseUs < (uint64_t)US_US_PER_CM) {
        return -1;
    }
    return (int)(pulseUs / US_US_PER_CM);
}

static void Ultrasonic_ReadAll(int distOut[US_CH_NUM])
{
    distOut[US_FRONT] = Ultrasonic_ReadGpio(ULTRA_FRONT_TRIG_GPIO, ULTRA_FRONT_ECHO_GPIO);
    distOut[US_LEFT] = Ultrasonic_ReadGpio(ULTRA_LEFT_TRIG_GPIO, ULTRA_LEFT_ECHO_GPIO);
    if (g_pcfReady) {
        distOut[US_BACK] = Ultrasonic_ReadPcf(PCF_DEV0, PCF_PIN_US2_TRIG, PCF_PIN_US2_ECHO);
        distOut[US_RIGHT] = Ultrasonic_ReadPcf(PCF_DEV0, PCF_PIN_US1_TRIG, PCF_PIN_US1_ECHO);
    } else {
        distOut[US_BACK] = -1;
        distOut[US_RIGHT] = -1;
    }
}

static int SanitizeUltra(int d)
{
    if (d < 0 || d >= AVOID_ABNORMAL_CM) {
        return -1;
    }
    return d;
}

static void *UltrasonicTask(void *arg)
{
    (void)arg;
    int dist[US_CH_NUM];
    int count = 0;
    while (1) {
        if (g_ultraBusy) {
            usleep(20 * 1000);
            continue;
        }
        g_ultraBusy = 1;
        Ultrasonic_ReadAll(dist);
        if (g_ultraMutex != NULL && osMutexAcquire(g_ultraMutex, 10) == osOK) {
            g_ultraFront = SanitizeUltra(dist[US_FRONT]);
            g_ultraBack = SanitizeUltra(dist[US_BACK]);
            g_ultraLeft = SanitizeUltra(dist[US_LEFT]);
            g_ultraRight = SanitizeUltra(dist[US_RIGHT]);
            g_ultraReady = 1;
            osMutexRelease(g_ultraMutex);
        }
        g_ultraBusy = 0;
        count++;
        if (count % 100 == 0) {
            printf("[ULTRA] F/B/L/R=%d/%d/%d/%d\r\n",
                   g_ultraFront, g_ultraBack, g_ultraLeft, g_ultraRight);
        }
        usleep(100 * 1000);
    }
    return NULL;
}

static void UltrasonicTaskStart(void)
{
    if (g_ultraMutex == NULL) {
        g_ultraMutex = osMutexNew(NULL);
        if (g_ultraMutex == NULL) {
            printf("[ULTRA] mutex create failed\r\n");
            return;
        }
    }
    osThreadAttr_t attr = {0};
    attr.name = "UltrasonicTask";
    attr.stack_size = 3072;
    attr.priority = osPriorityAboveNormal;
    if (osThreadNew((osThreadFunc_t)UltrasonicTask, NULL, &attr) == NULL) {
        printf("[ULTRA] 任务创建失败\r\n");
    }
}

/* 板载 GPIO 直接驱动 L298N */
static void Motor_Init(void)
{
    IoTGpioInit(MOTOR_IN1_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_1, HI_IO_FUNC_GPIO_1_GPIO);
    IoTGpioSetDir(MOTOR_IN1_GPIO, IOT_GPIO_DIR_OUT);

    IoTGpioInit(MOTOR_IN2_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_0, HI_IO_FUNC_GPIO_0_GPIO);
    IoTGpioSetDir(MOTOR_IN2_GPIO, IOT_GPIO_DIR_OUT);

    IoTGpioInit(MOTOR_IN3_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_2, HI_IO_FUNC_GPIO_2_GPIO);
    IoTGpioSetDir(MOTOR_IN3_GPIO, IOT_GPIO_DIR_OUT);

    IoTGpioInit(MOTOR_IN4_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_10, HI_IO_FUNC_GPIO_10_GPIO);
    IoTGpioSetDir(MOTOR_IN4_GPIO, IOT_GPIO_DIR_OUT);

    Motor_Stop();
}

static void Motor_Stop(void)
{
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
}

static void Motor_Forward(void)
{
    /* 右 IN1/IN2 + 左 IN3/IN4 同向前进 */
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
}

static void Motor_Backward(void)
{
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 1);
}

static void Motor_TurnLeft(void)
{
    /* 左转：右轮前进、左轮后退 */
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 1);
}

static void Motor_TurnRight(void)
{
    /* 右转：左轮前进、右轮后退 */
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 1);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
}

static const char *DriveActionName(int action)
{
    switch (action) {
        case 1: return "RUN";
        case 2: return "BACK";
        case 3: return "LEFT";
        case 4: return "RIGHT";
        default: return "STOP";
    }
}

static int IsObstacleDistance(int d)
{
    return d > 0 && d <= AVOID_THRESHOLD_CM;
}

static void Button1_Init(void)
{
    printf("[BUTTON1] read from PCF8574 P3\r\n");
}

static int Button1_Pressed(void)
{
    if (!g_pcfReady) {
        return 0;
    }
    return (Pcf8574ReadPin(PCF_DEV0, PCF_PIN_BUTTON1) == 0) ? 1 : 0;
}

static int Button1_TogglePressed(void)
{
    int pressed = Button1_Pressed();
    int edge = (pressed && !g_button1PrevPressed) ? 1 : 0;
    g_button1PrevPressed = pressed;
    return edge;
}

static void Avoidance_Execute(int front, int back, int left, int right)
{
    int frontBlocked = IsObstacleDistance(front);
    int backBlocked = IsObstacleDistance(back);
    int leftBlocked = IsObstacleDistance(left);
    int rightBlocked = IsObstacleDistance(right);

    if (!g_driveEnabled || g_agvEstop) {
        Motor_Stop();
        g_driveAction = DRIVE_ACT_STOP;
        return;
    }

    if (!frontBlocked) {
        Motor_Forward();
        g_driveAction = DRIVE_ACT_FWD;
    } else if (!leftBlocked) {
        Motor_TurnLeft();
        g_driveAction = DRIVE_ACT_LEFT;
    } else if (!rightBlocked) {
        Motor_TurnRight();
        g_driveAction = DRIVE_ACT_RIGHT;
    } else if (!backBlocked) {
        Motor_Backward();
        g_driveAction = DRIVE_ACT_BACK;
    } else {
        Motor_Stop();
        g_driveAction = DRIVE_ACT_STOP;
    }
}

/* 火焰/烟雾/燃气报警任务 */
static void AlarmFlashTask(void *arg)
{
    (void)arg;
    int phase = 0;
    int wasAlarm = 0;
    while (1) {
        if (g_flameAlarm || g_smokeAlarm || g_gasAlarm) {
            wasAlarm = 1;
            phase ^= 1;
            usleep(ALARM_FLASH_MS * 1000);
        } else {
            if (wasAlarm) {
                wasAlarm = 0;
                phase = 0;
            }
            usleep(50 * 1000);
        }
    }
}

static void AlarmFlash_Start(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "AlarmFlash";
    attr.stack_size = 2048;
    attr.priority = osPriorityAboveNormal;
    if (osThreadNew(AlarmFlashTask, NULL, &attr) == NULL) {
        printf("[ALARM] 闪烁任务创建失败\r\n");
    }
}

static void OnWifiScanChanged(int state, int size)
{
    (void)state;
    if (size > 0) {
        g_ssidCount = size;
        g_wifiScanDone = 1;
    }
    printf("  WiFi扫描回调: size=%d\r\n", size);
}

static void OnWifiConnectionChanged(int state, WifiLinkedInfo *info)
{
    if (info != NULL && state == WIFI_STATE_AVAILABLE) {
        g_wifiConnected = 1;
        printf("  WiFi已连接! rssi=%d\r\n", info->rssi);
    } else {
        g_wifiConnected = 0;
        printf("  WiFi状态变化: state=%d\r\n", state);
    }
}

static void OnHotspotStaJoin(StationInfo *info) { (void)info; }
static void OnHotspotStaLeave(StationInfo *info) { (void)info; }
static void OnHotspotStateChanged(int state) { (void)state; }

static int WiFi_Connect(void)
{
    printf("[WiFi] 开始连接 %s ...\r\n", WIFI_SSID);

    g_wifiEvent.OnWifiScanStateChanged = OnWifiScanChanged;
    g_wifiEvent.OnWifiConnectionChanged = OnWifiConnectionChanged;
    g_wifiEvent.OnHotspotStaJoin = OnHotspotStaJoin;
    g_wifiEvent.OnHotspotStaLeave = OnHotspotStaLeave;
    g_wifiEvent.OnHotspotStateChanged = OnHotspotStateChanged;

    WifiErrorCode err = RegisterWifiEvent(&g_wifiEvent);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] 注册事件失败: %d\r\n", err);
        return -1;
    }

    err = EnableWifi();
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] 使能失败: %d\r\n", err);
        return -1;
    }

    int timeout = 5;
    while (!IsWifiActive() && timeout > 0) {
        sleep(1);
        timeout--;
    }
    if (!IsWifiActive()) {
        printf("[WiFi] 未激活\r\n");
        return -1;
    }
    printf("[WiFi] 已激活，开始扫描...\r\n");

    g_wifiScanDone = 0;
    Scan();
    timeout = WIFI_SCAN_TIMEOUT;
    while (!g_wifiScanDone && timeout > 0) {
        sleep(1);
        timeout--;
    }
    if (!g_wifiScanDone) {
        printf("[WiFi] 扫描超时\r\n");
        return -1;
    }
    printf("[WiFi] 发现 %d 个网络\r\n", g_ssidCount);

    unsigned int size = WIFI_SCAN_HOTSPOT_LIMIT;
    WifiScanInfo *scanInfo = malloc(sizeof(WifiScanInfo) * WIFI_SCAN_HOTSPOT_LIMIT);
    if (scanInfo == NULL) {
        printf("[WiFi] 内存不足\r\n");
        return -1;
    }
    GetScanInfoList(scanInfo, &size);

    int found = -1;
    for (int i = 0; i < g_ssidCount; i++) {
        if (i < 10) {
            printf("  [%d] %s (rssi=%d)\r\n", i + 1, scanInfo[i].ssid, scanInfo[i].rssi);
        }
        if (strcmp(scanInfo[i].ssid, WIFI_SSID) == 0) {
            found = i;
        }
    }
    if (found < 0) {
        printf("[WiFi] 未找到 '%s'\r\n", WIFI_SSID);
        free(scanInfo);
        return -1;
    }

    WifiDeviceConfig config = {0};
    strncpy(config.ssid, WIFI_SSID, sizeof(config.ssid) - 1);
    config.ssid[sizeof(config.ssid) - 1] = '\0';
    strncpy(config.preSharedKey, WIFI_PSK, sizeof(config.preSharedKey) - 1);
    config.preSharedKey[sizeof(config.preSharedKey) - 1] = '\0';
    config.securityType = WIFI_SEC_TYPE_PSK;

    g_wifiNetId = 0;
    err = AddDeviceConfig(&config, &g_wifiNetId);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] 添加配置失败: %d\r\n", err);
        free(scanInfo);
        return -1;
    }

    g_wifiConnected = 0;
    err = ConnectTo(g_wifiNetId);
    free(scanInfo);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] ConnectTo失败: %d\r\n", err);
        return -1;
    }

    timeout = WIFI_CONNECT_TIMEOUT;
    while (!g_wifiConnected && timeout > 0) {
        sleep(1);
        timeout--;
    }
    if (!g_wifiConnected) {
        printf("[WiFi] 连接超时\r\n");
        return -1;
    }
    printf("[WiFi] 连接成功，DHCP中...\r\n");

    struct netif *netif = netifapi_netif_find("wlan0");
    if (netif == NULL) {
        printf("[WiFi] 未找到 wlan0\r\n");
        return -1;
    }

    /* 必须在 DHCP 之前设置，路由器才能显示自定义名称 */
#if LWIP_NETIF_HOSTNAME
    netif->hostname = WIFI_HOSTNAME;
    printf("[WiFi] hostname=%s\r\n", netif->hostname);
#endif

    dhcp_start(netif);
    timeout = 10;
    while (timeout > 0) {
        sleep(1);
        if (dhcp_is_bound(netif) == ERR_OK) {
            printf("[WiFi] 获取IP成功!\r\n");
            netifapi_netif_common(netif, dhcp_clients_info_show, NULL);
            return 0;
        }
        timeout--;
    }
    printf("[WiFi] DHCP超时\r\n");
    return -1;
}

static void AgvAppTask(void *arg)
{
    (void)arg;
    char line[24];
    float temp = 0.0f;
    float humi = 0.0f;
    int count = 0;

    printf("\r\n============================\r\n");
    printf("  AGV Node (从节点采集)\r\n");
    printf("  Board: QST-HM-1.1\r\n");
    printf("  SSID: %s\r\n", WIFI_SSID);
    printf("  hostname: %s\r\n", WIFI_HOSTNAME);
    printf("  MQTT topic: %s\r\n", MQTT_TOPIC_AGV);
    printf("============================\r\n\r\n");

    printf("[STEP] Motor_Init...\r\n");
    Motor_Init();
    printf("[STEP] Button1_Init...\r\n");
    Button1_Init();
    printf("[STEP] OledInit...\r\n");
    if (OledInit() != IOT_SUCCESS) {
        printf("[ERR] OLED init failed\r\n");
    } else {
        printf("[STEP] OLED ok\r\n");
    }
    OledFillScreen(0x00);
    OledShowString(0, 0, "AGV Node", FONT8x16);
    OledShowString(0, 2, "Init...", FONT8x16);
    usleep(100 * 1000);

    printf("[STEP] Pcf8574Init...\r\n");
    if (Pcf8574Init() != IOT_SUCCESS) {
        g_pcfReady = 0;
        printf("[WARN] PCF8574 init failed, skip PCF-dependent features\r\n");
    } else {
        g_pcfReady = 1;
        printf("[STEP] PCF8574 ok\r\n");
    }
    printf("  -> 火焰/烟雾/燃气报警；超声仅上报\r\n");

#if ENABLE_SHT20
    printf("[STEP] SHT20_Init...\r\n");
    if (SHT20_Init() != IOT_SUCCESS) {
        g_sht20Ready = 0;
        printf("[WARN] SHT20 not present, skip temp/humi\r\n");
    } else {
        g_sht20Ready = 1;
        printf("[STEP] SHT20 ok\r\n");
    }
#else
    g_sht20Ready = 0;
    printf("[STEP] SHT20 disabled\r\n");
#endif

    printf("[STEP] Ultrasonic_GpioInit...\r\n");
    Ultrasonic_GpioInit();
    printf("[STEP] UltrasonicTaskStart...\r\n");
    UltrasonicTaskStart();

    OledFillScreen(0x00);
    OledShowString(0, 0, "WiFi...", FONT8x16);
    OledShowString(0, 2, WIFI_SSID, FONT6x8);
    if (WiFi_Connect() == 0) {
        OledFillScreen(0x00);
        OledShowString(0, 0, "WiFi OK", FONT8x16);
        printf("[WiFi] 就绪\r\n");

        MQTT_InitClientId();
        OledShowString(0, 2, "MQTT...", FONT8x16);
        if (MQTT_Connect() == 0) {
            OledShowString(0, 2, "MQTT OK ", FONT8x16);
        } else {
            OledShowString(0, 2, "MQTT FAIL", FONT8x16);
            g_mqttReconnectAt = MQTT_RECONNECT_INTERVAL;
        }
    } else {
        OledFillScreen(0x00);
        OledShowString(0, 0, "WiFi FAIL", FONT8x16);
        OledShowString(0, 2, "Continue", FONT8x16);
        printf("[WiFi] 失败，继续本地采集\r\n");
    }
    sleep(2);
    OledFillScreen(0x00);

    {
        int lastFlame = -1; /* -1 表示尚未采样，强制首次上报 */
        int lastSmoke = -1;
        int lastGas = -1;
        int lastDist[US_CH_NUM] = { -2, -2, -2, -2 };
        int lastTempX10 = -9999; /* 0.1℃ 精度 */
        int lastHumiX10 = -9999;

        while (1) {
        count++;
        /* 按键1只控制驱动/避障启停，不影响采集/报警/MQTT/OLED */
        if (Button1_TogglePressed()) {
            g_driveEnabled = !g_driveEnabled;
            if (!g_driveEnabled) {
                Motor_Stop();
                g_driveAction = DRIVE_ACT_STOP;
            }
            printf("[DRIVE] 按键1切换状态 -> %s\r\n", g_driveEnabled ? "ON" : "OFF");
            usleep(200 * 1000);
        }

        if (count % 20 == 0 && g_wifiNetId >= 0) {
            WifiLinkedInfo linkedInfo;
            if (GetLinkedInfo(&linkedInfo) != WIFI_SUCCESS || !g_wifiConnected) {
                printf("[WiFi] 已断开，尝试重连...\r\n");
                g_wifiConnected = 0;
                MQTT_CleanupDeadSession();
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
                if (ConnectTo(g_wifiNetId) == WIFI_SUCCESS) {
                    int retry = 10;
                    while (!g_wifiConnected && retry > 0) {
                        sleep(1);
                        retry--;
                    }
                    if (g_wifiConnected) {
                        struct netif *netif = netifapi_netif_find("wlan0");
                        if (netif) {
#if LWIP_NETIF_HOSTNAME
                            netif->hostname = WIFI_HOSTNAME;
#endif
                            dhcp_start(netif);
                        }
                        printf("[WiFi] 重连成功\r\n");
                    }
                }
            }
        }

        if (g_mqttConnected) {
            if (MQTT_Maintain() != 0) {
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
            }
        }
        if (g_agvEstop) {
            Motor_Stop();
            g_driveAction = DRIVE_ACT_STOP;
        }
        if (!g_mqttConnected && g_wifiConnected && count >= g_mqttReconnectAt) {
            if (MQTT_Reconnect() != 0) {
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
            }
        }

        /* 火焰/烟雾/燃气 + 四路超声波（前/后/左/右） */
        int flame = 0;
        int smoke = 0;
        int gas = 0;
        if (g_pcfReady) {
            flame = (Pcf8574GetPin(PCF_DEV0, PCF_PIN_FLAME) == 0) ? 1 : 0;
            smoke = (Pcf8574GetPin(PCF_DEV0, PCF_PIN_SMOKE) == 0) ? 1 : 0;
            gas = (Pcf8574GetPin(PCF_DEV0, PCF_PIN_GAS) == 0) ? 1 : 0;
        }
        int distCm[US_CH_NUM];
        int i;
        int dataChanged = 0;
        char distStr[48];

        g_flameAlarm = flame;
        g_smokeAlarm = smoke;
        g_gasAlarm = gas;

        if (g_ultraReady && g_ultraMutex != NULL && osMutexAcquire(g_ultraMutex, 10) == osOK) {
            distCm[US_FRONT] = g_ultraFront;
            distCm[US_BACK] = g_ultraBack;
            distCm[US_LEFT] = g_ultraLeft;
            distCm[US_RIGHT] = g_ultraRight;
            osMutexRelease(g_ultraMutex);
        } else {
            distCm[US_FRONT] = -1;
            distCm[US_BACK] = -1;
            distCm[US_LEFT] = -1;
            distCm[US_RIGHT] = -1;
        }
        Avoidance_Execute(distCm[US_FRONT], distCm[US_BACK], distCm[US_LEFT], distCm[US_RIGHT]);

        {
            int n = 0;
            n += snprintf(distStr + n, sizeof(distStr) - n, "F/B/L/R=");
            for (i = 0; i < US_CH_NUM; i++) {
                if (i > 0) {
                    n += snprintf(distStr + n, sizeof(distStr) - n, "/");
                }
                if (distCm[i] < 0) {
                    n += snprintf(distStr + n, sizeof(distStr) - n, "--");
                } else {
                    n += snprintf(distStr + n, sizeof(distStr) - n, "%d", distCm[i]);
                }
            }
        }

        g_flameAlarm = flame ? 1 : 0;
        /* 按键仅控制驱动轮与避障，其他原有采集/报警逻辑不受影响 */

        /* 温湿度约每秒读一次（5×200ms） */
        if (count % 5 == 0) {
            if (!g_sht20Ready || SHT20_ReadTempHumidity(&temp, &humi) != IOT_SUCCESS) {
                printf("[%d] SHT20 skip/read error Dist %s\r\n", count, distStr);
                OledShowString(0, 0, "SHT20 SKIP", FONT8x16);
            } else {
                printf("[%d] T=%.2fC H=%.1f%% Flame=%d Smoke=%d Gas=%d Dist %s WiFi=%s MQTT=%s%s%s%s\r\n",
                       count, temp, humi, flame, smoke, gas, distStr,
                       g_wifiConnected ? "OK" : "OFF",
                       g_mqttConnected ? "OK" : "OFF",
                       flame ? " FLAME!" : "",
                       smoke ? " SMOKE!" : "",
                       gas ? " GAS!" : "");

                /* 本板 OLED 仅两行(FONT8x16: y=0 / y=2) */
                if (flame || smoke || gas) {
                    snprintf(line, sizeof(line), "T:%.1f %s", temp,
                             flame ? "FLAME" : (smoke ? "SMOKE" : "GAS"));
                    OledShowString(0, 0, line, FONT8x16);
                } else {
                    snprintf(line, sizeof(line), "T:%.1fC H:%.0f", temp, humi);
                    OledShowString(0, 0, line, FONT8x16);
                }
            }

        } else if (flame != lastFlame && lastFlame >= 0) {
            if (flame) {
                OledShowString(0, 2, "FLAME!    ", FONT8x16);
            }
        }

        /* 每圈刷新第2行：动作状态（不依赖 SHT20 1秒周期） */
        if (flame || smoke || gas) {
            snprintf(line, sizeof(line), "ALM %s    ",
                     g_driveEnabled ? DriveActionName(g_driveAction) : "STOP");
        } else if (g_driveEnabled) {
            snprintf(line, sizeof(line), "F%d %s    ",
                     (distCm[US_FRONT] >= 0) ? distCm[US_FRONT] : 0,
                     DriveActionName(g_driveAction));
        } else {
            snprintf(line, sizeof(line), "F%d STOP  ",
                     (distCm[US_FRONT] >= 0) ? distCm[US_FRONT] : 0);
        }
        OledShowString(0, 2, line, FONT8x16);

        /* 任一字段变化立即上报；否则约每 2 秒心跳
         * 距离用 3cm 死区，减轻超声抖动导致的频繁 MQTT（易拖垮 TLS 内存）
         */
        if (flame != lastFlame || smoke != lastSmoke || gas != lastGas) {
            dataChanged = 1;
        }
        for (i = 0; i < US_CH_NUM; i++) {
            int d = distCm[i];
            int ld = lastDist[i];
            /* 无效读数抖动（-- ↔ 数值）不触发立即上报，靠心跳同步 */
            if (d < 0 || ld < 0) {
                continue;
            }
            if (d - ld >= 3 || ld - d >= 3) {
                dataChanged = 1;
                break;
            }
        }
        {
            int tx10 = (int)(temp * 10.0f + (temp >= 0 ? 0.5f : -0.5f));
            int hx10 = (int)(humi * 10.0f + (humi >= 0 ? 0.5f : -0.5f));
            if (tx10 != lastTempX10 || hx10 != lastHumiX10) {
                dataChanged = 1;
            }
        }

        if (dataChanged || (count % 10 == 0)) {
            if (g_mqttConnected) {
                char payload[320];
                snprintf(payload, sizeof(payload),
                         "{\"node\":\"agv\",\"alarm_type\":%d,\"alarm_active\":%s,"
                         "\"agv_temperature\":%.1f,\"agv_humidity\":%.1f,"
                         "\"agv_flame\":%s,\"agv_smoke\":%s,\"agv_gas\":%s,"
                         "\"agv_dist_front\":%d,\"agv_dist_back\":%d,"
                         "\"agv_dist_left\":%d,\"agv_dist_right\":%d}",
                         (flame ? 1 : 0) + (smoke ? 2 : 0) + (gas ? 4 : 0),
                         (flame || smoke || gas) ? "true" : "false",
                         temp, humi,
                         flame ? "true" : "false",
                         smoke ? "true" : "false", gas ? "true" : "false",
                         distCm[US_FRONT], distCm[US_BACK],
                         distCm[US_LEFT], distCm[US_RIGHT]);
                if (MQTT_Publish(MQTT_TOPIC_AGV, payload) == 0) {
                    if (dataChanged) {
                        printf("  [MQTT] 变化立即上报: %s\r\n", payload);
                    } else {
                        printf("  [MQTT] 心跳: %s\r\n", payload);
                    }
                }
            }
            lastFlame = flame;
            lastSmoke = smoke;
            lastGas = gas;
            for (i = 0; i < US_CH_NUM; i++) {
                lastDist[i] = distCm[i];
            }
            lastTempX10 = (int)(temp * 10.0f + (temp >= 0 ? 0.5f : -0.5f));
            lastHumiX10 = (int)(humi * 10.0f + (humi >= 0 ? 0.5f : -0.5f));
        }

        usleep(200 * 1000);
        }
    }
}

static void AgvNodeEntry(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "AgvNodeTask";
    attr.stack_size = 12288; /* WiFi/TLS/DHCP 需要更大栈 */
    attr.priority = osPriorityNormal;
    if (osThreadNew(AgvAppTask, NULL, &attr) == NULL) {
        printf("[AgvNode] Task create failed!\r\n");
    }
}
APP_FEATURE_INIT(AgvNodeEntry);
