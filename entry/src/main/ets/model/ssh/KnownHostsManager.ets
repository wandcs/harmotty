import { common } from '@kit.AbilityKit'
import sshNative from 'libleantty_ssh.so'
import { DurableStateManager } from '../persistence/DurableStateManager'

export class KnownHostRemovalResult {
  target: string = ''
  removed: number = 0
}

export class KnownHostQueryResult {
  target: string = ''
  output: string = ''
  found: number = 0
}

export class KnownHostsManager {
  static formatTarget(host: string, port: number): string {
    return port === 22 ? host : '[' + host + ']:' + port.toString()
  }

  static remove(context: common.Context, host: string, port: number): KnownHostRemovalResult {
    let nativeResult = sshNative.sshRemoveKnownHostEntries(
      DurableStateManager.readKnownHosts(), host, port)
    let result: KnownHostRemovalResult = new KnownHostRemovalResult()
    result.target = KnownHostsManager.formatTarget(host, port)
    result.removed = nativeResult.removed
    if (result.removed > 0) {
      DurableStateManager.commitKnownHostsContent(context, nativeResult.content)
    }
    return result
  }

  static find(host: string, port: number): KnownHostQueryResult {
    let nativeResult = sshNative.sshFindKnownHostEntries(
      DurableStateManager.readKnownHosts(), host, port)
    let result: KnownHostQueryResult = new KnownHostQueryResult()
    result.target = KnownHostsManager.formatTarget(host, port)
    result.output = nativeResult.output
    result.found = nativeResult.found
    return result
  }
}
