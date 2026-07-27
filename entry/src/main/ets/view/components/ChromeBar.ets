import { TabInfo, SshSessionState } from '../../common/types/TerminalTypes'
import { ChromeColors } from '../theme/ThemeConstants'

@Component
export struct ChromeBar {
  @Prop tabs: TabInfo[] = []
  @Prop activeTabIndex: number = 0
  @Prop chromeColors: ChromeColors = new ChromeColors()
  @Prop titleButtonReservedWidth: number = 140
  onTabSelect: (index: number) => void = () => {}
  onTabClose: (index: number) => void = () => {}
  onNewTab: () => void = () => {}
  onMenuToggle: () => void = () => {}
  private tabScroller: Scroller = new Scroller()
  private lastScrolledTabId: string = ''

  onDidBuild(): void {
    if (this.activeTabIndex < 0 || this.activeTabIndex >= this.tabs.length) {
      return
    }
    let activeId: string = this.tabs[this.activeTabIndex].id
    if (activeId === this.lastScrolledTabId) {
      return
    }
    this.lastScrolledTabId = activeId
    setTimeout(() => {
      this.tabScroller.scrollTo({
        xOffset: Math.max(0, this.activeTabIndex * 176 - 176),
        yOffset: 0,
        animation: { duration: 160, curve: Curve.EaseOut }
      })
    }, 0)
  }

  private tabViewportWidth(): number {
    return 12 + this.tabs.length * 176
  }

  private tabState(tab: TabInfo): SshSessionState {
    for (let i = 0; i < tab.panes.length; i++) {
      if (tab.panes[i].id === tab.activePaneId) {
        return tab.panes[i].state
      }
    }
    return SshSessionState.IDLE
  }

  private tabNeedsAttention(tab: TabInfo): boolean {
    for (let i = 0; i < tab.panes.length; i++) {
      if (tab.panes[i].needsAttention) {
        return true
      }
    }
    return false
  }

  private tabRenderKey(tab: TabInfo): string {
    return tab.id + ':' + tab.title + ':' + (this.tabNeedsAttention(tab) ? 'attention' : 'normal')
  }

  build() {
    Row() {
      Scroll(this.tabScroller) {
        Row() {
          ForEach(this.tabs, (tab: TabInfo, index: number) => {
            ChromeTab({
              title: tab.title,
              isActive: index === this.activeTabIndex,
              sessionState: this.tabState(tab),
              hasAttention: this.tabNeedsAttention(tab),
              chromeColors: this.chromeColors,
              onSelect: () => { this.onTabSelect(index) },
              onClose: () => { this.onTabClose(index) }
            })
          }, (tab: TabInfo) => this.tabRenderKey(tab))
        }
        .padding({ left: 12 })
      }
      .align(Alignment.TopStart)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width(this.tabViewportWidth())
      .constraintSize({ maxWidth: '70%' })
      .height(40)

      ChromeButton({
        symbol: '+',
        chromeColors: this.chromeColors,
        onTap: () => { this.onNewTab() }
      })
        .margin({ left: 4 })

      Blank()
        .layoutWeight(1)
        .constraintSize({ minWidth: 96 })
        .height(40)

      MoreButton({
        chromeColors: this.chromeColors,
        onTap: () => { this.onMenuToggle() }
      })
        .margin({ right: 8 })
    }
    .width('100%')
    .height(40)
    .padding({ right: this.titleButtonReservedWidth })
    .backgroundColor(this.chromeColors.tabBackground)
  }
}

@Component
struct ChromeTab {
  @Prop title: string = 'htty'
  @Prop isActive: boolean = false
  @Prop sessionState: SshSessionState = SshSessionState.IDLE
  @Prop hasAttention: boolean = false
  @Prop chromeColors: ChromeColors = new ChromeColors()
  @State hovered: boolean = false
  onSelect: () => void = () => {}
  onClose: () => void = () => {}

  private indicatorColor(): string {
    if (this.sessionState === SshSessionState.CONNECTED) {
      return this.chromeColors.statusConnected
    }
    if (this.sessionState === SshSessionState.CONNECTING || this.sessionState === SshSessionState.RECONNECTING ||
      this.sessionState === SshSessionState.AUTHENTICATING || this.sessionState === SshSessionState.HOST_VERIFICATION_REQUIRED) {
      return this.chromeColors.statusConnecting
    }
    if (this.sessionState === SshSessionState.FAILED) {
      return this.chromeColors.statusDisconnected
    }
    return this.chromeColors.commandBarPlaceholder
  }

