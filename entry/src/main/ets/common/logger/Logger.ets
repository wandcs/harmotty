import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0001

export class Logger {
  private tag: string

  constructor(tag: string) {
    this.tag = tag
  }

  info(msg: string): void {
    hilog.info(DOMAIN, this.tag, '%{public}s', msg)
  }

  warn(msg: string): void {
    hilog.warn(DOMAIN, this.tag, '%{public}s', msg)
  }

  error(msg: string): void {
    hilog.error(DOMAIN, this.tag, '%{public}s', msg)
  }

  debug(msg: string): void {
    hilog.debug(DOMAIN, this.tag, '%{public}s', msg)
  }
}
