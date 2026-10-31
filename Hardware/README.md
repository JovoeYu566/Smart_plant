# Hardware —— OpenHarmony 设备端（Hi3861）

本目录是智慧工厂项目的**设备端应用层代码**，运行在 Hi3861V100上，基于 **OpenHarmony 4.1 Release（`ohos:mini` 轻量系统）**，用 C + CMSIS-RTOS2 编写，通过 MQTT/TLS 与后端交换工况与控制指令。

> 仓库只收录**当前在用的两个节点**：主节点 `plant_gateway` 与从节点 `agv_servo_node`；早期版本的 `agv_node` 已作废，不在仓库中维护。OpenHarmony 源码树本身（数 GB）不在仓库内，编译时需要把本目录挂回去。

## 目录结构

```
Hardware/
└── app/                        # 对应 OH 源码树里的 applications/sample/wifi-iot/app
    ├── BUILD.gn                # 组件入口：用哪个应用参与编译在这里放开/注释
    ├── plant_gateway/          # 主节点（中控汇总网关）
    └── agv_servo_node/         # 从节点 AGV（移动监测/电机/舵机驱动 + 避障）
```

| 目录 | 角色 | 主要功能 |
|---|---|---|
| `plant_gateway` | 主节点 | 采集 DHT11 / MQ2 / 烟雾 DO / BH1750 光照 / PIR / 光电计数；汇总从节点数据后**一帧 JSON 上报后端**；订阅控制指令，驱动 PCF8574 拓展板灯、蜂鸣器、软复位 |
| `agv_servo_node` | 从节点 | 底盘电机 PWM 差速驱动、舵机转向、超声波避障、DHT11、PCF8574 火焰/气体/烟雾；周期上报 AGV 状态 |

每个节点目录自带 `BUILD.gn`（组件定义）与 `mqtt_tls.c`（mbedTLS 封装），可直接放回源码树编译。

## 编译步骤

### 1. 准备 OpenHarmony 源码

```bash
repo init -u https://gitee.com/openharmony/manifest -b refs/tags/OpenHarmony-v4.1-Release -g ohos:mini
repo sync -c
```

### 2. 把本目录挂回源码树

```bash
cp -r Hardware/app/* <OH_ROOT>/applications/sample/wifi-iot/app/
```

### 3. 选择要编译的节点

编辑 `app/BUILD.gn`，`features` 里**只保留一个**（Hi3861 的 `lite_component("app")` 是单入口，同时开多个会互相抢占初始化流程）：

```gn
lite_component("app") {
  features = [
    "plant_gateway:plant_gateway",     # 主节点
    # "agv_servo_node:agv_servo_node", # 从节点
  ]
}
```

> 仓库里的 `BUILD.gn` 保持原样（当前激活的是 `led_interrupt_board` 例程，该例程未收录），编译前请按上面的写法改成你要烧的节点。

### 4. 编译

```bash
cd <OH_ROOT>
./build.sh --product-name wifiiot_hispark_pegasus --ccache --no-prebuilt-sdk
```

产物：

```
out/hispark_pegasus/wifiiot_hispark_pegasus/Hi3861_wifiiot_app_allinone.bin
```

### 5. 烧录

用 DevEco Device Tool 或 HiBurn 打开上面的 `allinone.bin`，选 Hi3861 串口（921600 或 115200）烧录后复位。

## 现场配置（WiFi / MQTT）

代码中的网络参数是**直接硬编码**在源文件顶部的宏里，换现场时改这几行即可：

| 文件 | 宏 |
|---|---|
| `app/plant_gateway/gateway_main.c` | `WIFI_SSID`、`WIFI_PSK`、`MQTT_BROKER_IP`、`MQTT_BROKER_PORT`、`MQTT_USERNAME`、`MQTT_PASSWORD` |
| `app/agv_servo_node/agv_servo_main.c` | `AGV_WIFI_SSID`、`AGV_WIFI_PSK`、`MQTT_BROKER_IP`、`MQTT_BROKER_PORT`、`MQTT_USERNAME`、`MQTT_PASSWORD` |


## 引脚与外设

### 主节点 `plant_gateway`

