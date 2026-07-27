import webview from '@ohos.web.webview'
import { BridgeMessage, BridgeProtocol } from '../bridge/BridgeProtocol'
import { TerminalBridge } from '../bridge/TerminalBridge'
import { ClipboardManager } from '../clipboard/ClipboardManager'
import { Logger } from '../../common/logger/Logger'
import { TerminalOutputBuffer } from './TerminalOutputBuffer'
import util from '@ohos.util'

export class TerminalSurfaceController {
  private bridge: TerminalBridge | null = null
  private outputBuffer: TerminalOutputBuffer = new TerminalOutputBuffer()
  private onMessageHandler: ((msg: BridgeMessage) => void) | null = null
  private onReadyHandler: ((flushedDetachedOutput: boolean) => void) | null = null
  private onOutputPauseChangeHandler: ((paused: boolean) => void) | null = null
  private onCopyResultHandler: ((success: boolean) => void) | null = null
  private onBellAttentionHandler: (() => void) | null = null
  private onAttentionAcknowledgedHandler: (() => void) | null = null
  private onOpenUrlHandler: ((url: string) => void) | null = null
  private logger: Logger = new Logger('TerminalSurfaceController')
  private textEncoder: util.TextEncoder = new util.TextEncoder()

  setOnMessage(handler: (msg: BridgeMessage) => void): void {
    this.onMessageHandler = handler
  }

  setOnReady(handler: (flushedDetachedOutput: boolean) => void): void {
    this.onReadyHandler = handler
  }

  setOnOutputPauseChange(handler: (paused: boolean) => void): void {
    this.onOutputPauseChangeHandler = handler
  }

  setOnCopyResult(handler: (success: boolean) => void): void {
    this.onCopyResultHandler = handler
  }

  setOnBellAttention(handler: () => void): void {
    this.onBellAttentionHandler = handler
  }

  setOnAttentionAcknowledged(handler: () => void): void {
    this.onAttentionAcknowledgedHandler = handler
  }

  setOnOpenUrl(handler: (url: string) => void): void {
    this.onOpenUrlHandler = handler
  }

  attach(ctrl: webview.WebviewController): void {
    this.detach()
    let detachedChunks: Uint8Array[] = this.outputBuffer.takeDetachedChunks()
    let flushedDetachedOutput: boolean = detachedChunks.length > 0
    let bridge: TerminalBridge = new TerminalBridge(ctrl)
    bridge.setOnMessage((msg: BridgeMessage) => {
      this.handleBridgeMessage(bridge, msg)
    })
    bridge.setOnReady(() => {
      if (this.onReadyHandler !== null) {
        this.onReadyHandler(flushedDetachedOutput)
      }
    })
    bridge.setOnBackpressure((paused: boolean) => {
      let previousPaused: boolean = this.outputBuffer.isOutputPaused()
      this.outputBuffer.setBridgeBackpressured(paused)
      this.notifyOutputPauseChange(previousPaused)
    })
    this.bridge = bridge
    let previousPaused: boolean = this.outputBuffer.isOutputPaused()
    this.outputBuffer.markAttached()
    for (let i = 0; i < detachedChunks.length; i++) {
      bridge.write(detachedChunks[i])
    }
    this.notifyOutputPauseChange(previousPaused)
    bridge.init()
  }

  detach(): void {
    let previousPaused: boolean = this.outputBuffer.isOutputPaused()
    if (this.bridge !== null) {
      this.bridge.destroy()
      this.bridge = null
    }
    this.outputBuffer.markDetached()
    this.notifyOutputPauseChange(previousPaused)
  }

  isAttached(): boolean {
    return this.bridge !== null
  }

  write(data: string): void {
    this.writeBytes(this.textEncoder.encodeInto(data))
  }

  writeBytes(data: Uint8Array): void {
    let previousPaused: boolean = this.outputBuffer.isOutputPaused()
    this.outputBuffer.append(data)
    if (this.bridge !== null) {
      this.bridge.write(data)
    }
    this.notifyOutputPauseChange(previousPaused)
  }

  sendTheme(themeJson: string): void {
    if (this.bridge !== null) {
      this.bridge.sendTheme(themeJson)
    }
  }

  requestFit(): void {
    if (this.bridge !== null) {
      this.bridge.requestFit()
    }
  }

