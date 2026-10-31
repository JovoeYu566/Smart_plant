#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "ohos_init.h"
#include "cmsis_os2.h"
#include "iot_errno.h"
#include "iot_gpio.h"
#include "iot_i2c.h"
#include "hi_io.h"
#include "hi_time.h"
#include "wifi_device.h"
#include "wifi_error_code.h"
#include "lwip/netif.h"
#include "lwip/netifapi.h"
#include "lwip/api_shell.h"
#include "MQTTClient.h"
#include "mqtt_tls.h"
#include "pcf8574.h"

#include "oled_ssd1306.h"

/* ------------------------- 舵机（SG90）配置 -------------------------
 * 原实现用 IoTPwmStart(port, duty, 50) 驱动 SG90，有两个硬伤：
 *   1) Hi3861 硬件 PWM 的周期/占空寄存器都是 16bit，160MHz 时钟下
 *      最低频率约 2.4kHz，50Hz 会因为分频值溢出而输出错误波形；
 *   2) IoTPwmStart 的 duty 是整数百分比，20ms 周期下 1% = 200us，
 *      500/1500/2500us 会被截断成 2%/7%/12%，角度误差接近 20 度。
 * 因此舵机改为 GPIO 软件 PWM：用 hi_udelay 直接产生 50Hz 脉冲串，
 * 转到位后停止发脉冲（轻量传感器支架靠自锁保持即可）。
 * ------------------------------------------------------------------ */
#define SERVO_GPIO 9
#define SERVO_PWM_CYCLE_US 20000
/* SG90 安全脉宽：600us~2400us 对应 0~180 度，1500us 居中。
 * 500us/2500us 会顶到机械端点，长期堵转会烧舵机，这里不再使用。 */
#define SERVO_MIN_PULSE_US 600
#define SERVO_CENTER_PULSE_US 1500
#define SERVO_MAX_PULSE_US 2400
#define SERVO_MOVE_FRAMES 24 /* 24 帧 ≈ 480ms，足够 SG90 走完 180 度 */
#define SERVO_HOLD_FRAMES 6  /* 角度未变化时的位置刷新帧数 */
#define SERVO_DAMP_MS 120    /* 停止脉冲后等机械抖动收敛 */

#define ULTRA_TRIG_GPIO 11
#define ULTRA_ECHO_GPIO 7
#define ULTRA_ECHO_IO_NAME HI_IO_NAME_GPIO_7
#define ULTRA_ECHO_IO_FUNC HI_IO_FUNC_GPIO_7_GPIO
#define MOTOR_IN1_GPIO 1
#define MOTOR_IN2_GPIO 0
#define MOTOR_IN3_GPIO 2
#define MOTOR_IN4_GPIO 10
#define DHT11_GPIO 8
#define MQTT_BROKER_IP "u7909e19.ala.cn-hangzhou.emqxsl.cn"
#define MQTT_BROKER_PORT 8883
#define MQTT_TOPIC_AGV "sensor/agv/data"
#define MQTT_TOPIC_CMD "plant/gateway/command"
#define MQTT_CLIENT_ID_PREFIX "agv-"
#define MQTT_USERNAME "jzy0606"
#define MQTT_PASSWORD "jzy0606"
#define AGV_WIFI_SSID "CPE-C562"
#define AGV_WIFI_PSK "jzy20050606"
#define AGV_WIFI_SCAN_TIMEOUT 15
#define AGV_WIFI_CONNECT_TIMEOUT 15
#define AGV_WIFI_HOSTNAME "AGV-Node"
#define PCF_FLAME_PIN 1
#define PCF_GAS_PIN 2
#define PCF_SMOKE_PIN 3

#define ULTRA_TIMEOUT_US 40000
#define ULTRA_SCAN_SETTLE_MS 100
#define ULTRA_RETRY_GAP_MS 100
#define ULTRA_RETRY_COUNT 3
#define OBSTACLE_CM 50
/* 转向时间按实际底盘惯性和轮胎抓地力调大，避免短促点动转不过去。 */
#define TURN_MS 430
#define REVERSE_MS 500
#define UTURN_MS 900
#define BUTTON_DEBOUNCE_MS 30
#define SERVO_RIGHT_ANGLE 0
#define SERVO_FRONT_ANGLE 90
#define SERVO_LEFT_ANGLE 180

