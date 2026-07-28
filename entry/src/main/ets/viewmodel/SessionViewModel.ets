import { SshClient, SshClientEvent } from '../model/ssh/SshClient'
import util from '@ohos.util'
import { SshConnectOptions } from '../common/types/SshTypes'
import { SshSession, SshSessionState } from '../model/ssh/SshSession'
import { SshKeyManager } from '../model/ssh/SshKeyManager'
import { KeyPairInfo } from '../common/types/SshKeyTypes'
import { BridgeProtocol, BridgeMessage } from '../model/bridge/BridgeProtocol'
import { CommandBarViewModel, CommandParseResult, KeyCommandResult } from './CommandBarViewModel'
import { CommandParser, KeyCommandKind } from '../model/command/CommandParser'
import { KeyCommandService, KeyCommandContext } from '../model/command/KeyCommandService'
import { Logger } from '../common/logger/Logger'
import { FileUtils } from '../common/utils/FileUtils'
import { DurableStateManager } from '../model/persistence/DurableStateManager'
import { TerminalInputAction, TerminalInputActionKind, TerminalInputParser } from '../model/terminal/TerminalInputParser'
import { TerminalMode } from '../common/types/TerminalTypes'
import { ConnectionControl } from '../model/ssh/ConnectionControl'
import { TerminalSurfaceController } from '../model/terminal/TerminalSurfaceController'
import { LocalCommandLine } from '../model/terminal/LocalCommandLine'
import { common } from '@kit.AbilityKit'

export { TerminalMode } from '../common/types/TerminalTypes'

export class SessionViewModel {
  private session: SshSession = new SshSession()
  private sshClient: SshClient = new SshClient()
  private terminalSurface: TerminalSurfaceController | null = null
  private lastCols: number = 80
  private lastRows: number = 24
  private onStateChange: ((state: SshSessionState) => void) | null = null
  private onModeChange: ((mode: TerminalMode) => void) | null = null
  private onTitleChange: ((title: string) => void) | null = null
  private onLocalExit: (() => boolean) | null = null
  private onConfirmKeyDelete: ((name: string, fingerprint: string,
    onConfirm: () => void, onCancel: () => void) => void) | null = null
  private logger: Logger = new Logger('SessionViewModel')

  private mode: TerminalMode = TerminalMode.IDLE
  private commandLine: LocalCommandLine = new LocalCommandLine()
  private passwordBuffer: string = ''
  private hostKeyBuffer: string = ''
  private knownHostsPath: string = ''
  private commandBarVm: CommandBarViewModel = new CommandBarViewModel()
  private heartbeatTimerId: number = -1
  private pendingKeyPath: string = ''
  private pendingKeyPassphrase: string = ''
  private privateKeyAttempted: boolean = false
  private context: common.Context | null = null
  private pendingKeypush: boolean = false
  private perfInputBuffer: string = ''
  private perfPingId: string = ''
  private perfPingStartedMs: number = 0
  private perfOutputTail: string = ''
  private keypushKeyName: string = ''
  private keypushPublicKey: string = ''
  private keypushMarker: string = ''
  private keypushOutputTail: string = ''
  private keypushTimeoutId: number = -1
  private terminalFocused: boolean = false
  private outputObserverDecoder: util.TextDecoder = util.TextDecoder.create('utf-8')

  getSession(): SshSession {
    return this.session
  }

  getSshClient(): SshClient {
    return this.sshClient
  }

  getMode(): TerminalMode {
    return this.mode
  }

  setOnStateChange(callback: (state: SshSessionState) => void): void {
    this.onStateChange = callback
  }

  setOnModeChange(callback: (mode: TerminalMode) => void): void {
    this.onModeChange = callback
  }

  setOnTitleChange(callback: (title: string) => void): void {
    this.onTitleChange = callback
  }

  setOnLocalExit(callback: () => boolean): void {
    this.onLocalExit = callback
  }

