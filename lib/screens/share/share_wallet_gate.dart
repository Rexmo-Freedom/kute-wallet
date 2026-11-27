// lib/screens/share/share_wallet_gate.dart
//
// THE WALLET ON THE FIRST ACTION (founder, 27 November 2026: "allow them to
// place bet instantly"). A slip opened with no wallet at all (a shared
// market's guest page, share_guest_screen.dart) meets this gate first: the
// slip never opens on a wallet that does not exist, and nothing is created
// until the person asks for it.

import 'package:flutter/foundation.dart'
    show immutable, kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';

/// What the person tapped, carried through the wallet step for analytics
/// and the slip it reopens: the outcome's name (or `long` / `short`) and
/// whether it was the No side.
@immutable
class ShareWalletPick {
  const ShareWalletPick({this.outcome, this.buyNo = false});
  final String? outcome;
  final bool buyNo;
}

abstract final class ShareWalletGate {
  /// Test seam: pins whether the gate applies (null: the web only).
  @visibleForTesting
  static bool? debugWeb;

  /// Whether a slip opened from [context] has no wallet behind it: the web
  /// with no wallet in this browser. Ledger and send-mode slips never come
  /// here (they need a wallet to exist to be opened at all).
  static bool needsWallet(BuildContext context) {
    if (!(debugWeb ?? kIsWeb)) return false;
    try {
      return ProviderScope.containerOf(context, listen: false)
          .read(settingsProvider)
          .wallets
          .isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Opens the way to a wallet for the slip [resume] would open, with
  /// [target] parked so the market opens again once the wallet exists.
  static Future<void> open(BuildContext context,
      {required ShareTarget? target,
      ShareWalletPick pick = const ShareWalletPick(),
      required VoidCallback resume}) async {
    // A region that refuses the venue's trading says so first, with the
    // policy's own sheet ("check your VPN settings"): no wallet is made for
    // a bet that could not be placed here. No policy read yet: the slip
    // gates itself as always.
    final capability =
        target?.investing ?? false ? 'hyperliquid.trade' : 'polymarket.trade';
    final policy = RuntimeCapabilitiesService.instance;
    if (policy.snapshot != null || policy.publicSnapshot != null) {
      final decision = policy.decision(capability);
      if (!decision.allowed) {
        await showCapabilityDecisionSheet(context, decision,
            capability: capability, surface: 'share_guest');
        return;
      }
    }
    if (target != null) ShareLinksStore.parkShareTarget(target.encode());
    if (context.mounted) context.go('/splash');
  }
}
