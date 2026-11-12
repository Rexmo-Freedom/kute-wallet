// lib/providers/crypto_next_round_provider.dart
//
// Gamma's read of the next round of a live crypto round card or row, the
// one its Up and Down buttons bet on (crypto_next_round.dart). Only
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

/// One asset's rounds of one length, for the strip's pick: the asset as the
/// card's config names it ('BTC'), the length in minutes.
typedef CryptoRoundPickKey = ({String asset, int minutes});

/// The start (UTC seconds) of the round the person tapped on the strip of
/// the live round card showing this asset at this length
/// (crypto_round_strip.dart); null while the buttons follow the roll. Per
/// asset and length, so another length starts clean; gone with the card
/// (the strip's rules decide how long a pick stands).
final cryptoPickedRoundProvider =
    StateProvider.autoDispose.family<int?, CryptoRoundPickKey>((_, __) => null);

/// The side the round card's quick amounts are for: the one last tapped
/// on the card, Up until then ('up' or 'down'). Per asset and length.
final cryptoQuickSideProvider = StateProvider.autoDispose
    .family<String, CryptoRoundPickKey>((_, __) => 'up');
