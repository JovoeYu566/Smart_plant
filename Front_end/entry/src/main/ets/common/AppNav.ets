/** 通知点击等跨页面导航意图 */
type NavListener = () => void

export class AppNav {
  /** 手机端目标 Tab：0首页 1告警 2历史 3控制台 4我的；-1 表示无 */
  static pendingPhoneTab: number = -1
  private static listeners: NavListener[] = []

  static subscribe(listener: NavListener): void {
    AppNav.listeners.push(listener)
  }

  static unsubscribe(listener: NavListener): void {
    const next: NavListener[] = []
    for (let i = 0; i < AppNav.listeners.length; i++) {
      if (AppNav.listeners[i] !== listener) {
        next.push(AppNav.listeners[i])
      }
    }
    AppNav.listeners = next
  }

  static requestPhoneTab(tab: number): void {
    AppNav.pendingPhoneTab = tab
    for (let i = 0; i < AppNav.listeners.length; i++) {
      AppNav.listeners[i]()
    }
  }

  /** 读取并清空 pending */
  static consumePhoneTab(): number {
    const t = AppNav.pendingPhoneTab
    AppNav.pendingPhoneTab = -1
    return t
  }

  static requestAlarmTab(): void {
    AppNav.requestPhoneTab(1)
  }
}