typedef enum {
    DRIVE_STOP,
    DRIVE_FORWARD,
    DRIVE_BACKWARD,
    DRIVE_LEFT,
    DRIVE_RIGHT,
} DriveAction;

static int g_pcfReady = 0;

static void GpioOutput(int gpio, hi_io_name io, unsigned char func)
{
    IoTGpioInit(gpio);
    hi_io_set_func(io, func);
    IoTGpioSetDir(gpio, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(gpio, 0);
}

static void MotorStop(void)
{
    IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0);
    IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
}

static void MotorApply(DriveAction action)
{
    switch (action) {
        case DRIVE_FORWARD:
            IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 1); IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
            IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 1); IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
            break;
        case DRIVE_BACKWARD:
            IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0); IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 1);
            IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0); IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 1);
            break;
        case DRIVE_LEFT:
            IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 1); IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 0);
            IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 0); IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 1);
            break;
        case DRIVE_RIGHT:
            IoTGpioSetOutputVal(MOTOR_IN1_GPIO, 0); IoTGpioSetOutputVal(MOTOR_IN2_GPIO, 1);
            IoTGpioSetOutputVal(MOTOR_IN3_GPIO, 1); IoTGpioSetOutputVal(MOTOR_IN4_GPIO, 0);
            break;
        default:
            MotorStop();
            break;
    }
}

static int g_servoAngle = -1;
static int g_servoReady = 0;

static unsigned int ServoPulseUsForAngle(int angle)
{
    if (angle < 0) angle = 0;
    if (angle > 180) angle = 180;
    /* 600us~2400us 线性映射 0~180 度，中点自然落在 1500us。 */
    return SERVO_MIN_PULSE_US +
        ((SERVO_MAX_PULSE_US - SERVO_MIN_PULSE_US) * (unsigned int)angle) / 180;
}

/* 输出一帧 50Hz 脉冲：高电平用 hi_udelay 保证宽度精度，
 * 低电平用 usleep 让出 CPU（低电平时长有抖动不影响舵机解析）。 */
static void ServoPulseOnce(unsigned int pulseUs)
{
    IoTGpioSetOutputVal(SERVO_GPIO, IOT_GPIO_VALUE1);
    hi_udelay(pulseUs);
    IoTGpioSetOutputVal(SERVO_GPIO, IOT_GPIO_VALUE0);
    usleep(SERVO_PWM_CYCLE_US - pulseUs);
}

static void ServoDrive(unsigned int pulseUs, int frames)
{
    int i;
    for (i = 0; i < frames; i++) {
        ServoPulseOnce(pulseUs);
    }
    /* 停止发脉冲：SG90 断掉脉冲后保持当前位置，
     * 既避免持续堵转发热，也让超声波测距不受 PWM 时序干扰。 */
    IoTGpioSetOutputVal(SERVO_GPIO, IOT_GPIO_VALUE0);
    usleep(SERVO_DAMP_MS * 1000);
}

static int ServoSetAngle(int angle)
{
    unsigned int pulseUs;
    int frames;

    if (angle < 0) angle = 0;
    if (angle > 180) angle = 180;
    if (!g_servoReady) {
        return -1;
    }

    frames = (g_servoAngle == angle) ? SERVO_HOLD_FRAMES : SERVO_MOVE_FRAMES;
    pulseUs = ServoPulseUsForAngle(angle);
    ServoDrive(pulseUs, frames);
    g_servoAngle = angle;
    return 0;
}

static void BusyDelayUs(unsigned int delayUs)
{
    hi_u64 start = hi_get_us();
    while ((hi_get_us() - start) < delayUs) {
    }
}

static int UltrasonicReadLevel(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    if (IoTGpioGetInputVal(ULTRA_ECHO_GPIO, &value) != IOT_SUCCESS) {
        return -1;
    }
    return (value == IOT_GPIO_VALUE1) ? 1 : 0;
}

static int UltrasonicWaitLevel(int level, unsigned int timeoutUs)
{
    hi_u64 deadline = hi_get_us() + timeoutUs;
    while (hi_get_us() < deadline) {
        int current = UltrasonicReadLevel();
        if (current < 0) {
            return -2;
        }
        if (current == level) {
            return 0;
        }
    }
    return -1;
}

