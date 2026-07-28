import { SshConfig, SshConfigHost } from '../ssh/SshConfig'
import { KeyAlgorithm } from '../../common/types/SshKeyTypes'

export class CommandParseResult {
  isValid: boolean
  host: string
  port: number
  username: string
  isAlias: boolean
  identityFile: string
  errorMessage: string

  constructor() {
    this.isValid = false
    this.host = ''
    this.port = 22
    this.username = ''
    this.isAlias = false
    this.identityFile = ''
    this.errorMessage = ''
  }
}

export enum KeyCommandKind {
  KEYGEN = 0,
  KEYS = 1,
  KEYIMPORT = 2,
  KEYPUB = 3,
  KEYRM = 4,
  HELP = 5,
  KEYPUSH = 6,
  ALIAS_ADD = 7,
  ALIAS_RM = 8,
  ALIAS_LIST = 9,
  EXIT = 10,
  HOST_SET = 11,
  SSH_CONFIG = 12,
  KEYINFO = 13,
  KEYEXPORT = 14
}

export class KeyCommandResult {
  kind: KeyCommandKind
  algorithm: KeyAlgorithm
  keyName: string
  destinationName: string
  sourcePath: string
  sshHost: string
  sshPort: number
  sshUser: string
  errorMessage: string
  legacySyntax: boolean

  constructor() {
    this.kind = KeyCommandKind.KEYS
    this.algorithm = KeyAlgorithm.ED25519
    this.keyName = ''
    this.destinationName = ''
    this.sourcePath = ''
    this.sshHost = ''
    this.sshPort = 22
    this.sshUser = ''
    this.errorMessage = ''
    this.legacySyntax = false
  }
}

