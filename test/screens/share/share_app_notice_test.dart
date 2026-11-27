// "Open in the app" on a shared market's guest page (share_app_notice.dart).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/in_app_browser.dart';
import 'package:kute/screens/share/share_app_notice.dart';
import 'package:kute/theme/app_theme.dart';

const _iphone = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 '
    'Safari/604.1';
const _android = 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
const _mac = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

void main() {
  final opened = <Uri>[];
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    ShareAppNotice.debugReset();
    opened.clear();
    ShareAppNotice.debugOpen = opened.add;
    dotenv.loadFromString(envString: 'APP_STORE_ID=id123456789');
  });
  tearDown(() {
    InAppBrowser.debugUserAgent = null;
    ShareAppNotice.debugOpen = null;
    dotenv.clean();
  });

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ShareAppNoticeHost(child: Text('MARKET')),
        ),
      ));

  testWidgets('iPhone: the App Store, no AppsFlyer; one notice at a time',
      (tester) async {
    InAppBrowser.debugUserAgent = _iphone;
    await pump(tester);
    expect(find.byKey(const ValueKey('share-app-notice')), findsOneWidget);
    expect(ShareAppNotice.showing.value, isTrue);
    await tester.tap(find.text('Open in the app'));
    expect(opened.single.toString(), 'https://apps.apple.com/app/id123456789');
    expect(opened.single.toString(), isNot(contains('onelink')));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.byKey(const ValueKey('share-app-notice')), findsNothing);
    expect(ShareAppNotice.showing.value, isFalse);
    // Dismissed for the run.
    await pump(tester);
    expect(find.byKey(const ValueKey('share-app-notice')), findsNothing);
  });

  testWidgets('Android: Google Play', (tester) async {
    InAppBrowser.debugUserAgent = _android;
    await pump(tester);
    await tester.tap(find.text('Open in the app'));
    expect(opened.single.toString(),
        'https://play.google.com/store/apps/details?id=com.kutewallet.app');
  });

  testWidgets('a laptop: no notice', (tester) async {
    InAppBrowser.debugUserAgent = _mac;
    await pump(tester);
    expect(find.byKey(const ValueKey('share-app-notice')), findsNothing);
    expect(find.text('MARKET'), findsOneWidget);
  });
}
