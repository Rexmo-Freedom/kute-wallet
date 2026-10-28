// After a seed restore, Predictions used to read "—" for the whole first
// session: the trading notifier never rebuilt when the spending wallet
// changed, and a refresh that started before the account start
// authenticated wrote the old (unauthenticated, address-less) state back
// over it. These cover the fix:
//   * a restore with nothing cached whose first address lookup fails heals
//     on the next poll: authenticated, with a balance (never "—");
//   * a refresh read never takes back the address or the authentication;
//   * the notifier rebuilds on the spending wallet's identity (created,
//     restored, switched, removed, EVM format changed);
//   * an identity change mid-refresh drops the stale read;
//   * a pending EVM format check sets nothing up until it settles, and its
//     retry is scheduled in the same session;
//   * the stuck state is recorded (`polymarket_account_start_unauthenticated`).
// Network fakes only: nothing is signed for or sent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/evm_format_settle.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/polymarket_usdc_cache_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _phrase =
    'panel custom call awesome sick ready hamster wool patch client reduce clay';
const _otherPhrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const _beaconWord = '2222222222222222222222222222222222222222';
const _beacon = '0x$_beaconWord';
const _otherDeposit = '0x3333333333333333333333333333333333333333';

String _word(BigInt value) => '0x${value.toRadixString(16).padLeft(64, '0')}';

/// The relayer, Polygon RPC, the Data API and the CLOB for one wallet on
/// the factory's current variant holding 12.5 pUSD.
class _Net {
  /// Polygon answers nothing (every JSON-RPC call fails).
  bool polygonDown = false;

  /// While set, Polygon and the Data API wait for it (a slow read).
  Completer<void>? gate;

  final calls = <String>[];
  var deployChecks = 0;

  Future<http.Response> handle(http.Request request) async {
    final url = request.url;
    if (url.host == 'relayer-v2.polymarket.com') {
      calls.add('relayer:${request.method}:${url.path}');
      if (request.method == 'GET' && url.path == '/deployed') {
        return http.Response(jsonEncode({'deployed': false}), 200);
      }
      return http.Response('no', 500);
    }
    if (url.host == 'clob.polymarket.com') {
      calls.add('clob:${url.path}');
      return http.Response('not found', 404);
    }
    final hold = gate;
    if (hold != null) await hold.future;
    if (url.host == 'data-api.polymarket.com') {
      calls.add('data:${url.path}');
      return http.Response('[]', 404);
    }
    if (request.method == 'POST' && request.body.contains('jsonrpc')) {
      if (polygonDown) {
        calls.add('rpc:down');
        return http.Response('down', 503);
      }
      final decoded = jsonDecode(request.body);
      if (decoded is List) {
        return http.Response(
            jsonEncode([
              for (final rpc in decoded) _rpc(rpc as Map<String, dynamic>),
            ]),
            200);
      }
      return http.Response(
          jsonEncode(_rpc(decoded as Map<String, dynamic>)), 200);
    }
    return http.Response('unexpected ${request.method} $url', 500);
  }

  Map<String, Object?> _rpc(Map<String, dynamic> rpc) {
    final method = rpc['method'] as String;
    calls.add(method);
    Object? result;
    if (method == 'eth_chainId') {
      result = '0x89';
    } else if (method == 'eth_getCode') {
      final address = (rpc['params'][0] as String).toLowerCase();
      if (address == _beacon) deployChecks++;
      result = '0x';
    } else if (method == 'eth_call') {
      final call = rpc['params'][0] as Map;
      final to = (call['to'] as String).toLowerCase();
      final data = (call['data'] as String).toLowerCase();
      final selector = data.substring(2, 10);
      result = switch (selector) {
        '04f1d3c7' => '0x${'0' * 24}$_beaconWord', // predictWalletAddress
        '70a08231' => _word(to == PolymarketConstants.pusdAddress.toLowerCase()
            ? BigInt.from(12500000)
            : BigInt.zero), // balanceOf
        'dd62ed3e' => _word(BigInt.two.pow(255)), // allowance
        'e985e9c5' => _word(BigInt.one), // isApprovedForAll
        _ => '0x${'0' * 64}',
      };
    } else {
      result = '0x';
    }
    return {'jsonrpc': '2.0', 'id': rpc['id'] ?? 1, 'result': result};
  }
}

