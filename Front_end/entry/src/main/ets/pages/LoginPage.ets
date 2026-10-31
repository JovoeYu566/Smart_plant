import { PhoneTheme, TabletTheme } from '../common/Theme'
import { AuthApi } from '../service/AuthApi'
import { PrefStore } from '../store/PrefStore'
import { ErrorUtil } from '../common/ErrorUtil'
import { SafeAreaUtil } from '../common/SafeAreaUtil'
import { promptAction } from '@kit.ArkUI'

@Component
export struct LoginPage {
  @Link loggedIn: boolean
  @Prop isTablet: boolean = false
  @State topInset: number = 0
  @State leftInset: number = 0
  @State rightInset: number = 0
  @State bottomInset: number = 0
  @State username: string = 'admin'
  @State password: string = 'admin123'
  @State loading: boolean = false
  @State showServerSettings: boolean = false
  @State baseUrl: string = ''
  @State enterReady: boolean = false

  aboutToAppear(): void {
    SafeAreaUtil.resolveEdgeInsets(getContext(this), (e) => {
      this.topInset = e.top
      this.leftInset = e.left
      this.rightInset = e.right
      this.bottomInset = e.bottom
    })
    SafeAreaUtil.applySystemBarStyle(getContext(this), this.isTablet, false)
    PrefStore.getBaseUrl().then((u: string) => {
      this.baseUrl = u
    })
    setTimeout(() => {
      this.enterReady = true
    }, 40)
  }

  private async doLogin(): Promise<void> {
    this.loading = true
    try {
      await AuthApi.login(this.username.trim(), this.password)
      this.loggedIn = true
      promptAction.showToast({ message: '登录成功' })
    } catch (e) {
      promptAction.showToast({
        message: `登录失败: ${ErrorUtil.message(e as Object)}`,
        duration: 4000
      })
    } finally {
      this.loading = false
    }
  }

  private async openServerSettings(): Promise<void> {
    this.baseUrl = await PrefStore.getBaseUrl()
    this.showServerSettings = true
  }

  private async saveServerUrl(): Promise<void> {
    let url = this.baseUrl.trim()
    if (url.length === 0) {
      promptAction.showToast({ message: '请输入服务器地址' })
      return
    }
    await PrefStore.setBaseUrl(url)
    this.baseUrl = await PrefStore.getBaseUrl()
    this.showServerSettings = false
    promptAction.showToast({ message: '服务器地址已保存' })
  }

