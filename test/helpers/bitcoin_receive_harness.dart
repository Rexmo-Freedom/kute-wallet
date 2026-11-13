// The Bitcoin QR receive (confirm_receive.dart) under the real shell bar, with
// a phone's insets, opened as the app opens it (showBitcoinQrReceiveSheet),
// and every state it can be in: confirm_receive_bar_test.dart reads the bar in
// each, receive_render_test.dart looks at them. The wallet never answers: the
// address, the Lightning address and the invoice are stubbed, nothing reaches
// a money call.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show ReceivePaymentResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/breez_provider.dart'
    show receivePaymentProvider, setupLnAddressProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show walletAddressProvider;
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart' show AmountKeypad;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import 'shell_bar_harness.dart';

const receiveAddress = 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq';
const receiveLnAddress = 'brutalkute@paykute.com';
const receiveLnurl =
    'lnurl1dp68gurn8ghj7ctsdyhxwetewdjhytnxw4hxgtmvde6hymp0wpshj0mswfhk5etrw3ykg0f3xqcs2mcx97';
const receiveInvoice =
    'lnbc1000n1pjqwertyuiopasdfghjklzxcvbnm1234567890qwertyuiopasdfghjkl';

final _l10n = AppLocalizationsEn();

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(60000),
          'BTC': Fixed.fromNum(1 / 60000, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

class _Balances extends WalletBalanceCacheNotifier {
  _Balances() {
    state = {
      'wallet':
          WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 123456),
    };
  }
}

/// What the wallet answers, each time it is asked.
class ReceiveWorld {
  ReceiveWorld({
    WalletConfig? wallet,
    this.kind,
    Future<String> Function()? address,
    Future<Lnurl> Function()? lnurl,
    Future<ReceivePaymentResponse> Function()? invoice,
  })  : wallet = wallet ?? WalletConfig(id: 'wallet', name: 'Spending Wallet'),
        address = address ?? (() async => receiveAddress),
        lnurl = lnurl ??
            (() async => Lnurl(
                username: 'brutalkute',
                lightningAddress: receiveLnAddress,
                lnurl: receiveLnurl)),
        invoice = invoice ??
            (() async => ReceivePaymentResponse(
                paymentRequest: receiveInvoice, fee: BigInt.zero));

  final WalletConfig wallet;

  /// A cold wallet's kind; null is the spending wallet.
  final ColdAccountKind? kind;
  Future<String> Function() address;
  Future<Lnurl> Function() lnurl;
  Future<ReceivePaymentResponse> Function() invoice;
}

/// Never answers: still loading.
Future<T> neverAnswers<T>() => Completer<T>().future;

Future<void> settleReceive(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Fonts for a render: the address's 'monospace' has none in a test.
Future<void> loadReceiveFonts(WidgetTester tester) =>
    tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
      final mono = FontLoader('monospace')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
      await mono.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

/// Opens the Bitcoin QR receive for [world], the bar over it.
Future<void> openBitcoinReceive(
  WidgetTester tester,
  ReceiveWorld world, {
  bool dark = false,
  Size size = const Size(375, 812),
  Locale? locale,
  double textScale = 1,
  Future<void> Function(BuildContext context) open = showBitcoinQrReceiveSheet,
}) async {
  installShellBar();
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = size.height >= 800
      ? const FakeViewPadding(top: 47, bottom: 34)
      : const FakeViewPadding(top: 20);
  addTearDown(tester.view.reset);
  final base = dark ? buildDarkTheme() : buildLightTheme();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: world.wallet.id,
            wallets: [world.wallet],
          ))),
      selectedAccountProvider.overrideWithValue(world.kind == null
          ? BtcSpendingAccount(world.wallet)
          : BtcColdAccount(world.wallet, world.kind!)),
      walletAddressProvider.overrideWith((ref, id) => world.address()),
      setupLnAddressProvider.overrideWith((ref) => world.lnurl()),
      receivePaymentProvider.overrideWith((ref, args) => world.invoice()),
      currencyProvider.overrideWith((_) => _Currency()),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromIntWithCurrency(6000000, AppCurrencies.usd)),
      walletBalanceCacheProvider.overrideWith((_) => _Balances()),
      breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    ],
    // The app's own scale (app_widget.dart), which a small phone depends on.
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: base.copyWith(
          splashFactory: NoSplash.splashFactory,
          textTheme: base.textTheme.apply(fontFamily: 'Inter'),
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: shellBarObservers(),
        builder: (context, child) => RepaintBoundary(
            key: const ValueKey('shot'), child: shellBarBuilder(context, child)),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                  onPressed: () => open(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await settleReceive(tester);
}

/// Unmounts the sheet before its 5 s balance watch fires, and stops the
/// policy's own timers (the bar's Sal asks it whether AI is on) unless
/// [reopen]: a sheet opened after that has no policy.
Future<void> closeBitcoinReceive(WidgetTester tester,
    {bool reopen = false}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  if (!reopen) RuntimeCapabilitiesService.instance.dispose();
}

/// Picks a tab of the format chips.
Future<void> pickReceiveTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await settleReceive(tester);
}