/* 对齐 agv_node 的可靠测距流程，并打印失败阶段，避免串口只看到 START。 */
static int UltrasonicReadCm(void)
{
    hi_u64 startUs;
    hi_u64 pulseUs;
    int sample;
    int i;
    int idle;

    for (i = 0; i < ULTRA_RETRY_COUNT; i++) {
        idle = UltrasonicReadLevel();
        if (idle < 0) {
            printf("[ULTRA] echo GPIO%d read failed\r\n", ULTRA_ECHO_GPIO);
            return -2;
        }
        if (idle != 0) {
            /* 空闲应为低；若仍高，先拉低 Trig 等待回落。 */
            IoTGpioSetOutputVal(ULTRA_TRIG_GPIO, IOT_GPIO_VALUE0);
            if (UltrasonicWaitLevel(0, 30000) != 0) {
                printf("[ULTRA] echo idle=HIGH (retry %d)\r\n", i + 1);
                usleep(ULTRA_RETRY_GAP_MS * 1000);
                continue;
            }
        }

        IoTGpioSetOutputVal(ULTRA_TRIG_GPIO, IOT_GPIO_VALUE0);
        BusyDelayUs(2);
        IoTGpioSetOutputVal(ULTRA_TRIG_GPIO, IOT_GPIO_VALUE1);
        BusyDelayUs(12);
        IoTGpioSetOutputVal(ULTRA_TRIG_GPIO, IOT_GPIO_VALUE0);

        if (UltrasonicWaitLevel(1, ULTRA_TIMEOUT_US) != 0) {
            printf("[ULTRA] no echo rising (retry %d, idle=%d)\r\n", i + 1, idle);
            usleep(ULTRA_RETRY_GAP_MS * 1000);
            continue;
        }
        startUs = hi_get_us();
        if (UltrasonicWaitLevel(0, ULTRA_TIMEOUT_US) != 0) {
            printf("[ULTRA] echo stay HIGH (retry %d)\r\n", i + 1);
            usleep(ULTRA_RETRY_GAP_MS * 1000);
            continue;
        }
        pulseUs = hi_get_us() - startUs;
        sample = (int)(pulseUs / 58);
        if (sample > 1 && sample <= 400) {
            return sample;
        }
        printf("[ULTRA] bad sample=%d pulse=%lluus (retry %d)\r\n",
               sample, (unsigned long long)pulseUs, i + 1);
        usleep(ULTRA_RETRY_GAP_MS * 1000);
    }
    return -3;
}

static int ScanDistanceOnce(int angle)
{
    ServoSetAngle(angle);
    usleep(ULTRA_SCAN_SETTLE_MS * 1000);
    return UltrasonicReadCm();
}

static int ScanDistance(int angle)
{
    int sample;
    int best = -1;
    int attempt;

    for (attempt = 0; attempt < 3; attempt++) {
        sample = ScanDistanceOnce(angle);
        if (sample > 1 && sample <= 400) {
            /* 前方必须采用保守值，避免一次远距离误读掩盖近处障碍。 */
            if (angle == SERVO_FRONT_ANGLE) {
                if (best < 0 || sample < best) {
                    best = sample;
                }
                if (sample <= OBSTACLE_CM) {
                    break;
                }
            } else {
                /* 侧向选较远值，减少偶发弱回波导致的错误转向。 */
                if (best < 0 || sample > best) {
                    best = sample;
                }
                if (sample >= 390) {
                    break;
                }
            }
        }
        usleep(ULTRA_RETRY_GAP_MS * 1000);
    }
    return best;
}

static volatile int g_buttonToggle = 0;

static int ButtonToggleRequested(void)
{
    if (g_buttonToggle) {
        g_buttonToggle = 0;
        return 1;
    }
    return 0;
}

static void OledStatus(const char *state, int distance)
{
    char line2[22];
    if (distance >= 0) {
        (void)snprintf(line2, sizeof(line2), "DIST %dCM", distance);
    } else {
        (void)strncpy(line2, "DIST ERROR", sizeof(line2));
        line2[sizeof(line2) - 1] = '\0';
    }
    OledShowLines(state, line2);
}

