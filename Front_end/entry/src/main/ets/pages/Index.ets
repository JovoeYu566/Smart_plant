import { AppConfig } from '../common/AppConfig'
import { AuthSession } from '../common/AuthSession'
import { LoginPage } from './LoginPage'
import { TabletShell } from './tablet/TabletShell'
import { PhoneShell } from './phone/PhoneShell'
import { AuthApi } from '../service/AuthApi'
import { AppStore } from '../store/AppStore'
import { SafeAreaUtil } from '../common/SafeAreaUtil'
import { TabletTheme, PhoneTheme } from '../common/Theme'

@Entry
@Component
struct Index {
  @Watch('onLoginChanged') @State loggedIn: boolean = false
  @State ready: boolean = false
  @State isTablet: boolean = false
  private unauthListener: () => void = (): void => {
    this.loggedIn = false
  }

  aboutToAppear(): void {
    AuthSession.subscribe(this.unauthListener)
    AuthApi.isLoggedIn().then((ok: boolean) => {
      this.loggedIn = ok
      this.ready = true
      if (ok) {
        AppStore.startPolling(true)
      }
    })
  }

  aboutToDisappear(): void {
    AuthSession.unsubscribe(this.unauthListener)
  }

  onLoginChanged(): void {
    if (this.loggedIn) {
      AppStore.startPolling(true)
    } else {
      AppStore.stopPolling()
    }
    this.syncChrome()
  }

  private syncChrome(): void {
    // 平板登录：深色沉浸 + 隐藏系统状态栏（应用时钟顶替）
    const tabletLive = this.isTablet && this.loggedIn
    SafeAreaUtil.applySystemBarStyle(getContext(this), tabletLive, tabletLive)
  }

  build() {
    Column() {
      if (!this.ready) {
        Text('加载中...')
          .fontSize(16)
          .width('100%')
          .height('100%')
          .textAlign(TextAlign.Center)
          .fontColor(this.isTablet ? TabletTheme.text : PhoneTheme.text)
      } else if (!this.loggedIn) {
        LoginPage({ loggedIn: $loggedIn, isTablet: this.isTablet })
      } else if (this.isTablet) {
        TabletShell({ loggedIn: $loggedIn })
      } else {
        PhoneShell({ loggedIn: $loggedIn })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isTablet ? TabletTheme.bg : PhoneTheme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const w = Number(newValue.width)
      this.isTablet = w >= AppConfig.TABLET_BREAKPOINT_VP
      this.syncChrome()
    })
  }
}
