// lib/screens/polymarket/components/combo_detail_sheet.dart
//
// One held Polymarket combo (parlay): the legs with their live prices and
// status, an ESTIMATED value chart (the product of the legs' price
// histories, with a "Bought" line at the stake), "Close combo" (a SELL
// RFQ: the exact proceeds, confirm, accept) and "Claim" once it settled.
//
// There is no combo price feed, so the chart and the value are estimates
// and say so. A SELL quote is the only exact exit price; it is never
// polled as a price feed, only requested when the user opens Close.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketPricePoint;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolyPriceHistoryCache;
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/combo_copy.dart';
import 'package:kute/screens/polymarket/components/combo_position_card.dart'
    show comboLegColor, comboLegStatusText;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/polymarket/combos/combo_analytics.dart';
import 'package:kute/services/polymarket/combos/combo_math.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// ESTIMATED combo value over the last week: shares × the product of the
/// legs' outcome price histories. Empty when a leg's history is missing.
final comboEstimateSeriesProvider = FutureProvider.autoDispose
    .family<List<PolymarketPricePoint>, String>((ref, conditionId) async {
  final position = ref
      .read(polymarketCombosProvider)
      .valueOrNull
      ?.positions
      .where((p) => p.conditionId == conditionId)
      .firstOrNull;
  if (position == null || position.legs.isEmpty) return const [];
  final tokens = await ref
      .read(polymarketComboServiceProvider)
      .fetchClobTokens([for (final l in position.legs) l.marketId ?? '']);
  final series = <List<PolymarketPricePoint>>[];
  for (final leg in position.legs) {
    final ids = tokens[leg.marketId];
    if (ids == null || leg.outcomeIndex >= ids.length) return const [];
    final points = await PolyPriceHistoryCache.load(ids[leg.outcomeIndex], '1w');
    if (points == null || points.isEmpty) return const [];
    series.add(points);
  }
  return [
    for (final p in comboEstimateSeries(series))
      PolymarketPricePoint(timestamp: p.timestamp, price: p.price * position.shares),
  ];
});

class ComboDetailSheet extends ConsumerWidget {
  const ComboDetailSheet({super.key, required this.conditionId});
  final String conditionId;

  static void show(BuildContext context, {required String conditionId}) {
    TrackingService.screenView('combo_detail');
    // ignore: discarded_futures
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ComboDetailSheet(conditionId: conditionId),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(polymarketCombosProvider).valueOrNull;
    final p = state?.positions
        .where((x) => x.conditionId == conditionId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: KuteBackButton(onPressed: () => Navigator.of(context).maybePop()),
        title: Text(
          p == null ? l10n.combosTitle : l10n.comboLegsLabel(p.legsTotal),
          style: TextStyle(
              color: c.textPrimary, fontSize: 18.sp, fontWeight: FontWeight.w600),
        ),
      ),
      body: p == null
          ? const SizedBox.shrink()
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
                      children: [
                        _Summary(position: p),
                        SizedBox(height: 18.h),
                        _EstimateChart(position: p),
                        SizedBox(height: 20.h),
                        Text(l10n.comboLegs,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 4.h),
                        Text(
                            l10n.comboLegsSettled(
                                p.legsResolved, p.legsTotal),
                            style: TextStyle(
                                color: c.textTertiary, fontSize: 13.sp)),
                        for (final leg in p.legs) _LegRow(leg: leg),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
                    child: _Actions(position: p),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.position});
  final ComboPosition position;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final p = position;
    final settled = p.settledPayoutUsd;
    Widget row(String label, String value, {Color? color, String? note}) =>
        Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600)),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(value,
                    style: TextStyle(
                      color: color ?? c.textPrimary,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
                if (note != null)
                  Text(note,
                      style: TextStyle(color: c.textTertiary, fontSize: 11.sp)),
              ]),
            ],
          ),
        );
    return Column(children: [
      row(l10n.comboStake, formatHlUsd(p.stakeUsd)),
      row(
        l10n.comboPotentialPayout,
        formatHlUsd(p.isLost ? 0 : p.potentialPayoutUsd),
        color: p.isLost ? AppColors.marketDown : AppColors.success,
      ),
      if (!p.isLost)
        row(l10n.comboMultiplier, comboMultiplierText(p.multiplier)),
      if (settled == null && !p.isLost)
        row(l10n.comboEstimatedValue, formatHlUsd(p.estimatedValueUsd),
            note: l10n.comboEstimateNote),
      if (p.isLost)
        Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Text(l10n.comboLost,
              style: TextStyle(
                  color: AppColors.marketDown,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700)),
        ),
    ]);
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg});
  final ComboLeg leg;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = leg.outcome;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: 38.sp,
            height: 38.sp,
            child: leg.imageUrl == null
                ? Icon(Icons.show_chart, color: c.textTertiary)
                : PolyCrestImage(
                    url: leg.imageUrl!,
                    size: 38.sp,
                    radius: 10,
                    fallback: Icon(Icons.show_chart, color: c.textTertiary)),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(leg.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600)),
              SizedBox(height: 2.h),
              Text(leg.outcomeLabel,
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        SizedBox(width: 8.w),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(comboLegStatusText(context, o),
              style: TextStyle(
                  color: comboLegColor(context, o),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700)),
          if (o == ComboLegOutcome.open)
            Text(formatPolyChance(leg.currentPrice),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
        ]),
      ]),
    );
  }
}

