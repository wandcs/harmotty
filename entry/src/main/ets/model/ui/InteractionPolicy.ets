export class InteractionPolicy {
  static readonly DEFAULT_FONT_SIZE: number = 16
  static readonly MIN_FONT_SIZE: number = 8
  static readonly MAX_FONT_SIZE: number = 48
  static readonly MIN_SPLIT_RATIO: number = 0.2
  static readonly MAX_SPLIT_RATIO: number = 0.8

  static clampFontSize(value: number): number {
    return Math.max(InteractionPolicy.MIN_FONT_SIZE,
      Math.min(InteractionPolicy.MAX_FONT_SIZE, value))
  }

  static clampSplitRatio(value: number): number {
    return Math.max(InteractionPolicy.MIN_SPLIT_RATIO,
      Math.min(InteractionPolicy.MAX_SPLIT_RATIO, value))
  }

  static warmTabAfterSwitch(currentTabId: string): string {
    return currentTabId
  }

  static evictedWarmTab(currentTabId: string, targetTabId: string,
    previousWarmTabId: string): string {
    if (previousWarmTabId.length > 0 && previousWarmTabId !== targetTabId &&
      previousWarmTabId !== currentTabId) {
      return previousWarmTabId
    }
    return ''
  }

  static shouldMountTab(isActiveTab: boolean, isWarmTab: boolean,
    hasActiveSession: boolean, isWindowVisible: boolean = true): boolean {
    return hasActiveSession || (isWindowVisible && (isActiveTab || isWarmTab))
  }

  static shouldDetachTabOnEviction(hasActiveSession: boolean): boolean {
    return !hasActiveSession
  }
}
