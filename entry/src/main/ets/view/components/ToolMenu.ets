import { ChromeColors } from '../theme/ThemeConstants'

export interface MenuItem {
  icon: string
  label: string
  shortcut: string
  enabled: boolean
}

@Component
export struct ToolMenuButton {
  @Prop chromeColors: ChromeColors = new ChromeColors()
  onToggle: () => void = () => {}

  build() {
    Text('▼')
      .fontSize(10)
      .fontColor(this.chromeColors.commandBarPlaceholder)
      .width(24)
      .height(40)
      .textAlign(TextAlign.Center)
      .onClick(() => { this.onToggle() })
  }
}
