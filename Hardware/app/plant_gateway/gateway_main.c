#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include "ohos_init.h"
#include "cmsis_os2.h"
#include "hi_adc.h"
#include "iot_gpio.h"
#include "iot_pwm.h"
#include "iot_i2c.h"
#include "hi_io.h"
#include "hi_watchdog.h"
#include "hi_reset.h"
#include "hi_time.h"
#include "iot_errno.h"
#include "oled_ssd1306.h"
#include "pcf8574.h"

#include "wifi_device.h"
#include "wifi_error_code.h"
#include "lwip/netif.h"
#include "lwip/netifapi.h"
#include "lwip/api_shell.h"

#include "MQTTClient.h"
#include "mqtt_tls.h"

/* ===== 部署前必须修改：以下凭据在仓库中为占位值，烧录前请换成现场真实配置 ===== */
/* MQTT（EMQX Serverless - TLS） */
#define MQTT_BROKER_IP   "YOUR_BROKER_HOST.emqxsl.cn"
#define MQTT_BROKER_PORT 8883
#define MQTT_TOPIC       "gas/sensor/data"      /* 本板汇总上报后端 */
#define BH1750_I2C_IDX   0
#define BH1750_I2C_BAUD  (400 * 1000)
static uint8_t g_bh1750I2cAddr = 0x23;
#define BH1750_ONE_TIME_H_RES_MODE 0x20
#define BH1750_POWER_ON   0x01
#define BH1750_RESET      0x07
#define MQTT_TOPIC_AGV   "sensor/agv/data"      /* 订阅 AGV 从节点数据 */
#define MQTT_TOPIC_CMD   "plant/gateway/command" /* 订阅控制台指令 */
#define MQTT_CLIENT_ID_PREFIX "gw-"
#define MQTT_USERNAME    "YOUR_MQTT_USERNAME"
#define MQTT_PASSWORD    "YOUR_MQTT_PASSWORD"
#define MQTT_CMD_TIMEOUT 5000
#define MQTT_KEEP_ALIVE  60
#define MQTT_RECONNECT_INTERVAL 30
#define AGV_DATA_STALE_SEC 10   /* 配合从节点约 2s 心跳；5s 易误判，改为 10s */

/* WiFi */
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PSK  "YOUR_WIFI_PASSWORD"
#define WIFI_SCAN_TIMEOUT 15
#define WIFI_CONNECT_TIMEOUT 15
#define WIFI_HOSTNAME "Plant-Gateway"

err_t netifapi_set_hostname(struct netif *netif, char *hostname, u8_t namelen);

static Network mqttNetwork;
static MQTTClient mqttClient;
static unsigned char mqttSendBuf[512];
static unsigned char mqttReadBuf[512];
static int g_mqttConnected = 0;
static char g_mqttClientId[32];
static int g_mqttReconnectAt = 0;
static osMutexId_t g_i2c0Mutex = NULL;
static volatile int g_manualAlarm = 0;
static volatile int g_autoAlarmMuted = 0;

static void Beep_On(void);
static void Beep_Off(void);
static void OnAgvMessage(MessageData *md);
static void OnCommandMessage(MessageData *md);
static void Dht11_Init(void);
static int Dht11_GetTempHumi(float *temp, float *humi);

static volatile float g_agvTemp = 0.0f;
static volatile float g_agvHumi = 0.0f;
static volatile int g_agvFlame = 0;
static volatile int g_agvSmoke = 0;
static volatile int g_agvGas = 0;
static volatile int g_agvDistFront = -1;
static volatile int g_agvDistBack = -1;
static volatile int g_agvDistLeft = -1;
static volatile int g_agvDistRight = -1;
static volatile int g_agvOnline = 0;
static volatile int g_agvLastCount = 0;
static volatile int g_agvNeedStamp = 0;
static volatile int g_agvNeedPublish = 0; /* AGV 有新报文，需立即汇总上报 */
static volatile int g_alarmFlashEnable = 0; /* 烟雾/火焰/AGV火焰报警闪烁 */
static volatile int g_gateLight = 0;         /* 白灯手动状态 */
static volatile int g_gateLightManual = 0;   /* 按钮1是否接管白灯 */
static volatile int g_autoWhiteLight = 0;    /* 光照不足/有人时自动白灯 */
static volatile int g_gateBuzzerMute = 0;    /* 按钮2静音锁存 */
static volatile int g_gateAgvEStop = 0;
static volatile int g_gateMaintenanceMode = 0;
static volatile int g_gateNeedReboot = 0;
static volatile unsigned int g_gateCargoCount = 0;

/* 本地传感器最新值（供变化检测 / 汇总上报） */
static float g_gateTemp = 0.0f;
static float g_gateHumi = 0.0f;
static int g_gateGasAdc = 0;
static float g_gateVoltage = 0.0f;
static int g_gateGasAlarm = 0;
static int g_gateSmoke = 0;
static int g_gateFlameAlarm = 0;
static int g_gateLux = 0;
static int g_gatePir = 0;

/* 上次已上报快照（-9999 表示尚未上报过） */
static int g_pubReady = 0;
static float g_pubAgvTemp = 0.0f;
static float g_pubAgvHumi = 0.0f;
static int g_pubAgvFlame = -1;
static int g_pubAgvSmoke = -1;
static int g_pubAgvGas = -1;
static int g_pubAgvOnline = -1;
static int g_pubAgvDistFront = -999;
static int g_pubAgvDistBack = -999;
static int g_pubAgvDistLeft = -999;
static int g_pubAgvDistRight = -999;
static int g_gatePubTempX10 = -9999;
static int g_gatePubHumiX10 = -9999;
static int g_gatePubGasAdc = -1;
static int g_gatePubGasAlarm = -1;
static int g_gatePubSmoke = -1;
static int g_gatePubFlameAlarm = -1;
static int g_gatePubLux = -1;
static int g_gatePubPir = -1;
static unsigned int g_gatePubCargo = 0xFFFFFFFFu;

static int g_wifiScanDone = 0;
static int g_wifiConnected = 0;
static int g_ssidCount = 0;
static int g_wifiNetId = -1;
static WifiEvent g_wifiEvent = {0};

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

