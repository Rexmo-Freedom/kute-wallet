// A fresh-install passkey restore looks in Breez's RP first, then Kute's
// (quietly), and offers the wallets of whichever home has any, each
// re-derived on its own home and pinned to that home's credential.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/recover_choice.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
final breezCred = Uint8List.fromList([4, 5, 6]);
final kuteCred = Uint8List.fromList([7, 8, 9]);

/// One home's client. Discovery (`label == null`) answers [published] or
/// throws [discoveryError]; a labelled confirmation is cancelled so the
/// test stops right after the flow chose a home.
class _Client implements PasskeyClient {
  _Client(this.name, this.log, this.credential,
      {this.published = const [], this.discoveryError});

  final String name;
  final List<String> log;
  final Uint8List credential;
  final List<String> published;
  final Object? discoveryError;
  final requests = <SignInRequest>[];

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    log.add('$name:${request.label ?? 'discover'}');
    if (request.label != null) {
      throw PasskeyError.prf(PrfProviderError.userCancelled());
    }
    if (discoveryError != null) throw discoveryError!;
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: 'Default',
      ),
      labels: published,
      credential: PasskeyCredential(credentialId: credential),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _notFound =
    PasskeyError.prf(PrfProviderError.credentialNotFound('none on device'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late List<(String, Map<String, Object>?)> events;
  late List<String> log;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('recover_homes');
    Hive.init(hiveDir.path);
    events = [];
    log = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester,
      {List<PasskeyHome>? homes}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final never = Completer<settings_model.Settings>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWith((ref) => never.future),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: withKuteShellBar,
          home: RecoverChoiceScreen(passkeyHomes: homes),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void install(_Client breez, _Client kute) {
    PasskeyService.debugSetClient(breez);
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, kute);
  }

  testWidgets('both homes are asked, Breez first, and both lists are offered',
      (tester) async {
    final breez =
        _Client('breez', log, breezCred, published: ['Daily · 1700000000000']);
    final kute =
        _Client('kute', log, kuteCred, published: ['Savings · 1710000000000']);
    install(breez, kute);

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(log, ['breez:discover', 'kute:discover']);
    // Breez's discovery is the call it always was; Kute's asks quietly.
    expect(breez.requests.single.preferImmediatelyAvailableCredentials, isNull);
    expect(kute.requests.single.preferImmediatelyAvailableCredentials, isTrue);
    expect(find.text('Pick a wallet to restore'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    // One prompt event for the lookup, as before.
    expect(events.where((e) => e.$1 == 'passkey_restore_prompt_shown'),
        hasLength(1));

    // The Kute wallet re-derives on Kute's home, pinned to its credential.
    await tester.tap(find.text('Savings'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(log.last, 'kute:Savings · 1710000000000');
    expect(kute.requests.last.allowCredentials, [kuteCred]);
    expect(breez.requests, hasLength(1));
    // Nothing persisted by a cancelled confirmation; no Breez key touched.
    expect(keychain.keys(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Breez wallet re-derives on Breez\'s home', (tester) async {
    final breez =
        _Client('breez', log, breezCred, published: ['Daily · 1700000000000']);
    final kute =
        _Client('kute', log, kuteCred, published: ['Savings · 1710000000000']);
    install(breez, kute);

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Daily'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(log.last, 'breez:Daily · 1700000000000');
    expect(breez.requests.last.allowCredentials, [breezCred]);
    expect(kute.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('only a Kute passkey: its single wallet restores on Kute',
      (tester) async {
    final breez = _Client('breez', log, breezCred, discoveryError: _notFound);
    final kute = _Client('kute', log, kuteCred,
        published: ['Spending Wallet · 1720000000000']);
    install(breez, kute);

    await pumpScreen(tester);

    expect(log, [
      'breez:discover',
      'kute:discover',
      'kute:Spending Wallet · 1720000000000',
    ]);
    expect(kute.requests.last.allowCredentials, [kuteCred]);
    expect(find.text('Pick a wallet to restore'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('only a Breez passkey: restored on Breez as before',
      (tester) async {
    final breez = _Client('breez', log, breezCred,
        published: ['Spending Wallet · 1700000000000']);
    final kute = _Client('kute', log, kuteCred, discoveryError: _notFound);
    install(breez, kute);

    await pumpScreen(tester);

    expect(log, [
      'breez:discover',
      'kute:discover',
      'breez:Spending Wallet · 1700000000000',
    ]);
    expect(breez.requests.last.allowCredentials, [breezCred]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a dismissed Breez sheet stops the lookup: Kute is not asked',
      (tester) async {
    final breez = _Client('breez', log, breezCred,
        discoveryError: PasskeyError.prf(PrfProviderError.userCancelled()));
    final kute =
        _Client('kute', log, kuteCred, published: ['Savings · 1710000000000']);
    install(breez, kute);

    await pumpScreen(tester);

    expect(log, ['breez:discover']);
    expect(events.where((e) => e.$1 == 'passkey_restore_cancelled').single.$2,
        {'stage': 'lookup'});
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('nothing on either home goes on to the legacy probe',
      (tester) async {
    final breez = _Client('breez', log, breezCred);
    final kute = _Client('kute', log, kuteCred, discoveryError: _notFound);
    install(breez, kute);

    await pumpScreen(tester);

    expect(log, ['breez:discover', 'kute:discover']);
    expect(find.text('Pick a wallet to restore'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the web order asks Kute\'s home alone', (tester) async {
    final breez =
        _Client('breez', log, breezCred, published: ['Daily · 1700000000000']);
    final kute =
        _Client('kute', log, kuteCred, published: ['Savings · 1710000000000']);
    install(breez, kute);

    await pumpScreen(tester, homes: PasskeyHomes.restoreOrder(web: true));

    expect(log.first, 'kute:discover');
    expect(breez.requests, isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });
}
