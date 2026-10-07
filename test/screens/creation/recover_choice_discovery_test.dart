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

import '../../services/support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
final credential = Uint8List.fromList([4, 5, 6]);

/// Discovery (`label == null`) answers with [published]. The labelled
/// confirmation is cancelled, so these tests stop right after the flow
/// decided what to do with the discovered wallets.
class _Client implements PasskeyClient {
  _Client(this.published);

  final List<String> published;
  final requests = <SignInRequest>[];
  Completer<void>? confirmGate;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    if (request.label != null) {
      await confirmGate?.future;
      throw StateError('user cancelled');
    }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('recover_choice');
    Hive.init(hiveDir.path);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Settings stay loading: the provider falls back to its defaults
    // (no wallets yet, as on a fresh device).
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
          home: const RecoverChoiceScreen(),
        ),
      ),
    ));
    // The screen runs the discovery on its first frame.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<String> steps() => [
        for (final (e, p) in events)
          if (e == 'restore_step') '${p!['step']}/${p['trigger'] ?? ''}',
      ];

  void expectNoIdentifiersInAnalytics(List<String> labels) {
    for (final (_, params) in events) {
      for (final value in (params ?? const {}).values) {
        for (final label in labels) {
          expect('$value', isNot(contains(label)));
        }
        expect('$value', isNot(contains('040506')));
      }
    }
  }

  testWidgets('one discovered wallet restores without a picker', (tester) async {
    const label = 'Spending Wallet · 1700000000000';
    final client = _Client([label]);
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);

    expect(find.text('Restore this wallet?'), findsNothing);
    expect(client.requests, hasLength(2));
    expect(client.requests.first.label, isNull);
    expect(client.requests.last.label, label);
    // Pinned to the credential the discovery resolved.
    expect(client.requests.last.allowCredentials, [credential]);
    expect(steps(), ['passkey_lookup/auto', 'passkey_confirm/auto']);
    expect(events.map((e) => e.$1),
        containsAllInOrder(['passkey_restore_prompt_shown', 'restore_step']));
    expect(
        events.where((e) => e.$1 == 'passkey_restore_cancelled').single.$2,
        {'stage': 'restore'});
    // A cancelled confirmation stops: no retry, nothing persisted.
    expect(keychain.keys(), isEmpty);
    expectNoIdentifiersInAnalytics([label]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the screen names the wallet the confirmation is for',
      (tester) async {
    final client = _Client(['Holiday · 1700000000000'])
      ..confirmGate = Completer<void>();
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);

    expect(find.text('Confirm to restore Holiday.'), findsOneWidget);
    expect(find.text('Choose how you saved access to your account.'),
        findsNothing);

    client.confirmGate!.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Choose how you saved access to your account.'),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('several discovered wallets open the picker first',
      (tester) async {
    const a = 'Daily · 1700000000000';
    const b = 'Savings · 1710000000000';
    final client = _Client([a, b]);
    PasskeyService.debugSetClient(client);

    await pumpScreen(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Pick a wallet to restore'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(client.requests, hasLength(1));
    expect(steps(), ['passkey_lookup/auto', 'passkey_pick/']);

    await tester.tap(find.text('Savings'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(client.requests, hasLength(2));
    expect(client.requests.last.label, b);
    expect(client.requests.last.allowCredentials, [credential]);
    expect(steps(),
        ['passkey_lookup/auto', 'passkey_pick/', 'passkey_confirm/tap']);
    expectNoIdentifiersInAnalytics([a, b]);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('no discovered wallet falls back to the legacy probe',
      (tester) async {
    final client = _Client(const []);
    PasskeyService.debugSetClient(client);
    // The legacy probe fails at once (no native PRF channel in tests), so
    // the flow ends on the lookup-failed message instead of a picker.
    await pumpScreen(tester);

    expect(client.requests, hasLength(1));
    expect(find.text('Pick a wallet to restore'), findsNothing);
    expect(find.text('Restore this wallet?'), findsNothing);
    expect(steps(), ['passkey_lookup/auto']);
    await tester.pump(const Duration(seconds: 5));
  });
}
