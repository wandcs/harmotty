import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import './test-font-cell-width.mjs';
import '../../entry/src/main/resources/rawfile/terminal-policy.js';

const policy = globalThis.LeanTTYTerminalPolicy;
const encode = text => `c;${Buffer.from(text, 'utf8').toString('base64')}`;

const assetManifest = JSON.parse(
  readFileSync(new URL('./assets-manifest.json', import.meta.url), 'utf8')
);
for (const asset of assetManifest) {
  const checkedOutBytes = readFileSync(
    new URL(`../../entry/src/main/resources/rawfile/${asset.file}`, import.meta.url),
    'utf8'
  );
  const bytes = Buffer.from(checkedOutBytes.replace(/\r\n/g, '\n'), 'utf8');
  assert.equal(bytes.length, asset.bytes, `${asset.file} normalized byte count must match the asset manifest`);
  assert.equal(
    createHash('sha256').update(bytes).digest('hex'),
    asset.sha256,
    `${asset.file} hash must match the asset manifest`
  );
}

for (const text of ['', 'plain text', '中文 🚀\nsecond line']) {
  const decoded = policy.decodeOsc52(encode(text));
  assert.equal(decoded.accepted, true);
  assert.equal(decoded.text, text);
}
const tmuxSelection = 'copied by tmux';
const decodedTmuxSelection = policy.decodeOsc52(
  `;${Buffer.from(tmuxSelection, 'utf8').toString('base64')}`
);
assert.equal(decodedTmuxSelection.accepted, true);
assert.equal(decodedTmuxSelection.text, tmuxSelection);
assert.equal(policy.decodeOsc52('c;?').reason, 'read-not-supported');
assert.equal(policy.decodeOsc52('p;YQ==').reason, 'unsupported-target');
assert.equal(policy.decodeOsc52('c;%%%').reason, 'invalid-base64');
assert.equal(policy.decodeOsc52(`c;${'A'.repeat(policy.MAX_CLIPBOARD_BASE64_LENGTH + 4)}`).reason, 'encoded-too-large');

const bellAttention = policy.createBellAttentionGate();
let bellAttentionCount = 0;
for (let bellIndex = 0; bellIndex < 61271; bellIndex++) {
  if (bellAttention.trigger()) bellAttentionCount++;
}
assert.equal(bellAttentionCount, 1);
assert.equal(bellAttention.isPending(), true);
assert.equal(bellAttention.rearmDelivery(), true);
assert.equal(bellAttention.isPending(), true);
assert.equal(bellAttention.trigger(), true);
assert.equal(bellAttention.acknowledge(), true);
assert.equal(bellAttention.acknowledge(), false);
assert.equal(bellAttention.isPending(), false);
assert.equal(bellAttention.trigger(), true);

assert.equal(policy.countPerfPayloadBytes('XXX'), 3);
assert.equal(policy.countPerfPayloadBytes('XX\u001b[6nX\r\n'), 3);
assert.equal(policy.countPerfPayloadBytes('中文 🚀'), 0);

const wheel = policy.createWheelState();
policy.enqueueWheel(wheel, 4, 0, 16, 40, 0);
policy.enqueueWheel(wheel, 12, 0, 16, 40, 16);
assert.ok(policy.pendingWheelLines(wheel) < 1);
assert.equal(policy.consumeWheelFrame(wheel, 40), 0);

const separatedSlowWheel = policy.createWheelState();
policy.enqueueWheel(separatedSlowWheel, 12, 0, 16, 40, 0);
policy.enqueueWheel(separatedSlowWheel, 4, 0, 16, 40, 120);
assert.ok(policy.pendingWheelLines(separatedSlowWheel) < 1);
assert.equal(policy.consumeWheelFrame(separatedSlowWheel, 40), 0);

const fastWheel = policy.createWheelState();
policy.enqueueWheel(fastWheel, 80, 0, 16, 40, 0);
policy.enqueueWheel(fastWheel, 160, 0, 16, 40, 16);
assert.ok(policy.pendingWheelLines(fastWheel) > 100);
let fastTotal = 0;
let frameCount = 0;
while (policy.hasPendingWheelSteps(fastWheel)) {
  fastTotal += policy.consumeWheelFrame(fastWheel, 40);
  frameCount++;
  assert.ok(frameCount < 5);
}
assert.ok(fastTotal > 100);
assert.ok(frameCount > 1);

