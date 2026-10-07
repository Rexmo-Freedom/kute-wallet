// lib/screens/activity/activity_history_screen.dart
//
// Every transaction, on its own screen.
//
// The Activity pill on Home, on Dollars and on a hardware wallet shows
// a preview: the four most recent rows, because the strip it sits in
// also has to hold a chart. There was no way past those four. Tapping
// the pill a second time did nothing, which is the obvious thing to
// try and the reason this screen exists.
//
// It is the same [TransactionList] the preview renders, with the cap
// off and the same scope the surface that opened it was showing, so a
// row reads identically in both places and nothing had to be rebuilt
// to say the same thing twice.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({
    super.key,
    this.walletIdOverride,
    this.onlyUsdb = false,
    this.title,
  });

  /// Scopes the list to one wallet's own history, for a hardware or
  /// watch-only wallet whose rows do not live on the active wallet.
  final String? walletIdOverride;

  /// The dollar ledger alone, matching the Dollars tab's preview.
  final bool onlyUsdb;

  /// Overrides the heading where the surface has a better word for
  /// what these rows are than the generic one.
  final String? title;

  static const routeName = 'activity-history';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const KuteBackButton(),
        automaticallyImplyLeading: false,
        title: Text(
          title ?? context.l10n.activity,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: PlatformSafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: 8.h, bottom: 24.h),
          child: TransactionList(
            walletIdOverride: walletIdOverride,
            onlyUsdb: onlyUsdb,
            showAll: true,
          ),
        ),
      ),
    );
  }
}

/// Opens [ActivityHistoryScreen] over whatever is on screen.
///
/// [source] is the categorical surface the "See all" came from; when a
/// caller leaves it null it is inferred from the scope (Dollars passes
/// [onlyUsdb], a wallet tab passes [walletIdOverride]).
Future<void> showActivityHistory(
  BuildContext context, {
  String? walletIdOverride,
  bool onlyUsdb = false,
  String? title,
  String? source,
}) {
  // The pushed route already reports a `$screen`; this adds where it was
  // opened from and which ledger it lists. Fires once per open (the tap),
  // never on rebuild. No wallet id: `scope` is categorical.
  final scope = onlyUsdb
      ? 'usd'
      : walletIdOverride != null
          ? 'wallet'
          : 'active_wallet';
  TrackingService.track('activity_history_opened', params: {
    'entry_source': source ??
        (onlyUsdb
            ? 'usd_tab'
            : walletIdOverride != null
                ? 'wallet_detail'
                : 'home'),
    'scope': scope,
  });
  return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: ActivityHistoryScreen.routeName),
        builder: (_) => ActivityHistoryScreen(
          walletIdOverride: walletIdOverride,
          onlyUsdb: onlyUsdb,
          title: title,
        ),
      ),
    );
}