class _EstimateChart extends ConsumerWidget {
  const _EstimateChart({required this.position});
  final ComboPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final series = ref.watch(comboEstimateSeriesProvider(position.conditionId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.comboChartEstimate,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 8.h),
        SizedBox(
          height: 170.h,
          child: series.when(
            data: (points) => points.length < 2
                ? Center(
                    child: Text(l10n.comboChartUnavailable,
                        style:
                            TextStyle(color: c.textTertiary, fontSize: 13.sp)))
                : CustomPaint(
                    painter: _EstimatePainter(
                      points: points,
                      bought: position.stakeUsd,
                      line: position.isLost
                          ? AppColors.marketDown
                          : AppColors.success,
                      grid: c.borderSubtle,
                      label: c.textTertiary,
                      boughtLabel: l10n.polyChartBought,
                    ),
                    size: Size.infinite,
                  ),
            loading: () => const Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, __) => Center(
                child: Text(l10n.comboChartUnavailable,
                    style: TextStyle(color: c.textTertiary, fontSize: 13.sp))),
          ),
        ),
      ],
    );
  }
}

/// The estimate line plus a dashed "Bought" line at the stake.
class _EstimatePainter extends CustomPainter {
  _EstimatePainter({
    required this.points,
    required this.bought,
    required this.line,
    required this.grid,
    required this.label,
    required this.boughtLabel,
  });

  final List<PolymarketPricePoint> points;
  final double bought;
  final Color line;
  final Color grid;
  final Color label;
  final String boughtLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) p.price];
    var lo = math.min(values.reduce(math.min), bought);
    var hi = math.max(values.reduce(math.max), bought);
    if ((hi - lo).abs() < 1e-9) {
      hi += 1;
      lo = math.max(0, lo - 1);
    }
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    final t0 = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.timestamp.millisecondsSinceEpoch.toDouble();
    double x(DateTime t) => t1 == t0
        ? 0
        : (t.millisecondsSinceEpoch - t0) / (t1 - t0) * size.width;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final px = x(points[i].timestamp);
      final py = y(points[i].price);
      i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);

    // Dashed Bought line.
    final by = y(bought);
    final dash = Paint()
      ..color = label
      ..strokeWidth = 1;
    for (var dx = 0.0; dx < size.width; dx += 8) {
      canvas.drawLine(Offset(dx, by), Offset(math.min(dx + 4, size.width), by),
          dash);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '$boughtLabel ${formatHlUsd(bought)}',
          style: TextStyle(color: label, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(4, math.max(0, by - tp.height - 2)));
  }

  @override
  bool shouldRepaint(covariant _EstimatePainter old) =>
      old.points != points || old.bought != bought || old.line != line;
}

