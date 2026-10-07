// lib/screens/analytics/components/fee_chart.dart
//
// Fees tab content. Reads from the unified FeeHistoryService ledger
// (Phase 9) so it captures every cost the user pays across every
// flow — predictions, conversions, swaps, sends, lightning routing —
// not just BTC chain fees.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'package:kute/helpers/extension.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Stable color per fee kind so the breakdown rows read consistently
/// across renders. Source labels also map deterministically to these
/// colors so users build muscle memory ("orange = Bitcoin chain stuff").
const Map<FeeKind, Color> _kKindColors = {
  FeeKind.btcOnchain: Color(0xFFF7931A),
  FeeKind.lightningRouting: Color(0xFFFFD54F),
  FeeKind.polymarketTaker: Color(0xFF3B82F6),
  FeeKind.uniswapSwap: Color(0xFFFF007A),
  FeeKind.orchestraSpread: Color(0xFF27D17F),
  FeeKind.kuteAffiliate: Color(0xFFAF52DE),
  FeeKind.sideshiftSpread: Color(0xFF64B5F6),
  FeeKind.bitcoinvnSpread: Color(0xFFE57373),
};

/// Material icon fallbacks for fee kinds that don't have a brand
/// SVG in the bundle (Orchestra, retired providers, Uniswap).
const Map<FeeKind, IconData> _kKindIcons = {
  FeeKind.btcOnchain: Icons.currency_bitcoin_rounded,
  FeeKind.lightningRouting: Icons.bolt_rounded,
  FeeKind.polymarketTaker: Icons.psychology_rounded,
  FeeKind.uniswapSwap: Icons.swap_horiz_rounded,
  FeeKind.orchestraSpread: Icons.sync_alt_rounded,
  FeeKind.kuteAffiliate: Icons.local_offer_rounded,
  FeeKind.sideshiftSpread: Icons.compare_arrows_rounded,
  FeeKind.bitcoinvnSpread: Icons.compare_arrows_rounded,
};

/// Brand-SVG asset path per fee kind, when one exists in the
/// bundle. Rendered in preference to the Material icon — keeps
/// rows visually anchored to the actual provider (Polymarket P,
/// Bitcoin orange, Kute dog) instead of a generic glyph.
const Map<FeeKind, String> _kKindSvgAsset = {
  FeeKind.btcOnchain: 'lib/assets/bitcoin-icon.svg',
  FeeKind.polymarketTaker: 'lib/assets/polymarket-logo.svg',
  FeeKind.kuteAffiliate: 'lib/assets/kute_dog.svg',
  // Provider brand SVGs — Uniswap and WalletConnect are pulled from
  // their official GitHub brand-asset repos, Orchestra is stylised
  // in-house. The retired providers' marks stay for fee history
  // recorded before they left the app.
  FeeKind.uniswapSwap: 'lib/assets/uniswap-logo.svg',
  FeeKind.orchestraSpread: 'lib/assets/orchestra-logo.svg',
  FeeKind.sideshiftSpread: 'lib/assets/sideshift-logo.svg',
  FeeKind.bitcoinvnSpread: 'lib/assets/bitcoinvn-logo.svg',
};

/// PNG fallback for assets we don't have as SVG. Lightning is the
/// only one in this bucket today (the bundled lightning logo ships
/// as PNG).
const Map<FeeKind, String> _kKindPngAsset = {
  FeeKind.lightningRouting: 'lib/assets/Bitcoin_lightning_logo.png',
};

Map<FeeKind, String> _kindVendors(AppLocalizations l10n) => {
  FeeKind.btcOnchain: l10n.feeBitcoinNetwork,
  FeeKind.lightningRouting: l10n.feeVendorLightningRouting,
  FeeKind.polymarketTaker: 'Polymarket',
  FeeKind.uniswapSwap: 'Uniswap',
  FeeKind.orchestraSpread: 'Orchestra',
  FeeKind.kuteAffiliate: 'Kute',
  FeeKind.sideshiftSpread: 'SideShift',
  FeeKind.bitcoinvnSpread: 'BitcoinVN',
};

class FeeChart extends ConsumerWidget {
  const FeeChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final selectedDays = ref.watch(selectedDaysDateArrayProvider);

    if (selectedDays.isEmpty) {
      return Center(
        child: Text(
          context.l10n.feeNoHistory,
          style: TextStyle(color: c.textTertiary, fontSize: 16.sp),
        ),
      );
    }

