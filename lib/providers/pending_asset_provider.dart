// lib/providers/pending_asset_provider.dart
//
// One-shot hand-off channel that lets an external surface (Add funds →
// From crypto) open the Receive flow straight on its cross-asset picker.
//
// The Receive screen's source-asset picker is private, so the cleanest
// cross-screen hook is a StateProvider the caller sets BEFORE pushing the
// route; ConfirmReceive reads-and-clears it in `initState`. "One-shot":
// the consumer immediately resets the value after reading so a later
// organic open of Receive doesn't spuriously re-trigger the picker.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One-shot flag: when true, the Receive flow auto-opens the FULL
/// "Receive other assets" source-asset picker (no asset pre-selected).
/// Set by the Add Funds method picker's "From crypto" tile;
/// read-and-cleared in `ConfirmReceive.initState`.
final pendingReceiveOpenOtherAssetsProvider =
    StateProvider<bool>((ref) => false);
