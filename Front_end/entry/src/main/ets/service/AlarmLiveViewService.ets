import { liveViewManager } from '@kit.LiveViewKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AlarmEvent } from '../model/Models'
import { AlarmNotifyService } from './AlarmNotifyService'

const DOMAIN = 0x5302

/**
 * 未恢复告警 → 系统实况窗（Live View）。
 * 场景使用 TIMER（持续计时），需在 AGC 申请对应实况窗权益，
 * 并在系统设置中打开本应用的「实况窗」。
 */
export class AlarmLiveViewService {
  private static readonly LIVE_ID: number = 530101
  private static started: boolean = false
  private static sequence: number = 0
  private static lastFingerprint: string = ''
  private static alarmSinceMs: number = 0
  private static syncing: boolean = false
  private static pending: AlarmEvent[] | null = null
  private static rightsWarned: boolean = false
  private static disabledWarned: boolean = false

  /** 有未恢复告警则创建/更新；全部恢复则结束。可重复调用。 */
  static sync(alarms: AlarmEvent[]): void {
    AlarmLiveViewService.syncAsync(alarms)
  }

  private static async syncAsync(alarms: AlarmEvent[]): Promise<void> {
    if (AlarmLiveViewService.syncing) {
      AlarmLiveViewService.pending = alarms
      return
    }
    AlarmLiveViewService.syncing = true
    try {
      await AlarmLiveViewService.doSync(alarms)
      while (AlarmLiveViewService.pending !== null) {
        const next = AlarmLiveViewService.pending
        AlarmLiveViewService.pending = null
        await AlarmLiveViewService.doSync(next)
      }
    } finally {
      AlarmLiveViewService.syncing = false
    }
  }

  private static activeList(alarms: AlarmEvent[]): AlarmEvent[] {
    const list: AlarmEvent[] = []
    for (let i = 0; i < alarms.length; i++) {
      if (alarms[i].active === true) {
        list.push(alarms[i])
      }
    }
    return list
  }

  private static fingerprint(active: AlarmEvent[]): string {
    const parts: string[] = []
    for (let i = 0; i < active.length; i++) {
      const a = active[i]
      parts.push(`${a.id ?? 0}|${a.alarmType ?? ''}|${a.message ?? ''}`)
    }
    return `${active.length}#${parts.join(';')}`
  }

  private static summary(active: AlarmEvent[]): string {
    if (active.length === 0) {
      return '告警已恢复'
    }
    if (active.length === 1) {
      const a = active[0]
      return a.message ?? `${a.alarmType ?? 'ALARM'} 未恢复`
    }
    const types: string[] = []
    for (let i = 0; i < active.length; i++) {
      const t = active[i].alarmType ?? 'ALARM'
      let found = false
      for (let j = 0; j < types.length; j++) {
        if (types[j] === t) {
          found = true
          break
        }
      }
      if (!found) {
        types.push(t)
      }
    }
    return `${active.length}条未恢复：${types.join('、')}`
  }

  private static async doSync(alarms: AlarmEvent[]): Promise<void> {
    const active = AlarmLiveViewService.activeList(alarms)
    if (active.length === 0) {
      await AlarmLiveViewService.stopIfNeeded()
      return
    }

    const fp = AlarmLiveViewService.fingerprint(active)
    if (AlarmLiveViewService.started && fp === AlarmLiveViewService.lastFingerprint) {
      return
    }

    try {
      const enabled = await liveViewManager.isLiveViewEnabled()
      if (!enabled) {
        if (!AlarmLiveViewService.disabledWarned) {
          AlarmLiveViewService.disabledWarned = true
          hilog.warn(DOMAIN, 'LiveView', 'live view disabled in system settings')
        }
        return
      }
    } catch (e) {
      const err = e as BusinessError
      hilog.warn(DOMAIN, 'LiveView', 'isLiveViewEnabled fail %{public}d', err.code)
      return
    }

    if (!AlarmLiveViewService.started) {
      AlarmLiveViewService.alarmSinceMs = Date.now()
      AlarmLiveViewService.sequence = 1
      const view = await AlarmLiveViewService.buildView(active, false, false)
      try {
        await liveViewManager.startLiveView(view)
        AlarmLiveViewService.started = true
        AlarmLiveViewService.lastFingerprint = fp
        hilog.info(DOMAIN, 'LiveView', 'started active=%{public}d', active.length)
      } catch (e) {
        await AlarmLiveViewService.handleStartError(e as BusinessError, active, fp)
      }
      return
    }

    AlarmLiveViewService.sequence += 1
    const view = await AlarmLiveViewService.buildView(active, false, true)
    try {
      await liveViewManager.updateLiveView(view)
      AlarmLiveViewService.lastFingerprint = fp
      hilog.info(DOMAIN, 'LiveView', 'updated seq=%{public}d active=%{public}d',
        AlarmLiveViewService.sequence, active.length)
    } catch (e) {
      const err = e as BusinessError
      // 不存在则尝试重新创建
      if (err.code === 1003500009 || err.code === 1003500010) {
        AlarmLiveViewService.started = false
        AlarmLiveViewService.lastFingerprint = ''
        await AlarmLiveViewService.doSync(alarms)
        return
      }
      hilog.warn(DOMAIN, 'LiveView', 'update fail %{public}d %{public}s', err.code, err.message)
    }
  }

