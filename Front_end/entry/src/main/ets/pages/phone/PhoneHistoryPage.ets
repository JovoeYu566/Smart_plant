import { PhoneTheme } from '../../common/Theme'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { PlantApi } from '../../service/PlantApi'
import { PlantLatest } from '../../model/Models'
import { PlantDisplay } from '../../common/PlantDisplay'

@Component
export struct PhoneHistoryPage {
  @State topInset: number = 0
  @State keyword: string = ''
  @State records: PlantLatest[] = []
  @State allRecords: PlantLatest[] = []
  @State total: number = 0
  @State loading: boolean = false
  @State isRefreshing: boolean = false
  @State showDetail: boolean = false
  // 详情弹窗字段（直接 @State，避免 Builder 传参不刷新）
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
  private timerId: number = -1
  private loadInFlight: boolean = false
  /** 列表页只拉最近 80 条，配合后端去掉 raw_json，加载才会快 */
  private static readonly LIST_SIZE: number = 80

  aboutToAppear(): void {
    SafeAreaUtil.resolveTopInset(getContext(this), (vp: number) => {
      this.topInset = vp
    })
    this.load(true)
  }

  aboutToDisappear(): void {
    // 历史页不做轮询，避免反复拉列表卡死
  }

  async load(showLoading: boolean = true): Promise<void> {
    if (this.loadInFlight) {
      return
    }
    this.loadInFlight = true
    if (showLoading && this.records.length === 0) {
      this.loading = true
    }
    try {
      const kw = this.keyword.trim()
      const page = await PlantApi.history(1, PhoneHistoryPage.LIST_SIZE, kw)
      this.records = page.records
      this.allRecords = page.records
      this.total = page.total
    } catch (_e) {
      if (showLoading && this.records.length === 0) {
        this.records = []
        this.allRecords = []
      }
    } finally {
      this.loadInFlight = false
      this.loading = false
      this.isRefreshing = false
    }
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

  private summaryLine(r: PlantLatest): string {
    return `ADC ${r.gasAdc ?? '--'} · 产量 ${r.cargoCount ?? '--'} · 前距 ${r.agvDistFront ?? '--'}`
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text(this.keyword.trim().length > 0
            ? `搜索结果（${this.records.length}）`
            : `历史快照（最近 ${this.records.length}，共 ${this.total}）`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(PhoneTheme.text)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })

        Row({ space: 8 }) {
          TextInput({ text: this.keyword, placeholder: '搜索全部快照（时间 / 来源 / ADC 等）' })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(PhoneTheme.card)
            .onChange((v: string) => {
              this.keyword = v
            })
            .onSubmit(() => {
              this.load(true)
            })
          Button('搜索')
            .height(40)
            .backgroundColor(PhoneTheme.primary)
            .onClick(() => {
              this.load(true)
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

        if (this.loading && this.allRecords.length === 0) {
          Text('加载中...').fontColor(PhoneTheme.textDim).margin({ top: 40 })
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List() {
              if (this.records.length === 0) {
                ListItem() {
                  Text(this.keyword.trim().length > 0 ? '无匹配结果' : '暂无历史')
                    .fontColor(PhoneTheme.textDim)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .margin({ top: 40 })
                }
              } else {
                ForEach(this.records, (r: PlantLatest) => {
                  ListItem() {
                    Column({ space: 4 }) {
                      Text(r.createdAt ?? r.updatedAt ?? '')
                        .fontSize(12)
                        .fontColor(PhoneTheme.textDim)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.summaryLine(r))
                        .fontSize(13)
                        .fontColor(PhoneTheme.text)
                        .width('100%')
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`来源 ${r.source ?? '--'}  主节点 ${PlantDisplay.onlineText(r.gatewayOnline)}  AGV ${PlantDisplay.onlineText(r.agvOnline)}`)
                        .fontSize(12)
                        .fontColor(PhoneTheme.textDim)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .width('100%')
                    .padding(14)
                    .backgroundColor(PhoneTheme.card)
                    .borderRadius(10)
                    .onClick(() => {
                      this.openDetail(r)
                    })
                  }
                  .width('100%')
                  .padding({ bottom: 10 })
                }, (r: PlantLatest, i: number) => `${r.id ?? i}-${r.updatedAt ?? ''}`)
              }
            }
            .width('100%')
            .height('100%')
            .padding({ left: 16, right: 16 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .clip(true)
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing(() => {
            this.load(false)
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PhoneTheme.bg)

      if (this.showDetail) {
        Column() {
          Column() {
            Row() {
              Text('快照详情')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(PhoneTheme.text)
                .layoutWeight(1)
              Text('关闭')
                .fontSize(14)
                .fontColor(PhoneTheme.primary)
                .onClick(() => {
                  this.showDetail = false
                })
            }
            .width('100%')
            .padding({ bottom: 12 })

            Scroll() {
              Column({ space: 6 }) {
                Text(this.dTime).fontSize(12).fontColor(PhoneTheme.textDim).width('100%')
                Text(`来源 ${this.dSource}`).fontSize(12).fontColor(PhoneTheme.textDim).width('100%').margin({ bottom: 8 })

                Text('主节点').fontSize(14).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.primary).width('100%')
                Row() {
                  Text('在线').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterOnline).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('温度').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterTemp).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('湿度').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterHum).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('可燃气体').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterGas).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('气体电压').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterVolt).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('气体告警').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterAlarm).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('火焰').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterFlame).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('光照强度').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterLight).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('有人').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterPir).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('烟雾').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterSmoke).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('产量').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dMasterCargo).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })

                Text('从节点').fontSize(14).fontWeight(FontWeight.Medium).fontColor(PhoneTheme.primary).width('100%').margin({ top: 10 })
                Row() {
                  Text('在线').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveOnline).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('温度').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveTemp).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('湿度').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveHum).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('前距').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dDistFront).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('后距').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dDistBack).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('左距').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dDistLeft).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('右距').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dDistRight).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('火焰').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveFlame).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('烟雾').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveSmoke).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
                Row() {
                  Text('可燃气体').fontSize(13).fontColor(PhoneTheme.textDim).layoutWeight(1)
                  Text(this.dSlaveGas).fontSize(13).fontColor(PhoneTheme.text)
                }.width('100%').padding({ top: 4, bottom: 4 })
              }
              .width('100%')
            }
            .layoutWeight(1)
            .width('100%')
            .scrollBar(BarState.Off)
          }
          .width('92%')
          .constraintSize({ maxHeight: '80%' })
          .padding(16)
          .backgroundColor(PhoneTheme.card)
          .borderRadius(12)
          .onClick(() => {
            // 阻止点击卡片关闭
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
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
