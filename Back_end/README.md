# 智慧工业后端 MVP

Spring Boot 3 + MySQL + MQTT(EMQX) + JWT，对接主/从节点与纯血鸿蒙前端。

## 功能

- 订阅 EMQX TLS 主题（默认 `gas/sensor/data`），解析全厂工况 JSON 入库
- 主节点 HTTP 上报：`POST /api/plant/report`（Header `X-Gateway-Key`）
- 鸿蒙查询：最新工况 / 历史快照 / 告警列表
- 简单阈值告警：火焰、气体、AGV 离线、近距碰撞
- **远程控制**：`POST /api/control/command` 经 MQTT 发布到 `plant/gateway/command`，并写审计日志
- JWT 登录：默认账号 `admin` / `admin123`


## 环境要求

- **必须 JDK 17**（本仓库固定 `java.version=17`。不要用 JDK 21/24 编译后再用 17 运行，否则会报 `UnsupportedClassVersionError: class file version 65.0`）
- Maven 3.6.1+（建议 3.6.3+）
- MySQL 8

### 避免 JDK 混用（必看）

本机若同时装了 JDK 8 / 17 / 24，IDEA「Build」很容易用高版本写出 class 65，而运行配置却是 JDK 17 → 启动失败。

固定做法任选其一：

1. **推荐脚本**（自动设 `JAVA_HOME` 并 `clean`）：
   ```powershell
   cd Back_end
   .\run-jdk17.ps1
   ```
2. **IDEA**：Project SDK / 运行配置 JRE 都选 `ms-17.0.16`（路径 `C:\Users\jzy05\.jdks\ms-17.0.16`）；Settings → Build → Build Tools → Maven → Runner → JRE 也选同一套。启动前应执行 `mvn clean compile`（运行配置已默认带上）。
3. 出问题先执行：
   ```powershell
   $env:JAVA_HOME='C:\Users\jzy05\.jdks\ms-17.0.16'
   $env:Path="$env:JAVA_HOME\bin;$env:Path"
   mvn clean spring-boot:run -Dspring-boot.run.profiles=local
   ```

## 快速开始

### 1. 建库

在 MySQL 中执行：

```bash
mysql -u root -p < src/main/resources/schema.sql
```

### 2. 修改配置

编辑 [`src/main/resources/application.yml`](src/main/resources/application.yml)：

- `spring.datasource.*`：本机 MySQL 账号密码
- `smart-plant.mqtt.*`：EMQX 地址与账号
- `smart-plant.gateway.api-key`：主节点上报密钥
- `smart-plant.jwt.secret`：至少 32 字节随机串

必须：复制 `application-local.yml.example` 为 `application-local.yml`（已 gitignore），填入本机 MySQL / EMQX 真实账号密码。仓库里的 `application.yml` 只保留环境变量占位（`DB_PASSWORD`、`MQTT_USERNAME`、`MQTT_PASSWORD`、`JWT_SECRET` 等），不再包含任何真实密钥，因此**启动时必须激活 `local` profile**。

- IDEA：运行配置 `SmartPlantApplication` 已设置 `ACTIVE_PROFILES=local`，直接运行即可。
- 命令行：`mvn spring-boot:run -Dspring-boot.run.profiles=local`，或先设置 `$env:SPRING_PROFILES_ACTIVE='local'`。
- 也可完全不建 local 文件，改用环境变量直接注入（适合服务器部署）。

### 3. 启动

```bash
cd Back_end
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

启动后会自动创建管理员（若不存在）：`admin` / `admin123`。

### 4. 联调

健康检查（无需登录）：

```bash
curl http://127.0.0.1:8080/api/health
```

登录拿 Token：

```bash
curl -X POST http://127.0.0.1:8080/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"admin123\"}"
```

查最新工况：

```bash
curl http://127.0.0.1:8080/api/plant/latest -H "Authorization: Bearer <token>"
```

主节点 HTTP 上报：

```bash
curl -X POST http://127.0.0.1:8080/api/plant/report ^
  -H "Content-Type: application/json" ^
  -H "X-Gateway-Key: gateway-dev-key-change-me" ^
  -d "{\"agv_temperature\":28.3,\"agv_humidity\":60.0,\"agv_flame\":false,\"agv_online\":true,\"agv_dist_front\":213,\"agv_dist_back\":49,\"agv_dist_left\":37,\"agv_dist_right\":62,\"gas_temperature\":35.0,\"gas_humidity\":40.8,\"gas_adc\":146,\"gas_voltage\":0.257,\"alarm\":false,\"flame_alarm\":false,\"dark\":false,\"pir\":false,\"cargo_count\":0}"
```

MQTT：设备向 `gas/sensor/data` 发布同上 JSON，后端会自动入库。也可用项目早期的 Python 订阅脚本对照联调。

## API 一览

| 方法 | 路径 | 鉴权 | 说明 |
|------|------|------|------|
| GET | `/api/health` | 无 | 健康检查 |
| POST | `/api/auth/login` | 无 | 登录返回 JWT |
| GET | `/api/plant/latest` | Bearer | 最新全厂工况 |
| GET | `/api/plant/history?page=1&size=20&from=&to=` | Bearer | 历史快照 |
| GET | `/api/alarms?activeOnly=true&limit=50` | Bearer | 告警列表 |
| POST | `/api/plant/report` | `X-Gateway-Key` 或 Bearer | 主节点汇总上报 |
| POST | `/api/control/command` | Bearer | 远程控制下发（MQTT） |
| GET | `/api/control/history?limit=30` | Bearer | 控制指令审计 |

统一响应：`{ "code": 0, "msg": "ok", "data": ... }`。

控制指令示例：

```bash
curl -X POST http://127.0.0.1:8080/api/control/command ^
  -H "Authorization: Bearer <token>" ^
  -H "Content-Type: application/json" ^
  -d "{\"action\":\"LIGHT_ON\",\"params\":{}}"
```

主节点订阅 Topic：`plant/gateway/command`。

## 告警阈值（可配置）

```yaml
smart-plant:
  alarm:
    gas-adc-threshold: 200
    gas-voltage-threshold: 0.5
    min-distance-cm: 20
```

## 包结构

```
com.smartplant
  config/      Security、MyBatis、属性、初始化
  mqtt/        EMQX 订阅与 JSON 解析
  domain/      实体
  mapper/      MyBatis-Plus Mapper
  service/     入库、告警、登录
  controller/  REST
  security/    JWT / Gateway Key
  dto/         请求响应与报文
```
