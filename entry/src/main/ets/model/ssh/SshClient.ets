import { SshErrorCode, SshError, SshConnectOptions } from '../../common/types/SshTypes'
import { Logger } from '../../common/logger/Logger'
import sshNative from 'libleantty_ssh.so'

export { SshErrorCode, SshError, SshConnectOptions } from '../../common/types/SshTypes'

export enum SshClientEvent {
  PASSWORD_PROMPT = 'PASSWORD_PROMPT',
  HOST_KEY_PROMPT = 'HOST_KEY_PROMPT',
  HOST_KEY_CHANGED = 'HOST_KEY_CHANGED',
  CONNECTED = 'CONNECTED',
  DATA = 'DATA',
  CLOSE = 'CLOSE',
  ERROR = 'ERROR',
  WARNING = 'WARNING'
}

export class SshClient {
  private sessionId: string = ''
  private connected: boolean = false
  private waitingAuth: boolean = false
  private pendingKnownHostLine: string = ''
  private eventCallback: ((event: SshClientEvent, data: string) => void) | null = null
  private dataCallback: ((data: Uint8Array) => void) | null = null
  private logger: Logger = new Logger('SshClient')

  async connect(options: SshConnectOptions): Promise<void> {
    if (this.sessionId.length > 0) {
      this.reportError(new SshError(SshErrorCode.SessionClosed, 'Session already active', '', 'client'))
      return
    }

    try {
      let id: string = sshNative.sshConnect(
        options.host,
        options.port,
        options.username,
        options.knownHostsPath,
        options.connectTimeoutMs,
        (data: Uint8Array) => {
          if (this.dataCallback !== null) {
            this.dataCallback(data)
          }
        },
        (closeResult: string) => {
          let closeError: string | null = SshClient.parseCloseError(closeResult)
          if (closeError !== null) {
            this.handleError('CONNECT:' + closeError)
          } else {
            let exitCode: number = parseInt(closeResult, 10)
            this.handleClose(isNaN(exitCode) ? -1 : exitCode)
          }
        },
        (event: string) => {
          this.handleRustEvent(event)
        }
      )
      this.sessionId = id
      this.logger.info('SSH connect initiated, sessionId=' + id)
    } catch (e) {
      this.logger.error('sshConnect N-API failed: ' + e)
      throw new Error('SSH connect failed: ' + e)
    }
  }

  authPassword(password: string): boolean {
    if (!this.waitingAuth || this.sessionId.length === 0) {
      this.reportError(new SshError(SshErrorCode.SessionClosed, 'Not waiting for password', '', 'client'))
      return false
    }
    try {
      sshNative.sshAuthPassword(this.sessionId, password)
      this.logger.info('Auth password sent')
      return true
    } catch (e) {
      this.logger.error('sshAuthPassword failed: ' + e)
      this.reportError(new SshError(SshErrorCode.Internal, 'Password authentication request failed', '' + e, 'client'))
      return false
    }
  }

  authPrivateKey(keyPath: string, passphrase: string): boolean {
    if (this.sessionId.length === 0) {
      this.reportError(new SshError(SshErrorCode.SessionClosed, 'Session not active', '', 'client'))
      return false
    }
    try {
      sshNative.sshAuthPrivateKey(this.sessionId, keyPath, passphrase)
      this.waitingAuth = true
      this.logger.info('Auth private key sent: ' + keyPath)
      return true
    } catch (e) {
      this.logger.error('sshAuthPrivateKey failed: ' + e)
      this.reportError(new SshError(SshErrorCode.Internal, 'Private key auth request failed', '' + e, 'client'))
      return false
    }
  }

  verifyHostKey(accepted: boolean): boolean {
    if (this.sessionId.length === 0) {
      this.reportError(new SshError(SshErrorCode.SessionClosed, 'Session not active', '', 'client'))
      return false
    }
    try {
      sshNative.sshVerifyHostKey(this.sessionId, accepted)
      this.pendingKnownHostLine = ''
      return true
    } catch (e) {
      this.reportError(new SshError(SshErrorCode.HostKey, 'Host key response failed', '' + e, 'client'))
      return false
    }
  }

  getPendingKnownHostLine(): string {
    return this.pendingKnownHostLine
  }

  write(data: string): void {
    if (!this.connected || this.sessionId.length === 0) {
      this.reportError(new SshError(SshErrorCode.SessionClosed, 'Session not active', '', 'client'))
      return
    }
    try {
      sshNative.sshWrite(this.sessionId, data)
    } catch (e) {
      this.logger.error('sshWrite failed: ' + e)
      this.handleWarning('Write request rejected: ' + e)
    }
  }

  resize(cols: number, rows: number): void {
    if (!this.connected || this.sessionId.length === 0) {
      return
    }
    try {
      sshNative.sshResize(this.sessionId, cols, rows)
    } catch (e) {
      this.logger.error('sshResize failed: ' + e)
      this.handleWarning('Resize request rejected: ' + e)
    }
  }

