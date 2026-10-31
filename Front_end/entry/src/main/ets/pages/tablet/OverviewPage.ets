import { TabletTheme } from '../../common/Theme'
import { AppStore } from '../../store/AppStore'
import { AlarmEvent, PlantLatest } from '../../model/Models'
import { PlantApi } from '../../service/PlantApi'
import { PlantDisplay } from '../../common/PlantDisplay'
import { promptAction } from '@kit.ArkUI'

/**
 * 数据总览：可变文案一律 Text(this.xxx)。
 * 告警/历史每次轮询都拉取（带 in-flight 合并），与组织列表同步。
 */
@Component
export struct OverviewPage {
  @State masterOnline: string = '—'
  @State masterOnlineOk: boolean = false
  @State slaveOnline: string = '—'
  @State slaveOnlineOk: boolean = false
  @State distFront: string = '--'
  @State distBack: string = '--'
  @State distLeft: string = '--'
  @State distRight: string = '--'
  /** 与后端 min-distance-cm 一致：有效距离 < 20cm 视为超标 */
  @State distDanger: boolean = false
  @State frontDanger: boolean = false
  @State backDanger: boolean = false
  @State leftDanger: boolean = false
  @State rightDanger: boolean = false
  @State agvBlinkOn: boolean = true
  private blinkTimer: number = -1
  /** 告警/历史列表单独慢刷，避免跟工况轮询叠加重建 */
  private listTimer: number = -1
  private static readonly DIST_WARN_CM: number = 20
  private static readonly LIST_REFRESH_MS: number = 8000
  private static readonly ALARM_PAGE_SIZE: number = 100
  @State masterTemp: string = '-- ℃'
  @State masterHum: string = '-- %'
  @State masterGas: string = '--'
  @State masterVolt: string = '--'
  @State masterLight: string = '—'
  @State masterPir: string = '—'
  @State masterFlame: string = '正常'
  @State masterSmoke: string = '--'
  @State masterAlarm: string = '正常'
  @State masterCargo: string = '--'
  @State slaveTemp: string = '-- ℃'
  @State slaveHum: string = '-- %'
  @State slaveFlame: string = '正常'
  @State slaveSmoke: string = '--'
  @State slaveGas: string = '--'
  @State alarmCountText: string = '0'
  @State historyTotalText: string = '0'
  @State histTitle: string = '历史快照'
  @State alarmKeyword: string = ''
  @State alarms: AlarmEvent[] = []
  @State histKeyword: string = ''
  @State histRecords: PlantLatest[] = []
  @State alarmRefreshing: boolean = false
  @State histRefreshing: boolean = false
  @State plantRefreshing: boolean = false
  @State showDetail: boolean = false
  @State dTime: string = ''
  @State dSource: string = ''
  @State dMasterOnline: string = ''
  @State dMasterTemp: string = ''
  @State dMasterHum: string = ''
  @State dMasterGas: string = ''
  @State dMasterVolt: string = ''
  @State dMasterAlarm: string = ''
  @State dMasterFlame: string = ''
  @State dMasterLight: string = ''
  @State dMasterPir: string = ''
  @State dMasterSmoke: string = ''
  @State dMasterCargo: string = ''
  @State dSlaveOnline: string = ''
  @State dSlaveTemp: string = ''
  @State dSlaveHum: string = ''
  @State dDistFront: string = ''
  @State dDistBack: string = ''
  @State dDistLeft: string = ''
  @State dDistRight: string = ''
  @State dSlaveFlame: string = ''
  @State dSlaveSmoke: string = ''
  @State dSlaveGas: string = ''
  private alarmInFlight: boolean = false
  private alarmQueued: boolean = false
  private histInFlight: boolean = false
  private histQueued: boolean = false
  private listener: () => void = (): void => {
  }

  aboutToAppear(): void {
    AppStore.startPolling(true)
    this.listener = (): void => {
      this.applyStore()
    }
    AppStore.subscribe(this.listener)
    this.applyStore()
    this.loadAlarms()
    this.loadHistory()
    this.startListTimer()
  }

  aboutToDisappear(): void {
    AppStore.unsubscribe(this.listener)
    this.stopBlink()
    this.stopListTimer()
  }

