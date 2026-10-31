/** 默认后端：贝锐花生壳外网地址*/
export class AppConfig {
  static readonly DEFAULT_BASE_URL: string = 'http://1208mq42688ct.vicp.fun'
  static readonly TABLET_BREAKPOINT_VP: number = 840
  /** 工况轮询间隔；过短会导致整页频繁重建，滚动时触发 APP_INPUT_BLOCK */
  static readonly POLL_INTERVAL_MS: number = 2000
  static readonly PREF_NAME: string = 'smart_plant_pref'
  static readonly KEY_TOKEN: string = 'token'
  static readonly KEY_USERNAME: string = 'username'
  static readonly KEY_BASE_URL: string = 'base_url'
}