export class CommandParser {
  static parseInput(input: string, sshConfig: SshConfig): CommandParseResult | KeyCommandResult | null {
    let trimmed: string = input.trim()
    let words: string[] = trimmed.length > 0 ? trimmed.split(/\s+/) : []
    if (trimmed === '?' || trimmed === '？' || trimmed === '-h' || trimmed === '--help' || words[0] === 'help') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.HELP
      if (words.length > 2) { result.errorMessage = 'Usage: help [<command>]'; return result }
      if (words.length === 2) { result.keyName = words[1] }
      return result
    }
    if (trimmed === 'exit') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.EXIT
      return result
    }
    if (words.length >= 2 && words.length <= 3 && words[words.length - 1] === '--help') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.HELP
      result.keyName = words[0]
      return result
    }
    if (words[0] === 'ssh' && words[1] === '-G') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.SSH_CONFIG
      if (words.length !== 3) { result.errorMessage = 'Usage: ssh -G <host-name>'; return result }
      result.keyName = words[2]
      return result
    }
    if (words[0] === 'ssh-keygen') {
      return CommandParser.parseSshKeygen(trimmed)
    }
    if (words[0] === 'ssh-copy-id') {
      return CommandParser.parseSshCopyId(trimmed)
    }
    if (trimmed.startsWith('ssh ') || trimmed.startsWith('ssh@') || trimmed.length === 0) {
      return CommandParser.parseCommand(trimmed, sshConfig)
    }

    if (trimmed === 'key list' || trimmed === 'keys') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.KEYS
      return result
    }
    if (words[0] === 'key' && words[1] === 'show') {
      return CommandParser.parseKeyShow(trimmed)
    }
    if (words[0] === 'key' && words[1] === 'rm') {
      return CommandParser.parseKeyRm(trimmed)
    }
    if (words[0] === 'key' && words[1] === 'import') {
      return CommandParser.parseKeyImport(trimmed)
    }
    if (words[0] === 'key' && words[1] === 'export') {
      return CommandParser.parseKeyExport(trimmed)
    }

    if ((words[0] === 'host' || words[0] === 'alias') && (words[1] === 'add' || words[1] === 'set')) {
      let result: KeyCommandResult = CommandParser.parseAliasAdd(trimmed)
      if (words[0] === 'host' && words[1] === 'set') { result.kind = KeyCommandKind.HOST_SET }
      result.legacySyntax = words[0] === 'alias'
      return result
    }
    if ((words[0] === 'host' || words[0] === 'alias') && words[1] === 'rm') {
      let result: KeyCommandResult = CommandParser.parseAliasRm(trimmed)
      result.legacySyntax = words[0] === 'alias'
      return result
    }
    if (trimmed === 'host list' || trimmed === 'host' || trimmed === 'alias list' || trimmed === 'alias') {
      let result: KeyCommandResult = new KeyCommandResult()
      result.kind = KeyCommandKind.ALIAS_LIST
      result.legacySyntax = words[0] === 'alias'
      return result
    }

    if (trimmed === 'ssh') {
      return CommandParser.parseCommand(trimmed, sshConfig)
    }
    return null
  }

  static parseCommand(input: string, sshConfig: SshConfig): CommandParseResult {
    let result: CommandParseResult = new CommandParseResult()
    let trimmed: string = input.trim()
    if (trimmed.length === 0) {
      result.errorMessage = 'Usage: ssh <user>@<host>'
      return result
    }
    let argText: string = trimmed
    if (trimmed.startsWith('ssh ')) {
      argText = trimmed.substring(4).trim()
    }
    if (argText.length === 0) {
      result.errorMessage = 'Usage: ssh <user>@<host> or ssh <host-name>'
      return result
    }

    let args: string[] = argText.split(/\s+/)
    let target: string = ''
    let explicitPort: number = 0
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '-p') {
        if (i + 1 >= args.length) { result.errorMessage = 'Missing port after -p'; return result }
        explicitPort = parseInt(args[i + 1], 10)
        if (isNaN(explicitPort) || explicitPort < 1 || explicitPort > 65535) { result.errorMessage = 'Port must be between 1 and 65535'; return result }
        i++
      } else if (args[i] === '-i') {
        if (i + 1 >= args.length) { result.errorMessage = 'Missing identity file after -i'; return result }
        result.identityFile = args[i + 1]
        i++
      } else if (args[i].startsWith('-')) {
        result.errorMessage = 'Unsupported SSH option: ' + args[i]; return result
      } else if (target.length === 0) {
        target = args[i]
      } else {
        result.errorMessage = 'Unexpected SSH argument: ' + args[i]; return result
      }
    }
    if (target.length === 0) { result.errorMessage = 'Missing SSH host'; return result }

    let host: SshConfigHost | null = sshConfig.findHost(target)
    if (host !== null) {
      if (host.user.length === 0) { result.errorMessage = 'SSH alias must define User: ' + target; return result }
      result.isValid = true
      result.host = host.hostname
      result.port = explicitPort > 0 ? explicitPort : host.port
      result.username = host.user
      if (result.identityFile.length === 0) { result.identityFile = host.identityFile }
      result.isAlias = true
      return result
    }

    let atIdx: number = target.lastIndexOf('@')
    if (atIdx <= 0) { result.errorMessage = 'Username required'; return result }
    result.username = target.substring(0, atIdx)
    let hostPort: string = target.substring(atIdx + 1)
    CommandParser.parseHostPort(hostPort, result)
    if (explicitPort > 0) { result.port = explicitPort }
    result.isValid = result.username.length > 0 && result.host.length > 0
    if (!result.isValid) { result.errorMessage = 'Invalid SSH target' }
    return result
  }

  private static parseHostPort(hostPort: string, result: CommandParseResult): void {
    if (hostPort.startsWith('[')) {
      let closingBracket: number = hostPort.indexOf(']')
      if (closingBracket <= 1) { result.errorMessage = 'Invalid bracketed IPv6 hostname'; return }
      result.host = hostPort.substring(1, closingBracket)
      if (closingBracket + 1 < hostPort.length && hostPort[closingBracket + 1] === ':') {
        let p: number = parseInt(hostPort.substring(closingBracket + 2), 10)
        if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'Port 1-65535'; return }
        result.port = p
      }
    } else {
      let firstColon: number = hostPort.indexOf(':')
      let lastColon: number = hostPort.lastIndexOf(':')
      if (firstColon > 0 && firstColon === lastColon) {
        result.host = hostPort.substring(0, firstColon)
        let p: number = parseInt(hostPort.substring(firstColon + 1), 10)
        if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'Port 1-65535'; return }
        result.port = p
      } else {
        result.host = hostPort
      }
    }
  }

  static parseSshKeygen(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYGEN
    let parts: string[] = input.split(/\s+/)
    let publicMode: boolean = false
    let fingerprintMode: boolean = false
    let i: number = 1
    while (i < parts.length) {
      if (parts[i] === '-t') {
        if (i + 1 >= parts.length) { result.errorMessage = 'ssh-keygen: missing type after -t'; return result }
        let keyType: string = parts[i + 1].toLowerCase()
        if (keyType === 'ed25519') { result.algorithm = KeyAlgorithm.ED25519 }
        else if (keyType === 'rsa' || keyType === 'rsa4096' || keyType === 'rsa-4096') {
          result.algorithm = KeyAlgorithm.RSA4096
        } else { result.errorMessage = 'ssh-keygen: unsupported key type ' + parts[i + 1]; return result }
        i += 1
      } else if (parts[i] === '-y') {
        publicMode = true
      } else if (parts[i] === '-l') {
        fingerprintMode = true
      } else if (parts[i] === '-f') {
        if (i + 1 >= parts.length) { result.errorMessage = 'ssh-keygen: missing filename after -f'; return result }
        result.keyName = parts[i + 1]; i += 1
      } else if (parts[i] === '-C') {
        if (i + 1 >= parts.length) { result.errorMessage = 'ssh-keygen: missing comment after -C'; return result }
        result.sourcePath = parts[i + 1]; i += 1
      } else if (parts[i].startsWith('-')) {
        result.errorMessage = 'ssh-keygen: unknown option ' + parts[i]; return result
      }
      i += 1
    }
    if (publicMode && fingerprintMode) {
      result.errorMessage = 'ssh-keygen: -y and -l cannot be used together'
    } else if (publicMode || fingerprintMode) {
      if (result.keyName.length === 0) {
        result.errorMessage = 'ssh-keygen: -f <identity> is required with -y or -l'
      } else {
        result.kind = publicMode ? KeyCommandKind.KEYPUB : KeyCommandKind.KEYINFO
      }
    }
    return result
  }

  static parseSshCopyId(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYPUSH
    let parts: string[] = input.split(/\s+/)
    let i: number = 1
    while (i < parts.length) {
      if (parts[i] === '-i') {
        if (i + 1 >= parts.length) { result.errorMessage = 'ssh-copy-id: missing key name after -i'; return result }
        result.keyName = parts[i + 1]; i += 1
      } else if (parts[i] === '-p') {
        if (i + 1 >= parts.length) { result.errorMessage = 'ssh-copy-id: missing port after -p'; return result }
        let p: number = parseInt(parts[i + 1], 10)
        if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'ssh-copy-id: port 1-65535'; return result }
        result.sshPort = p; i += 1
      } else if (parts[i].startsWith('-')) {
        result.errorMessage = 'ssh-copy-id: unknown option ' + parts[i]; return result
      } else {
        let target: string = parts[i]
        let atIdx: number = target.lastIndexOf('@')
        if (atIdx <= 0) { result.errorMessage = 'ssh-copy-id: expected user@host'; return result }
        result.sshUser = target.substring(0, atIdx)
        let hostPort: string = target.substring(atIdx + 1)
        if (hostPort.startsWith('[')) {
          let closing: number = hostPort.indexOf(']')
          if (closing <= 1) { result.errorMessage = 'ssh-copy-id: invalid IPv6'; return result }
          result.sshHost = hostPort.substring(1, closing)
          if (closing + 1 < hostPort.length && hostPort[closing + 1] === ':') {
            let p: number = parseInt(hostPort.substring(closing + 2), 10)
            if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'ssh-copy-id: port 1-65535'; return result }
            result.sshPort = p
          }
        } else {
          let colonIdx: number = hostPort.indexOf(':')
          if (colonIdx > 0 && hostPort.lastIndexOf(':') === colonIdx) {
            result.sshHost = hostPort.substring(0, colonIdx)
            let p: number = parseInt(hostPort.substring(colonIdx + 1), 10)
            if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'ssh-copy-id: port 1-65535'; return result }
            result.sshPort = p
          } else { result.sshHost = hostPort }
        }
      }
      i += 1
    }
    if (result.keyName.length === 0) { result.errorMessage = 'ssh-copy-id: -i <key-name> is required' }
    if (result.sshHost.length === 0) { result.errorMessage = 'ssh-copy-id: target <user>@<host> is required' }
    return result
  }

  static parseKeyShow(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYPUB
    result.sourcePath = 'legacy-key-show'
    let parts: string[] = input.split(/\s+/)
    if (parts.length !== 3) { result.errorMessage = 'Usage: key show <key-name>'; return result }
    result.keyName = parts[2]
    return result
  }

  static parseKeyRm(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYRM
    let parts: string[] = input.split(/\s+/)
    if (parts.length !== 3) { result.errorMessage = 'Usage: key rm <key-name>'; return result }
    result.keyName = parts[2]
    return result
  }

  static parseKeyImport(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYIMPORT
    let parts: string[] = input.split(/\s+/)
    if (parts.length < 3 || parts.length > 4) {
      result.errorMessage = 'Usage: key import <path> [<key-name>]'
      return result
    }
    result.sourcePath = parts[2]
    if (parts.length === 4) { result.keyName = parts[3] }
    else {
      let normalizedPath: string = parts[2].replace(/\\/g, '/')
      let lastSlash: number = normalizedPath.lastIndexOf('/')
      result.keyName = lastSlash >= 0 ? normalizedPath.substring(lastSlash + 1) : normalizedPath
    }
    return result
  }

  static parseKeyExport(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.KEYEXPORT
    let parts: string[] = input.split(/\s+/)
    if (parts.length < 3 || parts.length > 4) {
      result.errorMessage = 'Usage: key export <key-name> [<file-name>]'
      return result
    }
    result.keyName = parts[2]
    result.destinationName = parts.length === 4 ? parts[3] : result.keyName
    return result
  }

  static parseAliasAdd(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.ALIAS_ADD
    let parts: string[] = input.split(/\s+/)
    if (parts.length !== 4) {
      result.errorMessage = 'Usage: host add <host-name> <user>@<host>[:<port>]'
      return result
    }
    result.keyName = parts[2]
    let target: string = parts[3]
    let atIdx: number = target.lastIndexOf('@')
    if (atIdx <= 0) {
      result.errorMessage = 'Usage: host add <host-name> <user>@<host>[:<port>]'
      return result
    }
    result.sshUser = target.substring(0, atIdx)
    let hostPort: string = target.substring(atIdx + 1)
    let colonIdx: number = hostPort.indexOf(':')
    if (colonIdx > 0 && hostPort.lastIndexOf(':') === colonIdx) {
      result.sshHost = hostPort.substring(0, colonIdx)
      let p: number = parseInt(hostPort.substring(colonIdx + 1), 10)
      if (isNaN(p) || p < 1 || p > 65535) { result.errorMessage = 'Port 1-65535'; return result }
      result.sshPort = p
    } else { result.sshHost = hostPort }
    return result
  }

  static parseAliasRm(input: string): KeyCommandResult {
    let result: KeyCommandResult = new KeyCommandResult()
    result.kind = KeyCommandKind.ALIAS_RM
    let parts: string[] = input.split(/\s+/)
    if (parts.length !== 3) { result.errorMessage = 'Usage: host rm <host-name>'; return result }
    result.keyName = parts[2]
    return result
  }
}
