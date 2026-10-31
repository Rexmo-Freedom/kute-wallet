// The proposal card: what will happen, the figure, the facts, one button.
// A prepared proposal names who prepared it and can be dismissed; the
// card never confirms itself (a null onConfirm draws the button disabled).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/proposal_card.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: card)),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the person\'s own proposal: title, figure, facts, one button',
      (tester) async {
    var confirmed = 0;
    await _pump(
        tester,
        ProposalCard(
          title: r'Put $5 in Gold',
          subtitle: 'From Dollars',
          amountText: r'$5.00',
          lines: const [
            ProposalLine('From', r'Dollars $12.80'),
            ProposalLine('Fee', r'$0.05'),
            ProposalLine('If Gold drops 10%', r'$4.50',
                valueColor: Colors.red),
          ],
          confirmLabel: r'Put $5 in Gold',
          onConfirm: () => confirmed++,
        ));
    expect(find.byKey(const ValueKey('proposal-card')), findsOneWidget);
    expect(find.text(r'Put $5 in Gold'), findsNWidgets(2));
    expect(find.text('From Dollars'), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-amount')), findsOneWidget);
    expect(find.text('Fee'), findsOneWidget);
    expect(find.text(r'$4.50'), findsOneWidget);
    // Nobody else prepared it: no origin line, no dismiss.
    expect(find.byKey(const ValueKey('proposal-origin')), findsNothing);
    expect(find.byKey(const ValueKey('proposal-dismiss')), findsNothing);
    await tester.tap(find.byType(AppButton));
    expect(confirmed, 1);
  });

  testWidgets('a prepared proposal says who prepared it and can be dismissed',
      (tester) async {
    var dismissed = 0;
    await _pump(
        tester,
        ProposalCard(
          title: r'Send $20 to Rina',
          amountText: r'$20.00',
          originLabel: 'Prepared by Sal',
          confirmLabel: 'Send',
          onConfirm: () {},
          dismissLabel: 'Not now',
          onDismiss: () => dismissed++,
        ));
    expect(find.text('Prepared by Sal'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proposal-dismiss')));
    expect(dismissed, 1);
  });

  testWidgets('without a confirm, the button is disabled: the card never '
      'confirms itself', (tester) async {
    await _pump(
        tester,
        const ProposalCard(
          title: r'Move $10 to Dollars',
          amountText: r'$10.00',
          confirmLabel: 'Move',
          onConfirm: null,
        ));
    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);
  });
}