class _Actions extends StatelessWidget {
  const _Actions({required this.position});
  final ComboPosition position;

  @override
  Widget build(BuildContext context) {
    final p = position;
    if (p.redeemable && (p.settledPayoutUsd ?? 0) > 0) {
      return ComboClaimButton(position: p, popRoute: true);
    }
    if (!p.isOpen) return const SizedBox.shrink();
    return AppButton(
      text: context.l10n.comboClose,
      onPressed: () => _CloseComboSheet.show(context, p),
    );
  }
}

/// "Claim $X" on a settled combo: one tap runs the claim and ends on the
/// claim confirmation, with no page in between. On the combo screen
/// ([popRoute] closes it first) and, [compact], on the Portfolio card.
class ComboClaimButton extends ConsumerStatefulWidget {
  const ComboClaimButton(
      {super.key,
      required this.position,
      this.compact = false,
      this.popRoute = false});
  final ComboPosition position;
  final bool compact;
  final bool popRoute;

  @override
  ConsumerState<ComboClaimButton> createState() => _ComboClaimButtonState();
}

class _ComboClaimButtonState extends ConsumerState<ComboClaimButton> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    final p = widget.position;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final nav = Navigator.of(context, rootNavigator: true);
    final local = Navigator.of(context);
    final question = context.l10n.comboLegsLabel(p.legsTotal);
    final outcome = context.l10n.comboLegWon;
    try {
      final payout = await ref
          .read(polymarketCombosProvider.notifier)
          .claim(p, trigger: 'manual');
      if (widget.popRoute && local.mounted) local.maybePop();
      if (!nav.mounted) return;
      pushClaimPlacedOverlay(
        navigator: nav,
        marketQuestion: question,
        outcome: outcome,
        amountUsd: payout,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(comboErrorCopy(context, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.position;
    // A claim already sent stays "claiming" until the index drops it.
    final claiming = ref.watch(polymarketCombosProvider.select(
        (s) => s.valueOrNull?.claiming.contains(p.conditionId) ?? false));
    final busy = _busy || claiming;
    final text = context.l10n.comboClaim(formatHlUsd(p.settledPayoutUsd ?? 0));
    if (widget.compact) {
      return AppButton(
        text: text,
        compact: true,
        isLoading: busy,
        onPressed: busy ? null : _claim,
      );
    }
    return AppButton(
      text: text,
      variant: AppButtonVariant.moneyIn,
      isLoading: busy,
      onPressed: busy ? null : _claim,
    );
  }
}

/// Close a combo early: one SELL RFQ for every share held, the exact pUSD
/// it pays after fees, a countdown, confirm (step-up), accept.
class _CloseComboSheet extends ConsumerStatefulWidget {
  const _CloseComboSheet({required this.position});
  final ComboPosition position;

  static Future<void> show(BuildContext context, ComboPosition p) =>
      showAppBottomSheet<void>(
        context: context,
        builder: (_) => _CloseComboSheet(position: p),
      );

  @override
  ConsumerState<_CloseComboSheet> createState() => _CloseComboSheetState();
}

class _CloseComboSheetState extends ConsumerState<_CloseComboSheet> {
  ComboQuote? _quote;
  String? _error;
  bool _loading = true;
  bool _placing = false;
  int _auto = 0;
  int _seq = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestQuote());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || _placing) return;
    final q = _quote;
    if (q == null) return;
    if (q.remaining(DateTime.now()) > Duration.zero) {
      setState(() {});
      return;
    }
    final again = _auto < 5;
    ComboAnalytics.quoteExpired(
        direction: 'sell',
        legs: widget.position.legsTotal,
        willRequote: again);
    if (again) {
      _auto++;
      _requestQuote();
    } else {
      setState(() => _quote = null);
    }
  }

  Future<void> _requestQuote() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final legs = widget.position.legsTotal;
    try {
      final q = await ref
          .read(polymarketCombosProvider.notifier)
          .quoteClose(widget.position);
      if (!mounted || seq != _seq) return;
      ComboAnalytics.closeQuoted(
        legs: legs,
        result: 'quoted',
        proceedsUsd: q.proceedsUsd,
        shares: q.sharesUsd,
        feeUsd: q.feesUsd,
      );
      setState(() {
        _quote = q;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      ComboAnalytics.closeQuoted(
        legs: legs,
        result: e is ComboNoQuoteException ? 'no_quote' : 'error',
        reasonCode: switch (e) {
          ComboNoQuoteException(:final code) => code,
          ComboRfqException(:final code) => code,
          _ => null,
        },
      );
      setState(() {
        _quote = null;
        _loading = false;
        _error = comboErrorCopy(context, e, selling: true);
      });
    }
  }

  Future<void> _confirm() async {
    final q = _quote;
    if (q == null) return;
    final walletId =
        ref.read(polymarketTradingProvider.notifier).signingWalletId;
    if (walletId == null || walletId.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _placing = true);
    try {
      final grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: PmGrants.comboClose(
          walletId: walletId,
          positionId: q.yesPositionId,
          sharesE6: q.requestedE6,
          minProceedsE6: q.netReceiveE6 * BigInt.from(99) ~/ BigInt.from(100),
        ),
        reason: context.l10n.stepUpReasonComboClose,
        amountUsd: q.proceedsUsd,
      );
      if (!mounted) return;
      if (grant == null) {
        setState(() => _placing = false);
        return;
      }
      final r = await ref.read(polymarketCombosProvider.notifier).close(
            position: widget.position,
            shown: q,
            grant: grant,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final text = switch (r.state) {
        ComboFillState.filled =>
          context.l10n.comboClosed(formatHlUsd(r.quote.proceedsUsd)),
        ComboFillState.pending => context.l10n.comboSettling,
        ComboFillState.failed => context.l10n.comboDeclined,
      };
      if (r.state == ComboFillState.failed) {
        setState(() {
          _placing = false;
          _quote = null;
          _error = text;
        });
        return;
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (!mounted) return;
      if (await handleGrantFailure(context, e,
          action: SensitiveAction.pmSell)) {
        if (mounted) {
          setState(() => _placing = false);
          await _requestQuote();
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _placing = false;
        if (e is ComboQuoteChanged) {
          _quote = e.quote;
          _error = context.l10n.comboPriceChanged;
        } else {
          _quote = null;
          _error = comboErrorCopy(context, e, selling: true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final q = _quote;
    final seconds =
        q == null ? 0 : (q.remaining(DateTime.now()).inMilliseconds / 1000).ceil();
    return AppBottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20.w, 0, 20.w, 12.h + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
                title: l10n.comboClose,
                subtitle: l10n.comboLegsLabel(widget.position.legsTotal)),
            SizedBox(height: 8.h),
            Text(
              q == null ? '-' : l10n.comboCloseFor(formatHlUsd(q.proceedsUsd)),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 24.sp,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              _error ??
                  (_loading
                      ? l10n.comboGettingPrice
                      : q == null
                          ? l10n.comboPriceFailed
                          : '${l10n.comboCloseExact} · ${l10n.comboPriceValidFor(seconds)}'),
              style: TextStyle(
                color: _error != null ? AppColors.error : c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (q != null && q.feesUsd > 0) ...[
              SizedBox(height: 4.h),
              Text('${l10n.fees}: ${formatHlUsd(q.feesUsd)}',
                  style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
            ],
            SizedBox(height: 16.h),
            q == null && !_loading
                ? AppButton(
                    text: l10n.comboGetNewPrice,
                    onPressed: () {
                      _auto = 0;
                      _requestQuote();
                    },
                  )
                : AppButton(
                    text: l10n.comboClose,
                    isLoading: _loading || _placing,
                    onPressed: q != null && !_placing ? _confirm : null,
                  ),
          ],
        ),
      ),
    );
  }
}