/// Asks for [amount] sats through the Request amount sheet.
Future<void> requestReceiveAmount(WidgetTester tester,
    {String amount = '1000'}) async {
  await tester.tap(find.byKey(const ValueKey('receive-request-amount')));
  await settleReceive(tester);
  tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged(amount);
  await settleReceive(tester);
  await tester.tap(find.byKey(kuteBarPrimaryButtonKey));
  await settleReceive(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

WalletConfig _ledger() => WalletConfig(
    id: 'wallet',
    name: 'Ledger',
    sparkEnabled: false,
    isHardware: true,
    walletType: 'ledger',
    scriptType: 'bip84');

WalletConfig _watchOnly() => WalletConfig(
    id: 'wallet', name: 'Watch', sparkEnabled: false, isWatchOnly: true);

WalletConfig _signer() =>
    WalletConfig(id: 'wallet', name: 'Signer', sparkEnabled: false, isSigner: true);

WalletConfig _tracked() => WalletConfig(
    id: 'wallet', name: 'Tracked', sparkEnabled: false, isExternalAddress: true);

/// One state of the screen and what the bar says in it.
class ReceiveState {
  ReceiveState(
    this.name,
    this.bar, {
    required this.world,
    this.busy = false,
    this.shares,
    this.after,
  });

  final String name;

  /// The bar's words.
  final String bar;

  /// A fresh world per pump: its answers are per test.
  final ReceiveWorld Function() world;
  final bool busy;

  /// What the bar hands to the share sheet, where it shares.
  final String? shares;

  /// Takes the sheet to the state after it opened.
  final Future<void> Function(WidgetTester tester)? after;
}

final List<ReceiveState> receiveStates = [
  ReceiveState('unified', _l10n.share,
      world: ReceiveWorld.new,
      shares: 'bitcoin:$receiveAddress?lightning=$receiveLnurl'),
  ReceiveState('bitcoin_only', _l10n.share,
      world: ReceiveWorld.new,
      shares: receiveAddress,
      after: (t) => pickReceiveTab(t, _l10n.receiveQrFormatBitcoinOnly)),
  ReceiveState('lightning_only', _l10n.share,
      world: ReceiveWorld.new,
      shares: receiveLnurl.toUpperCase(),
      after: (t) => pickReceiveTab(t, _l10n.receiveQrFormatLightningOnly)),
  ReceiveState('amount_invoice', _l10n.share,
      world: ReceiveWorld.new,
      shares: receiveInvoice,
      after: requestReceiveAmount),
  ReceiveState('amount_bitcoin_only', _l10n.share,
      world: ReceiveWorld.new,
      shares: 'bitcoin:$receiveAddress?amount=0.00001000', after: (t) async {
    await pickReceiveTab(t, _l10n.receiveQrFormatBitcoinOnly);
    await requestReceiveAmount(t);
  }),
  ReceiveState('amount_lightning_only', _l10n.share,
      world: ReceiveWorld.new,
      shares: receiveInvoice, after: (t) async {
    await pickReceiveTab(t, _l10n.receiveQrFormatLightningOnly);
    await requestReceiveAmount(t);
  }),
  ReceiveState('address_loading', _l10n.share,
      world: () => ReceiveWorld(address: neverAnswers), busy: true),
  ReceiveState('lightning_address_loading', _l10n.share,
      world: () => ReceiveWorld(lnurl: neverAnswers), busy: true),
  ReceiveState('invoice_loading', _l10n.share,
      world: () => ReceiveWorld(invoice: neverAnswers),
      busy: true,
      after: requestReceiveAmount),
  ReceiveState('address_failed', _l10n.tryAgain,
      world: () => ReceiveWorld(address: () async => throw Exception('no'))),
  ReceiveState('address_failed_spark_empty', _l10n.tryAgain,
      world: () => ReceiveWorld(address: () async => '')),
  ReceiveState('lightning_failed', _l10n.tryAgain,
      world: () => ReceiveWorld(lnurl: () async => throw Exception('no')),
      after: (t) => pickReceiveTab(t, _l10n.receiveQrFormatLightningOnly)),
  // The unified code does without Lightning: the plain Bitcoin URI.
  ReceiveState('lightning_failed_unified', _l10n.share,
      world: () => ReceiveWorld(lnurl: () async => throw Exception('no')),
      shares: 'bitcoin:$receiveAddress'),
  ReceiveState('ledger', _l10n.share,
      world: () =>
          ReceiveWorld(wallet: _ledger(), kind: ColdAccountKind.hardware),
      shares: receiveAddress),
  ReceiveState('ledger_syncing', _l10n.share,
      world: () => ReceiveWorld(
          wallet: _ledger(),
          kind: ColdAccountKind.hardware,
          address: neverAnswers),
      busy: true),
  ReceiveState('ledger_failed', _l10n.tryAgain,
      world: () => ReceiveWorld(
          wallet: _ledger(),
          kind: ColdAccountKind.hardware,
          address: () async => throw Exception('no'))),
  ReceiveState('watch_only', _l10n.share,
      world: () =>
          ReceiveWorld(wallet: _watchOnly(), kind: ColdAccountKind.watchOnly),
      shares: receiveAddress),
  ReceiveState('tracked', _l10n.share,
      world: () =>
          ReceiveWorld(wallet: _tracked(), kind: ColdAccountKind.tracked),
      shares: receiveAddress),
  ReceiveState('tracked_none_stored', _l10n.done,
      world: () => ReceiveWorld(
          wallet: _tracked(),
          kind: ColdAccountKind.tracked,
          address: () async => '')),
  ReceiveState('signer', _l10n.done,
      world: () => ReceiveWorld(
          wallet: _signer(),
          kind: ColdAccountKind.signer,
          address: () async => '')),
];

/// The plate's side.
double receivePlateSide(WidgetTester tester) => tester
    .getSize(find
        .descendant(
            of: find.byType(ReceiveQrPlate), matching: find.byType(Container))
        .first)
    .width;
