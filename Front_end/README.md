# 智慧工业鸿蒙前端

纯血鸿蒙 App：按屏幕宽度自动切换 **平板数据大屏** / **手机业务端**，共用登录与后端 API。

## 功能

- 登录（JWT）与本地 Preferences 持久化
- 每 3 秒轮询最新工况与未恢复告警
- **平板**（宽 ≥ 840vp）：系统总览 / 数据监控 / 控制台
- **手机**：首页 / 告警 / 历史 / 控制台 / 我的
- 控制台：远程指令经后端 MQTT 下发主节点（含危险操作二次确认）

## 联调前准备

1. 后端已启动，MySQL 已执行 `schema.sql`，并执行控制表增量：

```bash
mysql -u root -p smart_plant < src/main/resources/schema_control.sql
```

（若重新执行完整 `schema.sql` 则已含该表。）

2. 修改默认后端地址：编辑

[`entry/src/main/ets/common/AppConfig.ets`](entry/src/main/ets/common/AppConfig.ets)

```ts
static readonly DEFAULT_BASE_URL: string = 'http://你的电脑局域网IP:8080'
```

也可在 App 登录页或「我的」里临时修改。

3. 手机/平板与电脑同一局域网；鸿蒙需已申请 `INTERNET` 权限（已写入 `module.json5`）。

## 主节点 MQTT 指令约定

- Topic：`plant/gateway/command`（后端 `smart-plant.mqtt.command-topic`）
- 示例 payload：

```json
{
  "action": "LIGHT_ON",
  "params": {},
  "requestId": "abc123",
  "ts": 1710000000000,
  "operator": "admin"
}
```

主节点应订阅该 Topic，按 `action` 执行。支持动作见控制台按钮（照明、告警/蜂鸣、AGV 急停/恢复、产量清零、网关重启、维护模式等）。

## 默认账号

与后端一致：`admin` / `admin123`

## DevEco 打开

用 DevEco Studio 打开 `Front_end` 目录，选择 Phone 或 Tablet 模拟器/真机运行。拉宽窗口可切到大屏布局。
