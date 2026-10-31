# 鸿安智联——基于开源鸿蒙的工业厂区多维度安全感知与联动管控系统

面向中小工厂安全值班场景的 **端 — 边 — 云** 协同系统：主/从节点采集多源工况，EMQX 以 MQTT/TLS 承载上行工况与下行控制，Spring Boot 完成入库、告警裁定、鉴权与审计，OpenHarmony 单工程同时交付 **手机巡检端** 与 **平板监控大屏**。

> 仓库只包含 `Back_end`（后端）与 `Front_end`（鸿蒙前端）两部分源代码。

---

## 目录

- [功能特性](#功能特性)
- [系统架构](#系统架构)
- [技术栈](#技术栈)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [API 一览](#api-一览)
- [MQTT 主题与报文](#mqtt-主题与报文)
- [告警规则与控制指令](#告警规则与控制指令)
- [安全设计](#安全设计)
- [常见问题](#常见问题)

---

## 功能特性

**后端 `Back_end`**

- 订阅 EMQX 主题（默认 `gas/sensor/data`），解析全厂工况 JSON 并**双轨入库**：最新值立即覆盖、历史快照节流写入
- 主节点 HTTP 兜底上报：`POST /api/plant/report`（Header `X-Gateway-Key`）
- 告警生命周期管理：火焰 / 气体越限 / 近距碰撞 / AGV 离线 / 网关离线，条件消失自动写恢复时间
- 远程控制：指令经 MQTT 发布到 `plant/gateway/command`，白名单校验 + 全量审计日志
- JWT 登录鉴权、BCrypt 口令、网关密钥过滤、统一异常响应

**前端 `Front_end`**

- 纯血鸿蒙 ArkTS 单工程，按窗口宽度 **840vp 断点** 自动切换两套壳：平板数据大屏 / 手机业务端
- 平板：系统总览、数据监控、控制台；手机：首页、告警、历史、控制台、我的
- 约 2 秒轮询最新工况与未恢复告警，断流时强制显示离线占位 `--`
- Token 与服务器地址本地 Preferences 持久化，危险操作二次确认
- 支持 `phone` / `tablet` / `2in1` 设备类型

## 系统架构

```
┌──────────────────────── 感知与执行层 ────────────────────────┐
│  火焰 / 可燃气体 / 温湿度 / PIR / 光照 / 超声波测距 / 光电计数  │
│  主节点汇聚上报            从节点（AGV）四向避障与急停执行      │
└───────────────────────────────┬──────────────────────────────┘
                                │ MQTT / TLS  或  HTTP 兜底
┌───────────────────────────────▼──────────────────────────────┐
│                      消息层  EMQX                             │
│   上行 gas/sensor/data          下行 plant/gateway/command     │
└───────────────────────────────┬──────────────────────────────┘
                                │ 订阅 / 发布
┌───────────────────────────────▼──────────────────────────────┐
│                   业务中枢层  Spring Boot 3                   │
│  报文归一 → 双轨入库 → 在线判定 → 告警引擎 → 控制鉴权 → 审计   │
└───────────────────────────────┬──────────────────────────────┘
                                │ MySQL 8
┌───────────────────────────────▼──────────────────────────────┐
│  sys_user · device_latest · plant_snapshot                    │
│  alarm_event · control_command_log                            │
└───────────────────────────────┬──────────────────────────────┘
                                │ REST / JWT
┌───────────────────────────────▼──────────────────────────────┐
│                 应用层  OpenHarmony ArkTS                     │
│        手机巡检端（< 840vp）   /   平板监控大屏（≥ 840vp）      │
└──────────────────────────────────────────────────────────────┘
```

## 技术栈

| 层 | 技术 |
|---|---|
| 后端框架 | Spring Boot 3.3.5、Spring Security、Spring Validation |
| 持久化 | MySQL 8、MyBatis-Plus 3.5.9 |
| 消息 | Eclipse Paho MQTT 1.2.5、EMQX（TLS 8883） |
| 鉴权 | JJWT 0.12.6、BCrypt |
| 前端 | OpenHarmony ArkTS（API 12+）、DevEco Studio |
| 运行时 | **JDK 17**（`pom.xml` 已用 enforcer 锁定，非 17 直接构建失败） |

## 目录结构

```
.
├── Back_end/                         # Spring Boot 后端
│   ├── pom.xml
│   ├── run-jdk17.ps1                 # 一键用 JDK17 干净编译并启动
│   └── src/main/
│       ├── java/com/smartplant/
│       │   ├── common/               # 统一响应、全局异常
│       │   ├── config/               # Security / MyBatis-Plus / 属性绑定 / 初始化
│       │   ├── controller/           # REST 接口
│       │   ├── domain/entity/        # 实体
│       │   ├── dto/                  # 请求响应与工况报文
│       │   ├── mapper/               # MyBatis-Plus Mapper
│       │   ├── mqtt/                 # EMQX 连接与报文解析
│       │   ├── security/             # JWT 过滤器、网关密钥过滤器
│       │   └── service/              # 入库、告警、控制、在线看门狗
│       └── resources/
│           ├── application.yml           # 仅环境变量占位，无真实密钥
│           ├── application-local.yml.example
│           └── schema*.sql               # 建表与增量脚本
└── Front_end/                        # OpenHarmony 前端
    ├── AppScope/
    └── entry/src/main/
        ├── ets/
        │   ├── common/               # 配置、主题、会话、显示映射
        │   ├── components/           # 平板面板、共用控制台
        │   ├── pages/                # Index / Login / phone / tablet
        │   ├── service/              # HttpClient、PlantApi、ControlApi、告警服务
        │   ├── store/                # AppStore、PrefStore
        │   └── model/                # 数据模型
        └── resources/                # 字符串、颜色、图标、页面配置
```

## 快速开始

### 1. 环境要求

- JDK 17（不要用 21/24 编译后再用 17 运行，会出现 `class file version 65.0` 错误）
- Maven 3.6.1+
- MySQL 8
- DevEco Studio（运行前端）

### 2. 建库

```bash
mysql -u root -p < Back_end/src/main/resources/schema.sql
```

`schema.sql` 已包含控制审计表；老库可单独执行 `schema_control.sql` / `schema_alter_master_slave.sql` 增量。

### 3. 后端配置

仓库中的 `application.yml` **只保留环境变量占位**，不含任何真实密钥。启动前二选一：

**方式 A：本地配置文件（推荐开发用）**

```bash
cd Back_end/src/main/resources
cp application-local.yml.example application-local.yml
# 填入本机 MySQL、EMQX、JWT 等真实值（该文件已被 .gitignore 忽略）
```

**方式 B：环境变量（推荐部署用）**

```bash
DB_URL / DB_USERNAME / DB_PASSWORD
JWT_SECRET / GATEWAY_API_KEY
MQTT_BROKER / MQTT_PORT / MQTT_USERNAME / MQTT_PASSWORD / MQTT_CLIENT_ID
```

> 使用方式 A 时必须激活 `local` profile，否则读到的是占位值。

### 4. 启动后端

```powershell
cd Back_end
.\run-jdk17.ps1          # 自动设置 JAVA_HOME=17 并 clean 启动
```

或手动：

```bash
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

IDEA 直接运行 `SmartPlantApplication` 即可（运行配置已设置 `ACTIVE_PROFILES=local`）。

启动后自动创建管理员账号：**`admin` / `admin123`**。

健康检查：

```bash
curl http://127.0.0.1:8080/api/health
```

### 5. 运行前端

1. 用 DevEco Studio 打开 `Front_end` 目录
2. 修改后端地址（默认是外网穿透地址）：

```ts
// Front_end/entry/src/main/ets/common/AppConfig.ets
static readonly DEFAULT_BASE_URL: string = 'http://你的电脑局域网IP:8080'
```

3. 选择 Phone / Tablet 模拟器或真机运行；拉宽窗口即可切到平板大屏布局

## API 一览

统一响应格式：`{ "code": 0, "msg": "ok", "data": ... }`

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| GET | `/api/health` | 无 | 健康检查 |
| POST | `/api/auth/login` | 无 | 登录，返回 JWT |
| GET | `/api/plant/latest` | Bearer | 最新全厂工况 |
| GET | `/api/plant/history?page=1&size=20&from=&to=` | Bearer | 历史快照分页 |
| GET | `/api/alarms?activeOnly=true&limit=50` | Bearer | 告警列表 |
| POST | `/api/plant/report` | `X-Gateway-Key` 或 Bearer | 主节点汇总上报 |
| POST | `/api/control/command` | Bearer | 远程控制下发（走 MQTT） |
| GET | `/api/control/history?limit=30` | Bearer | 控制指令审计 |

登录示例：

```bash
curl -X POST http://127.0.0.1:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

控制示例：

```bash
curl -X POST http://127.0.0.1:8080/api/control/command \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"action":"LIGHT_ON","params":{}}'
```

## MQTT 主题与报文

| 方向 | 主题 | 说明 |
|---|---|---|
| 上行 | `gas/sensor/data` | 设备工况 JSON，后端订阅后入库并评估告警 |
| 下行 | `plant/gateway/command` | 控制指令，主节点订阅并执行 |

上行报文示例（字段缺省即忽略，兼容 `gate_*` 旧字段）：

```json
{
  "agv_temperature": 28.3, "agv_humidity": 60.0, "agv_flame": false, "agv_online": true,
  "agv_dist_front": 213, "agv_dist_back": 49, "agv_dist_left": 37, "agv_dist_right": 62,
  "gas_temperature": 35.0, "gas_humidity": 40.8, "gas_adc": 146, "gas_voltage": 0.257,
  "alarm": false, "flame_alarm": false, "dark": false, "pir": false, "cargo_count": 0
}
```

下行指令示例：

```json
{
  "action": "LIGHT_ON",
  "params": {},
  "requestId": "abc123",
  "ts": 1710000000000,
  "operator": "admin"
}
```

## 告警规则与控制指令

**告警阈值（`application.yml` 可调）**

```yaml
smart-plant:
  alarm:
    gas-adc-threshold: 200      # 气体 ADC 越限
    gas-voltage-threshold: 0.5  # 气体电压越限
    min-distance-cm: 20         # 四向测距小于该值判定碰撞
  ingest:
    snapshot-interval-ms: 3000  # 历史快照节流
    alarm-interval-ms: 300      # 常规告警节流
    online-timeout-ms: 60000    # 超时未上报判定离线
```

**控制指令白名单**（后端硬校验，不在表内直接拒绝）

```
LIGHT_ON / LIGHT_OFF / LIGHT_TOGGLE
ALARM_ACK / ALARM_MUTE / ALARM_UNMUTE
BUZZER_ON / BUZZER_OFF
AGV_ESTOP / AGV_RESUME / AGV_GOTO
CARGO_RESET
GATEWAY_REBOOT / GATEWAY_STATUS_QUERY
SENSOR_CALIBRATE / DATA_SNAPSHOT_FORCE
MAINTENANCE_MODE_ON / MAINTENANCE_MODE_OFF
```

## 安全设计

- **密钥不入库**：`application.yml` 只有环境变量占位，真实凭据放 `application-local.yml`（已 gitignore）或环境变量
- **传输**：MQTT 走 TLS 8883；HTTP 建议在生产环境前置 HTTPS
- **鉴权分层**：终端用户 JWT（24h 过期）+ 网关上报独立密钥，两者互不通用
- **最小权限**：控制指令白名单校验，非法动作直接抛业务异常
- **全程可审计**：控制指令与告警事件均落库，可按时间与操作人回溯

## 常见问题

| 现象 | 原因与处理 |
|---|---|
| `UnsupportedClassVersionError: class file version 65.0` | 用高版本 JDK 编译过。执行 `mvn clean` 后用 JDK 17 重新编译，或直接跑 `run-jdk17.ps1` |
| 启动报数据库连接失败 | 未激活 `local` profile 或 `application-local.yml` 未填，读到的是空占位密码 |
| 前端一直显示 `--` | 后端未启动 / 地址不对 / 设备与电脑不在同一局域网 |
| 平板布局没生效 | 窗口宽度需 ≥ 840vp，可拉宽窗口或改用平板模拟器 |
| 页面滚动卡顿 | 轮询过密导致整页重建，可调大 `AppConfig.POLL_INTERVAL_MS` |

---

**默认账号**：`admin` / `admin123`（首次启动自动创建，生产环境请立即修改）
