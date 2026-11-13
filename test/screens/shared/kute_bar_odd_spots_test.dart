// Spots where the floating Sal pill rendered oddly (founder, 4 November
// 2026: "some places the pill button appears in strange ways"), each held
// here: the bar over a surface that should have it away, or over the last
// rows of a tall sheet that could not scroll them clear.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/amount_unit_picker.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

final _navKey = GlobalKey<NavigatorState>();

/// The app's layering in miniature (as kute_shell_bar_test.dart): a root
/// navigator under the bar, the route observer on it, on a phone of
/// [size].
Future<ProviderContainer> _pump(WidgetTester tester,
    {Size size = const Size(375, 667), double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    aiEnabledProvider.overrideWith((_) async => true),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: _navKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Stack(children: [child!, const KuteShellBar()])),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// Whether the bar is up: shown and taking taps.
bool _up(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('kute-shell-bar-slide')));
  return slide.offset == Offset.zero;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    KuteBarRouteObserver.reset();
  });

  for (final (size, scale) in const [
    (Size(375, 667), 1.0),
    (Size(390, 844), 1.0),
    (Size(430, 932), 1.0),
    (Size(375, 667), 1.4),
  ]) {
    testWidgets(
        'the PIN gate (every step-up approval) never shows the pill: the '
        'bar is its Cancel, clear of its keypad (${size.width.toInt()} x '
        '${size.height.toInt()}, text x$scale)', (tester) async {
      await _pump(tester, size: size, textScale: scale);
      // ignore: unawaited_futures
      PinGateSheet.show(_navKey.currentContext!,
          title: 'Approve', onVerified: () {});
      await _settle(tester);
      expect(find.byType(PinGateSheet), findsOneWidget);
      // Short or tall, the bar is up as the sheet's one button: Cancel,
      // never the search pill, and the sheet draws no Cancel of its own.
      expect(_up(tester), isTrue);
      expect(find.byType(KuteSalPill), findsNothing);
      final bar = find.byKey(const ValueKey('kute-bar-primary-button'));
      expect(find.descendant(of: bar, matching: find.text('Cancel')),
          findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // The keypad's last row sits above the bar, every key tappable.
      final keypadBottom = tester
          .getRect(find.descendant(
              of: find.byType(PinGateSheet), matching: find.text('0')))
          .bottom;
      expect(keypadBottom, lessThanOrEqualTo(tester.getRect(bar).top));
      expect(find.text('0').hitTestable(), findsOneWidget);
      expect(bar.hitTestable(), findsOneWidget);
      await tester.tap(bar);
      await _settle(tester);
      expect(find.byType(PinGateSheet), findsNothing);
    });
  }

  // A tall sheet (past kuteBarShortSheetFraction) has the pill over its
  // foot: its scroll content ends with KuteSheetBarSpace, so the last row
  // scrolls clear of the pill and can be tapped. A short sheet has the
  // bar away, and gains no empty band.
  testWidgets(
      'a tall list sheet: the last row scrolls clear of the pill; a short '
      'one has the bar away and no extra room', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    final home = _navKey.currentContext!;
    // ignore: unawaited_futures
    showAppBottomSheet<void>(
      context: home,
      builder: (_) => AppBottomSheetContainer(
        maxHeight: 0.85,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AppBottomSheetHeader(title: 'Pick one'),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 56, child: Text('Row $i')),
              const KuteSheetBarSpace(),
            ]),
          ),
        ]),
      ),
    );
    await _settle(tester);
    expect(_up(tester), isTrue);
    await tester.drag(find.text('Row 10'), const Offset(0, -4000));
    await _settle(tester);
    expect(tester.getSize(find.byType(KuteSheetBarSpace)).height,
        greaterThan(60));
    final pillTop = tester.getRect(find.byType(KuteSalPill)).top;
    expect(tester.getRect(find.text('Row 39')).bottom,
        lessThanOrEqualTo(pillTop));
    expect(find.text('Row 39').hitTestable(), findsOneWidget);
    _navKey.currentState!.pop();
    await _settle(tester);

    // ignore: unawaited_futures
    showAppBottomSheet<void>(
      context: home,
      builder: (_) => AppBottomSheetContainer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const AppBottomSheetHeader(title: 'Short'),
          for (var i = 0; i < 3; i++)
            SizedBox(height: 56, child: Text('Item $i')),
          const KuteSheetBarSpace(),
        ]),
      ),
    );
    await _settle(tester);
    expect(_up(tester), isFalse);
    expect(tester.getSize(find.byType(KuteSheetBarSpace)).height, 0);
  });

  testWidgets(
      'the amount unit picker: its Cancel sits above the pill, never '
      'under it', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    // ignore: unawaited_futures
    showAmountUnitPicker(_navKey.currentContext!,
        selected: 'Sats',
        onSelected: (_) {},
        iconBuilder: (code, size) => SizedBox.square(dimension: size));
    await _settle(tester);
    final cancel = find.text('Cancel');
    expect(cancel, findsOneWidget);
    // Seven units make the sheet tall: the pill is over it.
    expect(_up(tester), isTrue);
    expect(tester.getRect(cancel).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(KuteSalPill)).top));
    expect(cancel.hitTestable(), findsOneWidget);
  });
}
