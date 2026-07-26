import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Logger } from '../common/logger/Logger';

const logger: Logger = new Logger('EntryBackupAbility')

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    logger.info('onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    logger.info('onRestore ok ' + JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}