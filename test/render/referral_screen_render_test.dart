// A look by eye at the Referral program screen (affiliate_screen.dart;
// founder, 7 November 2026: "this screen must be remade in a much much
// better way"), written only when asked: REFERRAL_RENDER=<dir>.
//
// The real Inter face, the real Sal sheets and the shell bar over the
// page, shadows drawn as on a phone. Every state the screen has:
//
//   * zero:     a fresh code, no friends, $0.00 everywhere;
//   * mid:      62 friends, between the tiers, an earnings line, two
//               payments and the friends list;
//   * top:      134 friends on the top rate;
//   * withheld: the mid data where the policy withholds affiliate.program
//               (no hero, no code, no share);
//   * nocode:   the program allowed but no code minted yet;
//   * error:    /me failed, the program live;
//   * soon:     /me failed, the program not live;
//   * loading:  the backend has not answered yet;
//   * qr:       the zero state with the QR sheet open (the new screen only).
//
// Each at 320, 375 and 430 points wide, light and dark: the whole page
// (tall, laid out at the phone's height and shown longer) so nothing hides
// under the fold; the phone's own fold at 320 and 375 (`fold`); and the
// light pages at 1.3x text (`large`). One case per run is safest:
//   for c in zero mid top withheld nocode error soon loading qr; do
//     REFERRAL_RENDER=<dir> flutter test \
//     test/render/referral_screen_render_test.dart --plain-name "$c "; done

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/settings/affiliate_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';
import '../helpers/runtime_policy_fixture.dart';

final _dir = Platform.environment['REFERRAL_RENDER'];

