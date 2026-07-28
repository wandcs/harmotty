import { describe, it, expect } from '@ohos/hypium'
import { CommandParser, CommandParseResult, KeyCommandKind, KeyCommandResult } from '../main/ets/model/command/CommandParser'
import { SshConfig } from '../main/ets/model/ssh/SshConfig'
import { SshClient } from '../main/ets/model/ssh/SshClient'
import { BridgeMessage, BridgeProtocol } from '../main/ets/model/bridge/BridgeProtocol'
import { InteractionPolicy } from '../main/ets/model/ui/InteractionPolicy'
import { KeyCodeMap } from '../main/ets/common/constants/KeyCodeMap'
import { TerminalOutputBuffer } from '../main/ets/model/terminal/TerminalOutputBuffer'
import {
  TerminalInputAction,
  TerminalInputActionKind,
  TerminalInputParser
} from '../main/ets/model/terminal/TerminalInputParser'
import { LocalCommandLine } from '../main/ets/model/terminal/LocalCommandLine'
import { SessionViewModel } from '../main/ets/viewmodel/SessionViewModel'
import { BrowserLauncher } from '../main/ets/model/browser/BrowserLauncher'

export default function interactionFixesTest() {
  describe('InteractionFixes', () => {
    it('parsesKeySubcommandsFromTheCorrectArgument', 0, () => {
      let config: SshConfig = new SshConfig()
      let showResult: CommandParseResult | KeyCommandResult | null = CommandParser.parseInput('key show deploy', config)
      let removeResult: CommandParseResult | KeyCommandResult | null = CommandParser.parseInput('key rm deploy', config)
      let importResult: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('key import C:\\keys\\source deploy', config)
      let exportResult: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('key export deploy', config)
      expect(showResult instanceof KeyCommandResult).assertEqual(true)
      expect(removeResult instanceof KeyCommandResult).assertEqual(true)
      expect(importResult instanceof KeyCommandResult).assertEqual(true)
      expect(exportResult instanceof KeyCommandResult).assertEqual(true)
      if (showResult instanceof KeyCommandResult) { expect(showResult.keyName).assertEqual('deploy') }
      if (removeResult instanceof KeyCommandResult) { expect(removeResult.keyName).assertEqual('deploy') }
      if (importResult instanceof KeyCommandResult) {
        expect(importResult.sourcePath).assertEqual('C:\\keys\\source')
        expect(importResult.keyName).assertEqual('deploy')
      }
      if (exportResult instanceof KeyCommandResult) {
        expect(exportResult.kind).assertEqual(KeyCommandKind.KEYEXPORT)
        expect(exportResult.keyName).assertEqual('deploy')
        expect(exportResult.destinationName).assertEqual('deploy')
      }
    })

    it('recognizesExitAsALocalCommand', 0, () => {
      let result: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('exit', new SshConfig())
      expect(result instanceof KeyCommandResult).assertEqual(true)
      if (result instanceof KeyCommandResult) { expect(result.kind).assertEqual(KeyCommandKind.EXIT) }
    })

    it('supportsTopicHelpAndExactCommandNames', 0, () => {
      let help: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('help ssh-keygen', new SshConfig())
      let commandHelp: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('host --help', new SshConfig())
      expect(help instanceof KeyCommandResult).assertEqual(true)
      expect(commandHelp instanceof KeyCommandResult).assertEqual(true)
      if (help instanceof KeyCommandResult) { expect(help.keyName).assertEqual('ssh-keygen') }
      if (commandHelp instanceof KeyCommandResult) { expect(commandHelp.keyName).assertEqual('host') }
      expect(CommandParser.parseInput('ssh-keygen-bad -t rsa', new SshConfig())).assertEqual(null)
    })

    it('acceptsAsciiAndFullwidthQuestionMarksAsStartupHelp', 0, () => {
      let ascii = CommandParser.parseInput('?', new SshConfig())
      let fullwidth = CommandParser.parseInput('？', new SshConfig())
      expect(ascii instanceof KeyCommandResult).assertEqual(true)
      expect(fullwidth instanceof KeyCommandResult).assertEqual(true)
      if (ascii instanceof KeyCommandResult) { expect(ascii.kind).assertEqual(KeyCommandKind.HELP) }
      if (fullwidth instanceof KeyCommandResult) { expect(fullwidth.kind).assertEqual(KeyCommandKind.HELP) }
    })

    it('keepsUnknownAndInvalidLocalCommandsDistinct', 0, () => {
      let unknown: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('not-a-command', new SshConfig())
      let empty: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('', new SshConfig())
      let invalidSsh: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('ssh', new SshConfig())
      expect(unknown).assertEqual(null)
      expect(empty instanceof CommandParseResult).assertEqual(true)
      expect(invalidSsh instanceof CommandParseResult).assertEqual(true)
      if (empty instanceof CommandParseResult) {
        expect(empty.errorMessage).assertEqual('Usage: ssh <user>@<host>')
      }
      if (invalidSsh instanceof CommandParseResult) {
        expect(invalidSsh.errorMessage).assertEqual('Username required')
      }
    })

    it('rejectsUnsupportedKeyTypesInsteadOfFallingBack', 0, () => {
      let result: KeyCommandResult = CommandParser.parseSshKeygen('ssh-keygen -t dsa')
      expect(result.errorMessage.length > 0).assertEqual(true)
    })

    it('parsesOpenSshKeyInspectionModes', 0, () => {
      let publicResult: KeyCommandResult = CommandParser.parseSshKeygen('ssh-keygen -y -f ~/.ssh/deploy')
      let infoResult: KeyCommandResult = CommandParser.parseSshKeygen('ssh-keygen -l -f deploy.pub')
      expect(publicResult.kind).assertEqual(KeyCommandKind.KEYPUB)
      expect(infoResult.kind).assertEqual(KeyCommandKind.KEYINFO)
      expect(publicResult.keyName).assertEqual('~/.ssh/deploy')
    })

    it('parsesOptionalKeyExportFileNameAndRejectsInvalidSyntax', 0, () => {
      let missingName: KeyCommandResult = CommandParser.parseKeyExport('key export')
      let renamed: KeyCommandResult = CommandParser.parseKeyExport('key export deploy deploy-backup')
      let extraName: KeyCommandResult = CommandParser.parseKeyExport('key export deploy backup extra')
      expect(missingName.errorMessage).assertEqual('Usage: key export <key-name> [<file-name>]')
      expect(renamed.keyName).assertEqual('deploy')
      expect(renamed.destinationName).assertEqual('deploy-backup')
      expect(extraName.errorMessage).assertEqual('Usage: key export <key-name> [<file-name>]')
    })

    it('parsesHostCommandsAndMarksLegacyAliasSyntax', 0, () => {
      let host: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('host add prod root@example.com', new SshConfig())
      let alias: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('alias add prod root@example.com', new SshConfig())
      expect(host instanceof KeyCommandResult).assertEqual(true)
      expect(alias instanceof KeyCommandResult).assertEqual(true)
      if (host instanceof KeyCommandResult) { expect(host.legacySyntax).assertEqual(false) }
      if (alias instanceof KeyCommandResult) { expect(alias.legacySyntax).assertEqual(true) }
    })

    it('parsesEffectiveConfigInspection', 0, () => {
      let result: CommandParseResult | KeyCommandResult | null =
        CommandParser.parseInput('ssh -G prod', new SshConfig())
      expect(result instanceof KeyCommandResult).assertEqual(true)
      if (result instanceof KeyCommandResult) {
        expect(result.kind).assertEqual(KeyCommandKind.SSH_CONFIG)
        expect(result.keyName).assertEqual('prod')
      }
    })

    it('aliasUpdatesPreserveUnmanagedSshConfigText', 0, () => {
      let config: SshConfig = new SshConfig()
      config.loadFromText('# keep\nHost *\n  ForwardAgent yes\n\nHost prod production # shared\n' +
        '  HostName old\n  User root\n  ProxyJump bastion\n')
      config.addAlias('prod', 'new.example.com', 2222, 'deploy')
      let text: string = config.previewConfigText()
      expect(text.includes('# keep')).assertEqual(true)
      expect(text.includes('ForwardAgent yes')).assertEqual(true)
      expect(text.includes('Host prod production # shared')).assertEqual(true)
      expect(text.includes('ProxyJump bastion')).assertEqual(true)
      expect(text.includes('# >>> LeanTTY managed hosts >>>')).assertEqual(true)
      expect(text.includes('Host prod\n  HostName new.example.com\n  User deploy\n  Port 2222')).assertEqual(true)
    })

    it('resolvesOpenSshFirstValueAndIdentityFile', 0, () => {
      let config: SshConfig = new SshConfig()
      config.loadFromText('Host prod\n  HostName prod.example.com\n  IdentityFile ~/.ssh/deploy\n\n' +
        'Host *\n  User deploy\n  Port 2200\n')
      let result: CommandParseResult | KeyCommandResult | null = CommandParser.parseInput('ssh prod', config)
      expect(result instanceof CommandParseResult).assertEqual(true)
      if (result instanceof CommandParseResult) {
        expect(result.host).assertEqual('prod.example.com')
        expect(result.username).assertEqual('deploy')
        expect(result.port).assertEqual(2200)
        expect(result.identityFile).assertEqual('~/.ssh/deploy')
      }
    })

    it('doesNotLeakMatchDirectivesIntoFollowingHostResolution', 0, () => {
      let config: SshConfig = new SshConfig()
      config.loadFromText('Host prod\n  HostName prod.example.com\nMatch user root\n  Port 9999\n' +
        'Host *\n  Port 2222\n  User deploy\n')
      let host = config.findHost('prod')
      expect(host !== null).assertEqual(true)
      if (host !== null) {
        expect(host.port).assertEqual(2222)
        expect(host.user).assertEqual('deploy')
      }
    })

    it('reportsCopySelectionResultsIncludingAnEmptySelection', 0, () => {
      expect(BridgeProtocol.copySelectionResult('copied text').serialize())
        .assertEqual('H2|W2N|CONTROL|copySelection|copied text')
      expect(BridgeProtocol.copySelectionResult('').serialize())
        .assertEqual('H2|W2N|CONTROL|copySelection|')
    })

    it('acceptsOnlyWebToNativeUrlOpenControls', 0, () => {
      let openUrl: BridgeMessage | null =
        BridgeProtocol.parse('H2|W2N|CONTROL|openUrl|https://example.com/path?q=1')
      expect(openUrl !== null).assertEqual(true)
      if (openUrl !== null) {
        expect(openUrl.kind).assertEqual(BridgeProtocol.KIND_OPEN_URL)
        expect(openUrl.payload).assertEqual('https://example.com/path?q=1')
      }
      expect(BridgeProtocol.parse('H2|N2W|CONTROL|openUrl|https://example.com')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|DATA|openUrl|https://example.com')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|openUrl|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|openUrl|' +
        'x'.repeat(BridgeProtocol.MAX_URL_PAYLOAD_LENGTH + 1))).assertEqual(null)
    })

    it('allowsOnlyNormalizedCredentialFreeHttpUrls', 0, () => {
      expect(BrowserLauncher.normalizeHttpUrl('https://example.com/path?q=1'))
        .assertEqual('https://example.com/path?q=1')
      expect(BrowserLauncher.normalizeHttpUrl('HTTP://EXAMPLE.COM'))
        .assertEqual('http://EXAMPLE.COM')
      expect(BrowserLauncher.normalizeHttpUrl('ftp://example.com')).assertEqual(null)
      expect(BrowserLauncher.normalizeHttpUrl('https://user:secret@example.com')).assertEqual(null)
      expect(BrowserLauncher.normalizeHttpUrl(' https://example.com')).assertEqual(null)
      expect(BrowserLauncher.normalizeHttpUrl('https://example.com/\nnext')).assertEqual(null)
    })

    it('encodesTerminalFocusAndBlurAsSeparateBridgeMessages', 0, () => {
      expect(BridgeProtocol.focus().serialize()).assertEqual('H2|N2W|CONTROL|focus|')
      expect(BridgeProtocol.blur().serialize()).assertEqual('H2|N2W|CONTROL|blur|')
      expect(BridgeProtocol.clearSelection().serialize()).assertEqual('H2|N2W|CONTROL|clearSelection|')
    })

    it('routesTerminalSurfaceActionsThroughBridgeControls', 0, () => {
      expect(BridgeProtocol.fit().serialize()).assertEqual('H2|N2W|CONTROL|fit|')
      expect(BridgeProtocol.fontSize(18).serialize()).assertEqual('H2|N2W|CONTROL|fontSize|18')
      expect(BridgeProtocol.copySelection().serialize()).assertEqual('H2|N2W|CONTROL|copySelection|')
      expect(BridgeProtocol.parse(BridgeProtocol.copySelection().serialize()) !== null).assertEqual(true)
      expect(BridgeProtocol.secondaryAction().serialize()).assertEqual('H2|N2W|CONTROL|secondaryAction|')
    })

    it('preservesDirectionalBridgePayloadsWithoutJsonEncoding', 0, () => {
      let raw: string = BridgeProtocol.write('a|b:c\r\n').serialize()
      let parsed: BridgeMessage | null = BridgeProtocol.parse(raw)
      expect(parsed !== null).assertEqual(true)
      if (parsed !== null) {
        expect(parsed.direction).assertEqual(BridgeProtocol.DIRECTION_NATIVE_TO_WEB)
        expect(parsed.channel).assertEqual(BridgeProtocol.CHANNEL_DATA)
        expect(parsed.kind).assertEqual(BridgeProtocol.KIND_TERMINAL)
        expect(parsed.payload).assertEqual('a|b:c\r\n')
      }
      expect(BridgeProtocol.parse('D:legacy')).assertEqual(null)
    })

    it('rejectsUnknownOrMisdirectedBridgeMessages', 0, () => {
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|unknown|payload')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|bell|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|title|remote-title')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|bellAttention|unexpected')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|attentionAcknowledged|unexpected')).assertEqual(null)
      let bellAttention: BridgeMessage | null =
        BridgeProtocol.parse('H2|W2N|CONTROL|bellAttention|')
      expect(bellAttention !== null).assertEqual(true)
      if (bellAttention !== null) {
        expect(bellAttention.kind).assertEqual(BridgeProtocol.KIND_BELL_ATTENTION)
        expect(bellAttention.payload).assertEqual('')
      }
      let attentionAcknowledged: BridgeMessage | null =
        BridgeProtocol.parse('H2|W2N|CONTROL|attentionAcknowledged|')
      expect(attentionAcknowledged !== null).assertEqual(true)
      if (attentionAcknowledged !== null) {
        expect(attentionAcknowledged.kind).assertEqual(BridgeProtocol.KIND_ATTENTION_ACKNOWLEDGED)
        expect(attentionAcknowledged.payload).assertEqual('')
      }
      expect(BridgeProtocol.parse('H2|N2W|CONTROL|ready|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|theme|{}')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|W2N|DATA|resize|80,24')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|N2W|DATA|terminal|ok') !== null).assertEqual(true)
      expect(BridgeProtocol.parse('H2|W2N|DATA|terminal|ok') !== null).assertEqual(true)
    })

    it('routesPhysicalTabToTerminalCompletion', 0, () => {
      let tab: string = KeyCodeMap.toAnsi(KeyCodeMap.TAB, false, false, false)
      let actions: TerminalInputAction[] = TerminalInputParser.parse(tab, true)
      expect(tab).assertEqual('\t')
      expect(actions.length).assertEqual(1)
      expect(actions[0].kind).assertEqual(TerminalInputActionKind.TAB)
    })

    it('keepsCursorPositionWhenEditingAPastedLocalCommand', 0, () => {
      let actions: TerminalInputAction[] = TerminalInputParser.parse('\u001b[D\u001b[D\u001b[C', true)
      expect(actions.length).assertEqual(3)
      expect(actions[0].kind).assertEqual(TerminalInputActionKind.CURSOR_LEFT)
      expect(actions[1].kind).assertEqual(TerminalInputActionKind.CURSOR_LEFT)
      expect(actions[2].kind).assertEqual(TerminalInputActionKind.CURSOR_RIGHT)

      let line: LocalCommandLine = new LocalCommandLine()
      line.insert('ssh user@host')
      expect(line.moveLeft()).assertEqual(true)
      expect(line.moveLeft()).assertEqual(true)
      let suffix: string = line.insert('X')
      expect(line.getText()).assertEqual('ssh user@hoXst')
      expect(line.getCursor()).assertEqual(12)
      expect(suffix).assertEqual('st')
    })

    it('redrawsLocalCommandsWithoutAssumingChineseCharactersAreOneTerminalColumn', 0, () => {
      let line: LocalCommandLine = new LocalCommandLine()
      line.insert('中文')
      expect(line.moveLeft()).assertEqual(true)
      expect(line.renderForTerminal('ltty> '))
        .assertEqual('\r\u001b[2Kltty> 中文\rltty> 中')
      expect(line.backspace() !== null).assertEqual(true)
      expect(line.renderForTerminal('ltty> '))
        .assertEqual('\r\u001b[2Kltty> 文\rltty> ')
    })

    it('confirmsApplicationCloseOnlyForUnsuppressedActiveSessions', 0, () => {
      expect(InteractionPolicy.shouldConfirmApplicationClose(false, false)).assertEqual(false)
      expect(InteractionPolicy.shouldConfirmApplicationClose(true, false)).assertEqual(true)
      expect(InteractionPolicy.shouldConfirmApplicationClose(true, true)).assertEqual(false)
    })

    it('doesNotTreatTerminalQueryResponsesAsLocalCommandText', 0, () => {
      let actions: TerminalInputAction[] = TerminalInputParser.parse(
        '\u001b[?1;2c\u001b[6;1R\u001b[1;1R', true)
      expect(actions.length).assertEqual(0)
    })

    it('endsAcceptedHostKeyInputBeforeTheNextAuthenticationPrompt', 0, () => {
      expect(SessionViewModel.hostKeyDecisionSubmitOutput('yes')).assertEqual('\r\n')
      expect(SessionViewModel.hostKeyDecisionSubmitOutput('no')).assertEqual('\r\n')
      expect(SessionViewModel.hostKeyDecisionSubmitOutput('maybe'))
        .assertEqual('\r\nPlease type yes or no: ')
    })

    it('buildsKeypushMarkerAndShellCommandWithoutEchoFalsePositive', 0, () => {
      let generatedMarker: string = SessionViewModel.buildKeypushMarker()
      expect(generatedMarker.startsWith('__LTTY_KEYPUSH_')).assertEqual(true)
      expect(generatedMarker.length > '__LTTY_KEYPUSH_'.length).assertEqual(true)

      let marker: string = '__LTTY_KEYPUSH_99'
      let cmd: string = SessionViewModel.buildKeypushShellCommand('ssh-ed25519 AAAAC test', marker)
      expect(cmd.indexOf(marker + ':') < 0).assertEqual(true)
      let markerPrint: string = "printf '\\n%s:%s\\n' '" + marker + "' \"$command_status\""
      expect(cmd.indexOf(markerPrint) >= 0).assertEqual(true)
      let echoLine: string = "printf '\\n%s:%s\\n' '" + marker + "' '$command_status'\n"
      expect(SessionViewModel.parseKeypushMarker(echoLine, marker)).assertEqual(null)
    })

    it('parsesOnlyCompleteNumericKeypushStatusLines', 0, () => {
      let marker: string = '__LTTY_KEYPUSH_100'
      expect(SessionViewModel.parseKeypushMarker('other\n' + marker + ':0\nmore', marker)).assertEqual(0)
      expect(SessionViewModel.parseKeypushMarker(marker + ':-1\n', marker)).assertEqual(-1)
      expect(SessionViewModel.parseKeypushMarker('missing marker', marker)).assertEqual(null)
      expect(SessionViewModel.parseKeypushMarker(marker + ':0', marker)).assertEqual(null)
      expect(SessionViewModel.parseKeypushMarker(marker + ':%s\n', marker)).assertEqual(null)
      expect(SessionViewModel.parseKeypushMarker(marker + ':\n', marker)).assertEqual(null)
      expect(SessionViewModel.parseKeypushMarker(marker + ':0junk\n', marker)).assertEqual(null)
    })

    it('rejectsRemovedReplayMessagesAndKeepsOsc52DirectionBounded', 0, () => {
      expect(BridgeProtocol.clipboardWriteResult('中文').serialize())
        .assertEqual('H2|W2N|CONTROL|clipboardWrite|中文')
      expect(BridgeProtocol.parse('H2|W2N|CONTROL|replayBegin|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|N2W|CONTROL|replayBegin|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|N2W|CONTROL|releaseBuffers|')).assertEqual(null)
      expect(BridgeProtocol.parse('H2|N2W|CONTROL|clipboardWrite|text')).assertEqual(null)
    })

    it('encodesShiftedDigitsAndAltPunctuation', 0, () => {
      expect(KeyCodeMap.toAnsi(KeyCodeMap.NUM_1, false, false, true)).assertEqual('!')
      expect(KeyCodeMap.toAnsi(KeyCodeMap.NUM_0, false, false, true)).assertEqual(')')
      expect(KeyCodeMap.toAnsi(2057, false, true, false)).assertEqual('\u001b-')
    })

    it('encodesCursorKeysForTerminalModeAndModifiers', 0, () => {
      expect(KeyCodeMap.toAnsi(KeyCodeMap.ARROW_UP, false, false, false, true)).assertEqual('\u001bOA')
      expect(KeyCodeMap.toAnsi(KeyCodeMap.ARROW_LEFT, true, false, false, false)).assertEqual('\u001b[1;5D')
      expect(KeyCodeMap.toAnsi(KeyCodeMap.ARROW_DOWN, false, false, true, false)).assertEqual('\u001b[1;2B')
    })

    it('clampsLayoutAndKeepsOnlyOnePreviousTabSurfaceWarm', 0, () => {
      expect(InteractionPolicy.DEFAULT_FONT_SIZE).assertEqual(16)
      expect(InteractionPolicy.clampSplitRatio(0.05)).assertEqual(0.2)
      expect(InteractionPolicy.clampSplitRatio(0.55)).assertEqual(0.55)
      expect(InteractionPolicy.clampSplitRatio(0.95)).assertEqual(0.8)
      expect(InteractionPolicy.clampFontSize(2)).assertEqual(8)
      expect(InteractionPolicy.clampFontSize(60)).assertEqual(48)
      expect(InteractionPolicy.warmTabAfterSwitch('A')).assertEqual('A')
      expect(InteractionPolicy.evictedWarmTab('A', 'B', '')).assertEqual('')
      expect(InteractionPolicy.warmTabAfterSwitch('B')).assertEqual('B')
      expect(InteractionPolicy.evictedWarmTab('B', 'A', 'A')).assertEqual('')
      expect(InteractionPolicy.warmTabAfterSwitch('A')).assertEqual('A')
      expect(InteractionPolicy.evictedWarmTab('A', 'C', 'B')).assertEqual('B')
    })

    it('keepsConnectedTabsMountedOutsideTheWarmSet', 0, () => {
      expect(InteractionPolicy.shouldMountTab(false, false, true)).assertEqual(true)
      expect(InteractionPolicy.shouldMountTab(true, false, false)).assertEqual(true)
      expect(InteractionPolicy.shouldMountTab(false, true, false)).assertEqual(true)
      expect(InteractionPolicy.shouldMountTab(false, false, false)).assertEqual(false)
      expect(InteractionPolicy.shouldMountTab(true, false, true, false)).assertEqual(true)
      expect(InteractionPolicy.shouldMountTab(false, false, true, false)).assertEqual(true)
      expect(InteractionPolicy.shouldMountTab(true, false, false, false)).assertEqual(false)
      expect(InteractionPolicy.shouldMountTab(false, true, false, false)).assertEqual(false)
      expect(InteractionPolicy.shouldDetachTabOnEviction(true)).assertEqual(false)
      expect(InteractionPolicy.shouldDetachTabOnEviction(false)).assertEqual(true)
    })

    it('buffersOnlyOutputProducedWhileTheTerminalSurfaceIsDetached', 0, () => {
      let output: TerminalOutputBuffer = new TerminalOutputBuffer(6)
      output.append(new Uint8Array([1, 2, 3, 4]))
      expect(output.isOutputPaused()).assertEqual(false)
      output.append(new Uint8Array([5, 6]))
      expect(output.isOutputPaused()).assertEqual(true)
      expect(output.getDetachedByteCount()).assertEqual(6)
      let detachedChunks: Uint8Array[] = output.takeDetachedChunks()
      expect(detachedChunks.length).assertEqual(2)
      expect(detachedChunks[0][0]).assertEqual(1)
      expect(detachedChunks[1][1]).assertEqual(6)
      output.markAttached()
      expect(output.isOutputPaused()).assertEqual(false)
      output.append(new Uint8Array([7, 8, 9, 10, 11, 12]))
      expect(output.getDetachedByteCount()).assertEqual(0)
      output.setBridgeBackpressured(true)
      expect(output.isOutputPaused()).assertEqual(true)
      output.releaseDisconnectedFlowControl()
      expect(output.isOutputPaused()).assertEqual(false)
      output.markDetached()
      output.append(new Uint8Array([13, 14]))
      expect(output.getDetachedByteCount()).assertEqual(2)
      expect(output.takeDetachedChunks()[0][1]).assertEqual(14)
    })

    it('mapsTaggedCloseResultsToAnActionableSshError', 0, () => {
      expect(SshClient.parseCloseError('-1')).assertEqual(null)
      expect(SshClient.parseCloseError('ERROR:SSH keepalive timed out. Check the network.'))
        .assertEqual('SSH keepalive timed out. Check the network.')
      expect(SshClient.parseCloseError('ERROR:'))
        .assertEqual('SSH connection ended unexpectedly.')
    })
  })
}
