// lib/screens/polymarket/components/fast_bet_scope.dart
//
// Marks a short-round screen for the fast-bet window (`FastBetWindow`).
// The short-round screens are, for a hot (spending wallet) 5 or 15 minute
// crypto Up/Down round only:
//   * the five-minute round sheet (`FiveMinMarketDetailSheet`);
//   * the market sheet of such a round (`MarketDetailSheet`);
//   * the bet slip opened on such a round (`BetSlipSheet`);
//   * the position page and the sell ticket of a position in such a round
//     (`PositionDetailSheet`, `SellSheet`).
// The window only opens while one of them is up and ends the moment the
// last one goes away. The Predictions list (its live round banner
// included) is not one: a bet placed straight from the list ends its
// window when the slip closes.
//
// Each scope also ends the window on the app leaving the screen, the
// session lock, a new or cleared session and a spending wallet switch.
// Draws nothing.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/privacy_cover_bridge.dart';
import 'package:kute/providers/auth_provider.dart'
    show appLockedProvider, sessionAuthProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/polymarket/fast_bet_window.dart';

class FastBetScope extends ConsumerStatefulWidget {
  const FastBetScope({super.key, required this.active, required this.child});

  /// Whether this screen is a short-round screen (see the file comment).
  final bool active;
  final Widget child;

  @override
  ConsumerState<FastBetScope> createState() => _FastBetScopeState();
}

class _FastBetScopeState extends ConsumerState<FastBetScope>
    with WidgetsBindingObserver {
  FastBetWindow get _window => FastBetWindow.instance;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _window.enterScope();
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didUpdateWidget(FastBetScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _window.enterScope();
      WidgetsBinding.instance.addObserver(this);
    } else {
      WidgetsBinding.instance.removeObserver(this);
      _window.exitScope();
    }
  }

  @override
  void dispose() {
    if (widget.active) {
      WidgetsBinding.instance.removeObserver(this);
      _window.exitScope();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _window.onLifecycle(state,
        selfPrompt: PrivacyCoverBridge.promptActive.value);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionAuthProvider, (prev, next) {
      if (!identical(prev, next)) {
        _window.end(FastBetWindowEnd.sessionChanged);
      }
    });
    ref.listen<bool>(appLockedProvider, (_, locked) {
      if (locked) _window.end(FastBetWindowEnd.sessionLock);
    });
    ref.listen<String?>(
        settingsProvider.select((s) => pickSpendingWallet(s)?.id),
        (prev, next) {
      if (prev != next) _window.end(FastBetWindowEnd.walletChanged);
    });
    return widget.child;
  }
}
