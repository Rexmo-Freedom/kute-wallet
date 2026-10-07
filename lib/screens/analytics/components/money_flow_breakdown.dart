// lib/screens/analytics/components/money_flow_breakdown.dart
//
// The Breakdown tab of the analytics strip on Home (the spending wallet's
// bitcoin) and on Dollars: where the money went, or where it came from,
// all time, as the category donut card (the Statistics donut's card).
//
//   * Sent | Received: the app's two small pills above the card (the
//     Market / Livestream pair's chrome), Sent first. Switching morphs
//     the ring category by category, with a selection click, and clears
//     the pick.
//   * The categories and their amounts: services/portfolio/
//     money_flow_categories.dart, from the same rows Activity lists, so
//     the donut and the list never disagree.
//   * Bitcoin reads in the screen's unit (sats or BTC) with the fiat
//     value under the hole's figure; Dollars reads in dollars.
//   * Nothing in a direction yet: the card says so in one quiet line.
//   * The slice event is the Statistics donut's, with venue 'bitcoin' or
//     'dollars' and the direction. The pills themselves send nothing.
//
// Only the hot spending wallet has these flows; hardware, Ledger,
// watch-only, external-address and other on-chain wallets never mount it.

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/shared/charts/kute_category_donut_card.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show activityOwnSettleAddresses, assembleActivityRows;
import 'package:kute/services/portfolio/money_flow_categories.dart';
import 'package:kute/theme/app_theme.dart';

/// A Breakdown category's name. Lightning, Spark and Cash App are names
/// of things and read the same in every language.
String moneyFlowCategoryLabel(AppLocalizations l10n, String key) =>
    switch (key) {
      MoneyFlowCategory.lightning => 'Lightning',
      MoneyFlowCategory.spark => 'Spark',
      MoneyFlowCategory.onchain => l10n.activityOnChain,
      MoneyFlowCategory.investing => l10n.trading,
      MoneyFlowCategory.predictions => l10n.predictions,
      MoneyFlowCategory.dollars => l10n.assetDollars,
      MoneyFlowCategory.bitcoin => l10n.bitcoin,
      MoneyFlowCategory.otherCrypto => l10n.sendOtherCrypto,
      MoneyFlowCategory.cashApp => 'Cash App',
      _ => l10n.betGroupOther,
    };

/// Home's Breakdown tab for [wallet]: the hot spending wallet's money in
/// and out, or null (no tab) for any other kind of wallet.
Widget? homeBreakdownChild(WalletConfig? wallet) =>
    (wallet?.isSparkWallet ?? false)
        ? const MoneyFlowBreakdown(ledger: MoneyFlowLedger.bitcoin)
        : null;

class MoneyFlowBreakdown extends ConsumerStatefulWidget {
  final MoneyFlowLedger ledger;

  const MoneyFlowBreakdown({super.key, required this.ledger});

  @override
  ConsumerState<MoneyFlowBreakdown> createState() => _MoneyFlowBreakdownState();
}

class _MoneyFlowBreakdownState extends ConsumerState<MoneyFlowBreakdown> {
  MoneyFlowDirection _direction = MoneyFlowDirection.sent;

  // The last split, kept while the wallet's rows are the same list (the
  // fold over the rows is Activity's, not free to redo every frame).
  List<BaseTransaction>? _memoRows;
  Set<String>? _memoOwn;
  final Map<MoneyFlowDirection, Map<String, double>> _memo = {};

  void _pick(MoneyFlowDirection next) {
    if (next == _direction) return;
    HapticFeedback.selectionClick();
    setState(() => _direction = next);
  }

  Map<String, double> _values(List<BaseTransaction> sorted, Set<String> own) {
    if (!identical(sorted, _memoRows) || !setEquals(own, _memoOwn)) {
      _memoRows = sorted;
      _memoOwn = own;
      _memo.clear();
    }
    return _memo.putIfAbsent(_direction, () {
      final rows = assembleActivityRows(
        sorted,
        ownAddresses: own,
        isHardwareOrWatchOnly: false,
        onlyUsdb: widget.ledger == MoneyFlowLedger.dollars,
        keepVenueMoves: true,
      );
      return moneyFlowCategories(rows,
          ledger: widget.ledger, direction: _direction);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    // The spending account's rows, read the way the Activity tab beside
    // this one reads them.
    final activeId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    final cache = ref.watch(walletTransactionCacheProvider);
    final sorted =
        (activeId != null ? cache[activeId] : null)?.allTransactionsSorted ??
            const <BaseTransaction>[];
    final values = _values(sorted, activityOwnSettleAddresses(ref));
    final bitcoin = widget.ledger == MoneyFlowLedger.bitcoin;
    final dollars = NumberFormat.simpleCurrency(name: 'USD');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KutePill(
              key: const ValueKey('money-flow-sent'),
              label: l10n.sent,
              selected: _direction == MoneyFlowDirection.sent,
              onTap: () => _pick(MoneyFlowDirection.sent),
            ),
            SizedBox(width: 6.w),
            KutePill(
              key: const ValueKey('money-flow-received'),
              label: l10n.received,
              selected: _direction == MoneyFlowDirection.received,
              onTap: () => _pick(MoneyFlowDirection.received),
            ),
          ],
        ),
        if (values.values.every((v) => !v.isFinite || v <= 0))
          Container(
            key: const ValueKey('money-flow-empty'),
            width: double.infinity,
            margin: EdgeInsets.only(top: 12.h),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 32.h),
            decoration: AppDecorations.card(context),
            child: Text(
              l10n.ledgerActivityEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          KuteCategoryDonutCard(
            values: values,
            scope: _direction,
            labelOf: (key) => moneyFlowCategoryLabel(l10n, key),
            formatValue: bitcoin
                ? (ref, sats) => ref.watch(conversionProvider(sats.round()))
                : (ref, usd) => dollars.format(usd),
            formatSecondary: bitcoin
                ? (ref, sats) =>
                    ref.watch(conversionToFiatProvider(sats.round()))
                : null,
            analyticsParams: {
              'venue': widget.ledger.name,
              'direction': _direction.name,
              'wallet_kind': 'hot',
            },
          ),
      ],
    );
  }
}
