// The step-up PIN sheet's Cancel is the floating bar (founder, 7 November
// 2026, over "Confirm a $5.00 prediction": "when i dont want to send, the
// button should be to cancel"; pin_gate_sheet.dart). End to end through
// the step-up helper with biometrics off, so the Kute PIN sheet asks: a
// slip's Place opens it, the bar turns from the slip's button into
// Cancel, a tap on it closes the sheet with nothing placed and no error,
// and the bar is the slip's button again, the slip as it was.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/pin_gate_sheet.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/shell_bar_harness.dart';
import '../../services/support/fake_secret_store.dart';

class _QuickAuth extends AuthModel {
  _QuickAuth(FakeKeychain keychain)
      : super(store: keychain.local, syncedStore: keychain.synced);

  @override
  Future<PinCheck> checkPin(String incomingPin,
          {String rescueSource = 'pin'}) async =>
      incomingPin == '111111' ? PinCheck.match : PinCheck.mismatch;
}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          wallets: [WalletConfig(id: 'w1', name: 'Spending')],
          activeWalletId: 'w1',
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: true,
          biometricsEnabled: false,
          bitcoinElectrumNode: 'ssl://example.com:50002',
          nodeType: 'electrum',
          reviewDone: true,
        ));
}

SensitiveIntent _buy(int dollars) => PmIntents.order(
      walletId: 'w1',
      tokenId: '0xabc',
      isBuy: true,
      amountMax: BigInt.from(dollars) * BigInt.from(1000000),
      limitPrice: 0.55,
      orderType: 'fok',
      maxSlippageBps: 200,
    );

int _placed = 0;
int _declined = 0;

/// A slip in miniature: an amount it can change, a side, and its Place as
/// the bar's primary button, which asks for the step-up and places only
/// with a grant.
class _Slip extends ConsumerStatefulWidget {
  const _Slip();

  @override
  ConsumerState<_Slip> createState() => _SlipState();
}

class _SlipState extends ConsumerState<_Slip> {
  int _amount = 5;
  final String _side = 'Yes';

  Future<void> _place() async {
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: _buy(_amount),
      reason: 'Confirm a \$$_amount.00 prediction',
      amountUsd: _amount.toDouble(),
    );
    if (grant == null) {
      _declined++;
      return;
    }
    _placed++;
  }

  @override
  Widget build(BuildContext context) => AppBottomSheetContainer(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Amount \$$_amount'),
          Text('Side $_side'),
          TextButton(
            onPressed: () => setState(() => _amount++),
            child: const Text('More'),
          ),
          for (var i = 0; i < 8; i++)
            SizedBox(height: 48, child: Text('Row $i')),
          KuteBarContextScope(
            barContext: KuteBarContext.primary(
              label: 'Place prediction · \$$_amount.00',
              onPrimary: _place,
              source: 'test_slip',
              disabledLabel: null,
            ),
            child: const SizedBox(height: 72),
          ),
        ]),
      );
}

void main() {
  late FakeKeychain keychain;
  late List<(String, Map<String, Object>?)> events;
  final navKey = GlobalKey<NavigatorState>();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    keychain = FakeKeychain();
    keychain.seed('v2:wallet:w1.mnemonic', 'words');
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    _placed = 0;
    _declined = 0;
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SecretStores.debugReset();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The slip open over a page, the bar mounted as in the app.
  Future<void> pumpSlip(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    installShellBar();
    final container = ProviderContainer(overrides: [
      authModelProvider.overrideWith((ref) => _QuickAuth(keychain)),
      settingsProvider.overrideWith((ref) => _Settings()),
      aiEnabledProvider.overrideWith((_) async => true),
    ]);
    addTearDown(container.dispose);
    container.read(sessionAuthProvider.notifier).state =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: shellBarApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
    await settle(tester);
    // ignore: unawaited_futures
    showKuteModalSheet<void>(
      context: navKey.currentContext!,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _Slip(),
    );
    await settle(tester);
  }

  /// The slip's Place on the bar, with the amount raised to $6 first.
  Future<void> openPin(WidgetTester tester) async {
    await tester.tap(find.text('More'));
    await settle(tester);
    expect(barPrimaryText('Place prediction · \$6.00'), findsOneWidget);
    await tester.tap(findBarPrimary());
    await settle(tester);
    expect(find.byType(PinGateSheet), findsOneWidget);
    expect(find.text('Confirm a \$6.00 prediction'), findsOneWidget);
  }

  testWidgets(
      'while the PIN sheet is up the bar is Cancel; a tap closes it, places '
      'nothing, shows no error, and gives the slip its button back',
      (tester) async {
    await pumpSlip(tester);
    await openPin(tester);

    // The bar is the sheet's Cancel: not the slip's Place, not the pill,
    // and the sheet draws no second Cancel.
    expect(barIsUp(tester), isTrue);
    expect(barPrimaryText('Cancel'), findsOneWidget);
    expect(barPrimaryText('Place prediction · \$6.00'), findsNothing);
    expect(find.byType(KuteSalPill), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(findBarPrimary());
    await settle(tester);

    expect(find.byType(PinGateSheet), findsNothing);
    expect(_placed, 0, reason: 'Cancel must not run the action');
    expect(_declined, 1);
    // The slip as it was, its own button back on the bar.
    expect(find.text('Amount \$6'), findsOneWidget);
    expect(find.text('Side Yes'), findsOneWidget);
    expect(barIsUp(tester), isTrue);
    expect(barPrimaryText('Place prediction · \$6.00'), findsOneWidget);
    expect(barPrimaryText('Cancel'), findsNothing);
    // No error: no message, no failure event, only the existing cancel
    // events.
    expect(find.byType(SnackBar), findsNothing);
    final names = [for (final (e, _) in events) e];
    expect(names, isNot(contains('step_up_auth')));
    expect(
        events.any(
            (e) => e.$1 == 'pin_gate_result' && e.$2?['result'] == 'cancelled'),
        isTrue);
    expect(
        events.any((e) =>
            e.$1 == 'step_up_auth_denied' &&
            e.$2?['reason'] == 'pin_cancelled'),
        isTrue);

    // The person can change their mind: Place asks again.
    await tester.tap(findBarPrimary());
    await settle(tester);
    expect(find.byType(PinGateSheet), findsOneWidget);
    expect(barPrimaryText('Cancel'), findsOneWidget);
  });

  testWidgets('the right PIN still approves, and the bar is the slip\'s again',
      (tester) async {
    await pumpSlip(tester);
    await openPin(tester);
    for (final d in '111111'.split('')) {
      await tester.tap(find.descendant(
          of: find.byType(PinGateSheet), matching: find.text(d)));
      await tester.pump();
    }
    await settle(tester);

    expect(find.byType(PinGateSheet), findsNothing);
    expect(_placed, 1);
    expect(_declined, 0);
    expect(barPrimaryText('Place prediction · \$6.00'), findsOneWidget);
  });
}
