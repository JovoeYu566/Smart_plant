import { ControlActionItem } from '../model/Models'

export class ControlActions {
  private static item(action: string, label: string, group: string, danger: boolean): ControlActionItem {
    const result: ControlActionItem = {
      action: action,
      label: label,
      group: group,
      danger: danger
    }
    return result
  }

  static all(): ControlActionItem[] {
    const list: ControlActionItem[] = []
    list.push(ControlActions.item('LIGHT_ON', '开灯', '照明', false))
    list.push(ControlActions.item('LIGHT_OFF', '关灯', '照明', false))
    list.push(ControlActions.item('ALARM_ACK', '告警确认', '告警', false))
    list.push(ControlActions.item('ALARM_MUTE', '告警静音', '告警', false))
    list.push(ControlActions.item('ALARM_UNMUTE', '取消静音', '告警', false))
    list.push(ControlActions.item('BUZZER_ON', '蜂鸣器开', '告警', false))
    list.push(ControlActions.item('BUZZER_OFF', '蜂鸣器关', '告警', false))
    list.push(ControlActions.item('AGV_ESTOP', 'AGV急停', 'AGV', true))
    list.push(ControlActions.item('AGV_RESUME', 'AGV恢复', 'AGV', true))
    list.push(ControlActions.item('CARGO_RESET', '产量清零', '产量', true))
    list.push(ControlActions.item('GATEWAY_REBOOT', '网关重启', '网关', true))
    return list
  }

  static groups(): string[] {
    return ['照明', '告警', 'AGV', '产量', '网关']
  }
}
