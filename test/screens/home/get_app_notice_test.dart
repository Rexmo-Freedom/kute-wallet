// The web home's "get the app" notice (get_app_notice.dart): which store
// buttons each browser gets, the plain store links, the 30-day close,
// the backup reminder winning, and nothing as an installed app or off the
// web.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/browser_signals.dart';
import 'package:kute/platform/plain_web_storage.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/home/components/get_app_notice.dart';
import 'package:kute/screens/shared/kute_notice_card.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

const _iphone = BrowserSignals(
  maxTouchPoints: 5,
  coarsePointer: true,
  noHover: true,
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148',
);
const _ipadOs = BrowserSignals(
  maxTouchPoints: 5,
  coarsePointer: true,
  noHover: true,
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
);
const _android = BrowserSignals(
  maxTouchPoints: 5,
  coarsePointer: true,
  noHover: true,
  userAgent: 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0 Mobile Safari/537.36',
);
const _mac = BrowserSignals(
  maxTouchPoints: 0,
  coarsePointer: false,
  noHover: false,
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
);
const _windows = BrowserSignals(
  maxTouchPoints: 10,
  coarsePointer: false,
  noHover: false,
  userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0',
);

BrowserSignals _installed(BrowserSignals s) => BrowserSignals(
    maxTouchPoints: s.maxTouchPoints,
    coarsePointer: s.coarsePointer,
    noHover: s.noHover,
    userAgent: s.userAgent,
    standalone: true);

