import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PrefStore } from '../store/PrefStore';
import { AppStore } from '../store/AppStore';
import { AppNav } from '../common/AppNav';
import { AlarmNotifyService } from '../service/AlarmNotifyService';
import { AlarmWatchService } from '../service/AlarmWatchService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    PrefStore.init(this.context);
    AlarmNotifyService.init(this.context);
    this.applyWant(want);
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onCreate');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 应用已在后台时，点击通知会走这里
    this.applyWant(want);
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onNewWant');
  }

  private applyWant(want: Want): void {
    try {
      const uri = want.uri ?? ''
      const params = want.parameters
      let target: string = ''
      if (params !== undefined && params !== null) {
        target = `${params['targetPage'] ?? ''}`
      }
      if (uri.indexOf('alarm') >= 0 || target === 'alarm') {
        AppNav.requestAlarmTab()
        hilog.info(DOMAIN, 'SmartPlant', 'navigate to alarm from notification uri=%{public}s', uri)
      }
    } catch (e) {
      hilog.warn(DOMAIN, 'SmartPlant', 'applyWant fail %{public}s', JSON.stringify(e))
    }
  }

  onDestroy(): void {
    AppStore.stopPolling();
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'SmartPlant', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'SmartPlant', 'Succeeded in loading the content.');
      this.applyImmersiveSystemBars(windowStage);
      AlarmNotifyService.requestPermission(this.context);
    });
  }

  /** 全屏 + 透明系统栏；具体内容色由页面按手机/平板主题再设 */
  private applyImmersiveSystemBars(windowStage: window.WindowStage): void {
    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true).catch((e: Error) => {
        hilog.warn(DOMAIN, 'SmartPlant', 'setWindowLayoutFullScreen fail: %{public}s', JSON.stringify(e));
      });
      const props: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: '#1A2332',
        navigationBarColor: '#00000000',
        navigationBarContentColor: '#1A2332'
      };
      mainWindow.setWindowSystemBarProperties(props).catch((e: Error) => {
        hilog.warn(DOMAIN, 'SmartPlant', 'setWindowSystemBarProperties fail: %{public}s', JSON.stringify(e));
      });
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, 'SmartPlant', 'getMainWindow fail: %{public}s', JSON.stringify(e));
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppStore.onEnterForeground();
    AlarmWatchService.stop(this.context);
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    AppStore.isForeground = false;
    AlarmWatchService.start(this.context);
    hilog.info(DOMAIN, 'SmartPlant', '%{public}s', 'Ability onBackground');
  }
}
