// lib/services/polymarket/fast_bet_window.dart
//
// The fast-bet window (owner decision, 2026-10): repeated orders on the
// Polymarket short crypto rounds (5 and 15 minute Up/Down) place with one
// tap after one fresh approval.
//
//   * Opens on a fresh step-up (Face ID, or the Kute PIN fallback) that
//     approved a hot (spending wallet) buy or sell on a 5 or 15 minute
//     Up/Down round, while a short-round screen is up ([enterScope]).
//   * While open, a further buy or sell on a short round gets an
//     `AuthGrant(method: fastWindow)` without a prompt. That grant is the
//     same single-use, 60 s grant a prompt gives, bound to that order's
//     own review intent (its stake cap, worst price and slippage), so the
//     executor's send-time checks (book at most 1 s old, never past the
//     approved max) are unchanged.
//   * Buys spend from a [buyCapCents] budget (the review cap of each
//     order, rounded up), booked in the same synchronous call that issues
//     the grant, so two quick taps can never both pass the cap. Sells do
//     not count.
//   * Ends on: [duration] elapsed; a buy that would pass the cap (that buy
//     prompts, and its approval opens a fresh window); the last
//     short-round screen closing; the app paused or hidden, or inactive
//     for longer than [inactiveGrace] (a biometric sheet the app opened
//     itself does not count); the session lock; a new or cleared session
//     (logout, wipe); a different spending wallet.
//
// What it holds: the approved wallet id, the unlocked session it was
// approved in (by identity), the open and end times and the cents booked.
// Never key material: the Predictions signer is the account's own
// in-memory key, which the trading provider already holds for the
// unlocked session and checks against that same session before each
// signature. Nothing here is persisted or logged, and [end] drops every
// field.

import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/polymarket/crypto_round.dart';

/// Why a window ended. Local only (tests, debugging); never tracked.
enum FastBetWindowEnd {
  expired,
  capReached,
  leftScreens,
  background,
  sessionLock,
  sessionChanged,
  walletChanged,
  replaced,
}

/// Whether the event with [slug] is a 5 or 15 minute crypto Up/Down round
/// (`btc-updown-5m-1791152100`, `eth-updown-15m-1791152100`). Hourly,
/// 4-hour and daily Up/Down markets are not.
bool polyIsFastBetRound(String? slug) {
  if (slug == null || slug.isEmpty) return false;
  final round = polyCryptoRoundOf(slug);
  if (round == null) return false;
  return round.window == const Duration(minutes: 5) ||
      round.window == const Duration(minutes: 15);
}

/// What a step-up caller tells the window about the order it approves.
class FastBetRequest {
  const FastBetRequest({required this.eventSlug, required this.hot});

  /// The event slug of the order's market.
  final String? eventSlug;

  /// The order signs with the spending wallet (never a Ledger).
  final bool hot;

  bool get eligible => hot && polyIsFastBetRound(eventSlug);
}

class _OpenWindow {
  _OpenWindow({
    required this.walletId,
    required this.session,
    required this.openedAt,
    required this.endsAt,
  });

  final String walletId;
  final Object session;
  final DateTime openedAt;
  final DateTime endsAt;
  int spentCents = 0;
}

class FastBetWindow {
  FastBetWindow({DateTime Function()? clock, AuthGrantRegistry? registry})
      : _clock = clock ?? (() => AuthGrants.clock()),
        _registry = registry;

  /// The app-wide window. Tests construct their own.
  static final FastBetWindow instance = FastBetWindow();

  static const Duration duration = Duration(minutes: 10);

  /// Cumulative buy budget of one window, in cents ($50).
  static const int buyCapCents = 5000;

  /// How long `inactive` (Control Center, a notification pulled down) may
  /// last before it ends the window. `paused` and `hidden` end it at once.
  static const Duration inactiveGrace = Duration(seconds: 3);

  final DateTime Function() _clock;
  final AuthGrantRegistry? _registry;

  _OpenWindow? _window;
  int _scopes = 0;
  Timer? _expiry;
  Timer? _inactive;
  FastBetWindowEnd? _lastEnd;

  AuthGrantRegistry get _grants => _registry ?? AuthGrantRegistry.instance;

  bool get isOpen {
    final w = _window;
    if (w == null) return false;
    if (!_clock().isBefore(w.endsAt)) {
      end(FastBetWindowEnd.expired);
      return false;
    }
    return true;
  }

  /// Short-round screens up right now.
  int get scopes => _scopes;

  /// Cents booked by buys in the open window (0 when closed).
  int get spentCents => _window?.spentCents ?? 0;

  /// Why the last window ended. Tests only.
  @visibleForTesting
  FastBetWindowEnd? get lastEnd => _lastEnd;

  /// True when any window field or timer is still held. Tests only.
  @visibleForTesting
  bool get debugHoldsState =>
      _window != null || _expiry != null || _inactive != null;

  // ── Scope (the short-round screens) ─────────────────────────────────

  /// A short-round screen came up (`FastBetScope`).
  void enterScope() => _scopes++;

  /// A short-round screen went away. The last one ends the window.
  void exitScope() {
    if (_scopes > 0) _scopes--;
    if (_scopes == 0) end(FastBetWindowEnd.leftScreens);
  }

  // ── Open / issue ────────────────────────────────────────────────────

