import { TabInfo } from '../../common/types/TerminalTypes'
import { ChromeColors } from '../theme/ThemeConstants'
import { ToolMenuButton } from './ToolMenu'

@Component
export struct TabBar {
  @Prop tabs: TabInfo[] = []
  @Prop activeTabIndex: number = 0
  @Prop chromeColors: ChromeColors = new ChromeColors()
  onTabSelect: (index: number) => void = () => {}
  onTabClose: (index: number) => void = () => {}
  onNewTab: () => void = () => {}
  onMenuToggle: () => void = () => {}

  build() {
    Row() {
      ForEach(this.tabs, (tab: TabInfo, index: number) => {
        TabItem({
          tab: tab,
          isActive: index === this.activeTabIndex,
          chromeColors: this.chromeColors,
          onSelect: () => { this.onTabSelect(index) },
          onClose: () => { this.onTabClose(index) }
        })
      }, (tab: TabInfo) => tab.id)
      Text('+')
        .fontSize(13)
        .fontColor(this.chromeColors.commandBarPlaceholder)
        .width(24)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => { this.onNewTab() })
      ToolMenuButton({
        chromeColors: this.chromeColors,
        onToggle: () => { this.onMenuToggle() }
      })
    }
    .width('100%')
    .height(40)
    .backgroundColor(this.chromeColors.tabBarBackground)
    .padding({ left: 12, right: 12 })
  }
}

@Component
export struct TabItem {
  @Prop tab: TabInfo = new TabInfo('', '')
  @Prop isActive: boolean = false
  @Prop chromeColors: ChromeColors = new ChromeColors()
  @State private hovered: boolean = false
  onSelect: () => void = () => {}
  onClose: () => void = () => {}

  build() {
    Row() {
      Text(this.tab.title)
        .fontSize(13)
        .fontColor(this.isActive ? this.chromeColors.commandBarText : this.chromeColors.statusText)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.hovered) {
        Text('\u2715')
          .fontSize(11)
          .fontColor(this.chromeColors.commandBarPlaceholder)
          .width(16)
          .height(16)
          .textAlign(TextAlign.Center)
          .borderRadius(8)
          .onClick(() => { this.onClose() })
      }
    }
    .width(120)
    .height(40)
    .padding({ left: 12, right: 8 })
    .backgroundColor(this.isActive ? this.chromeColors.tabActiveBackground : this.chromeColors.tabBackground)
    .border({ width: { bottom: this.isActive ? 2 : 0 }, color: { bottom: this.chromeColors.tabActiveIndicator } })
    .onClick(() => { this.onSelect() })
    .onHover((isHover: boolean) => { this.hovered = isHover })
  }
}
