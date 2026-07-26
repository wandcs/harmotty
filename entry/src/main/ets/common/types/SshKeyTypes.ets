export enum KeyAlgorithm {
  ED25519 = 0,
  RSA4096 = 1
}

export class KeyPairInfo {
  algorithm: KeyAlgorithm
  filePath: string
  pubPath: string
  fingerprint: string
  publicKeyText: string
  hasPassphrase: boolean

  constructor() {
    this.algorithm = KeyAlgorithm.ED25519
    this.filePath = ''
    this.pubPath = ''
    this.fingerprint = ''
    this.publicKeyText = ''
    this.hasPassphrase = false
  }
}

export class KeyGenerationResult {
  privateKey: KeyPairInfo

  constructor() {
    this.privateKey = new KeyPairInfo()
  }
}

export function algorithmToString(algo: KeyAlgorithm): string {
  if (algo === KeyAlgorithm.RSA4096) {
    return 'rsa-4096'
  }
  return 'ed25519'
}

export function algorithmFromString(s: string): KeyAlgorithm {
  if (s === 'rsa-4096' || s === 'rsa' || s === 'rsa4096') {
    return KeyAlgorithm.RSA4096
  }
  return KeyAlgorithm.ED25519
}