static int ParseJsonInt(const char *json, const char *key, int *out)
{
    char pattern[40];
    const char *p;
    if (json == NULL || key == NULL || out == NULL) {
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
    return (sscanf(p, "%d", out) == 1) ? 0 : -1;
}

static int ParseJsonFloat(const char *json, const char *key, float *out)
{
    char pattern[40];
    const char *p;
    if (json == NULL || key == NULL || out == NULL) {
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
    return (sscanf(p, "%f", out) == 1) ? 0 : -1;
}

static int ParseJsonBoolTrue(const char *json, const char *key)
{
    char pattern[40];
    const char *p;
    if (json == NULL || key == NULL) {
        return 0;
    }
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    p = strstr(json, pattern);
    if (p == NULL) {
        return 0;
    }
    p += strlen(pattern);
    while (*p == ' ' || *p == '\t') {
        p++;
    }
    return (strncmp(p, "true", 4) == 0 || strncmp(p, "TRUE", 4) == 0 || *p == '1') ? 1 : 0;
}

static volatile int g_rebootPending = 0;

static void Gateway_DoReboot(void)
{
    printf("[CMD] 已安排安全重启\r\n");
    g_rebootPending = 1;
}

static void Gateway_StartSafeReboot(void)
{
    printf("[CMD] 当前任务执行系统软复位\r\n");
    osDelay(1000);
    printf("[CMD] 调用 hi_soft_reboot\r\n");
    hi_soft_reboot(HI_SYS_REBOOT_CAUSE_CMD);
    while (1) {
        osDelay(100);
    }
}

static void ApplyCommandAction(const char *action, const char *params)
{
    if (action == NULL) {
        return;
    }

    if (strcmp(action, "LIGHT_ON") == 0) {
        g_gateLightManual = 1;
        g_gateLight = 1;
        printf("[CMD] LIGHT_ON\r\n");
    } else if (strcmp(action, "LIGHT_OFF") == 0) {
        g_gateLightManual = 1;
        g_gateLight = 0;
        printf("[CMD] LIGHT_OFF\r\n");
    } else if (strcmp(action, "LIGHT_AUTO") == 0) {
        g_gateLightManual = 0;
        printf("[CMD] LIGHT_AUTO\r\n");
    } else if (strcmp(action, "LIGHT_TOGGLE") == 0) {
        g_gateLightManual = 1;
        g_gateLight = !g_gateLight;
        printf("[CMD] LIGHT_TOGGLE -> %d\r\n", g_gateLight);
    } else if (strcmp(action, "ALARM_ACK") == 0) {
        g_alarmFlashEnable = 0;
        printf("[CMD] ALARM_ACK\r\n");
    } else if (strcmp(action, "ALARM_MUTE") == 0) {
        g_gateBuzzerMute = 1;
        printf("[CMD] ALARM_MUTE\r\n");
    } else if (strcmp(action, "ALARM_UNMUTE") == 0) {
        g_gateBuzzerMute = 0;
        printf("[CMD] ALARM_UNMUTE\r\n");
    } else if (strcmp(action, "BUZZER_ON") == 0) {
        g_gateBuzzerMute = 0;
        Beep_On();
        printf("[CMD] BUZZER_ON\r\n");
    } else if (strcmp(action, "BUZZER_OFF") == 0) {
        g_gateBuzzerMute = 1;
        Beep_Off();
        printf("[CMD] BUZZER_OFF\r\n");
    } else if (strcmp(action, "AGV_ESTOP") == 0) {
        g_gateAgvEStop = 1;
        printf("[CMD] AGV_ESTOP\r\n");
    } else if (strcmp(action, "AGV_RESUME") == 0) {
        g_gateAgvEStop = 0;
        printf("[CMD] AGV_RESUME\r\n");
    } else if (strcmp(action, "CARGO_RESET") == 0) {
        g_gateCargoCount = 0;
        g_agvNeedPublish = 1;
        printf("[CMD] CARGO_RESET -> count=0\r\n");
    } else if (strcmp(action, "GATEWAY_REBOOT") == 0) {
        g_gateNeedReboot = 1;
        printf("[CMD] GATEWAY_REBOOT\r\n");
    } else if (strcmp(action, "GATEWAY_STATUS_QUERY") == 0) {
        g_gateMaintenanceMode = 1;
        g_agvNeedPublish = 1;
        printf("[CMD] GATEWAY_STATUS_QUERY\r\n");
    } else if (strcmp(action, "SENSOR_CALIBRATE") == 0) {
        printf("[CMD] SENSOR_CALIBRATE params=%s\r\n", params ? params : "{}");
        g_agvNeedPublish = 1;
    } else if (strcmp(action, "DATA_SNAPSHOT_FORCE") == 0) {
        g_agvNeedPublish = 1;
        printf("[CMD] DATA_SNAPSHOT_FORCE\r\n");
    } else if (strcmp(action, "MAINTENANCE_MODE_ON") == 0) {
        g_gateMaintenanceMode = 1;
        printf("[CMD] MAINTENANCE_MODE_ON\r\n");
    } else if (strcmp(action, "MAINTENANCE_MODE_OFF") == 0) {
        g_gateMaintenanceMode = 0;
        printf("[CMD] MAINTENANCE_MODE_OFF\r\n");
    } else if (strcmp(action, "AGV_GOTO") == 0) {
        printf("[CMD] AGV_GOTO params=%s\r\n", params ? params : "{}");
    } else {
        printf("[CMD] unknown action=%s params=%s\r\n", action, params ? params : "{}");
    }
}

static void OnAgvMessage(MessageData *md)
{
    if (md == NULL || md->message == NULL || md->message->payload == NULL) {
        return;
    }

    char buf[512];
    int len = (int)md->message->payloadlen;
    int d;
    if (len <= 0) {
        return;
    }
    if (len >= (int)sizeof(buf)) {
        len = (int)sizeof(buf) - 1;
    }
    memcpy(buf, md->message->payload, len);
    buf[len] = '\0';

    g_agvNeedStamp = 1;
    g_agvOnline = 1;
    g_agvNeedPublish = 1;

    if (ParseJsonFloat(buf, "agv_temperature", &g_agvTemp) != 0) {
        printf("[AGV] 温度字段缺失或格式错误\r\n");
    }
    if (ParseJsonFloat(buf, "agv_humidity", &g_agvHumi) != 0) {
        printf("[AGV] 湿度字段缺失或格式错误\r\n");
    }
    g_agvFlame = ParseJsonBoolTrue(buf, "agv_flame");
    g_agvSmoke = ParseJsonBoolTrue(buf, "agv_smoke");
    g_agvGas = ParseJsonBoolTrue(buf, "agv_gas");
    if (ParseJsonInt(buf, "agv_dist_front", &d) == 0) {
        g_agvDistFront = d;
    }
    if (ParseJsonInt(buf, "agv_dist_back", &d) == 0) {
        g_agvDistBack = d;
    }
    if (ParseJsonInt(buf, "agv_dist_left", &d) == 0) {
        g_agvDistLeft = d;
    }
    if (ParseJsonInt(buf, "agv_dist_right", &d) == 0) {
        g_agvDistRight = d;
    }

    printf("[AGV] topic=%s flame=%d smoke=%d gas=%d F/B/L/R=%d/%d/%d/%d\r\n",
           MQTT_TOPIC_AGV, g_agvFlame, g_agvSmoke, g_agvGas,
           g_agvDistFront, g_agvDistBack, g_agvDistLeft, g_agvDistRight);
}

static void OnCommandMessage(MessageData *md)
{
    if (md == NULL || md->message == NULL || md->message->payload == NULL) {
        return;
    }

    char buf[320];
    int len = (int)md->message->payloadlen;
    char action[40] = {0};
    char params[240] = {0};

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

    printf("[CMD] topic=%s action=%s params=%s\r\n", MQTT_TOPIC_CMD, action, params[0] ? params : "{}");
    ApplyCommandAction(action, params);
}

static void MQTT_RefreshAgvStatus(int count)
{
    if (g_agvNeedStamp) {
        g_agvLastCount = count;
        g_agvNeedStamp = 0;
    }
    if (g_agvOnline && (count - g_agvLastCount) > AGV_DATA_STALE_SEC) {
        g_agvOnline = 0;
        g_agvFlame = 0;
        g_agvSmoke = 0;
        g_agvGas = 0;
        g_agvDistFront = -1;
        g_agvDistBack = -1;
        g_agvDistLeft = -1;
        g_agvDistRight = -1;
        g_agvNeedPublish = 1; /* 立刻触发汇总，把 agv_online:false 发出去 */
        printf("[MQTT] AGV 超时%d秒无数据，判为离线\r\n", AGV_DATA_STALE_SEC);
    }
}

static void MQTT_InitClientId(void)
{
    unsigned char mac[6] = {0};
    if (GetDeviceMacAddress(mac) == WIFI_SUCCESS) {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId),
                 "%s%02x%02x%02x%02x%02x%02x",
                 MQTT_CLIENT_ID_PREFIX,
                 mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    } else {
        snprintf(g_mqttClientId, sizeof(g_mqttClientId),
                 "%s%08lx", MQTT_CLIENT_ID_PREFIX,
                 (unsigned long)osKernelGetTickCount());
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
    printf("[MQTT] 连接 %s:%d (TLS)...\r\n", MQTT_BROKER_IP, MQTT_BROKER_PORT);

    int rc = MqttTlsConnect(&mqttNetwork, MQTT_BROKER_IP, MQTT_BROKER_PORT);
    if (rc != 0) {
        printf("[MQTT] TLS连接失败: %d\r\n", rc);
        return -1;
    }
    printf("[MQTT] TLS连接成功\r\n");

    MQTTClientInit(&mqttClient, &mqttNetwork, MQTT_CMD_TIMEOUT,
                   mqttSendBuf, sizeof(mqttSendBuf), mqttReadBuf, sizeof(mqttReadBuf));

    MQTTPacket_connectData connData = MQTTPacket_connectData_initializer;
    connData.clientID.cstring = g_mqttClientId;
    connData.keepAliveInterval = MQTT_KEEP_ALIVE;
    connData.cleansession = 1;
    connData.MQTTVersion = 4;
    connData.username.cstring = MQTT_USERNAME;
    connData.password.cstring = MQTT_PASSWORD;
    /* 异常掉线时由 Broker 代发主节点离线 */
    connData.willFlag = 1;
    connData.will.topicName.cstring = (char *)MQTT_TOPIC;
    connData.will.message.cstring = (char *)"{\"gateway_online\":false}";
    connData.will.qos = 0;
    connData.will.retained = 0;

    printf("[MQTT] 认证: user='%s', clientID='%s'\r\n",
           MQTT_USERNAME, g_mqttClientId);

    rc = MQTTConnect(&mqttClient, &connData);
    if (rc != 0) {
        printf("[MQTT] 连接失败: %d\r\n", rc);
        MqttTlsDisconnect(&mqttNetwork);
        return -1;
    }

    g_mqttConnected = 1;
    g_mqttReconnectAt = 0;
    printf("[MQTT] 连接成功!\r\n");

    rc = MQTTSubscribe(&mqttClient, MQTT_TOPIC_AGV, QOS0, OnAgvMessage);
    if (rc != 0) {
        printf("[MQTT] 订阅 %s 失败: %d\r\n", MQTT_TOPIC_AGV, rc);
    } else {
        printf("[MQTT] 已订阅: %s\r\n", MQTT_TOPIC_AGV);
    }
    rc = MQTTSubscribe(&mqttClient, MQTT_TOPIC_CMD, QOS0, OnCommandMessage);
    if (rc != 0) {
        printf("[MQTT] 订阅 %s 失败: %d\r\n", MQTT_TOPIC_CMD, rc);
    } else {
        printf("[MQTT] 已订阅: %s\r\n", MQTT_TOPIC_CMD);
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

    int rc = MQTTPublish(&mqttClient, topic, &msg);
    if (rc != 0) {
        printf("[MQTT] 发布失败: %d\r\n", rc);
        MQTT_CleanupDeadSession();
        return -1;
    }
    return 0;
}

static int Gateway_DataChanged(void)
{
    int currAgvFlame = (g_agvOnline && g_agvFlame) ? 1 : 0;
    int currAgvSmoke = (g_agvOnline && g_agvSmoke) ? 1 : 0;
    int currAgvGas = (g_agvOnline && g_agvGas) ? 1 : 0;
    int currTempX10 = (int)(g_gateTemp * 10.0f + (g_gateTemp >= 0 ? 0.5f : -0.5f));
    int currHumiX10 = (int)(g_gateHumi * 10.0f + (g_gateHumi >= 0 ? 0.5f : -0.5f));
    int currDf = g_agvOnline ? g_agvDistFront : -1;
    int currDb = g_agvOnline ? g_agvDistBack : -1;
    int currDl = g_agvOnline ? g_agvDistLeft : -1;
    int currDr = g_agvOnline ? g_agvDistRight : -1;

    if (!g_pubReady) {
        return 1;
    }
    if (g_pubAgvOnline != g_agvOnline || g_pubAgvFlame != currAgvFlame ||
        g_pubAgvSmoke != currAgvSmoke || g_pubAgvGas != currAgvGas) {
        return 1;
    }
    if (g_agvOnline) {
        if ((int)(g_pubAgvTemp * 10.0f + 0.5f) != (int)(g_agvTemp * 10.0f + 0.5f) ||
            (int)(g_pubAgvHumi * 10.0f + 0.5f) != (int)(g_agvHumi * 10.0f + 0.5f)) {
            return 1;
        }
        if (g_pubAgvDistFront != currDf || g_pubAgvDistBack != currDb ||
            g_pubAgvDistLeft != currDl || g_pubAgvDistRight != currDr) {
            int changed = 0;
            int cur[4] = { currDf, currDb, currDl, currDr };
            int pub[4] = { g_pubAgvDistFront, g_pubAgvDistBack,
                           g_pubAgvDistLeft, g_pubAgvDistRight };
            int k;
            for (k = 0; k < 4; k++) {
                int a = cur[k];
                int b = pub[k];
                int diff;
                if (a < 0 && b < 0) {
                    continue;
                }
                if (a < 0 || b < 0) {
                    continue;
                }
                diff = a - b;
                if (diff < 0) {
                    diff = -diff;
                }
                if (diff >= 3) {
                    changed = 1;
                    break;
                }
            }
            if (changed) {
                return 1;
            }
        }
    }
    if (currTempX10 != g_gatePubTempX10 || currHumiX10 != g_gatePubHumiX10) {
        return 1;
    }
    if (g_gateGasAdc != g_gatePubGasAdc) {
        int diff = g_gateGasAdc - g_gatePubGasAdc;
        if (diff < 0) {
            diff = -diff;
        }
        if (diff >= 30) {
            return 1;
        }
    }
    if (g_gateGasAlarm != g_gatePubGasAlarm || g_gateSmoke != g_gatePubSmoke ||
        g_gateFlameAlarm != g_gatePubFlameAlarm || g_gateLux != g_gatePubLux ||
        g_gatePir != g_gatePubPir || g_gateCargoCount != g_gatePubCargo) {
        return 1;
    }
    return 0;
}

static void Gateway_PublishIfChanged(int force)
{
    char mqttPayload[512];
    int currAgvFlame = (g_agvOnline && g_agvFlame) ? 1 : 0;
    int currAgvSmoke = (g_agvOnline && g_agvSmoke) ? 1 : 0;
    int currAgvGas = (g_agvOnline && g_agvGas) ? 1 : 0;
    int currDf = g_agvOnline ? g_agvDistFront : -1;
    int currDb = g_agvOnline ? g_agvDistBack : -1;
    int currDl = g_agvOnline ? g_agvDistLeft : -1;
    int currDr = g_agvOnline ? g_agvDistRight : -1;
    int currTempX10 = (int)(g_gateTemp * 10.0f + (g_gateTemp >= 0 ? 0.5f : -0.5f));
    int currHumiX10 = (int)(g_gateHumi * 10.0f + (g_gateHumi >= 0 ? 0.5f : -0.5f));
    int isHeartbeat = (force == 2);

    if (!g_mqttConnected) {
        return;
    }
    if (!force && !Gateway_DataChanged()) {
        return;
    }

    snprintf(mqttPayload, sizeof(mqttPayload),
             "{"
             "\"gateway_online\":true,"
             "\"gate_alarm_active\":%s,\"gate_alarm_type\":%d,"
             "\"gate_temperature\":%.1f,\"gate_humidity\":%.1f,"
             "\"gate_gas_adc\":%d,\"gate_gas_voltage\":%.3f,"
             "\"gate_smoke\":%s,\"gate_gas_alarm\":%s,\"gate_flame_alarm\":%s,"
             "\"gate_lux\":%d,\"gate_pir\":%s,\"gate_cargo_count\":%u,"
             "\"agv_online\":%s,\"agv_temperature\":%.1f,\"agv_humidity\":%.1f,"
             "\"agv_flame\":%s,\"agv_smoke\":%s,\"agv_gas\":%s,"
             "\"agv_dist_front\":%d,\"agv_dist_back\":%d,"
             "\"agv_dist_left\":%d,\"agv_dist_right\":%d"
             "}",
             (g_gateGasAlarm || g_gateSmoke || g_gateFlameAlarm || currAgvFlame || currAgvSmoke || currAgvGas) ? "true" : "false",
             (currAgvFlame ? 1 : 0) | (currAgvSmoke ? 2 : 0) | (currAgvGas ? 4 : 0) |
                 (g_gateGasAlarm ? 8 : 0) | (g_gateSmoke ? 16 : 0) | (g_gateFlameAlarm ? 32 : 0),
             g_gateTemp, g_gateHumi,
             g_gateGasAdc, g_gateVoltage,
             g_gateSmoke ? "true" : "false",
             g_gateGasAlarm ? "true" : "false",
             g_gateFlameAlarm ? "true" : "false",
             g_gateLux,
             g_gatePir ? "true" : "false",
             g_gateCargoCount,
             g_agvOnline ? "true" : "false",
             g_agvOnline ? g_agvTemp : 0.0f,
             g_agvOnline ? g_agvHumi : 0.0f,
             currAgvFlame ? "true" : "false",
             currAgvSmoke ? "true" : "false",
             currAgvGas ? "true" : "false",
             currDf, currDb, currDl, currDr);

    if (MQTT_Publish(MQTT_TOPIC, mqttPayload) == 0) {
        if (isHeartbeat) {
            printf("  [MQTT] 心跳汇总: %s\r\n", mqttPayload);
        } else {
            printf("  [MQTT] 变化立即汇总: %s\r\n", mqttPayload);
        }
        g_pubReady = 1;
        g_pubAgvTemp = g_agvTemp;
        g_pubAgvHumi = g_agvHumi;
        g_pubAgvFlame = currAgvFlame;
        g_pubAgvSmoke = currAgvSmoke;
        g_pubAgvGas = currAgvGas;
        g_pubAgvOnline = g_agvOnline;
        g_pubAgvDistFront = currDf;
        g_pubAgvDistBack = currDb;
        g_pubAgvDistLeft = currDl;
        g_pubAgvDistRight = currDr;
        g_gatePubTempX10 = currTempX10;
        g_gatePubHumiX10 = currHumiX10;
        g_gatePubGasAdc = g_gateGasAdc;
        g_gatePubGasAlarm = g_gateGasAlarm;
        g_gatePubSmoke = g_gateSmoke;
        g_gatePubFlameAlarm = g_gateFlameAlarm;
        g_gatePubLux = g_gateLux;
        g_gatePubPir = g_gatePir;
        g_gatePubCargo = g_gateCargoCount;
        g_agvNeedPublish = 0;
    }
}

static int MQTT_Reconnect(void)
{
    printf("[MQTT] 尝试重连...\r\n");
    MQTT_CleanupDeadSession();
    sleep(3);
    return MQTT_Connect();
}

static int MQTT_Maintain(void)
{
    if (!g_mqttConnected) {
        return -1;
    }
    int rc = MQTTYield(&mqttClient, 200);
    if (rc != 0) {
        printf("[MQTT] Yield失败: %d，连接可能已断开\r\n", rc);
        MQTT_CleanupDeadSession();
        return -1;
    }
    return 0;
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
        printf("  WiFi连接状态变化: state=%d\r\n", state);
    }
}

static void OnHotspotStaJoin(StationInfo *info) { (void)info; }
static void OnHotspotStaLeave(StationInfo *info) { (void)info; }
static void OnHotspotStateChanged(int state) { (void)state; }

static int WiFi_Connect(void)
{
    printf("[WiFi] 开始连接...\r\n");

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
        printf("[WiFi] 使能WiFi失败: %d\r\n", err);
        return -1;
    }
    printf("[WiFi] WiFi已使能\r\n");

    int timeout = 5;
    while (!IsWifiActive() && timeout > 0) {
        sleep(1);
        timeout--;
    }
    if (!IsWifiActive()) {
        printf("[WiFi] WiFi未激活\r\n");
        return -1;
    }
    printf("[WiFi] WiFi已激活\r\n");

    printf("[WiFi] 扫描网络...\r\n");
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
    printf("[WiFi] 发现%d个网络\r\n", g_ssidCount);

    unsigned int size = WIFI_SCAN_HOTSPOT_LIMIT;
    WifiScanInfo *scanInfo = malloc(sizeof(WifiScanInfo) * WIFI_SCAN_HOTSPOT_LIMIT);
    if (scanInfo == NULL) {
        printf("[WiFi] 内存分配失败\r\n");
        return -1;
    }
    GetScanInfoList(scanInfo, &size);

    for (int i = 0; i < g_ssidCount && i < 10; i++) {
        printf("  [%d] %s (rssi=%d)\r\n", i + 1, scanInfo[i].ssid, scanInfo[i].rssi);
    }

    int found = -1;
    for (int i = 0; i < g_ssidCount; i++) {
        if (strcmp(scanInfo[i].ssid, WIFI_SSID) == 0) {
            found = i;
            break;
        }
    }

    if (found < 0) {
        printf("[WiFi] 未找到 '%s'\r\n", WIFI_SSID);
        free(scanInfo);
        return -1;
    }

    printf("[WiFi] 找到 '%s'，正在连接...\r\n", WIFI_SSID);

    WifiDeviceConfig config = {0};
    strcpy_s(config.ssid, sizeof(config.ssid), WIFI_SSID);
    strcpy_s(config.preSharedKey, sizeof(config.preSharedKey), WIFI_PSK);
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
    if (err != WIFI_SUCCESS) {
        printf("[WiFi] 连接失败: %d\r\n", err);
        free(scanInfo);
        return -1;
    }

    timeout = WIFI_CONNECT_TIMEOUT;
    while (!g_wifiConnected && timeout > 0) {
        sleep(1);
        timeout--;
    }

    free(scanInfo);

    if (!g_wifiConnected) {
        printf("[WiFi] 连接超时\r\n");
        return -1;
    }

    printf("[WiFi] 连接成功!\r\n");

    struct netif *netif = netifapi_netif_find("wlan0");
    if (netif) {
        char hostname[] = WIFI_HOSTNAME;
        err_t hr = netifapi_set_hostname(netif, hostname, (u8_t)strlen(hostname));
        printf("[WiFi] hostname=%s ret=%d\r\n", hostname, hr);

        dhcp_start(netif);
        printf("[WiFi] DHCP启动中...\r\n");

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

    printf("[WiFi] 未找到wlan0网卡\r\n");
    return -1;
}

/* ---------- 外设引脚 ----------
 * PCF8574：P0火焰 P3白灯 P4绿灯 P5黄灯
 * 本板：光敏GPIO1 无源蜂鸣GPIO2(PWM2) PIR GPIO9
 *       计数GPIO8 烟雾DO GPIO0 红GPIO10 烟雾ADC GPIO11 蓝GPIO12
 *       I2C GPIO13/14（OLED/PCF）
 * DHT11：GPIO7
 * 注意：GPIO3/4=调试串口；GPIO8 勿接（会干扰串口/WLAN）
 */
#define BEEP_GPIO        2
#define BEEP_PWM_PORT    2
#define BEEP_PWM_FREQ    2700
#define BEEP_PWM_DUTY    50
#define LED_RED          10
#define LED_BLUE         12
#define LIGHT_GPIO       1     /* 光敏 DO，暗=高电平 */
#define DHT11_GPIO       7
#define PIR_GPIO         9
#define COUNT_GPIO       8     /* 光电计数 DO */
#define SMOKE_GPIO       0     /* 烟雾模块 DO，有烟=低电平（勿用 GPIO8） */
#define GAS_ADC_CH       HI_ADC_CHANNEL_5  /* MQ2 模拟量：GPIO11 */

#define LED_LEVEL_ON     1   /* 与拓展板白/绿/黄一致：高电平亮 */
#define LED_LEVEL_OFF    0

#define ADC_REF_VOLT     1.8f
#define ADC_COEFFICIENT  4
#define ADC_MAX_VAL      4096.0f
#define ALARM_THRESHOLD  1200
#define COUNT_DEBOUNCE_MS 30
#define ALARM_FLASH_MS   100

static volatile int g_countLastLevel = 1;
static int g_beepPwmReady = 0;

static void Beep_On(void)
{
    if (g_beepPwmReady) {
        (void)IoTPwmStart(BEEP_PWM_PORT, BEEP_PWM_DUTY, BEEP_PWM_FREQ);
    }
}

static void Beep_Off(void)
{
    if (g_beepPwmReady) {
        (void)IoTPwmStop(BEEP_PWM_PORT);
    }
}

static void Led_Set(int gpio, int on)
{
    IoTGpioSetOutputVal(gpio, on ? LED_LEVEL_ON : LED_LEVEL_OFF);
}

static void BoardLed_AllOff(void)
{
    Led_Set(LED_RED, 0);
    Led_Set(LED_BLUE, 0);
}

/* 拓展板灯：高电平亮（与本板红/蓝一致） */
static void ExtLed_Set(unsigned int pin, int on)
{
    Pcf8574SetPin(pin, on ? 1 : 0);
}

static void ExtLed_AllOff(void)
{
    Pcf8574UpdateBits((uint8_t)((1u << PCF_PIN_WHITE) |
                                (1u << PCF_PIN_GREEN) |
                                (1u << PCF_PIN_YELLOW)), 0);
}

/* 工厂状态灯：白灯=照明，绿/黄=无人/有人；报警时强制关绿灯 */
static void UpdateFactoryLights(int isDark, int hasPerson, int alarmActive)
{
    static int lastWhite = -1;
    static int lastGreen = -1;
    static int lastYellow = -1;
    uint8_t clearMask = (uint8_t)((1u << PCF_PIN_WHITE) |
                                  (1u << PCF_PIN_GREEN) |
                                  (1u << PCF_PIN_YELLOW));
    uint8_t setMask = 0;
    int whiteOn = g_gateLightManual ? g_gateLight : ((isDark && hasPerson) ? 1 : 0);
    int greenOn = (hasPerson == 0 && !alarmActive) ? 1 : 0;
    int yellowOn = (hasPerson == 1) ? 1 : 0;

    if (whiteOn == lastWhite && greenOn == lastGreen && yellowOn == lastYellow) {
        return;
    }
    if (whiteOn) setMask |= (uint8_t)(1u << PCF_PIN_WHITE);
    if (greenOn) setMask |= (uint8_t)(1u << PCF_PIN_GREEN);
    if (yellowOn) setMask |= (uint8_t)(1u << PCF_PIN_YELLOW);
    Pcf8574UpdateBits(clearMask, setMask);
    lastWhite = whiteOn;
    lastGreen = greenOn;
    lastYellow = yellowOn;
}

/* 烟雾/火焰/燃气报警：蜂鸣器 + 红/蓝灯快速交替闪烁 */
static void AlarmFlashTask(void *arg)
{
    (void)arg;
    int phase = 0;
    int wasAlarm = 0;
    while (1) {
        if (g_alarmFlashEnable) {
            wasAlarm = 1;
            Beep_On();
            if (phase == 0) {
                Led_Set(LED_RED, 1);
                Led_Set(LED_BLUE, 0);
            } else {
                Led_Set(LED_RED, 0);
                Led_Set(LED_BLUE, 1);
            }
            phase ^= 1;
            usleep(ALARM_FLASH_MS * 1000);
        } else {
            if (wasAlarm) {
                wasAlarm = 0;
                phase = 0;
                Beep_Off();
            }
            BoardLed_AllOff();
            usleep(50 * 1000);
        }
    }
}

static void AlarmFlash_Start(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "AlarmFlash";
    attr.stack_size = 1536;
    attr.priority = osPriorityAboveNormal;
    if (osThreadNew(AlarmFlashTask, NULL, &attr) == NULL) {
        printf("[ALARM] 闪烁任务创建失败\r\n");
    }
}

static void HwPeriphInit(void)
{
    /* 无源蜂鸣器：GPIO2 → PWM2，约 2.7kHz */
    IoTGpioInit(BEEP_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_2, HI_IO_FUNC_GPIO_2_PWM2_OUT);
    if (IoTPwmInit(BEEP_PWM_PORT) == IOT_SUCCESS) {
        g_beepPwmReady = 1;
        Beep_Off();
        printf("[BEEP] PWM2 on GPIO2 ok freq=%dHz\r\n", BEEP_PWM_FREQ);
    } else {
        g_beepPwmReady = 0;
        printf("[BEEP] PWM init fail\r\n");
    }

    /* PCF8574：火焰 + 白/绿/黄灯 */
    if (Pcf8574Init() != IOT_SUCCESS) {
        printf("[WARN] PCF8574 初始化失败，相关外设不可用\r\n");
    }
    /* 上电不执行逐灯自检，避免启动阶段反复改写 PCF8574 输出造成灯闪烁。 */
    ExtLed_AllOff();
    printf("  -> 拓展板灯初始化完成（跳过逐灯自检）\r\n");

    /* 红 GPIO10、蓝 GPIO12（报警用） */
    IoTGpioInit(LED_RED);
    hi_io_set_func(HI_IO_NAME_GPIO_10, HI_IO_FUNC_GPIO_10_GPIO);
    IoTGpioSetDir(LED_RED, IOT_GPIO_DIR_OUT);

    IoTGpioInit(LED_BLUE);
    hi_io_set_func(HI_IO_NAME_GPIO_12, HI_IO_FUNC_GPIO_12_GPIO);
    IoTGpioSetDir(LED_BLUE, IOT_GPIO_DIR_OUT);
    BoardLed_AllOff();

    /* 光照传感器 BH1750：I2C0 SDA=GPIO13 SCL=GPIO14 */
    IoTGpioInit(HI_IO_NAME_GPIO_13);
    hi_io_set_func(HI_IO_NAME_GPIO_13, HI_IO_FUNC_GPIO_13_I2C0_SDA);
    hi_io_set_pull(HI_IO_NAME_GPIO_13, HI_IO_PULL_UP);
    IoTGpioInit(HI_IO_NAME_GPIO_14);
    hi_io_set_func(HI_IO_NAME_GPIO_14, HI_IO_FUNC_GPIO_14_I2C0_SCL);
    hi_io_set_pull(HI_IO_NAME_GPIO_14, HI_IO_PULL_UP);
    IoTI2cInit(BH1750_I2C_IDX, BH1750_I2C_BAUD);
    {
        unsigned short addr = (unsigned short)((g_bh1750I2cAddr << 1) | 1);
        uint8_t probe = 0;
        if (IoTI2cRead(BH1750_I2C_IDX, addr, &probe, 1) != IOT_SUCCESS) {
            printf("[BH1750] probe failed addr=0x%02X, try 0x5C\r\n", g_bh1750I2cAddr);
            g_bh1750I2cAddr = 0x5C;
        }
    }

    IoTGpioInit(PIR_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_9, HI_IO_FUNC_GPIO_9_GPIO);
    IoTGpioSetDir(PIR_GPIO, IOT_GPIO_DIR_IN);

    /* 光电计数：GPIO8 */
    IoTGpioInit(COUNT_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_8, HI_IO_FUNC_GPIO_8_GPIO);
    IoTGpioSetDir(COUNT_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_8, HI_IO_PULL_UP);
    {
        IotGpioValue cv = IOT_GPIO_VALUE1;
        IoTGpioGetInputVal(COUNT_GPIO, &cv);
        g_countLastLevel = (cv == IOT_GPIO_VALUE0) ? 0 : 1;
    }

    /* 烟雾数字量：GPIO0，有烟=低（GPIO8 会干扰串口，勿用） */
    IoTGpioInit(SMOKE_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_0, HI_IO_FUNC_GPIO_0_GPIO);
    IoTGpioSetDir(SMOKE_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_0, HI_IO_PULL_UP);

    /* 烟雾模拟量 ADC：GPIO11 */
    hi_io_set_pull(HI_IO_NAME_GPIO_11, HI_IO_PULL_UP);

    /* DHT11 温湿度：GPIO7 */
    Dht11_Init();
}

static uint16_t MQ2_ReadADC(void)
{
    hi_u16 adcData = 0;
    hi_u32 ret = hi_adc_read(GAS_ADC_CH, &adcData, HI_ADC_EQU_MODEL_8, HI_ADC_CUR_BAIS_DEFAULT, 0xff);
    if (ret != HI_ERR_SUCCESS) {
        printf("Gas ADC read error:%d\r\n", ret);
        return 0;
    }
    return adcData;
}

/* 火焰：有火时 DO=1（本板与从节点相反）
 * 读成功才更新；失败保持上次，避免误报/卡死重试
 */
static int Flame_Detected(void)
{
    static int s_last = 0;
    int raw = Pcf8574TryGetPin(PCF_PIN_FLAME);
    if (raw < 0) {
        return s_last;
    }
    s_last = raw ? 1 : 0;
    return s_last;
}

static void Dht11_Init(void)
{
    IoTGpioInit(DHT11_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_7, HI_IO_FUNC_GPIO_7_GPIO);
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
}

static void Dht11_SetInput(void)
{
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_7, HI_IO_PULL_UP);
}

static void Dht11_SetOutput(void)
{
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
}

static int Dht11_ReadLevel(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    if (IoTGpioGetInputVal(DHT11_GPIO, &value) != HI_ERR_SUCCESS) {
        return -1;
    }
    return (value == IOT_GPIO_VALUE0) ? 0 : 1;
}

static int Dht11_WaitLevel(int level, unsigned int timeoutUs)
{
    while (timeoutUs > 0) {
        int cur = Dht11_ReadLevel();
        if (cur < 0) {
            return -1;
        }
        if (cur == level) {
            return 0;
        }
        hi_udelay(1);
        timeoutUs--;
    }
    return -1;
}

static int Dht11_Read(float *temperature, float *humidity)
{
    unsigned char data[5] = {0};
    hi_u64 tStart;
    unsigned int highUs;
    int i;

    if (temperature == NULL || humidity == NULL) {
        return -1;
    }

    Dht11_SetOutput();
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE0);
    hi_udelay(20000);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
    hi_udelay(30);
    Dht11_SetInput();

    if (Dht11_WaitLevel(0, 200) != 0) return -1;
    if (Dht11_WaitLevel(1, 200) != 0) return -1;
    if (Dht11_WaitLevel(0, 200) != 0) return -1;

    for (i = 0; i < 40; i++) {
        if (Dht11_WaitLevel(1, 200) != 0) return -1;
        tStart = hi_get_us();
        if (Dht11_WaitLevel(0, 200) != 0) return -1;
        highUs = (unsigned int)(hi_get_us() - tStart);
        data[i / 8] <<= 1;
        if (highUs > 40) {
            data[i / 8] |= 0x01;
        }
    }

    if (((data[0] + data[1] + data[2] + data[3]) & 0xFF) != data[4]) {
        return -1;
    }

    *humidity = (float)data[0] + (float)data[1] / 10.0f;
    *temperature = (float)data[2] + (float)data[3] / 10.0f;
    return 0;
}

