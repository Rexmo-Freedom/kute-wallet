// lib/providers/polymarket_instant_provider.dart
//
// The filter of Predictions › Instant, remembered on this device: a
// convenience, so a failed read or save only means Bitcoin's five minutes
// again. Asset and length only (instant_rounds.dart), in their own Hive box
// as the watchlist is.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/services/polymarket/instant_rounds.dart';

final polyInstantChoiceProvider =
    NotifierProvider<PolyInstantChoiceNotifier, PolyInstantChoice>(
        PolyInstantChoiceNotifier.new);

class PolyInstantChoiceNotifier extends Notifier<PolyInstantChoice> {
  static const boxName = 'polymarket_instant';
  static const _key = 'choice';

  /// Whether the person has picked in this run, so a slow first read never
  /// overwrites the pick.
  bool _picked = false;

  @override
  PolyInstantChoice build() {
    if (Hive.isBoxOpen(boxName)) return _read(Hive.box<String>(boxName));
    Hive.openBox<String>(boxName).then((box) {
      if (!_picked) state = _read(box);
    }).catchError((_) {});
    return kPolyInstantDefault;
  }

  static PolyInstantChoice _read(Box<String> box) {
    try {
      final raw = box.get(_key);
      if (raw == null) return kPolyInstantDefault;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final asset = map['asset'];
      final length = map['length'];
      if (asset is! String || asset.isEmpty) return kPolyInstantDefault;
      if (length is! String || !kPolyInstantLengths.contains(length)) {
        return kPolyInstantDefault;
      }
      return PolyInstantChoice(asset: asset, length: length);
    } catch (_) {
      return kPolyInstantDefault;
    }
  }

  void pick(PolyInstantChoice next) {
    _picked = true;
    if (next == state) return;
    state = next;
    final raw = jsonEncode({'asset': next.asset, 'length': next.length});
    Future<void>(() async {
      final box = Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
      await box.put(_key, raw);
    }).catchError((_) {});
  }
}
