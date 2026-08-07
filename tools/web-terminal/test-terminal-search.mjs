import assert from 'node:assert/strict';

const SEARCH_OPTIONS = {
  regex: false,
  wholeWord: false,
  caseSensitive: false,
  decorations: {
    matchBackground: '#45475A',
    matchBorder: '#585B70',
    matchOverviewRuler: '#89B4FA',
    activeMatchBackground: '#585B70',
    activeMatchBorder: '#89B4FA',
    activeMatchColorOverviewRuler: '#89B4FA'
  }
};

function write(terminal, data) {
  return new Promise(resolve => terminal.write(data, resolve));
}

async function waitFor(predicate, description, timeoutMs = 1500) {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) {
      assert.fail(`timed out waiting for ${description}`);
    }
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}

function createHarness(TerminalCtor, SearchAddonCtor, options = {}) {
  const terminal = new TerminalCtor({
    cols: options.cols ?? 24,
    rows: options.rows ?? 4,
    scrollback: options.scrollback ?? 100,
    allowProposedApi: true
  });
  const addon = new SearchAddonCtor({ highlightLimit: 1000 });
  let selection = null;
  let results = { resultIndex: -1, resultCount: 0 };
  const originalScrollLines = terminal.scrollLines.bind(terminal);

  terminal.select = (column, row, size) => {
    const endOffset = column + size;
    selection = {
      start: { x: column, y: row },
      end: {
        x: endOffset % terminal.cols,
        y: row + Math.floor(endOffset / terminal.cols)
      }
    };
  };
  terminal.getSelectionPosition = () => selection;
  terminal.clearSelection = () => { selection = null; };
  terminal.scrollLines = amount => { originalScrollLines(amount); };

  terminal.loadAddon(addon);
  const resultListener = addon.onDidChangeResults(event => {
    if (event) results = event;
  });

  return {
    terminal,
    addon,
    selection: () => selection,
    results: () => results,
    dispose() {
      resultListener.dispose();
      addon.dispose();
      terminal.dispose();
    }
  };
}

function restartSearch(harness, query, options = SEARCH_OPTIONS) {
  harness.addon.clearDecorations();
  harness.terminal.clearSelection();
  return harness.addon.findNext(query, options);
}

async function testOrdinaryTextAndNavigation(TerminalCtor, SearchAddonCtor) {
  const harness = createHarness(TerminalCtor, SearchAddonCtor);
  try {
    await write(harness.terminal, 'Alpha beta\r\nalpha gamma\r\nbeta alpha');

    assert.equal(restartSearch(harness, 'alpha'), true);
    assert.deepEqual(harness.selection()?.start, { x: 0, y: 0 });
    assert.deepEqual(harness.results(), { resultIndex: 0, resultCount: 3 });
    assert.equal(harness.addon.findNext('alpha', SEARCH_OPTIONS), true);
    assert.deepEqual(harness.selection()?.start, { x: 0, y: 1 });
    assert.deepEqual(harness.results(), { resultIndex: 1, resultCount: 3 });
    assert.equal(harness.addon.findNext('alpha', SEARCH_OPTIONS), true);
    assert.deepEqual(harness.selection()?.start, { x: 5, y: 2 });
    assert.deepEqual(harness.results(), { resultIndex: 2, resultCount: 3 });
    assert.equal(harness.addon.findNext('alpha', SEARCH_OPTIONS), true);
    assert.deepEqual(harness.selection()?.start, { x: 0, y: 0 },
      'next must wrap from the final match to the first');
    assert.equal(harness.addon.findPrevious('alpha', SEARCH_OPTIONS), true);
    assert.deepEqual(harness.selection()?.start, { x: 5, y: 2 },
      'previous must wrap from the first match to the final match');

    assert.equal(restartSearch(harness, 'Alpha', { ...SEARCH_OPTIONS, caseSensitive: true }), true);
    assert.deepEqual(harness.results(), { resultIndex: 0, resultCount: 1 });
    assert.equal(restartSearch(harness, 'ALPHA', { ...SEARCH_OPTIONS, caseSensitive: true }), false);
    assert.equal(harness.selection(), null);
    assert.deepEqual(harness.results(), { resultIndex: -1, resultCount: 0 });
    harness.terminal.select(3, 1, 2);
    assert.equal(harness.addon.findNext('', SEARCH_OPTIONS), false);
    assert.equal(harness.selection(), null, 'an empty query must clear the addon selection');
  } finally {
    harness.dispose();
  }
}

