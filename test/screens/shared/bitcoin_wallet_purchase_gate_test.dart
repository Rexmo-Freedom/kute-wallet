// Purchase opens Buy bitcoin. On the spending account it can always pay
// from the dollar balance, so it stays whatever the policy says about
// onramps. A savings wallet's own Purchase has nothing to pay with but an
// onramp: with none on offer the button is not drawn (founder decision,
// October 2026), and it follows the policy live.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/shared/bitcoin_wallet_actions.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

class _Policy extends ChangeNotifier implements RuntimeCapabilitiesService {
  _Policy({required this.onramps});
  bool onramps;

  void set(bool value) {
    onramps = value;
    notifyListeners();
  }

  @override
  CapabilityDecision decision(String id) => id.startsWith('onramp.') && !onramps
      ? const CapabilityDecision(allowed: false, reason: 'disabled')
      : const CapabilityDecision(allowed: true);

  @override
  bool allows(String id) => decision(id).allowed && !decision(id).comingSoon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _spending = WalletConfig(id: 'spending', name: 'Spending');
final _savings = WalletConfig(
  id: 'cold',
  name: 'Cold',
  sparkEnabled: false,
  isHardware: true,
);

Future<void> _pump(
    WidgetTester tester, _Policy policy, WalletConfig wallet) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      runtimeCapabilitiesProvider.overrideWith((ref) {
        policy.addListener(ref.notifyListeners);
        ref.onDispose(() => policy.removeListener(ref.notifyListeners));
        return policy;
      }),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BitcoinWalletPrimaryActions(wallet: wallet, source: 'test'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('spending Purchase pays from dollars even with no onramp',
      (tester) async {
    await _pump(tester, _Policy(onramps: false), _spending);
    // Dollars can pay, so the spending Purchase opens the buy itself
    // (the Move sheet, not pumped here) and is never "Buy unavailable".
    expect(find.text('Purchase Bitcoin'), findsOneWidget);
  });

  testWidgets(
      'a savings wallet Purchase always shows; with no onramp it says so',
      (tester) async {
    final policy = _Policy(onramps: true);
    await _pump(tester, policy, _savings);
    expect(find.text('Purchase Bitcoin'), findsOneWidget);
    policy.set(false);
    await tester.pumpAndSettle();
    // The door stays drawn (founder decision, October 2026)...
    expect(find.text('Purchase Bitcoin'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
    // ...and a tap opens the "no purchase providers" sheet, not a buy.
    await tester.tap(find.text('Purchase Bitcoin'));
    await tester.pumpAndSettle();
    expect(find.text('Buy unavailable'), findsOneWidget);
    expect(find.text('No purchase providers are available at the moment.'),
        findsOneWidget);
  });
}
