import { describe, it, expect } from '@ohos/hypium'
import { SshKeyManager } from '../main/ets/model/ssh/SshKeyManager'

export default function keySafetyTest() {
  describe('KeySafety', () => {
    it('rejectsSshControlFilesAsKeyNames', 0, () => {
      expect(SshKeyManager.validateKeyName('config') !== null).assertEqual(true)
      expect(SshKeyManager.validateKeyName('config.harmotty.bak') !== null).assertEqual(true)
      expect(SshKeyManager.validateKeyName('known_hosts') !== null).assertEqual(true)
      expect(SshKeyManager.validateKeyName('known_hosts.old') !== null).assertEqual(true)
      expect(SshKeyManager.validateKeyName('authorized_keys') !== null).assertEqual(true)
    })

    it('keepsCustomKeyNamesAvailable', 0, () => {
      expect(SshKeyManager.validateKeyName('deploy-prod')).assertEqual(null)
      expect(SshKeyManager.validateKeyName('work.github')).assertEqual(null)
    })
  })
}