  private applyStore(): void {
    const l = AppStore.latest
    this.masterOnline = PlantDisplay.onlineText(l?.gatewayOnline)
    this.masterOnlineOk = l?.gatewayOnline === true
    this.slaveOnline = PlantDisplay.onlineText(l?.agvOnline)
    this.slaveOnlineOk = l?.agvOnline === true
    this.distFront = PlantDisplay.numByOnline(l?.agvOnline, l?.agvDistFront, '')
    this.distBack = PlantDisplay.numByOnline(l?.agvOnline, l?.agvDistBack, '')
    this.distLeft = PlantDisplay.numByOnline(l?.agvOnline, l?.agvDistLeft, '')
    this.distRight = PlantDisplay.numByOnline(l?.agvOnline, l?.agvDistRight, '')
    this.frontDanger = l?.agvOnline === true && this.isDistTooClose(l?.agvDistFront)
    this.backDanger = l?.agvOnline === true && this.isDistTooClose(l?.agvDistBack)
    this.leftDanger = l?.agvOnline === true && this.isDistTooClose(l?.agvDistLeft)
    this.rightDanger = l?.agvOnline === true && this.isDistTooClose(l?.agvDistRight)
    this.distDanger = this.frontDanger || this.backDanger || this.leftDanger || this.rightDanger
    this.syncBlink()
    this.masterTemp = PlantDisplay.numByOnline(l?.gatewayOnline, l?.gasTemperature, ' ℃')
    this.masterHum = PlantDisplay.numByOnline(l?.gatewayOnline, l?.gasHumidity, ' %')
    this.masterGas = PlantDisplay.gasAdc(l)
    this.masterVolt = PlantDisplay.numByOnline(l?.gatewayOnline, l?.gasVoltage, ' V')
    this.masterLight = PlantDisplay.light(l)
    this.masterPir = PlantDisplay.sensorBool(l?.gatewayOnline, l?.pir, '有人', '无人')
    this.masterFlame = PlantDisplay.sensorBool(l?.gatewayOnline, l?.flameAlarm, '报警', '正常')
    this.masterSmoke = PlantDisplay.sensorBool(l?.gatewayOnline, l?.smoke, '报警', '正常')
    this.masterAlarm = PlantDisplay.sensorBool(l?.gatewayOnline, l?.alarm, '告警', '正常')
    this.masterCargo = PlantDisplay.numByOnline(l?.gatewayOnline, l?.cargoCount, '')
    this.slaveTemp = PlantDisplay.numByOnline(l?.agvOnline, l?.agvTemperature, ' ℃')
    this.slaveHum = PlantDisplay.numByOnline(l?.agvOnline, l?.agvHumidity, ' %')
    this.slaveFlame = PlantDisplay.sensorBool(l?.agvOnline, l?.agvFlame, '报警', '正常')
    this.slaveSmoke = PlantDisplay.sensorBool(l?.agvOnline, l?.agvSmoke, '报警', '正常')
    this.slaveGas = PlantDisplay.agvGasText(l)

    // 与组织列表同源，避免标题数滞后
    this.historyTotalText = `${AppStore.historyTotal}`
    this.histTitle = `历史快照（${AppStore.historyTotal}）`

    let count = 0
    for (let i = 0; i < AppStore.alarms.length; i++) {
      if (AppStore.alarms[i].active === true) {
        count++
      }
    }
    this.alarmCountText = `${count}`
    // 告警/历史列表改由 listTimer / 下拉刷新 / 搜索触发，避免 2s 轮询叠加重建卡死主线程
  }

  private startListTimer(): void {
    this.stopListTimer()
    this.listTimer = setInterval(() => {
      this.loadAlarms()
      this.loadHistory()
    }, OverviewPage.LIST_REFRESH_MS)
  }

  private stopListTimer(): void {
    if (this.listTimer >= 0) {
      clearInterval(this.listTimer)
      this.listTimer = -1
    }
  }

  private isDistTooClose(v: number | undefined): boolean {
    return v !== undefined && v !== null && v >= 0 && v < OverviewPage.DIST_WARN_CM
  }

