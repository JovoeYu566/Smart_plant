import { PlantLatest } from '../model/Models'

/** 把工况对象摊平为可绑定到 @State 的展示字符串（手机/平板共用逻辑） */
export class PlantDisplay {
  static onlineText(v: boolean | undefined): string {
    if (v === true) {
      return '在线'
    }
    if (v === false) {
      return '离线'
    }
    return '—'
  }

  static num(v: number | undefined, unit: string): string {
    if (v === undefined || v === null) {
      return '--'
    }
    return `${v}${unit}`
  }

  /** 节点离线时统一 --；在线无值也用 --（已装传感器不再显示「预留」） */
  static numByOnline(online: boolean | undefined, v: number | undefined, unit: string): string {
    if (online === false) {
      return '--'
    }
    return PlantDisplay.num(v, unit)
  }

  static bool(v: boolean | undefined, whenTrue: string, whenFalse: string): string {
    if (v === true) {
      return whenTrue
    }
    if (v === false) {
      return whenFalse
    }
    return '—'
  }

  /**
   * 布尔传感器：离线 → --；在线有值 → 文案；缺字段 → --（不再用「预留」）
   */
  static sensorBool(online: boolean | undefined, v: boolean | undefined,
    whenTrue: string, whenFalse: string): string {
    if (online === false) {
      return '--'
    }
    if (v === undefined) {
      return '--'
    }
    return PlantDisplay.bool(v, whenTrue, whenFalse)
  }

  /** @deprecated 已装传感器请用 sensorBool；保留兼容旧调用 */
  static reservedBool(v: boolean | undefined, whenTrue: string, whenFalse: string): string {
    return PlantDisplay.sensorBool(true, v, whenTrue, whenFalse)
  }

  static reservedNum(v: number | undefined): string {
    if (v === undefined) {
      return '--'
    }
    return `${v}`
  }

  /** 从节点气体：离线 --；优先 ADC，否则布尔告警 */
  static agvGasText(l: PlantLatest | null): string {
    if (l === null || l.agvOnline === false) {
      return '--'
    }
    if (l.agvGasAdc !== undefined) {
      return `${l.agvGasAdc}`
    }
    if (l.agvGas !== undefined) {
      return PlantDisplay.bool(l.agvGas, '报警', '正常')
    }
    return '--'
  }

  /** 光照：优先 lux 数值；无 lux 时回退旧光敏 dark；网关离线 -- */
  static light(l: PlantLatest | null): string {
    if (l === null || l.gatewayOnline === false) {
      return '--'
    }
    if (l.lightLux !== undefined && l.lightLux !== null) {
      return `${l.lightLux} lux`
    }
    if (l.dark !== undefined) {
      return PlantDisplay.bool(l.dark, '黑暗', '明亮')
    }
    return '--'
  }

  static gasAdc(l: PlantLatest | null): string {
    if (l === null || l.gatewayOnline === false) {
      return '--'
    }
    if (l.gasAdc === undefined) {
      return '--'
    }
    return l.alarm === true ? `ADC ${l.gasAdc}·告警` : `${l.gasAdc}`
  }

  static onlineRate(l: PlantLatest | null): string {
    if (l === null) {
      return '0%'
    }
    let n = 0
    if (l.gatewayOnline === true) {
      n++
    }
    if (l.agvOnline === true) {
      n++
    }
    return `${((n / 2) * 100).toFixed(0)}%`
  }

  static onlineCount(l: PlantLatest | null): number {
    if (l === null) {
      return 0
    }
    return (l.gatewayOnline === true ? 1 : 0) + (l.agvOnline === true ? 1 : 0)
  }
}
