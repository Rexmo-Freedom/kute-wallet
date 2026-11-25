// The Bitcoin QR receive's Share is the bar (founder, 8 November 2026: "the
// share button should be the sal on the bottom"): no button in the page, a
// truthful bar in every state and never the default search, the code's exact
// payload at the share sheet from each tab with the same events as before, a
// retry that asks again, and a page that scrolls clear of the bar.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/receive/components/confirm_receive.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/bitcoin_receive_harness.dart';
import '../../helpers/kute_bar_test_support.dart' show kuteBarPrimaryContext;
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart' hide KuteBarContext;

final _l10n = AppLocalizationsEn();

Finder get _bar => find.byKey(kuteBarPrimaryButtonKey);

/// The bar's words, and that it is drawn.
void _expectBar(WidgetTester tester, String label, {bool busy = false}) {
  expect(find.descendant(of: _bar, matching: find.text(label)), findsOneWidget,
      reason: 'the bar says "$label"');
  final ctx = kuteBarPrimaryContext(tester);
  expect(ctx.label, label);
  expect(ctx.busy, busy);
  expect(ctx.enabled, !busy);
}

/// Records what reaches the share sheet.
List<String> _recordShares(WidgetTester tester) {
  final shared = <String>[];
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
      (call) async {
    shared.add((call.arguments as Map)['text'] as String);
    return 'dev.fluttercommunity.plus/share/unavailable';
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  return shared;
}

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    TrackingService.debugTrackObserver = null;
  });

  for (final state in receiveStates) {
    testWidgets('the bar: ${state.name} reads "${state.bar}"', (tester) async {
      final shared = _recordShares(tester);
      await openBitcoinReceive(tester, state.world());
      await state.after?.call(tester);
      _expectBar(tester, state.bar, busy: state.busy);
      // No Share in the page, whatever the state.
      expect(
          find.descendant(
              of: find.byType(ConfirmReceive), matching: find.text(_l10n.share)),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(ConfirmReceive), matching: find.text(_l10n.done)),
          findsNothing);
      await tester.tap(_bar);
      await tester.pump();
      if (state.shares != null) {
        expect(shared, [state.shares], reason: 'the code\'s exact payload');
      } else {
        expect(shared, isEmpty, reason: 'nothing to share yet');
      }
      expect(tester.takeException(), isNull);
      await closeBitcoinReceive(tester);
    });
  }

  testWidgets(
      'the bar\'s Share records what the page\'s did, per tab, and nothing new',
      (tester) async {
    _recordShares(tester);
    await openBitcoinReceive(tester, ReceiveWorld());
    Iterable<(String, Map<String, Object>?)> shares() =>
        events.where((e) => e.$1 == 'receive_qr_shared');
    for (final (tab, type) in [
      (_l10n.receiveQrFormatUnified, 'bip21'),
      (_l10n.receiveQrFormatBitcoinOnly, 'bitcoin_address'),
      (_l10n.receiveQrFormatLightningOnly, 'bolt11'),
    ]) {
      await pickReceiveTab(tester, tab);
      await tester.tap(_bar);
      await tester.pump();
      expect(shares().last.$2, {'method': 'share', 'invoice_type': type});
    }
    expect(shares().length, 3);
    await closeBitcoinReceive(tester);
  });

  testWidgets('Try again asks for the address again: busy, then Share',
      (tester) async {
    final shared = _recordShares(tester);
    // Failing until told otherwise.
    var fail = true;
    final again = Completer<String>();
    final world = ReceiveWorld(address: () {
      if (fail) return Future.error(Exception('no'));
      return again.future;
    });
    await openBitcoinReceive(tester, world);
    _expectBar(tester, _l10n.tryAgain);
    expect(find.text(_l10n.failedToGetAddress), findsOneWidget);

    // It fails again: Try again again.
    await tester.tap(_bar);
    await settleReceive(tester);
    _expectBar(tester, _l10n.tryAgain);

    fail = false;
    await tester.tap(_bar);
    await settleReceive(tester);
    _expectBar(tester, _l10n.share, busy: true);
    expect(find.text(_l10n.failedToGetAddress), findsNothing);

    again.complete(receiveAddress);
    await settleReceive(tester);
    _expectBar(tester, _l10n.share);
    await tester.tap(_bar);
    await tester.pump();
    expect(shared, ['bitcoin:$receiveAddress?lightning=$receiveLnurl']);
    await closeBitcoinReceive(tester);
  });

  testWidgets('Try again on the Lightning tab asks for the Lightning address',
      (tester) async {
    var fail = true;
    final world = ReceiveWorld(lnurl: () async {
      if (fail) throw Exception('no');
      return ReceiveWorld().lnurl();
    });
    await openBitcoinReceive(tester, world);
    await pickReceiveTab(tester, _l10n.receiveQrFormatLightningOnly);
    _expectBar(tester, _l10n.tryAgain);
    fail = false;
    await tester.tap(_bar);
    await settleReceive(tester);
    _expectBar(tester, _l10n.share);
    await closeBitcoinReceive(tester);
  });

  testWidgets('Done closes a wallet with no address to give', (tester) async {
    await openBitcoinReceive(
        tester,
        ReceiveWorld(
            wallet: WalletConfig(
                id: 'wallet',
                name: 'Signer',
                sparkEnabled: false,
                isSigner: true),
            kind: ColdAccountKind.signer,
            address: () async => ''));
    expect(find.byType(ReceiveQrShimmer), findsNothing,
        reason: 'it says so rather than loading for ever');
    await tester.tap(_bar);
    await settleReceive(tester);
    expect(find.byType(ConfirmReceive), findsNothing);
    await closeBitcoinReceive(tester);
  });

  testWidgets(
      'the sheets over it keep their own bars, and Share comes back when '
      'they close', (tester) async {
    await openBitcoinReceive(tester, ReceiveWorld());
    await tester.tap(find.byIcon(Icons.edit_rounded));
    await settleReceive(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(EditUsernameModalSheet), findsOneWidget);
    // The field is focused in a test with no keyboard inset: the bar stays.
    expect(find.descendant(of: _bar, matching: find.text(_l10n.saveChanges)),
        findsOneWidget);
    expect(find.descendant(of: _bar, matching: find.text(_l10n.share)),
        findsNothing);
    Navigator.of(tester.element(find.byType(EditUsernameModalSheet))).pop();
    await settleReceive(tester);
    _expectBar(tester, _l10n.share);

    await tester.tap(find.byKey(const ValueKey('receive-request-amount')));
    await settleReceive(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    expect(find.descendant(of: _bar, matching: find.text(_l10n.share)),
        findsNothing);
    Navigator.of(tester.element(find.byType(RequestAmountSheet))).pop();
    await settleReceive(tester);
    _expectBar(tester, _l10n.share);
    await closeBitcoinReceive(tester);
  });

  testWidgets('the deep link\'s sheet (its "What is this?" under it) too',
      (tester) async {
    final shared = _recordShares(tester);
    await openBitcoinReceive(tester, ReceiveWorld(), open: (context) async {
      Navigator.of(context).push(
          const ReceiveSheetPage(usd: false, name: 'receive')
              .createRoute(context));
    });
    _expectBar(tester, _l10n.share);
    await tester.tap(_bar);
    await tester.pump();
    expect(shared, hasLength(1));
    await closeBitcoinReceive(tester);
  });

  testWidgets(
      'a hardware wallet: Share on the bar, its Verify in the page, no Request '
      'amount and no chips', (tester) async {
    await openBitcoinReceive(
        tester,
        ReceiveWorld(
            wallet: WalletConfig(
                id: 'wallet',
                name: 'Ledger',
                sparkEnabled: false,
                isHardware: true,
                walletType: 'ledger',
                scriptType: 'bip84'),
            kind: ColdAccountKind.hardware));
    _expectBar(tester, _l10n.share);
    expect(find.widgetWithText(AppButton, _l10n.verifyOnLedger), findsOneWidget);
    expect(find.byKey(const ValueKey('receive-request-amount')), findsNothing);
    expect(find.text(_l10n.receiveQrFormatUnified), findsNothing);
    await closeBitcoinReceive(tester);
  });

  testWidgets(
      'on a 375 x 812 phone the plate keeps its side and it all stands above '
      'the bar', (tester) async {
    await openBitcoinReceive(tester, ReceiveWorld());
    expect(receivePlateSide(tester), closeTo(375 * 0.87, 0.5));
    final barTop = tester.getTopLeft(_bar).dy;
    expect(
        tester.getBottomLeft(find.text(_l10n.receiveQrFormatUnified)).dy,
        lessThan(barTop));
    final scroll = tester.state<ScrollableState>(find.descendant(
        of: find.byType(ConfirmReceive), matching: find.byType(Scrollable)));
    expect(scroll.position.maxScrollExtent, 0, reason: 'nothing to scroll');
    await closeBitcoinReceive(tester);
  });

  for (final (name, size, locale, scale, scrolls) in [
    ('320 x 568', const Size(320, 568), null, 1.0, false),
    ('320 x 568 in German', const Size(320, 568), const Locale('de'), 1.0, false),
    ('375 x 667', const Size(375, 667), null, 1.0, false),
    ('320 x 568 at 1.5x text', const Size(320, 568), null, 1.5, true),
  ]) {
    testWidgets('on $name the page scrolls clear of the bar', (tester) async {
      await openBitcoinReceive(tester, ReceiveWorld(),
          size: size, locale: locale, textScale: scale);
      final page = find.descendant(
          of: find.byType(ConfirmReceive), matching: find.byType(Scrollable));
      final scroll = tester.state<ScrollableState>(page);
      if (scrolls) expect(scroll.position.maxScrollExtent, greaterThan(0));
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final barTop = tester.getTopLeft(_bar).dy;
      // The last thing in the page, the chips' row.
      final lastBottom = tester
          .getBottomLeft(find.text(
              tester.element(page).l10n.receiveQrFormatLightningOnly))
          .dy;
      expect(lastBottom, lessThanOrEqualTo(barTop),
          reason: 'the bar covers nothing');
      expect(tester.takeException(), isNull);
      await closeBitcoinReceive(tester);
    });
  }
}