| 外设 | 引脚 | 备注 |
|---|---|---|
| 光敏 DO | GPIO1 | 暗 = 高电平 |
| 无源蜂鸣器 | GPIO2 → PWM2 | 约 2.7 kHz |
| DHT11 | GPIO7 | 温湿度 |
| 光电计数 DO | GPIO8 | 上升沿计数（勿接其它模块，会干扰串口/WLAN） |
| PIR | GPIO9 | 有人 = 高电平 |
| 红灯 | GPIO10 | 报警闪烁 |
| 烟雾 DO | GPIO0 | 有烟 = 低电平 |
| MQ2 模拟量 | GPIO11 / ADC5 | 电压换算见 `ADC_REF_VOLT * ADC_COEFFICIENT` |
| 蓝灯 | GPIO12 | 报警闪烁 |
| I2C0 | SDA=GPIO13 / SCL=GPIO14 | OLED SSD1306、PCF8574、BH1750（地址 0x23，自动回退 0x5C） |
| PCF8574 | P0 火焰 / P3 白灯 / P4 绿灯 / P5 黄灯 | 拓展板 |

> GPIO3 / GPIO4 是调试串口，不要占用。

### 从节点 `agv_servo_node`

| 外设 | 引脚 |
|---|---|
| 超声波 TRIG / ECHO | GPIO11 / GPIO7 |
| 电机 IN1 / IN2 / IN3 / IN4 | GPIO1 / GPIO0 / GPIO2 / GPIO10 |
| DHT11 | GPIO8 |
| PCF8574 | P1 火焰 / P2 气体 / P3 烟雾 |
| I2C0 | SDA=GPIO13 / SCL=GPIO14（OLED） |

## MQTT 主题

| 方向 | 主题 | 发布者 | 订阅者 |
|---|---|---|---|
| 上行（AGV → 网关） | `sensor/agv/data` | `agv_servo_node` | 主节点 |
| 上行（网关 → 后端） | `gas/sensor/data` | 主节点 | 后端 `MqttClientManager` |
| 下行（后端 → 设备） | `plant/gateway/command` | 后端 | 主节点 / 从节点 |

主节点上报报文（后端同时兼容 `gate_*` 与旧版字段名）：

```json
{
  "gateway_online": true, "gate_alarm_active": false, "gate_alarm_type": 0,
  "gate_temperature": 28.5, "gate_humidity": 61.0,
  "gate_gas_adc": 146, "gate_gas_voltage": 0.257,
  "gate_smoke": false, "gate_gas_alarm": false, "gate_flame_alarm": false,
  "gate_lux": 320, "gate_pir": false, "gate_cargo_count": 3,
  "agv_online": true, "agv_temperature": 27.8, "agv_humidity": 58.0,
  "agv_flame": false, "agv_smoke": false, "agv_gas": false,
  "agv_dist_front": 213, "agv_dist_back": 49,
  "agv_dist_left": 37, "agv_dist_right": 62
}
```

## 与后端联调注意点

- **AGV 离线判定**：主节点用 `AGV_DATA_STALE_SEC = 10` 秒判定从节点掉线，后端 `online-timeout-ms = 60000` 独立判定，两边各自置离线。
- **本地告警阈值不同**：主节点 `ALARM_THRESHOLD = 1200`（ADC 原始值，触发本板蜂鸣与灯闪），后端默认 `gas-adc-threshold = 200`。前端展示以后端裁定结果为准，设备端只负责现场声光。
- **TLS**：EMQX Serverless 走 8883 端口，`mqtt_tls.c` 用 mbedTLS 做加密，但当前为 `MBEDTLS_SSL_VERIFY_NONE`（只加密、不校验服务端证书），正式部署建议加载 CA 并开启校验。
- **I2C 地址**：OLED 在 `oled_ssd1306.c` 里写死 `OLED_I2C_ADDR 0x78`（即 7 位地址 0x3C），换屏时注意修改。
- **指令动作**：设备端支持 `LIGHT_ON/OFF/TOGGLE/AUTO`、`ALARM_ACK/MUTE/UNMUTE`、`BUZZER_ON/OFF`、`AGV_ESTOP/RESUME/GOTO`、`CARGO_RESET`、`GATEWAY_REBOOT/STATUS_QUERY`、`SENSOR_CALIBRATE`、`DATA_SNAPSHOT_FORCE`、`MAINTENANCE_MODE_ON/OFF`；其中 `LIGHT_AUTO` 仅设备端支持，后端白名单未收录。

## 常见问题

| 现象 | 处理 |
|---|---|
| 编译报 `gn` 找不到组件 | `app/BUILD.gn` 里的名字要和目录名一致，且只开一个 |
| 串口一直打印 WiFi 扫描 | 热点名写错，或热点为 5 GHz（Hi3861 仅支持 2.4 GHz） |
| 连上 WiFi 但 MQTT 失败 | 检查 `MQTT_BROKER_IP` / 账号密码；确认 EMQX 实例未过期 |
| OLED 不亮 | 确认 GPIO13/14 未被复用，且 `OLED_I2C_ADDR`（0x78）与屏幕一致 |
| 烧录后无输出 | 波特率改成 115200 再看串口日志 |
