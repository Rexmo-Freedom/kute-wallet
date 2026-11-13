// BrantaPayeeService (lib/services/branta/branta_payee_service.dart): who
// Send is paying, by Branta. A payee only for the very address and rail
// Send pays, the swapped-address warning, nothing for anything else; a
// lookup capped at its timeout, errors as "no badge", answers cached,
// failures remembered for a minute, one lookup in flight per input; the
// rails each send maps to; nothing looked up that Branta cannot verify.

import 'dart:async';

import 'package:branta/branta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/branta/branta_payee_service.dart';

const _addr = 'bc1qgw3dzmhnyvcswc9r0v0z0ajtp8ulm4nuyeahwr';
const _code = 'bitcoin:$_addr?branta_id=abc%2Bdef%3D%3D&branta_secret=s3cr3t';
const _invoice = 'lnbc10u1p4w23tzpp50uc6g4020tt3ffp5xfpp83k0lcv2spyt';
const _evm = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
const _polCode = 'pol:$_evm?value=50&branta_id=xyz&branta_secret=k';
const _logo = 'https://guardrail.branta.pro/logo.png';
const _sol = 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB';
const _tron = 'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb';

VerifyResult _match(String value, DestinationType type,
        {String name = 'Bitfinex', String? logo = _logo}) =>
    VerifyResult(
      status: VerifyStatus.match,
      payments: [
        Payment(
          destinations: [
            Destination(value: value, type: type, isEncrypted: false),
          ],
          platform: name,
          platformLogoUrl: logo,
        ),
      ],
      matchedDestinations: [
        Destination(value: value, type: type, isEncrypted: false),
      ],
      verifyUrl: 'https://guardrail.branta.pro/v2/verify/x',
    );

const _unknown = VerifyResult(status: VerifyStatus.unknown, verifyUrl: '');

/// A verifier answering [answer], recording each input it was asked.
class _Fake {
  _Fake(this.answer);

  FutureOr<VerifyResult> Function(String input) answer;
  final inputs = <String>[];

  Future<VerifyResult> call(String input) async {
    inputs.add(input);
    return answer(input);
  }
}