static void ButtonTask(void *arg)
{
    static int armed = 0;
    static int releasedCount = 0;
    static int state = 0; /* 0=idle 1=pressed-confirm 2=wait-release 3=release-confirm */
    (void)arg;

    while (1) {
        int pressed = g_pcfReady && Pcf8574ReadPin(0, PCF_PIN_BUTTON1) == 0;

        if (!armed) {
            releasedCount = pressed ? 0 : releasedCount + 1;
            if (releasedCount >= 50) {
                armed = 1;
                printf("[BUTTON] P0 stable released 1s; button armed\r\n");
            }
            usleep(20 * 1000);
            continue;
        }

        switch (state) {
            case 0:
                if (pressed) state = 1;
                break;
            case 1:
                if (pressed) {
                    state = 2;
                    printf("[BUTTON] P0 press confirmed\r\n");
                } else {
                    state = 0;
                }
                break;
            case 2:
                if (!pressed) state = 3;
                break;
            case 3:
                if (!pressed) {
                    g_buttonToggle = 1;
                    printf("[BUTTON] P0 release confirmed; toggle queued\r\n");
                }
                state = 0;
                break;
        }
        usleep(20 * 1000);
    }
}

static Network g_mqttNetwork;
static MQTTClient g_mqttClient;
static unsigned char g_mqttSend[512];
static unsigned char g_mqttRead[512];
static char g_mqttClientId[32];
static int g_mqttConnected = 0;
static int g_wifiConnected = 0;
static int g_agvEstop = 0;
static int g_ultraFront = -1;
static int g_ultraLeft = -1;
static int g_ultraRight = -1;
static volatile int g_alarmFlame = 0;
static volatile int g_alarmGas = 0;
static volatile int g_alarmSmoke = 0;
static volatile float g_tempC = 0.0f;
static volatile float g_humiPct = 0.0f;
static volatile int g_dataChanged = 0;

static void MqttClientIdInit(void)
{
    unsigned char mac[6] = {0};
    if (GetDeviceMacAddress(mac) == WIFI_SUCCESS) {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId), "%s%02x%02x%02x%02x%02x%02x",
                 MQTT_CLIENT_ID_PREFIX, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    } else {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId), "%s%08lx", MQTT_CLIENT_ID_PREFIX,
                 (unsigned long)osKernelGetTickCount());
    }
}

static void OnCommandMessage(MessageData *md)
{
    char buf[160];
    int len;
    if (md == NULL || md->message == NULL || md->message->payload == NULL) return;
    len = (int)md->message->payloadlen;
    if (len <= 0) return;
    if (len >= (int)sizeof(buf)) len = (int)sizeof(buf) - 1;
    memcpy(buf, md->message->payload, len);
    buf[len] = '\0';
    if (strstr(buf, "AGV_ESTOP") != NULL) {
        g_agvEstop = 1;
        MotorStop();
        printf("[CMD] AGV_ESTOP\r\n");
    } else if (strstr(buf, "AGV_RESUME") != NULL) {
        g_agvEstop = 0;
        printf("[CMD] AGV_RESUME\r\n");
    }
}

static int MqttConnect(void)
{
    MQTTPacket_connectData data = MQTTPacket_connectData_initializer;
    if (MqttTlsConnect(&g_mqttNetwork, MQTT_BROKER_IP, MQTT_BROKER_PORT) != 0) return -1;
    MQTTClientInit(&g_mqttClient, &g_mqttNetwork, 5000, g_mqttSend, sizeof(g_mqttSend), g_mqttRead, sizeof(g_mqttRead));
    data.clientID.cstring = g_mqttClientId;
    data.username.cstring = MQTT_USERNAME;
    data.password.cstring = MQTT_PASSWORD;
    data.keepAliveInterval = 60;
    data.cleansession = 1;
    data.MQTTVersion = 4;
    printf("[MQTT] broker connect...\r\n");
    if (MQTTConnect(&g_mqttClient, &data) != 0) {
        printf("[MQTT] broker connect failed\r\n");
        MqttTlsDisconnect(&g_mqttNetwork);
        return -1;
    }
    printf("[MQTT] broker connected\r\n");
    if (MQTTSubscribe(&g_mqttClient, MQTT_TOPIC_CMD, QOS0, OnCommandMessage) != 0) {
        MqttTlsDisconnect(&g_mqttNetwork);
        return -1;
    }
    g_mqttConnected = 1;
    printf("[MQTT] connected pub=%s sub=%s\r\n", MQTT_TOPIC_AGV, MQTT_TOPIC_CMD);
    return 0;
}

static void MQTT_Cleanup(void)
{
    g_mqttConnected = 0;
    MqttTlsDisconnect(&g_mqttNetwork);
}

static int MQTT_Maintain(void)
{
    if (!g_mqttConnected) return -1;
    if (MQTTYield(&g_mqttClient, 200) != 0) {
        printf("[MQTT] yield failed\r\n");
        MQTT_Cleanup();
        return -1;
    }
    return 0;
}

