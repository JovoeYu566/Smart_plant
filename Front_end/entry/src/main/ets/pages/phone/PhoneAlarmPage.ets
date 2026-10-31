import { PhoneTheme } from '../../common/Theme'
import { AppConfig } from '../../common/AppConfig'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { AlarmEvent } from '../../model/Models'
import { PlantApi } from '../../service/PlantApi'
import { AppStore } from '../../store/AppStore'
import { promptAction } from '@kit.ArkUI'

@Component
export struct PhoneAlarmPage {
  @State topInset: number = 0
  @State activeOnly: boolean = false
  @State keyword: string = ''
  @State alarms: AlarmEvent[] = []
  @State loading: boolean = false
  @State isRefreshing: boolean = false
  @State tip: string = ''
  private timerId: number = -1
  private reloadInFlight: boolean = false
  private lastAlarmSig: string = ''
  private storeListener: () => void = (): void => {
  }
  /** 列表默认 500；有搜索关键词时拉全库匹配 */
  private static readonly LIST_LIMIT: number = 500
  private static readonly SEARCH_LIMIT: number = 10000

  aboutToAppear(): void {
    SafeAreaUtil.resolveTopInset(getContext(this), (vp: number) => {
      this.topInset = vp
    })
    this.reload(true)
    this.startAutoRefresh()
    this.storeListener = (): void => {
      this.onStoreAlarmsChanged()
    }
    AppStore.subscribe(this.storeListener)
  }

  aboutToDisappear(): void {
    this.stopAutoRefresh()
    AppStore.unsubscribe(this.storeListener)
  }

  private alarmSig(): string {
    let sig = ''
    for (let i = 0; i < AppStore.alarms.length; i++) {
      const a = AppStore.alarms[i]
      sig += `${a.id ?? 0}:${a.active === true ? 1 : 0}:${a.triggeredAt ?? ''};`
    }
    return sig
  }

  /** 全局轮询发现新告警时，自动刷新本页（无需手动下拉） */
  private onStoreAlarmsChanged(): void {
    const sig = this.alarmSig()
    if (sig === this.lastAlarmSig) {
      return
    }
    this.lastAlarmSig = sig
    this.reload(false)
  }

  private startAutoRefresh(): void {
    this.stopAutoRefresh()
    this.timerId = setInterval(() => {
      this.reload(false)
    }, AppConfig.POLL_INTERVAL_MS * 4)
  }

  private stopAutoRefresh(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private async reload(showLoading: boolean): Promise<void> {
    if (this.reloadInFlight) {
      return
    }
    this.reloadInFlight = true
    if (showLoading && this.alarms.length === 0) {
      this.loading = true
    }
    try {
      const kw = this.keyword.trim()
      const limit = kw.length > 0 ? PhoneAlarmPage.SEARCH_LIMIT : PhoneAlarmPage.LIST_LIMIT
      const list = await PlantApi.alarms(this.activeOnly, limit, kw)
      this.alarms = list
      this.tip = ''
    } catch (e) {
      if (showLoading && this.alarms.length === 0) {
        this.alarms = []
        this.tip = `${e}`
        promptAction.showToast({ message: `加载失败: ${e}`, duration: 3000 })
      }
    } finally {
      this.reloadInFlight = false
      this.loading = false
      this.isRefreshing = false
    }
  }

  private statusLabel(a: AlarmEvent): string {
    if (a.active === true) {
      return '未恢复'
    }
    return '已恢复'
  }

  private statusColor(a: AlarmEvent): string {
    return a.active === true ? PhoneTheme.danger : PhoneTheme.textDim
  }

  build() {
    Column() {
      Row() {
        Text('告警')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(PhoneTheme.text)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })

      Row({ space: 8 }) {
        TextInput({ text: this.keyword, placeholder: '搜索全部告警（类型 / 内容）' })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(PhoneTheme.card)
          .onChange((v: string) => {
            this.keyword = v
          })
          .onSubmit(() => {
            this.reload(true)
          })
        Button('搜索')
          .height(40)
          .backgroundColor(PhoneTheme.primary)
          .onClick(() => {
            this.reload(true)
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      Row({ space: 8 }) {
        Text('全部')
          .fontSize(13)
          .fontColor(!this.activeOnly ? Color.White : PhoneTheme.text)
          .backgroundColor(!this.activeOnly ? PhoneTheme.primary : PhoneTheme.card)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(14)
          .border({ width: 1, color: PhoneTheme.border })
          .onClick(() => {
            this.activeOnly = false
            this.reload(true)
          })
        Text('仅未恢复')
          .fontSize(13)
          .fontColor(this.activeOnly ? Color.White : PhoneTheme.text)
          .backgroundColor(this.activeOnly ? PhoneTheme.primary : PhoneTheme.card)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .borderRadius(14)
          .border({ width: 1, color: PhoneTheme.border })
          .onClick(() => {
            this.activeOnly = true
            this.reload(true)
          })
        Text(`共 ${this.alarms.length} 条`)
          .fontSize(12)
          .fontColor(PhoneTheme.textDim)
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      if (this.loading && this.alarms.length === 0) {
        Text('加载中...')
          .fontColor(PhoneTheme.textDim)
          .margin({ top: 80 })
      } else if (this.tip.length > 0 && this.alarms.length === 0) {
        Text(this.tip)
          .fontColor(PhoneTheme.danger)
          .margin({ top: 40, left: 16, right: 16 })
      } else {
        Refresh({ refreshing: $$this.isRefreshing }) {
          List() {
            if (this.alarms.length === 0) {
              ListItem() {
                Text(this.activeOnly ? '暂无未恢复告警' : '暂无告警记录')
                  .fontColor(PhoneTheme.textDim)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ top: 80 })
              }
            } else {
              ForEach(this.alarms, (a: AlarmEvent) => {
                ListItem() {
                  Column({ space: 4 }) {
                    Row() {
                      Text(a.alarmType ?? '')
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(PhoneTheme.danger)
                        .layoutWeight(1)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.statusLabel(a))
                        .fontSize(12)
                        .fontColor(this.statusColor(a))
                        .margin({ left: 8 })
                        .flexShrink(0)
                    }
                    .width('100%')

                    Text(a.message ?? '')
                      .fontSize(13)
                      .fontColor(PhoneTheme.text)
                      .width('100%')
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`触发: ${a.triggeredAt ?? '--'}`)
                      .fontSize(12)
                      .fontColor(PhoneTheme.textDim)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (a.active !== true && a.recoveredAt) {
                      Text(`恢复: ${a.recoveredAt}`)
                        .fontSize(12)
                        .fontColor(PhoneTheme.textDim)
                        .width('100%')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding(14)
                  .backgroundColor(PhoneTheme.card)
                  .borderRadius(10)
                }
                .width('100%')
                .padding({ bottom: 10 })
              }, (a: AlarmEvent) => `${a.id}-${a.active}-${a.recoveredAt ?? ''}`)
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .clip(true)
          .cachedCount(8)
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(() => {
          this.reload(false)
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PhoneTheme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
