// lib/screens/activity/activity_history_screen.dart
//
// Every transaction, on its own screen.
//
// The Activity pill on Home, on Dollars and on a hardware wallet shows a
// preview: the most recent rows, because the strip it sits in also has to
// hold a chart. Once selected the pill reads "See all" and opens this
// screen.
//
// Without a wallet and outside the Dollars ledger it lists the spending
// wallet's merged activity in one chronological list with day headers, no
// filters, no tabs, built a page at a time as it scrolls
// (AllActivitySliver), in a scope (all_activity.dart): opened from the
// Bitcoin home, the Bitcoin scope (founder, 4 November 2026: bitcoin sends
// and receives, and money moving into or out of bitcoin; no prediction or
// Investing fill); from an Investments surface, the Investments scope;
// otherwise (a money move's own link) everything. The share links this
// wallet sent and nobody has claimed yet stay at its top.
//
// The Dollars tab ([onlyUsdb]) and a hardware or watch-only wallet
// ([walletIdOverride]) keep their own ledger: the same [TransactionList]
// their preview renders, uncapped.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/all_activity.dart'
    show ActivityScope, AllActivitySliver;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;

import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class ActivityHistoryScreen extends StatefulWidget {
  const ActivityHistoryScreen({
    super.key,
    this.walletIdOverride,
    this.onlyUsdb = false,
    this.title,
    this.investments = false,
    this.scope,
  });

  /// Scopes the list to one wallet's own history, for a hardware or
  /// watch-only wallet whose rows do not live on the active wallet.
  final String? walletIdOverride;

  /// The dollar ledger alone, matching the Dollars tab's preview.
  final bool onlyUsdb;

  /// Overrides the heading where the surface has a better word for
  /// what these rows are than the generic one.
  final String? title;

  /// Opened from an Investments surface: the Investments scope, unless
  /// [scope] says otherwise.
  final bool investments;

  /// What the merged list shows ([ActivityScope]); null: the Investments
  /// scope when [investments], else everything.
  final ActivityScope? scope;

  static const routeName = 'activity-history';

  /// Whether this screen lists the spending wallet's merged activity (in
  /// [listedScope]) rather than one ledger.
  bool get listsAll => walletIdOverride == null && !onlyUsdb;

  /// The scope the merged list is read in.
  ActivityScope get listedScope =>
      scope ?? (investments ? ActivityScope.investments : ActivityScope.all);

  @override
  State<ActivityHistoryScreen> createState() => _ActivityHistoryScreenState();
}

class _ActivityHistoryScreenState extends State<ActivityHistoryScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
          widget.title ?? context.l10n.activity,
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
        child: widget.listsAll
            ? CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverPadding(padding: EdgeInsets.only(top: 8.h)),
                  // Share links this wallet sent and nobody has claimed
                  // or that still wait to be paid: not transactions yet.
                  const SliverToBoxAdapter(child: PendingShareLinksCard()),
                  AllActivitySliver(
                      controller: _scroll, scope: widget.listedScope),
                  // The last rows scroll clear of the floating bar.
                  SliverPadding(
                      padding: EdgeInsets.only(
                          bottom: 24.h + kuteBarScrollClearance.h)),
                ],
              )
            : SingleChildScrollView(
                // The last rows scroll clear of the floating bar.
                padding: EdgeInsets.only(
                    top: 8.h, bottom: 24.h + kuteBarScrollClearance.h),
                child: TransactionList(
                  walletIdOverride: widget.walletIdOverride,
                  onlyUsdb: widget.onlyUsdb,
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
/// [onlyUsdb], a wallet tab passes [walletIdOverride]). [investments]
/// marks an Investments surface (the Investments scope); [scope] names the
/// merged list's scope outright (the Bitcoin home passes
/// [ActivityScope.bitcoin]).
Future<void> showActivityHistory(
  BuildContext context, {
  String? walletIdOverride,
  bool onlyUsdb = false,
  String? title,
  String? source,
  bool investments = false,
  ActivityScope? scope,
}) {
  final screen = ActivityHistoryScreen(
    walletIdOverride: walletIdOverride,
    onlyUsdb: onlyUsdb,
    title: title,
    investments: investments,
    scope: scope,
  );
  // The pushed route already reports a `$screen`; this adds where it was
  // opened from and which ledger it lists. Fires once per open (the tap),
  // never on rebuild. No wallet id: `scope` is categorical ('usd',
  // 'wallet', or the merged list's scope: 'all', 'bitcoin',
  // 'investments').
  final scopeName = onlyUsdb
      ? 'usd'
      : walletIdOverride != null
          ? 'wallet'
          : screen.listedScope.name;
  TrackingService.track('activity_history_opened', params: {
    'entry_source': source ??
        (onlyUsdb
            ? 'usd_tab'
            : walletIdOverride != null
                ? 'wallet_detail'
                : investments
                    ? 'investments'
                    : 'home'),
    'scope': scopeName,
  });
  return Navigator.of(context, rootNavigator: true).push<void>(
    KutePageRoute<void>(
      settings: const RouteSettings(name: ActivityHistoryScreen.routeName),
      builder: (_) => screen,
    ),
  );
}