static void PublishStatus(int front, int left, int right, float temp, float humi)
{
    char payload[320];
    MQTTMessage msg;
    if (!g_mqttConnected) return;
    snprintf(payload, sizeof(payload),
        "{\"node\":\"agv\",\"alarm_type\":%d,\"alarm_active\":%s,"
        "\"agv_temperature\":%.1f,\"agv_humidity\":%.1f,\"agv_flame\":%s,"
        "\"agv_smoke\":%s,\"agv_gas\":%s,\"agv_dist_front\":%d,"
        "\"agv_dist_back\":-1,\"agv_dist_left\":%d,\"agv_dist_right\":%d}",
        (g_alarmFlame ? 1 : 0) + (g_alarmSmoke ? 2 : 0) + (g_alarmGas ? 4 : 0),
        (g_alarmFlame || g_alarmSmoke || g_alarmGas) ? "true" : "false",
        temp, humi,
        g_alarmFlame ? "true" : "false", g_alarmSmoke ? "true" : "false",
        g_alarmGas ? "true" : "false", front, left, right);
    msg.qos = QOS0; msg.retained = 0; msg.dup = 0;
    msg.payload = payload; msg.payloadlen = strlen(payload);
    if (MQTTPublish(&g_mqttClient, MQTT_TOPIC_AGV, &msg) != 0) {
        printf("[MQTT] publish failed\r\n");
        g_mqttConnected = 0;
        MqttTlsDisconnect(&g_mqttNetwork);
    } else {
        printf("[MQTT] pub %s\r\n", payload);
    }
}

static void ReadPcfAlarms(void)
{
    g_alarmFlame = Pcf8574GetPin(0, PCF_FLAME_PIN) == 0;
    g_alarmGas = Pcf8574GetPin(0, PCF_GAS_PIN) == 0;
    g_alarmSmoke = Pcf8574GetPin(0, PCF_SMOKE_PIN) == 0;
}

static volatile int g_wifiScanDone = 0;
static volatile int g_wifiScanCount = 0;
static int g_wifiNetId = -1;
static WifiEvent g_wifiEvent = {0};

static void WifiScanStateChanged(int state, int size)
{
    (void)state;
    g_wifiScanCount = size;
    g_wifiScanDone = 1;
    printf("[WiFi] scan finished, networks=%d\r\n", size);
}

static void WifiConnectionChanged(int state, WifiLinkedInfo *info)
{
    if (state == WIFI_STATE_AVAILABLE && info != NULL) {
        g_wifiConnected = 1;
    } else {
        g_wifiConnected = 0;
    }
}

static int WiFiConnect(void)
{
    WifiErrorCode err;
    WifiDeviceConfig config = {0};
    int timeout;

    printf("[WiFi] connecting SSID=%s\r\n", AGV_WIFI_SSID);
    g_wifiEvent.OnWifiScanStateChanged = WifiScanStateChanged;
    g_wifiEvent.OnWifiConnectionChanged = WifiConnectionChanged;
    err = RegisterWifiEvent(&g_wifiEvent);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] register event failed=%d\r\n", err);
        return -1;
    }
    err = EnableWifi();
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] enable failed=%d\r\n", err);
        return -1;
    }
    timeout = 5;
    while (!IsWifiActive() && timeout-- > 0) sleep(1);
    if (!IsWifiActive()) {
        printf("[WiFi] not active\r\n");
        return -1;
    }
    g_wifiScanDone = 0;
    if (Scan() != WIFI_SUCCESS) {
        printf("[WiFi] scan start failed\r\n");
        return -1;
    }
    timeout = AGV_WIFI_SCAN_TIMEOUT;
    while (!g_wifiScanDone && timeout-- > 0) sleep(1);
    if (!g_wifiScanDone) {
        printf("[WiFi] scan timeout\r\n");
        return -1;
    }
    strncpy(config.ssid, AGV_WIFI_SSID, sizeof(config.ssid) - 1);
    strncpy(config.preSharedKey, AGV_WIFI_PSK, sizeof(config.preSharedKey) - 1);
    config.securityType = WIFI_SEC_TYPE_PSK;
    config.ssid[sizeof(config.ssid) - 1] = '\0';
    config.preSharedKey[sizeof(config.preSharedKey) - 1] = '\0';
    printf("[WiFi] adding config ssid=%s\r\n", config.ssid);
    err = AddDeviceConfig(&config, &g_wifiNetId);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] add config failed=%d\r\n", err);
        return -1;
    }
    g_wifiConnected = 0;
    err = ConnectTo(g_wifiNetId);
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] connect failed=%d\r\n", err);
        return -1;
    }
    timeout = AGV_WIFI_CONNECT_TIMEOUT;
    while (!g_wifiConnected && timeout-- > 0) sleep(1);
    if (!g_wifiConnected) {
        printf("[WiFi] connect timeout\r\n");
        return -1;
    }
    printf("[WiFi] connected\r\n");
    struct netif *netif = netifapi_netif_find("wlan0");
    if (netif == NULL) {
        printf("[WiFi] wlan0 not found\r\n");
        return -1;
    }
