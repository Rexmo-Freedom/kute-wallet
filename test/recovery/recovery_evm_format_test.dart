import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/recovery_evm_format.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Position;

// Public BIP39 test vector; never a real user's phrase.
const phrase = 'abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon about';

// Both account-zero EOAs, computed from the derivation code itself.
final legacyEoa = RecoveryCheck.deriveSync(phrase,
    version: EvmDerivationVersion.legacySha256);
final standardEoa = RecoveryCheck.deriveSync(phrase,
    version: EvmDerivationVersion.standardBip39);

const _found = EvmVenueHistory(hyperliquid: true, polymarket: false);
const _empty = EvmVenueHistory(hyperliquid: false, polymarket: false);
const _unknown = EvmVenueHistory(hyperliquid: false);

EvmVenueProbe _probe(Map<String, EvmVenueHistory> byEoa) =>
    (eoa) async => byEoa[eoa] ?? _empty;

Future<EvmRecoveryAccounts> _derive(String _) async =>
    (legacy: legacyEoa, standard: standardEoa);

const _position = Position(
  proxyWallet: '0x0000000000000000000000000000000000000001',
  asset: 'yes',
  conditionId: '0xc1',
  size: 1,
  avgPrice: 0.5,
  initialValue: 0.5,
  currentValue: 1,
  cashPnl: 0.5,
  percentPnl: 100,
  totalBought: 0.5,
  realizedPnl: 0,
  percentRealizedPnl: 0,
  curPrice: 1,
  redeemable: false,
  title: 'Market',
  slug: 'market',
  eventSlug: 'event',
  outcome: 'Yes',
  outcomeIndex: 0,
  oppositeOutcome: 'No',
  oppositeAsset: 'no',
);

/// Polymarket reads with a Safe, a UUPS and a current deposit wallet per
/// EOA. Everything is empty unless set.
class _FakePmReads implements PolymarketAccountReads {
  String safe = '0x00000000000000000000000000000000000000aa';
  String uups = '0x00000000000000000000000000000000000000bb';
  String current = '0x00000000000000000000000000000000000000cc';
  final Set<String> withCode = {};
  final Set<String> withPositions = {};
  final Map<String, BigInt> balances = {};
  bool failRpc = false;

  @override
  String deriveDepositWalletAddress(String eoa) => uups;
  @override
  Future<String> predictDepositWallet(String eoa) async =>
      failRpc ? throw StateError('rpc') : current;
  @override
  Future<bool?> relayerWalletDeployed(String address) async => null;
  @override
  Future<bool> hasCode(String address) async =>
      failRpc ? throw StateError('rpc') : withCode.contains(address);
  @override
  Future<String> deriveSafeAddress(String eoa) async =>
      failRpc ? throw StateError('rpc') : safe;
  @override
  Future<List<Position>> positions(String address) async =>
      withPositions.contains(address) ? const [_position] : const [];
  @override
  Future<BigInt> erc20Balance(
          {required String token, required String owner}) async =>
      failRpc
          ? throw StateError('rpc')
          : balances['$token:$owner'] ?? BigInt.zero;
}

/// Hyperliquid info API with configurable answers.
HyperliquidModel _hl({
  double accountValue = 0,
  List<Object> fills = const [],
  List<Object> ledger = const [],
  bool fail = false,
}) =>
    HyperliquidModel(
      client: MockClient((request) async {
        if (fail) return http.Response('down', 500);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final reply = switch (body['type']) {
          'clearinghouseState' => {
              'marginSummary': {
                'accountValue': '$accountValue',
                'totalMarginUsed': '0'
              },
              'assetPositions': [],
              'withdrawable': '0',
            },
          'spotClearinghouseState' => {'balances': []},
          'userFills' => fills,
          'userNonFundingLedgerUpdates' => ledger,
          _ => null,
        };
        return http.Response(jsonEncode(reply), 200);
      }),
    );

