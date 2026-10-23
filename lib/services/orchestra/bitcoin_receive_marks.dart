// lib/services/orchestra/bitcoin_receive_marks.dart
//
// Which standing `spark:USDB` addresses the person opened from the Bitcoin
// receive's "other coins" line, so the deposits to them also show in the
// Bitcoin Activity (founder decision), and not only in the Investments and
// Dollars Activity where every dollar receive lives.
//
// The Bitcoin ledger otherwise leaves out a conversion that only touches
// dollars ("Bitcoin history excludes unrelated stable-only swaps"); this is
// the one targeted exception. A standing address is reused per wallet,
// source and destination, so the same address can be opened from both
// entry points: the mark records the instruction (its label), the source
// chain, the deposit address on that chain and when it was first opened
// from Bitcoin. Only deposits seen from then on are let in, and only
// receives into the dollar balance paid to that exact address.
//
// Local only: the box never leaves the device and no address reaches
// analytics.

import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;

/// One standing address opened from the Bitcoin receive.
class BitcoinReceiveMark {
  const BitcoinReceiveMark({
    required this.walletId,
    required this.label,
    required this.sourceChain,
    required this.address,
    required this.markedAtMs,
  });

  final String walletId, label, sourceChain, address;

  /// When it was first opened from the Bitcoin receive.
  final int markedAtMs;

  String get key => '$walletId|$label|$sourceChain';

  Map<String, Object> toJson() => {
        'walletId': walletId,
        'label': label,
        'sourceChain': sourceChain,
        'address': address,
        'markedAtMs': markedAtMs,
      };

  static BitcoinReceiveMark? fromJson(Object? json) {
    if (json is! Map) return null;
    final walletId = json['walletId'];
    final label = json['label'];
    final chain = json['sourceChain'];
    final address = json['address'];
    final at = json['markedAtMs'];
    if (walletId is! String ||
        label is! String ||
        chain is! String ||
        address is! String ||
        address.isEmpty ||
        at is! int) {
      return null;
    }
    return BitcoinReceiveMark(
        walletId: walletId,
        label: label,
        sourceChain: chain,
        address: address,
        markedAtMs: at);
  }
}

/// A deposit row seen this long before its address was marked still
/// counts: the provider stamps observation to the second.
const Duration kBitcoinReceiveMarkSkew = Duration(minutes: 1);

abstract final class BitcoinReceiveMarks {
  static const boxName = 'bitcoin_receive_marks_v1';

  /// Bumped whenever the marks change.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<BitcoinReceiveMark> _marks = const [];
  static Future<void>? _loading;

  /// The marks held in memory (loaded by [load]).
  static List<BitcoinReceiveMark> get current => _marks;

  static Future<Box<String>?> _box() async {
    try {
      return Hive.isBoxOpen(boxName)
          ? Hive.box<String>(boxName)
          : await Hive.openBox<String>(boxName);
    } catch (_) {
      return null;
    }
  }

  /// Reads the stored marks once.
  static Future<void> load() => _loading ??= () async {
        final box = await _box();
        if (box == null) return;
        _marks = [
          for (final raw in box.values)
            if (_decode(raw) case final mark?) mark,
        ];
        revision.value++;
      }();

  static BitcoinReceiveMark? _decode(String raw) {
    try {
      return BitcoinReceiveMark.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Records that [address] (instruction [label], source [sourceChain])
  /// was opened from the Bitcoin receive for [walletId]. The first time
  /// is kept. Best effort: a failed write keeps the mark in memory.
  static Future<void> mark({
    required String walletId,
    required String label,
    required String sourceChain,
    required String address,
    DateTime? now,
  }) async {
    await load();
    final mark = BitcoinReceiveMark(
        walletId: walletId,
        label: label,
        sourceChain: sourceChain.trim().toLowerCase(),
        address: address,
        markedAtMs: (now ?? DateTime.now()).millisecondsSinceEpoch);
    if (_marks.any((m) => m.key == mark.key && m.address == address)) return;
    _marks = [
      ..._marks.where((m) => m.key != mark.key),
      mark,
    ];
    revision.value++;
    try {
      await (await _box())?.put(mark.key, jsonEncode(mark.toJson()));
    } catch (_) {}
  }

  /// Forgets every mark of [walletId] (wallet removed).
  static Future<void> deleteWallet(String walletId) async {
    await load();
    _marks = _marks.where((m) => m.walletId != walletId).toList();
    revision.value++;
    try {
      final box = await _box();
      await box?.deleteAll(box.keys
          .where((k) => k.toString().startsWith('$walletId|'))
          .toList());
    } catch (_) {}
  }

  /// Forgets every mark (device wipe).
  static Future<void> clear() async {
    _marks = const [];
    _loading = null;
    revision.value++;
    try {
      await Hive.deleteBoxFromDisk(boxName);
    } catch (_) {}
  }

  @visibleForTesting
  static void reset() {
    _marks = const [];
    _loading = null;
    revision.value++;
  }
}

/// Whether [row] is a deposit to a standing address opened from the
/// Bitcoin receive ([marks]): a receive into the dollar balance on Spark,
/// paid to that exact address on that source chain, by the marked wallet,
/// seen since the mark.
bool shownFromBitcoinReceive(SwapOrder row, List<BitcoinReceiveMark> marks) {
  if (marks.isEmpty ||
      !row.isOrchestra ||
      row.coinTo.toUpperCase() != kOrchestraUsdAssetCode ||
      row.networkTo.toUpperCase() != 'SPARK' ||
      !(row.activityDirection == 'receive' ||
          row.purchaseSource == 'crypto_receive') ||
      row.depositAddress.isEmpty) {
    return false;
  }
  final chain = row.networkFrom.trim().toLowerCase();
  final address = row.depositAddress.toLowerCase();
  return marks.any((m) =>
      m.sourceChain == chain &&
      m.address.toLowerCase() == address &&
      (row.walletId == null || row.walletId == m.walletId) &&
      row.timestamp >= m.markedAtMs - kBitcoinReceiveMarkSkew.inMilliseconds);
}

/// The marks, for the Activity lists. Not autoDispose: a list rebuilds
/// when a mark is added.
final bitcoinReceiveMarksProvider =
    NotifierProvider<BitcoinReceiveMarksNotifier, List<BitcoinReceiveMark>>(
        BitcoinReceiveMarksNotifier.new);

class BitcoinReceiveMarksNotifier extends Notifier<List<BitcoinReceiveMark>> {
  @override
  List<BitcoinReceiveMark> build() {
    void changed() => state = BitcoinReceiveMarks.current;
    BitcoinReceiveMarks.revision.addListener(changed);
    ref.onDispose(() => BitcoinReceiveMarks.revision.removeListener(changed));
    // ignore: discarded_futures
    BitcoinReceiveMarks.load();
    return BitcoinReceiveMarks.current;
  }
}
