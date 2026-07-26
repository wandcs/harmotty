import webview from '@ohos.web.webview'
import { TerminalMode } from '../../common/types/TerminalTypes'

@Component
export struct TerminalPane {
  private webCtrl: webview.WebviewController = new webview.WebviewController()
  @Prop paneBackground: string = '#1E1E2E'
  @Prop focusVeilColor: string = '#11111B'
  @Prop focusVeilOpacity: number = 0.20
  @Prop sessionMode: TerminalMode = TerminalMode.IDLE
  @Prop isFocused: boolean = true
  @Prop paneId: string = ''
  @Prop showCloseButton: boolean = false
  @Prop needsAttention: boolean = false
  @Prop attentionColor: string = '#F9E2AF'
  onWebControllerReady: (ctrl: webview.WebviewController) => void = () => {}
  onPaneDisappear: () => void = () => {}
  onPaneKeyEvent: (event: KeyEvent) => boolean = () => false
  onPaneFocus: () => void = () => {}
  onSecondaryClick: () => void = () => {}
  onClosePane: () => void = () => {}
  onRendererExited: () => void = () => {}
  aboutToDisappear(): void {
    this.onPaneDisappear()
  }

  build() {
    Stack() {
      Web({
        src: $rawfile('terminal.html'),
        controller: this.webCtrl,
        renderMode: RenderMode.ASYNC_RENDER,
        sharedRenderProcessToken: 'harmotty-terminal'
      })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(false)
        .fileAccess(false)
        .onlineImageAccess(false)
        .mixedMode(MixedMode.None)
        .darkMode(WebDarkMode.Off)
        .zoomAccess(false)
        .zoomControlAccess(false)
        .overviewModeAccess(false)
        .backgroundColor(this.paneBackground)
        .onControllerAttached(() => {
        })
        .onPageEnd(() => {
          this.onWebControllerReady(this.webCtrl)
        })
        .onRenderExited(() => {
          this.onRendererExited()
        })
        .onContextMenuShow((event: OnContextMenuShowEvent) => {
          this.onPaneFocus()
          event.result.closeContextMenu()
          return true
        })
        .onInterceptKeyEvent((event: KeyEvent) => {
          return this.onPaneKeyEvent(event)
        })

      if (!this.isFocused) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.focusVeilColor)
          .opacity(this.focusVeilOpacity)
          .transition(TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseOut }))
      }

      if (this.needsAttention) {
        Column()
          .width('100%')
          .height('100%')
          .border({ width: 2, color: this.attentionColor })
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.showCloseButton && this.isFocused) {
        Text('×')
          .fontSize(18)
          .fontColor('#CDD6F4')
          .textAlign(TextAlign.Center)
          .width(30)
          .height(30)
          .backgroundColor('#181825CC')
          .border({ width: 1, color: '#45475A', radius: 6 })
          .position({ x: '100%', y: 8 })
          .translate({ x: -38, y: 0 })
          .focusable(true)
          .accessibilityText('Close active pane')
          .onClick(() => { this.onClosePane() })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.paneBackground)
    .onClick(() => {
      this.onPaneFocus()
    })
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Right && event.action === MouseAction.Release) {
        event.stopPropagation()
        this.onPaneFocus()
        this.onSecondaryClick()
      }
    })
    .onAppear(() => {
      if (this.isFocused) {
        this.onPaneFocus()
      }
    })
  }
}
