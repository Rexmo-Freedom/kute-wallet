import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/slip_form_body.dart';
import 'package:kute/theme/app_theme.dart';

const _message = "No one is buying this outcome anymore. It's trading at "
    "effectively \$0, so these shares can't be sold right now.";

Future<void> _pump(WidgetTester tester, ValueNotifier<bool> failed,
    TextEditingController amount,
    {Size size = const Size(430, 932), double extraFormHeight = 0}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final updates = Listenable.merge([failed, amount]);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * 0.92),
          child: AnimatedBuilder(
              animation: updates,
              builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          height: 80.h,
                          child: const Text('Bitcoin Up or Down')),
                      Flexible(
                          child: SlipFormBody(
                        expandForMessage: failed.value,
                        form: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                  height: 68.h,
                                  child: const Text('DOWN · 7.8 shares')),
                              SizedBox(height: 8.h),
                              const Text('Avg 64¢ · Now 1.5¢'),
                              SizedBox(height: 22.h),
                              BigAmountDisplay(
                                  prefix: '\$',
                                  amountText: amount.text,
                                  conversionLabel: '≈ 7.80 shares',
                                  availableLabel: 'Available \$0.12'),
                              SizedBox(height: 24.h),
                              SizedBox(
                                  height: 44.h,
                                  child: const Text('Estimated fee < \$0.01')),
                              SizedBox(height: 8.h),
                              PolySlipAdvancedRow(onTap: () {}),
                              SizedBox(height: extraFormHeight),
                              if (failed.value) ...[
                                SizedBox(height: 12.h),
                                const PolySlipNotice(
                                    title: 'Could not sell', message: _message),
                              ],
                              SizedBox(height: 12.h),
                            ],
                          ),
                        ),
                        input: AmountKeypad(
                            value: amount.text,
                            onChanged: (value) {
                              amount.text = value;
                              failed.value = false;
                            }),
                      )),
                      SizedBox(
                          key: const ValueKey('pinned-action'),
                          height: 72.h,
                          child: Center(
                              child: Text(failed.value ? 'Retry' : 'Sell'))),
                    ],
                  )),
        ),
      )),
    ),
  ));
  await tester.pump();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'a quiet compact ticket keeps its content height and pinned input',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
        child: const SlipFormBody(
          expandForMessage: false,
          form: SizedBox(height: 40),
          input: SizedBox(key: ValueKey('input'), height: 100),
        ),
      ),
    )));
    expect(tester.getSize(find.byType(SlipFormBody)).height, 140);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('input')),
            matching: find.byType(SingleChildScrollView)),
        findsNothing);
  });

  testWidgets(
      'sell failure grows the upper viewport and keeps the full notice above input',
      (tester) async {
    final failed = ValueNotifier(false);
    final amount = TextEditingController(text: '0.12');
    addTearDown(failed.dispose);
    addTearDown(amount.dispose);
    await _pump(tester, failed, amount);
    final viewport = find.byType(SingleChildScrollView);
    final before = tester.getSize(viewport).height;
    expect(
        find.ancestor(
            of: find.byType(AmountKeypad),
            matching: find.byType(SingleChildScrollView)),
        findsNothing);
    final actionBottom =
        tester.getRect(find.byKey(const ValueKey('pinned-action'))).bottom;
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    failed.value = true;
    await tester.pump();
    expect(tester.getSize(viewport).height, greaterThan(before + 100));
    expect(tester.getRect(find.byType(PolySlipNotice)).bottom,
        lessThanOrEqualTo(tester.getRect(viewport).bottom));
    expect(tester.state<ScrollableState>(find.byType(Scrollable)).position,
        same(position));
    expect(position.pixels, 0);
    expect(tester.getRect(find.byKey(const ValueKey('pinned-action'))).bottom,
        actionBottom);
    expect(find.text('Retry'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byType(AmountKeypad),
            matching: find.byType(SingleChildScrollView)),
        findsOneWidget);
    expect(amount.text, '0.12');

    // Input still works after the failure; it was reflowed, never removed.
    await tester.ensureVisible(find.byIcon(Icons.backspace_rounded));
    await tester.tap(find.byIcon(Icons.backspace_rounded));
    await tester.pump();
    expect(amount.text, '0.1');
    expect(failed.value, isFalse);
    expect(find.byType(AmountKeypad), findsOneWidget);
    expect(position.pixels, inInclusiveRange(0, position.maxScrollExtent));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a message during an active drag preserves the reader and scrolling input',
      (tester) async {
    final failed = ValueNotifier(false);
    final amount = TextEditingController(text: '0.12');
    addTearDown(failed.dispose);
    addTearDown(amount.dispose);
    await _pump(tester, failed, amount,
        size: const Size(430, 760), extraFormHeight: 250);
    final viewport = find.byType(SingleChildScrollView);
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    await tester.drag(viewport, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    final gesture = await tester.startGesture(tester.getCenter(viewport));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    final before = position.pixels;
    failed.value = true;
    await tester.pump();
    expect(position.pixels, closeTo(before, 0.01));
    expect(tester.state<ScrollableState>(find.byType(Scrollable)).position,
        same(position));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(position.pixels, greaterThan(before));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(amount.text, '0.12');
    await tester.pumpWidget(const SizedBox());
  });
}
