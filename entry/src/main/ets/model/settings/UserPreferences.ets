import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { Logger } from '../../common/logger/Logger'
import { InteractionPolicy } from '../ui/InteractionPolicy'

const logger: Logger = new Logger('UserPreferences')
const PREFERENCES_NAME: string = 'leantty_settings'
const TERMINAL_FONT_SIZE_KEY: string = 'terminal_font_size'

export class UserPreferences {
  private static store: preferences.Preferences | null = null

  static initialize(context: common.UIAbilityContext): number {
    try {
      UserPreferences.store = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME })
      let storedValue: preferences.ValueType = UserPreferences.store.getSync(
        TERMINAL_FONT_SIZE_KEY, InteractionPolicy.DEFAULT_FONT_SIZE)
      if (typeof storedValue !== 'number') {
        UserPreferences.saveFontSize(InteractionPolicy.DEFAULT_FONT_SIZE)
        return InteractionPolicy.DEFAULT_FONT_SIZE
      }
      let fontSize: number = InteractionPolicy.clampFontSize(storedValue)
      if (fontSize !== storedValue) {
        UserPreferences.saveFontSize(fontSize)
      }
      return fontSize
    } catch (e) {
      logger.warn('Failed to load user preferences: ' + e)
      return InteractionPolicy.DEFAULT_FONT_SIZE
    }
  }

  static saveFontSize(value: number): void {
    if (UserPreferences.store === null) {
      logger.warn('Cannot save terminal font size before preferences initialization')
      return
    }
    try {
      let fontSize: number = InteractionPolicy.clampFontSize(value)
      UserPreferences.store.putSync(TERMINAL_FONT_SIZE_KEY, fontSize)
      UserPreferences.store.flushSync()
    } catch (e) {
      logger.warn('Failed to save terminal font size: ' + e)
    }
  }
}