  releaseDisconnectedFlowControl(): void {
    let previousPaused: boolean = this.outputBuffer.isOutputPaused()
    this.outputBuffer.releaseDisconnectedFlowControl()
    this.notifyOutputPauseChange(previousPaused)
  }

  isOutputPaused(): boolean {
    return this.outputBuffer.isOutputPaused()
  }

  focus(): void {
    if (this.bridge !== null) {
      this.bridge.focus()
    }
  }

  blur(): void {
    if (this.bridge !== null) {
      this.bridge.blur()
    }
  }

  clearSelection(): void {
    if (this.bridge !== null) {
      this.bridge.clearSelection()
    }
  }

  setFontSize(fontSize: number): void {
    if (this.bridge !== null) {
      this.bridge.setFontSize(fontSize)
    }
  }

  handleSecondaryAction(): void {
    if (this.bridge !== null) {
      this.bridge.handleSecondaryAction()
    }
  }

  requestCopySelection(): void {
    if (this.bridge !== null) {
      this.bridge.requestCopySelection()
    }
  }

  ping(): void {
    if (this.bridge !== null) {
      this.bridge.ping()
    }
  }

  private handleBridgeMessage(sourceBridge: TerminalBridge, msg: BridgeMessage): void {
    if (msg.direction === BridgeProtocol.DIRECTION_WEB_TO_NATIVE &&
      msg.channel === BridgeProtocol.CHANNEL_CONTROL && msg.kind === BridgeProtocol.KIND_BELL_ATTENTION) {
      if (this.onBellAttentionHandler !== null) {
        this.onBellAttentionHandler()
      }
      return
    }
    if (msg.direction === BridgeProtocol.DIRECTION_WEB_TO_NATIVE &&
      msg.channel === BridgeProtocol.CHANNEL_CONTROL && msg.kind === BridgeProtocol.KIND_ATTENTION_ACKNOWLEDGED) {
      if (this.onAttentionAcknowledgedHandler !== null) {
        this.onAttentionAcknowledgedHandler()
      }
      return
    }
    if (msg.direction === BridgeProtocol.DIRECTION_WEB_TO_NATIVE &&
      msg.channel === BridgeProtocol.CHANNEL_CONTROL && msg.kind === BridgeProtocol.KIND_COPY_SELECTION) {
      if (msg.payload.length === 0) {
        return
      }
      ClipboardManager.writeText(msg.payload).then((success: boolean) => {
        this.logger.info('Clipboard copy success=' + success.toString() +
          ',length=' + msg.payload.length.toString())
        if (success && this.bridge === sourceBridge) {
          sourceBridge.clearSelection()
        }
        if (this.onCopyResultHandler !== null) {
          this.onCopyResultHandler(success)
        }
      })
      return
    }
    if (msg.direction === BridgeProtocol.DIRECTION_WEB_TO_NATIVE &&
      msg.channel === BridgeProtocol.CHANNEL_CONTROL && msg.kind === BridgeProtocol.KIND_CLIPBOARD_WRITE) {
      ClipboardManager.writeText(msg.payload).then((success: boolean) => {
        this.logger.info('OSC 52 clipboard write success=' + success.toString() +
          ',length=' + msg.payload.length.toString())
        if (this.onCopyResultHandler !== null) {
          this.onCopyResultHandler(success)
        }
      })
      return
    }
    if (msg.direction === BridgeProtocol.DIRECTION_WEB_TO_NATIVE &&
      msg.channel === BridgeProtocol.CHANNEL_CONTROL && msg.kind === BridgeProtocol.KIND_OPEN_URL) {
      if (this.onOpenUrlHandler !== null) {
        this.onOpenUrlHandler(msg.payload)
      }
      return
    }
    if (this.onMessageHandler !== null) {
      this.onMessageHandler(msg)
    }
  }

  private notifyOutputPauseChange(previousPaused: boolean): void {
    let paused: boolean = this.outputBuffer.isOutputPaused()
    if (previousPaused === paused) {
      return
    }
    this.logger.info('PERF output paused=' + paused.toString() +
      ',bridge=' + this.outputBuffer.isBridgeBackpressured().toString() +
      ',hidden=' + this.outputBuffer.isDetachedBackpressured().toString())
    if (this.onOutputPauseChangeHandler !== null) {
      this.onOutputPauseChangeHandler(paused)
    }
  }
}