  private static async handleStartError(err: BusinessError, active: AlarmEvent[], fp: string): Promise<void> {
    if (err.code === 1003500006) {
      // 已存在：当作已启动，走更新
      AlarmLiveViewService.started = true
      AlarmLiveViewService.sequence += 1
      try {
        await liveViewManager.updateLiveView(await AlarmLiveViewService.buildView(active, false, true))
        AlarmLiveViewService.lastFingerprint = fp
      } catch (e2) {
        const err2 = e2 as BusinessError
        hilog.warn(DOMAIN, 'LiveView', 'update after exists fail %{public}d', err2.code)
      }
      return
    }
    if (err.code === 1003500005) {
      if (!AlarmLiveViewService.rightsWarned) {
        AlarmLiveViewService.rightsWarned = true
        hilog.warn(DOMAIN, 'LiveView',
          'rights not enabled (1003500005): apply TIMER live-view in AGC')
      }
      return
    }
    hilog.warn(DOMAIN, 'LiveView', 'start fail %{public}d %{public}s', err.code, err.message)
  }

  private static async stopIfNeeded(): Promise<void> {
    if (!AlarmLiveViewService.started) {
      AlarmLiveViewService.lastFingerprint = ''
      AlarmLiveViewService.alarmSinceMs = 0
      return
    }
    AlarmLiveViewService.sequence += 1
    try {
      const view = await AlarmLiveViewService.buildView([], true, true)
      await liveViewManager.stopLiveView(view)
      hilog.info(DOMAIN, 'LiveView', 'stopped')
    } catch (e) {
      const err = e as BusinessError
      hilog.warn(DOMAIN, 'LiveView', 'stop fail %{public}d %{public}s', err.code, err.message)
    }
    AlarmLiveViewService.started = false
    AlarmLiveViewService.lastFingerprint = ''
    AlarmLiveViewService.alarmSinceMs = 0
  }

  private static async buildView(active: AlarmEvent[], ending: boolean, mute: boolean): Promise<liveViewManager.LiveView> {
    const count = active.length
    const title = ending ? '告警已恢复' : (count === 1 ? '未恢复告警' : `${count}条未恢复告警`)
    const text = AlarmLiveViewService.summary(active)
    const agent = await AlarmNotifyService.createAlarmWantAgent(530101)
    const since = AlarmLiveViewService.alarmSinceMs > 0 ? AlarmLiveViewService.alarmSinceMs : Date.now()

    const primary: liveViewManager.PrimaryData = {
      title: title,
      content: [
        { text: text, textColor: ending ? '#FF666666' : '#FFC62828' }
      ],
      clickAction: agent
    }
    if (ending) {
      primary.keepTime = 5
    }

    const view: liveViewManager.LiveView = {
      id: AlarmLiveViewService.LIVE_ID,
      event: 'TIMER',
      sequence: AlarmLiveViewService.sequence,
      isMute: mute,
      timer: {
        time: since,
        isCountdown: false,
        isPaused: false
      },
      liveViewData: {
        primary: primary,
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
          status: ending ? -1 : 1,
          content: ending ? '已恢复' : `${count}条`,
          time: since,
          isCountdown: false,
          backgroundColor: ending ? '#FF666666' : '#FFC62828'
        }
      }
    }
    return view
  }

  /** 供「我的」页检查系统是否允许实况窗 */
  static async isEnabled(): Promise<boolean> {
    try {
      return await liveViewManager.isLiveViewEnabled()
    } catch (_e) {
      return false
    }
  }
}
