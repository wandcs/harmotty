import { SshSessionState } from '../../common/types/TerminalTypes'
import { ChromeColors } from '../theme/ThemeConstants'

@Component
export struct PaneHeader {
  @Prop title: string = ''
  @Prop sessionState: SshSessionState = SshSessionState.IDLE
  @Prop visible: boolean = false
  @Prop chromeColors: ChromeColors = new ChromeColors()
  onReconnect: () => void = () => {}
  onClose: () => void = () => {}

  build() {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .fill(this.statusColor())
        .margin({ right: 8 })
      Text(this.title)
        .fontSize(12)
        .fontColor(this.chromeColors.statusText)
        .layoutWeight(1)
      Text('↻')
        .fontSize(14)
        .fontColor(this.chromeColors.tabActiveIndicator)
        .margin({ right: 12 })
        .onClick(() => { this.onReconnect() })
      Text('✕')
        .fontSize(14)
        .fontColor(this.chromeColors.commandBarPlaceholder)
        .onClick(() => { this.onClose() })
    }
    .width('100%')
    .height(32)
    .backgroundColor(this.chromeColors.tabBackground)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  private statusColor(): string {
    if (this.sessionState === SshSessionState.CONNECTED) {
      return this.chromeColors.statusConnected
    }
    if (this.sessionState === SshSessionState.DISCONNECTED || this.sessionState === SshSessionState.FAILED) {
      return this.chromeColors.statusDisconnected
    }
    return this.chromeColors.statusConnecting
  }
}