/// Settings the test can replace in one step, as a restore or a switch does.
class _Settings extends SettingsModel {
  _Settings(super.state);
  void put(Settings next) => state = next;
}

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: wallets.firstOrNull?.id,
      wallets: wallets,
    );

WalletConfig _wallet(String id,
        {bool restored = true,
        bool formatPending = false,
        EvmDerivationVersion version = EvmDerivationVersion.standardBip39}) =>
    WalletConfig(
      id: id,
      name: 'Spending Wallet',
      sparkEnabled: true,
      isRestore: restored,
      evmDerivationVersion: version,
      evmFormatCheckPending: formatPending,
    );

Future<T> _with<T>(_Net net, Future<T> Function() body) {
  SharedHttpClient.debugOverride = MockClient(net.handle);
  return http.runWithClient(body, () => MockClient(net.handle));
}

Future<void> _settle(_Net net, [int ms = 400]) =>
    _with(net, () => Future<void>.delayed(Duration(milliseconds: ms)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <(String, Map<String, Object>?)>[];
  var scheduled = 0;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pm_restore_rebuild');
    Hive.init(dir.path);
    for (final box in [
      'polymarket_suppressed_positions',
      'polymarket_order_submissions',
      'polymarket_optimistic_activity',
      'usdc_balance_history',
    ]) {
      await Hive.openBox<String>(box);
    }
  });

  setUp(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    FlutterSecureStorage.setMockInitialValues({
      'v2:wallet:spend.mnemonic': _phrase,
      'v2:wallet:other.mnemonic': _otherPhrase,
    });
    WalletIdentityService.debugBind(pubkey: null);
    AffiliateService.debugSessionToken = 'test-session';
    PolymarketAccountCache.debugReset();
    PolymarketAccountCache.memoryOnly = true;
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.polygonRpcTimeout =
        const Duration(milliseconds: 300);
    PolymarketOnboardingService.polygonRpcStagger =
        const Duration(milliseconds: 20);
    PolymarketOnboardingService.relayerResolveTimeout =
        const Duration(milliseconds: 200);
    PolymarketOnboardingService.loadHealthyRpcs = () async => null;
    PolymarketOnboardingService.persistHealthyRpcs = (_) async {};
    PolymarketTradingNotifier.liveNotifierWait =
        const Duration(milliseconds: 500);
    PolymarketTradingNotifier.healBackoffUnit = Duration.zero;
    scheduled = 0;
    EvmFormatSettle.debugScheduleOverride = (_) => scheduled++;
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    SharedHttpClient.debugOverride = null;
    TrackingService.debugTrackObserver = null;
    AffiliateService.debugSessionToken = null;
    EvmFormatSettle.debugScheduleOverride = null;
    PolymarketAccountCache.debugReset();
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.relayerResolveTimeout =
        const Duration(seconds: 4);
    PolymarketTradingNotifier.liveNotifierWait = const Duration(seconds: 20);
    PolymarketTradingNotifier.healBackoffUnit = const Duration(seconds: 5);
  });

  (ProviderContainer, _Settings) container(List<WalletConfig> wallets) {
    final settings = _Settings(_settings(wallets));
    final session =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => settings),
      sessionAuthProvider.overrideWith((ref) => session),
      sessionUnlockedProvider.overrideWith((ref) => true),
    ]);
    addTearDown(c.dispose);
    return (c, settings);
  }

  List<Map<String, Object>?> named(String name) => [
        for (final e in events)
          if (e.$1 == name) e.$2
      ];

  group('restore with nothing cached', () {
    test(
        'a first address lookup that fails heals on the next poll: '
        'authenticated, with a balance', () async {
      final net = _Net()..polygonDown = true;
      final (c, _) = container([_wallet('spend')]);
      final first =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(first.proxyWalletAddress, isNull);
      expect(first.balanceKnown, isFalse);
      // The account start ends: no address, no credentials.
      await _settle(net, 1500);
      final stuck = c.read(polymarketTradingProvider).valueOrNull!;
      expect(stuck.isAuthenticated, isFalse);
      expect(stuck.proxyWalletAddress, isNull);

      final unauth = named('polymarket_account_start_unauthenticated');
      expect(unauth, hasLength(1));
      expect(unauth.single?['stage'], 'account_start');
      expect(unauth.single?['restore'], isTrue);
      expect(unauth.single?['boot'], 'first');
      expect(
          unauth.single?.keys,
          everyElement(
              isIn(['stage', 'reason', 'restore', 'offline', 'boot'])));
      expect(unauth.single?.values.join(' '), isNot(contains('0x')));
      expect(named('polymarket_account_ready'), isEmpty,
          reason: 'not ready while unauthenticated');

      // Polygon answers again; one poll (the 30 s pipeline's refresh).
      net.polygonDown = false;
      await _with(
          net, () => c.read(polymarketTradingProvider.notifier).refresh());
      await _settle(net, 600);
      final healed = c.read(polymarketTradingProvider).valueOrNull!;
      expect(healed.isAuthenticated, isTrue);
      expect(healed.proxyWalletAddress?.toLowerCase(), _beacon);
      expect(healed.balanceKnown, isTrue,
          reason: 'the tile reads a figure, not —');
      expect(healed.usdcBalance, 12.5);

      expect(named('polymarket_balance_loaded').single?['source'], 'network');
      expect(named('polymarket_account_ready'), hasLength(1));
      expect(named('polymarket_account_start_unauthenticated'), hasLength(1));
      // The address found is kept for the next start.
      expect(PolymarketAccountCache.read('spend')?.depositAddress.toLowerCase(),
          _beacon);
    });

    test('a refresh while the lookup still fails changes nothing and retries',
        () async {
      final net = _Net()..polygonDown = true;
      final (c, _) = container([_wallet('spend')]);
      await _with(net, () => c.read(polymarketTradingProvider.future));
      await _settle(net, 1500);
      final before = net.calls.where((c) => c == 'rpc:down').length;
      await _with(
          net, () => c.read(polymarketTradingProvider.notifier).refresh());
      final after = c.read(polymarketTradingProvider).valueOrNull!;
      expect(after.proxyWalletAddress, isNull);
      expect(after.isAuthenticated, isFalse);
      expect(
          net.calls.where((c) => c == 'rpc:down').length, greaterThan(before),
          reason: 'the refresh looked the address up again');
    });
  });

  test('a build that could not read the phrase builds again on a refresh',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final net = _Net();
    final (c, _) = container([_wallet('spend', restored: false)]);
    final first =
        await _with(net, () => c.read(polymarketTradingProvider.future));
    expect(first.walletAddress, isNull);
    expect(first.error, isNotNull);
    expect(named('polymarket_account_start_unauthenticated').single?['stage'],
        isIn(['mnemonic', 'build']));

    // The phrase is readable again (restore secrets wrote it back).
    FlutterSecureStorage.setMockInitialValues(
        {'v2:wallet:spend.mnemonic': _phrase});
    await _with(
        net, () => c.read(polymarketTradingProvider.notifier).refresh());
    final next =
        await _with(net, () => c.read(polymarketTradingProvider.future));
    expect(next.walletAddress, isNotNull);
    expect(next.balanceKnown, isTrue);
    expect(named('polymarket_account_start_unauthenticated'), hasLength(1),
        reason: 'one stuck episode, one event');
  });

  group('mergePolymarketRefresh', () {
    const eoa = '0x1111111111111111111111111111111111111111';
    const live = PolymarketTradingState(
      isAuthenticated: true,
      walletAddress: eoa,
      proxyWalletAddress: _beacon,
      usdcBalance: 12.5,
      isPlacingOrder: true,
    );

    test('a read begun before authentication never takes it back', () {
      // Captured when the account was unauthenticated, read for the address.
      const read = PolymarketTradingState(
        walletAddress: eoa,
        proxyWalletAddress: _beacon,
        usdcBalance: 20,
      );
      final merged = mergePolymarketRefresh(live: live, read: read)!;
      expect(merged.isAuthenticated, isTrue);
      expect(merged.proxyWalletAddress, _beacon);
      expect(merged.usdcBalance, 20);
      expect(merged.isPlacingOrder, isTrue);
    });

    test('a read made without the address is dropped, never nulls it', () {
      const read = PolymarketTradingState(
          walletAddress: eoa, balanceKnown: false, usdcBalance: 0);
      expect(mergePolymarketRefresh(live: live, read: read), isNull);
    });

    test('a read for another deposit address or owner is dropped', () {
      expect(
          mergePolymarketRefresh(
              live: live,
              read: const PolymarketTradingState(
                  walletAddress: eoa, proxyWalletAddress: _otherDeposit)),
          isNull);
      expect(
          mergePolymarketRefresh(
              live: live,
              read: const PolymarketTradingState(
                  walletAddress: _otherDeposit, proxyWalletAddress: _beacon)),
          isNull);
    });

    test('a balance that could not be read keeps the last one', () {
      final merged = mergePolymarketRefresh(
          live: live,
          read: const PolymarketTradingState(
              walletAddress: eoa,
              proxyWalletAddress: _beacon,
              balanceKnown: false))!;
      expect(merged.usdcBalance, 12.5);
      expect(merged.balanceKnown, isTrue);
    });

    test('a read that found the address fills it in', () {
      const noAddress = PolymarketTradingState(walletAddress: eoa);
      final merged = mergePolymarketRefresh(
          live: noAddress,
          read: const PolymarketTradingState(
              walletAddress: eoa, proxyWalletAddress: _beacon))!;
      expect(merged.proxyWalletAddress, _beacon);
    });
  });

  group('identity', () {
    test('rebuilds on create, restore, format change, switch and removal',
        () async {
      final net = _Net();
      final (c, settings) = container(const []);
      Future<PolymarketTradingState> read() =>
          _with(net, () => c.read(polymarketTradingProvider.future));

      final none = await read();
      expect(none.walletAddress, isNull);
      expect(none.balanceKnown, isFalse);

      // Created on this device: its EOA, $0.00 with no network.
      settings.put(_settings([_wallet('spend', restored: false)]));
      final created = await read();
      final standardEoa = created.walletAddress;
      expect(standardEoa, isNotNull);

      // Its EVM format changes (a recovered wallet moving to legacy).
      settings.put(_settings([
        _wallet('spend',
            restored: false, version: EvmDerivationVersion.legacySha256),
      ]));
      final legacy = await read();
      expect(legacy.walletAddress, isNotNull);
      expect(legacy.walletAddress, isNot(standardEoa));

      // Switched to another spending wallet (restored from its phrase).
      settings.put(_settings([_wallet('other')]));
      final other = await read();
      expect(other.walletAddress, isNotNull);
      expect(other.walletAddress, isNot(standardEoa));
      expect(other.walletAddress, isNot(legacy.walletAddress));

      // Removed: no spending wallet, nothing derived.
      settings.put(_settings(const []));
      final removed = await read();
      expect(removed.walletAddress, isNull);
      expect(removed.balanceKnown, isFalse);
      expect(
          c.read(polymarketTradingProvider.notifier).signingWalletId, isNull);
    });

    test('a settings write that keeps the identity does not rebuild', () async {
      final net = _Net();
      final (c, settings) = container([_wallet('spend', restored: false)]);
      await _with(net, () => c.read(polymarketTradingProvider.future));
      var builds = 0;
      c.listen(polymarketTradingProvider, (prev, next) {
        if (next.isLoading) builds++;
      });
      settings.put(_settings([_wallet('spend', restored: false)])
          .copyWith(currency: 'EUR'));
      await _settle(net, 50);
      expect(builds, 0);
    });

    test('an identity change mid-refresh drops the stale read', () async {
      await PolymarketAccountCache.write(
          'spend',
          PolymarketAccountSnapshot(
            depositAddress: _beacon,
            legacyWallet: false,
            usdcBalance: 42,
            updatedAt: DateTime.utc(2026, 10, 1),
          ));
      await PolymarketAccountCache.write(
          'other',
          PolymarketAccountSnapshot(
            depositAddress: _otherDeposit,
            legacyWallet: false,
            usdcBalance: 7,
            updatedAt: DateTime.utc(2026, 10, 1),
          ));
      final net = _Net()..gate = Completer<void>();
      final (c, settings) = container([_wallet('spend')]);
      final first =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(first.usdcBalance, 42);

      // A refresh starts for the old account and waits on the network.
      final stale = _with(
          net, () => c.read(polymarketTradingProvider.notifier).refresh());
      await _settle(net, 50);

      // The spending wallet changes meanwhile.
      settings.put(_settings([_wallet('other')]));
      final next =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(next.proxyWalletAddress, _otherDeposit);

      // The old read lands (12.5 for the old address): dropped.
      net.gate!.complete();
      net.gate = null;
      await stale;
      final live = c.read(polymarketTradingProvider).valueOrNull!;
      expect(live.proxyWalletAddress, _otherDeposit);
      expect(live.walletAddress, next.walletAddress);
    });
  });

  group('EVM format pending', () {
    test(
        'nothing is deployed, approved or provisioned until it settles, and '
        'the retry is scheduled in the same session', () async {
      final net = _Net();
      final (c, settings) = container([_wallet('spend', formatPending: true)]);
      final first =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(scheduled, greaterThanOrEqualTo(1),
          reason: 'the format retry runs in this session');
      // The account is read: address and balance.
      expect(first.proxyWalletAddress?.toLowerCase(), _beacon);
      await _settle(net, 600);
      expect(net.deployChecks, 0, reason: 'no deployment check or deploy');
      expect(net.calls.where((c) => c.startsWith('relayer:POST')), isEmpty);
      expect(net.calls.where((c) => c.startsWith('clob:')), isEmpty,
          reason: 'no credentials created for an unsettled account');
      expect(
          named('polymarket_account_ready').single?['credentials'], 'deferred');

      // Every setup entry point waits.
      await expectLater(
          _with(net,
              () => c.read(polymarketTradingProvider.notifier).enableTrading()),
          throwsA(isA<PolymarketEvmFormatPendingException>()));
      await _with(
          net,
          () => provisionPolymarketAccount(
              mnemonic: _phrase,
              walletId: 'spend',
              evmDerivationVersion: EvmDerivationVersion.standardBip39,
              evmFormatPending: true));
      final deferred = named('polymarket_provisioning_outcome').last;
      expect(deferred?['outcome'], 'deferred');
      expect(deferred?['stage'], 'evm_format');
      expect(net.deployChecks, 0);

      // The check settles on the standard format: setup resumes.
      await _with(net, () async => settings.put(_settings([_wallet('spend')])));
      await _settle(net, 1200);
      expect(net.deployChecks, greaterThanOrEqualTo(1),
          reason: 'setup ran once the format settled');
      expect(net.calls.any((c) => c.startsWith('clob:')), isTrue);
    });

    test('a provisioning call made while pending sets nothing up', () async {
      final net = _Net();
      await _with(
          net,
          () => provisionPolymarketAccount(
              mnemonic: _phrase,
              walletId: 'spend',
              evmDerivationVersion: EvmDerivationVersion.standardBip39,
              evmFormatPending: true));
      expect(net.calls, isEmpty);
      final outcome = named('polymarket_provisioning_outcome').single;
      expect(outcome?['outcome'], 'deferred');
      expect(outcome?['stage'], 'evm_format');
    });
  });

  // A pull-to-refresh is "update everything" (refresh_everything_provider):
  // it gets an account out of the states a poll never could, the ones only
  // a restart used to fix, and never blanks what is on screen.
  group('pull to refresh', () {
    test(
        'a failed start a poll will not rebuild for 30 s (repro: only a '
        'restart showed it) is built again by a pull', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final net = _Net();
      final (c, _) = container([_wallet('spend')]);
      final first =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      final notifier = c.read(polymarketTradingProvider.notifier);
      expect(first.error, isNotNull, reason: 'the phrase could not be read');
      // A poll spends the self-rebuild while the phrase is still unreadable.
      await _with(net, notifier.refresh);
      final again =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(again.error, isNotNull);

      // The phrase is readable now (the keystore answered).
      FlutterSecureStorage.setMockInitialValues(
          {'v2:wallet:spend.mnemonic': _phrase});
      // The reproduction: a poll inside the 30 s spacing changes nothing,
      // Predictions keeps reading "—" ...
      await _with(net, notifier.refresh);
      final stuck =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(stuck.walletAddress, isNull);
      expect(stuck.balanceKnown, isFalse);
      // ... while a restart (a new process) shows the account at once.
      final (restart, _) = container([_wallet('spend')]);
      final cold = await _with(
          net, () => restart.read(polymarketTradingProvider.future));
      expect(cold.walletAddress, isNotNull);
      expect(cold.balanceKnown, isTrue);

      // The pull does what the restart did.
      await _with(net, notifier.pullRefresh);
      final pulled =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      expect(pulled.walletAddress, cold.walletAddress);
      expect(pulled.proxyWalletAddress?.toLowerCase(), _beacon);
      expect(pulled.balanceKnown, isTrue);
      expect(pulled.usdcBalance, 12.5);
      expect(pulled.error, isNull);
    });

    test(
        'credentials that failed in the start are asked for again by a '
        'pull, never by a poll', () async {
      final net = _Net();
      final (c, _) = container([_wallet('spend')]);
      await _with(net, () => c.read(polymarketTradingProvider.future));
      final notifier = c.read(polymarketTradingProvider.notifier);
      await _settle(net, 1500);
      final live = c.read(polymarketTradingProvider).valueOrNull!;
      expect(live.proxyWalletAddress?.toLowerCase(), _beacon);
      expect(notifier.backendService, isNull,
          reason: 'the CLOB refused: no credentials, open orders unknown');
      int auth() => net.calls.where((x) => x.startsWith('clob:/auth')).length;
      final asked = auth();
      expect(asked, greaterThan(0));

      await _with(net, notifier.refresh);
      await _settle(net, 200);
      expect(auth(), asked, reason: 'a poll never asks again (the gap)');

      await _with(net, notifier.pullRefresh);
      await _settle(net, 600);
      expect(auth(), greaterThan(asked),
          reason: 'the pull ran the rest of the account start again');
    });

    test('a pull on a working account blanks nothing while it reads',
        () async {
      final net = _Net();
      final (c, _) = container([_wallet('spend')]);
      await _with(net, () => c.read(polymarketTradingProvider.future));
      final notifier = c.read(polymarketTradingProvider.notifier);
      await _settle(net, 1500);
      final seen = <AsyncValue<PolymarketTradingState>>[];
      c.listen(polymarketTradingProvider, (_, next) => seen.add(next),
          fireImmediately: true);
      net.gate = Completer<void>();
      final pull = _with(net, notifier.pullRefresh);
      await _settle(net, 100);
      net.gate!.complete();
      net.gate = null;
      await pull;
      await _settle(net, 600);
      expect(seen, isNotEmpty);
      for (final s in seen) {
        final v = s.valueOrNull;
        expect(v, isNotNull, reason: 'never without figures');
        expect(v!.balanceKnown, isTrue, reason: 'never "—"');
        expect(v.usdcBalance, 12.5);
        expect(v.proxyWalletAddress?.toLowerCase(), _beacon);
        expect(v.isAuthenticated, isTrue);
      }
    });
  });

  // A Predictions balance that could not be read is unknown, never a
  // known $0.00: no server answering made the model hand back its cache
  // (0 on a fresh model), which the account showed and saved as $0.00.
  group('a balance no server could read', () {
    test(
        'with nothing cached: unknown, nothing saved, the last figure on '
        'disk kept', () async {
      FlutterSecureStorage.setMockInitialValues({
        'v2:wallet:spend.mnemonic': _phrase,
        // An earlier start confirmed the deposit address.
        'pm_proxy_wallet_spend': _beacon,
      });
      final mirror = await Hive.openBox<double>('polymarket_usdc_cache');
      await mirror.put('usdc_balance', 9.75);
      final net = _Net()..polygonDown = true;
      final (c, _) = container([_wallet('spend')]);
      final first =
          await _with(net, () => c.read(polymarketTradingProvider.future));
      await _settle(net, 1500);
      final live = c.read(polymarketTradingProvider).valueOrNull!;
      expect(first.proxyWalletAddress?.toLowerCase(), _beacon);
      expect(live.balanceKnown, isFalse, reason: 'unknown, not \$0.00');
      expect(PolymarketAccountCache.read('spend'), isNull,
          reason: 'an unread balance is never saved');
      expect(named('polymarket_balance_loaded'), isEmpty);
      // The balance shown is the last one read, and the disk keeps it.
      expect(c.read(polymarketBalanceProvider), 9.75);
      expect(mirror.get('usdc_balance'), 9.75);
      await mirror.close();
    });

    test('with a cached balance: the cached figure stays, never replaced by 0',
        () async {
      await PolymarketAccountCache.write(
          'spend',
          PolymarketAccountSnapshot(
            depositAddress: _beacon,
            legacyWallet: false,
            usdcBalance: 42,
            updatedAt: DateTime.utc(2026, 10, 1),
          ));
      final net = _Net()..polygonDown = true;
      final (c, _) = container([_wallet('spend')]);
      await _with(net, () => c.read(polymarketTradingProvider.future));
      final notifier = c.read(polymarketTradingProvider.notifier);
      await _settle(net, 1500);
      await _with(net, notifier.refresh);
      final live = c.read(polymarketTradingProvider).valueOrNull!;
      expect(live.balanceKnown, isTrue);
      expect(live.usdcBalance, 42);
      expect(PolymarketAccountCache.read('spend')?.usdcBalance, 42);
    });
  });
}
