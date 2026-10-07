import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_trade_notification.dart';
import 'package:flutter/widgets.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid_closed_trade.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlMarketDirectory;
import 'package:kute/helpers/hyperliquid_activity.dart' show hlFillAction;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlPrice, formatHlSize, formatHlUsd;
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/trade_notification_store.dart';

/// Marks receipts read in the durable store (opening the notifications
/// sheet marks everything it shows). A provider so widget tests can keep the
/// store in memory.
final markTradeNotificationsReadProvider =
    Provider<Future<void> Function(Iterable<TradeNotification>)>(
        (_) => TradeNotificationStore.markAllRead);

/// Persist results while the app is open; reconcile held settlements and recent
/// fills on the next visit as well. This is not OS background push delivery.
final tradeNotificationsProvider =
    StreamProvider.autoDispose<List<TradeNotification>>((ref) async* {
  final pmAccount = ref.watch(polymarketTradingProvider
      .select((s) => s.valueOrNull?.proxyWalletAddress));
  final hlAccount = ref.watch(
      hyperliquidTradingProvider.select((s) => s.valueOrNull?.walletAddress));
  final settings = ref.watch(settingsProvider);
  final spending = pickSpendingWallet(settings);
  final owners = <String, ({String id, String name})>{
    if (spending != null && pmAccount != null)
      pmAccount.toLowerCase(): (id: spending.id, name: spending.name),
    if (spending != null && hlAccount != null)
      hlAccount.toLowerCase(): (id: spending.id, name: spending.name),
  };
  final predictionAccounts = <String>{
    if (pmAccount != null) pmAccount.toLowerCase(),
  };
  // Resolve public accounts against each device-verified Ledger identity.
  // This never unlocks a wallet, signs, or creates trading credentials.
  for (final wallet in settings.wallets.where(
      (w) => w.isLedger && w.evmAddress != null && w.evmVerifiedAtMs != null)) {
    final ledger = ref.watch(ledgerPmAccountProvider(wallet.id)).valueOrNull;
    final address = ledger?.account?.address;
    if (ledger?.walletId != wallet.id ||
        ledger?.eoa?.toLowerCase() != wallet.evmAddress!.toLowerCase() ||
        ledger?.account?.kind == PolymarketAccountKind.uncertain ||
        address == null) {
      continue;
    }
    predictionAccounts.add(address.toLowerCase());
    owners[address.toLowerCase()] = (id: wallet.id, name: wallet.name);
  }
  final accounts = owners.keys.toSet();
  Future<List<TradeNotification>> readReceipts() async => [
        for (final n in await TradeNotificationStore.read(accounts))
          TradeNotification.fromJson({
            ...n.toJson(),
            'walletId': owners[n.account]?.id,
            'walletName': owners[n.account]?.name,
          }),
      ];
  var disposed = false;
  ref.onDispose(() => disposed = true);
  yield await readReceipts();
  final fundingRetryAt = <String, DateTime>{};
  final model = PolymarketModel();
  ref.onDispose(model.dispose);
  while (!disposed) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      await Future<void>.delayed(const Duration(seconds: 30));
      continue;
    }
    for (final address in predictionAccounts) {
      if (disposed) return;
      try {
        // Use indexed on-chain activity, never optimistic order submissions.
        final activity = await model.getUserActivityOrThrow(address);
        if (disposed) return;
        final owner = owners[address];
        if (owner == null) {
          continue;
        }
        for (final receipt in polymarketTradeNotifications(activity,
            account: address, walletId: owner.id, walletName: owner.name)) {
          if (disposed) return;
          await TradeNotificationStore.reconcile(receipt);
        }
      } catch (_) {
        /* Keep saved receipts when the public indexer is unavailable. */
      }
    }
    var fundingRequests = 0;
    final stored = {
      for (final n in await TradeNotificationStore.read(accounts)) n.id: n
    };
    final pm = ref.read(polymarketTradingProvider).valueOrNull;
    final hl = ref.read(hyperliquidTradingProvider).valueOrNull;
    if (pmAccount != null && pm?.proxyWalletAddress == pmAccount) {
      for (final p in pm!.openPositions
          .where((p) => p.redeemable || p.curPrice >= 0.99)) {
        if (disposed) return;
        final payout = await PolymarketOnboardingService()
            .settledPayout(p.conditionId, p.outcomeIndex);
        if (payout == null || disposed) {
          continue;
        }
        final amount = p.size * payout;
        await TradeNotificationStore.add(TradeNotification(
          id: 'pm:${pmAccount.toLowerCase()}:${p.asset}:$payout',
          account: pmAccount.toLowerCase(),
          product: 'predictions',
          imageUrl: p.icon,
          title: payout == 1
              ? 'Prediction won'
              : payout == 0
                  ? 'Prediction lost'
                  : 'Prediction settled',
          subtitle: '${p.title} · ${p.outcome}',
          time: DateTime.now().millisecondsSinceEpoch,
          positive: payout == 1 && amount > p.initialValue,
          rows: {
            'Settlement payout': '\$${amount.toStringAsFixed(2)}',
            if (p.initialValue > 0)
              'Position cost basis': '\$${p.initialValue.toStringAsFixed(2)}',
            if (p.initialValue > 0)
              'Return less cost basis':
                  '\$${(amount - p.initialValue).toStringAsFixed(2)}',
            'Profit details': 'Additional fees may affect net profit',
            'Result': payout > 0
                ? 'Open Positions to check claim status'
                : 'No payout'
          },
        ));
      }
    }
    if (hlAccount != null && hl?.walletAddress == hlAccount) {
      for (final fill in hl!.recentFills.where(
          (f) => f.dir.toLowerCase().contains('close') || f.closedPnl != 0)) {
        if (disposed) return;
        final identity =
            fill.tradeId ?? '${fill.oid}:${fill.time}:${fill.hash}:${fill.sz}';
        final id = 'hl:${hlAccount.toLowerCase()}:$identity';
        if (stored[id]?.rows.containsKey('Net profit') == true) {
          continue;
        }
        // Receipts name the market ('TSLA', not '@142' or 'xyz:TSLA') and
        // price it at the venue's precision.
        final known = HlMarketDirectory.byWire(fill.coin);
        final shown = HlMarketDirectory.displayName(fill.coin);
        final trade = HlClosedTrade.fromFills(hl.recentFills, fill);
        double? funding;
        if (trade != null &&
            fundingRequests < 3 &&
            !(fundingRetryAt[id]?.isAfter(DateTime.now()) ?? false)) {
          fundingRequests++;
          fundingRetryAt[id] = DateTime.now().add(const Duration(minutes: 5));
          try {
            funding = await HyperliquidModel().getTradeFunding(
                hlAccount, fill.coin, trade.openedAt, trade.closedAt);
          } catch (_) {/* Keep the clearly labeled provisional receipt. */}
        }
        if (disposed) return;
        if (trade != null && funding != null) {
          final net = trade.net(funding);
          await TradeNotificationStore.reconcile(TradeNotification(
            id: id,
            account: hlAccount.toLowerCase(),
            product: 'trading',
            assetCode: fill.coin,
            title: net > 0 ? 'Trade closed in profit' : 'Trade closed',
            subtitle: '$shown · Full position',
            time: fill.time,
            positive: net > 0,
            rows: {
              'Net profit': formatHlUsd(net),
              'Trading P&L': formatHlUsd(trade.gross),
              'All trading fees': '\$${trade.fees.toStringAsFixed(4)}',
              'Funding received / paid': '\$${funding.toStringAsFixed(4)}',
              'Includes': 'Opening, partial closes and final close',
            },
          ));
          continue;
        }
        await TradeNotificationStore.add(TradeNotification(
          id: id,
          account: hlAccount.toLowerCase(), product: 'trading',
          assetCode: fill.coin,
          // The action is stored in English, like every receipt label, and
          // put in the app language when shown (trade_notification_copy).
          title: 'Closing fill', subtitle: '$shown · ${hlFillAction(fill)}',
          time: fill.time,
          // Funding and opening fees are not allocated by a closing fill.
          // Keep a neutral receipt until the complete net result is known.
          rows: {
            'Closed P&L (exchange)': formatHlUsd(fill.closedPnl),
            'Fill fee': '${fill.fee.toStringAsFixed(4)} ${fill.feeToken}',
            'Filled size': formatHlSize(fill.sz),
            'Fill price':
                formatHlPrice(fill.px, decimalCap: known?.pxDecimalCap),
            'Accounting': 'See trade history for all fees and funding'
          },
        ));
      }
    }
    if (disposed) return;
    yield await readReceipts();
    await Future<void>.delayed(const Duration(seconds: 30));
  }
});
