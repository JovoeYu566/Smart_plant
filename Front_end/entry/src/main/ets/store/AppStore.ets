import { AppConfig } from '../common/AppConfig'
import { ErrorUtil } from '../common/ErrorUtil'
import { AlarmEvent, PlantLatest } from '../model/Models'
import { PlantApi } from '../service/PlantApi'
import { PlantMapper } from '../common/PlantMapper'
import { AlarmNotifyService } from '../service/AlarmNotifyService'
import { AlarmLiveViewService } from '../service/AlarmLiveViewService'

type Listener = () => void

export class AppStore {
  static latest: PlantLatest | null = null
  static alarms: AlarmEvent[] = []
  static historyTotal: number = 0
  static lastError: string = ''
  static polling: boolean = false
  /** 前台 / 后台标记（持续任务用） */
  static isForeground: boolean = true

  private static timerId: number = -1
  private static listeners: Listener[] = []
  private static knownActiveKeys: string[] = []
  private static alarmPrimed: boolean = false
  private static refreshInFlight: boolean = false
  private static refreshQueued: boolean = false

  static subscribe(listener: Listener): void {
    AppStore.listeners.push(listener)
  }

  static unsubscribe(listener: Listener): void {
    const next: Listener[] = []
    for (let i = 0; i < AppStore.listeners.length; i++) {
      if (AppStore.listeners[i] !== listener) {
        next.push(AppStore.listeners[i])
      }
    }
    AppStore.listeners = next
  }

  private static notify(): void {
    for (let i = 0; i < AppStore.listeners.length; i++) {
      AppStore.listeners[i]()
    }
  }

  private static alarmKey(a: AlarmEvent): string {
    return `${a.id ?? 0}|${a.alarmType ?? ''}|${a.triggeredAt ?? ''}`
  }

  private static emitNewAlarms(list: AlarmEvent[]): void {
    AlarmNotifyService.publishAlarms(list)
  }

  private static detectNewAlarms(): void {
    const active: AlarmEvent[] = []
    for (let i = 0; i < AppStore.alarms.length; i++) {
      if (AppStore.alarms[i].active === true) {
        active.push(AppStore.alarms[i])
      }
    }
    const keys: string[] = []
    for (let i = 0; i < active.length; i++) {
      keys.push(AppStore.alarmKey(active[i]))
    }
    if (!AppStore.alarmPrimed) {
      AppStore.knownActiveKeys = keys
      AppStore.alarmPrimed = true
      return
    }
    const newcomers: AlarmEvent[] = []
    for (let i = 0; i < active.length; i++) {
      const k = keys[i]
      let known = false
      for (let j = 0; j < AppStore.knownActiveKeys.length; j++) {
        if (AppStore.knownActiveKeys[j] === k) {
          known = true
          break
        }
      }
      if (!known) {
        newcomers.push(active[i])
      }
    }
    AppStore.knownActiveKeys = keys
    if (newcomers.length > 0) {
      AppStore.emitNewAlarms(newcomers)
    }
  }

  static async refreshOnce(): Promise<void> {
    if (AppStore.refreshInFlight) {
      AppStore.refreshQueued = true
      return
    }
    AppStore.refreshInFlight = true
    try {
      const latest = await PlantApi.latest()
      // 有有效数据才替换；失败时保留上一帧，避免「退出再进」被清空
      if (latest !== null && PlantMapper.hasSensorData(latest)) {
        AppStore.latest = latest
        AppStore.lastError = ''
      } else if (AppStore.latest === null) {
        AppStore.lastError = '暂无工况数据，正在重试…'
      }

      try {
        AppStore.alarms = await PlantApi.alarms(true, 50)
        AppStore.detectNewAlarms()
        AlarmLiveViewService.sync(AppStore.alarms)
      } catch (_a) {
        // 告警失败不阻断工况，保留旧告警列表
      }

      try {
        const hist = await PlantApi.history(1, 1)
        AppStore.historyTotal = hist.total
      } catch (_h) {
        // ignore
      }

      AppStore.notify()
    } catch (e) {
      // 网络错误：保留旧数据，只更新错误文案
      AppStore.lastError = ErrorUtil.message(e as Object)
      AppStore.notify()
    } finally {
      AppStore.refreshInFlight = false
      if (AppStore.refreshQueued) {
        AppStore.refreshQueued = false
        AppStore.refreshOnce()
      }
    }
  }

  /**
   * 启动或恢复轮询。forceRestart=true 时重建定时器（回前台必用）。
   */
  static startPolling(forceRestart: boolean = false): void {
    if (forceRestart && AppStore.timerId >= 0) {
      clearInterval(AppStore.timerId)
      AppStore.timerId = -1
      AppStore.polling = false
    }
    if (AppStore.polling && AppStore.timerId >= 0) {
      AppStore.refreshOnce()
      return
    }
    AppStore.polling = true
    AppStore.refreshOnce()
    AppStore.timerId = setInterval(() => {
      AppStore.refreshOnce()
    }, AppConfig.POLL_INTERVAL_MS)
  }

  /** 从后台回到前台：重建定时器并立刻拉数 */
  static onEnterForeground(): void {
    AppStore.isForeground = true
    AppStore.startPolling(true)
  }

  static stopPolling(): void {
    AppStore.polling = false
    if (AppStore.timerId >= 0) {
      clearInterval(AppStore.timerId)
      AppStore.timerId = -1
    }
  }
}
