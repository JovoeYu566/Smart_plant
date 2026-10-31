import { TabletTheme } from '../../common/Theme'

/** 科技风异形面板：切角、顶栏高光、标题侧栏 */
@Component
export struct TechPanel {
  @Prop title: string = ''
  /** 父组件刷新令牌：变化时强制重绘面板内容 */
  @Prop refreshToken: number = 0
  @BuilderParam headerLeading: () => void = this.emptySlot
  @BuilderParam headerTrailing: () => void = this.emptySlot
  @BuilderParam content: () => void = this.defaultContent

  @Builder
  emptySlot() {
  }

  @Builder
  defaultContent() {
    Text('')
  }

  build() {
    Column() {
      Row()
        .width('100%')
        .height(2)
        .linearGradient({
          angle: 90,
          colors: [['#003A66', 0], [TabletTheme.accent, 0.45], [TabletTheme.border, 0.75], ['#003A66', 1]]
        })

      Row({ space: 8 }) {
        this.headerLeading()
        if (this.title.length > 0) {
          Row({ space: 8 }) {
            Column()
              .width(3)
              .height(14)
              .backgroundColor(TabletTheme.accent)
              .borderRadius(1)
            Text(this.title)
              .fontSize(14)
              .fontColor(TabletTheme.accent)
              .fontWeight(FontWeight.Medium)
          }
        }
        Blank()
        this.headerTrailing()
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 8 })

      Row()
        .width('100%')
        .height(1)
        .linearGradient({
          angle: 90,
          colors: [['#00000000', 0], [TabletTheme.border, 0.25], [TabletTheme.accent, 0.55],
            [TabletTheme.border, 0.8], ['#00000000', 1]]
        })

      Column() {
        this.content()
      }
      .width('100%')
      .layoutWeight(1)
      .padding(10)
      .opacity(this.refreshToken >= 0 ? 1 : 1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.panel)
    .border({ width: 1, color: TabletTheme.border })
    .borderRadius({ topLeft: 2, topRight: 16, bottomLeft: 16, bottomRight: 2 })
    .clip(true)
    .shadow({
      radius: 12,
      color: '#001A4D88',
      offsetX: 0,
      offsetY: 2
    })
  }
}
