// The Predictions account start shows something at once and never puts
// the balance behind credentials:
//   * a wallet the device has seen shows its last figures immediately,
//     marked as refreshing;
//   * a wallet created on this device and never funded shows $0.00 with no
//     network at all;
//   * an existing wallet without a cache gets its address and balance
//     (Stage A, public reads) while the CLOB credentials (Stage B) are
//     still being created;
//   * wallet creation's provisioning, the home-screen start and the first
//     bet share one setup through the notifier's readiness.
// Network fakes only: nothing is signed for or sent.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:hive_ce/hive.dart';
import 'package:http/testing.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/polymarket_usdc_cache_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

const _phrase =
    'panel custom call awesome sick ready hamster wool patch client reduce clay';
const _beaconWord = '2222222222222222222222222222222222222222';
const _beacon = '0x$_beaconWord';

String _word(BigInt value) => '0x${value.toRadixString(16).padLeft(64, '0')}';

/// The relayer, Polygon RPC, the Data API and the CLOB for one wallet that
/// lives on the factory's current variant and holds 12.5 pUSD.
class _Net {
  _Net({this.hangEverything = false, this.hangClob = true});

  /// No request ever answers (a dead link).
  final bool hangEverything;

  /// The CLOB's credential endpoints never answer.
  final bool hangClob;
  final calls = <String>[];
  var deployChecks = 0;

  Future<http.Response> handle(http.Request request) async {
    if (hangEverything) return Completer<http.Response>().future;
    final url = request.url;
    if (url.host == 'relayer-v2.polymarket.com' && url.path == '/deployed') {
      calls.add('relayer');
      return http.Response(jsonEncode({'deployed': false}), 200);
    }
    if (url.host == 'clob.polymarket.com') {
      calls.add('clob:${url.path}');
      if (hangClob) return Completer<http.Response>().future;
      return http.Response('not found', 404);
    }
    if (url.host == 'data-api.polymarket.com') {
      calls.add('data:${url.path}');
      return http.Response('[]', 404);
    }
    if (request.method == 'POST' && request.body.contains('jsonrpc')) {
      // One call, or a JSON-RPC batch (the cash balance reads are one
      // batch over the shared client, answered entry by entry).
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
      result = address == _beacon ? '0x6080' : '0x';
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

Settings _settings({required bool restored}) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spend',
      wallets: [
        WalletConfig(
            id: 'spend',
            name: 'Spending Wallet',
            sparkEnabled: true,
            isRestore: restored),
      ],
    );

/// Runs [body] with every request answered by [net]: the one-off calls
/// through the zone's client, and the reads on the shared keep-alive
/// client (the cash balance batch) through its test override.
Future<T> _with<T>(_Net net, Future<T> Function() body) {
  SharedHttpClient.debugOverride = MockClient(net.handle);
  return http.runWithClient(body, () => MockClient(net.handle));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final events = <(String, Map<String, Object>?)>[];

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pm_account_start');
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
    FlutterSecureStorage.setMockInitialValues(
        {'v2:wallet:spend.mnemonic': _phrase});
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
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    SharedHttpClient.debugOverride = null;
    TrackingService.debugTrackObserver = null;
    AffiliateService.debugSessionToken = null;
    PolymarketAccountCache.debugReset();
    PolymarketOnboardingService.debugResetPolygonRpcs();
    PolymarketOnboardingService.relayerResolveTimeout =
        const Duration(seconds: 4);
    PolymarketTradingNotifier.liveNotifierWait = const Duration(seconds: 20);
  });

  ProviderContainer container({required bool restored}) {
    final session =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    final c = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => SettingsModel(_settings(restored: restored))),
      sessionAuthProvider.overrideWith((ref) => session),
      sessionUnlockedProvider.overrideWith((ref) => true),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Map<String, Object>? event(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2).firstOrNull;

  test(
      'an existing wallet gets its address and balance while the CLOB '
      'credentials are still being created', () async {
    final net = _Net();
    final c = container(restored: true);
    final first = await _with(
        net, () => c.read(polymarketTradingProvider.future));
    expect(first.balanceKnown, isTrue);
    expect(first.usdcBalance, 12.5);
    expect(first.proxyWalletAddress?.toLowerCase(), _beacon);
    expect(first.refreshing, isTrue, reason: 'Stage B still running');
    // Nothing from the CLOB was waited for: the balance came from public
    // reads only.
    expect(net.calls.where((c) => c.startsWith('clob:')), isEmpty);

    final loaded = event('polymarket_balance_loaded');
    expect(loaded?['source'], 'network');
    expect(loaded?['boot'], 'first');
    expect(loaded?.keys, containsAll(['ms_mnemonic', 'ms_derive', 'ms_resolve', 'ms_data']));
    expect(loaded?.values.join(' '), isNot(contains('0x')));

    // Stage B then asks the CLOB for credentials, in the background.
    await _with(net, () => Future<void>.delayed(const Duration(milliseconds: 200)));
    expect(net.calls.any((c) => c.startsWith('clob:')), isTrue);
    expect(c.read(polymarketTradingProvider).valueOrNull?.usdcBalance, 12.5);
  });

