import { PhoneTheme } from '../../common/Theme'
import { AppStore } from '../../store/AppStore'
import { PlantLatest } from '../../model/Models'
import { ControlApi } from '../../service/ControlApi'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { promptAction } from '@kit.ArkUI'

@Component
export struct PhoneHomePage {
  @State topInset: number = 0
  @State isRefreshing: boolean = false
  // 主节点
  @State masterOnline: string = '--'
  @State masterOnlineColor: string = PhoneTheme.textDim
  @State masterTemp: string = '--'
  @State masterHum: string = '--'
  @State masterGas: string = '--'
  @State masterLight: string = '--'
  @State masterPir: string = '--'
  @State masterFlame: string = '--'
  @State masterSmoke: string = '--'
  @State masterCargo: string = '--'
  // 从节点
  @State slaveOnline: string = '--'
  @State slaveOnlineColor: string = PhoneTheme.textDim
  @State slaveTemp: string = '--'
  @State slaveHum: string = '--'
  @State distFront: string = '--'
  @State distBack: string = '--'
  @State distLeft: string = '--'
  @State distRight: string = '--'
  @State slaveFlame: string = '--'
  @State slaveSmoke: string = '--'
  @State slaveGas: string = '--'
  /** 急停已下发后显示「恢复」 */
  @State agvEstopped: boolean = false
  private listener: () => void = (): void => {
  }

  aboutToAppear(): void {
    SafeAreaUtil.resolveTopInset(getContext(this), (vp: number) => {
      this.topInset = vp
    })
    this.listener = (): void => {
      this.applyLatest(AppStore.latest)
    }
    AppStore.subscribe(this.listener)
    AppStore.refreshOnce().then(() => {
      this.applyLatest(AppStore.latest)
    })
  }

  aboutToDisappear(): void {
    AppStore.unsubscribe(this.listener)
  }

