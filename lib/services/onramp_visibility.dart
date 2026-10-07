// lib/services/onramp_visibility.dart
//
// Whether an onramp (a way outside money comes into Kute) may appear on
// screen at all.
//
// AN ONRAMP THE POLICY DOES NOT OFFER IS NOT SHOWN (founder decision,
// October 2026, replacing September's "listed, disabled, wearing the
// reason"). Denied, switched off, coming soon, or no policy to read: no
// tile, no row, no chip, no badge and no door whose only purpose is that
// onramp. Doors that opened on it open on their own non-fiat source
// instead. Every onramp surface asks this one function, so a new
// `onramp.*` capability follows the rule without any screen changing.
//
// THE TOP-LEVEL BUY DOORS ARE THE EXCEPTION (founder decision, October
// 2026): Purchase on Home and the wallet detail, "Add funds" in the Move
// sheet and the venue buy doors are always drawn. Tapped with no onramp on offer ([anyOnrampVisible] false,
// or no policy), they open the shared unavailable sheet saying no purchase
// providers are available instead of a buy. The rails inside the picker
// stay hidden exactly as above.
//
// Execution is still gated where the order is created (the Orchestra
// client checks the capability again); this decides visibility only.

import 'package:kute/services/runtime_capabilities_service.dart';

/// Cash App, through the Flashnet Lightning onramp.
const kOnrampCashApp = 'onramp.cashapp';

/// The bank transfer rail.
const kOnrampBank = 'onramp.bank';

/// True only while the runtime policy offers onramp [id] outright:
/// allowed and not coming soon.
///
/// No policy reads as hidden. [RuntimeCapabilitiesService.allows] already
/// answers false for an onramp then, because onramps are neither
/// location-advisory nor exits, and a denial seen earlier this session
/// still stands; `test/services/onramp_visibility_test.dart` pins it.
///
/// Call it with a policy obtained through `ref.watch` in a build, so the
/// surface follows an admin switch live.
bool onrampVisible(RuntimeCapabilitiesService policy, String id) {
  assert(id.startsWith('onramp.'), 'onrampVisible takes an onramp.* id');
  return policy.allows(id);
}

/// True while the runtime policy offers at least one onramp. False with
/// no policy. A top-level Buy door asks this at the tap.
bool anyOnrampVisible(RuntimeCapabilitiesService policy) =>
    onrampVisible(policy, kOnrampCashApp) ||
    onrampVisible(policy, kOnrampBank);