const reversedWheel = policy.createWheelState();
policy.enqueueWheel(reversedWheel, 320, 0, 16, 40, 0);
policy.enqueueWheel(reversedWheel, -32, 0, 16, 40, 16);
assert.ok(policy.pendingWheelLines(reversedWheel) < 0);
assert.ok(policy.consumeWheelFrame(reversedWheel, 40) < 0);

const mouseWheel = policy.createWheelState();
policy.enqueueWheel(mouseWheel, 3, 1, 16, 40, 0);
assert.equal(policy.pendingWheelLines(mouseWheel), 3);

assert.equal(policy.centerGridLeadingPadding(4, 4, 942, 926), 8);
assert.equal(policy.centerGridLeadingPadding(4, 4, 934, 926), 4);
assert.equal(policy.centerGridLeadingPadding(4, 4, 930, 926), 4);

const exactCtrl = {
  button: 0,
  ctrlKey: true,
  altKey: false,
  shiftKey: false,
  metaKey: false
};
const exactCtrlShift = {
  ...exactCtrl,
  shiftKey: true
};
assert.equal(policy.isLinkModifierActive(exactCtrl, 'none'), true);
assert.equal(policy.isLinkModifierActive(exactCtrlShift, 'none'), false);
assert.equal(policy.isLinkModifierActive({ ...exactCtrl, metaKey: true }, 'none'), false);
assert.equal(policy.isLinkModifierActive(exactCtrlShift, 'sgr'), false,
  'mouse encoding names must not be mistaken for xterm mouse tracking modes');
for (const mouseTrackingMode of ['x10', 'vt200', 'drag', 'any']) {
  assert.equal(policy.isLinkModifierActive(exactCtrl, mouseTrackingMode), false,
    `Ctrl alone must remain owned by ${mouseTrackingMode} mouse reporting`);
  assert.equal(policy.isLinkModifierActive(exactCtrlShift, mouseTrackingMode), true,
    `Ctrl+Shift must activate links while Shift bypasses ${mouseTrackingMode} mouse reporting`);
  assert.equal(policy.isLinkModifierActive(
    { ...exactCtrlShift, altKey: true }, mouseTrackingMode), false);
  assert.equal(policy.isLinkModifierActive(
    { ...exactCtrlShift, metaKey: true }, mouseTrackingMode), false);
  assert.equal(policy.shouldActivateLink(
    exactCtrlShift, mouseTrackingMode, true, false), true);
  assert.equal(policy.shouldActivateLink(
    exactCtrlShift, mouseTrackingMode, true, true), false);
}
assert.equal(policy.shouldActivateLink(exactCtrl, 'none', true, false), true);
assert.equal(policy.shouldActivateLink({ ...exactCtrl, button: 1 }, 'none', true, false), false);
assert.equal(policy.shouldActivateLink(exactCtrl, 'none', false, false), false);
assert.equal(policy.shouldActivateLink(exactCtrl, 'none', true, true), false);

const terminalHtml = readFileSync(new URL('../../entry/src/main/resources/rawfile/terminal.html', import.meta.url), 'utf8');
assert.match(terminalHtml,
  /fontFamily:\s*"'JetBrains Mono Nerd Font Mono', 'HarmonyOS Sans Mono', monospace"/,
  'xterm must use the single-cell Nerd Font Mono variant before system fallbacks');
assert.match(terminalHtml,
  /url\('JetBrainsMonoNerdFontMono-Regular\.ttf'\)[\s\S]*url\('JetBrainsMonoNerdFontMono-Bold\.ttf'\)/,
  'the embedded regular and bold faces must both use single-cell Nerd Font Mono assets');
assert.doesNotMatch(terminalHtml, /JetBrainsMonoNerdFont-(?:Regular|Bold)\.ttf/,
  'the double-width Nerd Font assets must not return to the terminal font face');