#if LWIP_NETIF_HOSTNAME
    netif->hostname = AGV_WIFI_HOSTNAME;
#endif
    dhcp_start(netif);
    timeout = 10;
    while (timeout-- > 0) {
        sleep(1);
        if (dhcp_is_bound(netif) == ERR_OK) {
            printf("[WiFi] DHCP bound\r\n");
            netifapi_netif_common(netif, dhcp_clients_info_show, NULL);
            return 0;
        }
    }
    printf("[WiFi] DHCP timeout\r\n");
    return -1;
}

static int Dht11_ReadTempHumi(float *temp, float *humi);
static uint32_t Dht11_ReadRaw(uint8_t data[5]);
static void Dht11_Task(void *arg)
{
    float temp;
    float humi;
    (void)arg;
    while (1) {
        if (Dht11_ReadTempHumi(&temp, &humi) == 0) {
            g_tempC = temp;
            g_humiPct = humi;
            g_dataChanged = 1;
        }
        usleep(2000 * 1000);
    }
}

static uint32_t Dht11_ReadRaw(uint8_t data[5])
{
    int i;
    int bit;
    uint8_t bytes[5] = {0};
    IotGpioValue val = IOT_GPIO_VALUE0;
    uint64_t t0;

    IoTGpioInit(DHT11_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_8, HI_IO_FUNC_GPIO_8_GPIO);
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(DHT11_GPIO, 0);
    usleep(18000);
    IoTGpioSetOutputVal(DHT11_GPIO, 1);
    hi_udelay(30);
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_8, HI_IO_PULL_UP);

    t0 = hi_get_us();
    while (1) {
        if (IoTGpioGetInputVal(DHT11_GPIO, &val) != IOT_SUCCESS) return IOT_FAILURE;
        if (val == IOT_GPIO_VALUE0) break;
        if (hi_get_us() - t0 > 100) return IOT_FAILURE;
    }
    t0 = hi_get_us();
    while (1) {
        if (IoTGpioGetInputVal(DHT11_GPIO, &val) != IOT_SUCCESS) return IOT_FAILURE;
        if (val == IOT_GPIO_VALUE1) break;
        if (hi_get_us() - t0 > 100) return IOT_FAILURE;
    }
    t0 = hi_get_us();
    while (1) {
        if (IoTGpioGetInputVal(DHT11_GPIO, &val) != IOT_SUCCESS) return IOT_FAILURE;
        if (val == IOT_GPIO_VALUE0) break;
        if (hi_get_us() - t0 > 100) return IOT_FAILURE;
    }

    for (i = 0; i < 5; i++) bytes[i] = 0;
    for (bit = 0; bit < 40; bit++) {
        while (1) {
            if (IoTGpioGetInputVal(DHT11_GPIO, &val) != IOT_SUCCESS) return IOT_FAILURE;
            if (val == IOT_GPIO_VALUE1) break;
        }
        t0 = hi_get_us();
        while (1) {
            if (IoTGpioGetInputVal(DHT11_GPIO, &val) != IOT_SUCCESS) return IOT_FAILURE;
            if (val == IOT_GPIO_VALUE0) break;
            if (hi_get_us() - t0 > 100) return IOT_FAILURE;
        }
        if ((hi_get_us() - t0) > 40) {
            bytes[bit / 8] |= (1u << (7 - (bit % 8)));
        }
    }
    if (((uint8_t)(bytes[0] + bytes[1] + bytes[2] + bytes[3])) != bytes[4]) {
        return IOT_FAILURE;
    }
    memcpy(data, bytes, 5);
    return IOT_SUCCESS;
}