  setOnConfirmKeyDelete(
    callback: (name: string, fingerprint: string, onConfirm: () => void, onCancel: () => void) => void
  ): void {
    this.onConfirmKeyDelete = callback
  }

  loadSshConfig(context: common.Context): void {
    this.context = context
    this.knownHostsPath = FileUtils.getSshDir(context) + '/known_hosts'
    this.commandBarVm.loadSshConfig(context)
  }

  bindTerminalSurface(surface: TerminalSurfaceController): void {
    this.terminalSurface = surface
    surface.setOnMessage((msg: BridgeMessage) => {
      this.handleBridgeMessage(msg)
    })
    surface.setOnReady((flushedDetachedOutput: boolean) => {
      this.onBridgeReady(flushedDetachedOutput)
    })
    surface.setOnOutputPauseChange((paused: boolean) => {
      this.applyOutputPause(paused)
    })
  }

  onTerminalSurfaceDetached(): void {
    this.stopHeartbeat()
  }

  private onBridgeReady(flushedDetachedOutput: boolean): void {
    if (this.mode === TerminalMode.IDLE && !flushedDetachedOutput) {
      this.writePrompt()
    }
    this.requestTerminalFit()
    this.applyTerminalFocus()
    this.startHeartbeat()
    this.logger.info(flushedDetachedOutput ?
      'Bridge ready, detached output flushed' : 'Bridge ready without detached output')
  }

  writePrompt(): void {
    this.writeTerminal('\u001b[0m\r\nltty> ')
  }

  writeError(msg: string): void {
    this.writeTerminal('\u001b[0m\r\n\u001b[31m' + msg + '\u001b[0m\r\nltty> ')
  }

  async connect(host: string, port: number, username: string): Promise<void> {
    this.privateKeyAttempted = false
    this.setMode(TerminalMode.CONNECTING)
    this.session.setState(SshSessionState.CONNECTING)
    this.session.setHostname(host)
    this.session.setPort(port)
    this.session.setUsername(username)
    this.notifyStateChange()

    try {
      this.sshClient.onEvent((event: SshClientEvent, data: string) => {
        this.onSshEvent(event, data)
      })
      this.outputObserverDecoder = util.TextDecoder.create('utf-8')
      this.sshClient.onData((data: Uint8Array) => {
        this.onSshData(data)
      })
      let opts: SshConnectOptions = new SshConnectOptions()
      opts.host = host
      opts.port = port
      opts.username = username
      opts.knownHostsPath = this.knownHostsPath
      await this.sshClient.connect(opts)
      this.logger.info('SSH connect initiated: ' + host)
    } catch (e) {
      this.session.setState(SshSessionState.FAILED)
      this.session.setErrorMessage('' + e)
      this.setMode(TerminalMode.IDLE)
      this.releaseDisconnectedFlowControl()
      this.writeError('Connection failed: ' + e)
      this.notifyStateChange()
    }
  }

  async disconnect(): Promise<void> {
    if (this.sshClient.hasActiveSession()) {
      await this.sshClient.disconnect()
    }
    this.session.setState(SshSessionState.DISCONNECTED)
    this.privateKeyAttempted = false
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    this.notifyStateChange()
  }

  async reconnect(): Promise<void> {
    let host: string = this.session.getHostname()
    let port: number = this.session.getPort()
    let username: string = this.session.getUsername()
    let previousClient: SshClient = this.sshClient
    previousClient.onEvent(() => {})
    previousClient.onData(() => {})
    await previousClient.disconnect()
    this.sshClient = new SshClient()
    this.session.setState(SshSessionState.RECONNECTING)
    await this.connect(host, port, username)
  }

  private cancelPendingConnection(): void {
    this.sshClient.disconnect()
    this.passwordBuffer = ''
    this.hostKeyBuffer = ''
    this.pendingKeyPassphrase = ''
    this.privateKeyAttempted = false
    this.clearKeypushState()
    this.session.setState(SshSessionState.DISCONNECTED)
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    this.writeTerminal('^C')
    this.writePrompt()
    this.notifyStateChange()
  }