  private syncBlink(): void {
    if (this.distDanger) {
      this.startBlink()
    } else {
      this.stopBlink()
      this.agvBlinkOn = true
    }
  }

  private startBlink(): void {
    if (this.blinkTimer >= 0) {
      return
    }
    this.blinkTimer = setInterval(() => {
      this.agvBlinkOn = !this.agvBlinkOn
    }, 700)
  }

  private stopBlink(): void {
    if (this.blinkTimer >= 0) {
      clearInterval(this.blinkTimer)
      this.blinkTimer = -1
    }
  }

  private histMatch(r: PlantLatest, kw: string): boolean {
    if (kw.length === 0) {
      return true
    }
    const hay = `${r.createdAt ?? ''} ${r.updatedAt ?? ''} ${r.source ?? ''} ${r.gasTemperature ?? ''} ` +
      `${r.gasHumidity ?? ''} ${r.gasAdc ?? ''} ${r.cargoCount ?? ''} ${r.agvDistFront ?? ''} ` +
      `${r.agvTemperature ?? ''}`.toLowerCase()
    return hay.indexOf(kw) >= 0
  }

  async loadAlarms(): Promise<void> {
    if (this.alarmInFlight) {
      this.alarmQueued = true
      return
    }
    this.alarmInFlight = true
    try {
      this.alarms = await PlantApi.alarms(false, OverviewPage.ALARM_PAGE_SIZE, this.alarmKeyword.trim())
    } catch (_e) {
      // 保留旧列表
    } finally {
      this.alarmInFlight = false
      this.alarmRefreshing = false
      if (this.alarmQueued) {
        this.alarmQueued = false
        this.loadAlarms()
      }
    }
  }

  async loadHistory(): Promise<void> {
    if (this.histInFlight) {
      this.histQueued = true
      return
    }
    this.histInFlight = true
    try {
      const page = await PlantApi.history(1, 80)
      const kw = this.histKeyword.trim().toLowerCase()
      const list: PlantLatest[] = []
      for (let i = 0; i < page.records.length; i++) {
        if (this.histMatch(page.records[i], kw)) {
          list.push(page.records[i])
        }
      }
      this.histRecords = list
      AppStore.historyTotal = page.total
      this.historyTotalText = `${page.total}`
      this.histTitle = `历史快照（${page.total}）`
    } catch (_e) {
      // 保留旧列表
    } finally {
      this.histInFlight = false
      this.histRefreshing = false
      if (this.histQueued) {
        this.histQueued = false
        this.loadHistory()
      }
    }
  }

  private onAlarmSearch(): void {
    this.loadAlarms()
  }

  private onHistSearch(): void {
    this.loadHistory()
  }

  private onVideoReserved(): void {
    promptAction.showToast({ message: '视频监控预留中，摄像头接入后开放', duration: 2500 })
  }

  private histSummary(r: PlantLatest): string {
    return `T ${r.gasTemperature ?? '--'}℃ · ADC ${r.gasAdc ?? '--'} · 产量 ${r.cargoCount ?? '--'} · 前距 ${r.agvDistFront ?? '--'}cm`
  }

