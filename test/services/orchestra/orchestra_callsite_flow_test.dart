import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import '../../helpers/runtime_policy_fixture.dart';

/// The call-site shape every Orchestra payment uses: fetchVerified, then
/// ensurePayable (or confirmStored for a quote kept on screen), then pay.
/// A refused quote must never reach the pay callback.

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _otherEvm = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';

final _now = DateTime.utc(2026, 9, 15, 12);

Map<String, dynamic> _fixture() => jsonDecode(
        File('test/services/fixtures/orchestra_quote_spark_to_polygon.json')
            .readAsStringSync())
    as Map<String, dynamic>;

OrchestraQuoteRequest _request({
  String refund = _ownSpark,
  String recipient = _pmWallet,
  String own = _pmWallet,
  int sats = 100000,
}) =>
    OrchestraQuoteRequest(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: 'polygon',
      destinationAsset: 'USDC.e',
      amountBaseUnits: BigInt.from(sats),
      recipientAddress: recipient,
      refundAddress: refund,
      recipientKind: RecipientKind.ownPmWallet,
      ownAddress: own,
    );

void main() {
  final events = <(String, Map<String, Object>?)>[];

  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    resetOrchestraDecimalsForTest();
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
  });

  Future<T> withQuote<T>(
    Map<String, dynamic> body,
    Future<T> Function() run, {
    void Function()? onQuote,
  }) =>
      http.runWithClient(
        run,
        () => MockClient((req) async {
          onQuote?.call();
          return http.Response(jsonEncode(body), 200);
        }),
      );

  /// Mirrors a Move sheet dispatcher: quote, persist, re-check, pay.
  Future<void> quoteThenPay(
    OrchestraQuoteRequest request, {
    required Map<String, dynamic> body,
    required void Function() pay,
    double usdPerBtc = 60000,
  }) =>
      withQuote(body, () async {
        final verified = await OrchestraQuoteGate.fetchVerified(
          request,
          OrchestraQuoteGate.boundsFor(request, usdPerBtc: usdPerBtc),
          flow: 'move_predictions',
          clock: () => _now,
        );
        OrchestraQuoteGate.ensurePayable(verified,
            amountBaseUnits: request.amountBaseUnits, now: _now);
        pay();
      });

  group('a refused quote never reaches the pay callback', () {
    final cases = <String, (OrchestraQuoteRequest, Map<String, dynamic>, double,
        WalletGuardReason)>{
      'missing quote id': (
        _request(),
        {..._fixture(), 'quoteId': ''},
        60000,
        WalletGuardReason.quoteMissingId
      ),
      'EVM deposit address on a Spark source': (
        _request(),
        {..._fixture(), 'depositAddress': _otherEvm},
        60000,
        WalletGuardReason.depositAddressFormat
      ),
      'deposit memo': (
        _request(),
        {..._fixture(), 'depositMemo': 'memo-1'},
        60000,
        WalletGuardReason.depositMemoPresent
      ),
      'amountIn differs': (
        _request(),
        {..._fixture(), 'amountIn': '100001'},
        60000,
        WalletGuardReason.amountMismatch
      ),
      'expired quote': (
        _request(),
        {..._fixture(), 'expiresAt': '2026-09-15T12:00:10Z'},
        60000,
        WalletGuardReason.quoteExpired
      ),
      'EVM refund on a Spark source': (
        _request(refund: _otherEvm),
        _fixture(),
        60000,
        WalletGuardReason.refundAddressChain
      ),
      'recipient is not the own wallet': (
        _request(recipient: _otherEvm),
        _fixture(),
        60000,
        WalletGuardReason.recipientNotOwn
      ),
      'fee above the cap': (
        _request(),
        {..._fixture(), 'feeBps': 450},
        60000,
        WalletGuardReason.feeAboveCap
      ),
      'echoed destination chain differs': (
        _request(),
        {..._fixture(), 'destinationChain': 'arbitrum'},
        60000,
        WalletGuardReason.echoMismatch
      ),
    };

    cases.forEach((name, c) {
      test(name, () async {
        final (request, body, price, reason) = c;
        var paid = 0;
        await expectLater(
          quoteThenPay(request, body: body, pay: () => paid++, usdPerBtc: price),
          throwsA(isA<WalletGuardException>()
              .having((e) => e.reason, 'reason', reason)),
        );
        expect(paid, 0);
        final rejected =
            events.where((e) => e.$1 == 'orchestra_quote_rejected').toList();
        expect(rejected, hasLength(1));
        expect(rejected.single.$2?['reason'], reason.code);
      });
    });

    test('a valid quote pays exactly once', () async {
      var paid = 0;
      await quoteThenPay(_request(), body: _fixture(), pay: () => paid++);
      expect(paid, 1);
      expect(events.where((e) => e.$1 == 'orchestra_quote_rejected'), isEmpty);
    });

    // The local-price output floor was removed on purpose (6bf6be95,
    // "NO OUTPUT FLOOR" in orchestra_quote_guard.dart): the outcome is
    // shown to the person before they sign instead of being refused
    // against this app's own price.
    final unrefused = <String, (Map<String, dynamic>, double)>{
      'output under the local price': (
        {..._fixture(), 'estimatedOut': '50000000'},
        60000
      ),
      'no local price': (_fixture(), 0),
    };
    unrefused.forEach((name, c) {
      test('$name is not a guard refusal', () async {
        final (body, price) = c;
        var paid = 0;
        await quoteThenPay(_request(),
            body: body, pay: () => paid++, usdPerBtc: price);
        expect(paid, 1);
        expect(
            events.where((e) => e.$1 == 'orchestra_quote_rejected'), isEmpty);
      });
    });

    test('a quote transport failure never pays and is not a guard event',
        () async {
      var paid = 0;
      await expectLater(
        http.runWithClient(
          () async {
            final request = _request();
            await OrchestraQuoteGate.fetchVerified(
              request,
              OrchestraQuoteGate.boundsFor(request, usdPerBtc: 60000),
              flow: 'move_predictions',
              clock: () => _now,
            );
            paid++;
          },
          () => MockClient((_) async => http.Response('{"error":"x"}', 502)),
        ),
        throwsA(isA<OrchestraQuoteFailure>()),
      );
      expect(paid, 0);
      expect(events.where((e) => e.$1 == 'orchestra_quote_rejected'), isEmpty);
    });
  });

  group('stored quote confirmation (Polymarket screens)', () {
    Future<VerifiedOrchestraQuote> fetchAt(
            DateTime at, Map<String, dynamic> body, {int sats = 100000}) =>
        withQuote(body, () {
          final request = _request(sats: sats);
          return OrchestraQuoteGate.fetchVerified(
            request,
            OrchestraQuoteGate.boundsFor(request, usdPerBtc: 60000),
            flow: 'pm_deposit',
            clock: () => at,
          );
        });

    test('an expired stored quote re-quotes once and needs another tap',
        () async {
      final stored = await fetchAt(_now, _fixture());
      final later = _now.add(const Duration(minutes: 2));
      final freshBody = {
        ..._fixture(),
        'quoteId': 'q_fresh',
        'expiresAt': '2026-09-15T12:04:00Z',
      };
      var requotes = 0;
      var paid = 0;
      VerifiedOrchestraQuote? shown;

      Future<void> confirm(VerifiedOrchestraQuote current) async {
        final checked = await OrchestraQuoteGate.confirmStored(
          current,
          amountBaseUnits: BigInt.from(100000),
          clock: () => later,
          requote: () {
            requotes++;
            return fetchAt(later, freshBody);
          },
        );
        if (checked.refreshed) {
          shown = checked.quote;
          return;
        }
        paid++;
      }

      await confirm(stored);
      expect(requotes, 1);
      expect(paid, 0, reason: 'the refreshed amount must be confirmed first');
      expect(shown?.quoteId, 'q_fresh');

      await confirm(shown!);
      expect(requotes, 1);
      expect(paid, 1);
    });

    test('an amount change since the quote re-quotes instead of paying',
        () async {
      final stored = await fetchAt(_now, _fixture());
      var requotes = 0;
      final checked = await OrchestraQuoteGate.confirmStored(
        stored,
        amountBaseUnits: BigInt.from(120000),
        clock: () => _now,
        requote: () {
          requotes++;
          return fetchAt(
              _now, {..._fixture(), 'amountIn': '120000', 'estimatedOut': '70560000'},
              sats: 120000);
        },
      );
      expect(requotes, 1);
      expect(checked.refreshed, isTrue);
      expect(checked.quote.amountIn, BigInt.from(120000));
    });

    test('a still-valid stored quote pays without re-quoting', () async {
      final stored = await fetchAt(_now, _fixture());
      var requotes = 0;
      final checked = await OrchestraQuoteGate.confirmStored(
        stored,
        amountBaseUnits: BigInt.from(100000),
        clock: () => _now.add(const Duration(seconds: 30)),
        requote: () {
          requotes++;
          return fetchAt(_now, _fixture());
        },
      );
      expect(requotes, 0);
      expect(checked.refreshed, isFalse);
      expect(identical(checked.quote, stored), isTrue);
    });

    test('a refused replacement quote propagates and nothing is paid',
        () async {
      final stored = await fetchAt(_now, _fixture());
      final later = _now.add(const Duration(minutes: 3));
      await expectLater(
        OrchestraQuoteGate.confirmStored(
          stored,
          amountBaseUnits: BigInt.from(100000),
          clock: () => later,
          requote: () => fetchAt(later, {
            ..._fixture(),
            'expiresAt': '2026-09-15T12:05:00Z',
            'feeBps': 900,
          }),
        ),
        throwsA(isA<WalletGuardException>()
            .having((e) => e.reason, 'reason', WalletGuardReason.feeAboveCap)),
      );
    });
  });

  group('local-price reference', () {
    test('BTC to a USD stablecoin is valued in destination units', () {
      final v = OrchestraQuoteGate.referenceOutputUnits(_request(),
          usdPerBtc: 60000);
      expect(v, closeTo(60000000, 0.001));
    });

    test('a USD stablecoin to BTC is valued in sats', () {
      final request = OrchestraQuoteRequest(
        sourceChain: 'polygon',
        sourceAsset: 'USDC.e',
        destinationChain: 'spark',
        destinationAsset: 'BTC',
        amountBaseUnits: BigInt.from(6000000),
        recipientAddress: _ownSpark,
        refundAddress: _pmWallet,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      );
      expect(
          OrchestraQuoteGate.referenceOutputUnits(request, usdPerBtc: 60000),
          closeTo(10000, 0.001));
      expect(
          OrchestraQuoteGate.boundsFor(request, usdPerBtc: 60000).expiryMargin,
          OrchestraQuoteBounds.relayerSourceExpiryMargin);
    });

    test('no price or an unpriced pair has no reference', () {
      expect(
          OrchestraQuoteGate.referenceOutputUnits(_request(), usdPerBtc: 0),
          isNull);
      expect(
          OrchestraQuoteGate.referenceOutputUnits(_request(),
              usdPerBtc: double.nan),
          isNull);
      final ethRequest = OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'ethereum',
        destinationAsset: 'ETH',
        amountBaseUnits: BigInt.from(100000),
        recipientAddress: _otherEvm,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.external,
      );
      expect(
          OrchestraQuoteGate.referenceOutputUnits(ethRequest, usdPerBtc: 60000),
          isNull);
    });

    OrchestraQuoteRequest sendRequest(String chain, String asset) =>
        OrchestraQuoteRequest(
          sourceChain: 'spark',
          sourceAsset: 'BTC',
          destinationChain: chain,
          destinationAsset: asset,
          amountBaseUnits: BigInt.from(100000),
          recipientAddress: _otherEvm,
          refundAddress: _ownSpark,
          recipientKind: RecipientKind.external,
        );

    test('a hostile catalog cannot scale the floor of a Send route', () {
      setOrchestraDecimalsCatalog(OrchestraRoutesCatalog.fromJson(
        {
          'assets': [
            for (final (chain, asset) in [
              ('tron', 'USDT'),
              ('arbitrum', 'USDT'),
              ('optimism', 'USDT'),
              ('plasma', 'USDT'),
              ('solana', 'USDC'),
              ('bsc', 'USDT'),
            ])
              {
                'id': '$chain:$asset',
                'chain': chain,
                'asset': asset,
                'decimals': 2,
                'route': {
                  'to': ['spark:BTC']
                },
              },
          ],
        },
        source: OrchestraCatalogSource.live,
      ));
      for (final (chain, asset) in [
        ('tron', 'USDT'),
        ('arbitrum', 'USDT'),
        ('optimism', 'USDT'),
        ('plasma', 'USDT'),
        ('solana', 'USDC'),
      ]) {
        expect(
            OrchestraQuoteGate.referenceOutputUnits(sendRequest(chain, asset),
                usdPerBtc: 60000),
            closeTo(60000000, 0.001),
            reason: '$chain:$asset');
      }
      expect(
          OrchestraQuoteGate.referenceOutputUnits(sendRequest('bsc', 'USDT'),
              usdPerBtc: 60000),
          isNull);
    });

    test('an unpinned route has no reference, which no longer refuses it',
        () async {
      // No output floor since 6bf6be95: a missing reference price rides
      // along in the bounds but is not a guard rejection.
      var quotes = 0;
      final request = sendRequest('bsc', 'USDT');
      final bounds = OrchestraQuoteGate.boundsFor(request, usdPerBtc: 60000);
      expect(bounds.inputValueInOutputUnits, isNull);
      final verified = await http.runWithClient(
        () => OrchestraQuoteGate.fetchVerified(
          request,
          bounds,
          flow: 'send_stablecoin',
          clock: () => _now,
        ),
        () => MockClient((req) async {
          quotes++;
          return http.Response(
              jsonEncode({..._fixture(), 'estimatedOut': '6000'}), 200);
        }),
      );
      expect(verified.quote.estimatedOut, '6000');
      expect(quotes, 1);
    });
  });
}
