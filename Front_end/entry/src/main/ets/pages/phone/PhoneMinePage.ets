import { PhoneTheme } from '../../common/Theme'
import { PrefStore } from '../../store/PrefStore'
import { AuthApi } from '../../service/AuthApi'
import { AppStore } from '../../store/AppStore'
import { SafeAreaUtil } from '../../common/SafeAreaUtil'
import { AlarmNotifyService } from '../../service/AlarmNotifyService'
import { AlarmLiveViewService } from '../../service/AlarmLiveViewService'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'

@Component
export struct PhoneMinePage {
  @Link loggedIn: boolean
  @State topInset: number = 0
  @State username: string = ''
  @State baseUrl: string = ''

  aboutToAppear(): void {
    SafeAreaUtil.resolveTopInset(getContext(this), (vp: number) => {
      this.topInset = vp
    })
    PrefStore.getUsername().then((u: string) => {
      this.username = u
    })
    PrefStore.getBaseUrl().then((u: string) => {
      this.baseUrl = u
    })
  }

  build() {
    Column({ space: 16 }) {
      Text('我的')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(PhoneTheme.text)
        .width('100%')

      Text(`当前用户：${this.username}`)
        .fontSize(14)
        .fontColor(PhoneTheme.text)
        .width('100%')

      Text('系统通知「横幅」默认关闭。请到：设置 → 通知和状态栏 → 鸿安智联 → 打开「横幅」，退到后台才有顶部弹窗。')
        .fontSize(12)
        .fontColor(PhoneTheme.textDim)
        .width('100%')

      Text('未恢复告警会显示在系统「实况窗」。请到：设置 → 通知和状态栏 → 鸿安智联 → 打开「实况窗」。需在 AGC 申请 TIMER 场景实况窗权益，否则创建会失败（错误码 1003500005）。')
        .fontSize(12)
        .fontColor(PhoneTheme.textDim)
        .width('100%')

      Button('重新申请通知权限')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(PhoneTheme.primary)
        .onClick(async () => {
          try {
            const ctx = getContext(this) as common.UIAbilityContext
            await AlarmNotifyService.requestPermission(ctx)
            promptAction.showToast({ message: '已请求通知权限，请再去系统设置打开「横幅」' })
          } catch (_e) {
            promptAction.showToast({ message: '请手动到系统设置中开启通知' })
          }
        })

      Button('检查实况窗开关')
        .width('100%')
        .height(40)
        .fontSize(14)
        .backgroundColor(PhoneTheme.primary)
        .onClick(async () => {
          const on = await AlarmLiveViewService.isEnabled()
          promptAction.showToast({
            message: on ? '系统已允许本应用实况窗' : '未开启：请到系统设置打开「实况窗」'
          })
        })

      Text('服务器地址')
        .fontSize(13)
        .fontColor(PhoneTheme.textDim)
        .width('100%')

      Text('请输入服务器地址')
        .fontSize(12)
        .fontColor(PhoneTheme.textDim)
        .width('100%')

      TextInput({ text: this.baseUrl, placeholder: '请输入服务器地址' })
        .width('100%')
        .height(44)
        .onChange((v: string) => {
          this.baseUrl = v
        })

      Button('保存地址')
        .width('100%')
        .backgroundColor(PhoneTheme.primary)
        .onClick(async () => {
          let url = this.baseUrl.trim()
          if (url.endsWith('/')) {
            url = url.substring(0, url.length - 1)
          }
          await PrefStore.setBaseUrl(url)
          this.baseUrl = await PrefStore.getBaseUrl()
          AppStore.startPolling(true)
          promptAction.showToast({ message: `已保存：${this.baseUrl}` })
        })

      Button('退出登录')
        .width('100%')
        .backgroundColor(PhoneTheme.danger)
        .margin({ top: 24 })
        .onClick(async () => {
          AppStore.stopPolling()
          await AuthApi.logout()
          this.loggedIn = false
        })
    }
    .padding({ left: 16, right: 16, top: this.topInset + 8, bottom: 16 })
    .width('100%')
    .height('100%')
    .backgroundColor(PhoneTheme.bg)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
