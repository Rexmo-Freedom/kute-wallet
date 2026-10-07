import 'package:kute/providers/trade_notifications_provider.dart';
import 'dart:async';

import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart'
    show prewarmLiveBtcFeed;
import 'package:kute/screens/home/home.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shell branch 0. Home for the spending account, or the wallet the user
/// switched to: switching wallets is a TAB now, not a pushed screen with an
/// app bar and a back button (user decision September 2026).
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  void initState() {
    super.initState();
    // Start background sync on app launch, delayed to let UI render first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final backgroundSyncService = BackgroundSyncService();
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          backgroundSyncService.start(context);
          // The scope below was pinned before the service had a container,
          // so the scan it asked for was dropped on the floor. Ask again
          // now that the service is live; it coalesces, so this is a no-op
          // when the scan did start.
          _kickScopedScan(ref.read(shellWalletIdProvider));
        }
      });
      // A deep link or a restored session can already have a wallet
      // parked on the first tab; pin its scope once mounted.
      _applyWalletScope(ref.read(shellWalletIdProvider));
    });
  }

  /// Pins every wallet-scoped surface to the wallet the first tab shows, or
  /// releases them back to the spending account when it goes null.
  ///
  /// This used to live in the pushed detail screen's initState/dispose. It
  /// belongs here now: this branch is always mounted, so the scope never has
  /// to be written while a widget is being torn down.
  void _applyWalletScope(String? walletId) {
    if (!mounted) return;
    if (walletId == null) {
      ref.read(bdkScopeWalletIdProvider.notifier).state = null;
      final activeId = ref.read(settingsProvider).activeWalletId;
      if (activeId != null) {
        ref.read(viewedWalletIdProvider.notifier).state = activeId;
      }
      ref.read(homeViewScopeProvider.notifier).state = null;
      return;
    }
    // Cold-start the Binance BTC/USD WS so the wallet's Price tab has
    // ticks flowing by the time the user reaches it.
    prewarmLiveBtcFeed();
    ref.read(bdkScopeWalletIdProvider.notifier).state = walletId;
    ref.read(viewedWalletIdProvider.notifier).state = walletId;
    // Clear the home carousel scope so analytics and breakdown surfaces
    // follow this wallet instead of aggregating across all wallets.
    ref.read(homeViewScopeProvider.notifier).state = null;
    ref
        .read(walletBalanceCacheProvider.notifier)
        .invalidateStreamFreshness(walletId);
    // The analytics history chain is built on autoDispose StateProviders;
    // force-invalidate so the first paint reflects THIS wallet's history
    // rather than the previous one's.
    ref.invalidate(bitcoinBalanceOverPeriod);
    ref.invalidate(bitcoinBalanceOverPeriodByDayProvider);
    ref.invalidate(bitcoinBalanceInFormatByDayProvider);
    ref.invalidate(bitcoinBalanceStepsProvider);
    // EVERY switch to this tab scans this wallet, not only its first open.
    // The person is looking at THIS wallet now, so its balance and coins
    // are the work that matters, and an already-scanned wallet used to sit
    // on whatever the cache happened to hold until a manual pull, which is
    // what left a maximum send with no coins to size against.
    _kickScopedScan(walletId);
  }

  /// Asks the syncer to scan the wallet the first tab is showing.
  ///
  /// Deliberately fire-and-forget and deliberately not guarded here:
  /// [BackgroundSyncService.scanBdkScope] returns the scan already in
  /// flight for this wallet instead of opening a second native session,
  /// and stands down entirely while a send build holds the wallet's
  /// native slot. Native BDK has one slot per wallet, so joining is the
  /// only safe way to be fast.
  void _kickScopedScan(String? walletId) {
    if (walletId == null) return;
    unawaited(BackgroundSyncService().scanBdkScope(source: 'wallet_switch'));
  }

  @override
  Widget build(BuildContext context) {
    // Fires outside build, so the scope swap never lands mid-frame.
    ref.listen<String?>(shellWalletIdProvider, (_, next) {
      _applyWalletScope(next);
    });
    ref.watch(tradeNotificationsProvider);
    final wallet = ref.watch(shellWalletProvider);
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(children: [
        Expanded(
          child: wallet == null
              ? const Home()
              : ShellWalletScreen(key: ValueKey(wallet.id), wallet: wallet),
        ),
      ]),
    );
  }
}