static int Dht11_GetTempHumi(float *temp, float *humi)
{
    float temperature = 0.0f;
    float humidity = 0.0f;
    int retry;

    if (temp == NULL || humi == NULL) {
        return -1;
    }
    for (retry = 0; retry < 3; retry++) {
        if (Dht11_Read(&temperature, &humidity) == 0) {
            *temp = (float)temperature;
            *humi = (float)humidity;
            return 0;
        }
        hi_udelay(20000);
    }
    return -1;
}

static int BH1750_WriteCmd(uint8_t cmd)
{
    uint8_t buf = cmd;
    unsigned short waddr = (unsigned short)((g_bh1750I2cAddr << 1) | 0);
    return IoTI2cWrite(BH1750_I2C_IDX, waddr, &buf, 1);
}

static uint16_t BH1750_ReadLuxRaw(void)
{
    uint8_t data[2] = {0};
    uint16_t raw = 0;
    unsigned short waddr = (unsigned short)((g_bh1750I2cAddr << 1) | 0);
    unsigned short raddr = (unsigned short)((g_bh1750I2cAddr << 1) | 1);
    int ret;

    if (g_i2c0Mutex != NULL && osMutexAcquire(g_i2c0Mutex, 100) != osOK) {
        return 0;
    }
    uint8_t cmd = BH1750_POWER_ON;
    ret = IoTI2cWrite(BH1750_I2C_IDX, waddr, &cmd, 1);
    cmd = BH1750_RESET;
    if (ret == IOT_SUCCESS) ret = IoTI2cWrite(BH1750_I2C_IDX, waddr, &cmd, 1);
    cmd = BH1750_ONE_TIME_H_RES_MODE;
    if (ret == IOT_SUCCESS) ret = IoTI2cWrite(BH1750_I2C_IDX, waddr, &cmd, 1);
    if (g_i2c0Mutex != NULL) osMutexRelease(g_i2c0Mutex);
    if (ret != IOT_SUCCESS) return 0;

    osDelay(180);
    if (g_i2c0Mutex != NULL && osMutexAcquire(g_i2c0Mutex, 100) != osOK) {
        return 0;
    }
    ret = IoTI2cRead(BH1750_I2C_IDX, raddr, data, sizeof(data));
    if (g_i2c0Mutex != NULL) osMutexRelease(g_i2c0Mutex);
    if (ret != IOT_SUCCESS) {
        printf("[BH1750] read fail addr=0x%02X ret=%d\r\n", g_bh1750I2cAddr, ret);
        return 0;
    }
    raw = (uint16_t)((data[0] << 8) | data[1]);
    return raw;
}

