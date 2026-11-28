/// Which secret unlocks the wallet in this browser: the 6-digit PIN, or a
/// typed password for a vault that was made with one.
///
/// THE RULE (founder, 27 November 2026, reversing the 24 November choice
/// of a password on laptop browsers): one secret on the web, the 6-digit
/// PIN, on every browser. A NEW web vault is always made with the PIN; on
/// a laptop the PIN pad also takes digits and Backspace from the keyboard.
/// The founder was told plainly, and accepted, that a PIN vault in a
/// laptop browser can be guessed offline from a copied browser profile
/// (10^6 guesses; seed_vault.dart, the threat note).
///
/// AN EXISTING VAULT KEEPS ITS KIND: a vault made with a password between
/// 24 and 27 November 2026 still asks for that password, and nothing is
/// migrated or weakened silently. Changing its secret in Settings sets a
/// PIN (the person types the current password, then a new PIN twice).
/// There is no "password upgrade" step any more: a PIN vault in a laptop
/// browser stays a PIN vault. The iOS and Android apps never get here:
/// off the web every answer is [VaultSecretKind.pin].
///
/// THE ONE PLACE THAT DECIDES: [current], what the unlock and every gate
/// ask for: the kind recorded in the vault (a vault always unlocks with
/// the kind it was made with); before any vault, the PIN.
library;

import 'package:flutter/foundation.dart';

import 'package:kute/services/secure/web_vault/seed_vault.dart'
    show VaultSecretKind;
import 'package:kute/services/secure/web_vault/web_vault.dart';

export 'package:kute/services/secure/web_vault/seed_vault.dart'
    show VaultSecretKind;

abstract final class UnlockSecret {
  /// Tests: the vault's recorded kind.
  @visibleForTesting
  static VaultSecretKind? debugVaultKind;

  /// The kind the unlock and every gate ask for (see the file header).
  static VaultSecretKind get current {
    final debug = debugVaultKind;
    if (debug != null) return debug;
    final web = WebVault.instance;
    if (web == null) return VaultSecretKind.pin;
    if (web.vault.exists) return web.vault.secretKind ?? VaultSecretKind.pin;
    // The old localStorage layout holds a PIN; a new vault takes one.
    return VaultSecretKind.pin;
  }
}
