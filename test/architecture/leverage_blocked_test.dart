// Leverage is blocked in Kute (founder, 14 October 2026), whatever the
// backend policy publishes: every Investing order is 1x isolated, and a
// position opened elsewhere at more leverage or in cross is never
// rewritten. These tests hold the rule at every layer: the one constant,
// the order notifier's leverage write, the intent a grant binds, the one
// exchange door every leverage write takes, and a scan of the sources.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/helpers/auth_grant.dart' show IntentLimit;
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

const _perp = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

HlPerpPosition _held({required int leverage, required bool cross}) =>
    HlPerpPosition(
      coin: 'BTC',
      szi: 0.01,
      entryPx: 60000,
      positionValue: 600,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: 55000,
      marginUsed: 600 / leverage,
      leverageType: cross ? 'cross' : 'isolated',
      leverageValue: leverage,
      maxLeverage: 40,
    );

void main() {
  test('the app offers 1x isolated only', () {
    expect(kHlMaxOfferedLeverage, 1);
    expect(kHlCrossMarginOffered, isFalse);
    expect(hlAppLeverage(40, 40), 1);
    expect(hlAppLeverage(0, 40), 1);
    expect(HlIntents.clampLeverage(_perp, 20), 1);
  });

  group('the leverage write before an order', () {
    test('a flat market is set to 1x isolated, whatever was asked', () {
      final write =
          HyperliquidTradingNotifier.leverageWriteFor(_perp, const [], 20);
      expect(write, isNotNull);
      expect(write!.leverage, 1);
      expect(write.isCross, isFalse);
    });

    for (final cross in [false, true]) {
      test(
          'an add to a 10x ${cross ? 'cross' : 'isolated'} position opened '
          'elsewhere writes nothing: that position is never rewritten', () {
        final write = HyperliquidTradingNotifier.leverageWriteFor(
            _perp, [_held(leverage: 10, cross: cross)], 1);
        expect(write, isNull);
      });
    }

    test('an add to a 10x position is bound to the grant at 1x', () {
      // The ticket sizes and binds the add at 1x (the typed dollars are
      // the notional added); the venue keeps the position's own setting.
      final intent = HlIntents.openPosition(
        walletId: 'w',
        market: _perp,
        isLong: true,
        marginUsd: 50,
        leverage: 10,
      );
      expect(intent.limits[IntentLimit.leverage], 1);
    });
  });

  group('the one exchange door every leverage write takes', () {
    late List<String> posted;
    late HyperliquidExchangeService exchange;

    setUp(() {
      posted = [];
      final key = EthPrivateKey.fromHex(
          '0x0123456789012345678901234567890101234567890123456789012345678901');
      exchange = HyperliquidExchangeService(
        credentials: key,
        walletAddress: key.address.hexEip55,
        httpClient: MockClient((request) async {
          final action = (jsonDecode(request.body)
              as Map<String, dynamic>)['action'] as Map<String, dynamic>;
          posted.add(jsonEncode(action));
          return http.Response(
              jsonEncode({
                'status': 'ok',
                'response': {'type': 'default'}
              }),
              200);
        }),
      );
    });

    test('refuses more than 1x before anything is signed or sent', () async {
      await expectLater(
          exchange.updateLeverage(assetId: 0, isCross: false, leverage: 2),
          throwsArgumentError);
      expect(posted, isEmpty);
    });

    test('refuses cross margin before anything is signed or sent', () async {
      await expectLater(
          exchange.updateLeverage(assetId: 0, isCross: true, leverage: 1),
          throwsArgumentError);
      expect(posted, isEmpty);
    });

    test('sends 1x isolated', () async {
      await exchange.updateLeverage(assetId: 0, isCross: false, leverage: 1);
      expect(posted, hasLength(1));
      final action = jsonDecode(posted.single) as Map<String, dynamic>;
      expect(action['type'], 'updateLeverage');
      expect(action['leverage'], 1);
      expect(action['isCross'], isFalse);
    });
  });

  test('no source sends leverage around the app rule', () {
    final offenders = <String>[];
    final callers = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path;
      final text = entity.readAsStringSync();
      // The venue maximum must never become an order's leverage.
      for (final pattern in [
        'clamp(1, market.maxLeverage)',
        'clamp(1, market.offeredMaxLeverage)',
      ]) {
        if (text.contains(pattern)) offenders.add('$path: $pattern');
      }
      if (RegExp(r'isCross:\s*true').hasMatch(text)) {
        offenders.add('$path: isCross: true');
      }
      if (RegExp(r'\.updateLeverage\(').hasMatch(text)) callers.add(path);
    }
    expect(offenders, isEmpty);
    // Every leverage write goes through the notifier's leverageWriteFor or
    // the Ledger order path, both 1x isolated, and then through the
    // exchange door tested above.
    expect(
        callers,
        unorderedEquals([
          'lib/providers/hyperliquid_trading_provider.dart',
          'lib/screens/ledger/hyperliquid/ledger_hl_execution_target.dart',
          'lib/services/hardware/ledger/ledger_hyperliquid_executor.dart',
        ]));
  });
}