static int BH1750_ReadLux(void)
{
    uint16_t raw = BH1750_ReadLuxRaw();
    if (raw == 0) {
        return 0;
    }
    return (int)(raw / 1.2f);
}

/* 人体红外：有人时 DO=1 */
static int Pir_Detected(void)
{
    IotGpioValue val = IOT_GPIO_VALUE0;
    IoTGpioGetInputVal(PIR_GPIO, &val);
    return (val == IOT_GPIO_VALUE1) ? 1 : 0;
}

/* 烟雾 DO：有烟时低电平（GPIO0） */
static int Smoke_Detected(void)
{
    IotGpioValue val = IOT_GPIO_VALUE1;
    IoTGpioGetInputVal(SMOKE_GPIO, &val);
    return (val == IOT_GPIO_VALUE0) ? 1 : 0;
}

/* 光电计数：GPIO6，低→高边沿 +1 */
static void CargoCountTask(void *arg)
{
    (void)arg;
    while (1) {
        IotGpioValue val = IOT_GPIO_VALUE1;
        int level;

        IoTGpioGetInputVal(COUNT_GPIO, &val);
        level = (val == IOT_GPIO_VALUE0) ? 0 : 1;

        if (g_countLastLevel == 0 && level == 1) {
            g_gateCargoCount++;
            usleep(COUNT_DEBOUNCE_MS * 1000);
            IoTGpioGetInputVal(COUNT_GPIO, &val);
            g_countLastLevel = (val == IOT_GPIO_VALUE0) ? 0 : 1;
        } else {
            g_countLastLevel = level;
        }
        usleep(20 * 1000);
    }
}

