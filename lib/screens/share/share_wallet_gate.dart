// lib/screens/share/share_wallet_gate.dart
//
// THE WALLET ON THE FIRST ACTION (founder, 27 November 2026: "allow them to
// place bet instantly"). A slip opened with no wallet at all (a shared
// market's guest page, share_guest_screen.dart) meets this gate first: the
// slip never opens on a wallet that does not exist, and nothing is created
// until the person asks for it.
//
// One step, in the app's own sheet: the passkey wording onboarding uses
// for this browser ("Unlock with Face ID" over "Kute uses Face ID to
// protect your wallet ..."), a line telling an in-app browser's visitor to
// open the page in Safari or Chrome, and one primary button, Create
// account. The button runs the app's own creation, shortened for a share
// arrival: set the PIN, the wallet (a passkey on Kute's own home where this
// browser can make one, else 12 words), then straight back to the market
// with the pick's slip (share_target_opener.dart). No survey, no code
// screens (founder decision 5); the referral code the link carried binds
// through the existing authWallet as the pending referrer.
//
// A 12-word wallet made this way shows its words first (the backup flow)
// and cannot show any receive address until they are backed up
// ([ShareQuickWallets.receiveBlocked], receive_sheet.dart).
//
// NOT YET: a passkey wallet without a PIN. The PIN step stays in front of
// the passkey because the web vault, the unlock screen, the lock overlay
// and the step-up's fallback all need a PIN today; a passkey-only vault is
// a separate, reviewed change.
//
// A region that refuses the venue's trading shows the policy's own sheet
// ("check your VPN settings") instead, and nothing is made.
//
// Analytics: `quick_wallet_started {entry_source: share_link, venue,
// browser}` on the button, `quick_wallet_abandoned {entry_source, stage:
// gate, venue}` when the sheet closes without it; `quick_wallet_completed`
// and `quick_wallet_failed` come from the creation (passkey_choice.dart).

import 'dart:async';

import 'package:flutter/foundation.dart'
    show immutable, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/helpers/passkey_account_name.dart'
    show webBiometricMethodName;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/in_app_browser.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/share_target.dart';
import 'package:kute/services/share_targets.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// What the person tapped, carried through the wallet step for the slip
/// it reopens: the outcome's name (or `long` / `short`) and whether it was
/// the No side.
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

  /// The pick waiting for its slip once the wallet exists; memory only.
  static ShareWalletPick? _pendingPick;
  static DateTime? _startedAt;

  /// Reads and clears the pick waiting for its slip.
  static ShareWalletPick? takePendingPick() {
    final p = _pendingPick;
    _pendingPick = null;
    return p;
  }

  /// Whether Create account was tapped in this run.
  static bool get started => _startedAt != null;

  /// Milliseconds since Create account was tapped (null: not this run).
  static int? get elapsedMs {
    final t = _startedAt;
    return t == null ? null : DateTime.now().difference(t).inMilliseconds;
  }

  @visibleForTesting
  static void debugReset() {
    _pendingPick = null;
    _startedAt = null;
  }

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

  /// The way to a wallet for the slip the person tapped on [target]: the
  /// region check, then the one step (see the file header). The market and
  /// the [pick]'s slip open again once the wallet exists; [resume] is the
  /// slip itself, for a caller still on screen then.
  static Future<void> open(BuildContext context,
      {required ShareTarget? target,
      ShareWalletPick pick = const ShareWalletPick(),
      required VoidCallback resume}) async {
    final capability =
        target?.investing ?? false ? 'hyperliquid.trade' : 'polymarket.trade';
    // No policy read yet: the slip gates itself as always.
    final policy = RuntimeCapabilitiesService.instance;
    if (policy.snapshot != null || policy.publicSnapshot != null) {
      final decision = policy.decision(capability);
      if (!decision.allowed) {
        await showCapabilityDecisionSheet(context, decision,
            capability: capability, surface: 'share_guest');
        return;
      }
    }
    if (!context.mounted) return;
    final venue = target?.venue.analyticsVenue ?? 'unknown';
    final go = await showAppBottomSheet<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'share_wallet_gate'),
      builder: (_) => const _GateSheet(),
    );
    if (go != true) {
      TrackingService.track('quick_wallet_abandoned', params: {
        'entry_source': 'share_link',
        'stage': 'gate',
        'venue': venue,
      });
      return;
    }
    _startedAt = DateTime.now();
    _pendingPick = pick;
    TrackingService.track('quick_wallet_started', params: {
      'entry_source': 'share_link',
      'venue': venue,
      'browser': InAppBrowser.kind,
    });
    if (target != null) {
      ShareTargets.parkForOnboarding(target);
    } else {
      ShareTargets.markArrivedThroughShare();
    }
    if (context.mounted) unawaited(GoRouter.of(context).push('/set_pin'));
  }
}

/// The gate's one step.
class _GateSheet extends StatelessWidget {
  const _GateSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final method = webBiometricMethodName(context);
    final inApp = InAppBrowser.isInApp;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: method == null
                ? l10n.passkeyChoiceTitleNoBiometrics
                : l10n.passkeyChoiceTitle(method),
            subtitle:
                method == null ? null : l10n.passkeyChoiceSubtitle(method),
            icon: Icons.account_balance_wallet_outlined,
          ),
          if (inApp)
            Padding(
              key: const ValueKey('share-gate-in-app'),
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Text(
                InAppBrowser.isApple
                    ? l10n.shareOpenInBrowserSafari
                    : l10n.shareOpenInBrowserChrome,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
            child: KuteBarContextScope(
              barContext: KuteBarContext.primary(
                label: l10n.createAccount,
                onPrimary: () => Navigator.of(context).pop(true),
                category: SearchCategory.all,
                source: 'share_wallet_gate',
                disabledLabel: null,
              ),
              child: SizedBox(height: kuteBarScrollClearance.h),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 12-word wallets made from a share link on this browser, which may
/// not receive anything until their words were shown and confirmed
/// (founder decision 4). Kept in the share box by wallet id.
abstract final class ShareQuickWallets {
  /// Marks [walletId] as a quick 12-word wallet.
  static void mark(String walletId) =>
      ShareLinksStore.markQuickWallet(walletId);

  /// Whether the active spending wallet must back up before it receives:
  /// a quick 12-word wallet whose words are not backed up.
  static bool receiveBlocked(WidgetRef ref) {
    final w = ref.read(settingsProvider).activeWallet;
    if (w == null || w.isPasskey || w.backedUp) return false;
    return ShareLinksStore.isQuickWallet(w.id);
  }
}