void main() {
  late List<(String, Map<String, Object>?)> events;
  late List<Uri> opened;
  var now = DateTime(2026, 11, 27, 12);

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    dotenv.loadFromString(envString: 'APP_STORE_ID=id6740000000');
    PlainWebStorage.debugValues = {};
    now = DateTime(2026, 11, 27, 12);
    GetAppNoticeRules.debugNow = () => now;
    debugResetGetAppNoticeSession();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    opened = [];
    debugGetAppNoticeOpen = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  tearDown(() {
    debugBrowserSignals = null;
    PlainWebStorage.debugValues = null;
    GetAppNoticeRules.debugNow = null;
    TrackingService.debugTrackObserver = null;
    debugGetAppNoticeOpen = null;
  });

  Future<void> pump(WidgetTester tester,
      {WalletConfig? pendingBackup, String surface = 'bitcoin'}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pendingSpendingWalletBackupProvider.overrideWith((ref) => pendingBackup),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: GetAppNotice(surface: surface)),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Finder notice() => find.byKey(const ValueKey('get-app-notice'));
  Finder appStore() => find.byKey(const ValueKey('get-app-app_store'));
  Finder play() => find.byKey(const ValueKey('get-app-google_play'));

  group('platform and stores', () {
    test('the browser kind', () {
      expect(_iphone.platform, BrowserPlatform.ios);
      expect(_ipadOs.platform, BrowserPlatform.ios);
      expect(_android.platform, BrowserPlatform.android);
      expect(_mac.platform, BrowserPlatform.laptop);
      expect(_windows.platform, BrowserPlatform.laptop);
    });

    test('the stores each kind gets', () {
      expect(GetAppNoticeRules.storesFor(BrowserPlatform.ios),
          [AppStoreKind.appStore]);
      expect(GetAppNoticeRules.storesFor(BrowserPlatform.android),
          [AppStoreKind.googlePlay]);
      expect(GetAppNoticeRules.storesFor(BrowserPlatform.laptop),
          [AppStoreKind.appStore, AppStoreKind.googlePlay]);
    });

    test('plain store links, no attribution parameters', () {
      expect(GetAppNoticeRules.storeUri(AppStoreKind.appStore).toString(),
          'https://apps.apple.com/app/id6740000000');
      expect(GetAppNoticeRules.storeUri(AppStoreKind.googlePlay).toString(),
          'https://play.google.com/store/apps/details?id=com.kutewallet.app');
    });
  });

  group('buttons per browser', () {
    for (final (label, signals, hasAppStore, hasPlay) in [
      ('iPhone', _iphone, true, false),
      ('iPadOS Safari', _ipadOs, true, false),
      ('Android', _android, false, true),
      ('Mac laptop', _mac, true, true),
      ('Windows laptop', _windows, true, true),
    ]) {
      testWidgets(label, (tester) async {
        debugBrowserSignals = signals;
        await pump(tester);
        expect(notice(), findsOneWidget);
        expect(find.byType(KuteNoticeCard), findsOneWidget);
        expect(find.text('Get the Kute app'), findsOneWidget);
        expect(find.text('Available for iPhone and Android'), findsOneWidget);
        expect(appStore(), hasAppStore ? findsOneWidget : findsNothing);
        expect(play(), hasPlay ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('get-app-close')), findsOneWidget);
      });
    }

    testWidgets('a store tap opens its plain link and is counted',
        (tester) async {
      debugBrowserSignals = _mac;
      await pump(tester, surface: 'dollars');
      await tester.tap(play());
      await tester.tap(appStore());
      expect(opened.map((u) => u.toString()), [
        'https://play.google.com/store/apps/details?id=com.kutewallet.app',
        'https://apps.apple.com/app/id6740000000',
      ]);
      final taps =
          events.where((e) => e.$1 == 'get_app_banner_store_tapped').toList();
      expect(taps.map((e) => e.$2!['store']), ['google_play', 'app_store']);
      expect(taps.first.$2!['surface'], 'dollars');
      expect(taps.first.$2!['platform'], 'laptop');
      final shown = events.where((e) => e.$1 == 'get_app_banner_shown');
      expect(shown, hasLength(1));
      expect(shown.single.$2, {'surface': 'dollars', 'platform': 'laptop'});
    });

    testWidgets('no APP_STORE_ID: an iPhone gets no notice at all',
        (tester) async {
      dotenv.loadFromString(envString: 'OTHER=1');
      debugBrowserSignals = _iphone;
      await pump(tester);
      expect(notice(), findsNothing);
    });
  });

  group('dismissal', () {
    testWidgets('a close hides it, is stored, and keeps it away for 30 days',
        (tester) async {
      debugBrowserSignals = _android;
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('get-app-close')));
      await tester.pump();
      expect(notice(), findsNothing);
      expect(events.map((e) => e.$1), contains('get_app_banner_dismissed'));
      expect(PlainWebStorage.debugValues![GetAppNoticeRules.storageKey],
          now.millisecondsSinceEpoch.toString());

      // A new page load in the same browser, 29 days later: still away.
      now = now.add(const Duration(days: 29, hours: 23));
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(notice(), findsNothing);

      // 30 days after the close: back.
      now = now.add(const Duration(hours: 1));
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      expect(notice(), findsOneWidget);
    });

    test('the rule itself', () {
      final at = DateTime(2026, 11, 1);
      bool show(DateTime n) => GetAppNoticeRules.shouldShow(
          signals: _mac, backupShowing: false, dismissedAt: at, now: n);
      expect(show(at.add(const Duration(days: 29))), isFalse);
      expect(show(at.add(const Duration(days: 30))), isTrue);
    });
  });

  group('never shown', () {
    testWidgets('while the backup reminder is up', (tester) async {
      debugBrowserSignals = _mac;
      await pump(tester,
          pendingBackup: WalletConfig(id: 'w1', name: 'Spending'));
      expect(notice(), findsNothing);
      expect(events.where((e) => e.$1 == 'get_app_banner_shown'), isEmpty);
    });

    for (final (label, signals) in [
      ('iPhone', _iphone),
      ('Android', _android),
      ('laptop', _mac),
    ]) {
      testWidgets('installed as an app (display-mode standalone): $label',
          (tester) async {
        debugBrowserSignals = _installed(signals);
        await pump(tester);
        expect(notice(), findsNothing);
      });
    }

    testWidgets('off the web (the phone apps)', (tester) async {
      await pump(tester);
      expect(notice(), findsNothing);
    });
  });
}
