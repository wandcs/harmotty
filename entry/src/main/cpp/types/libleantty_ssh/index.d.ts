export declare function sshConnect(
  host: string, port: number, user: string, knownHostsPath: string, connectTimeoutMs: number,
  onData: (data: Uint8Array) => void,
  onClose: (exitCode: string) => void,
  onControl: (event: string) => void
): string
export declare function sshAuthPassword(sessionId: string, password: string): void
export declare function sshAuthPrivateKey(sessionId: string, keyPath: string, passphrase: string): void
export declare function sshVerifyHostKey(sessionId: string, accepted: boolean): void
export declare function sshWrite(sessionId: string, data: string): void
export declare function sshResize(sessionId: string, cols: number, rows: number): void
export declare function sshSetOutputPaused(sessionId: string, paused: boolean): void
export declare function sshDisconnect(sessionId: string): void
export declare function sshGenerateKeyPair(algorithm: string, passphrase: string, outputDir: string, fileName: string, comment: string): string
export declare function sshReadPublicKey(keyPath: string): string
export declare function sshInspectPrivateKey(keyPath: string): string
export declare function sshProtectPrivateKey(keyPath: string): void