assert.match(terminalHtml, /addEventListener\('wheel', handleAlternateWheel, true\)/,
  'alternate-buffer wheel handling must run during capture before xterm scrolls its inner viewport');
assert.match(terminalHtml, /#terminal-container > \.xterm\s*\{[^}]*padding:\s*4px 2px 4px 10px;/s,
  'terminal padding must offset the scrollbar gutter without changing the total horizontal inset');
assert.match(terminalHtml, /function fitAndCenterTerminalGrid\(\)/,
  'terminal fitting must redistribute unused cell-grid height instead of leaving it all below the grid');
assert.match(terminalHtml,
  /centerGridLeadingPadding\(\s*TERMINAL_BASE_PADDING_TOP,\s*TERMINAL_BASE_PADDING_BOTTOM,/s,
  'terminal fitting must center rows with the tested layout policy');
assert.match(terminalHtml, /var TERMINAL_SCROLLBAR_WIDTH = 8;/,
  'the auto-hiding scrollbar must reserve less than one default terminal cell');
assert.match(terminalHtml, /overviewRuler:\s*\{\s*width:\s*TERMINAL_SCROLLBAR_WIDTH\s*\}/,
  'xterm and FitAddon must share the slim scrollbar width');
assert.match(terminalHtml,
  /\.xterm \.xterm-scrollable-element > \.scrollbar\.vertical > \.slider\s*\{[^}]*border:\s*2px solid transparent;[^}]*background-clip:\s*content-box !important;/s,
  'the scrollbar must keep an eight-pixel hit target with a compact visible thumb');
assert.match(terminalHtml,
  /html, body,[^}]*#terminal-container,[^}]*#terminal-container > \.xterm,[^}]*\.xterm \.xterm-viewport\s*\{[^}]*background(?:-color)?:\s*var\(--terminal-background\)/s,
  'terminal padding and leftover cell space must share the active terminal background');
assert.match(terminalHtml, /document\.documentElement\.style\.setProperty\('--terminal-background', themeObj\.background\)/,
  'theme changes must propagate their background to the Web terminal chrome');
assert.match(terminalHtml, /themeObj\.overviewRulerBorder = themeObj\.background/,
  'the width-only overview ruler must not draw a contrasting edge line');
assert.match(terminalHtml, /parseTerminalPacket\(e\.data\)/,
  'the MessagePort must accept the original binary terminal packet directly');
assert.doesNotMatch(terminalHtml, /leanttyOutput\.pullOutput|decodePulledTerminalPacket|case 'outputAvailable':/,
  'the rejected synchronous Base64 pull experiment must not remain in the terminal path');