  setOutputPaused(paused: boolean): void {
    if (!this.connected || this.sessionId.length === 0) {
      return
    }
    try {
      sshNative.sshSetOutputPaused(this.sessionId, paused)
    } catch (e) {
      this.logger.error('sshSetOutputPaused failed: ' + e)
      this.handleWarning('Output flow-control request rejected: ' + e)
    }
  }

  async disconnect(): Promise<void> {
    if (this.sessionId.length === 0) {
      return
    }
    try {
      sshNative.sshDisconnect(this.sessionId)
    } catch (e) {
      this.logger.error('sshDisconnect failed: ' + e)
    }
    this.connected = false
    this.waitingAuth = false
    this.sessionId = ''
  }

  onEvent(callback: (event: SshClientEvent, data: string) => void): void {
    this.eventCallback = callback
  }

  onData(callback: (data: Uint8Array) => void): void {
    this.dataCallback = callback
  }

  isConnected(): boolean {
    return this.connected
  }

  hasActiveSession(): boolean {
    return this.sessionId.length > 0
  }

  isWaitingAuth(): boolean {
    return this.waitingAuth
  }

  static parseCloseError(closeResult: string): string | null {
    if (!closeResult.startsWith('ERROR:')) {
      return null
    }
    let detail: string = closeResult.substring(6).trim()
    return detail.length > 0 ? detail : 'SSH connection ended unexpectedly.'
  }

  private handleRustEvent(event: string): void {
    this.logger.info('rust event: ' + event)
    if (event === 'PASSWORD_PROMPT') {
      this.waitingAuth = true
      this.emitEvent(SshClientEvent.PASSWORD_PROMPT, '')
    } else if (event === 'CONNECTED') {
      this.waitingAuth = false
      this.connected = true
      this.logger.info('SSH connected')
      this.emitEvent(SshClientEvent.CONNECTED, '')
    } else if (event.startsWith('HOST_KEY_PROMPT:')) {
      let payload: string = event.substring(16)
      let separator: number = payload.indexOf('\t')
      if (separator < 1 || separator >= payload.length - 1) {
        this.handleError('HOST_KEY:Invalid host key prompt payload')
        return
      }
      this.pendingKnownHostLine = payload.substring(separator + 1)
      this.emitEvent(SshClientEvent.HOST_KEY_PROMPT, payload.substring(0, separator))
    } else if (event.startsWith('HOST_KEY_CHANGED:')) {
      this.emitEvent(SshClientEvent.HOST_KEY_CHANGED, event.substring(17))
    } else if (event.startsWith('HOST_KEY_ERROR:')) {
      this.handleError('HOST_KEY:' + event.substring(15))
    } else if (event.startsWith('RESIZE_ERROR:')) {
      this.handleWarning(event.substring(13))
    } else if (event.startsWith('OUTPUT_METRICS:')) {
      this.logger.info('PERF rust ' + event.substring(15))
    } else if (event.startsWith('CONNECT:') || event.startsWith('AUTH:') ||
               event.startsWith('KEY_ERROR:') ||
               event.startsWith('CHANNEL:') || event.startsWith('PTY:') ||
               event.startsWith('SHELL:') || event.startsWith('WRITE_ERROR:')) {
      this.handleError(event)
    }
  }

  private emitEvent(event: SshClientEvent, data: string): void {
    if (this.eventCallback !== null) {
      this.eventCallback(event, data)
    }
  }

  private reportError(error: SshError): void {
    this.emitEvent(SshClientEvent.ERROR, error.detail)
  }

  private handleWarning(detail: string): void {
    this.logger.warn('Recoverable SSH warning: ' + detail)
    this.emitEvent(SshClientEvent.WARNING, detail)
  }

  private handleClose(exitCode: number): void {
    this.connected = false
    this.waitingAuth = false
    this.sessionId = ''
    this.emitEvent(SshClientEvent.CLOSE, exitCode.toString())
  }

  private handleError(errorStr: string): void {
    this.connected = false
    this.waitingAuth = false
    this.sessionId = ''
    let code: SshErrorCode = SshErrorCode.Internal
    let detail: string = errorStr
    if (errorStr.startsWith('CONNECT:')) {
      code = SshErrorCode.Network
      detail = errorStr.substring(8)
    } else if (errorStr.startsWith('AUTH:')) {
      code = SshErrorCode.Auth
      detail = errorStr.substring(5)
    } else if (errorStr.startsWith('KEY_ERROR:')) {
      code = SshErrorCode.Auth
      detail = errorStr.substring(10)
    } else if (errorStr.startsWith('CHANNEL:')) {
      code = SshErrorCode.Channel
      detail = errorStr.substring(8)
    } else if (errorStr.startsWith('PTY:')) {
      code = SshErrorCode.Protocol
      detail = errorStr.substring(4)
    } else if (errorStr.startsWith('SHELL:')) {
      code = SshErrorCode.Protocol
      detail = errorStr.substring(6)
    } else if (errorStr.startsWith('HOST_KEY:')) {
      code = SshErrorCode.HostKey
      detail = errorStr.substring(9)
    }
    this.emitEvent(SshClientEvent.ERROR, new SshError(code, detail, detail, 'rust').detail)
  }
}
