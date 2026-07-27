import { AnsiColors, AnsiColorsLatte, ChromeColors, ChromeColorsLatte, TerminalColors, TerminalColorsLatte, Sizing, Spacing, Typography, GhosttyDefault } from './ThemeConstants'
import { XtermTheme, CATPPUCCIN_MOCHA_THEME, CATPPUCCIN_LATTE_THEME, TerminalThemeState } from './TerminalTheme'

export enum ColorMode {
  DARK = 0,
  LIGHT = 1,
  SYSTEM = 2
}

export class AppTheme {
  colorMode: ColorMode
  terminal: TerminalThemeState
  terminalColors: TerminalColors | TerminalColorsLatte
  ansiColors: AnsiColors | AnsiColorsLatte
  chrome: ChromeColors | ChromeColorsLatte
  sizing: Sizing
  spacing: Spacing
  typography: Typography
  ghosttyDefault: GhosttyDefault

  constructor(mode: ColorMode) {
    this.colorMode = mode
    this.sizing = new Sizing()
    this.spacing = new Spacing()
    this.typography = new Typography()
    this.ghosttyDefault = new GhosttyDefault()
    if (mode === ColorMode.LIGHT) {
      this.terminalColors = new TerminalColorsLatte()
      this.ansiColors = new AnsiColorsLatte()
      this.chrome = new ChromeColorsLatte()
      this.terminal = new TerminalThemeState(CATPPUCCIN_LATTE_THEME)
    } else {
      this.terminalColors = new TerminalColors()
      this.ansiColors = new AnsiColors()
      this.chrome = new ChromeColors()
      this.terminal = new TerminalThemeState(CATPPUCCIN_MOCHA_THEME)
    }
  }

  isDark(): boolean {
    return this.colorMode === ColorMode.DARK
  }

  background(): string {
    return this.terminalColors.background
  }
}

export class ThemeManager {
  private static instance: ThemeManager | null = null
  private currentTheme: AppTheme
  private listeners: (() => void)[]
  private preferredMode: ColorMode
  private systemIsDark: boolean

  private constructor() {
    this.preferredMode = ColorMode.DARK
    this.systemIsDark = true
    this.currentTheme = new AppTheme(ColorMode.DARK)
    this.listeners = []
  }

  static getInstance(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager()
    }
    return ThemeManager.instance
  }

  getTheme(): AppTheme {
    return this.currentTheme
  }

  setMode(mode: ColorMode): void {
    this.preferredMode = mode
    this.refreshTheme()
  }

  setSystemIsDark(isDark: boolean): void {
    this.systemIsDark = isDark
    if (this.preferredMode === ColorMode.SYSTEM) {
      this.refreshTheme()
    }
  }

  private refreshTheme(): void {
    let effectiveMode: ColorMode = this.preferredMode
    if (this.preferredMode === ColorMode.SYSTEM) {
      effectiveMode = this.systemIsDark ? ColorMode.DARK : ColorMode.LIGHT
    }
    this.currentTheme = new AppTheme(effectiveMode)
    this.notifyListeners()
  }

  onThemeChange(callback: () => void): void {
    this.listeners.push(callback)
  }

  removeThemeChange(callback: () => void): void {
    let idx: number = -1
    for (let i = 0; i < this.listeners.length; i++) {
      if (this.listeners[i] === callback) {
        idx = i
        break
      }
    }
    if (idx >= 0) {
      this.listeners.splice(idx, 1)
    }
  }

  private notifyListeners(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i]()
    }
  }
}
