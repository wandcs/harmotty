import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import '../../entry/src/main/resources/rawfile/terminal-policy.js';

const policy = globalThis.HarmoTTYTerminalPolicy;
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
assert.equal(bellAttention.clear(), true);
assert.equal(bellAttention.clear(), false);
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

const terminalHtml = readFileSync(new URL('../../entry/src/main/resources/rawfile/terminal.html', import.meta.url), 'utf8');
assert.match(terminalHtml, /addEventListener\('wheel', handleAlternateWheel, true\)/,
  'alternate-buffer wheel handling must run during capture before xterm scrolls its inner viewport');
assert.match(terminalHtml, /#terminal-container > \.xterm\s*\{[^}]*padding:\s*4px 6px;/s,
  'terminal cells must keep compact vertical and horizontal padding from pane edges');
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
assert.doesNotMatch(terminalHtml, /harmottyOutput\.pullOutput|decodePulledTerminalPacket|case 'outputAvailable':/,
  'the rejected synchronous Base64 pull experiment must not remain in the terminal path');
assert.match(terminalHtml, /term\.write\(terminalBytes/,
  'the terminal must receive the original Uint8Array bytes rather than a decoded string');
assert.doesNotMatch(terminalHtml,
  /outputBurst|validationMarker|HTTY_(?:BEGIN|END|KEY)_|samplePortDelivery|TERMINAL_RENDERER_MODE/,
  'temporary binary-output and renderer diagnostics must not remain in the terminal runtime');
assert.doesNotMatch(terminalHtml, /replayGate|replayBegin|replayEnd/,
  'terminal history must not be replayed into a new xterm instance');
assert.doesNotMatch(terminalHtml, /releaseBuffers|term\.clear\(\)|term\.reset\(\)/,
  'normal disconnect cleanup must not clear the current xterm screen or scrollback');
assert.match(terminalHtml, /term\.onBell\s*\(/,
  'xterm must remain the semantic source for terminal bell events');
assert.match(terminalHtml,
  /term\.onBell\s*\(function\(\)\s*\{\s*if\s*\(bellAttentionGate\.trigger\(\)\)\s*\{\s*sendBridgeControl\('bellAttention', ''\)/s,
  'a BEL flood must cross the bridge only after the source-side attention gate accepts it');
assert.doesNotMatch(terminalHtml, /term\.onBell\s*\(function\(\)\s*\{\s*sendBridgeControl\('bellAttention'/s,
  'bell attention must never be sent directly for every parsed BEL');
assert.match(terminalHtml, /term\.onTitleChange\s*\(/,
  'the local performance-marker parser must continue to observe title sequences');
assert.doesNotMatch(terminalHtml, /sendBridgeControl\('title'/,
  'ordinary remote title changes must not cross the bridge when the product does not consume them');

const terminalBridge = readFileSync(
  new URL('../../entry/src/main/ets/model/bridge/TerminalBridge.ets', import.meta.url), 'utf8');
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
assert.doesNotMatch(terminalBridge, /HTTY_(?:BEGIN|END|KEY)_|scanValidationMarkers|sentAtLow32/,
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

const sessionViewModel = readFileSync(
  new URL('../../entry/src/main/ets/viewmodel/SessionViewModel.ets', import.meta.url), 'utf8');
assert.doesNotMatch(sessionViewModel, /KIND_BELL_ATTENTION|case BridgeProtocol\.KIND_(?:BELL|TITLE)\b/,
  'bell attention belongs to the terminal surface and app shell, not the SSH session');
assert.match(sessionViewModel,
  /private onSshClose[\s\S]*?releaseDisconnectedFlowControl\(\)[\s\S]*?writeTerminal\([\s\S]*?writePrompt\(\)/,
  'disconnect cleanup must release output flow control before appending the local close message and prompt');

const terminalSurfaceController = readFileSync(
  new URL('../../entry/src/main/ets/model/terminal/TerminalSurfaceController.ets', import.meta.url), 'utf8');
assert.match(terminalSurfaceController,
  /msg\.kind === BridgeProtocol\.KIND_BELL_ATTENTION[\s\S]*onBellAttentionHandler/,
  'the terminal surface must consume bell attention before generic session message routing');
assert.doesNotMatch(terminalSurfaceController, /getHistoryChunks|queueReplay|replayedHistory/,
  'a new terminal surface must not receive already displayed terminal history');
assert.match(terminalSurfaceController, /takeDetachedChunks/,
  'a new terminal surface must take only output produced while no surface was attached');
assert.doesNotMatch(terminalSurfaceController, /releaseBuffers|term\.clear|term\.reset/,
  'disconnect cleanup must not ask a live terminal surface to clear its screen or scrollback');

const indexPage = readFileSync(
  new URL('../../entry/src/main/ets/pages/Index.ets', import.meta.url), 'utf8');
assert.doesNotMatch(indexPage, /recyclePaneWebViewWhenDrained/,
  'normal disconnect and failure must keep the current terminal surface mounted');

const terminalPane = readFileSync(
  new URL('../../entry/src/main/ets/view/components/TerminalPane.ets', import.meta.url), 'utf8');
assert.match(terminalPane, /renderMode:\s*RenderMode\.ASYNC_RENDER/,
  'terminal panes must use the normal asynchronous ArkWeb render mode');
assert.match(terminalPane, /sharedRenderProcessToken:\s*'harmotty-terminal'/,
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

console.log('terminal policy tests passed');
