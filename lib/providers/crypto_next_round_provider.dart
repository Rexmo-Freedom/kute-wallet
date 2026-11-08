// lib/providers/crypto_next_round_provider.dart
//
// Gamma's read of the next window of a live 5-minute crypto card, for its
// rolling buttons (lib/services/polymarket/crypto_next_round.dart). Only
// the event: its tokens, title and times. Its odds come from the live feed
// alone. A window Gamma does not have yet, or not open for orders, reads
// null and is asked again every 10 s while the card wants it.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart' show Btc5MinEvent;
import 'package:kute/providers/crypto_live_odds_provider.dart'
    show cryptoOddsClockProvider;
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/current_round.dart'
    show polyRoundWindowReaderProvider;

/// One window: the asset as the slug writes it, its length, its start
/// (UTC epoch seconds).
typedef CryptoNextRoundKey = ({String asset, int minutes, int start});

/// How long before a window Gamma did not offer is asked for again.
const Duration kCryptoNextRoundRetry = Duration(seconds: 10);

final cryptoNextRoundProvider = FutureProvider.autoDispose
    .family<Btc5MinEvent?, CryptoNextRoundKey>((ref, key) async {
  final read = ref.watch(polyRoundWindowReaderProvider);
  Btc5MinEvent? event;
  try {
    event = await read(key.asset, key.start, key.minutes);
  } catch (_) {
    event = null;
  }
  final now = ref.read(cryptoOddsClockProvider)();
  if (event != null && polyNextRoundOpen(event, start: key.start, now: now)) {
    return event;
  }
  final again = Timer(kCryptoNextRoundRetry, ref.invalidateSelf);
  ref.onDispose(again.cancel);
  return null;
});