static int Dht11_ReadTempHumi(float *temp, float *humi)
{
    uint8_t raw[5];
    if (temp == NULL || humi == NULL) return -1;
    if (Dht11_ReadRaw(raw) != IOT_SUCCESS) return -1;
    *humi = (float)raw[0] + (float)raw[1] / 10.0f;
    *temp = (float)raw[2] + (float)raw[3] / 10.0f;
    return 0;
}

static void AgvServoTask(void *arg)
{
    int running = 0;
    int front;
    int left;
    int right;
    int lastCount = 0;
    int flame = 0;
    int gas = 0;
    int smoke = 0;
    int count = 0;
    (void)arg;

    printf("\r\n[AGV2] button-controlled obstacle avoidance ready\r\n");
    MotorStop();
    g_ultraFront = -1;
    g_ultraLeft = -1;
    g_ultraRight = -1;
    if (OledInit() == IOT_SUCCESS) {
        OledStatus("AGV STOP", -1);
        printf("[OLED] ready\r\n");
    }
    if (Pcf8574Init() == IOT_SUCCESS) {
        g_pcfReady = 1;
    }
    printf("[AGV2] press PCF8574 P0 button to START or STOP\r\n");
    MqttClientIdInit();
    osThreadAttr_t dhtAttr = {0};
    dhtAttr.name = "Dht11Task";
    dhtAttr.stack_size = 2048;
    dhtAttr.priority = osPriorityBelowNormal;
    if (osThreadNew(Dht11_Task, NULL, &dhtAttr) == NULL) {
        printf("[DHT11] task create failed\r\n");
    }
    if (WiFiConnect() == 0) {
        printf("[MQTT] starting TLS connection...\r\n");
        if (MqttConnect() != 0) {
            printf("[MQTT] connection failed\r\n");
            printf("[MQTT] initial connection failed\r\n");
        }
    } else {
        printf("[WiFi] initial connection failed\r\n");
    }

    while (1) {
        count++;
        if (ButtonToggleRequested()) {
            running = !running;
            MotorStop();
            ServoSetAngle(SERVO_FRONT_ANGLE);
            OledStatus(running ? "AGV RUN" : "AGV STOP", -1);
            printf("[AGV2] %s\r\n", running ? "START" : "STOP");
            usleep(150 * 1000);
        }

        if (!g_wifiConnected) {
            if (WiFiConnect() == 0) {
                g_wifiConnected = 1;
            }
        }
        if (g_wifiConnected && !g_mqttConnected) {
            if (MqttConnect() != 0) {
                usleep(100 * 1000);
                continue;
            }
        }
        if (g_mqttConnected) {
            (void)MQTT_Maintain();
        }

        flame = (Pcf8574GetPin(0, PCF_FLAME_PIN) == 0) ? 1 : 0;
        gas = (Pcf8574GetPin(0, PCF_GAS_PIN) == 0) ? 1 : 0;
        smoke = (Pcf8574GetPin(0, PCF_SMOKE_PIN) == 0) ? 1 : 0;
        if (flame != g_alarmFlame || gas != g_alarmGas || smoke != g_alarmSmoke) {
            g_alarmFlame = flame;
            g_alarmGas = gas;
            g_alarmSmoke = smoke;
            g_dataChanged = 1;
        }

        if (running && g_agvEstop) {
            MotorStop();
            OledStatus("E-STOP", -1);
        } else if (running) {
            front = ScanDistance(SERVO_FRONT_ANGLE);
            g_ultraFront = front;
            if (front < 0) {
                MotorStop();
                OledStatus("SENSOR ERR", front);
                printf("[ULTRA] SENSOR ERR front=%d (check Echo->GPIO%d Trig->GPIO%d)\r\n",
                       front, ULTRA_ECHO_GPIO, ULTRA_TRIG_GPIO);
                usleep(300 * 1000);
                continue;
            }
            if (front > OBSTACLE_CM) {
                OledStatus("FORWARD", front);
                MotorApply(DRIVE_FORWARD);
                printf("[AVOID] front=%dcm forward\r\n", front);
            } else {
                MotorStop();
                left = ScanDistance(SERVO_LEFT_ANGLE);
                right = ScanDistance(SERVO_RIGHT_ANGLE);
                g_ultraLeft = left;
                g_ultraRight = right;
                printf("[AVOID] left=%dcm right=%dcm\r\n", left, right);
                ServoSetAngle(SERVO_FRONT_ANGLE);
                if (left > OBSTACLE_CM) {
                    OledStatus("TURN LEFT", left);
                    MotorApply(DRIVE_LEFT);
                    usleep(TURN_MS * 1000);
                } else if (right > OBSTACLE_CM) {
                    OledStatus("TURN RIGHT", right);
                    MotorApply(DRIVE_RIGHT);
                    usleep(TURN_MS * 1000);
                } else {
                    OledStatus("UTURN", front);
                    MotorApply(DRIVE_BACKWARD);
                    usleep(REVERSE_MS * 1000);
                    MotorApply(DRIVE_RIGHT);
                    usleep(UTURN_MS * 1000);
                }
                MotorStop();
            }
            ServoSetAngle(SERVO_FRONT_ANGLE);
        } else {
            g_ultraFront = -1;
            g_ultraLeft = -1;
            g_ultraRight = -1;
        }

        if (g_dataChanged || (count - lastCount) >= 5) {
            if (g_mqttConnected) {
                PublishStatus(g_ultraFront, g_ultraLeft, g_ultraRight, g_tempC, g_humiPct);
                g_dataChanged = 0;
            }
            lastCount = count;
        }
        if (!running) {
            MotorStop();
            usleep(20 * 1000);
            continue;
        }
        usleep(200 * 1000);
    }
}

