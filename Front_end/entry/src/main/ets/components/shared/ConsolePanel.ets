import { ControlActions } from '../../common/ControlActions'
import { PhoneTheme, TabletTheme } from '../../common/Theme'
import { ControlActionItem, ControlLog } from '../../model/Models'
import { ControlApi } from '../../service/ControlApi'
import { promptAction } from '@kit.ArkUI'

/**
 * 手机 / 平板共用控制台。
 * dark=true 平板深色；false 手机浅色。
 */
@Component
export struct ConsolePanel {
  @Prop dark: boolean = true
  @State logs: ControlLog[] = []
  @State busyAction: string = ''
  @State wide: boolean = false
  private groups: string[] = ControlActions.groups()
  private actions: ControlActionItem[] = ControlActions.all()

  aboutToAppear(): void {
    this.reloadLogs()
  }

  private actionsOf(group: string): ControlActionItem[] {
    const list: ControlActionItem[] = []
    for (let i = 0; i < this.actions.length; i++) {
      if (this.actions[i].group === group) {
        list.push(this.actions[i])
      }
    }
    return list
  }

  private cBg(): string {
    return this.dark ? TabletTheme.bg : PhoneTheme.bg
  }

  private cPanel(): string {
    return this.dark ? TabletTheme.panel : PhoneTheme.card
  }

  private cBorder(): string {
    return this.dark ? TabletTheme.border : PhoneTheme.border
  }

  private cAccent(): string {
    return this.dark ? TabletTheme.accent : PhoneTheme.primary
  }

  private cText(): string {
    return this.dark ? TabletTheme.text : PhoneTheme.text
  }

  private cDim(): string {
    return this.dark ? TabletTheme.textDim : PhoneTheme.textDim
  }

  private cDanger(): string {
    return this.dark ? TabletTheme.danger : PhoneTheme.danger
  }

  private cOk(): string {
    return this.dark ? TabletTheme.ok : PhoneTheme.ok
  }

  async reloadLogs(): Promise<void> {
    try {
      this.logs = await ControlApi.history(20)
    } catch (_e) {
      // ignore
    }
  }

  async doAction(item: ControlActionItem): Promise<void> {
    if (item.danger) {
      try {
        const result = await promptAction.showDialog({
          title: '确认操作',
          message: `确定执行「${item.label}」？此操作可能影响现场设备。`,
          buttons: [
            { text: '取消', color: '#999999' },
            { text: '确定', color: '#D32F2F' }
          ]
        })
        if (result.index === 1) {
          await this.sendAction(item)
        }
      } catch (_e) {
        // dialog dismiss
      }
      return
    }
    await this.sendAction(item)
  }

  async sendAction(item: ControlActionItem): Promise<void> {
    this.busyAction = item.action
    try {
      const res = await ControlApi.send(item.action)
      promptAction.showToast({ message: res.message || '已下发' })
      await this.reloadLogs()
    } catch (e) {
      promptAction.showToast({ message: `失败: ${e}` })
    } finally {
      this.busyAction = ''
    }
  }

  build() {
    Column() {
      if (this.wide) {
        Row({ space: 12 }) {
          Scroll() {
            this.actionSections()
          }
          .layoutWeight(3)
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)

          Column() {
            this.logsPanel()
          }
          .layoutWeight(2)
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .padding(12)
      } else {
        Scroll() {
          Column({ space: 12 }) {
            this.actionSections()
            this.logsPanel()
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 20 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.cBg())
    .onAreaChange((_o: Area, n: Area) => {
      this.wide = Number(n.width) >= 720
    })
  }

  @Builder
  actionSections() {
    Column({ space: 12 }) {
      Text('设备控制')
        .fontSize(this.dark ? 18 : 16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.cAccent())
        .width('100%')
        .margin({ bottom: 2 })

      ForEach(this.groups, (group: string) => {
        this.groupCard(group)
      }, (g: string) => g)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  groupCard(group: string) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column()
          .width(3)
          .height(14)
          .backgroundColor(this.cAccent())
          .borderRadius(1)
        Text(group)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cText())
      }
      .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.actionsOf(group), (item: ControlActionItem) => {
          Button(this.busyAction === item.action ? '下发中…' : item.label)
            .width('48%')
            .height(44)
            .margin({ bottom: 8 })
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(item.danger
              ? this.cDanger()
              : (this.dark ? '#0A4A7A' : PhoneTheme.primary))
            .borderRadius(this.dark ? 2 : 10)
            .enabled(this.busyAction.length === 0)
            .opacity(this.busyAction.length === 0 || this.busyAction === item.action ? 1 : 0.55)
            .onClick(() => {
              this.doAction(item)
            })
        }, (item: ControlActionItem) => item.action)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor(this.cPanel())
    .border({ width: 1, color: this.cBorder() })
    .borderRadius(this.dark
      ? { topLeft: 2, topRight: 14, bottomLeft: 14, bottomRight: 2 }
      : 12)
  }

  @Builder
  logsPanel() {
    Column({ space: 10 }) {
      Row() {
        Row({ space: 8 }) {
          Column()
            .width(3)
            .height(14)
            .backgroundColor(this.cAccent())
            .borderRadius(1)
          Text('最近下发')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.cText())
        }
        .layoutWeight(1)

        Text('刷新')
          .fontSize(13)
          .fontColor(this.cAccent())
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            this.reloadLogs()
          })
      }
      .width('100%')

      if (this.logs.length === 0) {
        Text('暂无下发记录')
          .fontSize(13)
          .fontColor(this.cDim())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 28, bottom: 28 })
      } else if (this.wide) {
        List() {
          ForEach(this.logs, (log: ControlLog) => {
            ListItem() {
              this.logRow(log)
            }
            .padding({ bottom: 8 })
          }, (log: ControlLog) => `${log.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        ForEach(this.logs, (log: ControlLog) => {
          this.logRow(log)
        }, (log: ControlLog) => `${log.id}`)
      }
    }
    .width('100%')
    .layoutWeight(this.wide ? 1 : 0)
    .padding(14)
    .backgroundColor(this.cPanel())
    .border({ width: 1, color: this.cBorder() })
    .borderRadius(this.dark
      ? { topLeft: 2, topRight: 14, bottomLeft: 14, bottomRight: 2 }
      : 12)
  }

  @Builder
  logRow(log: ControlLog) {
    Column({ space: 6 }) {
      Row() {
        Text(log.action ?? '--')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.cText())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(log.success ? '成功' : '失败')
          .fontSize(11)
          .fontColor(log.success ? this.cOk() : this.cDanger())
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(log.success
            ? (this.dark ? '#0A2E24' : '#E8F5E9')
            : (this.dark ? '#2A1010' : '#FFEBEE'))
          .borderRadius(4)
      }
      .width('100%')

      Text(`${log.createdAt ?? '--'} · ${log.operator ?? '--'}`)
        .fontSize(11)
        .fontColor(this.cDim())
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding(10)
    .margin({ bottom: this.wide ? 0 : 8 })
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.dark ? '#061428' : '#F7F9FC')
    .borderRadius(8)
  }
}
