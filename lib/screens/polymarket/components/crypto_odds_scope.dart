// Registers a crypto Up/Down card's Up token with [cryptoLiveOddsProvider]
// while the card can be seen: mounted with its tickers on. A hidden shell
// branch turns tickers off (`Offstage` + `TickerMode`), which unregisters
// the token, so the live odds stop being read for a card nobody sees.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/crypto_live_odds_provider.dart';

class CryptoOddsScope extends ConsumerStatefulWidget {
  const CryptoOddsScope({super.key, required this.token, required this.child});

  /// The card's Up token; null or empty registers nothing.
  final String? token;
  final Widget child;

  @override
  ConsumerState<CryptoOddsScope> createState() => _CryptoOddsScopeState();
}

class _CryptoOddsScopeState extends ConsumerState<CryptoOddsScope> {
  CryptoLiveOddsNotifier? _notifier;
  String? _registered;
  bool _visible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant CryptoOddsScope old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token) _scheduleSync();
  }

  // Registration writes provider state, which is not allowed mid-build.
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final notifier = ref.read(cryptoLiveOddsProvider.notifier);
    final token = widget.token;
    final want = _visible && token != null && token.isNotEmpty ? token : null;
    if (identical(notifier, _notifier) && want == _registered) return;
    final old = _registered;
    if (old != null) _notifier?.unwatch(old);
    _notifier = notifier;
    _registered = want;
    if (want != null) notifier.watch(want);
  }

  @override
  void dispose() {
    final old = _registered;
    if (old != null) _notifier?.unwatch(old);
    _registered = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the shared notifier alive while the card is mounted.
    ref.watch(cryptoLiveOddsProvider.notifier);
    return widget.child;
  }
}
