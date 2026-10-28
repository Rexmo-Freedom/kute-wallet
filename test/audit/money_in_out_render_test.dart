// Bitcoin home "In & out" render harness: the analytics strip with the In
// & out tab open over five months of realistic history, written as PNGs
// in light and dark at 390 wide: Out picked, In picked, an empty month,
// and the Year view. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/money_in_out_render_test.dart \
//     --dart-define=MONEY_IN_OUT_RENDER=true \
//     --dart-define=MONEY_IN_OUT_RENDER_OUT=/tmp/kute_money_in_out

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/address_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/analytics/components/money_in_out.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('MONEY_IN_OUT_RENDER');
const _outDefine = String.fromEnvironment('MONEY_IN_OUT_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_money_in_out';

const _shotKey = ValueKey('money-in-out-render-shot');
final _now = DateTime(2026, 10, 28, 9);
final _spending = WalletConfig(id: 'spending', name: 'Spending');

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

SparkTransaction _pay(String id, int sats, int fee, bool out, DateTime at,
    {breez.PaymentMethod method = breez.PaymentMethod.lightning}) {
  return SparkTransaction(
    id: id,
    timestamp: at,
    isConfirmed: true,
    details: breez.Payment(
      id: id,
      paymentType: out ? breez.PaymentType.send : breez.PaymentType.receive,
      status: breez.PaymentStatus.completed,
      amount: BigInt.from(sats),
      fees: BigInt.from(fee),
      timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
      method: method,
    ),
  );
}

SwapOrderTransaction _swap(String id, String from, String fromNet, String to,
        String toNet, String deposit, String withdrawal, DateTime at,
        {String? route, String? purchase}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: SwapOrder(
        id: id,
        coinFrom: from,
        networkFrom: fromNet,
        coinTo: to,
        networkTo: toNet,
        depositAddress: 'deposit-$id',
        depositAmount: deposit,
        withdrawalAmount: withdrawal,
        status: 'success',
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: toNet == 'SPARK' ? 'sp1self' : '0xelsewhere',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
        routeVersion: route,
        purchaseSource: purchase,
      ),
    );

const _usd = kOrchestraUsdAssetCode;

/// June to October 2026, nothing in May; a little of 2025 for the Year
/// view.
Transaction _history() => Transaction(
      bitcoinTransactions: const [],
      sparkTransactions: [
        _pay('o1', 12400, 8, true, DateTime(2026, 10, 3, 10)),
        _pay('o2', 25000, 3, true, DateTime(2026, 10, 11, 18),
            method: breez.PaymentMethod.spark),
        _pay('i1', 40000, 0, false, DateTime(2026, 10, 7, 9)),
        _pay('i2', 8500, 0, false, DateTime(2026, 10, 19, 21)),
        _pay('s1', 18000, 11, true, DateTime(2026, 9, 4, 12)),
        _pay('s2', 6500, 140, true, DateTime(2026, 9, 21, 8),
            method: breez.PaymentMethod.withdraw),
        _pay('si', 55000, 0, false, DateTime(2026, 9, 14, 16)),
        _pay('a1', 30000, 15, true, DateTime(2026, 8, 9, 13)),
        _pay('ai', 22000, 0, false, DateTime(2026, 8, 25, 11)),
        _pay('j1', 9000, 6, true, DateTime(2026, 7, 2, 10)),
        _pay('n1', 5000, 4, true, DateTime(2026, 6, 18, 19)),
        _pay('ni', 60000, 0, false, DateTime(2026, 6, 5, 7)),
        _pay('y1', 150000, 0, false, DateTime(2025, 11, 20, 10)),
        _pay('y2', 42000, 9, true, DateTime(2025, 12, 12, 17)),
      ],
      sparkUnclaimedDeposits: const [],
      swapOrderTransactions: [
        _swap('oct_usd', 'BTC', 'SPARK', _usd, 'SPARK', '0.0005', '40.75',
            DateTime(2026, 10, 15, 12)),
        _swap('oct_home', 'USDC', 'HYPERCORE', 'BTC', 'SPARK', '24.45',
            '0.0003', DateTime(2026, 10, 24, 15),
            route: 'hypercore_to_spark_v1'),
        _swap('oct_inv', 'BTC', 'SPARK', 'USDC', 'HYPERCORE', '0.0002',
            '16.30', DateTime(2026, 10, 26, 9),
            route: 'spark_to_hypercore_v1'),
        _swap('sep_buy', 'BTC', 'LIGHTNING', 'BTC', 'SPARK', '0.0012', '0.0012',
            DateTime(2026, 9, 2, 14),
            purchase: 'cashapp'),
        _swap('sep_inv', 'BTC', 'SPARK', 'USDC', 'HYPERCORE', '0.00015',
            '12.20', DateTime(2026, 9, 28, 10),
            route: 'spark_to_hypercore_v1'),
        _swap('aug_usd', _usd, 'SPARK', 'BTC', 'SPARK', '32.60', '0.0004',
            DateTime(2026, 8, 17, 12)),
        _swap('jul_buy', 'BTC', 'LIGHTNING', 'BTC', 'SPARK', '0.001', '0.001',
            DateTime(2026, 7, 8, 14),
            purchase: 'cashapp'),
        _swap('jul_inv', 'BTC', 'SPARK', 'USDC', 'HYPERCORE', '0.00045',
            '36.70', DateTime(2026, 7, 20, 10),
            route: 'spark_to_hypercore_v1'),
      ],
    );

Future<void> _pump(WidgetTester tester, {required bool dark}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = Settings(
    currency: 'USD',
    language: 'en',
    btcFormat: 'sats',
    backup: false,
    biometricsEnabled: false,
    bitcoinElectrumNode: '',
    nodeType: '',
    reviewDone: true,
    activeWalletId: 'spending',
    wallets: [_spending],
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(settings)),
      walletTransactionCacheProvider
          .overrideWith((_) => _Cache({'spending': _history()})),
      initialAddressesProvider.overrideWith((_) async =>
          Address(bitcoinAddressIndex: 0, bitcoinAddress: 'bc1qself')),
      sparkSelfAddressProvider.overrideWith((_) async => 'sp1self'),
      // About $81,500 a bitcoin.
      conversionToFiatProvider.overrideWith(
          (ref, sats) => '\$${(sats * 0.000815).toStringAsFixed(2)}'),
      viewedWalletProvider.overrideWithValue(_spending),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => RepaintBoundary(key: _shotKey, child: child),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: HomeAnalyticsWidget(
                surface: 'home',
                showPrice: false,
                activityChild: const SizedBox(height: 40),
                breakdownChild: MoneyInOut(now: _now),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('In & out'));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
}

void main() {
  if (!_enabled) {
    test('money in out render', () {},
        skip: 'on demand: --dart-define=MONEY_IN_OUT_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [
      GoogleFonts.inter().fontFamily!,
      'Inter',
      'FlutterTest'
    ]) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('out $theme', (tester) async {
      await _pump(tester, dark: dark);
      await _shot(tester, 'in_out_out_$theme');
    });
    testWidgets('in $theme', (tester) async {
      await _pump(tester, dark: dark);
      await _tapKey(tester, 'in-out-side-in');
      await _shot(tester, 'in_out_in_$theme');
    });
    testWidgets('empty month $theme', (tester) async {
      await _pump(tester, dark: dark);
      await _tapKey(tester, 'in-out-bar-0');
      await _shot(tester, 'in_out_empty_$theme');
    });
    testWidgets('year $theme', (tester) async {
      await _pump(tester, dark: dark);
      await _tapKey(tester, 'in-out-year');
      await _shot(tester, 'in_out_year_$theme');
    });
  }
}
