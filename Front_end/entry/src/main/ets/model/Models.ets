export interface ApiResponse<T> {
  code: number
  msg: string
  data: T
}

export interface LoginRequest {
  username: string
  password: string
}

export interface LoginData {
  token: string
  tokenType: string
  expireHours: number
  username: string
  displayName: string
}

export interface PlantLatest {
  id?: number
  deviceKey?: string
  source?: string
  topic?: string
  // 从节点 AGV
  agvTemperature?: number
  agvHumidity?: number
  agvFlame?: boolean
  agvOnline?: boolean
  agvDistFront?: number
  agvDistBack?: number
  agvDistLeft?: number
  agvDistRight?: number
  agvSmoke?: boolean
  /** 旧版 ADC；新版多为 agvGas 布尔 */
  agvGasAdc?: number
  agvGas?: boolean
  // 主节点网关
  gatewayOnline?: boolean
  gasTemperature?: number
  gasHumidity?: number
  gasAdc?: number
  gasVoltage?: number
  alarm?: boolean
  flameAlarm?: boolean
  dark?: boolean
  lightLux?: number
  pir?: boolean
  smoke?: boolean
  cargoCount?: number
  gateAlarmType?: number
  rawJson?: string
  snapshotId?: number
  updatedAt?: string
  createdAt?: string
}

export interface AlarmEvent {
  id?: number
  alarmType?: string
  message?: string
  active?: boolean
  snapshotId?: number
  triggeredAt?: string
  recoveredAt?: string
}

export interface HistoryPage {
  records: PlantLatest[]
  total: number
  page: number
  size: number
}

export interface ControlCommandBody {
  action: string
}

export interface ControlResult {
  requestId: string
  action: string
  topic: string
  success: boolean
  message: string
}

export interface ControlLog {
  id?: number
  requestId?: string
  action?: string
  paramsJson?: string
  operator?: string
  topic?: string
  payloadJson?: string
  success?: boolean
  errorMessage?: string
  createdAt?: string
}

export interface ControlActionItem {
  action: string
  label: string
  group: string
  danger: boolean
}