  requestTerminalFit(): void {
    if (this.terminalSurface !== null) {
      this.terminalSurface.requestFit()
    }
  }

  requestFocus(): void {
    this.terminalFocused = true
    this.applyTerminalFocus()
  }

  requestBlur(): void {
    this.terminalFocused = false
    this.applyTerminalFocus()
  }

  private applyTerminalFocus(): void {
    if (this.terminalSurface !== null) {
      if (this.terminalFocused) {
        this.terminalSurface.focus()
      } else {
        this.terminalSurface.blur()
      }
    }
  }

  applyTerminalTheme(themeJson: string): void {
    if (this.terminalSurface !== null) {
      this.terminalSurface.sendTheme(themeJson)
    }
  }

  private setMode(newMode: TerminalMode): void {
    this.mode = newMode
    if (this.onModeChange !== null) {
      this.onModeChange(newMode)
    }
  }

  private onSshEvent(event: SshClientEvent, data: string): void {
    switch (event) {
      case SshClientEvent.PASSWORD_PROMPT:
        this.session.setState(SshSessionState.AUTHENTICATING)
        this.notifyStateChange()
        if (!this.pendingKeypush && !this.privateKeyAttempted) {
          let key: KeyPairInfo | null = this.resolvePrivateKey()
          if (key !== null) {
            this.privateKeyAttempted = true
            this.tryKeyAuth(key.filePath, key.hasPassphrase)
            return
          }
        }
        this.setMode(TerminalMode.PASSWORD_INPUT)
        this.passwordBuffer = ''
        this.writeTerminal('Password: ')
        break
      case SshClientEvent.HOST_KEY_PROMPT:
        this.hostKeyBuffer = ''
        this.setMode(TerminalMode.HOST_KEY_INPUT)
        this.session.setState(SshSessionState.HOST_VERIFICATION_REQUIRED)
        this.notifyStateChange()
        this.writeTerminal('\r\nThe authenticity of this host cannot be established.\r\n' +
          'Fingerprint: ' + data + '\r\nTrust this host key? Type yes or no: ')
        break
      case SshClientEvent.HOST_KEY_CHANGED:
        this.onSshError('WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED. Fingerprint: ' + data)
        break
      case SshClientEvent.CONNECTED:
        this.setMode(TerminalMode.CONNECTED)
        this.onSshConnected()
        break
      case SshClientEvent.CLOSE:
        this.onSshClose(parseInt(data, 10))
        break
      case SshClientEvent.ERROR:
        this.onSshError(data)
        break
      case SshClientEvent.WARNING:
        this.logger.warn('SSH warning: ' + data)
        break
    }
  }

  private onSshConnected(): void {
    if (this.pendingKeypush) {
      this.executeKeypushCommand()
      return
    }
    this.session.setState(SshSessionState.CONNECTED)
    let connectedTitle: string = this.session.getConnectionTitle()
    this.logger.info('Connected tab title=' + connectedTitle)
    this.session.setHostAlias(connectedTitle)
    this.notifyTitleChange(connectedTitle)
    this.notifyStateChange()
    this.sshClient.resize(this.lastCols, this.lastRows)
    this.applyOutputPause(this.terminalSurface !== null && this.terminalSurface.isOutputPaused())
    this.logger.info('SSH session connected, pty resized to ' +
      this.lastCols.toString() + 'x' + this.lastRows.toString())
  }

  private writeTerminal(data: string): void {
    if (this.terminalSurface !== null) {
      this.terminalSurface.write(data)
    }
  }

  private writeTerminalBytes(data: Uint8Array): void {
    if (this.terminalSurface !== null) {
      this.terminalSurface.writeBytes(data)
    }
  }

