/** 登录失效时通知 UI 退回登录页 */
type LogoutListener = () => void

export class AuthSession {
  private static listeners: LogoutListener[] = []
  private static handling: boolean = false

  static subscribe(listener: LogoutListener): void {
    AuthSession.listeners.push(listener)
  }

  static unsubscribe(listener: LogoutListener): void {
    const next: LogoutListener[] = []
    for (let i = 0; i < AuthSession.listeners.length; i++) {
      if (AuthSession.listeners[i] !== listener) {
        next.push(AuthSession.listeners[i])
      }
    }
    AuthSession.listeners = next
  }

  static notifyUnauthorized(): void {
    if (AuthSession.handling) {
      return
    }
    AuthSession.handling = true
    for (let i = 0; i < AuthSession.listeners.length; i++) {
      AuthSession.listeners[i]()
    }
    AuthSession.handling = false
  }
}
