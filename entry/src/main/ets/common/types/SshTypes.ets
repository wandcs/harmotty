export enum SshErrorCode {
  Network = 1,
  Auth = 2,
  HostKey = 3,
  Channel = 4,
  Protocol = 5,
  Internal = 6,
  SessionClosed = 7
}

export class SshError extends Error {
  code: SshErrorCode
  detail: string
  layer: string

  constructor(code: SshErrorCode, message: string, detail: string, layer: string) {
    super(message)
    this.code = code
    this.detail = detail
    this.layer = layer
  }
}

export class SshConnectOptions {
  host: string
  port: number
  username: string
  password: string
  privateKeyPath: string
  passphrase: string
  knownHostsPath: string
  connectTimeoutMs: number

  constructor() {
    this.host = ''
    this.port = 22
    this.username = ''
    this.password = ''
    this.privateKeyPath = ''
    this.passphrase = ''
    this.knownHostsPath = ''
    this.connectTimeoutMs = 15000
  }
}