  private applyLatest(l: PlantLatest | null): void {
    if (l === null) {
      this.resetEmpty()
      return
    }

    let plain: Record<string, number | boolean | string | null> = {}
    try {
      plain = JSON.parse(JSON.stringify(l)) as Record<string, number | boolean | string | null>
    } catch (_e) {
      plain = {}
    }

    if (plain['agvTemperature'] === undefined && plain['gasAdc'] === undefined) {
      const raw = plain['rawJson']
      if (typeof raw === 'string' && raw.length > 2) {
        try {
          const payload = JSON.parse(raw) as Record<string, number | boolean | string | null>
          plain['agvTemperature'] = payload['agv_temperature'] ?? payload['agvTemperature']
          plain['agvHumidity'] = payload['agv_humidity'] ?? payload['agvHumidity']
          plain['agvFlame'] = payload['agv_flame'] ?? payload['agvFlame']
          // 在线状态：已有后端校正值则不覆盖（rawJson 可能仍是旧的 true）
          if (plain['agvOnline'] === undefined) {
            plain['agvOnline'] = payload['agv_online'] ?? payload['agvOnline']
          }
          plain['agvDistFront'] = payload['agv_dist_front'] ?? payload['agvDistFront']
          plain['agvDistBack'] = payload['agv_dist_back'] ?? payload['agvDistBack']
          plain['agvDistLeft'] = payload['agv_dist_left'] ?? payload['agvDistLeft']
          plain['agvDistRight'] = payload['agv_dist_right'] ?? payload['agvDistRight']
          plain['agvSmoke'] = payload['agv_smoke'] ?? payload['agvSmoke']
          plain['agvGasAdc'] = payload['agv_gas_adc'] ?? payload['agvGasAdc']
          plain['agvGas'] = payload['agv_gas'] ?? payload['agv_gas_alarm'] ?? payload['agvGas']
          if (plain['gatewayOnline'] === undefined) {
            plain['gatewayOnline'] = payload['gateway_online'] ?? payload['master_online']
              ?? payload['gas_online'] ?? payload['gatewayOnline']
          }
          plain['gasTemperature'] = payload['gate_temperature'] ?? payload['gas_temperature'] ?? payload['gasTemperature']
          plain['gasHumidity'] = payload['gate_humidity'] ?? payload['gas_humidity'] ?? payload['gasHumidity']
          plain['gasAdc'] = payload['gate_gas_adc'] ?? payload['gas_adc'] ?? payload['gasAdc']
          plain['gasVoltage'] = payload['gate_gas_voltage'] ?? payload['gas_voltage'] ?? payload['gasVoltage']
          const gateAlarmActive = payload['gate_alarm_active']
          const gateGasAlarm = payload['gate_gas_alarm']
          if (payload['alarm'] !== undefined && payload['alarm'] !== null) {
            plain['alarm'] = payload['alarm']
          } else if (gateAlarmActive !== undefined || gateGasAlarm !== undefined) {
            plain['alarm'] = gateAlarmActive === true || gateGasAlarm === true
          }
          plain['flameAlarm'] = payload['gate_flame_alarm'] ?? payload['flame_alarm'] ?? payload['flameAlarm']
          plain['dark'] = payload['gate_dark'] ?? payload['dark']
          plain['lightLux'] = payload['gate_lux'] ?? payload['light_lux'] ?? payload['lux'] ?? payload['lightLux']
          plain['pir'] = payload['gate_pir'] ?? payload['pir']
          plain['smoke'] = payload['gate_smoke'] ?? payload['smoke'] ?? payload['smoke_alarm'] ?? payload['gateway_smoke']
          plain['cargoCount'] = payload['gate_cargo_count'] ?? payload['cargo_count'] ?? payload['cargoCount']
          plain['gateAlarmType'] = payload['gate_alarm_type'] ?? payload['gateAlarmType']
        } catch (_e2) {
          // ignore
        }
      }
    }

    const gwOnline = isTrue(plain['gatewayOnline'])
    const gwOffline = isFalse(plain['gatewayOnline'])
    const agvOnline = isTrue(plain['agvOnline'])
    const agvOffline = isFalse(plain['agvOnline'])

    this.masterOnline = gwOnline ? '在线' : (gwOffline ? '离线' : '未知')
    this.masterOnlineColor = gwOnline ? PhoneTheme.ok : (gwOffline ? PhoneTheme.danger : PhoneTheme.textDim)
    this.slaveOnline = agvOnline ? '在线' : (agvOffline ? '离线' : '未知')
    this.slaveOnlineColor = agvOnline ? PhoneTheme.ok : (agvOffline ? PhoneTheme.danger : PhoneTheme.textDim)

    if (gwOffline) {
      this.masterTemp = '--'
      this.masterHum = '--'
      this.masterGas = '--'
      this.masterLight = '--'
      this.masterPir = '--'
      this.masterFlame = '--'
      this.masterSmoke = '--'
      this.masterCargo = '--'
    } else {
      this.masterTemp = fmtNum(plain['gasTemperature'], '℃')
      this.masterHum = fmtNum(plain['gasHumidity'], '%')
      this.masterGas = fmtGas(plain['gasAdc'], plain['alarm'])
      this.masterLight = fmtLight(plain['lightLux'], plain['dark'])
      this.masterPir = fmtBool(plain['pir'], '有人', '无人')
      this.masterFlame = fmtBool(plain['flameAlarm'], '报警', '正常')
      this.masterSmoke = fmtSensorBool(plain['smoke'], '报警', '正常')
      this.masterCargo = fmtNum(plain['cargoCount'], '')
    }

    if (agvOffline) {
      this.slaveTemp = '--'
      this.slaveHum = '--'
      this.distFront = '--'
      this.distBack = '--'
      this.distLeft = '--'
      this.distRight = '--'
      this.slaveFlame = '--'
      this.slaveSmoke = '--'
      this.slaveGas = '--'
    } else {
      this.slaveTemp = fmtNum(plain['agvTemperature'], '℃')
      this.slaveHum = fmtNum(plain['agvHumidity'], '%')
      this.distFront = fmtNum(plain['agvDistFront'], 'cm')
      this.distBack = fmtNum(plain['agvDistBack'], 'cm')
      this.distLeft = fmtNum(plain['agvDistLeft'], 'cm')
      this.distRight = fmtNum(plain['agvDistRight'], 'cm')
      this.slaveFlame = fmtBool(plain['agvFlame'], '报警', '正常')
      this.slaveSmoke = fmtSensorBool(plain['agvSmoke'], '报警', '正常')
      if (plain['agvGasAdc'] !== undefined && plain['agvGasAdc'] !== null) {
        this.slaveGas = fmtNum(plain['agvGasAdc'], '')
      } else if (plain['agvGas'] !== undefined && plain['agvGas'] !== null) {
        this.slaveGas = fmtSensorBool(plain['agvGas'], '报警', '正常')
      } else {
        this.slaveGas = '--'
      }
    }
  }