  static bool _isPlainOrder(SensitiveIntent intent) {
    if (intent.venue != IntentVenue.polymarket) return false;
    if (intent.action != SensitiveAction.pmBet &&
        intent.action != SensitiveAction.pmSell) {
      return false;
    }
    // Combos and Builder runs are never short-round orders.
    if (intent.limits.containsKey(IntentLimit.legs)) return false;
    if (intent.limits.containsKey(IntentLimit.orderKind)) return false;
    return true;
  }

  static bool _isPromptMethod(AuthGrantMethod m) =>
      m == AuthGrantMethod.biometric ||
      m == AuthGrantMethod.pin ||
      m == AuthGrantMethod.pinThenBiometric;

  /// Opens a fresh window after a prompt approved [intent] in [session].
  /// Ignored unless [request] is eligible, a short-round screen is up,
  /// the session is unlocked and [method] was a real prompt. A window
  /// already open is replaced (its budget starts again from zero).
  void open(
    SensitiveIntent intent, {
    required FastBetRequest request,
    required AuthGrantMethod method,
    required Object? session,
    required bool sessionUnlocked,
  }) {
    if (!request.eligible ||
        !_isPromptMethod(method) ||
        !_isPlainOrder(intent) ||
        session == null ||
        !sessionUnlocked ||
        _scopes == 0 ||
        intent.walletId.isEmpty) {
      return;
    }
    if (_window != null) end(FastBetWindowEnd.replaced);
    final now = _clock();
    _window = _OpenWindow(
      walletId: intent.walletId,
      session: session,
      openedAt: now,
      endsAt: now.add(duration),
    );
    _expiry = Timer(duration, () => end(FastBetWindowEnd.expired));
  }

  /// A grant for [intent] from the open window, or null when it must
  /// prompt. Synchronous on purpose: the cap check and the booking happen
  /// together, so concurrent taps cannot both pass the cap.
  ///
  /// [amountUsdCents] is the USD value of a buy's `amountMax`, rounded up
  /// (ignored for sells).
  AuthGrant? tryIssue(
    SensitiveIntent intent, {
    required FastBetRequest request,
    required int amountUsdCents,
    required Object? session,
    required bool sessionUnlocked,
  }) {
    final w = _window;
    if (w == null) return null;
    if (!request.eligible || !_isPlainOrder(intent)) return null;
    if (!_clock().isBefore(w.endsAt)) {
      end(FastBetWindowEnd.expired);
      return null;
    }
    if (_scopes == 0) {
      end(FastBetWindowEnd.leftScreens);
      return null;
    }
    if (!sessionUnlocked) {
      end(FastBetWindowEnd.sessionLock);
      return null;
    }
    if (session == null || !identical(session, w.session)) {
      end(FastBetWindowEnd.sessionChanged);
      return null;
    }
    if (intent.walletId != w.walletId) {
      end(FastBetWindowEnd.walletChanged);
      return null;
    }
    final isBuy = intent.action == SensitiveAction.pmBet;
    if (isBuy) {
      if (amountUsdCents <= 0) return null;
      // The cents must cover the bound base units (pUSD, 6 decimals), so
      // a mismatched figure cannot slip a larger buy past the budget.
      if (intent.amountMax > BigInt.from(amountUsdCents) * BigInt.from(10000)) {
        return null;
      }
      if (w.spentCents + amountUsdCents > buyCapCents) {
        end(FastBetWindowEnd.capReached);
        return null;
      }
    }
    final AuthGrant grant;
    try {
      grant = _grants.issue(intent, method: AuthGrantMethod.fastWindow);
    } on ArgumentError {
      return null;
    }
    if (isBuy) w.spentCents += amountUsdCents;
    return grant;
  }

  // ── End ─────────────────────────────────────────────────────────────

  /// Ends the window and drops everything it held. Idempotent.
  void end(FastBetWindowEnd reason) {
    _expiry?.cancel();
    _expiry = null;
    _inactive?.cancel();
    _inactive = null;
    if (_window == null) return;
    _window = null;
    _lastEnd = reason;
  }

  /// App lifecycle, from `FastBetScope`. [selfPrompt] is true while a
  /// biometric sheet the app opened is up (`PrivacyCoverBridge`).
  void onLifecycle(AppLifecycleState state, {bool selfPrompt = false}) {
    switch (state) {
      case AppLifecycleState.resumed:
        _inactive?.cancel();
        _inactive = null;
      case AppLifecycleState.inactive:
        if (selfPrompt || _window == null || _inactive != null) return;
        _inactive = Timer(inactiveGrace, () {
          _inactive = null;
          end(FastBetWindowEnd.background);
        });
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        end(FastBetWindowEnd.background);
    }
  }

  /// Clears the window and the scope count. Tests only.
  @visibleForTesting
  void debugReset() {
    end(FastBetWindowEnd.replaced);
    _scopes = 0;
    _lastEnd = null;
  }

  /// The `approval` value on the order events: how the order was approved.
  static String approvalParam(AuthGrantMethod method) => switch (method) {
        AuthGrantMethod.fastWindow => 'fast_window',
        AuthGrantMethod.allowance => 'allowance',
        AuthGrantMethod.biometric ||
        AuthGrantMethod.pin ||
        AuthGrantMethod.pinThenBiometric =>
          'biometric',
      };
}