    final from = selectedDays.first;
    final to = DateTime(
      selectedDays.last.year,
      selectedDays.last.month,
      selectedDays.last.day,
      23,
      59,
      59,
    );
    // Scope fees to the active wallet — a hardware wallet's analytics
    // shouldn't surface Polymarket / Spark / USDC fees that belong to
    // the spending wallet, and vice versa. FeeHistoryService keys each
    // entry by `walletId` so the filter is exact.
    final activeWalletId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    // Build the exclude set: BitcoinVN fees logged at order creation
    // for exchanges that haven't actually settled yet. We don't count
    // those toward total fees — the user hasn't paid them. Each
    // BitcoinVN fee entry's id is `bvn-<exchangeId>`; cross-reference
    // against the swap orders list and skip any whose status
    // isn't terminal-success.
    final exchanges = ref.watch(swapOrdersProvider);
    final pendingBvnIds = <String>{
      for (final ex in exchanges)
        if (ex.provider == 'BitcoinVN' &&
            !(ex.status == 'success' || ex.status == 'settled'))
          'bvn-${ex.id}',
    };
    final summary = FeeHistoryService.summarize(
      from: from,
      to: to,
      walletId: activeWalletId,
      excludeIds: pendingBvnIds.isEmpty ? null : pendingBvnIds,
    );

    // Convert microUsd → user's selected fiat once. The fee ledger
    // stores everything in micro-USD, so display is always a single
    // multiplication regardless of what currency the user is on.
    final fiatPerUsd =
        ref.watch(selectedCurrencyProviderFromUSD(currency)).toDouble();
    final usdToFiat = fiatPerUsd > 0 ? fiatPerUsd : 1.0;
    final totalFiat = (summary.totalMicroUsd / 1000000.0) * usdToFiat;

    // USD → sats so we can show "fees paid in sats" alongside fiat.
    // Users on a sats-native mindset want to see "how much Bitcoin
    // did I burn on fees this month" without doing the math in
    // their head. Use the live spot price (USD-denominated).
    final usdPerBtc = ref.watch(selectedCurrencyProvider('USD')).toDouble();
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final btcUnit = btcFormat == 'sats' ? 'sats' : 'BTC';
    int satsFromMicroUsd(int microUsd) {
      if (usdPerBtc <= 0) return 0;
      final usd = microUsd / 1000000.0;
      return ((usd / usdPerBtc) * 1e8).round();
    }

    final totalSats = satsFromMicroUsd(summary.totalMicroUsd);

    if (summary.count == 0) {
      return Center(
        child: Text(
          context.l10n.feeNoHistory,
          style: TextStyle(color: c.textTertiary, fontSize: 16.sp),
        ),
      );
    }

