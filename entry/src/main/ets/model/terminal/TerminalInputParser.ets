export enum TerminalInputActionKind {
  TEXT = 0,
  SUBMIT = 1,
  BACKSPACE = 2,
  TAB = 3,
  HISTORY_PREVIOUS = 4,
  HISTORY_NEXT = 5,
  CURSOR_LEFT = 6,
  CURSOR_RIGHT = 7
}

export class TerminalInputAction {
  kind: TerminalInputActionKind
  text: string

  constructor(kind: TerminalInputActionKind, text: string = '') {
    this.kind = kind
    this.text = text
  }
}

export class TerminalInputParser {
  static parse(data: string, allowHistory: boolean): TerminalInputAction[] {
    let actions: TerminalInputAction[] = []
    for (let i = 0; i < data.length; i++) {
      let code: number = data.charCodeAt(i)
      if (code === 13) {
        actions.push(new TerminalInputAction(TerminalInputActionKind.SUBMIT))
      } else if (code === 10) {
        continue
      } else if (code === 127 || code === 8) {
        actions.push(new TerminalInputAction(TerminalInputActionKind.BACKSPACE))
      } else if (code === 9) {
        actions.push(new TerminalInputAction(TerminalInputActionKind.TAB))
      } else if (code === 27 && i + 1 < data.length && data.charCodeAt(i + 1) === 91) {
        let finalIndex: number = i + 2
        while (finalIndex < data.length) {
          let finalCode: number = data.charCodeAt(finalIndex)
          if (finalCode >= 64 && finalCode <= 126) {
            break
          }
          finalIndex++
        }
        if (finalIndex >= data.length) {
          i = data.length
          continue
        }
        let finalCode: number = data.charCodeAt(finalIndex)
        let isSimpleArrow: boolean = finalIndex === i + 2
        if (allowHistory && isSimpleArrow && finalCode === 65) {
          actions.push(new TerminalInputAction(TerminalInputActionKind.HISTORY_PREVIOUS))
        } else if (allowHistory && isSimpleArrow && finalCode === 66) {
          actions.push(new TerminalInputAction(TerminalInputActionKind.HISTORY_NEXT))
        } else if (isSimpleArrow && finalCode === 68) {
          actions.push(new TerminalInputAction(TerminalInputActionKind.CURSOR_LEFT))
        } else if (isSimpleArrow && finalCode === 67) {
          actions.push(new TerminalInputAction(TerminalInputActionKind.CURSOR_RIGHT))
        }
        i = finalIndex
      } else if (code >= 32) {
        actions.push(new TerminalInputAction(TerminalInputActionKind.TEXT, data[i]))
      }
    }
    return actions
  }
}
