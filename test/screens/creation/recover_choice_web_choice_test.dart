// The web's recovery screen (founder, 26 November 2026: "keep the passkey;
// just on recovery allow for choosing the different options"): no passkey
// ceremony runs before a tap; the passkey pill opens the browser's sheet
// from its tap, the phrase choice leads to the phrase, and a cancelled
// sheet returns to both choices. (The web's no-auto-lookup is the
// `autoLookup: false` seam here: the VM is never the web.)

import 'dart:async';
import 'dart:io';

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
import 'package:kute/services/passkey_home.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../services/support/fake_secret_store.dart';

class _Client implements PasskeyClient {
  final requests = <SignInRequest>[];

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    requests.add(request);
    throw PasskeyError.prf(PrfProviderError.userCancelled());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDir;
  late _Client kute;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('recover_web');
    Hive.init(hiveDir.path);
    kute = _Client();
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, kute);
  });

  tearDown(() async {
    PasskeyService.debugSetHomeClient(PasskeyHome.kute, null);
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final never = Completer<settings_model.Settings>();
    await tester.pumpWidget(ProviderScope(
      overrides: [initialSettingsProvider.overrideWith((ref) => never.future)],
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
          home: const RecoverChoiceScreen(
              passkeyHomes: [PasskeyHome.kute], autoLookup: false),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('no ceremony before a tap; cancel returns to both choices',
      (tester) async {
    await pump(tester);
    expect(kute.requests, isEmpty);
    final pill = find.text('Use your Google account');
    final phrase = find.text('Use your recovery phrase');
    expect(pill, findsOneWidget);
    expect(phrase, findsOneWidget);

    await tester.tap(pill);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // One discovery sign-in, from the tap. (On the web it is the
    // browser's ordinary sheet: `preferImmediatelyAvailable` is null there,
    // by kIsWeb, which the VM is not.)
    expect(kute.requests, hasLength(1));
    expect(kute.requests.single.label, isNull);
    // Cancelled: both choices are still there, nothing retried.
    expect(find.text('Use your Google account'), findsOneWidget);
    expect(find.text('Use your recovery phrase'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(kute.requests, hasLength(1));
  });
}
