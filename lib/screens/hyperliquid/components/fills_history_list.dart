// lib/screens/hyperliquid/components/fills_history_list.dart
//
// Recent-fills history for the Trading tab. V1 keeps Hyperliquid trade
// history IN-TAB only (no transactions_model.dart change — see the
// integration plan §2): this list + the bottom sheet host are that
// surface. Rows come from the trading notifier's WS-patched
// `recentFills` ring when it's alive, falling back to the REST-polled
// hyperliquidUserFillsProvider so the sheet also works when opened
// before the trading stack has spun up.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/hyperliquid_activity_list.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';

class HlFillsHistoryList extends ConsumerWidget {
  /// Cap on rendered rows (the fills ring holds up to 200).
  final int maxRows;
  const HlFillsHistoryList({super.key, this.maxRows = 50});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fills = ref.watch(hyperliquidActivityFillsProvider);
    final history = ref.watch(hyperliquidUserFillsProvider);
    final walletId = pickSpendingWallet(ref.watch(settingsProvider))?.id;
    return HyperliquidActivityList(
        fills: fills,
        walletId: walletId,
        loading: history.isLoading,
        loadFailed: history.hasError,
        onRetry: () => ref.invalidate(hyperliquidUserFillsProvider),
        compareWithSpendingWallet: true,
        maxRows: maxRows);
  }
}
