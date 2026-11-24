/// Which secret unlocks the wallet in this browser: the 6-digit PIN or a
/// typed password (founder, 24 November 2026: "on web, allow for user to
/// put in a password (stronger); only on iPad allow for manual").
///
/// The web vault's one real weakness is a copied browser profile: with
/// it, the derivation runs offline and a 6-digit PIN (10^6 guesses) falls
/// quickly (seed_vault.dart, the threat note). A laptop or desktop
/// browser therefore locks with a password of at least
/// [VaultSecretKind.minPasswordLength] characters; a touch-first browser
/// (iPad, phone) keeps the PIN pad as it is. The iOS and Android apps
/// never get here: off the web every answer is [VaultSecretKind.pin].
///
/// THE ONE PLACE THAT DECIDES:
///   * [deviceKind]: what a NEW vault in this browser is made with. A
///     browser whose primary pointer is coarse or cannot hover (`(pointer:
///     coarse)`, `(hover: none)`), a phone or iPad user agent, or a "Mac"
///     with touch points (iPadOS Safari reports itself as a Mac; real Macs
///     have no touch screen) is touch-first: PIN. Anything else (a laptop
///     or desktop, a touch-screen Windows laptop driven by a mouse and a
///     trackpad included) is a laptop: password. Read once per session.
///   * [current]: what the unlock asks for: the kind recorded in the
///     vault (a vault always unlocks with the kind it was made with,
///     whatever the device reports later); before any vault, [deviceKind].
///   * [needsPasswordUpgrade]: a PIN vault in a laptop browser. After its
///     PIN unlocks it, the app has the person create a password once
///     before going on; until then the PIN still opens it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import 'package:kute/services/secure/web_vault/seed_vault.dart'
    show VaultSecretKind;
import 'package:kute/services/secure/web_vault/web_vault.dart';

import 'unlock_secret_native.dart'
    if (dart.library.js_interop) 'unlock_secret_web.dart' as impl;

export 'package:kute/services/secure/web_vault/seed_vault.dart'
    show VaultSecretKind;

/// What the browser says about its pointer and touch screen.
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
}

abstract final class UnlockSecret {
  /// Tests: the device's kind, as if in a browser of that kind.
  @visibleForTesting
  static VaultSecretKind? debugDeviceKind;

  /// Tests: the vault's recorded kind.
  @visibleForTesting
  static VaultSecretKind? debugVaultKind;

  static VaultSecretKind? _cached;

  static final RegExp _touchAgent =
      RegExp(r'iPhone|iPad|iPod|Android|Mobi', caseSensitive: false);

  /// The classing rule (see the file header). [signals] null (the browser
  /// would not say) is a laptop: the stronger secret.
  static VaultSecretKind classify(BrowserSignals? signals) {
    if (signals == null) return VaultSecretKind.password;
    if (signals.coarsePointer || signals.noHover) return VaultSecretKind.pin;
    final ua = signals.userAgent;
    if (_touchAgent.hasMatch(ua)) return VaultSecretKind.pin;
    if (ua.contains('Macintosh') && signals.maxTouchPoints > 1) {
      return VaultSecretKind.pin;
    }
    return VaultSecretKind.password;
  }

  /// The kind a new vault in this browser is made with. Always the PIN
  /// off the web.
  static VaultSecretKind get deviceKind {
    final debug = debugDeviceKind;
    if (debug != null) return debug;
    if (!kIsWeb) return VaultSecretKind.pin;
    return _cached ??= classify(impl.readBrowserSignals());
  }

  /// The kind the unlock and every gate ask for (see the file header).
  static VaultSecretKind get current {
    final debug = debugVaultKind;
    if (debug != null) return debug;
    final web = WebVault.instance;
    if (web == null) return deviceKind;
    if (web.vault.exists) return web.vault.secretKind ?? VaultSecretKind.pin;
    // The old localStorage layout holds a PIN.
    if (web.hasPinMaterial) return VaultSecretKind.pin;
    return deviceKind;
  }

  /// The kind a CHANGED secret takes: a password stays a password, and a
  /// laptop browser always moves to one.
  static VaultSecretKind get forChange =>
      current == VaultSecretKind.password ||
              deviceKind == VaultSecretKind.password
          ? VaultSecretKind.password
          : VaultSecretKind.pin;

  /// A PIN vault in a laptop browser: a password must be created once.
  static bool get needsPasswordUpgrade =>
      current == VaultSecretKind.pin &&
      deviceKind == VaultSecretKind.password;

  /// The only rule: [VaultSecretKind.minPasswordLength] characters or
  /// more, as the person sees them. No composition rules.
  static bool meetsRule(String password) =>
      password.characters.length >= VaultSecretKind.minPasswordLength;
}
