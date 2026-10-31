import { PlantLatest, AlarmEvent, HistoryPage } from '../model/Models'

/**
 * 将后端 JSON 规范化为前端模型。
 * 优先解析 rawJson（与 MQTT 一致的 snake_case），再读 camelCase 字段。
 * 通过 JSON.stringify 往返，规避 ArkTS ESObject 下标取值异常。
 */
export class PlantMapper {
  static normalizeLatest(src: object | null | undefined): PlantLatest | null {
    if (src === null || src === undefined) {
      return null
    }
    const plain = PlantMapper.toPlain(src)
    // 1) 优先 rawJson（与现场报文一致）
    const rawStr = PlantMapper.asString(plain['rawJson'] ?? plain['raw_json'])
    if (rawStr !== undefined && rawStr.length > 2) {
      try {
        const payload = PlantMapper.toPlain(JSON.parse(rawStr) as object)
        const fromRaw = PlantMapper.fromKeys(payload)
        // 补上后端封装字段
        fromRaw.id = PlantMapper.asNumber(plain['id'])
        fromRaw.deviceKey = PlantMapper.asString(plain['deviceKey'] ?? plain['device_key'])
        fromRaw.source = PlantMapper.asString(plain['source'])
        fromRaw.topic = PlantMapper.asString(plain['topic'])
        fromRaw.rawJson = rawStr
        fromRaw.snapshotId = PlantMapper.asNumber(plain['snapshotId'] ?? plain['snapshot_id'])
        fromRaw.updatedAt = PlantMapper.asString(plain['updatedAt'] ?? plain['updated_at'])
        fromRaw.createdAt = PlantMapper.asString(plain['createdAt'] ?? plain['created_at'])
        // 在线状态以后端列为准：心跳超时/启动校正会改列，但不会改 rawJson 里的旧 true
        PlantMapper.applyAuthoritativeOnline(fromRaw, plain)
        if (PlantMapper.hasSensorData(fromRaw)) {
          return fromRaw
        }
      } catch (_e) {
        // fallthrough
      }
    }
    // 2) 直接读 camelCase / snake_case
    const direct = PlantMapper.fromKeys(plain)
    direct.id = PlantMapper.asNumber(plain['id'])
    direct.deviceKey = PlantMapper.asString(plain['deviceKey'] ?? plain['device_key'])
    direct.source = PlantMapper.asString(plain['source'])
    direct.topic = PlantMapper.asString(plain['topic'])
    direct.rawJson = rawStr
    direct.snapshotId = PlantMapper.asNumber(plain['snapshotId'] ?? plain['snapshot_id'])
    direct.updatedAt = PlantMapper.asString(plain['updatedAt'] ?? plain['updated_at'])
    direct.createdAt = PlantMapper.asString(plain['createdAt'] ?? plain['created_at'])
    if (!PlantMapper.hasSensorData(direct)) {
      return null
    }
    return direct
  }

  static hasSensorData(r: PlantLatest): boolean {
    return r.gasAdc !== undefined
      || r.agvTemperature !== undefined
      || r.agvDistFront !== undefined
      || r.gasTemperature !== undefined
      || r.cargoCount !== undefined
  }

  static normalizeAlarm(src: object): AlarmEvent {
    const plain = PlantMapper.toPlain(src)
    const r: AlarmEvent = {
      id: PlantMapper.asNumber(plain['id']),
      alarmType: PlantMapper.asString(plain['alarmType'] ?? plain['alarm_type']),
      message: PlantMapper.asString(plain['message']),
      active: PlantMapper.asBool(plain['active']),
      snapshotId: PlantMapper.asNumber(plain['snapshotId'] ?? plain['snapshot_id']),
      triggeredAt: PlantMapper.asString(plain['triggeredAt'] ?? plain['triggered_at']),
      recoveredAt: PlantMapper.asString(plain['recoveredAt'] ?? plain['recovered_at'])
    }
    return r
  }

  static normalizeHistory(src: object): HistoryPage {
    const plain = PlantMapper.toPlain(src)
    const recordsRaw = plain['records']
    const list: PlantLatest[] = []
    if (Array.isArray(recordsRaw)) {
      for (let i = 0; i < recordsRaw.length; i++) {
        // 历史列表用列字段，不解析 rawJson（后端列表已去掉 raw_json）
        const item = PlantMapper.normalizeSnapshotRow(recordsRaw[i] as object)
        if (item) {
          list.push(item)
        }
      }
    }
    const page: HistoryPage = {
      records: list,
      total: PlantMapper.asNumber(plain['total']) ?? 0,
      page: PlantMapper.asNumber(plain['page']) ?? 1,
      size: PlantMapper.asNumber(plain['size']) ?? 20
    }
    return page
  }

  /** 快照列表行：只读库表列，避免 JSON.parse(rawJson) */
  private static normalizeSnapshotRow(src: object): PlantLatest | null {
    const plain = PlantMapper.toPlain(src)
    const direct = PlantMapper.fromKeys(plain)
    direct.id = PlantMapper.asNumber(plain['id'])
    direct.source = PlantMapper.asString(plain['source'])
    direct.topic = PlantMapper.asString(plain['topic'])
    direct.createdAt = PlantMapper.asString(plain['createdAt'] ?? plain['created_at'])
    direct.updatedAt = PlantMapper.asString(plain['updatedAt'] ?? plain['updated_at'] ?? plain['createdAt'] ?? plain['created_at'])
    if (!PlantMapper.hasSensorData(direct) && direct.createdAt === undefined) {
      return null
    }
    return direct
  }