static void CargoCount_Start(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "CargoCount";
    attr.stack_size = 2048;
    attr.priority = osPriorityNormal;
    if (osThreadNew(CargoCountTask, NULL, &attr) == NULL) {
        printf("[COUNT] 任务创建失败\r\n");
    }
}

static void GatewayAppTask(void *arg)
{
    (void)arg;
    int count = 0;
    char buf[32];
    float temp = 0, humi = 0;

    printf("\r\n\r\n============================\r\n");
    printf("  Plant Gateway (中控汇总)\r\n");
    printf("  hostname: %s\r\n", WIFI_HOSTNAME);
    printf("============================\r\n\r\n");

    printf("[1] 初始化I2C互斥锁...\r\n");
    g_i2c0Mutex = osMutexNew(NULL);
    if (g_i2c0Mutex != NULL) {
        OledSetI2cMutex(g_i2c0Mutex);
        Pcf8574SetI2cMutex(g_i2c0Mutex);
    } else {
        printf("[WARN] I2C mutex create failed\r\n");
    }

    printf("[2] 初始化外设...\r\n");
    HwPeriphInit();
    printf("  SmokeDO=GPIO0 Light=GPIO1 Beep=GPIO2 Count=GPIO8 PIR=GPIO9 DHT11=GPIO7\r\n");
    printf("  Red=GPIO10 GasADC=GPIO11 Blue=GPIO12 I2C=GPIO13/14\r\n");
    printf("  PCF: P0=Flame P3=White P4=Green P5=Yellow (GPIO8 unused)\r\n");

    printf("  -> 无源蜂鸣器PWM+红灯自检...\r\n");
    Beep_On();
    Led_Set(LED_RED, 1);
    sleep(1);
    Beep_Off();
    BoardLed_AllOff();
    printf("  -> OK\r\n\r\n");

    CargoCount_Start();
    printf("  -> 光电计数已启动(GPIO6)\r\n\r\n");
    AlarmFlash_Start();
    printf("  -> 报警闪烁任务已启动\r\n\r\n");

    printf("[2] 初始化OLED(I2C0: SDA=GPIO13, SCL=GPIO14)...\r\n");
    uint32_t ret = OledInit();
    printf("  -> OLED ret=%d\r\n\r\n", ret);

    OledFillScreen(0x00);
    OledShowString(0, 0, "Gas Sensor", FONT8x16);
    OledShowString(0, 2, "Starting...", FONT8x16);

    printf("[3] 初始化DHT11...\r\n");
    int dht11Ok = 0;
    if (Dht11_GetTempHumi(&temp, &humi) == 0) {
        dht11Ok = 1;
        printf("  -> DHT11 OK! T=%.2fC H=%.2f%%\r\n\r\n", temp, humi);
    } else {
        printf("  -> DHT11读取失败，将跳过温湿度显示\r\n\r\n");
    }

    printf("  -> 拓展板按钮任务已启动\r\n\r\n");

    printf("[4] 连接WiFi...\r\n");
    WiFi_Connect();

    printf("[5] 连接MQTT...\r\n");
    MQTT_InitClientId();
    if (MQTT_Connect() != 0) {
        g_mqttReconnectAt = MQTT_RECONNECT_INTERVAL;
    }

    printf("[6] 预热2秒...\r\n");
    sleep(2);

    printf("[7] 进入主循环\r\n\r\n");
    OledFillScreen(0x00);

    while (1) {
        count++;

        /* 先收 AGV 报文，再判报警，使从节点火焰能立即联动本板报警 */
        if (g_mqttConnected) {
            if (MQTT_Maintain() != 0) {
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
                printf("[MQTT] 连接断开，将在约%d秒后重连\r\n", MQTT_RECONNECT_INTERVAL);
            }
        }
        MQTT_RefreshAgvStatus(count);

        uint16_t gasAdc = MQ2_ReadADC();
        float voltage = gasAdc * ADC_REF_VOLT * ADC_COEFFICIENT / ADC_MAX_VAL;
        int smokeDo = Smoke_Detected();
        /* 上电前几秒烟雾模块 DO 常不稳定，避免误报一直响 */
        int gasAlarm = (gasAdc > ALARM_THRESHOLD) ? 1 : 0;
        if (count > 5 && smokeDo) {
            gasAlarm = 1;
        }
        int localFlame = Flame_Detected();
        int agvFlame = (g_agvOnline && g_agvFlame) ? 1 : 0;
        int agvSmoke = (g_agvOnline && g_agvSmoke) ? 1 : 0;
        int agvGas = (g_agvOnline && g_agvGas) ? 1 : 0;
        /* 本地/从节点 任一火焰、烟雾、燃气都进入同一报警模式 */
        int flameAlarm = (localFlame || agvFlame) ? 1 : 0;
        int autoAlarm = (gasAlarm || flameAlarm || agvSmoke || agvGas) ? 1 : 0;
        int hazardAlarm = (autoAlarm || g_manualAlarm) ? 1 : 0;
        if (!autoAlarm) {
            g_autoAlarmMuted = 0;
            g_gateBuzzerMute = 0;
        }
        int lux = BH1750_ReadLux();
        int isDark = (lux > 0 && lux < 80) ? 1 : 0;
        int hasPerson = Pir_Detected();
        static int lastPersonForLights = -1;
        static int personStableTicks = 0;
        if (lastPersonForLights < 0) {
            lastPersonForLights = hasPerson;
        } else if (hasPerson != lastPersonForLights) {
            personStableTicks++;
            if (personStableTicks >= 1) {
                lastPersonForLights = hasPerson;
                personStableTicks = 0;
            } else {
                hasPerson = lastPersonForLights;
            }
        } else {
            personStableTicks = 0;
        }
        g_autoWhiteLight = (isDark && hasPerson) ? 1 : 0;

        if (dht11Ok && (count % 100 == 0)) {
            float newTemp, newHumi;
            if (Dht11_GetTempHumi(&newTemp, &newHumi) == 0) {
                temp = newTemp;
                humi = newHumi;
            }
        }

        g_gateTemp = temp;
        g_gateHumi = humi;
        g_gateGasAdc = (int)gasAdc;
        g_gateVoltage = voltage;
        g_gateSmoke = smokeDo;
        g_gateGasAlarm = gasAlarm;
        g_gateFlameAlarm = flameAlarm;
        g_gateLux = lux;
        g_gatePir = hasPerson;

        static unsigned int lastCargo = 0;
        if (g_gateCargoCount != lastCargo) {
            printf("  [COUNT] 货物合计=%u\r\n", g_gateCargoCount);
            lastCargo = g_gateCargoCount;
        }

        printf("[%d] T=%.2fC H=%.1f%% Gas=%d Smoke=%d LocalF=%d AgvF=%d Lux=%d Dark=%d PIR=%d Cargo=%u\r\n",
               count, temp, humi, gasAdc, smokeDo, localFlame, agvFlame,
               lux, isDark, hasPerson, g_gateCargoCount);

        snprintf(buf, sizeof(buf), "T:%.1fC H:%.1f%%", temp, humi);
        static char lastOled0[24] = {0};
        if (strcmp(lastOled0, buf) != 0) {
            OledShowString(0, 0, buf, FONT8x16);
            strncpy(lastOled0, buf, sizeof(lastOled0) - 1);
        }

        /* G=ADC  S=烟雾DO  F=本板火焰 */
        snprintf(buf, sizeof(buf), "G:%4d S:%d F:%d", gasAdc, smokeDo, localFlame);
        static char lastOled2[24] = {0};
        if (strcmp(lastOled2, buf) != 0) {
            OledShowString(0, 2, buf, FONT8x16);
            strncpy(lastOled2, buf, sizeof(lastOled2) - 1);
        }

        snprintf(buf, sizeof(buf), "L:%4d P:%d C:%u", lux, hasPerson, g_gateCargoCount);
        static char lastOled4[24] = {0};
        if (strcmp(lastOled4, buf) != 0) {
            OledShowString(0, 4, buf, FONT8x16);
            strncpy(lastOled4, buf, sizeof(lastOled4) - 1);
        }

        /* 报警优先：烟雾(ADC或DO)或火焰 → 蜂鸣器 + 红蓝灯快速闪烁 */
        if (hazardAlarm) {
            g_alarmFlashEnable = g_gateBuzzerMute ? 0 : 1;
            UpdateFactoryLights(isDark, hasPerson, 1);
            if (agvSmoke && agvGas) {
                OledShowString(0, 6, "AGV SM+GAS", FONT8x16);
            } else if (agvSmoke) {
                OledShowString(0, 6, "AGV SMOKE!", FONT8x16);
            } else if (agvGas) {
                OledShowString(0, 6, "AGV GAS!  ", FONT8x16);
            } else if (gasAlarm && flameAlarm) {
                OledShowString(0, 6, "GAS+FLAME!", FONT8x16);
            } else if (flameAlarm) {
                if (agvFlame && !localFlame) {
                    OledShowString(0, 6, "AGV FLAME!", FONT8x16);
                } else {
                    OledShowString(0, 6, "FLAME!    ", FONT8x16);
                }
            } else {
                OledShowString(0, 6, "GAS ALARM!", FONT8x16);
            }
            printf("  *** ALARM gasAdc=%d smokeDo=%d localFlame=%d agvFlame=%d agvSmoke=%d agvGas=%d ***\r\n",
                   gasAdc, smokeDo, localFlame, agvFlame, agvSmoke, agvGas);
        } else {
            g_alarmFlashEnable = 0;
            g_gateBuzzerMute = 0;
            UpdateFactoryLights(isDark, hasPerson, 0);
            if (isDark == 1 && hasPerson == 1) {
                OledShowString(0, 6, "W+Y LIGHT ", FONT8x16);
            } else if (isDark == 1 && hasPerson == 0) {
                OledShowString(0, 6, "GREEN     ", FONT8x16);
            } else if (isDark == 0 && hasPerson == 1) {
                OledShowString(0, 6, "YELLOW    ", FONT8x16);
            } else {
                OledShowString(0, 6, "GREEN     ", FONT8x16);
            }
        }

        if (g_gateAgvEStop) {
            g_agvNeedPublish = 0;
        }

        if (g_gateNeedReboot) {
            g_gateNeedReboot = 0;
            Gateway_DoReboot();
        }
        if (g_rebootPending) {
            g_rebootPending = 0;
            Gateway_StartSafeReboot();
        }

        if (count % 10 == 0) {
            WifiLinkedInfo linkedInfo;
            WifiErrorCode werr = GetLinkedInfo(&linkedInfo);
            if (werr != WIFI_SUCCESS || !g_wifiConnected) {
                printf("[WiFi] 连接已断开(werr=%d, connected=%d)，尝试重连...\r\n", werr, g_wifiConnected);
                g_wifiConnected = 0;
                MQTT_CleanupDeadSession();
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
                if (g_wifiNetId >= 0) {
                    werr = ConnectTo(g_wifiNetId);
                    if (werr == WIFI_SUCCESS) {
                        int retry = 10;
                        while (!g_wifiConnected && retry > 0) {
                            sleep(1);
                            retry--;
                        }
                        if (g_wifiConnected) {
                            printf("[WiFi] 重连成功!\r\n");
                        } else {
                            printf("[WiFi] 重连超时\r\n");
                        }
                    } else {
                        printf("[WiFi] ConnectTo失败: %d\r\n", werr);
                    }
                }
            }
        }

        if (!g_mqttConnected && count >= g_mqttReconnectAt) {
            printf("[MQTT] 连接已断开，尝试重连...\r\n");
            if (MQTT_Reconnect() != 0) {
                g_mqttReconnectAt = count + MQTT_RECONNECT_INTERVAL;
            }
        }

        /* AGV 离线/本地变化立即汇总；约每 5 秒心跳 */
        if (g_agvNeedPublish) {
            Gateway_PublishIfChanged(1);
        } else if (count % 5 == 0) {
            Gateway_PublishIfChanged(2);
        } else {
            Gateway_PublishIfChanged(0);
        }
        g_agvNeedPublish = 0;

        osDelay(50);
    }
}

static void PlantGatewayEntry(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "GatewayTask";
    attr.stack_size = 8192;
    attr.priority = osPriorityNormal;
    if (osThreadNew(GatewayAppTask, NULL, &attr) == NULL) {
        printf("[PlantGateway] Task create failed!\r\n");
    }
}
APP_FEATURE_INIT(PlantGatewayEntry);