  private surfaceColor(): string {
    if (this.isActive) {
      return this.chromeColors.tabActiveBackground
    }
    return this.hovered ? this.chromeColors.commandBarBorder : '#00000000'
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row()
        .width(172)
        .height(this.isActive ? 37 : 32)
        .margin({ top: 4 })
        .backgroundColor(this.surfaceColor())
        .borderRadius({
          topLeft: 8,
          topRight: 8,
          bottomLeft: this.isActive ? 0 : 8,
          bottomRight: this.isActive ? 0 : 8
        })
        .animation({ duration: 100, curve: Curve.EaseOut })

      Row() {
        Circle()
          .width(6)
          .height(6)
          .fill(this.indicatorColor())
          .opacity(this.isActive ? 1 : 0.55)
          .margin({ right: 6 })
        Text(this.title)
          .fontSize(13)
          .fontColor(this.isActive ? this.chromeColors.commandBarText : this.chromeColors.statusText)
          .fontWeight(this.isActive ? FontWeight.Medium : FontWeight.Regular)
          .opacity(this.isActive || this.hovered ? 1 : 0.72)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.hasAttention) {
          Text('●')
            .fontSize(10)
            .fontColor(this.chromeColors.statusConnecting)
            .width(16)
            .textAlign(TextAlign.Center)
            .accessibilityText('Terminal attention requested')
        }
        if (this.isActive || this.hovered) {
          Text('\u2715')
            .fontSize(10)
            .fontColor(this.hovered ? this.chromeColors.statusText : this.chromeColors.commandBarPlaceholder)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(8)
            .focusable(true)
            .accessibilityText('Close tab ' + this.title)
            .onClick(() => { this.onClose() })
        }
      }
      .width(172)
      .height(32)
      .position({ x: 0, y: 4 })
      .padding({ left: 12, right: 8 })
    }
    .width(172)
    .height(40)
    .margin({ right: 4 })
    .accessibilityDescription(this.title)
    .accessibilityText((this.isActive ? 'Active tab, ' : 'Tab, ') + this.title +
      (this.hasAttention ? ', attention requested' : ''))
    .onClick(() => { this.onSelect() })
    .onHover((isHover: boolean) => { this.hovered = isHover })
  }
}

@Component
struct ChromeButton {
  @Prop symbol: string = ''
  @Prop chromeColors: ChromeColors = new ChromeColors()
  @State hovered: boolean = false
  onTap: () => void = () => {}

  build() {
    Text(this.symbol)
      .fontSize(13)
      .fontColor(this.chromeColors.commandBarPlaceholder)
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(6)
      .backgroundColor(this.hovered ? this.chromeColors.commandBarBorder : '#00000000')
      .focusable(true)
      .accessibilityText('New tab')
      .onClick(() => { this.onTap() })
      .onHover((isHover: boolean) => { this.hovered = isHover })
  }
}

@Component
struct MoreButton {
  @Prop chromeColors: ChromeColors = new ChromeColors()
  @State hovered: boolean = false
  onTap: () => void = () => {}

  build() {
    Stack() {
      Column() {
        Row() {
          Circle()
            .width(3)
            .height(3)
            .fill(this.chromeColors.commandBarPlaceholder)
            .margin({ right: 4 })
          Circle()
            .width(3)
            .height(3)
            .fill(this.chromeColors.commandBarPlaceholder)
        }
        .margin({ bottom: 4 })
        Row() {
          Circle()
            .width(3)
            .height(3)
            .fill(this.chromeColors.commandBarPlaceholder)
            .margin({ right: 4 })
          Circle()
            .width(3)
            .height(3)
            .fill(this.chromeColors.commandBarPlaceholder)
        }
      }
    }
    .width(32)
    .height(32)
    .borderRadius(6)
    .backgroundColor(this.hovered ? this.chromeColors.commandBarBorder : '#00000000')
    .focusable(true)
    .accessibilityText('Open terminal menu')
    .onClick(() => { this.onTap() })
    .onHover((isHover: boolean) => { this.hovered = isHover })
  }
}
