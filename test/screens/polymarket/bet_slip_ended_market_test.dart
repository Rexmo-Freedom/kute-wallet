// A slip never opens on a market that is already over (data audit: seven
// slips opened on ended markets): a short round past its end, or an event
// Gamma marks closed. The person is told instead, and nothing is tracked
// as an opened slip.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

const _outcomes = [
  PolymarketOutcome(name: 'Up', price: 0.5, tokenId: 'up-token'),
  PolymarketOutcome(name: 'Down', price: 0.5, tokenId: 'down-token'),
];

Future<void> _open(WidgetTester tester,
    {required DateTime endAt, PolymarketEvent? event}) async {
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => BetSlipSheet.show(
                context,
                marketQuestion: 'Bitcoin Up or Down - 5 minutes',
                marketSlug: 'btc-updown-5m-1760356800',
                outcomes: _outcomes,
                marketEndAt: endAt,
                event: event,
                source: 'test',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a short round past its end never opens a slip',
      (tester) async {
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    addTearDown(() => TrackingService.debugTrackObserver = null);

    await _open(tester,
        endAt: DateTime.now().subtract(const Duration(seconds: 20)));

    expect(find.byType(BetSlipSheet), findsNothing);
    expect(find.text('This market is no longer available.'), findsOneWidget);
    expect(events, isNot(contains('polymarket_bet_slip_opened')));
    // Let the notice time out.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an event marked closed never opens a slip', (tester) async {
    await _open(tester,
        endAt: DateTime.now().add(const Duration(minutes: 3)),
        event: const PolymarketEvent(
            id: '1',
            slug: 'btc-updown-5m-1760356800',
            title: 'Bitcoin Up or Down',
            volume: 0,
            liquidity: 0,
            category: 'crypto',
            conditionId: '',
            outcomes: [],
            closed: true));

    expect(find.byType(BetSlipSheet), findsNothing);
    expect(find.text('This market is no longer available.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
  });
}
