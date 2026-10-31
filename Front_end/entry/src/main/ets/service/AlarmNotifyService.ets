import notificationManager from '@ohos.notificationManager'
import { wantAgent, WantAgent, common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { AlarmEvent } from '../model/Models'

const DOMAIN = 0x5301

/**
 * 系统通知栏告警。
 * 点击通过 WantAgent 打开 EntryAbility（uri + parameters）。
 */
export class AlarmNotifyService {
  private static nextId: number = 91000
  private static bundleName: string = 'com.example.front_end'
  private static moduleName: string = 'entry'

  static init(ctx: common.UIAbilityContext): void {
    try {
      AlarmNotifyService.bundleName = ctx.abilityInfo.bundleName
      if (ctx.abilityInfo.moduleName) {
        AlarmNotifyService.moduleName = ctx.abilityInfo.moduleName
      }
    } catch (_e) {
      // keep default
    }
  }

  static async requestPermission(ctx: common.UIAbilityContext): Promise<void> {
    AlarmNotifyService.init(ctx)
    try {
      await notificationManager.requestEnableNotification(ctx)
      try {
        await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION)
      } catch (_e) {
        // ignore
      }
      try {
        await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION)
      } catch (_e2) {
        // ignore
      }
      hilog.info(DOMAIN, 'Notify', 'notification channel ready')
    } catch (e) {
      hilog.warn(DOMAIN, 'Notify', 'requestEnableNotification fail %{public}s', JSON.stringify(e))
    }
  }

  /** 构造「打开 App → 告警页」的 WantAgent */
  static async createAlarmWantAgent(requestCode: number): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: AlarmNotifyService.bundleName,
          moduleName: AlarmNotifyService.moduleName,
          abilityName: 'EntryAbility',
          uri: 'smartplant://alarm',
          parameters: {
            targetPage: 'alarm'
          }
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: requestCode,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    return wantAgent.getWantAgent(info)
  }

  static async publishAlarms(list: AlarmEvent[]): Promise<void> {
    if (list.length === 0) {
      return
    }
    for (let i = 0; i < list.length; i++) {
      const a = list[i]
      const typeName = a.alarmType ?? 'ALARM'
      const text = `${typeName}  ${a.message ?? '检测到新告警'}`
      await AlarmNotifyService.publishAlarm('鸿安智联', text)
    }
  }

  static async publishAlarm(title: string, text: string): Promise<void> {
    try {
      const id = AlarmNotifyService.nextId++
      if (AlarmNotifyService.nextId > 92000) {
        AlarmNotifyService.nextId = 91000
      }
      const agent = await AlarmNotifyService.createAlarmWantAgent(800000 + id)
      const req: notificationManager.NotificationRequest = {
        id: id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text
          }
        },
        wantAgent: agent,
        deliveryTime: Date.now(),
        showDeliveryTime: true,
        tapDismissed: true,
        isAlertOnce: false
      }
      await notificationManager.publish(req)
      hilog.info(DOMAIN, 'Notify', 'published alarm id=%{public}d with wantAgent', id)
    } catch (e) {
      hilog.warn(DOMAIN, 'Notify', 'publish fail %{public}s', JSON.stringify(e))
    }
  }
}