  private static fromKeys(plain: Record<string, Object | number | boolean | string | null>): PlantLatest {
    const gateAlarmActive = PlantMapper.asBool(plain['gateAlarmActive'] ?? plain['gate_alarm_active'])
    const gateGasAlarm = PlantMapper.asBool(plain['gateGasAlarm'] ?? plain['gate_gas_alarm'])
    let alarm = PlantMapper.asBool(plain['alarm'])
    if (alarm === undefined && (gateAlarmActive !== undefined || gateGasAlarm !== undefined)) {
      alarm = gateAlarmActive === true || gateGasAlarm === true
    }

    const r: PlantLatest = {
      agvTemperature: PlantMapper.asNumber(plain['agvTemperature'] ?? plain['agv_temperature']),
      agvHumidity: PlantMapper.asNumber(plain['agvHumidity'] ?? plain['agv_humidity']),
      agvFlame: PlantMapper.asBool(plain['agvFlame'] ?? plain['agv_flame']),
      agvOnline: PlantMapper.asBool(plain['agvOnline'] ?? plain['agv_online']),
      agvDistFront: PlantMapper.asNumber(plain['agvDistFront'] ?? plain['agv_dist_front']),
      agvDistBack: PlantMapper.asNumber(plain['agvDistBack'] ?? plain['agv_dist_back']),
      agvDistLeft: PlantMapper.asNumber(plain['agvDistLeft'] ?? plain['agv_dist_left']),
      agvDistRight: PlantMapper.asNumber(plain['agvDistRight'] ?? plain['agv_dist_right']),
      agvSmoke: PlantMapper.asBool(plain['agvSmoke'] ?? plain['agv_smoke']),
      agvGasAdc: PlantMapper.asNumber(plain['agvGasAdc'] ?? plain['agv_gas_adc']),
      agvGas: PlantMapper.asBool(plain['agvGas'] ?? plain['agv_gas'] ?? plain['agv_gas_alarm']),
      gatewayOnline: PlantMapper.asBool(
        plain['gatewayOnline'] ?? plain['gateway_online'] ?? plain['master_online'] ?? plain['gas_online']
      ),
      gasTemperature: PlantMapper.asNumber(
        plain['gasTemperature'] ?? plain['gas_temperature'] ?? plain['gate_temperature']
      ),
      gasHumidity: PlantMapper.asNumber(
        plain['gasHumidity'] ?? plain['gas_humidity'] ?? plain['gate_humidity']
      ),
      gasAdc: PlantMapper.asNumber(plain['gasAdc'] ?? plain['gas_adc'] ?? plain['gate_gas_adc']),
      gasVoltage: PlantMapper.asNumber(
        plain['gasVoltage'] ?? plain['gas_voltage'] ?? plain['gate_gas_voltage']
      ),
      alarm: alarm,
      flameAlarm: PlantMapper.asBool(
        plain['flameAlarm'] ?? plain['flame_alarm'] ?? plain['gate_flame_alarm']
      ),
      dark: PlantMapper.asBool(plain['dark'] ?? plain['gate_dark']),
      lightLux: PlantMapper.asNumber(
        plain['lightLux'] ?? plain['light_lux'] ?? plain['gate_lux'] ?? plain['lux'] ?? plain['light_intensity']
      ),
      pir: PlantMapper.asBool(plain['pir'] ?? plain['gate_pir']),
      smoke: PlantMapper.asBool(
        plain['smoke'] ?? plain['smoke_alarm'] ?? plain['gateway_smoke'] ?? plain['gate_smoke']
      ),
      cargoCount: PlantMapper.asNumber(
        plain['cargoCount'] ?? plain['cargo_count'] ?? plain['gate_cargo_count']
      ),
      gateAlarmType: PlantMapper.asNumber(plain['gateAlarmType'] ?? plain['gate_alarm_type'])
    }
    return r
  }

  /**
   * 后端列上的 gatewayOnline / agvOnline 优先于 rawJson。
   * 心跳超时、启动校正只会改列，不会改 rawJson 里残留的 true。
   */
  private static applyAuthoritativeOnline(target: PlantLatest,
    plain: Record<string, Object | number | boolean | string | null>): void {
    const gw = PlantMapper.asBool(
      plain['gatewayOnline'] ?? plain['gateway_online'] ?? plain['master_online'] ?? plain['gas_online']
    )
    const agv = PlantMapper.asBool(plain['agvOnline'] ?? plain['agv_online'])
    if (gw !== undefined) {
      target.gatewayOnline = gw
    }
    if (agv !== undefined) {
      target.agvOnline = agv
    }
  }

  private static toPlain(src: object): Record<string, Object | number | boolean | string | null> {
    try {
      return JSON.parse(JSON.stringify(src)) as Record<string, Object | number | boolean | string | null>
    } catch (_e) {
      return src as Record<string, Object | number | boolean | string | null>
    }
  }

  private static asNumber(v: Object | number | boolean | string | null | undefined): number | undefined {
    if (v === undefined || v === null || v === '') {
      return undefined
    }
    const n = Number(v)
    return isNaN(n) ? undefined : n
  }

  private static asString(v: Object | number | boolean | string | null | undefined): string | undefined {
    if (v === undefined || v === null) {
      return undefined
    }
    return `${v}`
  }

  private static asBool(v: Object | number | boolean | string | null | undefined): boolean | undefined {
    if (v === undefined || v === null) {
      return undefined
    }
    if (typeof v === 'boolean') {
      return v
    }
    if (typeof v === 'number') {
      return v !== 0
    }
    const s = `${v}`
    if (s === 'true' || s === '1') {
      return true
    }
    if (s === 'false' || s === '0') {
      return false
    }
    return undefined
  }
}
