import { SshConfig } from '../model/ssh/SshConfig'
import { common } from '@kit.AbilityKit'
import { CommandParser, CommandParseResult, KeyCommandResult, KeyCommandKind } from '../model/command/CommandParser'

export { CommandParseResult, KeyCommandResult, KeyCommandKind } from '../model/command/CommandParser'

export class CommandBarViewModel {
  private inputText: string = ''
  private history: string[] = []
  private historyIndex: number = -1
  private completions: string[] = []
  private sshConfig: SshConfig = new SshConfig()
  private static readonly MAX_HISTORY: number = 100

  setInputText(text: string): void { this.inputText = text }

  loadSshConfig(context: common.Context): void {
    this.sshConfig.load(context)
  }

  getSshConfig(): SshConfig { return this.sshConfig }

  tryTabComplete(): string[] {
    let trimmed: string = this.inputText.trim()
    let hostPrefix: string = ''
    if (this.inputText.startsWith('ssh ')) { hostPrefix = 'ssh ' }
    else if (this.inputText.startsWith('host rm ')) { hostPrefix = 'host rm ' }
    if (hostPrefix.length > 0) {
      let partial: string = this.inputText.substring(hostPrefix.length).trim()
      let aliases: string[] = this.sshConfig.getHostAliases()
      let hostMatches: string[] = []
      for (let i = 0; i < aliases.length; i++) {
        if (aliases[i].startsWith(partial)) { hostMatches.push(hostPrefix + aliases[i]) }
      }
      this.completions = hostMatches
      return hostMatches
    }
    let commands: string[] = ['help', 'ssh', 'ssh-keygen', 'ssh-copy-id', 'key list', 'key import', 'key rm',
      'host list', 'host add', 'host set', 'host rm', 'exit']
    let matches: string[] = []
    for (let i = 0; i < commands.length; i++) {
      if (commands[i].startsWith(trimmed)) { matches.push(commands[i]) }
    }
    this.completions = matches
    return matches
  }

  applyCompletion(completion: string): string {
    this.inputText = completion + ' '
    this.completions = []
    return this.inputText
  }

  navigateHistory(direction: number): string {
    if (this.history.length === 0) { return this.inputText }
    let newIndex: number = this.historyIndex + (direction < 0 ? 1 : -1)
    if (newIndex < -1) { newIndex = -1 }
    if (newIndex >= this.history.length) { newIndex = this.history.length - 1 }
    this.historyIndex = newIndex
    if (this.historyIndex >= 0) { this.inputText = this.history[this.historyIndex] }
    else { this.inputText = '' }
    return this.inputText
  }

  addToHistory(command: string): void {
    if (command.trim().length === 0) { return }
    if (this.history.length > 0 && this.history[0] === command) { return }
    this.history.unshift(command)
    if (this.history.length > CommandBarViewModel.MAX_HISTORY) { this.history.pop() }
    this.historyIndex = -1
  }
}
