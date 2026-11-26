/// Where a passkey wallet's credential lives: its WebAuthn Relying Party.
///
/// A passkey belongs to exactly one RP and can never move to another, and
/// a passkey wallet's seed comes out of the passkey (PRF), so the RP is
/// part of the wallet's identity. Every passkey wallet record carries a
/// provider marker (`WalletConfig.passkeyProvider`) that names its home:
///
///   * `null`         → LEGACY (pre-2.x) wallet on the Breez RP, derived
///                      through the app's own `PasskeyPrfService`
///                      (`PasskeyService.getLegacySeed`), never the SDK.
///   * `'breez-0.17'` → the Breez SDK `PasskeyClient` on Breez's shared RP
///                      `keys.breez.technology`. Every wallet created
///                      before Kute had its own RP. Stays there forever.
///   * `'kute-1'`     → the Breez SDK `PasskeyClient` on Kute's own RP
///                      `kutewallet.com` (rpName "Kute"). New wallets.
///
/// Any other marker FAILS CLOSED ([UnknownPasskeyProvider]): a wallet whose
/// home is not known must never be derived on some default RP, which would
/// produce a different (empty) wallet.
///
/// This file is the one mapping from marker to home and RP id.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// A Relying Party the SDK's `PasskeyClient` derives wallets on.
enum PasskeyHome {
  /// Breez's shared RP, `keys.breez.technology`.
  breez,

  /// Kute's own RP, `kutewallet.com`.
  kute;

  /// The value analytics carry (`passkey_home`): `breez` or `kute`.
  String get analyticsValue => name;
}

/// How a passkey wallet's seed is resolved, from its marker.
enum PasskeyRoute {
  /// Pre-2.x wallet: `PasskeyService.getLegacySeed` only.
  legacy,

  /// SDK `PasskeyClient` on [PasskeyHome.breez].
  breez,

  /// SDK `PasskeyClient` on [PasskeyHome.kute].
  kute,
}

/// A wallet record carries a passkey provider marker this build does not
/// know. Thrown instead of guessing a home.
class UnknownPasskeyProvider implements Exception {
  const UnknownPasskeyProvider(this.marker);

  /// The marker as stored (a short constant, never secret).
  final String marker;

  @override
  String toString() => 'UnknownPasskeyProvider($marker)';
}

abstract final class PasskeyHomes {
  /// Marker of wallets on the Breez RP through the SDK. HISTORICAL literal
  /// (minted on SDK 0.17.1), persisted on every such wallet: never rename.
  static const String markerBreez = 'breez-0.17';

  /// Marker of wallets on Kute's own RP through the SDK. Persisted on every
  /// such wallet: never rename.
  static const String markerKute = 'kute-1';

  /// Breez's shared RP (the SDK's default when no rpId is given).
  static const String breezRpId = 'keys.breez.technology';

  /// Kute's own RP. The web app lives on a subdomain of it.
  static const String kuteRpId = 'kutewallet.com';

  /// The RP name the OS passkey sheets show for Kute's RP.
  static const String kuteRpName = 'Kute';

  /// The route for a wallet's [marker]. Throws [UnknownPasskeyProvider]
  /// for any marker other than null, [markerBreez] and [markerKute].
  static PasskeyRoute routeFor(String? marker) {
    switch (marker) {
      case null:
        return PasskeyRoute.legacy;
      case markerBreez:
        return PasskeyRoute.breez;
      case markerKute:
        return PasskeyRoute.kute;
      default:
        throw UnknownPasskeyProvider(marker);
    }
  }

  /// The SDK home of a wallet's [marker]. Legacy (`null`) wallets have no
  /// SDK home (they derive through `getLegacySeed`), so null throws too,
  /// as does an unknown marker.
  static PasskeyHome homeForMarker(String? marker) {
    switch (routeFor(marker)) {
      case PasskeyRoute.breez:
        return PasskeyHome.breez;
      case PasskeyRoute.kute:
        return PasskeyHome.kute;
      case PasskeyRoute.legacy:
        throw ArgumentError.value(
            marker,
            'marker',
            'A legacy passkey wallet has no SDK home; it derives via '
                'PasskeyService.getLegacySeed.');
    }
  }

  /// The marker a wallet created or restored on [home] is stamped with.
  static String markerFor(PasskeyHome home) => switch (home) {
        PasskeyHome.breez => markerBreez,
        PasskeyHome.kute => markerKute,
      };

  /// The RP id of [home].
  static String rpIdFor(PasskeyHome home) => switch (home) {
        PasskeyHome.breez => breezRpId,
        PasskeyHome.kute => kuteRpId,
      };

  /// Whether a web page on [host] may run WebAuthn ceremonies for Kute's
  /// RP: the RP id itself or any subdomain of it (WebAuthn's registrable
  /// suffix rule). `localhost` and every other host answer false.
  static bool hostIsKute(String host) {
    final h = host.toLowerCase();
    return h == kuteRpId || h.endsWith('.$kuteRpId');
  }

  /// Web only: the page is served from Kute's RP (or a subdomain), so the
  /// Kute home's passkeys work here. False on native and on any other host
  /// (localhost included). Breez-home and legacy passkeys never work on
  /// the web: Breez's RP does not list Kute's website.
  static bool get webPageOnKuteHome => kIsWeb && hostIsKute(Uri.base.host);

  /// The homes a fresh-install passkey restore looks in, in order: Breez
  /// first, then Kute on iOS / Android; Kute only on the web.
  static List<PasskeyHome> restoreOrder({required bool web}) => web
      ? const [PasskeyHome.kute]
      : const [PasskeyHome.breez, PasskeyHome.kute];
}
