// lib/screens/hyperliquid/components/hl_price_lines_host.dart
//
// Says so with the app's quiet snack bar when a price line is reached,
// wherever the person is in the app. Mounted once in the shell; paints
// nothing. In-app only: there are no notifications, and nothing checks a
// line while the app is closed. One at a time, a few seconds apart (a new
// toast replaces the one up), at most three waiting.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/message_display.dart';

class HlPriceLinesHost extends ConsumerStatefulWidget {
  const HlPriceLinesHost({super.key});

  @override
  ConsumerState<HlPriceLinesHost> createState() => _HlPriceLinesHostState();
}

class _HlPriceLinesHostState extends ConsumerState<HlPriceLinesHost> {
  static const _shown = Duration(seconds: 3);
  static const _gap = Duration(seconds: 4);
  static const _maxWaiting = 3;

  final List<HlPriceLine> _waiting = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual<List<HlPriceLine>>(hlPriceLinesProvider, (prev, next) {
      final waited = {
        for (final line in prev ?? const <HlPriceLine>[])
          if (!line.isReached) line.id,
      };
      _waiting.addAll(
          next.where((line) => line.isReached && waited.contains(line.id)));
      while (_waiting.length > _maxWaiting) {
        _waiting.removeAt(0);
      }
      _pump();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pump() {
    if (!mounted || _timer != null || _waiting.isEmpty) return;
    final line = _waiting.removeAt(0);
    showMessageSnackBarInfo(
      context: context,
      message: context.l10n.chartPriceLineReachedToast(
        line.coin,
        formatHlPrice(line.level,
            decimalCap: HlMarketDirectory.byWire(line.wireCoin)?.pxDecimalCap),
      ),
      duration: _shown,
    );
    _timer = Timer(_gap, () {
      _timer = null;
      _pump();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