  private openDetail(r: PlantLatest): void {
    this.dTime = r.createdAt ?? r.updatedAt ?? '--'
    this.dSource = r.source ?? '--'
    this.dMasterOnline = PlantDisplay.onlineText(r.gatewayOnline)
    this.dMasterTemp = PlantDisplay.numByOnline(r.gatewayOnline, r.gasTemperature, ' ℃')
    this.dMasterHum = PlantDisplay.numByOnline(r.gatewayOnline, r.gasHumidity, ' %')
    this.dMasterGas = PlantDisplay.gasAdc(r)
    this.dMasterVolt = PlantDisplay.numByOnline(r.gatewayOnline, r.gasVoltage, ' V')
    this.dMasterAlarm = PlantDisplay.sensorBool(r.gatewayOnline, r.alarm, '告警', '正常')
    this.dMasterFlame = PlantDisplay.sensorBool(r.gatewayOnline, r.flameAlarm, '报警', '正常')
    this.dMasterLight = PlantDisplay.light(r)
    this.dMasterPir = PlantDisplay.sensorBool(r.gatewayOnline, r.pir, '有人', '无人')
    this.dMasterSmoke = PlantDisplay.sensorBool(r.gatewayOnline, r.smoke, '报警', '正常')
    this.dMasterCargo = PlantDisplay.numByOnline(r.gatewayOnline, r.cargoCount, '')
    this.dSlaveOnline = PlantDisplay.onlineText(r.agvOnline)
    this.dSlaveTemp = PlantDisplay.numByOnline(r.agvOnline, r.agvTemperature, ' ℃')
    this.dSlaveHum = PlantDisplay.numByOnline(r.agvOnline, r.agvHumidity, ' %')
    this.dDistFront = PlantDisplay.numByOnline(r.agvOnline, r.agvDistFront, ' cm')
    this.dDistBack = PlantDisplay.numByOnline(r.agvOnline, r.agvDistBack, ' cm')
    this.dDistLeft = PlantDisplay.numByOnline(r.agvOnline, r.agvDistLeft, ' cm')
    this.dDistRight = PlantDisplay.numByOnline(r.agvOnline, r.agvDistRight, ' cm')
    this.dSlaveFlame = PlantDisplay.sensorBool(r.agvOnline, r.agvFlame, '报警', '正常')
    this.dSlaveSmoke = PlantDisplay.sensorBool(r.agvOnline, r.agvSmoke, '报警', '正常')
    this.dSlaveGas = PlantDisplay.agvGasText(r)
    this.showDetail = true
  }

  private async onPlantRefresh(): Promise<void> {
    try {
      await AppStore.refreshOnce()
      this.applyStore()
    } finally {
      this.plantRefreshing = false
    }
  }