async function testUnicodeWideAndWrappedText(TerminalCtor, SearchAddonCtor) {
  const harness = createHarness(TerminalCtor, SearchAddonCtor, { cols: 12, rows: 5 });
  try {
    await write(harness.terminal, '前缀中文后缀\r\nemoji 🚀 done\r\nwrap-中文-tail');
    assert.equal(restartSearch(harness, '中文'), true);
    assert.deepEqual(harness.selection()?.start, { x: 4, y: 0 });
    assert.deepEqual(harness.selection()?.end, { x: 8, y: 0 },
      'two CJK characters must occupy four terminal cells');
    assert.equal(restartSearch(harness, '🚀'), true);
    assert.deepEqual(harness.selection()?.start, { x: 6, y: 1 });
    assert.deepEqual(harness.selection()?.end, { x: 7, y: 1 },
      'a surrogate-pair emoji must count as one xterm buffer cell, not two JavaScript code units');
    assert.equal(restartSearch(harness, '中文-tail'), true);
    assert.equal(harness.selection()?.start.y, 2);
    assert.ok(harness.selection().end.y > harness.selection().start.y,
      'a match spanning a soft-wrapped line must retain one logical result');
  } finally {
    harness.dispose();
  }
}

async function testNormalAndAlternateBuffers(TerminalCtor, SearchAddonCtor) {
  const harness = createHarness(TerminalCtor, SearchAddonCtor);
  try {
    await write(harness.terminal, 'normal-target');
    await write(harness.terminal, '\u001b[?1049h');
    await write(harness.terminal, 'alternate-target');
    assert.equal(harness.terminal.buffer.active.type, 'alternate');
    assert.equal(restartSearch(harness, 'normal-target'), false,
      'alternate-buffer search must not read normal-buffer scrollback');
    assert.equal(restartSearch(harness, 'alternate-target'), true);
    await write(harness.terminal, '\u001b[?1049l');
    assert.equal(harness.terminal.buffer.active.type, 'normal');
    assert.equal(restartSearch(harness, 'alternate-target'), false,
      'normal-buffer search must not retain alternate-buffer content');
    assert.equal(restartSearch(harness, 'normal-target'), true);
  } finally {
    harness.dispose();
  }
}

async function testLargeScrollback(TerminalCtor, SearchAddonCtor) {
  const harness = createHarness(TerminalCtor, SearchAddonCtor, { cols: 40, rows: 4, scrollback: 10000 });
  try {
    const lines = [];
    for (let index = 0; index < 2000; index++) {
      const marker = index === 7 || index === 1997 ? ' scrollback-target' : '';
      lines.push(`line-${index.toString().padStart(4, '0')}${marker}`);
    }
    await write(harness.terminal, lines.join('\r\n'));
    assert.ok(harness.terminal.buffer.active.baseY > 1900,
      'fixture must place most content in scrollback');
    assert.equal(restartSearch(harness, 'scrollback-target'), true);
    assert.equal(harness.results().resultCount, 2);
    const firstRow = harness.selection().start.y;
    assert.equal(harness.addon.findNext('scrollback-target', SEARCH_OPTIONS), true);
    assert.ok(harness.selection().start.y > firstRow + 1900,
      'navigation must reach a match near the end of a large scrollback buffer');
  } finally {
    harness.dispose();
  }
}

async function testOngoingOutputAndRapidQueries(TerminalCtor, SearchAddonCtor) {
  const harness = createHarness(TerminalCtor, SearchAddonCtor, { cols: 32, rows: 6 });
  try {
    await write(harness.terminal, 'steady output');
    assert.equal(restartSearch(harness, 'arrived'), false);
    await write(harness.terminal, '\r\narrived-one\r\narrived-two');
    await waitFor(() => harness.results().resultCount === 2, 'ongoing-output search refresh');
    assert.equal(harness.results().resultCount, 2,
      'cached search must refresh after ongoing terminal output is parsed');

    await write(harness.terminal, '\r\nalpha alphabet beta 中文 alpha');
    const queries = ['a', 'al', 'alp', 'alpha', 'missing', '中文', 'beta', 'alpha'];
    for (let iteration = 0; iteration < 80; iteration++) {
      const query = queries[iteration % queries.length];
      const found = restartSearch(harness, query);
      assert.equal(found, query !== 'missing', `rapid query must remain deterministic: ${query}`);
    }
    assert.equal(restartSearch(harness, 'alpha'), true);
    assert.ok(harness.results().resultCount >= 3);
  } finally {
    harness.dispose();
  }
}

export async function runTerminalSearchTests(TerminalCtor, SearchAddonCtor) {
  await testOrdinaryTextAndNavigation(TerminalCtor, SearchAddonCtor);
  await testUnicodeWideAndWrappedText(TerminalCtor, SearchAddonCtor);
  await testNormalAndAlternateBuffers(TerminalCtor, SearchAddonCtor);
  await testLargeScrollback(TerminalCtor, SearchAddonCtor);
  await testOngoingOutputAndRapidQueries(TerminalCtor, SearchAddonCtor);
  console.log('terminal search matrix tests passed');
}
