import { TabletTheme } from '../../common/Theme'
import { OverviewPage } from './OverviewPage'
import { ConsolePanel } from '../../components/shared/ConsolePanel'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { AppStore } from '../../store/AppStore'
import { AuthApi } from '../../service/AuthApi'
import { PrefStore } from '../../store/PrefStore'
import { promptAction } from '@kit.ArkUI'

@Component
export struct TabletShell {
  @Link loggedIn: boolean
  /** 0=数据总览 1=控制台 */
  @State shellTab: number = 0
  @State clockText: string = ''
  @State dateText: string = ''
  @State topInset: number = 0
  @State leftInset: number = 0
  @State rightInset: number = 0
  @State bottomInset: number = 0
  @State showServerSettings: boolean = false
  @State baseUrl: string = ''
  private clockTimer: number = -1
  private readonly sidePad: number = 150

  aboutToAppear(): void {
    AppStore.startPolling(true)
    PrefStore.getBaseUrl().then((u: string) => {
      this.baseUrl = u
    })
    SafeAreaUtil.applySystemBarStyleAsync(getContext(this), true, true).then(() => {
      SafeAreaUtil.resolveEdgeInsets(getContext(this), (e) => {
        this.topInset = e.top > 0 ? e.top : 8
        this.leftInset = e.left > 0 ? e.left + 6 : 0
        this.rightInset = e.right > 0 ? e.right + 6 : 0
        this.bottomInset = e.bottom
      })
    })
    this.refreshClock()
    this.clockTimer = setInterval(() => {
      this.refreshClock()
    }, 1000)
  }

  aboutToDisappear(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer)
    }
    SafeAreaUtil.applySystemBarStyle(getContext(this), false, false)
  }

  refreshClock(): void {
    const now = new Date()
    this.clockText = `${this.pad2(now.getHours())}:${this.pad2(now.getMinutes())}:${this.pad2(now.getSeconds())}`
    const y = now.getFullYear()
    const m = this.pad2(now.getMonth() + 1)
    const d = this.pad2(now.getDate())
    const weeks: string[] = ['日', '一', '二', '三', '四', '五', '六']
    this.dateText = `${y}-${m}-${d} 星期${weeks[now.getDay()]}`
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`
  }

  private async openServerSettings(): Promise<void> {
    this.baseUrl = await PrefStore.getBaseUrl()
    this.showServerSettings = true
  }

  private async saveServerUrl(): Promise<void> {
    let url = this.baseUrl.trim()
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1)
    }
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入后端地址' })
      return
    }
    await PrefStore.setBaseUrl(url)
    this.baseUrl = await PrefStore.getBaseUrl()
    this.showServerSettings = false
    AppStore.startPolling(true)
    promptAction.showToast({ message: `已保存：${this.baseUrl}` })
  }

  private async onLogout(): Promise<void> {
    try {
      const r = await promptAction.showDialog({
        title: '退出登录',
        message: '确认退出当前账号？',
        buttons: [
          { text: '取消', color: '#999999' },
          { text: '退出', color: '#D32F2F' }
        ]
      })
      if (r.index !== 1) {
        return
      }
      AppStore.stopPolling()
      await AuthApi.logout()
      this.loggedIn = false
    } catch (_e) {
      // cancel
    }
  }

  build() {
    Stack() {
      Column() {
        // 标题绝对居中；两侧等宽，按钮贴标题左右等距
        Row() {
          Row() {
            Column() {
              Text(this.clockText)
                .fontSize(18)
                .fontColor(TabletTheme.accent)
                .fontWeight(FontWeight.Bold)
              Text(this.dateText)
                .fontSize(10)
                .fontColor(TabletTheme.textDim)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .width(this.sidePad)

            Blank()
            this.navTab('数据总览', 0)
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          Column({ space: 2 }) {
            Text('鸿安智联监控大屏')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(TabletTheme.text)
            Row()
              .width(160)
              .height(2)
              .linearGradient({
                angle: 90,
                colors: [['#00000000', 0], [TabletTheme.accent, 0.5], ['#00000000', 1]]
              })
              .alignSelf(ItemAlign.Center)
          }
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })

          Row({ space: 8 }) {
            this.navTab('控制台', 1)
            Blank()
            Text('服务器')
              .fontSize(13)
              .fontColor(TabletTheme.accent)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius({ topLeft: 2, topRight: 12, bottomLeft: 12, bottomRight: 2 })
              .border({ width: 1, color: TabletTheme.border })
              .backgroundColor('#0A1A3A')
              .onClick(() => {
                this.openServerSettings()
              })
            Text('退出登录')
              .fontSize(13)
              .fontColor(TabletTheme.danger)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .borderRadius({ topLeft: 2, topRight: 12, bottomLeft: 12, bottomRight: 2 })
              .border({ width: 1, color: TabletTheme.danger })
              .backgroundColor('#2A1010')
              .onClick(() => {
                this.onLogout()
              })
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: Math.max(24, 12 + this.leftInset),
          right: 12 + this.rightInset,
          top: this.topInset + 4,
          bottom: 10
        })
        .alignItems(VerticalAlign.Center)

        if (this.shellTab === 0) {
          OverviewPage()
            .layoutWeight(1)
        } else {
          Column() {
            ConsolePanel({ dark: true })
          }
          .layoutWeight(1)
          .padding(8)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.bottomInset })
      .backgroundColor(TabletTheme.bg)

      if (this.showServerSettings) {
        Column() {
          Column({ space: 14 }) {
            Row() {
              Text('服务器设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(TabletTheme.text)
                .layoutWeight(1)
              Text('关闭')
                .fontSize(14)
                .fontColor(TabletTheme.accent)
                .onClick(() => {
                  this.showServerSettings = false
                })
            }
            .width('100%')

            Text('请输入服务器地址')
              .fontSize(12)
              .fontColor(TabletTheme.textDim)
              .width('100%')

            TextInput({ text: this.baseUrl, placeholder: '请输入服务器地址' })
              .width('100%')
              .height(44)
              .backgroundColor('#061428')
              .fontColor(TabletTheme.text)
              .onChange((v: string) => {
                this.baseUrl = v
              })

            Button('保存并重连')
              .width('100%')
              .height(44)
              .backgroundColor(TabletTheme.accent)
              .fontColor(TabletTheme.bg)
              .onClick(() => {
                this.saveServerUrl()
              })
          }
          .width('56%')
          .constraintSize({ maxWidth: 520 })
          .padding(20)
          .backgroundColor(TabletTheme.panel)
          .border({ width: 1, color: TabletTheme.border })
          .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
          .onClick(() => {
            // 阻止冒泡关闭
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#99000D2D')
        .onClick(() => {
          this.showServerSettings = false
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  navTab(title: string, index: number) {
    Text(title)
      .fontSize(14)
      .fontColor(this.shellTab === index ? TabletTheme.bg : TabletTheme.text)
      .backgroundColor(this.shellTab === index ? TabletTheme.accent : '#0A1A3A')
      .padding({ left: 18, right: 18, top: 8, bottom: 8 })
      .borderRadius({ topLeft: 2, topRight: 12, bottomLeft: 12, bottomRight: 2 })
      .border({ width: 1, color: TabletTheme.border })
      .onClick(() => {
        this.shellTab = index
      })
  }
}