  test('a wallet created on this device shows \$0.00 with no network',
      () async {
    final net = _Net(hangEverything: true);
    final c = container(restored: false);
    final clock = Stopwatch()..start();
    final first = await _with(
        net, () => c.read(polymarketTradingProvider.future));
    expect(clock.elapsedMilliseconds, lessThan(1500));
    expect(first.balanceKnown, isTrue);
    expect(first.usdcBalance, 0);
    expect(first.refreshing, isTrue);
    expect(event('polymarket_balance_loaded')?['source'], 'new_wallet');
  });

  test(
      'a stored UUPS address is dropped but the wallet is never "new" '
      '(the re-check keeps the legacy lookup)', () async {
    // An upgrader from 2.1.1: no account cache yet, no loadable
    // credentials, only the UUPS address 2.1.1 kept in secure storage.
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: _phrase,
        version: EvmDerivationVersion.legacySha256,
        index: 0);
    final uups =
        PolymarketOnboardingService().deriveDepositWalletAddress(wallet.address);
    FlutterSecureStorage.setMockInitialValues({
      'v2:wallet:spend.mnemonic': _phrase,
      'pm_proxy_wallet_spend': uups,
    });
    final net = _Net(hangEverything: true);
    final c = container(restored: false);
    final first = await _with(
        net, () => c.read(polymarketTradingProvider.future));
    expect(event('polymarket_balance_loaded')?['source'], isNot('new_wallet'));
    expect(first.balanceKnown && first.usdcBalance == 0, isFalse);
  });

  test('a wallet the device has seen shows its last figures first', () async {
    await PolymarketAccountCache.write(
        'spend',
        PolymarketAccountSnapshot(
          depositAddress: _beacon,
          legacyWallet: false,
          usdcBalance: 42,
          updatedAt: DateTime.utc(2026, 10, 1),
        ));
    final net = _Net(hangEverything: true);
    final c = container(restored: true);
    final first = await _with(
        net, () => c.read(polymarketTradingProvider.future));
    expect(first.usdcBalance, 42);
    expect(first.proxyWalletAddress, _beacon);
    expect(first.balanceKnown, isTrue);
    expect(first.refreshing, isTrue);
    expect(event('polymarket_balance_loaded')?['source'], 'cache');
    expect(event('polymarket_balance_loaded')?['boot'], 'later');
    // The deposit sheet gets the address with no wait at all.
    expect(await c.read(polymarketTradingProvider.notifier).depositAddress(),
        _beacon);
  });

  test('the last figures read are kept for the next start', () async {
    final net = _Net();
    final c = container(restored: true);
    await _with(net, () => c.read(polymarketTradingProvider.future));
    await _with(net, () => Future<void>.delayed(const Duration(milliseconds: 200)));
    final kept = PolymarketAccountCache.read('spend');
    expect(kept?.usdcBalance, 12.5);
    expect(kept?.depositAddress.toLowerCase(), _beacon);
    expect(kept?.legacyWallet, isFalse);
  });

  test(
      'creation, the home-screen start and the first bet share one setup',
      () async {
    final net = _Net(hangClob: false);
    final c = container(restored: false);
    await _with(net, () async {
      // Wallet creation's provisioning, scheduled before home builds.
      final provisioning = provisionPolymarketAccount(
          mnemonic: _phrase,
          walletId: 'spend',
          evmDerivationVersion: EvmDerivationVersion.standardBip39);
      // The home screen starts the account.
      await c.read(polymarketTradingProvider.future);
      // The first bet asks for setup.
      final bet = c.read(polymarketTradingProvider.notifier).enableTrading();
      await Future.wait([provisioning, bet]);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(net.deployChecks, 1, reason: 'one setup for the three callers');
    expect(c.read(polymarketTradingProvider.notifier).tradingReady, isTrue);
    final outcome = event('polymarket_provisioning_outcome');
    expect(outcome?['outcome'], 'completed');
    expect(outcome?['path'], 'provider');
    expect(outcome?.keys, isNot(contains('wallet_id')));
  });
}