assert.match(terminalHtml, /term\.write\(terminalBytes/,
  'the terminal must receive the original Uint8Array bytes rather than a decoded string');
assert.doesNotMatch(terminalHtml,
  /outputBurst|validationMarker|LTTY_(?:BEGIN|END|KEY)_|samplePortDelivery|TERMINAL_RENDERER_MODE/,
  'temporary binary-output and renderer diagnostics must not remain in the terminal runtime');
assert.doesNotMatch(terminalHtml, /replayGate|replayBegin|replayEnd/,
  'the removed raw terminal-history replay protocol must not return');
assert.match(terminalHtml, /<script src="addon-serialize\.js"><\/script>/,
  'the terminal page must load the pinned xterm serialization addon');
assert.match(terminalHtml, /serializeAddon = new SerializeAddon\.SerializeAddon\(\)/,
  'terminal recovery checkpoints must use xterm framebuffer serialization');
assert.match(terminalHtml,
  /term\._core\.coreService\.isCursorHidden[\s\S]*?snapshot \+= '\\x1b\[\?25l'/,
  'terminal recovery checkpoints must preserve hidden cursor state');
assert.match(terminalHtml,
  /function requestTerminalSnapshot[\s\S]*?term\.write\('',[\s\S]*?serializeTerminalSnapshot/,
  'snapshot capture must wait for all queued terminal writes to finish');
assert.match(terminalHtml,
  /var scrollback = 0[\s\S]*?snapshot\.length > availableLength[\s\S]*?return bestSnapshot[\s\S]*?Math\.min\(scrollback \* 2, TERMINAL_SCROLLBACK_LINES\)/,
  'checkpoint allocation must grow from the visible screen instead of serializing all scrollback first');
assert.doesNotMatch(terminalHtml, /scrollback = Math\.floor\(scrollback \/ 2\)/,
  'checkpoint bounding must not allocate full scrollback before shrinking');
assert.match(terminalHtml,
  /pendingSnapshotRequestIds\.push[\s\S]*?snapshotCapturePending[\s\S]*?for \(var j = 0; j < requestIds\.length; j\+\+\)/,
  'concurrent checkpoint requests must share one serialized framebuffer');
assert.match(terminalHtml,
  /return bestSnapshot[\s\S]*?if \(snapshot !== null\)[\s\S]*?sendBridgeControl\('snapshot'/,
  'a failed checkpoint must time out without erasing the last successful snapshot');
const snapshotSerializerSource = terminalHtml.match(
  /(function serializeTerminalSnapshot\(availableLength\) \{[\s\S]*?\n    \})\n\n    function requestTerminalSnapshot/);
assert.ok(snapshotSerializerSource,
  'the bounded snapshot serializer must remain executable in the regression harness');
const attemptedScrollbacks = [];
globalThis.TERMINAL_SCROLLBACK_LINES = 10000;
globalThis.term = null;
globalThis.serializeAddon = {
  serialize: ({ scrollback }) => {
    attemptedScrollbacks.push(scrollback);
    return 'x'.repeat(scrollback === 0 ? 100 : scrollback * 2);
  }
};
vm.runInThisContext(snapshotSerializerSource[1]);
const boundedSnapshot = globalThis.serializeTerminalSnapshot(4096);
assert.equal(boundedSnapshot.length, 4096,
  'the snapshot budget must retain the largest successful candidate');
assert.deepEqual(attemptedScrollbacks, [0, 64, 128, 256, 512, 1024, 2048, 4096],
  'snapshot work must grow from the visible screen and stop after one over-budget candidate');
assert.match(terminalHtml,
  /case 'restoreSnapshot':[\s\S]*?restoringSnapshot = true[\s\S]*?restoringSnapshot = false[\s\S]*?sendBridgeControl\('restoreComplete'[\s\S]*?term\.write\(message\.payload, completeRestore\)/,
  'a replacement xterm instance must suppress generated input until restoration completes');
assert.match(terminalHtml,
  /term\.onData\(function\(data\)[\s\S]*?if \(!restoringSnapshot\)[\s\S]*?sendBridgeData\('terminal', data\)/,
  'checkpoint mode restoration must not inject generated input into SSH');
assert.doesNotMatch(terminalHtml, /releaseBuffers|term\.clear\(\)|term\.reset\(\)/,
  'normal disconnect cleanup must not clear the current xterm screen or scrollback');
assert.match(terminalHtml, /term\.onBell\s*\(/,
  'xterm must remain the semantic source for terminal bell events');
assert.match(terminalHtml,
  /term\.onKey\s*\(function\(\)\s*\{\s*acknowledgeBellAttention\(\);/s,
  'the first real keyboard input after BEL must acknowledge the owning pane');
assert.match(terminalHtml,
  /term\.textarea\.addEventListener\('compositionstart', acknowledgeBellAttention\);[\s\S]*term\.textarea\.addEventListener\('input', acknowledgeBellAttention, true\);[\s\S]*term\.textarea\.addEventListener\('paste', acknowledgeBellAttention\);/s,
  'IME composition, ArkWeb text input, and browser paste must acknowledge the owning pane');
assert.match(terminalHtml,
  /if \(text\.length > 0 && term\) \{\s*acknowledgeBellAttention\(\);\s*term\.paste\(text\);/s,
  'a user paste after BEL must acknowledge the owning pane');
assert.doesNotMatch(terminalHtml,
  /term\.onData\s*\(function\(data\)\s*\{[^}]*acknowledgeBellAttention/s,
  'terminal-generated query responses must not acknowledge pane attention');
assert.match(terminalHtml,
  /case 'focus':[\s\S]*?bellAttentionGate\.rearmDelivery\(\);[\s\S]*?term\.focus\(\);/s,
  'programmatic focus must rearm BEL delivery without acknowledging pane attention');
assert.match(terminalHtml,
  /term\.onBell\s*\(function\(\)\s*\{\s*if\s*\(bellAttentionGate\.trigger\(\)\)\s*\{\s*sendBridgeControl\('bellAttention', ''\)/s,
  'a BEL flood must cross the bridge only after the source-side attention gate accepts it');
assert.doesNotMatch(terminalHtml, /term\.onBell\s*\(function\(\)\s*\{\s*sendBridgeControl\('bellAttention'/s,
  'bell attention must never be sent directly for every parsed BEL');
assert.match(terminalHtml, /term\.onTitleChange\s*\(/,
  'the local performance-marker parser must continue to observe title sequences');
assert.doesNotMatch(terminalHtml, /sendBridgeControl\('title'/,
  'ordinary remote title changes must not cross the bridge when the product does not consume them');
assert.match(terminalHtml, /new WebLinksAddon\.WebLinksAddon\(/,
  'plain HTTP(S) text must use the xterm web-links provider');
assert.match(terminalHtml, /linkHandler:\s*\{[\s\S]*?activate:/,
  'OSC 8 links must use the same native-system activation path as plain links');
assert.match(terminalHtml,
  /shouldActivateLink\([\s\S]*?currentMouseTrackingMode\(\)[\s\S]*?sendBridgeControl\('openUrl', url\)/s,
  'URL activation must use the tested modifier policy, primary click, same link, and no drag');
assert.match(terminalHtml,
  /ctrlKey:\s*linkModifierState\.ctrlKey,[\s\S]*?shiftKey:\s*linkModifierState\.shiftKey/,
  'stationary link feedback must retain both Ctrl and Shift state for mouse-reporting mode changes');
const linkActivationBody = terminalHtml.match(
  /function activateTerminalLink\(event, url\)\s*\{([\s\S]*?)\n    \}/
);
assert.ok(linkActivationBody, 'the shared terminal link activation callback must exist');
assert.doesNotMatch(linkActivationBody[1], /event\.stopPropagation\(\)/,
  'link mouseup must reach xterm document listeners so text-selection drag state is released');
assert.match(terminalHtml, /setCurrentLinkDecorations\(linkModifierActive\)/,
  'pressing or releasing required modifiers while stationary must update the hovered link immediately');
assert.match(terminalHtml, /id="link-preview"/,
  'modifier-hover must expose the real target of an OSC 8 link before opening it');
assert.doesNotMatch(terminalHtml, /window\.open|location\.(?:href|assign|replace)/,
  'the terminal page must never bypass the typed native browser bridge');

const xtermJs = readFileSync(
  new URL('../../entry/src/main/resources/rawfile/xterm.js', import.meta.url), 'utf8');
assert.match(xtermJs,
  /get currentLink\(\)[\s\S]*?Object\.defineProperties\([^)]*decorations[\s\S]*?pointerCursor[\s\S]*?underline/,
  'the pinned xterm build must retain the decoration adapter used for modifier-only link feedback');
assert.match(xtermJs,
  /shouldForceSelection\(e\)\{return [^}]*:e\.shiftKey\}/,
  'the pinned xterm build must retain Shift as the local mouse-reporting bypass');
assert.match(xtermJs,
  /areMouseEventsActive&&!this\._selectionService\.shouldForceSelection\(e\)/,
  'xterm must test the Shift bypass before forwarding mouse events to tmux or another TUI');

const addonSerialize = readFileSync(
  new URL('../../entry/src/main/resources/rawfile/addon-serialize.js', import.meta.url), 'utf8');
assert.match(addonSerialize, /SerializeAddon/,
  'the packaged serialization addon must expose the framebuffer checkpoint implementation');
globalThis.self = globalThis;
vm.runInThisContext(xtermJs);
vm.runInThisContext(addonSerialize);
const sourceTerminal = new globalThis.Terminal({ cols: 20, rows: 4, scrollback: 20 });
const sourceSerializer = new globalThis.SerializeAddon.SerializeAddon();
sourceTerminal.loadAddon(sourceSerializer);
sourceTerminal.write('first\r\n');
sourceTerminal.write('second\r\n');
sourceTerminal.write('third\r\n');
sourceTerminal.write('fourth\r\n');
sourceTerminal.write('fifth\r\n');
sourceTerminal.write('\u001b]0;checkpoint-title\u0007');
sourceTerminal.write('\u001b]52;c;Y2hlY2twb2ludA==\u0007');
sourceTerminal.write('\u001b[31msixth\u001b[0m\u001b[?25l\u001b[?1004h');
await new Promise(resolve => {
  sourceTerminal.write('', resolve);
});
const cursorVisibility = sourceTerminal._core.coreService.isCursorHidden ? '\u001b[?25l' : '';
const serializedSnapshot = sourceSerializer.serialize({ scrollback: 20 }) + cursorVisibility;
assert.doesNotMatch(serializedSnapshot, /\u0007|\u001b\]0;|\u001b\]52;/,
  'framebuffer checkpoints must not retain title, clipboard, or bell side effects');
assert.match(serializedSnapshot, /\u001b\[\?1004h/,
  'the focus-reporting fixture must exercise serializer mode restoration');
const restoredTerminal = new globalThis.Terminal({ cols: 20, rows: 4, scrollback: 20 });
const restoredSerializer = new globalThis.SerializeAddon.SerializeAddon();
restoredTerminal.loadAddon(restoredSerializer);
const forwardedRestoreData = [];
let restoringCheckpoint = true;
restoredTerminal.onData(data => {
  if (!restoringCheckpoint) forwardedRestoreData.push(data);
});
await new Promise(resolve => {
  restoredTerminal.write(serializedSnapshot, () => {
    restoringCheckpoint = false;
    resolve();
  });
});
assert.equal(forwardedRestoreData.length, 0,
  'restoring focus-reporting mode must not emit synthetic input to native');
assert.equal(restoredTerminal._core.coreService.isCursorHidden, true,
  'serialized recovery must preserve hidden cursor state');
await new Promise(resolve => {
  restoredTerminal.write('\u001b[?1004l\u001b[?1004h', resolve);
});
assert.equal(forwardedRestoreData.length, 1,
  'focus reporting must resume after the restore-complete boundary');
await new Promise(resolve => {
  restoredTerminal.write('\r\ndetached-output', resolve);
});
const restoredSnapshot = restoredSerializer.serialize();
assert.match(restoredSnapshot, /first/,
  'serialized recovery must restore lines that have moved into scrollback');
assert.match(restoredSnapshot, /\u001b\[31msixth/,
  'serialized recovery must restore styled terminal content');
assert.equal(restoredSnapshot.match(/detached-output/g)?.length, 1,
  'output produced after the checkpoint must follow restored content exactly once');

const terminalBridge = readFileSync(
  new URL('../../entry/src/main/ets/model/bridge/TerminalBridge.ets', import.meta.url), 'utf8');
assert.match(terminalBridge,
  /awaitingRestoreComplete[\s\S]*?KIND_RESTORE_COMPLETE[\s\S]*?notifyReadyHandler/,
  'native focus and ready handling must wait for the web restore acknowledgement');
assert.match(terminalBridge,
  /private pumpSnapshotRequests[\s\S]*?pendingDataHead < this\.pendingData\.length \|\| this\.inFlightMessages > 0/,
  'a checkpoint request must wait until all earlier terminal output is acknowledged');
assert.match(terminalBridge, /postMessageEvent\(packet\.buffer\)/,
  'terminal output must use one raw binary WebMessagePort push path');
assert.match(terminalBridge, /BINARY_HEADER_BYTES:\s*number = 12/,
  'terminal packets must carry only magic, sequence, and payload length');
assert.match(terminalBridge, /inFlightMessages < TerminalBridge\.MAX_IN_FLIGHT_MESSAGES/,
  'normal output must leave queued data in the bridge while xterm drains its bounded pipeline');
assert.doesNotMatch(terminalBridge, /Base64Helper|pullOutput|outputAvailable/,
  'terminal output must not retain the rejected Base64 pull transport');
assert.doesNotMatch(terminalBridge, /TextDecoder|LOSSY_OUTPUT_CHUNK_CHARACTERS/,
  'the native terminal transport must not decode or heuristically rewrite terminal bytes');
assert.doesNotMatch(terminalBridge, /LTTY_(?:BEGIN|END|KEY)_|scanValidationMarkers|sentAtLow32/,
  'temporary cross-layer marker and delivery-timestamp diagnostics must not remain in the bridge');
assert.doesNotMatch(terminalBridge, /replay/i,
  'the bridge must have only one ordered output path and no historical replay state');

const bridgeProtocol = readFileSync(
  new URL('../../entry/src/main/ets/model/bridge/BridgeProtocol.ets', import.meta.url), 'utf8');
assert.match(bridgeProtocol, /KIND_BELL_ATTENTION/,
  'the bridge allowlist must name the coalesced attention state rather than a raw BEL event');
assert.doesNotMatch(bridgeProtocol, /KIND_BELL\b|KIND_TITLE\b/,
  'the bridge allowlist must not restore raw bell or remote-title messages');
assert.doesNotMatch(bridgeProtocol, /replay/i,
  'historical replay must not remain in the bridge protocol allowlist');
assert.doesNotMatch(bridgeProtocol, /releaseBuffers|KIND_RELEASE_BUFFERS/,
  'disconnect cleanup must not expose a bridge command that clears a live terminal surface');
assert.match(bridgeProtocol, /KIND_OPEN_URL:\s*string = 'openUrl'/,
  'browser requests must cross the typed web-to-native control allowlist');

const sessionViewModel = readFileSync(
  new URL('../../entry/src/main/ets/viewmodel/SessionViewModel.ets', import.meta.url), 'utf8');
assert.doesNotMatch(sessionViewModel, /KIND_BELL_ATTENTION|case BridgeProtocol\.KIND_(?:BELL|TITLE)\b/,
  'bell attention belongs to the terminal surface and app shell, not the SSH session');
assert.match(sessionViewModel,
  /private onSshClose[\s\S]*?releaseDisconnectedFlowControl\(\)[\s\S]*?writeTerminal\([\s\S]*?writePrompt\(\)/,
  'disconnect cleanup must release output flow control before appending the local close message and prompt');
assert.match(sessionViewModel,
  /if \(parsed === null\) \{\s*this\.writeError\("Unknown command\. Type 'help' for commands, or use: ssh user@host"\)/,
  'unknown idle commands must point to both local help and the direct SSH path');

const terminalSurfaceController = readFileSync(
  new URL('../../entry/src/main/ets/model/terminal/TerminalSurfaceController.ets', import.meta.url), 'utf8');
assert.match(terminalSurfaceController,
  /msg\.kind === BridgeProtocol\.KIND_BELL_ATTENTION[\s\S]*onBellAttentionHandler/,
  'the terminal surface must consume bell attention before generic session message routing');
assert.match(terminalSurfaceController,
  /msg\.kind === BridgeProtocol\.KIND_OPEN_URL[\s\S]*onOpenUrlHandler/,
  'the terminal surface must consume browser requests before generic SSH session routing');
assert.doesNotMatch(terminalSurfaceController, /getHistoryChunks|queueReplay|replayedHistory/,
  'the rejected raw byte history replay buffer must not return');
assert.match(terminalSurfaceController,
  /bridge\.restoreSnapshot\(snapshot\)[\s\S]*?takeDetachedChunks/,
  'a replacement surface must restore its checkpoint before detached output');
assert.match(terminalSurfaceController,
  /msg\.kind === BridgeProtocol\.KIND_SNAPSHOT[\s\S]*?requestIdText[\s\S]*?lastCommittedSnapshotRequestId[\s\S]*?replaceSnapshot/,
  'only a sequenced current-bridge checkpoint may replace the session recovery snapshot');
assert.match(terminalSurfaceController, /takeDetachedChunks/,
  'a new terminal surface must take only output produced while no surface was attached');
assert.doesNotMatch(terminalSurfaceController, /releaseBuffers|term\.clear|term\.reset/,
  'disconnect cleanup must not ask a live terminal surface to clear its screen or scrollback');

const indexPage = readFileSync(
  new URL('../../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.doesNotMatch(indexPage, /recyclePaneWebViewWhenDrained/,
  'normal disconnect and failure must keep the current terminal surface mounted');
assert.match(indexPage, /runtime\.surface\.setOnOpenUrl\(/,
  'each terminal surface must route URL requests through its owning pane');
assert.match(indexPage,
  /private onMainWindowVisibilityChanged[\s\S]*?captureMountedTerminalSnapshots\(\)/,
  'backgrounding the window must checkpoint every currently mounted terminal');
assert.match(indexPage,
  /private checkpointAndDestroyTabBridge[\s\S]*?checkpointingTabIds[\s\S]*?runtime\.surface\.captureSnapshot\(\(\) =>[\s\S]*?finishTabCheckpoint/,
  'an idle tab must remain mounted until its asynchronous eviction checkpoint completes');
assert.match(indexPage, /BrowserLauncher\.open\(/,
  'the ArkUI shell must hand validated HTTP(S) links to the HarmonyOS system browser');
assert.doesNotMatch(indexPage, /requestCopySelection|['"]Copy['"]/,
  'the tool menu must not keep a standalone Copy action');
assert.match(indexPage, /for \(let i = 0; i < 6; i\+\+\)/,
  'keyboard menu selection must traverse the six remaining actions');
assert.match(indexPage, /\(next \+ direction \+ 6\) % 6/,
  'keyboard menu selection must wrap across the six remaining actions');
assert.match(indexPage,
  /selected === 3\) \{ this\.handleFontIncrease\(\)[\s\S]*selected === 4\) \{ this\.handleFontReset\(\)[\s\S]*selected === 5\) \{ this\.handleFontDecrease\(\)/,
  'Enter dispatch must map the reindexed font actions in menu order');
assert.match(indexPage,
  /menuRow\(3, 'A⁺', 'Font Size \+'[\s\S]*menuRow\(4, 'Aa', 'Reset Font Size'[\s\S]*menuRow\(5, 'A⁻', 'Font Size -'/,
  'the rendered menu must retain the three font actions at indices 3 through 5');

const terminalPane = readFileSync(
  new URL('../../entry/src/main/ets/view/components/TerminalPane.ets', import.meta.url), 'utf8');
assert.match(terminalPane, /renderMode:\s*RenderMode\.ASYNC_RENDER/,
  'terminal panes must use the normal asynchronous ArkWeb render mode');
assert.match(terminalPane, /sharedRenderProcessToken:\s*'leantty-terminal'/,
  'terminal panes keep the measured shared renderer-process configuration');
assert.doesNotMatch(terminalPane, /\.onRenderProcess(?:NotResponding|Responding)\(/,
  'temporary ArkWeb renderer responsiveness diagnostics must not remain');
assert.doesNotMatch(terminalPane, /\.javaScriptProxy\(/,
  'the terminal pane must not expose the rejected output-pull proxy');
assert.match(terminalPane, /@Prop needsAttention: boolean = false/,
  'the pane must render its app-shell-owned attention state');

const chromeBar = readFileSync(
  new URL('../../entry/src/main/ets/view/components/ChromeBar.ets', import.meta.url), 'utf8');
assert.match(chromeBar, /tabRenderKey[\s\S]*tabNeedsAttention\(tab\)/,
  'the tab render key must change when nested pane attention changes');
assert.match(chromeBar,
  /\.constraintSize\(\{\s*maxWidth:\s*'calc\(100% - 172vp\)'\s*\}\)/,
  'the tab strip must use parent layout space left after fixed controls and drag space');
assert.doesNotMatch(chromeBar, /maxWidth:\s*'\d+%'/,
  'the tab strip must not be capped at a fixed percentage of wide windows');
assert.doesNotMatch(chromeBar, /chromeBarWidth|\.onAreaChange\(/,
  'the tab strip must not create a self-measurement feedback loop');

console.log('terminal policy tests passed');