Future<void> _assets(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      // The old screen's code and the late-entry field ask for
      // 'monospace', which iOS does not resolve (the system face draws
      // it): Inter stands in, so the letters read instead of boxes.
      final mono = FontLoader('monospace');
      for (final f in ['Regular', 'Bold']) {
        mono.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await mono.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final manifest = jsonDecode(
              await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>;
      SalSpriteCache.debugSetManifest(manifest);
      for (final clip in [
        'idle',
        'search',
        'share',
        'body_wag',
        'body_sad',
      ]) {
        // Both sheets: the shot is laid out at 1x and painted at 3x.
        await SalSpriteCache.clip(clip, 2);
        await SalSpriteCache.clip(clip, 3);
      }
    });

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

/// The program's rules as the backend publishes them (affiliate_me.go).
const Map<String, Object> _rules = {
  'referee_discount_pct': 20,
  'base_rate_pct': 5.0,
  'max_rate_pct': 25.0,
  'tiers': [
    {'activated_referees': 50, 'rate_pct': 10.0},
    {'activated_referees': 100, 'rate_pct': 20.0},
  ],
};

Map<String, Object> _me({
  String code = 'EKVGUY',
  double rate = 5,
  int friends = 0,
  double accrued = 0,
  double paid = 0,
  List<Object> payments = const [],
}) =>
    {
      'affiliate_code': code,
      'commission_rate_pct': rate,
      'referees_bound': friends,
      'referees_activated': friends,
      'accrued_usd': accrued,
      'paid_usd': paid,
      'is_referred': false,
      'payments': payments,
      'referee_discount_pct': 20,
      'rules': _rules,
    };

List<Object> _history(double end) => [
      for (var i = 0; i < 30; i++)
        {
          'date': DateTime.utc(2026, 10, 9 + i).toIso8601String(),
          'cumulative_usd': end * (i * i) / (29 * 29),
        },
    ];

List<Object> _referees(int n) => [
      for (var i = 0; i < n; i++)
        {'activated': true, 'contribution_usd': 4.0 + (i % 7) * 3.5},
    ];

enum _Case { zero, mid, top, withheld, nocode, error, soon, loading, qr }

({Map<String, Object>? me, List<Object> history, List<Object> referees}) _data(
        _Case c) =>
    switch (c) {
      _Case.zero || _Case.qr || _Case.loading => (
          me: _me(),
          history: const [],
          referees: const []
        ),
      _Case.mid || _Case.withheld => (
          me: _me(
            rate: 10,
            friends: 62,
            accrued: 12.4,
            paid: 30,
            payments: [
              {'paid_at': '2026-10-01T10:00:00Z', 'amount_usd': 18.0},
              {'paid_at': '2026-11-01T10:00:00Z', 'amount_usd': 12.0},
            ],
          ),
          history: _history(42.4),
          referees: _referees(6),
        ),
      _Case.top => (
          me: _me(
            rate: 20,
            friends: 134,
            accrued: 245.18,
            paid: 1210.5,
            payments: [
              {'paid_at': '2026-11-01T10:00:00Z', 'amount_usd': 1210.5},
            ],
          ),
          history: _history(1455.68),
          referees: _referees(4),
        ),
      _Case.nocode => (
          me: _me(code: ''),
          history: const [],
          referees: const []
        ),
      _Case.error || _Case.soon => (
          me: null,
          history: const [],
          referees: const []
        ),
    };

http.Client _backend(_Case c, Completer<void> gate) =>
    MockClient((request) async {
      if (c == _Case.loading) await gate.future;
      final d = _data(c);
      switch (request.url.path) {
        case '/api/v1/affiliate/me':
          final me = d.me;
          return me == null
              ? http.Response('down', 500)
              : http.Response(jsonEncode(me), 200);
        case '/api/v1/affiliate/me/history':
          return http.Response(jsonEncode({'history': d.history}), 200);
        case '/api/v1/affiliate/me/referees':
          return http.Response(jsonEncode({'referees': d.referees}), 200);
        default:
          return http.Response('not found', 404);
      }
    });

/// The whole screen as a PNG, the shadows drawn as on a phone.
Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _heights = {320: 568.0, 375: 812.0, 430: 932.0};

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FlutterSecureStorage.setMockInitialValues({});
    dotenv.loadFromString(
        envString: 'BACKEND=https://backend.test\n'
            'APPSFLYER_ONELINK_TEMPLATE=kute.onelink.me/aBcD');
    AffiliateService.debugSessionToken = 'render-session';
    TrackingService.setDisabled(true);
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    kuteShellMounted.value = false;
  });

  for (final c in _Case.values) {
    for (final width in _heights.keys) {
      for (final dark in [false, true]) {
        for (final (scale, tall) in [(1.0, true), (1.0, false), (1.3, true)]) {
          // The fold (phone height) and the large text only where they
          // tell something new: the main states at 375 and 320.
          if (!tall && width == 430) continue;
          if (scale > 1 && dark) continue;
          final mode = dark ? 'dark' : 'light';
          final tag = [
            c.name,
            width.toString(),
            mode,
            if (!tall) 'fold',
            if (scale > 1) 'large',
          ].join(' ');
          testWidgets(tag, skip: _dir == null, (tester) async {
            await _assets(tester);
            final policy = runtimePolicyFixture(also: {
              'affiliate.program'
            }, blocked: {
              if (c == _Case.withheld || c == _Case.soon) 'affiliate.program'
            });
            RuntimeCapabilitiesService.debugInstance = policy;
            await tester.runAsync(policy.refresh);
            kuteShellMounted.value = true;
            final height = tall ? 2400.0 : _heights[width]!;
            tester.view.physicalSize = Size(width * 1.0, height);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue);
            final gate = Completer<void>();
            await http.runWithClient(() async {
              // A tall shot keeps the phone's height for the design
              // scale (ScreenUtil's .h), so the page is laid out as on the
              // phone and only shown longer.
              await tester.pumpWidget(ProviderScope(
                child: ScreenUtilInit(
                  designSize: const Size(430, 932),
                  builder: (context, __) {
                    ScreenUtil.configure(
                      data: MediaQueryData.fromView(View.of(context))
                          .copyWith(size: Size(width * 1.0, _heights[width]!)),
                      designSize: const Size(430, 932),
                    );
                    return MaterialApp(
                      debugShowCheckedModeBanner: false,
                      theme: _theme(dark),
                      builder: withKuteShellBar,
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      home: const AffiliateScreen(),
                    );
                  },
                ),
              ));
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 50)));
              await _frames(tester);
              if (c == _Case.qr) {
                await tester
                    .tap(find.byKey(const ValueKey('referral-code-qr')));
                await _frames(tester, 10);
              }
              await _shoot(tester, 'referral_${tag.replaceAll(' ', '_')}');
              final error = tester.takeException();
              if (error is FlutterError) debugPrint(error.toStringDeep());
              expect(error, isNull);
              if (!gate.isCompleted) gate.complete();
              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 1));
            }, () => _backend(c, gate));
            policy.dispose();
          });
        }
      }
    }
  }
}
