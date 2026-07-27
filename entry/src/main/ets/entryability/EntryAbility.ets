import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../view/theme/ThemeManager';
import { Logger } from '../common/logger/Logger';
import { UserPreferences } from '../model/settings/UserPreferences';
import { InteractionPolicy } from '../model/ui/InteractionPolicy';
import webview from '@ohos.web.webview';

const logger: Logger = new Logger('EntryAbility')
const FALLBACK_TITLE_BUTTON_WIDTH: number = 140

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | null = null
  private windowVisibilityChangeHandler: (visible: boolean) => void = (visible: boolean): void => {
    AppStorage.setOrCreate('mainWindowVisible', visible)
    logger.info('Window visibility changed: visible=' + visible.toString())
  }
  private titleButtonRectChangeHandler: (rect: window.TitleButtonRect) => void =
    (rect: window.TitleButtonRect): void => {
      this.publishTitleButtonRect(rect)
      logger.info('Title button rect changed: right=' + rect.right.toString() +
        ', top=' + rect.top.toString() + ', width=' + rect.width.toString() +
        ', height=' + rect.height.toString())
    }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    AppStorage.setOrCreate('pcTitleButtonReservedWidth', FALLBACK_TITLE_BUTTON_WIDTH)
    AppStorage.setOrCreate('mainWindowVisible', true)
    AppStorage.setOrCreate('terminalFontSize', UserPreferences.initialize(this.context))
    AppStorage.setOrCreate('hasActiveSshSession', false)
    AppStorage.setOrCreate('skipNextTerminateConfirmation', false)
    try {
      webview.WebviewController.setRenderProcessMode(webview.RenderProcessMode.SINGLE)
      webview.WebviewController.setWebDestroyMode(webview.WebDestroyMode.FAST_MODE)
      logger.info('ArkWeb configured: renderProcessMode=' +
        webview.WebviewController.getRenderProcessMode().toString() + ', destroyMode=fast')
    } catch (e) {
      logger.error('Failed to configure ArkWeb process lifecycle: ' + e)
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      ThemeManager.getInstance().setSystemIsDark(true);
    } catch (err) {
      logger.error('Failed to set colorMode: ' + err)
    }
    logger.info('Ability onCreate');
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageCreate');
    windowStage.setWindowRectAutoSave(true).then(() => {
      logger.info('Window rect auto-save enabled')
    }).catch((e: Error) => {
      logger.warn('Window rect auto-save is unavailable: ' + e.message)
    })

    windowStage.loadContent('pages/Index', (loadError) => {
      if (loadError.code) {
        logger.error('Failed to load the content: ' + loadError.code + ' ' + loadError.message);
        return;
      }
      logger.info('Succeeded in loading the content.');

      windowStage.getMainWindow((windowError, mainWindow: window.Window) => {
        if (windowError.code) {
          logger.error('Failed to get main window: ' + windowError.code + ' ' + windowError.message);
          return;
        }
        this.mainWindow = mainWindow
        this.validatePcWindowChrome(mainWindow)
      })
    });
  }

  onWindowStageDestroy(): void {
    if (this.mainWindow !== null) {
      try {
        this.mainWindow.off('windowTitleButtonRectChange', this.titleButtonRectChangeHandler)
      } catch (e) {
        logger.warn('Failed to unregister title button rect listener: ' + e)
      }
      try {
        this.mainWindow.off('windowVisibilityChange', this.windowVisibilityChangeHandler)
      } catch (e) {
        logger.warn('Failed to unregister window visibility listener: ' + e)
      }
      this.mainWindow = null
    }
    logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    AppStorage.setOrCreate('mainWindowVisible', true)
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    AppStorage.setOrCreate('mainWindowVisible', false)
    logger.info('Ability onBackground');
  }

  async onPrepareToTerminateAsync(): Promise<boolean> {
    let hasActiveSession: boolean = AppStorage.get<boolean>('hasActiveSshSession') ?? false
    let confirmationSuppressed: boolean =
      AppStorage.get<boolean>('skipNextTerminateConfirmation') ?? false
    AppStorage.setOrCreate('skipNextTerminateConfirmation', false)
    if (!InteractionPolicy.shouldConfirmApplicationClose(hasActiveSession, confirmationSuppressed)) {
      return false
    }
    if (this.mainWindow === null) {
      logger.warn('Application close canceled because the main window is unavailable')
      return true
    }
    try {
      let result = await this.mainWindow.getUIContext().getPromptAction().showDialog({
        title: 'Close active sessions?',
        message: 'Closing LeanTTY will disconnect all active SSH sessions.',
        buttons: [
          { text: 'Cancel', color: '#CDD6F4' },
          { text: 'Close LeanTTY', color: '#F38BA8' }
        ]
      })
      return result.index !== 1
    } catch (e) {
      logger.error('Application close confirmation failed: ' + e)
      return true
    }
  }

  private validatePcWindowChrome(mainWindow: window.Window): void {
    try {
      mainWindow.on('windowVisibilityChange', this.windowVisibilityChangeHandler)
      logger.info('Window visibility listener registered')
    } catch (e) {
      logger.warn('Window visibility listener registration failed: ' + e)
    }

    try {
      logger.info('Window decor before=' + mainWindow.getWindowDecorVisible().toString())
      mainWindow.setWindowDecorVisible(false)
      logger.info('Window decor after=' + mainWindow.getWindowDecorVisible().toString())
    } catch (e) {
      logger.error('setWindowDecorVisible validation failed: ' + e)
    }

    try {
      mainWindow.setWindowDecorHeight(40)
      logger.info('Window decor height=' + mainWindow.getWindowDecorHeight().toString())
    } catch (e) {
      logger.warn('Window decor height validation failed: ' + e)
    }

    try {
      let rect: window.TitleButtonRect = mainWindow.getTitleButtonRect()
      this.publishTitleButtonRect(rect)
      logger.info('Title button rect: right=' + rect.right.toString() +
        ', top=' + rect.top.toString() + ', width=' + rect.width.toString() +
        ', height=' + rect.height.toString())
      mainWindow.on('windowTitleButtonRectChange', this.titleButtonRectChangeHandler)
    } catch (e) {
      logger.warn('Title button rect validation failed: ' + e)
    }
  }

  private publishTitleButtonRect(rect: window.TitleButtonRect): void {
    if (rect.width > 0 && rect.height > 0) {
      AppStorage.setOrCreate('pcTitleButtonReservedWidth', rect.right + rect.width)
    }
  }
}
