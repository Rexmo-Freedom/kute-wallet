// lib/providers/arbitrum_refund_provider.dart
//
// The spending wallet's USDC returned on Arbitrum (arbitrum_refund_watch.dart),
// read when Investing or the Portfolio refreshes, on resume, and as soon as
// one of its CCTP moves' rows turns refunded
// ([arbitrumRefundRowsWatcherProvider]). Display only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/arbitrum_refund_watch.dart';

/// The balance read (Circle's USDC on Arbitrum One); a test's fake.
final arbitrumUsdcReaderProvider =
    Provider<Future<BigInt> Function(String owner)>((_) => readArbitrumUsdc);

/// Where the once-per-amount report is remembered; a test's fake.
final arbitrumRefundReportsProvider =
    Provider<ArbitrumRefundReports>((_) => HiveArbitrumRefundReports());

final arbitrumRefundProvider =
    StateNotifierProvider<ArbitrumRefundWatch, ArbitrumRefundState>((ref) {
  String? walletId() => pickSpendingWallet(ref.read(settingsProvider))?.id;
  final watch = ArbitrumRefundWatch(
    account: () async {
      final id = walletId();
      if (id == null) return null;
      final owner = await ref.read(hyperliquidAddressProvider.future);
      if (owner == null || walletId() != id) return null;
      return (walletId: id, owner: owner);
    },
    knownRefund: (id) =>
        refundedCctpMoveIds(ref.read(swapOrdersProvider), walletId: id)
            .isNotEmpty,
    readBalance: ref.read(arbitrumUsdcReaderProvider),
    reports: ref.read(arbitrumRefundReportsProvider),
  );
  return watch;
});

/// The side-car that reads the balance as soon as one of the spending
/// wallet's CCTP moves turns refunded (or one already is when it starts).
/// Kept out of [arbitrumRefundProvider] so showing the line never pulls
/// the Activity rows in; held by the screens that already follow them
/// (Investing, the Portfolio). Ids are compared in the listener: a
/// selector may not read other providers.
final arbitrumRefundRowsWatcherProvider = Provider<void>((ref) {
  var seen = const <String>{};
  ref.listen<List<SwapOrder>>(
    swapOrdersProvider,
    (_, rows) {
      final id = pickSpendingWallet(ref.read(settingsProvider))?.id;
      final ids = refundedCctpMoveIds(rows, walletId: id);
      final fresh = ids.difference(seen).isNotEmpty;
      seen = ids;
      if (fresh) {
        ref
            .read(arbitrumRefundProvider.notifier)
            .scan(ArbitrumRefundTrigger.cctpRefund);
      }
    },
    fireImmediately: true,
  );
});
