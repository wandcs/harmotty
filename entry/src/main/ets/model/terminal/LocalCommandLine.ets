export class LocalCommandLine {
  private text: string = ''
  private cursor: number = 0

  getText(): string {
    return this.text
  }

  getCursor(): number {
    return this.cursor
  }

  setText(text: string): void {
    this.text = text
    this.cursor = text.length
  }

  clear(): void {
    this.text = ''
    this.cursor = 0
  }

  insert(text: string): string {
    let suffix: string = this.text.substring(this.cursor)
    this.text = this.text.substring(0, this.cursor) + text + suffix
    this.cursor += text.length
    return suffix
  }

  backspace(): string | null {
    if (this.cursor === 0) {
      return null
    }
    let suffix: string = this.text.substring(this.cursor)
    this.text = this.text.substring(0, this.cursor - 1) + suffix
    this.cursor--
    return suffix
  }

  moveLeft(): boolean {
    if (this.cursor === 0) {
      return false
    }
    this.cursor--
    return true
  }

  moveRight(): boolean {
    if (this.cursor === this.text.length) {
      return false
    }
    this.cursor++
    return true
  }

  renderForTerminal(prompt: string): string {
    let prefix: string = this.text.substring(0, this.cursor)
    return '\r\u001b[2K' + prompt + this.text + '\r' + prompt + prefix
  }
}