  private resetEmpty(): void {
    this.masterOnline = '--'
    this.masterOnlineColor = PhoneTheme.textDim
    this.masterTemp = '--'
    this.masterHum = '--'
    this.masterGas = '--'
    this.masterLight = '--'
    this.masterPir = '--'
    this.masterFlame = '--'
    this.masterSmoke = '--'
    this.masterCargo = '--'
    this.slaveOnline = '--'
    this.slaveOnlineColor = PhoneTheme.textDim
    this.slaveTemp = '--'
    this.slaveHum = '--'
    this.distFront = '--'
    this.distBack = '--'
    this.distLeft = '--'
    this.distRight = '--'
    this.slaveFlame = '--'
    this.slaveSmoke = '--'
    this.slaveGas = '--'
  }

  build() {
    Column() {
      Row() {
        Text('全厂工况')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(PhoneTheme.text)
          .layoutWeight(1)

        Button(this.agvEstopped ? '恢复' : '急停')
          .height(36)
          .backgroundColor(this.agvEstopped ? PhoneTheme.ok : PhoneTheme.danger)
          .onClick(async () => {
            try {
              if (this.agvEstopped) {
                const r = await promptAction.showDialog({
                  title: 'AGV恢复',
                  message: '确认下发 AGV 恢复指令？',
                  buttons: [
                    { text: '取消', color: '#999999' },
                    { text: '恢复', color: '#2E7D32' }
                  ]
                })
                if (r.index === 1) {
                  const res = await ControlApi.send('AGV_RESUME')
                  this.agvEstopped = false
                  promptAction.showToast({ message: res.message })
                }
              } else {
                const r = await promptAction.showDialog({
                  title: 'AGV急停',
                  message: '确认下发 AGV 急停指令？',
                  buttons: [
                    { text: '取消', color: '#999999' },
                    { text: '急停', color: '#D32F2F' }
                  ]
                })
                if (r.index === 1) {
                  const res = await ControlApi.send('AGV_ESTOP')
                  this.agvEstopped = true
                  promptAction.showToast({ message: res.message })
                }
              }
            } catch (_e) {
              // cancel
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })

      Refresh({ refreshing: $$this.isRefreshing }) {
        List() {
          ListItem() {
            Column({ space: 12 }) {
              Row() {
                Column() {
                  Text('主节点 · 网关')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PhoneTheme.text)
                  Text('车间固定点位')
                    .fontSize(11)
                    .fontColor(PhoneTheme.textDim)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text(this.masterOnline)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.masterOnlineColor)
              }
              .width('100%')

              Grid() {
                GridItem() {
                  Column() {
                    Text('温度').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterTemp).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('湿度').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterHum).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('可燃气体').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterGas).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('光照强度').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterLight).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('车间有人').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterPir).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('火焰').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterFlame).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('烟雾').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterSmoke).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('产量').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.masterCargo).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
            }
            .width('100%')
            .padding(14)
            .margin({ bottom: 14 })
            .backgroundColor(PhoneTheme.card)
            .borderRadius(12)
            .border({ width: 1, color: PhoneTheme.border })
            .alignItems(HorizontalAlign.Center)
          }

