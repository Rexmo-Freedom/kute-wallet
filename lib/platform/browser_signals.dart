/// What the browser says about its pointer, touch screen and user agent.
/// Web only: off the web [readBrowserSignals] is null.
///
/// It once picked the web vault's secret (a password on a laptop, the PIN
/// on a touch-first browser); since 27 November 2026 every new web vault
/// takes the PIN (unlock_secret.dart), and these signals only tell which
/// kind of browser the page runs in.
library;

import 'package:flutter/foundation.dart';

import 'browser_signals_native.dart'
    if (dart.library.js_interop) 'browser_signals_web.dart' as impl;

@immutable
class BrowserSignals {
  const BrowserSignals({
    required this.maxTouchPoints,
    required this.coarsePointer,
    required this.noHover,
    required this.userAgent,
  });

  /// `navigator.maxTouchPoints`.
  final int maxTouchPoints;

  /// `matchMedia('(pointer: coarse)')`: the PRIMARY pointer is a finger.
  final bool coarsePointer;

  /// `matchMedia('(hover: none)')`: the primary pointer cannot hover.
  final bool noHover;
  final String userAgent;

  static final RegExp _touchAgent =
      RegExp(r'iPhone|iPad|iPod|Android|Mobi', caseSensitive: false);

  /// A laptop or desktop browser: not touch-first. A browser whose
  /// primary pointer is coarse or cannot hover, a phone or iPad user
  /// agent, or a "Mac" with touch points (iPadOS Safari reports itself as
  /// a Mac; real Macs have no touch screen) is touch-first. Anything else
  /// (a touch-screen Windows laptop driven by a mouse included) is a
  /// laptop.
  bool get isLaptop {
    if (coarsePointer || noHover) return false;
    if (_touchAgent.hasMatch(userAgent)) return false;
    if (userAgent.contains('Macintosh') && maxTouchPoints > 1) return false;
    return true;
  }
}

/// Tests: the signals, as if in a browser that reports them.
@visibleForTesting
BrowserSignals? debugBrowserSignals;

/// The browser's signals, or null off the web (or when it would not say).
BrowserSignals? readBrowserSignals() =>
    debugBrowserSignals ?? (kIsWeb ? impl.readBrowserSignals() : null);