static void AgvServoInit(void)
{
    GpioOutput(MOTOR_IN1_GPIO, HI_IO_NAME_GPIO_1, HI_IO_FUNC_GPIO_1_GPIO);
    GpioOutput(MOTOR_IN2_GPIO, HI_IO_NAME_GPIO_0, HI_IO_FUNC_GPIO_0_GPIO);
    GpioOutput(MOTOR_IN3_GPIO, HI_IO_NAME_GPIO_2, HI_IO_FUNC_GPIO_2_GPIO);
    GpioOutput(MOTOR_IN4_GPIO, HI_IO_NAME_GPIO_10, HI_IO_FUNC_GPIO_10_GPIO);
    GpioOutput(ULTRA_TRIG_GPIO, HI_IO_NAME_GPIO_11, HI_IO_FUNC_GPIO_11_GPIO);
    IoTGpioInit(ULTRA_ECHO_GPIO);
    hi_io_set_func(ULTRA_ECHO_IO_NAME, ULTRA_ECHO_IO_FUNC);
    IoTGpioSetDir(ULTRA_ECHO_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(ULTRA_ECHO_IO_NAME, HI_IO_PULL_DOWN);
    IoTGpioSetOutputVal(ULTRA_TRIG_GPIO, IOT_GPIO_VALUE0);
    usleep(50 * 1000);
    printf("[ULTRA] trig=GPIO%d echo=GPIO%d initialized (pull-down)\r\n",
           ULTRA_TRIG_GPIO, ULTRA_ECHO_GPIO);
    {
        int probe = UltrasonicReadCm();
        printf("[ULTRA] boot probe = %d cm (trig=GPIO%d echo=GPIO%d)\r\n",
               probe, ULTRA_TRIG_GPIO, ULTRA_ECHO_GPIO);
    }

    /* 舵机走软件 PWM，GPIO9 必须复用为普通 GPIO 输出，不能再设成 PWM0_OUT。 */
    IoTGpioInit(SERVO_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_9, HI_IO_FUNC_GPIO_9_GPIO);
    IoTGpioSetDir(SERVO_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(SERVO_GPIO, IOT_GPIO_VALUE0);
    g_servoReady = 1;
    printf("[SERVO] software PWM 50Hz on GPIO9, %u-%uus\r\n",
        (unsigned int)SERVO_MIN_PULSE_US, (unsigned int)SERVO_MAX_PULSE_US);

    osThreadAttr_t buttonAttr = {0};
    buttonAttr.name = "ButtonMonitor";
    buttonAttr.stack_size = 1024;
    buttonAttr.priority = osPriorityNormal;
    if (osThreadNew(ButtonTask, NULL, &buttonAttr) == NULL) {
        printf("[BUTTON] monitor task create failed\r\n");
    }

    osThreadAttr_t attr = {0};
    attr.name = "AgvServo";
    attr.stack_size = 4096;
    attr.priority = osPriorityNormal;
    (void)osThreadNew(AgvServoTask, NULL, &attr);
}

SYS_RUN(AgvServoInit);
