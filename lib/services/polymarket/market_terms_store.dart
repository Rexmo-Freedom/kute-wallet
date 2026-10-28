// lib/services/polymarket/market_terms_store.dart
//
// The two market facts an order is signed with, saved per token across
// sessions, so a slow approval never sends the placement back to the
// venue for them:
//
//   * neg-risk: which exchange the order is signed for. It never changes
//     for a market, so once read (a REST book, a neg-risk probe) it is
//     saved for good.
//   * tick size: the market's price increment. It only moves when the
//     price crosses about 4¢ or 96¢; the market feed announces the move
//     (`tick_size_change`), and every REST book or `/tick-size` read
//     confirms the current value. A saved increment is used while the
//     feed is current for the token or the value was confirmed recently;
//     a fine increment seen with a price well inside the band is treated
//     as unknown (the step went back to 0.01 while nobody was listening).
//
// Public market data only: token ids and venue parameters. Nothing about
// the person's account is written here. The box is opened when a slip
// opens, never at launch, and the saved rows are also held in memory so
// the sign path reads them synchronously.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderBook;

class PolymarketMarketTerms {
  const PolymarketMarketTerms({this.negRisk, this.tickSize, this.tickSizeAt});

  /// Null until read once; then fixed.
  final bool? negRisk;

  /// The last increment seen, and when it was seen (confirmed or changed).
  final String? tickSize;
  final DateTime? tickSizeAt;

  Map<String, Object?> toJson() => {
        'negRisk': negRisk,
        'tickSize': tickSize,
        'tickSizeAt': tickSizeAt?.millisecondsSinceEpoch,
      };

  static PolymarketMarketTerms? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['tickSizeAt'];
    return PolymarketMarketTerms(
      negRisk: raw['negRisk'] is bool ? raw['negRisk'] as bool : null,
      tickSize: raw['tickSize'] is String ? raw['tickSize'] as String : null,
      tickSizeAt:
          at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null,
    );
  }
}

class PolymarketMarketTermsStore {
  PolymarketMarketTermsStore._();

  static const boxName = 'polymarket_market_terms_v1';

  /// How long a confirmed increment stands on its own, with no feed
  /// activity for the token.
  static const Duration tickSizeFreshFor = Duration(minutes: 10);

  static const Set<String> validTickSizes = {
    '0.1',
    '0.01',
    '0.005',
    '0.0025',
    '0.001',
    '0.0001'
  };

  static final Map<String, PolymarketMarketTerms> _memory = {};
  static Future<Box<String>?>? _opening;
  static Box<String>? _open;
  static DateTime Function() clock = DateTime.now;

  /// Whether the live feed is current for a token; wired by the live
  /// book registry so this file does not import the socket.
  static bool Function(String tokenId) feedIsCurrent = (_) => false;

  @visibleForTesting
  static void resetForTest() {
    _memory.clear();
    _opening = null;
    _open = null;
    clock = DateTime.now;
    feedIsCurrent = (_) => false;
  }

  static Future<Box<String>?> _box() => _opening ??= () async {
        try {
          final box = Hive.isBoxOpen(boxName)
              ? Hive.box<String>(boxName)
              : await Hive.openBox<String>(boxName)
                  .timeout(const Duration(seconds: 5));
          // Saved rows never override what this session already read.
          for (final key in box.keys) {
            final id = '$key';
            if (_memory.containsKey(id)) continue;
            final terms = PolymarketMarketTerms.fromJson(
                jsonDecode(box.get(key) ?? 'null'));
            if (terms != null) _memory[id] = terms;
          }
          return _open = box;
        } catch (_) {
          // No Hive (a test) or a damaged box: memory only.
          return null;
        }
      }();

  /// Opens the box and loads the saved rows (a slip about to open).
  static Future<void> warmUp() => _box().then((_) {});

  /// What is known about [tokenId] now, from this session or the disk.
  static PolymarketMarketTerms? read(String tokenId) => _memory[tokenId];

  static void _write(String tokenId, PolymarketMarketTerms terms) {
    _memory[tokenId] = terms;
    // Written through only once the box is open ([warmUp]); a save never
    // opens it.
    try {
      unawaited(_open?.put(tokenId, jsonEncode(terms.toJson())));
    } catch (_) {}
  }

  /// Records a neg-risk read for good, and a tick size as confirmed now.
  static void save(String tokenId, {bool? negRisk, String? tickSize}) {
    if (tokenId.isEmpty) return;
    final held = _memory[tokenId];
    final tick = tickSize != null && validTickSizes.contains(tickSize)
        ? tickSize
        : null;
    _write(
        tokenId,
        PolymarketMarketTerms(
          negRisk: held?.negRisk ?? negRisk,
          tickSize: tick ?? held?.tickSize,
          tickSizeAt: tick != null ? clock() : held?.tickSizeAt,
        ));
  }

  /// The feed announced a new increment for [tokenId].
  static void saveTickSize(String tokenId, String tickSize) =>
      save(tokenId, tickSize: tickSize);

  /// A REST book carries both facts.
  static void saveFromBook(OrderBook book) => save(book.assetId,
      negRisk: book.negRisk, tickSize: book.minTickSize);

  /// The increment to sign [tokenId] with now, or null when it must be
  /// read: none saved, saved too long ago with no feed to announce a
  /// change, or a fine increment while [referencePrice] sits well inside
  /// the band where the venue quotes 0.01.
  static String? currentTickSize(String tokenId, {double? referencePrice}) {
    final terms = _memory[tokenId];
    final tick = terms?.tickSize, at = terms?.tickSizeAt;
    if (tick == null || at == null) return null;
    if (referencePrice != null &&
        referencePrice > 0.05 &&
        referencePrice < 0.95 &&
        (tick == '0.001' || tick == '0.0001')) {
      return null;
    }
    if (clock().difference(at) <= tickSizeFreshFor) return tick;
    return feedIsCurrent(tokenId) ? tick : null;
  }
}
