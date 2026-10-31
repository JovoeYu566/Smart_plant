import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { AppConfig } from '../common/AppConfig'

export class PrefStore {
  private static context: common.UIAbilityContext | undefined = undefined

  static init(ctx: common.UIAbilityContext): void {
    PrefStore.context = ctx
  }

  private static async pref(): Promise<preferences.Preferences> {
    if (!PrefStore.context) {
      throw new Error('PrefStore 未初始化')
    }
    return preferences.getPreferences(PrefStore.context, AppConfig.PREF_NAME)
  }

  static async getToken(): Promise<string> {
    const p = await PrefStore.pref()
    const v = await p.get(AppConfig.KEY_TOKEN, '')
    return `${v}`
  }

  static async setToken(token: string): Promise<void> {
    const p = await PrefStore.pref()
    await p.put(AppConfig.KEY_TOKEN, token)
    await p.flush()
  }

  static async getUsername(): Promise<string> {
    const p = await PrefStore.pref()
    const v = await p.get(AppConfig.KEY_USERNAME, '')
    return `${v}`
  }

  static async setUsername(name: string): Promise<void> {
    const p = await PrefStore.pref()
    await p.put(AppConfig.KEY_USERNAME, name)
    await p.flush()
  }

  static async getBaseUrl(): Promise<string> {
    const p = await PrefStore.pref()
    const v = await p.get(AppConfig.KEY_BASE_URL, AppConfig.DEFAULT_BASE_URL)
    const s = PrefStore.normalizeBaseUrl(`${v}`)
    return s.length > 0 ? s : AppConfig.DEFAULT_BASE_URL
  }

  static async setBaseUrl(url: string): Promise<void> {
    const p = await PrefStore.pref()
    await p.put(AppConfig.KEY_BASE_URL, PrefStore.normalizeBaseUrl(url))
    await p.flush()
  }

  /**
   * 花生壳外网域名已映射到本机 8080，公网不要再写 :8080（会超时）。
   * 局域网 IP 仍可带 :8080。
   */
  static normalizeBaseUrl(raw: string): string {
    let s = raw.trim()
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1)
    }
    const lower = s.toLowerCase()
    if (lower.indexOf('vicp.fun') >= 0 || lower.indexOf('oray.net') >= 0
      || lower.indexOf('imwork.net') >= 0 || lower.indexOf('xicp.net') >= 0) {
      s = s.replace(/:8080\b/g, '')
    }
    return s
  }

  static async clearAuth(): Promise<void> {
    const p = await PrefStore.pref()
    await p.put(AppConfig.KEY_TOKEN, '')
    await p.put(AppConfig.KEY_USERNAME, '')
    await p.flush()
  }
}