Settings _settings(List<WalletConfig> wallets) => Settings(
      wallets: wallets,
      activeWalletId: wallets.first.id,
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'ssl://example.com:50002',
      nodeType: 'electrum',
      reviewDone: true,
    );

void main() {
  test('the test phrase has two different account-zero EOAs', () {
    expect(RecoveryCheck.matches(legacyEoa, standardEoa), isFalse);
  });

  group('anyTrue', () {
    const timeout = Duration(seconds: 1);
    test('true wins over a failure', () async {
      expect(
          await EvmVenueHistoryReader.anyTrue([
            () async => throw StateError('x'),
            () async => true,
          ], timeout),
          isTrue);
    });
    test('all false is false, a failure without a hit is unknown', () async {
      expect(
          await EvmVenueHistoryReader.anyTrue(
              [() async => false, () async => false], timeout),
          isFalse);
      expect(
          await EvmVenueHistoryReader.anyTrue(
              [() async => false, () async => throw StateError('x')], timeout),
          isNull);
    });
    test('a read that never answers is unknown after the timeout', () async {
      expect(
          await EvmVenueHistoryReader.anyTrue([
            () async => false,
            () => Completer<bool>().future,
          ], const Duration(milliseconds: 50)),
          isNull);
    });
  });

  group('EvmVenueHistoryReader', () {
    late _FakePmReads pm;
    setUp(() => pm = _FakePmReads());

    EvmVenueHistoryReader reader(HyperliquidModel hl,
            {bool activity = false}) =>
        EvmVenueHistoryReader(
          hyperliquid: hl,
          polymarket: pm,
          polymarketActivity: (_) async => activity,
        );

    test('an untouched account is complete and inactive', () async {
      final history = await reader(_hl()).read(legacyEoa);
      expect(history.hyperliquid, isFalse);
      expect(history.polymarket, isFalse);
      expect(history.complete, isTrue);
      expect(history.active, isFalse);
    });

    test('Hyperliquid equity, a fill or a ledger update counts', () async {
      for (final hl in [
        _hl(accountValue: 12.5),
        _hl(fills: [{'coin': 'BTC'}]),
        _hl(ledger: [{'delta': {'type': 'deposit'}}]),
      ]) {
        final history = await reader(hl).read(legacyEoa);
        expect(history.hyperliquid, isTrue);
        expect(history.active, isTrue);
      }
    });

    test('Polymarket positions, activity, pUSD or a deployed Safe count',
        () async {
      pm.withPositions.add(pm.current);
      expect((await reader(_hl()).read(legacyEoa)).polymarket, isTrue);

      pm.withPositions.clear();
      expect((await reader(_hl(), activity: true).read(legacyEoa)).polymarket,
          isTrue);

      pm.balances['${PolymarketConstants.pusdAddress}:${pm.safe}'] =
          BigInt.from(1);
      expect((await reader(_hl()).read(legacyEoa)).polymarket, isTrue);

      pm.balances.clear();
      pm.withCode.add(pm.safe);
      expect((await reader(_hl()).read(legacyEoa)).polymarket, isTrue);
    });

    test('a deployed deposit wallet alone does not count', () async {
      // The app deploys one for every account it provisions.
      pm.withCode.addAll([pm.uups, pm.current]);
      final history = await reader(_hl()).read(standardEoa);
      expect(history.polymarket, isFalse);
      expect(history.active, isFalse);
    });

    test('a zero Safe address is never read for balances', () async {
      pm.safe = PolymarketConstants.zeroAddress;
      pm.balances['${PolymarketConstants.usdcEAddress}:${pm.safe}'] =
          BigInt.from(10);
      expect((await reader(_hl()).read(legacyEoa)).polymarket, isFalse);
    });

    test('failed reads with nothing found leave the answer unknown',
        () async {
      pm.failRpc = true;
      final history = await reader(_hl(fail: true)).read(legacyEoa);
      expect(history.hyperliquid, isNull);
      expect(history.polymarket, isNull);
      expect(history.complete, isFalse);
    });
  });

  group('choose', () {
    test('legacy history keeps the legacy format', () async {
      final choice = await RecoveryEvmFormat.choose(phrase,
          probe: _probe({legacyEoa: _found}), derive: _derive);
      expect(choice.version, EvmDerivationVersion.legacySha256);
      expect(choice.checked, isTrue);
      expect(choice.hyperliquidActive, isTrue);
      expect(choice.analyticsValue, 'legacy');
    });

    test('history on both prefers legacy for continuity', () async {
      final choice = await RecoveryEvmFormat.choose(phrase,
          probe: _probe({legacyEoa: _found, standardEoa: _found}),
          derive: _derive);
      expect(choice.version, EvmDerivationVersion.legacySha256);
    });

    test('standard only, or nothing anywhere, is standard', () async {
      for (final probe in [
        _probe({standardEoa: _found}),
        _probe({}),
      ]) {
        final choice = await RecoveryEvmFormat.choose(phrase,
            probe: probe, derive: _derive);
        expect(choice.version, EvmDerivationVersion.standardBip39);
        expect(choice.checked, isTrue);
        expect(choice.analyticsValue, 'standard');
      }
    });

    test('an unfinished legacy check falls back to standard, unchecked',
        () async {
      final choice = await RecoveryEvmFormat.choose(phrase,
          probe: _probe({legacyEoa: _unknown}), derive: _derive);
      expect(choice.version, EvmDerivationVersion.standardBip39);
      expect(choice.checked, isFalse);
      expect(choice.analyticsValue, 'unchecked');
    });

    test('a failing probe falls back to standard, unchecked', () async {
      final choice = await RecoveryEvmFormat.choose(phrase,
          probe: (_) async => throw StateError('offline'), derive: _derive);
      expect(choice.version, EvmDerivationVersion.standardBip39);
      expect(choice.checked, isFalse);
    });

    test('derives both EOAs off the UI isolate', () async {
      final accounts = await RecoveryEvmFormat.deriveAccounts(phrase);
      expect(accounts.legacy, legacyEoa);
      expect(accounts.standard, standardEoa);
    });
  });

  group('retryPending', () {
    late Directory hiveDir;
    late List<(String, Map<String, Object>?)> events;

    setUp(() async {
      RecoveryEvmFormat.resetForTest();
      hiveDir = await Directory.systemTemp.createTemp('recovery_evm_format');
      Hive.init(hiveDir.path);
      events = [];
      TrackingService.debugTrackObserver =
          (event, params) => events.add((event, params));
    });

    tearDown(() async {
      TrackingService.debugTrackObserver = null;
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    WalletConfig pendingWallet() => WalletConfig(
          id: 'w1',
          name: 'Spending',
          isRestore: true,
          evmDerivationVersion: EvmDerivationVersion.standardBip39,
          evmFormatCheckPending: true,
          recoveryCheckAddress: standardEoa,
        );

    Future<(SettingsModel, List<String>)> run(
        Map<String, EvmVenueHistory> byEoa) async {
      final wallet = pendingWallet();
      final settings = SettingsModel(_settings([wallet]));
      final adopted = <String>[];
      await RecoveryEvmFormat.retryPending(
        settings: settings,
        wallets: [wallet],
        readMnemonic: (_) async => phrase,
        probe: _probe(byEoa),
        derive: _derive,
        onAdopted: (id, _, {required hyperliquidActive}) async =>
            adopted.add(id),
      );
      return (settings, adopted);
    }

    List<Object?> results() => [
          for (final e in events)
            if (e.$1 == 'recovery_evm_format_rechecked') e.$2?['result'],
        ];

    test('switches to legacy when only the legacy account has history',
        () async {
      final (settings, adopted) = await run({legacyEoa: _found});
      final wallet = settings.walletById('w1')!;
      expect(wallet.evmDerivationVersion, EvmDerivationVersion.legacySha256);
      expect(wallet.evmFormatCheckPending, isFalse);
      expect(wallet.recoveryCheckAddress, legacyEoa);
      expect(adopted, ['w1']);
      expect(results(), ['switched_legacy']);
      // Persisted, not only in memory.
      final stored = (Hive.box('settings').get('wallets') as List).single;
      expect(WalletConfig.fromMap(stored as Map).evmDerivationVersion,
          EvmDerivationVersion.legacySha256);
    });

    test('never switches away from a standard account with activity',
        () async {
      final (settings, adopted) =
          await run({legacyEoa: _found, standardEoa: _found});
      final wallet = settings.walletById('w1')!;
      expect(wallet.evmDerivationVersion, EvmDerivationVersion.standardBip39);
      expect(wallet.evmFormatCheckPending, isFalse);
      expect(adopted, isEmpty);
      expect(results(), ['standard_active']);
    });

    test('nothing on legacy settles on standard', () async {
      final (settings, _) = await run({});
      final wallet = settings.walletById('w1')!;
      expect(wallet.evmDerivationVersion, EvmDerivationVersion.standardBip39);
      expect(wallet.evmFormatCheckPending, isFalse);
      expect(results(), ['kept_standard']);
    });

    test('an unfinished retry keeps the flag for the next launch', () async {
      final (settings, _) = await run({legacyEoa: _unknown});
      expect(settings.walletById('w1')!.evmFormatCheckPending, isTrue);
      expect(results(), ['incomplete']);
    });

    test('runs once per launch', () async {
      final wallet = pendingWallet();
      final settings = SettingsModel(_settings([wallet]));
      var reads = 0;
      for (var i = 0; i < 2; i++) {
        await RecoveryEvmFormat.retryPending(
          settings: settings,
          wallets: [wallet],
          readMnemonic: (_) async {
            reads++;
            return phrase;
          },
          probe: _probe({legacyEoa: _unknown}),
          derive: _derive,
        );
      }
      expect(reads, 1);
    });
  });

  group('adoptLegacyEvmAfterRecoveryCheck', () {
    late Directory hiveDir;
    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('adopt_legacy');
      Hive.init(hiveDir.path);
    });
    tearDown(() async {
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    test('refuses a wallet without a pending check', () async {
      final settings = SettingsModel(_settings([
        WalletConfig(
            id: 'w1',
            name: 'Spending',
            evmDerivationVersion: EvmDerivationVersion.standardBip39),
      ]));
      expect(
          await settings.adoptLegacyEvmAfterRecoveryCheck('w1',
              recoveryCheckAddress: legacyEoa),
          isFalse);
      expect(settings.walletById('w1')!.evmDerivationVersion,
          EvmDerivationVersion.standardBip39);
    });

    test('refuses passkey and hardware wallets', () async {
      for (final wallet in [
        WalletConfig(
            id: 'w1',
            name: 'Passkey',
            isPasskey: true,
            evmFormatCheckPending: true,
            evmDerivationVersion: EvmDerivationVersion.standardBip39),
        WalletConfig(
            id: 'w1',
            name: 'Ledger',
            isHardware: true,
            evmFormatCheckPending: true,
            evmDerivationVersion: EvmDerivationVersion.standardBip39),
      ]) {
        final settings = SettingsModel(_settings([wallet]));
        expect(
            await settings.adoptLegacyEvmAfterRecoveryCheck('w1',
                recoveryCheckAddress: legacyEoa),
            isFalse);
      }
    });

    test('the pending flag survives a round trip and defaults to false', () {
      final pending = WalletConfig(
          id: 'w1', name: 'Spending', evmFormatCheckPending: true);
      expect(WalletConfig.fromMap(pending.toMap()).evmFormatCheckPending,
          isTrue);
      expect(
          WalletConfig.fromMap({'id': 'w2', 'name': 'Old'})
              .evmFormatCheckPending,
          isFalse);
      expect(pending.copyWith(name: 'Renamed').evmFormatCheckPending, isTrue);
    });
  });
}
