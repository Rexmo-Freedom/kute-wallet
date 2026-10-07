import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/polymarket_model.dart' show ActivityType;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show
        activityDaySections,
        buildUnifiedTransactionItem,
        predictionResultTransactions;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Full bet history — every prediction the user placed, sold, won or
/// lost, in one dedicated surface reached from the History button at
/// the left of the Predictions category pills.
///
/// Deliberately a THIN filter over the same [PolymarketTransaction]
/// rows the activity feed renders (`buildUnifiedTransactionItem`), so
/// titles, crest icons, amounts, and the tap-through detail sheets all
/// stay pixel-identical to the feed — one rendering path, no drift.
/// Predictions deposit/withdraw rows are INCLUDED (user decision —
/// this is the full Predictions ledger, money movements and bets),
/// rendered with the same ₿↔$ conversion styling as the feed.
class PredictionHistoryScreen extends ConsumerWidget {
  final bool embedded;
  const PredictionHistoryScreen({super.key, this.embedded = false});

  static const routeName = 'polymarket-prediction-history';

  static void show(BuildContext context) {
    TrackingService.screenView('prediction_history');
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const PredictionHistoryScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Same scope-aware source as the activity feed. Bet lifecycle rows
    // (trades placed/sold, redeems won/lost) PLUS the Predictions
    // deposit/withdraw money movements (user decision — this page is
    // the full Predictions ledger, so the ₿↔$ conversion rows belong
    // here even though the home feed collapses them behind bet rows).
    final txs = ref.watch(scopedTransactionsProvider);
    final bets = <BaseTransaction>[
      ...txs.polymarketTransactions.where(
        (t) =>
            t.activityType == ActivityType.trade ||
            t.activityType == ActivityType.redeem,
      ),
      // The results the history does not record: a lost prediction is
      // never claimed, so only its resolved market says it lost (and a
      // win shows here until it is claimed).
      ...predictionResultTransactions(ref, txs.polymarketTransactions),
      // Orchestra conversion legs whose USDC side is Polygon = the
      // Predictions deposit/withdraw rows (same predicate the feed's
      // _buildSwapOrderItem uses to title them).
      ...txs.swapOrderTransactions.where((e) {
        final d = e.details;
        return d.isOrchestra &&
            ((d.coinTo == 'USDC' && d.networkTo == 'POLYGON') ||
                (d.coinFrom == 'USDC' && d.networkFrom == 'POLYGON'));
      }),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final content = Column(
      children: [
        if (!embedded)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
            child: Row(
              children: [
                const KuteCloseButton(),
                SizedBox(width: 14.w),
                Text(
                  context.l10n.betHistoryTitle,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          // Embedded, the tab runs under the Portfolio's dock: the empty
          // state keeps clear of it, the list keeps its last row clear.
          child: bets.isEmpty
              ? (embedded
                  ? KuteDockClearance(child: _EmptyHistory(c: c))
                  : _EmptyHistory(c: c))
              // Same day cards, headers and rows as Home and the
              // wallets.
              : ListView(
                  padding: EdgeInsets.fromLTRB(0, 4.h, 0,
                      40.h + (embedded ? kuteDockScrollClearance(context) : 0)),
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  children: activityDaySections<BaseTransaction>(
                    bets,
                    timeOf: (tx) => tx.timestamp,
                    rowOf: (tx) => buildUnifiedTransactionItem(tx, context, ref),
                  ),
                ),
        ),
      ],
    );
    if (embedded) return content;
    return Scaffold(
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(child: content),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final AppColorsExtension c;
  const _EmptyHistory({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 40.sp, color: c.textTertiary),
          SizedBox(height: 12.h),
          Text(
            context.l10n.betHistoryEmpty,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            context.l10n.betHistoryEmptyBody,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