void main() {
  group('lookup', () {
    test('a code Branta matches for the address paid: the payee', () async {
      final fake = _Fake((_) => _match(_addr, DestinationType.bitcoinAddress));
      final service = BrantaPayeeService(verifier: fake.call);
      service.noteInput(_code);
      final payee = await service.lookup(_addr, BrantaRail.bitcoinOnchain);
      expect(payee, const BrantaPayee.verified(name: 'Bitfinex', logoUrl: _logo));
      expect(payee!.verified, isTrue);
      // Looked up by the code as scanned (its Branta params), not the
      // bare address Send kept.
      expect(fake.inputs, [_code]);
    });

    test('a match on another rail or another address is no payee', () async {
      final fake =
          _Fake((_) => _match(_evm, DestinationType.usdtPolygon, name: 'X'));
      final service = BrantaPayeeService(verifier: fake.call);
      service.noteInput(_polCode);
      // Registered as USDT on Polygon: paid as USDC, nothing shows.
      expect(await service.lookup(_evm, BrantaRail.usdcPolygon), isNull);
      expect(await service.lookup(_evm, BrantaRail.usdtPolygon),
          const BrantaPayee.verified(name: 'X', logoUrl: _logo));

      final other = BrantaPayeeService(
          verifier: _Fake((_) => _match(
              'bc1qother000000000000000000000000000000',
              DestinationType.bitcoinAddress)).call);
      other.noteInput(_code);
      expect(await other.lookup(_addr, BrantaRail.bitcoinOnchain), isNull);
    });

    test('EVM and bech32 addresses match without case', () async {
      final service = BrantaPayeeService(
          verifier: _Fake((_) =>
              _match(_evm.toLowerCase(), DestinationType.usdcPolygon)).call);
      service.noteInput(_polCode);
      expect((await service.lookup(_evm, BrantaRail.usdcPolygon))?.name,
          'Bitfinex');
    });

    test('Solana and Tron addresses (base58) match only exactly', () async {
      final sol = BrantaPayeeService(
          verifier:
              _Fake((_) => _match(_sol, DestinationType.usdtSolana)).call);
      sol.noteInput('sol:$_sol?branta_id=x&branta_secret=k');
      expect((await sol.lookup(_sol, BrantaRail.usdtSolana))?.name, 'Bitfinex');
      // The same code paid as USDC on Solana, or USDT on another chain:
      // not the rail Branta bound.
      expect(await sol.lookup(_sol, BrantaRail.usdcSolana), isNull);
      expect(await sol.lookup(_sol, BrantaRail.usdtTron), isNull);

      final caseOff = BrantaPayeeService(
          verifier: _Fake(
                  (_) => _match(_sol.toLowerCase(), DestinationType.usdcSolana))
              .call);
      caseOff.noteInput('sol:$_sol?branta_id=x&branta_secret=k');
      expect(await caseOff.lookup(_sol, BrantaRail.usdcSolana), isNull);

      final tron = BrantaPayeeService(
          verifier: _Fake(
                  (_) => _match(_tron.toUpperCase(), DestinationType.usdtTron))
              .call);
      tron.noteInput('tron:$_tron?branta_id=x&branta_secret=k');
      expect(await tron.lookup(_tron, BrantaRail.usdtTron), isNull);
    });

    test('a match naming nobody shows nothing; a non-https logo is dropped',
        () async {
      final nameless = BrantaPayeeService(
          verifier: _Fake((_) =>
              _match(_invoice, DestinationType.bolt11, name: '  ')).call);
      expect(await nameless.lookup(_invoice, BrantaRail.lightning), isNull);
      final http = BrantaPayeeService(
          verifier: _Fake((_) => _match(_invoice, DestinationType.bolt11,
              logo: 'http://guardrail.branta.pro/x.png')).call);
      expect(await http.lookup(_invoice, BrantaRail.lightning),
          const BrantaPayee.verified(name: 'Bitfinex'));
    });

    test('unknown: nothing; tampered: the warning', () async {
      final unknown = BrantaPayeeService(verifier: _Fake((_) => _unknown).call);
      expect(await unknown.lookup(_invoice, BrantaRail.lightning), isNull);
      final tampered = BrantaPayeeService(
          verifier: _Fake((_) => const VerifyResult(
              status: VerifyStatus.tampered, verifyUrl: '')).call);
      tampered.noteInput(_code);
      final payee = await tampered.lookup(_addr, BrantaRail.bitcoinOnchain);
      expect(payee, const BrantaPayee.tampered());
      expect(payee!.tampered, isTrue);
      expect(payee.name, isNull);
    });

    test('a bare address is never looked up', () async {
      final fake = _Fake((_) => _unknown);
      final service = BrantaPayeeService(verifier: fake.call);
      expect(await service.lookup(_addr, BrantaRail.bitcoinOnchain), isNull);
      expect(await service.lookup(_evm, BrantaRail.usdcPolygon), isNull);
      expect(fake.inputs, isEmpty);
    });

    test('a slow lookup gives up at the timeout, never blocking', () async {
      final never = Completer<VerifyResult>();
      final service = BrantaPayeeService(
          verifier: (_) => never.future,
          timeout: const Duration(milliseconds: 50));
      final sw = Stopwatch()..start();
      expect(await service.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      expect(kBrantaLookupTimeout, lessThanOrEqualTo(const Duration(seconds: 2)));
    });

    test('an error (or Branta unreachable) is no badge, remembered a minute',
        () async {
      var now = DateTime(2026, 11, 12, 12);
      var calls = 0;
      final service = BrantaPayeeService(
        verifier: (_) async {
          calls++;
          throw Exception('offline');
        },
        now: () => now,
      );
      expect(await service.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(await service.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(calls, 1, reason: 'no retry storm');
      now = now.add(const Duration(seconds: 61));
      expect(await service.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(calls, 2);

      var incompleteCalls = 0;
      final incomplete = BrantaPayeeService(
        verifier: (_) async {
          incompleteCalls++;
          return const VerifyResult(
              status: VerifyStatus.incomplete, verifyUrl: '');
        },
        now: () => now,
      );
      expect(await incomplete.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(await incomplete.lookup(_invoice, BrantaRail.lightning), isNull);
      expect(incompleteCalls, 1);
    });

    test('answers are cached; one lookup in flight is shared', () async {
      final gate = Completer<void>();
      final fake = _Fake((_) async {
        await gate.future;
        return _match(_invoice, DestinationType.bolt11);
      });
      final service = BrantaPayeeService(verifier: fake.call);
      final a = service.lookup(_invoice, BrantaRail.lightning);
      final b = service.lookup(_invoice, BrantaRail.lightning);
      gate.complete();
      expect((await a)?.name, 'Bitfinex');
      expect((await b)?.name, 'Bitfinex');
      expect(await service.lookup(_invoice, BrantaRail.lightning),
          isNotNull);
      expect(fake.inputs, hasLength(1));
      expect(service.debugCacheSize, 1);
    });

    test('the cache is bounded', () async {
      final service = BrantaPayeeService(
          verifier: _Fake((_) => _unknown).call, maxEntries: 3);
      for (var i = 0; i < 6; i++) {
        await service.lookup('lnbc$i', BrantaRail.lightning);
      }
      expect(service.debugCacheSize, 3);
    });

    test('cached() reads memory only and never starts a lookup', () async {
      final fake = _Fake((_) => _match(_invoice, DestinationType.bolt11));
      final service = BrantaPayeeService(verifier: fake.call);
      expect(service.cached(_invoice, BrantaRail.lightning), isNull);
      expect(fake.inputs, isEmpty);
      await service.lookup(_invoice, BrantaRail.lightning);
      expect(service.cached(_invoice, BrantaRail.lightning)?.verified, isTrue);
    });

    test('brantaVerifiedPayee is a yes/no from memory', () async {
      final saved = BrantaPayeeService.shared;
      addTearDown(() => BrantaPayeeService.shared = saved);
      final fake = _Fake((_) => _match(_invoice, DestinationType.bolt11));
      BrantaPayeeService.shared = BrantaPayeeService(verifier: fake.call);
      expect(brantaVerifiedPayee(_invoice, BrantaRail.lightning), isFalse);
      expect(fake.inputs, isEmpty);
      await BrantaPayeeService.shared.lookup(_invoice, BrantaRail.lightning);
      expect(brantaVerifiedPayee(_invoice, BrantaRail.lightning), isTrue);
      expect(brantaVerifiedPayee(_invoice, null), isFalse);
    });
  });

  group('noted inputs', () {
    test('a unified code is remembered for its address and its invoice', () {
      final service = BrantaPayeeService(verifier: _Fake((_) => _unknown).call);
      final unified = 'bitcoin:${_addr.toUpperCase()}?lightning=$_invoice'
          '&branta_id=a&branta_secret=b';
      service.noteInput(unified);
      expect(service.inputFor(_addr), unified);
      expect(service.inputFor(_invoice), unified);
      expect(service.inputFor('bc1qsomethingelse'), 'bc1qsomethingelse');
    });

    test('only codes with Branta params are kept', () {
      final service = BrantaPayeeService(verifier: _Fake((_) => _unknown).call);
      service.noteInput('bitcoin:$_addr?amount=0.1');
      expect(service.inputFor(_addr), _addr);
      service.noteInput(_polCode);
      expect(service.inputFor(_evm), _polCode);
    });
  });

  group('rails', () {
    test('coins on networks: the stablecoins Branta has and Kute pays', () {
      expect(brantaRailFor(assetCode: 'USDC', chain: 'polygon'),
          BrantaRail.usdcPolygon);
      expect(brantaRailFor(assetCode: 'usdt', chain: 'Polygon'),
          BrantaRail.usdtPolygon);
      expect(brantaRailFor(assetCode: 'USDC.e', chain: 'polygon'), isNull);
      // branta 4.3.0: Ethereum, BNB Smart Chain, Tron (USDT), Solana.
      expect(brantaRailFor(assetCode: 'USDC', chain: 'ethereum'),
          BrantaRail.usdcEthereum);
      expect(brantaRailFor(assetCode: 'USDT', chain: 'ethereum'),
          BrantaRail.usdtEthereum);
      expect(
          brantaRailFor(assetCode: 'USDC', chain: 'bsc'), BrantaRail.usdcBsc);
      expect(
          brantaRailFor(assetCode: 'USDT', chain: 'bsc'), BrantaRail.usdtBsc);
      expect(
          brantaRailFor(assetCode: 'USDT', chain: 'tron'), BrantaRail.usdtTron);
      expect(brantaRailFor(assetCode: 'USDC', chain: 'solana'),
          BrantaRail.usdcSolana);
      expect(brantaRailFor(assetCode: 'USDT', chain: 'solana'),
          BrantaRail.usdtSolana);
      // Branta has no USDC on Tron; Kute pays no TON; other tokens and
      // other networks have nothing.
      expect(brantaRailFor(assetCode: 'USDC', chain: 'tron'), isNull);
      expect(brantaRailFor(assetCode: 'USDT', chain: 'ton'), isNull);
      expect(brantaRailFor(assetCode: 'USDT0', chain: 'ethereum'), isNull);
      expect(brantaRailFor(assetCode: 'USDB', chain: 'ethereum'), isNull);
      expect(brantaRailFor(assetCode: 'BTC', chain: 'solana'), isNull);
      for (final chain in ['base', 'arbitrum', 'optimism', 'avalanche']) {
        expect(brantaRailFor(assetCode: 'USDC', chain: chain), isNull,
            reason: chain);
        expect(brantaRailFor(assetCode: 'USDT', chain: chain), isNull,
            reason: chain);
      }
      expect(brantaRailFor(assetCode: 'BTC', chain: 'bitcoin'),
          BrantaRail.bitcoinOnchain);
      expect(brantaRailFor(assetCode: 'BTC', chain: 'lightning'),
          BrantaRail.lightning);
    });

    test('bitcoin destinations by their shape', () {
      expect(brantaRailForBitcoin(_invoice), BrantaRail.lightning);
      expect(brantaRailForBitcoin('lightning:${_invoice.toUpperCase()}'),
          BrantaRail.lightning);
      expect(brantaRailForBitcoin(_addr), BrantaRail.bitcoinOnchain);
      expect(brantaRailForBitcoin(_code), BrantaRail.bitcoinOnchain);
      expect(brantaRailForBitcoin('1BoatSLRHtKNngkdXEeobR76b53LETtpyT'),
          BrantaRail.bitcoinOnchain);
      expect(brantaRailForBitcoin('jay@paykute.com'), isNull);
      expect(brantaRailForBitcoin('lnurl1dp68gurn8ghj7'), isNull);
      expect(brantaRailForBitcoin(_evm), isNull);
      expect(brantaRailForBitcoin('spark1pgss93sy072yrmtad5cy2srwj'), isNull);
    });

    test('rails name Branta destination types', () {
      expect(BrantaRail.bitcoinOnchain.type, DestinationType.bitcoinAddress);
      expect(BrantaRail.lightning.type, DestinationType.bolt11);
      expect(BrantaRail.usdcPolygon.type, DestinationType.usdcPolygon);
      expect(BrantaRail.usdtPolygon.type, DestinationType.usdtPolygon);
      expect(BrantaRail.usdcEthereum.type, DestinationType.usdcEthereum);
      expect(BrantaRail.usdtEthereum.type, DestinationType.usdtEthereum);
      expect(BrantaRail.usdcBsc.type, DestinationType.usdcBsc);
      expect(BrantaRail.usdtBsc.type, DestinationType.usdtBsc);
      expect(BrantaRail.usdtTron.type, DestinationType.usdtTron);
      expect(BrantaRail.usdcSolana.type, DestinationType.usdcSolana);
      expect(BrantaRail.usdtSolana.type, DestinationType.usdtSolana);
    });

    test('every Branta chain code is noted by the address Send keeps', () {
      final service = BrantaPayeeService(verifier: _Fake((_) => _unknown).call);
      for (final scheme in kBrantaChainSchemes) {
        final code = '$scheme:$_sol?branta_id=x&branta_secret=k';
        service.noteInput(code);
        expect(service.inputFor(_sol), code, reason: scheme);
      }
    });

    test('what Branta can verify', () {
      expect(brantaCanVerify(_code), isTrue);
      expect(brantaCanVerify(_polCode), isTrue);
      expect(brantaCanVerify(_invoice), isTrue);
      expect(brantaCanVerify('LIGHTNING:${_invoice.toUpperCase()}'), isTrue);
      expect(brantaCanVerify(_addr), isFalse);
      expect(brantaCanVerify(_evm), isFalse);
      expect(brantaCanVerify('bitcoin:$_addr?branta_id=x'), isFalse);
      expect(brantaCanVerify(''), isFalse);
    });
  });
}
