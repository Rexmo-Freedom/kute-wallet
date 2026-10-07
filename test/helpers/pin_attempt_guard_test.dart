import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/theme/app_theme.dart';

import '../services/support/fake_secret_store.dart';

/// Compares PINs without PBKDF2 so widget tests stay in fake time; the
/// counters still go through the fake keychain.
class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeKeychain keychain;
  late AuthModel auth;
  late DateTime now;
  late PinAttemptGuard guard;

  setUp(() {
    keychain = FakeKeychain();
    auth = AuthModel(store: keychain.local, syncedStore: keychain.synced);
    now = DateTime(2026, 9, 15, 12);
    guard = PinAttemptGuard(auth, now: () => now);
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
  });

  tearDown(SecretStores.debugReset);

  bool wiped() => keychain.mutations.any((m) => m.op == 'deleteAllLocalOnly');

  group('lock screen', () {
    test('keeps the escalation and wipes after the sixth wrong PIN', () async {
      final outcomes = [
        for (var i = 0; i < 6; i++)
          await guard.recordFailure(surface: PinSurface.lockScreen),
      ];
      expect(outcomes.map((o) => o.attempts), [1, 2, 3, 4, 5, 6]);
      expect(outcomes.map((o) => o.lockout.inSeconds), [0, 0, 30, 60, 300, 0]);
      expect(outcomes.map((o) => o.action), [
        ...List.filled(5, PinFailureAction.retry),
        PinFailureAction.wipe,
      ]);
      expect(keychain.peek('failed_pin_attempts'), '6');
      expect(wiped(), isFalse, reason: 'the caller performs the wipe');
    });

    test('without wipe it stops at five and stays on screen', () async {
      late PinFailureOutcome last;
      for (var i = 0; i < 8; i++) {
        last = await guard.recordFailure(
            surface: PinSurface.lockScreen, allowWipe: false);
        expect(last.action, PinFailureAction.retry);
      }
      expect(last.attempts, 5);
      expect(last.lockout, const Duration(seconds: 300));
      expect(keychain.peek('failed_pin_attempts'), '5');
    });
  });

  group('sheet', () {
    test('locks the app at five with the 300 s lockout and never wipes',
        () async {
      final outcomes = [
        for (var i = 0; i < 7; i++)
          await guard.recordFailure(surface: PinSurface.sheet),
      ];
      expect(outcomes.map((o) => o.attempts), [1, 2, 3, 4, 5, 5, 5]);
      expect(outcomes.map((o) => o.action), [
        ...List.filled(4, PinFailureAction.retry),
        ...List.filled(3, PinFailureAction.lockApp),
      ]);
      expect(outcomes.last.lockout, const Duration(seconds: 300));
      expect(outcomes.any((o) => o.action == PinFailureAction.wipe), isFalse);
      expect(keychain.peek('failed_pin_attempts'), '5');
      expect(await guard.lockoutRemaining(), const Duration(seconds: 300));
    });

    test('the next wrong PIN on the lock screen after a sheet lockout wipes',
        () async {
      for (var i = 0; i < 5; i++) {
        await guard.recordFailure(surface: PinSurface.sheet);
      }
      final next = await guard.recordFailure(surface: PinSurface.lockScreen);
      expect(next.action, PinFailureAction.wipe);
    });
  });

  test('success clears the counter and the lockout', () async {
    for (var i = 0; i < 3; i++) {
      await guard.recordFailure(surface: PinSurface.sheet);
    }
    expect(await guard.lockoutRemaining(), const Duration(seconds: 30));
    await guard.recordSuccess();
    expect(await guard.attempts(), 0);
    expect(await guard.lockoutRemaining(), Duration.zero);
  });

  test('the lockout counts down with the clock', () async {
    for (var i = 0; i < 4; i++) {
      await guard.recordFailure(surface: PinSurface.lockScreen);
    }
    now = now.add(const Duration(seconds: 45));
    expect(await guard.lockoutRemaining(), const Duration(seconds: 15));
    now = now.add(const Duration(seconds: 30));
    expect(await guard.lockoutRemaining(), Duration.zero);
  });

  test('an unreadable counter throws and counts nothing', () async {
    keychain.failRead('local', PlatformException(code: 'x', details: -25308),
        key: 'failed_pin_attempts');
    await expectLater(guard.recordFailure(surface: PinSurface.lockScreen),
        throwsA(isA<PlatformException>()));
    expect(keychain.mutations, isEmpty);
  });

  group('checkPin', () {
    test('no PIN material and unreadable storage are not mismatches', () async {
      expect(await auth.checkPin('111111'), PinCheck.noPinMaterial);
      keychain.failRead('local', PlatformException(code: 'x', details: -25308),
          key: 'pin_hash');
      expect(await auth.checkPin('111111'), PinCheck.unavailable);
    });

    test('verifies pin_hash', () async {
      keychain.seed('pin_hash', PinHashHelper.hashPin('111111'));
      expect(await auth.checkPin('111111'), PinCheck.match);
      expect(await auth.checkPin('222222'), PinCheck.mismatch);
    });

    test('a matching legacy plaintext pin is upgraded to pin_hash', () async {
      keychain.seed('pin', '111111');
      expect(await auth.checkPin('222222'), PinCheck.mismatch);
      expect(await auth.checkPin('111111'), PinCheck.match);
      expect(keychain.peek('pin'), isNull);
      expect(keychain.peek('pin_hash'), isNotNull);
    });
  });

  group('PinGateSheet', () {
    setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

    Future<ProviderContainer> pumpSheet(
      WidgetTester tester, {
      required VoidCallback onVerified,
      required VoidCallback onCancelled,
    }) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [
        authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: PinGateSheet(
                title: 'Confirm',
                analyticsSurface: 'step_up',
                onVerified: onVerified,
                onCancelled: onCancelled,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> typePin(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
    }

    testWidgets('at the threshold locks the app, closes and never wipes',
        (tester) async {
      keychain.seed('failed_pin_attempts', '4');
      var cancelled = 0;
      final container = await pumpSheet(tester,
          onVerified: () => fail('must not verify'),
          onCancelled: () => cancelled++);

      await typePin(tester, '222222');

      expect(container.read(appLockedProvider), isTrue);
      expect(container.read(pinSheetLockedProvider), isTrue);
      expect(cancelled, 1);
      expect(keychain.peek('failed_pin_attempts'), '5');
      expect(wiped(), isFalse);
      expect(
          keychain.mutations.where((m) => m.op.startsWith('delete')), isEmpty);
    });

    testWidgets('a wrong PIN below the threshold counts and keeps the sheet',
        (tester) async {
      var cancelled = 0;
      final container = await pumpSheet(tester,
          onVerified: () => fail('must not verify'),
          onCancelled: () => cancelled++);

      await typePin(tester, '222222');

      expect(keychain.peek('failed_pin_attempts'), '1');
      expect(container.read(appLockedProvider), isFalse);
      expect(cancelled, 0);
    });

    testWidgets('the right PIN clears the counter and sets the session',
        (tester) async {
      keychain.seed('failed_pin_attempts', '2');
      var verified = 0;
      final container = await pumpSheet(tester,
          onVerified: () => verified++,
          onCancelled: () => fail('must not cancel'));

      await typePin(tester, '111111');

      expect(verified, 1);
      expect(keychain.peek('failed_pin_attempts'), isNull);
      expect(container.read(sessionAuthProvider)?.method, UnlockMethod.pin);
      expect(container.read(sessionUnlockedProvider), isTrue);
      expect(container.read(typedPinProvider), isNull,
          reason: 'no stored wallet needs the PIN');
    });
  });
}
