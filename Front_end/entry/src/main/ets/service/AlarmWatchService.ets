import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import notificationManager from '@ohos.notificationManager'
import { AlarmNotifyService } from './AlarmNotifyService'
import { AppStore } from '../store/AppStore'

const DOMAIN = 0x5302
const LEGACY_WATCH_NOTIFY_ID = 90001

/**
 * 退到后台时申请持续任务，保持告警轮询。
 * 注意：不要再手动 publish「数据传输」通知，系统 startBackgroundRunning 会自动发一条。
 */
export class AlarmWatchService {
  private static running: boolean = false

  static async start(ctx: common.UIAbilityContext): Promise<void> {
    if (AlarmWatchService.running) {
      return
    }
    try {
      AlarmNotifyService.init(ctx)
      // 清掉以前手动发的重复监护通知
      try {
        await notificationManager.cancel(LEGACY_WATCH_NOTIFY_ID)
      } catch (_c) {
        // ignore
      }

      const agent = await AlarmNotifyService.createAlarmWantAgent(1001)
      await backgroundTaskManager.startBackgroundRunning(
        ctx,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
        agent
      )
      AlarmWatchService.running = true
      AppStore.startPolling(true)
      hilog.info(DOMAIN, 'Watch', 'background watch started (single system task notify)')
    } catch (e) {
      AlarmWatchService.running = false
      hilog.warn(DOMAIN, 'Watch', 'start fail %{public}s', JSON.stringify(e))
    }
  }

  static async stop(ctx: common.UIAbilityContext): Promise<void> {
    if (!AlarmWatchService.running) {
      return
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx)
      try {
        await notificationManager.cancel(LEGACY_WATCH_NOTIFY_ID)
      } catch (_c) {
        // ignore
      }
      hilog.info(DOMAIN, 'Watch', 'background watch stopped')
    } catch (e) {
      hilog.warn(DOMAIN, 'Watch', 'stop fail %{public}s', JSON.stringify(e))
    } finally {
      AlarmWatchService.running = false
    }
  }

  static isRunning(): boolean {
    return AlarmWatchService.running
  }
}