    // Sort kinds by total descending so the biggest contributor sits
    // at the top of the breakdown — most users want to know "where
    // did most of my fees go?" first.
    final kinds = summary.byKind.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final fiatFormatter =
        NumberFormat.simpleCurrency(name: currency, decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big total at top
        Text(
          context.l10n.feeTotalPaid,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          fiatFormatter.format(totalFiat),
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 28.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(height: 4.h),
        // Same total in sats so the "how many sats went to fees"
        // narrative shows alongside the fiat figure.
        if (totalSats > 0)
          Text(
            '${totalSats.toFormattedString(btcFormat)} $btcUnit',
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        SizedBox(height: 4.h),
        Text(
          context.l10n.feeTransactionCount(summary.count),
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 14.h),

        // Stacked bar showing share-of-total per kind. Quick visual
        // for "where did my fees actually go this period".
        if (totalFiat > 0)
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: SizedBox(
              height: 8.h,
              child: Row(
                children: [
                  for (final entry in kinds)
                    Flexible(
                      flex: ((entry.value / summary.totalMicroUsd) * 1000)
                          .round()
                          .clamp(1, 1000),
                      child: Container(
                        color: _kKindColors[entry.key] ?? c.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        SizedBox(height: 12.h),

        // Per-kind breakdown — scrollable so we don't get clipped on
        // small phones when the user has paid lots of different fee
        // categories.
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: kinds.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (_, i) {
              final entry = kinds[i];
              final kindFiat = (entry.value / 1000000.0) * usdToFiat;
              final kindSats = satsFromMicroUsd(entry.value);
              final pct = entry.value / summary.totalMicroUsd;
              // Per-kind source breakdown — captures which wallet
              // / flow each fee came from (e.g. "Spark · Savings"
              // for `btcOnchain`). Sorted by share descending so the
              // dominant source is named first.
              final perSource = (summary.byKindAndSource[entry.key] ??
                      const <String, int>{})
                  .entries
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              return _FeeKindRow(
                kind: entry.key,
                fiat: kindFiat,
                sats: kindSats,
                btcFormat: btcFormat,
                btcUnit: btcUnit,
                pct: pct,
                fiatFormatter: fiatFormatter,
                sources: perSource,
                c: c,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeeKindRow extends StatelessWidget {
  final FeeKind kind;
  final double fiat;
  final int sats;
  final String btcFormat;
  final String btcUnit;
  final double pct;
  final NumberFormat fiatFormatter;

  /// `(source, microUsd)` pairs sorted by share descending. Source
  /// is the human label captured at log-time — `'Spark'`,
  /// `'Savings'`, `'Polymarket'`, etc.
  final List<MapEntry<String, int>> sources;
  final AppColorsExtension c;

  const _FeeKindRow({
    required this.kind,
    required this.fiat,
    required this.sats,
    required this.btcFormat,
    required this.btcUnit,
    required this.pct,
    required this.fiatFormatter,
    required this.sources,
    required this.c,
  });

  /// Build the "Spark, Savings · 45% of total" subtitle. Shows up
  /// to three source labels — beyond that we collapse the rest into
  /// "+N more" so the row stays single-line.
  String _composeSubtitle(BuildContext context) {
    final shareText =
        context.l10n.feeShareOfTotal((pct * 100).toStringAsFixed(1));
    final names = <String>{
      if (_kindVendors(context.l10n)[kind] case final String vendor) vendor,
      ...sources.map((e) => e.key).where((s) => s.isNotEmpty),
    }.toList();
    if (names.isEmpty) return shareText;
    final shown = names.take(3).join(', ');
    return '$shown${names.length > 3 ? '…' : ''} · $shareText';
  }

  /// Render the badge child for non-SVG fee rows. Order of preference:
  /// PNG fallback (Lightning), then a monochrome Material glyph for the
  /// providers without a brand asset (Orchestra, retired providers,
  /// Uniswap). Brand SVGs are rendered directly in `build` without a disc.
  Widget _buildLeadingIcon(Color tint) {
    final png = _kKindPngAsset[kind];
    if (png != null) {
      return Padding(
        padding: EdgeInsets.all(2.w),
        child: Image.asset(png, fit: BoxFit.contain),
      );
    }
    final icon = _kKindIcons[kind] ?? Icons.attach_money_rounded;
    return Icon(icon, color: tint, size: 18.sp);
  }

  @override
  Widget build(BuildContext context) {
    final color = _kKindColors[kind] ?? c.textTertiary;
    final label = switch (kind) {
      FeeKind.btcOnchain => context.l10n.feeBitcoinNetwork,
      FeeKind.lightningRouting => context.l10n.feeLightningNetwork,
      FeeKind.polymarketTaker => context.l10n.feePredictions,
      FeeKind.kuteAffiliate => context.l10n.feeApp,
      FeeKind.uniswapSwap ||
      FeeKind.orchestraSpread ||
      FeeKind.sideshiftSpread ||
      FeeKind.bitcoinvnSpread =>
        context.l10n.feeConversion,
    };

    final svg = _kKindSvgAsset[kind];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          // Brand SVGs render raw — no background disc, sized up to fill
          // the 32-wide leading slot so the logo carries its own footprint.
          if (svg != null)
            SizedBox(
              width: 32.w,
              height: 32.w,
              child: SvgPicture.asset(svg, fit: BoxFit.contain),
            )
          else
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                // PNG (Lightning) keeps the white surface so the raster
                // logo pops; generic Material icons sit on the neutral
                // squared plate (the series color moves to the dot
                // beside the label).
                color:
                    _kKindPngAsset.containsKey(kind) ? Colors.white : c.surface,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              alignment: Alignment.center,
              clipBehavior: Clip.antiAlias,
              child: _buildLeadingIcon(c.textSecondary),
            ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Series-color dot keeps the mapping to the stacked
                    // fee bar above now that the leading plate is neutral.
                    Container(
                      width: 6.sp,
                      height: 6.sp,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 2.h),
                // Source line: "Spark · 45% of total" when only one
                // wallet contributed; "Spark, Savings · 45% of
                // total" when multiple. The "of total" stays as a
                // suffix so the user can still see the share at a
                // glance. Cap to the top 3 sources so a long tail
                // of one-off fees doesn't blow up the row height.
                Text(
                  _composeSubtitle(context),
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fiatFormatter.format(fiat),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (sats > 0) ...[
                SizedBox(height: 2.h),
                Text(
                  '${sats.toFormattedString(btcFormat)} $btcUnit',
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
