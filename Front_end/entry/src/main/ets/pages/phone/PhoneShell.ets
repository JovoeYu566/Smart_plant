import { PhoneTheme } from '../../common/Theme'
import { PhoneHomePage } from './PhoneHomePage'
import { PhoneAlarmPage } from './PhoneAlarmPage'
import { PhoneHistoryPage } from './PhoneHistoryPage'
import { PhoneMinePage } from './PhoneMinePage'
import { ConsolePanel } from '../../components/shared/ConsolePanel'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { AppNav } from '../../common/AppNav'

@Component
export struct PhoneShell {
  @Link loggedIn: boolean
  @State currentIndex: number = 0
  @State topInset: number = 0
  private navListener: () => void = (): void => {
  }

  aboutToAppear(): void {
    SafeAreaUtil.resolveTopInset(getContext(this), (vp: number) => {
      this.topInset = vp
    })
    SafeAreaUtil.applySystemBarStyle(getContext(this), false)
    this.applyPendingTab()
    this.navListener = (): void => {
      this.applyPendingTab()
    }
    AppNav.subscribe(this.navListener)
  }

  aboutToDisappear(): void {
    AppNav.unsubscribe(this.navListener)
  }

  private applyPendingTab(): void {
    const tab = AppNav.consumePhoneTab()
    if (tab >= 0) {
      this.currentIndex = tab
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
      TabContent() {
        PhoneHomePage()
      }
      .tabBar(this.tabBuilder('首页', 0))

      TabContent() {
        PhoneAlarmPage()
      }
      .tabBar(this.tabBuilder('告警', 1))

      TabContent() {
        PhoneHistoryPage()
      }
      .tabBar(this.tabBuilder('历史', 2))

      TabContent() {
        Column() {
          Text('控制台')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(PhoneTheme.text)
            .width('100%')
            .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 8 })
          ConsolePanel({ dark: false })
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(PhoneTheme.bg)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }
      .tabBar(this.tabBuilder('控制台', 3))

      TabContent() {
        PhoneMinePage({ loggedIn: $loggedIn })
      }
      .tabBar(this.tabBuilder('我的', 4))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PhoneTheme.bg)
    .barBackgroundColor(PhoneTheme.card)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onChange((index: number) => {
      this.currentIndex = index
    })
  }

  @Builder
  tabBuilder(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? PhoneTheme.primary : PhoneTheme.textDim)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
  }
}
