(function(global) {
  'use strict';

  var MAX_CLIPBOARD_BYTES = 1024 * 1024;
  var MAX_CLIPBOARD_BASE64_LENGTH = Math.ceil(MAX_CLIPBOARD_BYTES / 3) * 4;

  function rejectOsc52(reason) {
    return { accepted: false, text: '', reason: reason, byteLength: 0 };
  }

  function decodeOsc52(payload) {
    if (typeof payload !== 'string') return rejectOsc52('invalid-payload');
    var separator = payload.indexOf(';');
    if (separator < 0) return rejectOsc52('missing-separator');
    var target = payload.substring(0, separator);
    var encoded = payload.substring(separator + 1);
    // OSC 52 uses an empty selector for the default clipboard. tmux emits
    // this form when copy-mode completes a selection.
    if (target !== '' && target !== 'c') return rejectOsc52('unsupported-target');
    if (encoded === '?') return rejectOsc52('read-not-supported');
    if (encoded.length > MAX_CLIPBOARD_BASE64_LENGTH) return rejectOsc52('encoded-too-large');
    if (encoded.length % 4 === 1 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
      return rejectOsc52('invalid-base64');
    }
    try {
      var binary = global.atob(encoded);
      if (binary.length > MAX_CLIPBOARD_BYTES) return rejectOsc52('decoded-too-large');
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      var text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      return { accepted: true, text: text, reason: 'ok', byteLength: bytes.length };
    } catch (ex) {
      return rejectOsc52('invalid-utf8');
    }
  }

  function createWheelState() {
    return {
      pendingLines: 0,
      velocityPixelsPerMs: 0,
      lastEventTime: -1,
      direction: 0
    };
  }

  function createBellAttentionGate() {
    var deliveryPending = false;
    var acknowledgementPending = false;
    return {
      trigger: function() {
        acknowledgementPending = true;
        if (deliveryPending) return false;
        deliveryPending = true;
        return true;
      },
      acknowledge: function() {
        if (!acknowledgementPending) return false;
        acknowledgementPending = false;
        deliveryPending = false;
        return true;
      },
      rearmDelivery: function() {
        if (!deliveryPending) return false;
        deliveryPending = false;
        return true;
      },
      isPending: function() { return acknowledgementPending; }
    };
  }

  function countPerfPayloadBytes(payload) {
    if (typeof payload !== 'string') return 0;
    var count = 0;
    for (var i = 0; i < payload.length; i++) {
      if (payload.charCodeAt(i) === 88) count++;
    }
    return count;
  }

  function wheelGain(speedPixelsPerMs) {
    var speed = Math.abs(speedPixelsPerMs);
    if (speed <= 0.5) return 0.4;
    if (speed <= 1.5) return 0.4 + (speed - 0.5) * 1.6;
    if (speed >= 4) return 8;
    return 2 + (speed - 1.5) / 2.5 * 6;
  }

  function enqueueWheel(state, deltaY, deltaMode, cellHeight, rows, timestamp) {
    if (!state || deltaY === 0) return;
    var safeCellHeight = Math.max(1, cellHeight);
    var safeRows = Math.max(1, rows);
    var deltaPixels = deltaY;
    if (deltaMode === 1) deltaPixels = deltaY * safeCellHeight;
    else if (deltaMode === 2) deltaPixels = deltaY * safeCellHeight * safeRows;
    var direction = deltaPixels < 0 ? -1 : 1;
    var eventTime = typeof timestamp === 'number' ? timestamp : 0;
    var eventGap = state.lastEventTime >= 0 ? eventTime - state.lastEventTime : 0;
    if (eventGap > 80) {
      state.pendingLines = 0;
      state.velocityPixelsPerMs = 0;
      state.direction = 0;
    }
    var elapsed = state.lastEventTime >= 0 ? Math.max(1, Math.min(100, eventGap)) : 16;
    var instantVelocity = deltaPixels / elapsed;
    if (state.direction !== 0 && state.direction !== direction) {
      state.pendingLines = 0;
      state.velocityPixelsPerMs = instantVelocity;
    } else if (state.lastEventTime < 0) {
      state.velocityPixelsPerMs = instantVelocity;
    } else {
      state.velocityPixelsPerMs = state.velocityPixelsPerMs * 0.65 + instantVelocity * 0.35;
    }
    state.direction = direction;
    state.lastEventTime = eventTime;
    var gain = deltaMode === 0 ? wheelGain(state.velocityPixelsPerMs) : 1;
    state.pendingLines += deltaPixels / safeCellHeight * gain;
    var maxPendingLines = safeRows * 8;
    state.pendingLines = Math.max(-maxPendingLines, Math.min(maxPendingLines, state.pendingLines));
  }

  function consumeWheelFrame(state, rows) {
    if (!state || Math.abs(state.pendingLines) < 1) return 0;
    var whole = state.pendingLines < 0 ? Math.ceil(state.pendingLines) : Math.floor(state.pendingLines);
    var maxSteps = Math.max(8, Math.floor(Math.max(1, rows) * 1.25));
    var steps = Math.max(-maxSteps, Math.min(maxSteps, whole));
    state.pendingLines -= steps;
    return steps;
  }

  function hasPendingWheelSteps(state) {
    return !!state && Math.abs(state.pendingLines) >= 1;
  }

  function pendingWheelLines(state) {
    return state ? state.pendingLines : 0;
  }

  function centerGridLeadingPadding(baseLeadingPadding, baseTrailingPadding, containerSize, gridSize) {
    var leading = typeof baseLeadingPadding === 'number' && isFinite(baseLeadingPadding)
      ? Math.max(0, baseLeadingPadding)
      : 0;
    var trailing = typeof baseTrailingPadding === 'number' && isFinite(baseTrailingPadding)
      ? Math.max(0, baseTrailingPadding)
      : 0;
    if (typeof containerSize !== 'number' || !isFinite(containerSize) ||
        typeof gridSize !== 'number' || !isFinite(gridSize)) {
      return leading;
    }
    var unusedSize = containerSize - leading - trailing - Math.max(0, gridSize);
    return leading + Math.max(0, unusedSize) / 2;
  }

  function isLinkModifierActive(event, mouseTrackingMode) {
    if (!event ||
        event.ctrlKey !== true ||
        event.altKey === true ||
        event.metaKey === true) {
      return false;
    }
    if (mouseTrackingMode === 'none') {
      return event.shiftKey !== true;
    }
    var mouseReportingActive =
      mouseTrackingMode === 'x10' ||
      mouseTrackingMode === 'vt200' ||
      mouseTrackingMode === 'drag' ||
      mouseTrackingMode === 'any';
    return mouseReportingActive && event.shiftKey === true;
  }

  function shouldActivateLink(event, mouseTrackingMode, sameLink, dragged) {
    return !!event &&
      event.button === 0 &&
      sameLink === true &&
      dragged !== true &&
      isLinkModifierActive(event, mouseTrackingMode);
  }

  global.LeanTTYTerminalPolicy = {
    MAX_CLIPBOARD_BYTES: MAX_CLIPBOARD_BYTES,
    MAX_CLIPBOARD_BASE64_LENGTH: MAX_CLIPBOARD_BASE64_LENGTH,
    decodeOsc52: decodeOsc52,
    countPerfPayloadBytes: countPerfPayloadBytes,
    createBellAttentionGate: createBellAttentionGate,
    createWheelState: createWheelState,
    enqueueWheel: enqueueWheel,
    consumeWheelFrame: consumeWheelFrame,
    hasPendingWheelSteps: hasPendingWheelSteps,
    pendingWheelLines: pendingWheelLines,
    centerGridLeadingPadding: centerGridLeadingPadding,
    isLinkModifierActive: isLinkModifierActive,
    shouldActivateLink: shouldActivateLink
  };
})(globalThis);