  build() {
    Stack() {
      if (this.isTablet) {
        this.tabletLogin()
      } else {
        this.phoneLogin()
      }

      if (this.showServerSettings) {
        this.serverSettingsOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  phoneLogin() {
    Stack() {
      // 氛围底：浅蓝径向感
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#E8F3FC', 0], ['#F3F6FA', 0.45], ['#EEF2F7', 1]]
        })

      Column()
        .width(280)
        .height(280)
        .borderRadius(140)
        .backgroundColor('#181565C0')
        .position({ x: '62%', y: '-8%' })

      Column()
        .width(180)
        .height(180)
        .borderRadius(90)
        .backgroundColor('#1200A2FF')
        .position({ x: '-18%', y: '68%' })

      Column({ space: 0 }) {
        Blank().height(this.topInset + 28)

        Image($r('app.media.logo'))
          .width(168)
          .height(168)
          .objectFit(ImageFit.Contain)
          .opacity(this.enterReady ? 1 : 0)
          .scale({ x: this.enterReady ? 1 : 0.92, y: this.enterReady ? 1 : 0.92 })
          .animation({ duration: 420, curve: Curve.EaseOut })

        Text('智联现场 · 安控有方')
          .fontSize(15)
          .fontColor(PhoneTheme.text)
          .fontWeight(FontWeight.Medium)
          .margin({ top: 4 })
          .opacity(this.enterReady ? 1 : 0)
          .animation({ duration: 480, delay: 60, curve: Curve.EaseOut })

        Text('登录后进入监控与控制台')
          .fontSize(12)
          .fontColor(PhoneTheme.textDim)
          .margin({ top: 6, bottom: 22 })

        Column({ space: 14 }) {
          TextInput({ placeholder: '用户名', text: this.username })
            .width('100%')
            .height(48)
            .backgroundColor('#F5F8FC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.username = v
            })

          TextInput({ placeholder: '密码', text: this.password })
            .width('100%')
            .height(48)
            .type(InputType.Password)
            .backgroundColor('#F5F8FC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.password = v
            })

          Button(this.loading ? '登录中...' : '登录')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(PhoneTheme.primary)
            .borderRadius(12)
            .enabled(!this.loading)
            .margin({ top: 4 })
            .onClick(() => {
              this.doLogin()
            })

          Text('服务器地址')
            .fontSize(13)
            .fontColor(PhoneTheme.primary)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 4, bottom: 2 })
            .onClick(() => {
              this.openServerSettings()
            })
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 20, bottom: 18 })
        .backgroundColor(PhoneTheme.card)
        .borderRadius(16)
        .shadow({
          radius: 24,
          color: '#1A1565C0',
          offsetX: 0,
          offsetY: 10
        })
        .opacity(this.enterReady ? 1 : 0)
        .translate({ y: this.enterReady ? 0 : 16 })
        .animation({ duration: 480, delay: 100, curve: Curve.EaseOut })

        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 28, right: 28, bottom: 24 + this.bottomInset })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  tabletLogin() {
    Stack() {
      Row() {
        // 左侧品牌区
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(420)
              .height(420)
              .borderRadius(210)
              .backgroundColor('#1000E5FF')
              .position({ x: '-18%', y: '55%' })

            Column()
              .width(260)
              .height(260)
              .borderRadius(130)
              .backgroundColor('#1400A2FF')
              .position({ x: '58%', y: '-12%' })

            Column({ space: 0 }) {
              Image($r('app.media.logo'))
                .width(220)
                .height(220)
                .objectFit(ImageFit.Contain)
                .opacity(this.enterReady ? 1 : 0)
                .scale({ x: this.enterReady ? 1 : 0.94, y: this.enterReady ? 1 : 0.94 })
                .animation({ duration: 500, curve: Curve.EaseOut })

              Text('智联现场 · 安控有方')
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .fontColor(TabletTheme.text)
                .margin({ top: 8 })
                .opacity(this.enterReady ? 1 : 0)
                .animation({ duration: 520, delay: 80, curve: Curve.EaseOut })

              Text('工况可视 · 告警可达 · 指令可控')
                .fontSize(14)
                .fontColor(TabletTheme.textDim)
                .margin({ top: 8, bottom: 28 })

              Row({ space: 10 }) {
                this.featureChip('实时工况')
                this.featureChip('告警联动')
                this.featureChip('远程控制')
                this.featureChip('历史追溯')
              }
              .opacity(this.enterReady ? 1 : 0)
              .translate({ y: this.enterReady ? 0 : 10 })
              .animation({ duration: 520, delay: 140, curve: Curve.EaseOut })

              Text('登录后进入监控大屏与控制台')
                .fontSize(12)
                .fontColor(TabletTheme.textDim)
                .margin({ top: 36 })
            }
            .width('78%')
            .constraintSize({ maxWidth: 480 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .layoutWeight(6)
        .height('100%')
        .padding({
          left: 40 + this.leftInset,
          right: 28,
          top: this.topInset + 24,
          bottom: 28 + this.bottomInset
        })
        .linearGradient({
          angle: 148,
          colors: [['#000A22', 0], ['#001536', 0.55], ['#062447', 1]]
        })

        // 右侧登录区
        Column() {
          Column({ space: 14 }) {
            Text('欢迎回来')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(TabletTheme.text)
              .width('100%')

            Text('请输入账号密码登录鸿安智联')
              .fontSize(14)
              .fontColor(TabletTheme.textDim)
              .width('100%')
              .margin({ bottom: 10 })

            Text('用户名')
              .fontSize(12)
              .fontColor(TabletTheme.textDim)
              .width('100%')

            TextInput({ placeholder: '请输入用户名', text: this.username })
              .width('100%')
              .height(48)
              .fontColor(TabletTheme.text)
              .placeholderColor('#5E7394')
              .backgroundColor('#071830')
              .border({ width: 1, color: '#1A4A7A' })
              .borderRadius(10)
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => {
                this.username = v
              })

            Text('密码')
              .fontSize(12)
              .fontColor(TabletTheme.textDim)
              .width('100%')
              .margin({ top: 4 })

            TextInput({ placeholder: '请输入密码', text: this.password })
              .width('100%')
              .height(48)
              .type(InputType.Password)
              .fontColor(TabletTheme.text)
              .placeholderColor('#5E7394')
              .backgroundColor('#071830')
              .border({ width: 1, color: '#1A4A7A' })
              .borderRadius(10)
              .padding({ left: 14, right: 14 })
              .onChange((v: string) => {
                this.password = v
              })

            Button(this.loading ? '登录中...' : '登 录')
              .width('100%')
              .height(50)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(TabletTheme.accent)
              .fontColor('#001022')
              .enabled(!this.loading)
              .borderRadius(10)
              .margin({ top: 10 })
              .onClick(() => {
                this.doLogin()
              })

            Text('服务器地址')
              .fontSize(13)
              .fontColor(TabletTheme.accent)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 8 })
              .onClick(() => {
                this.openServerSettings()
              })
          }
          .width('78%')
          .constraintSize({ maxWidth: 420, minWidth: 300 })
          .padding({ left: 28, right: 28, top: 32, bottom: 28 })
          .backgroundColor('#AA0A162E')
          .border({ width: 1, color: '#881E4F7A' })
          .borderRadius(16)
          .opacity(this.enterReady ? 1 : 0)
          .translate({ y: this.enterReady ? 0 : 18 })
          .animation({ duration: 520, delay: 120, curve: Curve.EaseOut })
        }
        .layoutWeight(5)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({
          left: 20,
          right: 36 + this.rightInset,
          top: this.topInset + 24,
          bottom: 28 + this.bottomInset
        })
        .linearGradient({
          angle: 200,
          colors: [['#000D2D', 0], ['#061428', 1]]
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TabletTheme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  featureChip(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor(TabletTheme.accent)
      .padding({ left: 12, right: 12, top: 7, bottom: 7 })
      .backgroundColor('#1400E5FF')
      .border({ width: 1, color: '#4400E5FF' })
      .borderRadius(20)
  }

  @Builder
  serverSettingsOverlay() {
    Column() {
      Column({ space: 14 }) {
        Row() {
          Text('服务器地址')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isTablet ? TabletTheme.text : PhoneTheme.text)
            .layoutWeight(1)
          Text('关闭')
            .fontSize(14)
            .fontColor(this.isTablet ? TabletTheme.accent : PhoneTheme.primary)
            .onClick(() => {
              this.showServerSettings = false
            })
        }
        .width('100%')

        Text('请输入服务器地址')
          .fontSize(12)
          .fontColor(this.isTablet ? TabletTheme.textDim : PhoneTheme.textDim)
          .width('100%')

        if (this.isTablet) {
          TextInput({ text: this.baseUrl, placeholder: '请输入服务器地址' })
            .width('100%')
            .height(44)
            .fontColor(TabletTheme.text)
            .placeholderColor(TabletTheme.textDim)
            .backgroundColor('#071830')
            .border({ width: 1, color: '#1A4A7A' })
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .onChange((v: string) => {
              this.baseUrl = v
            })
        } else {
          TextInput({ text: this.baseUrl, placeholder: '请输入服务器地址' })
            .width('100%')
            .height(48)
            .backgroundColor('#F5F8FC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .onChange((v: string) => {
              this.baseUrl = v
            })
        }

        Button('保存')
          .width('100%')
          .height(44)
          .backgroundColor(this.isTablet ? TabletTheme.accent : PhoneTheme.primary)
          .fontColor(this.isTablet ? '#001022' : Color.White)
          .borderRadius(this.isTablet ? 10 : 12)
          .onClick(() => {
            this.saveServerUrl()
          })
      }
      .width(this.isTablet ? '52%' : '86%')
      .constraintSize({ maxWidth: 480 })
      .padding(22)
      .backgroundColor(this.isTablet ? '#0A162E' : PhoneTheme.card)
      .border(this.isTablet ? { width: 1, color: '#1E4F7A' } : { width: 0 })
      .borderRadius(16)
      .onClick(() => {
        // 阻止冒泡关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isTablet ? '#99000D2D' : '#66000000')
    .onClick(() => {
      this.showServerSettings = false
    })
  }
}
