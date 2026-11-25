// "Advanced" on a trade ticket answers to `trading.advanced`. While the
// policy withholds it, or no policy can be read, the entry stays visible
// and a tap opens the shared unavailable sheet instead of the Advanced
// page. Allowed, the page opens as before.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy(this.decisionFor);
  final CapabilityDecision Function(String id) decisionFor;
  @override
  CapabilityDecision decision(String id) => decisionFor(id);
}

Future<bool?> _tapAdvanced(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  bool? offered;
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        // The shell bar over the page (kute_bar_test_support.dart): the
        // sheet's one button is the bar.
        builder: withKuteShellBar,
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  offered = advancedTradingOffered(context, policy),
              child: const Text('Advanced'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Advanced'));
  await tester.pumpAndSettle();
  return offered;
}

/// The sheet's "Got it": the bar as the sheet's primary button.
final Finder _gotIt = kuteBarPrimaryWithText('Got it');

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('allowed: the page may open, no sheet', (tester) async {
    final offered = await _tapAdvanced(
        tester, _Policy((_) => const CapabilityDecision(allowed: true)));
    expect(offered, isTrue);
    expect(_gotIt, findsNothing);
  });

  testWidgets('withheld: the sheet with the policy reason, nothing opens',
      (tester) async {
    final offered = await _tapAdvanced(
        tester,
        _Policy((_) =>
            const CapabilityDecision(allowed: false, reason: 'disabled')));
    expect(offered, isFalse);
    expect(_gotIt, findsOneWidget);
    expect(find.text('This feature is currently unavailable in Kute.'),
        findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
  });

  testWidgets('region block: the region title and copy', (tester) async {
    final offered = await _tapAdvanced(
        tester,
        _Policy((_) => const CapabilityDecision(
            allowed: false, reason: 'country_blocked')));
    expect(offered, isFalse);
    // A region block's one button asks again: "Check connection".
    expect(_gotIt, findsNothing);
    expect(kuteBarPrimaryWithText('Check connection'), findsOneWidget);
    expect(find.text('Check connection'), findsOneWidget);
    expect(find.text('Not available in your region'), findsOneWidget);
  });

  testWidgets('coming soon reads as withheld', (tester) async {
    final offered = await _tapAdvanced(
        tester,
        _Policy((_) =>
            const CapabilityDecision(allowed: true, comingSoon: true)));
    expect(offered, isFalse);
    expect(_gotIt, findsOneWidget);
  });

  test('every Advanced entry asks the gate before it opens', () {
    for (final path in [
      'lib/screens/polymarket/components/bet_slip_sheet.dart',
      'lib/screens/polymarket/components/sell_sheet.dart',
      'lib/screens/hyperliquid/components/order_slip_sheet.dart',
      'lib/screens/hyperliquid/components/close_position_sheet.dart',
      'lib/screens/ledger/polymarket/ledger_sell_sheet.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf('Future<void> _openAdvanced() async {');
      expect(start, isNonNegative, reason: path);
      final gate = source.indexOf('advancedTradingOffered(', start);
      final push = source.indexOf('.push', start);
      expect(gate, isNonNegative, reason: path);
      expect(gate, lessThan(push), reason: '$path checks before it pushes');
    }
  });
}