  build() {
    Stack() {
      Row({ space: 10 }) {
        Column({ space: 10 }) {
          Column() {
            this.orgPanel()
          }
          .width('100%')
          .height('34%')

          Column() {
            this.alarmPanel()
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('23%')
        .height('100%')

        Column({ space: 10 }) {
          Column() {
            this.agvPanel()
          }
          .width('100%')
          .layoutWeight(11)

          Column() {
            this.histPanel()
          }
          .width('100%')
          .layoutWeight(9)
        }
        .layoutWeight(1)
        .height('100%')

        Column() {
          this.plantPanel()
        }
        .width('26%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .padding(8)

      if (this.showDetail) {
        Column() {
          this.detailOverlay()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  panelTopBar() {
    Row()
      .width('100%')
      .height(2)
      .linearGradient({
        angle: 90,
        colors: [['#003A66', 0], [TabletTheme.accent, 0.45], [TabletTheme.border, 0.75], ['#003A66', 1]]
      })
  }

  @Builder
  panelDivider() {
    Row()
      .width('100%')
      .height(1)
      .linearGradient({
        angle: 90,
        colors: [['#00000000', 0], [TabletTheme.border, 0.25], [TabletTheme.accent, 0.55],
          [TabletTheme.border, 0.8], ['#00000000', 1]]
      })
  }

  /** 固定宽高，数字区预留三位居中，避免方块忽大忽小 */
  @Builder
  distBoxFront() {
    Column({ space: 2 }) {
      Text('前距')
        .fontSize(11)
        .fontColor(this.frontDanger ? TabletTheme.danger : TabletTheme.textDim)
      Row({ space: 4 }) {
        Text(this.distFront)
          .fontSize(22)
          .fontColor(this.frontDanger ? TabletTheme.danger : TabletTheme.accent)
          .fontWeight(FontWeight.Bold)
          .width(54)
          .textAlign(TextAlign.Center)
        Text('cm')
          .fontSize(11)
          .fontColor(this.frontDanger ? TabletTheme.danger : TabletTheme.textDim)
      }
    }
    .width(100)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.frontDanger ? '#2A1010' : '#061428')
    .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
    .border({ width: 1, color: this.frontDanger ? TabletTheme.danger : TabletTheme.border })
  }

  @Builder
  distBoxBack() {
    Column({ space: 2 }) {
      Text('后距')
        .fontSize(11)
        .fontColor(this.backDanger ? TabletTheme.danger : TabletTheme.textDim)
      Row({ space: 4 }) {
        Text(this.distBack)
          .fontSize(22)
          .fontColor(this.backDanger ? TabletTheme.danger : TabletTheme.accent)
          .fontWeight(FontWeight.Bold)
          .width(54)
          .textAlign(TextAlign.Center)
        Text('cm')
          .fontSize(11)
          .fontColor(this.backDanger ? TabletTheme.danger : TabletTheme.textDim)
      }
    }
    .width(100)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.backDanger ? '#2A1010' : '#061428')
    .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
    .border({ width: 1, color: this.backDanger ? TabletTheme.danger : TabletTheme.border })
  }

  @Builder
  distBoxLeft() {
    Column({ space: 2 }) {
      Text('左距')
        .fontSize(11)
        .fontColor(this.leftDanger ? TabletTheme.danger : TabletTheme.textDim)
      Row({ space: 4 }) {
        Text(this.distLeft)
          .fontSize(22)
          .fontColor(this.leftDanger ? TabletTheme.danger : TabletTheme.accent)
          .fontWeight(FontWeight.Bold)
          .width(54)
          .textAlign(TextAlign.Center)
        Text('cm')
          .fontSize(11)
          .fontColor(this.leftDanger ? TabletTheme.danger : TabletTheme.textDim)
      }
    }
    .width(100)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.leftDanger ? '#2A1010' : '#061428')
    .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
    .border({ width: 1, color: this.leftDanger ? TabletTheme.danger : TabletTheme.border })
  }

  @Builder
  distBoxRight() {
    Column({ space: 2 }) {
      Text('右距')
        .fontSize(11)
        .fontColor(this.rightDanger ? TabletTheme.danger : TabletTheme.textDim)
      Row({ space: 4 }) {
        Text(this.distRight)
          .fontSize(22)
          .fontColor(this.rightDanger ? TabletTheme.danger : TabletTheme.accent)
          .fontWeight(FontWeight.Bold)
          .width(54)
          .textAlign(TextAlign.Center)
        Text('cm')
          .fontSize(11)
          .fontColor(this.rightDanger ? TabletTheme.danger : TabletTheme.textDim)
      }
    }
    .width(100)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.rightDanger ? '#2A1010' : '#061428')
    .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
    .border({ width: 1, color: this.rightDanger ? TabletTheme.danger : TabletTheme.border })
  }

  @Builder
  orgPanel() {
    Column() {
      this.panelTopBar()
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(TabletTheme.accent)
          .borderRadius(1)
        Text('组织列表')
          .fontSize(14)
          .fontColor(TabletTheme.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })
      this.panelDivider()

      Column({ space: 8 }) {
        Row() {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.masterOnlineOk ? TabletTheme.ok : TabletTheme.offline)
            .margin({ right: 8 })
          Text('主节点网关')
            .fontSize(13)
            .fontColor(TabletTheme.text)
            .layoutWeight(1)
          Text(this.masterOnline)
            .fontSize(11)
            .fontColor(this.masterOnlineOk ? TabletTheme.ok : TabletTheme.offline)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#061428')
            .borderRadius(10)
            .border({ width: 1, color: this.masterOnlineOk ? '#1A5A4A' : '#2A3548' })
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#061428')
        .borderRadius({ topLeft: 2, topRight: 8, bottomLeft: 8, bottomRight: 2 })
        .border({ width: 1, color: '#0E2A4A' })

        Row() {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.slaveOnlineOk ? TabletTheme.ok : TabletTheme.offline)
            .margin({ right: 8 })
          Text('从节点 AGV')
            .fontSize(13)
            .fontColor(TabletTheme.text)
            .layoutWeight(1)
          Text(this.slaveOnline)
            .fontSize(11)
            .fontColor(this.slaveOnlineOk ? TabletTheme.ok : TabletTheme.offline)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor('#061428')
            .borderRadius(10)
            .border({ width: 1, color: this.slaveOnlineOk ? '#1A5A4A' : '#2A3548' })
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#061428')
        .borderRadius({ topLeft: 2, topRight: 8, bottomLeft: 8, bottomRight: 2 })
        .border({ width: 1, color: '#0E2A4A' })

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(this.alarmCountText)
              .fontSize(16)
              .fontColor(TabletTheme.accent)
              .fontWeight(FontWeight.Bold)
            Text('告警')
              .fontSize(10)
              .fontColor(TabletTheme.textDim)
          }
          .layoutWeight(1)
          .padding(8)
          .backgroundColor('#061428')
          .borderRadius(6)
          .border({ width: 1, color: '#0E2A4A' })

          Column({ space: 2 }) {
            Text(this.historyTotalText)
              .fontSize(16)
              .fontColor(TabletTheme.accent)
              .fontWeight(FontWeight.Bold)
            Text('快照')
              .fontSize(10)
              .fontColor(TabletTheme.textDim)
          }
          .layoutWeight(1)
          .padding(8)
          .backgroundColor('#061428')
          .borderRadius(6)
          .border({ width: 1, color: '#0E2A4A' })
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding(10)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
  }

  @Builder
  alarmPanel() {
    Column() {
      this.panelTopBar()
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(TabletTheme.accent)
          .borderRadius(1)
        Text('实时报警')
          .fontSize(14)
          .fontColor(TabletTheme.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })
      this.panelDivider()

      Row({ space: 8 }) {
        TextInput({ text: this.alarmKeyword, placeholder: '搜索类型 / 内容' })
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .fontColor(TabletTheme.text)
          .placeholderColor(TabletTheme.textDim)
          .backgroundColor('#061428')
          .borderRadius(6)
          .padding({ left: 10, right: 10 })
          .onChange((v: string) => {
            this.alarmKeyword = v
          })
          .onSubmit(() => {
            this.onAlarmSearch()
          })
        Text('搜索')
          .fontSize(12)
          .fontColor(TabletTheme.bg)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(TabletTheme.accent)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(6)
          .onClick(() => {
            this.onAlarmSearch()
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 6 })

      Refresh({ refreshing: $$this.alarmRefreshing }) {
        if (this.alarms.length === 0) {
          Column() {
            Text('暂无报警记录')
              .fontSize(13)
              .fontColor(TabletTheme.textDim)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.alarms, (a: AlarmEvent) => {
              ListItem() {
                Row() {
                  Column()
                    .width(3)
                    .height(36)
                    .backgroundColor(a.active === true ? TabletTheme.danger : TabletTheme.ok)
                    .margin({ right: 8 })
                  Column({ space: 3 }) {
                    Row() {
                      Text(a.alarmType ?? '告警')
                        .fontSize(12)
                        .fontColor(a.active === true ? TabletTheme.danger : TabletTheme.text)
                        .fontWeight(FontWeight.Medium)
                        .layoutWeight(1)
                      Text(a.active === true ? '未恢复' : '已恢复')
                        .fontSize(10)
                        .fontColor(a.active === true ? TabletTheme.danger : TabletTheme.ok)
                    }
                    .width('100%')
                    Text(a.message ?? '')
                      .fontSize(11)
                      .fontColor(TabletTheme.text)
                      .maxLines(2)
                    Text(a.triggeredAt ?? '')
                      .fontSize(10)
                      .fontColor(TabletTheme.textDim)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor('#061428')
                .borderRadius({ topLeft: 2, topRight: 8, bottomLeft: 8, bottomRight: 2 })
                .border({ width: 1, color: '#0E2A4A' })
                .margin({ bottom: 6 })
              }
            }, (a: AlarmEvent) => `${a.id}-${a.active}-${a.triggeredAt ?? ''}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 10, right: 10, bottom: 8 })
      .onRefreshing(() => {
        this.loadAlarms()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
  }

  @Builder
  agvPanel() {
    Column() {
      this.panelTopBar()
      Row({ space: 8 }) {
        Text('AGV状态')
          .fontSize(12)
          .fontColor(TabletTheme.bg)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
          .border({ width: 1, color: TabletTheme.border })
          .backgroundColor(TabletTheme.accent)
        Text('视频监控')
          .fontSize(12)
          .fontColor(TabletTheme.accent)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius({ topLeft: 2, topRight: 10, bottomLeft: 10, bottomRight: 2 })
          .border({ width: 1, color: TabletTheme.border })
          .backgroundColor('#062038')
          .onClick(() => {
            this.onVideoReserved()
          })
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })
      this.panelDivider()

      Row() {
        Column({ space: 16 }) {
          this.distBoxFront()
          this.distBoxBack()
        }
        .justifyContent(FlexAlign.Center)
        .padding({ left: 8 })

        Blank()

        // 俯视车体 + 四向独立雷达弧（超标侧单独闪烁）
        this.agvRadarBoard()

        Blank()

        Column({ space: 16 }) {
          this.distBoxLeft()
          this.distBoxRight()
        }
        .justifyContent(FlexAlign.Center)
        .padding({ right: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 6, right: 6, top: 8, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
  }

  /**
   * 车体在上层盖住雷达图的空白区；弧线实体露在车身外缘外侧（不压车身实物）。
   * 雷达图与车身包围盒可重叠，看起来更聚拢。
   */
  @Builder
  agvRadarBoard() {
    Stack({ alignContent: Alignment.Center }) {
      // 下层：四向雷达（空白区伸进车身包围盒，由上层车体盖住）
      Image($r('app.media.agv_radar'))
        .width(112)
        .height(76)
        .objectFit(ImageFit.Contain)
        .opacity(this.radarOpacity(this.frontDanger))
        .zIndex(0)
        .offset({ x: 0, y: -98 })

      Image($r('app.media.agv_radar'))
        .width(112)
        .height(76)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 180 })
        .opacity(this.radarOpacity(this.backDanger))
        .zIndex(0)
        .offset({ x: 0, y: 98 })

      Image($r('app.media.agv_radar'))
        .width(112)
        .height(76)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: -90 })
        .opacity(this.radarOpacity(this.leftDanger))
        .zIndex(0)
        .offset({ x: -76, y: 0 })

      Image($r('app.media.agv_radar'))
        .width(112)
        .height(76)
        .objectFit(ImageFit.Contain)
        .rotate({ angle: 90 })
        .opacity(this.radarOpacity(this.rightDanger))
        .zIndex(0)
        .offset({ x: 76, y: 0 })

      // 上层：车体盖住伸进来的空白/底色，弧线只从外侧露出来
      Image($r('app.media.agv_body'))
        .width(148)
        .height(208)
        .objectFit(ImageFit.Contain)
        .zIndex(2)
    }
    .width(260)
    .height(300)
    .clip(true)
  }

  private radarOpacity(danger: boolean): number {
    if (!danger) {
      return 0.9
    }
    return this.agvBlinkOn ? 1 : 0.08
  }

  @Builder
  histPanel() {
    Column() {
      this.panelTopBar()
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(TabletTheme.accent)
          .borderRadius(1)
        Text(this.histTitle)
          .fontSize(14)
          .fontColor(TabletTheme.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })
      this.panelDivider()

      Row({ space: 8 }) {
        TextInput({ text: this.histKeyword, placeholder: '搜索快照时间 / 数值' })
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .fontColor(TabletTheme.text)
          .placeholderColor(TabletTheme.textDim)
          .backgroundColor('#061428')
          .borderRadius(6)
          .padding({ left: 10, right: 10 })
          .onChange((v: string) => {
            this.histKeyword = v
          })
          .onSubmit(() => {
            this.onHistSearch()
          })
        Text('搜索')
          .fontSize(12)
          .fontColor(TabletTheme.bg)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(TabletTheme.accent)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(6)
          .onClick(() => {
            this.onHistSearch()
          })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 6 })

      Refresh({ refreshing: $$this.histRefreshing }) {
        if (this.histRecords.length === 0) {
          Column() {
            Text('暂无历史快照')
              .fontSize(13)
              .fontColor(TabletTheme.textDim)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.histRecords, (r: PlantLatest, idx: number) => {
              ListItem() {
                Row() {
                  Column()
                    .width(3)
                    .height(28)
                    .backgroundColor(TabletTheme.accent)
                    .borderRadius(1)
                    .margin({ right: 8 })
                  Column({ space: 2 }) {
                    Text(r.createdAt ?? r.updatedAt ?? '--')
                      .fontSize(12)
                      .fontColor(TabletTheme.text)
                      .fontWeight(FontWeight.Medium)
                    Text(this.histSummary(r))
                      .fontSize(11)
                      .fontColor(TabletTheme.textDim)
                      .maxLines(1)
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(8)
                .backgroundColor(idx % 2 === 0 ? '#061428' : '#071A32')
                .borderRadius(4)
                .margin({ bottom: 4 })
                .onClick(() => {
                  this.openDetail(r)
                })
              }
            }, (r: PlantLatest, idx: number) => `h-${r.id ?? idx}-${r.createdAt ?? ''}`)
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 10, right: 10, bottom: 8 })
      .onRefreshing(() => {
        this.loadHistory()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
  }

  @Builder
  plantPanel() {
    Column() {
      this.panelTopBar()
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(TabletTheme.accent)
          .borderRadius(1)
        Text('全厂工况')
          .fontSize(14)
          .fontColor(TabletTheme.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })
      this.panelDivider()

      Refresh({ refreshing: $$this.plantRefreshing }) {
        Scroll() {
          Column({ space: 8 }) {
            Text('主节点网关')
              .fontSize(12)
              .fontColor(TabletTheme.accent)
              .width('100%')
            Row() {
              Text('在线').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterOnline).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('温度').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterTemp).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('湿度').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterHum).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('可燃气体').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterGas).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('电压').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterVolt).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('光照强度').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterLight).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('有人').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterPir).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('总告警').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterAlarm).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('火焰').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterFlame).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('烟雾').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterSmoke).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('产量').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.masterCargo).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)

            Text('从节点 AGV')
              .fontSize(12)
              .fontColor(TabletTheme.accent)
              .width('100%')
              .margin({ top: 6 })
            Row() {
              Text('在线').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveOnline).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('温度').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveTemp).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('湿度').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveHum).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('火焰').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveFlame).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('烟雾').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveSmoke).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
            Row() {
              Text('可燃气体').fontSize(12).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.slaveGas).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor('#061428').borderRadius(4)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .layoutWeight(1)
      .padding(10)
      .onRefreshing(() => {
        this.onPlantRefresh()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
  }

  @Builder
  detailOverlay() {
    Column() {
      Column() {
        Row() {
          Text('快照详情')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(TabletTheme.text)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(TabletTheme.accent)
            .onClick(() => {
              this.showDetail = false
            })
        }
        .width('100%')
        .padding({ bottom: 12 })

        Scroll() {
          Column({ space: 6 }) {
            Text(this.dTime).fontSize(12).fontColor(TabletTheme.textDim).width('100%')
            Text(`来源 ${this.dSource}`).fontSize(12).fontColor(TabletTheme.textDim).width('100%').margin({ bottom: 8 })

            Text('主节点').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TabletTheme.accent).width('100%')
            Row() {
              Text('在线').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterOnline).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('温度').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterTemp).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('湿度').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterHum).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('可燃气体').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterGas).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('气体电压').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterVolt).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('气体告警').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterAlarm).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('火焰').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterFlame).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('光照强度').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterLight).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('有人').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterPir).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('烟雾').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterSmoke).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('产量').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dMasterCargo).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })

            Text('从节点').fontSize(14).fontWeight(FontWeight.Medium).fontColor(TabletTheme.accent).width('100%').margin({ top: 10 })
            Row() {
              Text('在线').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveOnline).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('温度').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveTemp).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('湿度').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveHum).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('前距').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dDistFront).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('后距').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dDistBack).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('左距').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dDistLeft).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('右距').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dDistRight).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('火焰').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveFlame).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('烟雾').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveSmoke).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
            Row() {
              Text('可燃气体').fontSize(13).fontColor(TabletTheme.textDim).layoutWeight(1)
              Text(this.dSlaveGas).fontSize(13).fontColor(TabletTheme.text)
            }.width('100%').padding({ top: 4, bottom: 4 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
      .width('56%')
      .constraintSize({ maxHeight: '86%' })
      .padding(20)
      .backgroundColor(TabletTheme.panel)
      .border({ width: 1, color: TabletTheme.border })
      .borderRadius(12)
      .onClick(() => {
        // 阻止穿透关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showDetail = false
    })
  }
}