          ListItem() {
            Column({ space: 12 }) {
              Row() {
                Column() {
                  Text('从节点 · AGV')
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(PhoneTheme.text)
                  Text('避障小车 · 移动点位')
                    .fontSize(11)
                    .fontColor(PhoneTheme.textDim)
                    .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text(this.slaveOnline)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.slaveOnlineColor)
              }
              .width('100%')

              Grid() {
                GridItem() {
                  Column() {
                    Text('温度').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.slaveTemp).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('湿度').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.slaveHum).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('前距').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.distFront).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('后距').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.distBack).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('左距').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.distLeft).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('右距').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.distRight).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('火焰').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.slaveFlame).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('烟雾').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.slaveSmoke).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
                GridItem() {
                  Column() {
                    Text('可燃气体').fontSize(12).fontColor(PhoneTheme.textDim)
                    Text(this.slaveGas).fontSize(18).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.text).margin({ top: 6 })
                  }
                  .width('100%').padding(12).backgroundColor(PhoneTheme.bg).borderRadius(8).alignItems(HorizontalAlign.Start)
                }
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(10)
              .rowsGap(10)
              .width('100%')
            }
            .width('100%')
            .padding(14)
            .backgroundColor(PhoneTheme.card)
            .borderRadius(12)
            .border({ width: 1, color: PhoneTheme.border })
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        AppStore.refreshOnce().then(() => {
          this.applyLatest(AppStore.latest)
          this.isRefreshing = false
        }).catch(() => {
          this.isRefreshing = false
        })
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PhoneTheme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}

function isTrue(v: number | boolean | string | null | undefined): boolean {
  return v === true || v === 1 || `${v}` === 'true'
}

function isFalse(v: number | boolean | string | null | undefined): boolean {
  return v === false || v === 0 || `${v}` === 'false'
}

function fmtNum(v: number | boolean | string | null | undefined, unit: string): string {
  if (v === undefined || v === null || v === '') {
    return '--'
  }
  const n = Number(v)
  if (isNaN(n)) {
    return '--'
  }
  return `${n}${unit}`
}

function fmtBool(v: number | boolean | string | null | undefined, whenTrue: string, whenFalse: string): string {
  if (v === undefined || v === null) {
    return '—'
  }
  if (isTrue(v)) {
    return whenTrue
  }
  if (isFalse(v)) {
    return whenFalse
  }
  return '—'
}

function fmtSensorBool(v: number | boolean | string | null | undefined, whenTrue: string, whenFalse: string): string {
  if (v === undefined || v === null || v === '') {
    return '--'
  }
  return fmtBool(v, whenTrue, whenFalse)
}

function fmtReservedBool(v: number | boolean | string | null | undefined, whenTrue: string, whenFalse: string): string {
  return fmtSensorBool(v, whenTrue, whenFalse)
}

function fmtReservedNum(v: number | boolean | string | null | undefined, unit: string): string {
  if (v === undefined || v === null || v === '') {
    return '--'
  }
  return fmtNum(v, unit)
}

function fmtGas(adc: number | boolean | string | null | undefined,
  alarm: number | boolean | string | null | undefined): string {
  if (adc === undefined || adc === null || adc === '') {
    return '--'
  }
  const n = Number(adc)
  if (isNaN(n)) {
    return '--'
  }
  return isTrue(alarm) ? `ADC ${n}·告警` : `ADC ${n}`
}

function fmtLight(lux: number | boolean | string | null | undefined,
  dark: number | boolean | string | null | undefined): string {
  if (lux !== undefined && lux !== null && lux !== '') {
    const n = Number(lux)
    if (!isNaN(n)) {
      return `${n} lux`
    }
  }
  if (dark === undefined || dark === null || dark === '') {
    return '--'
  }
  return fmtBool(dark, '黑暗', '明亮')
}