  private releaseDisconnectedFlowControl(): void {
    if (this.terminalSurface !== null) {
      this.terminalSurface.releaseDisconnectedFlowControl()
    }
  }

  private applyOutputPause(paused: boolean): void {
    this.sshClient.setOutputPaused(paused)
  }

  private onSshData(data: Uint8Array): void {
    let observedText: string = this.outputObserverDecoder.decodeToString(data, { stream: true })
    this.observePerfOutput(observedText)
    this.observeKeypushOutput(observedText)
    this.writeTerminalBytes(data)
  }

  private observePerfOutput(data: string): void {
    let combined: string = this.perfOutputTail + data
    if (this.perfPingId.length > 0 && combined.indexOf(this.perfPingId) >= 0) {
      let elapsed: number = Date.now() - this.perfPingStartedMs
      this.logger.info('PERF ping id=' + this.perfPingId + ' rttMs=' + elapsed.toString())
      this.perfPingId = ''
      this.perfPingStartedMs = 0
    }
    this.perfOutputTail = combined.length > 256 ? combined.substring(combined.length - 256) : combined
  }

  private observePerfInput(data: string): void {
    for (let i = 0; i < data.length; i++) {
      let ch: string = data.charAt(i)
      if (ch === '\r' || ch === '\n') {
        if (this.perfInputBuffer.startsWith('echo LTTY_PERF_PING_')) {
          this.perfPingId = this.perfInputBuffer.substring(5)
          this.perfPingStartedMs = Date.now()
          this.perfOutputTail = ''
        }
        this.perfInputBuffer = ''
      } else if (ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) < 127) {
        this.perfInputBuffer += ch
        if (this.perfInputBuffer.length > 256) {
          this.perfInputBuffer = this.perfInputBuffer.substring(this.perfInputBuffer.length - 256)
        }
      }
    }
  }

  private onSshClose(exitCode: number): void {
    if (this.pendingKeypush) {
      this.failKeypush('Connection closed before key installation completed.')
      return
    }
    this.pendingKeypush = false
    this.keypushPublicKey = ''
    this.session.setState(SshSessionState.DISCONNECTED)
    this.session.setExitCode(exitCode)
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    this.writeTerminal('\r\n' + ConnectionControl.describeClose(exitCode))
    this.writePrompt()
    this.notifyStateChange()
    this.logger.info('SSH closed, exitCode=' + exitCode.toString())
  }

  private onSshError(errorDetail: string): void {
    if (this.pendingKeypush) {
      this.failKeypush('Key installation failed: ' + errorDetail)
      return
    }
    this.pendingKeypush = false
    this.keypushPublicKey = ''
    this.session.setState(SshSessionState.FAILED)
    this.session.setErrorMessage(errorDetail)
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    this.writeError('SSH error: ' + errorDetail)
    this.notifyStateChange()
  }

  private notifyStateChange(): void {
    if (this.onStateChange !== null) {
      this.onStateChange(this.session.getState())
    }
  }

  private handleBridgeMessage(msg: BridgeMessage): void {
    switch (msg.kind) {
      case BridgeProtocol.KIND_TERMINAL:
        if (msg.channel !== BridgeProtocol.CHANNEL_DATA) {
          break
        }
        this.logger.info('D: ' + msg.payload.length.toString() + ' chars, mode=' + this.mode.toString())
        this.handleTerminalInput(msg.payload)
        break
      case BridgeProtocol.KIND_RESIZE:
        if (msg.channel !== BridgeProtocol.CHANNEL_CONTROL) {
          break
        }
        let dims: number[] = BridgeProtocol.parseResizePayload(msg.payload)
        if (dims.length === 2) {
          this.lastCols = dims[0]
          this.lastRows = dims[1]
          if (this.sshClient.isConnected()) {
            this.sshClient.resize(dims[0], dims[1])
            this.logger.info('Terminal resized: ' + dims[0].toString() + 'x' + dims[1].toString())
          }
        }
        break
      default:
        break
    }
  }

  handleTerminalInput(data: string): void {
    if (ConnectionControl.shouldInterrupt(this.mode, data)) {
      this.cancelPendingConnection()
      return
    }
    if (this.mode === TerminalMode.CONNECTED) {
      this.observePerfInput(data)
      this.sshClient.write(data)
      return
    }

    if (this.mode === TerminalMode.IDLE) {
      this.handleIdleInput(data)
      return
    }

    if (this.mode === TerminalMode.PASSWORD_INPUT) {
      this.handlePasswordInput(data)
      return
    }

    if (this.mode === TerminalMode.HOST_KEY_INPUT) {
      this.handleHostKeyInput(data)
      return
    }

    if (this.mode === TerminalMode.KEY_PASSPHRASE_INPUT) {
      this.handleKeyPassphraseInput(data)
      return
    }

    if (this.mode === TerminalMode.CONNECTING) {
      return
    }
  }

  private handleIdleInput(data: string): void {
    let actions: TerminalInputAction[] = TerminalInputParser.parse(data, true)
    for (let i = 0; i < actions.length; i++) {
      let action: TerminalInputAction = actions[i]
      if (action.kind === TerminalInputActionKind.SUBMIT) {
        this.executeCommandBuffer()
      } else if (action.kind === TerminalInputActionKind.BACKSPACE) {
        if (this.commandLine.backspace() !== null) {
          this.redrawLocalCommandLine()
        }
      } else if (action.kind === TerminalInputActionKind.TAB) {
        this.tabComplete()
      } else if (action.kind === TerminalInputActionKind.HISTORY_PREVIOUS) {
        this.navigateHistory(-1)
      } else if (action.kind === TerminalInputActionKind.HISTORY_NEXT) {
        this.navigateHistory(1)
      } else if (action.kind === TerminalInputActionKind.CURSOR_LEFT) {
        if (this.commandLine.moveLeft()) {
          this.redrawLocalCommandLine()
        }
      } else if (action.kind === TerminalInputActionKind.CURSOR_RIGHT) {
        if (this.commandLine.moveRight()) {
          this.redrawLocalCommandLine()
        }
      } else if (action.kind === TerminalInputActionKind.TEXT) {
        this.commandLine.insert(action.text)
        this.redrawLocalCommandLine()
      }
    }
  }

  private handlePasswordInput(data: string): void {
    this.handleBufferedInput(data, this.passwordBuffer, (v) => { this.passwordBuffer = v }, () => { this.submitPassword() }, '*')
  }

  private handleHostKeyInput(data: string): void {
    this.handleBufferedInput(data, this.hostKeyBuffer, (v) => { this.hostKeyBuffer = v }, () => { this.submitHostKeyDecision() }, '', (c: number) => c < 127)
  }

  private handleKeyPassphraseInput(data: string): void {
    this.handleBufferedInput(data, this.pendingKeyPassphrase, (v) => { this.pendingKeyPassphrase = v }, () => { this.submitKeyPassphrase() }, '*')
  }

  private handleBufferedInput(
    data: string,
    buffer: string,
    setBuffer: (v: string) => void,
    onSubmit: () => void,
    echo: string,
    textFilter?: (code: number) => boolean
  ): void {
    let actions: TerminalInputAction[] = TerminalInputParser.parse(data, false)
    let currentBuffer: string = buffer
    for (let i = 0; i < actions.length; i++) {
      let action: TerminalInputAction = actions[i]
      if (action.kind === TerminalInputActionKind.SUBMIT) {
        onSubmit()
      } else if (action.kind === TerminalInputActionKind.BACKSPACE) {
        if (currentBuffer.length > 0) {
          currentBuffer = currentBuffer.substring(0, currentBuffer.length - 1)
          setBuffer(currentBuffer)
          this.writeTerminal('\b \b')
        }
      } else if (action.kind === TerminalInputActionKind.TEXT) {
        if (textFilter !== undefined && !textFilter(action.text.charCodeAt(0))) { continue }
        currentBuffer += action.text
        setBuffer(currentBuffer)
        this.writeTerminal(echo.length > 0 ? echo : action.text)
      }
    }
  }

  private submitHostKeyDecision(): void {
    if (this.mode !== TerminalMode.HOST_KEY_INPUT) {
      return
    }
    let answer: string = this.hostKeyBuffer.trim().toLowerCase()
    this.hostKeyBuffer = ''
    this.writeTerminal(SessionViewModel.hostKeyDecisionSubmitOutput(answer))
    if (answer !== 'yes' && answer !== 'no') {
      return
    }
    let accepted: boolean = answer === 'yes'
    if (accepted) {
      if (this.context === null) {
        this.sshClient.verifyHostKey(false)
        this.onSshError('Host key could not be retained because the application context is unavailable')
        return
      }
      try {
        DurableStateManager.commitKnownHostLine(this.context, this.sshClient.getPendingKnownHostLine())
      } catch (e) {
        this.sshClient.verifyHostKey(false)
        this.onSshError('Host key could not be retained: ' + e)
        return
      }
    }
    if (this.sshClient.verifyHostKey(accepted) && accepted) {
      this.setMode(TerminalMode.CONNECTING)
      this.session.setState(SshSessionState.CONNECTING)
      this.notifyStateChange()
      return
    }
    if (!accepted) {
      this.session.setState(SshSessionState.FAILED)
      this.setMode(TerminalMode.IDLE)
      this.releaseDisconnectedFlowControl()
      this.writeError('Host key rejected')
      this.notifyStateChange()
    }
  }

  static hostKeyDecisionSubmitOutput(answer: string): string {
    return answer === 'yes' || answer === 'no' ? '\r\n' : '\r\nPlease type yes or no: '
  }

  private executeCommandBuffer(): void {
    let cmd: string = this.commandLine.getText().trim()
    this.commandLine.clear()
    this.writeTerminal('\r\n')

    if (cmd.length === 0) {
      this.writePrompt()
      return
    }

    this.commandBarVm.addToHistory(cmd)
    let parsed: CommandParseResult | KeyCommandResult | null = CommandParser.parseInput(cmd, this.commandBarVm.getSshConfig())
    if (parsed === null) {
      this.writeError("Unknown command. Type 'help' for commands, or use: ssh user@host")
      return
    }
    if (parsed instanceof KeyCommandResult) {
      if (parsed.kind === KeyCommandKind.EXIT) {
        if (this.onLocalExit === null || !this.onLocalExit()) {
          this.writeError('Cannot close this pane until its remote connection is closed.')
        }
        return
      }
      this.executeKeyCommand(parsed)
      return
    }
    let result: CommandParseResult = parsed
    if (!result.isValid) {
      this.writeError(result.errorMessage)
      return
    }

    let host: string = result.host
    let port: number = result.port
    let username: string = result.username
    this.pendingKeyPath = result.identityFile
    this.pendingKeyPassphrase = ''
    this.connect(host, port, username)
  }

  private submitPassword(): void {
    if (this.mode !== TerminalMode.PASSWORD_INPUT) {
      return
    }
    this.writeTerminal('\r\n')
    let pw: string = this.passwordBuffer
    this.passwordBuffer = ''
    if (this.sshClient.authPassword(pw)) {
      this.setMode(TerminalMode.CONNECTING)
      this.session.setState(SshSessionState.CONNECTING)
      this.notifyStateChange()
    }
  }

  private tabComplete(): void {
    this.commandBarVm.setInputText(this.commandLine.getText())
    let matches: string[] = this.commandBarVm.tryTabComplete()
    if (matches.length === 1) {
      let completed: string = this.commandBarVm.applyCompletion(matches[0])
      this.commandLine.setText(completed)
      this.redrawLocalCommandLine()
    } else if (matches.length > 1) {
      this.writeTerminal('\r\n' + matches.join('  ') + '\r\nltty> ' + this.commandLine.getText())
    }
  }

  private navigateHistory(direction: number): void {
    this.commandBarVm.setInputText(this.commandLine.getText())
    let newCmd: string = this.commandBarVm.navigateHistory(direction)
    this.commandLine.setText(newCmd)
    this.redrawLocalCommandLine()
  }

  private redrawLocalCommandLine(): void {
    this.writeTerminal(this.commandLine.renderForTerminal('ltty> '))
  }

  private notifyTitleChange(title: string): void {
    if (this.onTitleChange !== null) {
      this.onTitleChange(title)
    }
  }

  private startHeartbeat(): void {
    if (this.heartbeatTimerId >= 0) {
      return
    }
    this.heartbeatTimerId = setInterval(() => {
      if (this.terminalSurface !== null) {
        this.terminalSurface.ping()
      }
    }, 30000)
  }
  private stopHeartbeat(): void {
    if (this.heartbeatTimerId >= 0) {
      clearInterval(this.heartbeatTimerId)
      this.heartbeatTimerId = -1
    }
  }

  private executeKeyCommand(result: KeyCommandResult): void {
    if (this.context === null) {
      this.writeError('Context not available')
      return
    }
    let ctx: KeyCommandContext = {
      context: this.context,
      sshConfig: this.commandBarVm.getSshConfig(),
      onConnect: (host: string, port: number, username: string) => {
        this.connect(host, port, username)
      },
      setPendingKeypush: (keyPath: string, pubText: string) => {
        this.pendingKeypush = true
        this.keypushKeyName = keyPath
        this.keypushPublicKey = pubText
      },
      writeError: (msg: string) => { this.writeError(msg) },
      writeOutput: (text: string) => { this.writeTerminal(text) },
      confirmKeyDelete: (name: string, fingerprint: string, onConfirm: () => void, onCancel: () => void) => {
        if (this.onConfirmKeyDelete === null) {
          this.writeError('Key deletion confirmation is unavailable.')
          return
        }
        this.onConfirmKeyDelete(name, fingerprint, onConfirm, onCancel)
      }
    }
    KeyCommandService.execute(result, ctx)
  }

  static buildKeypushMarker(): string {
    return '__LTTY_KEYPUSH_' + Date.now().toString()
  }

  static buildKeypushShellCommand(publicKey: string, marker: string): string {
    let safeKey: string = publicKey.replace(/'/g, "'\\''")
    return "mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && " +
      "(grep -qxF -- '" + safeKey + "' ~/.ssh/authorized_keys || printf '%s\\n' '" + safeKey +
      "' >> ~/.ssh/authorized_keys); " +
      "command_status=$?; printf '\\n%s:%s\\n' '" + marker + "' \"$command_status\"\n"
  }

  private executeKeypushCommand(): void {
    this.setMode(TerminalMode.CONNECTED)
    this.session.setState(SshSessionState.CONNECTED)
    this.notifyStateChange()
    this.keypushMarker = SessionViewModel.buildKeypushMarker()
    this.keypushOutputTail = ''
    let cmd: string = SessionViewModel.buildKeypushShellCommand(this.keypushPublicKey, this.keypushMarker)
    this.sshClient.write(cmd)
    this.logger.info('Keypush command sent')
    this.keypushTimeoutId = setTimeout(() => {
      this.completeKeypush(-1)
    }, 15000)
  }

  static parseKeypushMarker(combinedOutput: string, marker: string): number | null {
    let markerIndex: number = combinedOutput.indexOf(marker + ':')
    if (markerIndex < 0) {
      return null
    }
    let statusStart: number = markerIndex + marker.length + 1
    let statusEnd: number = combinedOutput.indexOf('\n', statusStart)
    if (statusEnd < 0) {
      return null
    }
    let statusStr: string = combinedOutput.substring(statusStart, statusEnd).trim()
    let validStatus: RegExp = /^-?\d{1,10}$/
    if (!validStatus.test(statusStr)) {
      return null
    }
    let status: number = parseInt(statusStr, 10)
    if (isNaN(status)) {
      return null
    }
    return status
  }

  private observeKeypushOutput(data: string): void {
    if (!this.pendingKeypush || this.keypushMarker.length === 0) {
      return
    }
    let combined: string = this.keypushOutputTail + data
    let status: number | null = SessionViewModel.parseKeypushMarker(combined, this.keypushMarker)
    if (status !== null) {
      this.completeKeypush(status)
      return
    }
    this.keypushOutputTail = combined.length > 256 ? combined.substring(combined.length - 256) : combined
  }

  private async completeKeypush(status: number): Promise<void> {
    if (!this.pendingKeypush) {
      return
    }
    let username: string = this.session.getUsername()
    let hostname: string = this.session.getHostname()
    let keyPath: string = this.keypushKeyName
    this.clearKeypushState()
    let client: SshClient = this.sshClient
    client.onEvent(() => {})
    client.onData(() => {})
    await client.disconnect()
    this.sshClient = new SshClient()
    this.session.setState(status === 0 ? SshSessionState.DISCONNECTED : SshSessionState.FAILED)
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    if (status === 0) {
      this.writeTerminal('\r\nKey installed. Verify with: ssh ' + username + '@' + hostname +
        ' -i ' + keyPath + '\r\nltty> ')
    } else if (status < 0) {
      this.writeError('Key installation timed out before the server confirmed completion.')
    } else {
      this.writeError('Key installation failed with remote exit status ' + status.toString() + '.')
    }
    this.notifyStateChange()
  }

  private failKeypush(message: string): void {
    this.clearKeypushState()
    this.session.setState(SshSessionState.FAILED)
    this.setMode(TerminalMode.IDLE)
    this.releaseDisconnectedFlowControl()
    this.writeError(message)
    this.notifyStateChange()
  }

  private clearKeypushState(): void {
    if (this.keypushTimeoutId >= 0) {
      clearTimeout(this.keypushTimeoutId)
      this.keypushTimeoutId = -1
    }
    this.pendingKeypush = false
    this.keypushKeyName = ''
    this.keypushPublicKey = ''
    this.keypushMarker = ''
    this.keypushOutputTail = ''
  }

  private resolvePrivateKey(): KeyPairInfo | null {
    if (this.context === null) {
      return null
    }
    if (this.pendingKeyPath.length > 0) {
      return SshKeyManager.findKeyByName(this.context, this.pendingKeyPath)
    }
    return SshKeyManager.findDefaultKey(this.context)
  }

  private tryKeyAuth(keyPath: string, requiresPassphrase: boolean): void {
    if (requiresPassphrase) {
      this.pendingKeyPath = keyPath
      this.pendingKeyPassphrase = ''
      this.setMode(TerminalMode.KEY_PASSPHRASE_INPUT)
      this.writeTerminal('\r\nThe key at ' + keyPath + ' is encrypted.\r\nEnter passphrase: ')
      return
    }
    if (this.sshClient.authPrivateKey(keyPath, '')) {
      this.setMode(TerminalMode.CONNECTING)
      this.notifyStateChange()
    }
  }

  private submitKeyPassphrase(): void {
    if (this.mode !== TerminalMode.KEY_PASSPHRASE_INPUT) {
      return
    }
    this.writeTerminal('\r\n')
    let pass: string = this.pendingKeyPassphrase
    this.pendingKeyPassphrase = ''
    if (this.sshClient.authPrivateKey(this.pendingKeyPath, pass)) {
      this.setMode(TerminalMode.CONNECTING)
      this.notifyStateChange()
    }
  }

}
