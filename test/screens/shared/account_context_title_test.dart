import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('fixed Send and Receive title cannot open an account picker',
      (tester) async {
    var picked = false;
    final account = BtcColdAccount(
      WalletConfig(
          id: 'cold',
          name: 'Cold savings',
          isWatchOnly: true,
          sparkEnabled: false),
      ColdAccountKind.watchOnly,
    );
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          home: Scaffold(
              appBar: AppBar(
                  title: AccountSwitcherPill(
            pickerTitle: 'Receive into',
            account: account,
            readOnly: true,
            onPicked: (_) => picked = true,
          ))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Cold savings'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AccountSwitcherPill),
            matching: find.byType(GestureDetector)),
        findsNothing);
    await tester.tap(find.text('Cold savings'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, isFalse);
    expect(find.text('Receive into'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
