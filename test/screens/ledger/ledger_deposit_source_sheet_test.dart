// The Ledger venue-deposit source sheet lists Cash App only while the
// runtime policy offers `onramp.cashapp`. Withheld, the row is not drawn
// at all (no disabled tile, no reason, no UNAVAILABLE pill), and the
// sheet follows a policy change while it is open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/ledger/funding/ledger_deposit_source_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A policy whose Cash App answer the test flips, notifying like the real
/// service does.
class _Policy extends ChangeNotifier implements RuntimeCapabilitiesService {
  _Policy({required this.cashApp});
  bool cashApp;

  void set(bool value) {
    cashApp = value;
    notifyListeners();
  }

  @override
  CapabilityDecision decision(String id) => id == 'onramp.cashapp' && !cashApp
      ? const CapabilityDecision(allowed: false, reason: 'disabled')
      : const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _open(WidgetTester tester, _Policy policy) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWith((ref) {
        policy.addListener(ref.notifyListeners);
        ref.onDispose(() => policy.removeListener(ref.notifyListeners));
        return policy;
      }),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showLedgerDepositSourceSheet(context, predictions: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Cash App offered: listed beside the Ledger bitcoin',
      (tester) async {
    await _open(tester, _Policy(cashApp: true));
    expect(find.text('Bitcoin'), findsWidgets);
    expect(find.text('Cash App'), findsOneWidget);
  });

  testWidgets('Cash App withheld: not drawn at all', (tester) async {
    await _open(tester, _Policy(cashApp: false));
    expect(find.text('Bitcoin'), findsWidgets);
    expect(find.text('Cash App'), findsNothing);
    expect(find.text('UNAVAILABLE'), findsNothing);
  });

  testWidgets('the open sheet follows the policy live', (tester) async {
    final policy = _Policy(cashApp: true);
    await _open(tester, policy);
    expect(find.text('Cash App'), findsOneWidget);
    policy.set(false);
    await tester.pumpAndSettle();
    expect(find.text('Cash App'), findsNothing);
    policy.set(true);
    await tester.pumpAndSettle();
    expect(find.text('Cash App'), findsOneWidget);
  });
}
