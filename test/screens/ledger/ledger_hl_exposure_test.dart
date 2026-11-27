// LEVERAGE IS BLOCKED on the Ledger order path too (hl_exposure_rule.dart):
// the real `runLedgerHlMarketOrder`, driven from a widget, refuses an add
// to (or a flip of) a position held above 1x or in cross, and an account
// it cannot read, before any device prompt (no builder, leverage or order
// sheet); an allowed reduction reaches the device's review as a
// reduce-only order with no leverage write before it. Nothing is signed:
// the review sheet is only looked at, never approved.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'package:kute/screens/ledger/ledger_approval_sheet.dart';
import 'package:kute/services/hardware/signing_clarity.dart' show LedgerActionKind;
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

const _walletId = 'ledger-1';
const _address = '0x14791697260E4c9A71f18484C9f997B308e59325';

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

HlPerpPosition _short({required bool cross}) => HlPerpPosition(
      coin: 'BTC',
      szi: -500 / 60000,
      entryPx: 60000,
      positionValue: 500,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: 50,
      leverageType: cross ? 'cross' : 'isolated',
      leverageValue: 10,
      maxLeverage: 40,
    );

LedgerHlAccount _account(List<HlPerpPosition>? positions) => LedgerHlAccount(
      walletId: _walletId,
      address: _address,
      account: positions == null
          ? null
          : HlAccountSnapshot(
              accountValue: 100,
              withdrawable: 100,
              totalMarginUsed: 50,
              positions: positions,
              spotBalances: const []),
    );

/// The venue the order path reads the market's dex from right before the
/// leverage write: [positions] (null: the read fails).
class _Venue extends HyperliquidModel {
  _Venue(this.positions);
  final List<HlPerpPosition>? positions;
  final reads = <String>[];

  @override
  Future<HlAccountSnapshot> getDexClearinghouse(
      String address, String dex) async {
    reads.add(dex);
    final p = positions;
    if (p == null) throw StateError('info failed');
    return HlAccountSnapshot(
        accountValue: 100,
        withdrawable: 100,
        totalMarginUsed: 50,
        positions: p,
        spotBalances: const [],
        positionDexes: {dex});
  }
}

class _Policy extends Fake implements RuntimeCapabilitiesService {
  @override
  RuntimeCapabilities? get snapshot => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  Future<void> ensureAllowed(String id, {Duration maxAge = Duration.zero}) async {}
  @override
  void ensureLeverageAllowed(int leverage) {}
}

/// Runs the Ledger market order of [usd] on the [isBuy] side against
/// [account]; the outcome (or error) lands in the returned record.
Future<({Object? error, bool done})> _run(WidgetTester tester,
    {required LedgerHlAccount account,
    required bool isBuy,
    required double usd,
    _Venue? venue}) async {
  Object? error;
  var done = false;
  final v = venue ?? _Venue(account.account?.positions);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ledgerHyperliquidModelProvider.overrideWithValue(v),
      ledgerIdentityProvider.overrideWith((ref, id) => const LedgerIdentity(
          walletId: _walletId, evmAddress: _address, evmVerifiedAtMs: 1)),
      ledgerHlAccountProvider.overrideWith((ref, id) async => account),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(builder: (context, ref, _) {
          // Loaded, as the ticket has it before its button is live.
          ref.watch(ledgerHlAccountProvider(_walletId));
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                try {
                  await runLedgerHlMarketOrder(context, ref,
                      walletId: _walletId,
                      market: _btc,
                      isBuy: isBuy,
                      marginUsd: usd);
                } catch (e) {
                  error = e;
                } finally {
                  done = true;
                }
              },
              child: const Text('go'),
            ),
          );
        }),
      ),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('go'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (error: error, done: done);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    RuntimeCapabilitiesService.debugInstance = _Policy();
  });
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final cross in [false, true]) {
    final kind = cross ? '10x cross' : '10x isolated';
    testWidgets('a \$1,000 buy against a $kind \$500 short: refused, no prompt',
        (tester) async {
      final r = await _run(tester,
          account: _account([_short(cross: cross)]), isBuy: true, usd: 1000);
      expect(r.error, isA<HlExposureRefusedException>());
      expect(find.byType(LedgerApprovalSheet), findsNothing);
    });

    testWidgets('an add to a $kind short: refused, no prompt', (tester) async {
      final r = await _run(tester,
          account: _account([_short(cross: cross)]), isBuy: false, usd: 100);
      expect(r.error, isA<HlExposureRefusedException>());
      expect(find.byType(LedgerApprovalSheet), findsNothing);
    });

    testWidgets(
        'a \$200 buy against a $kind short: the device reviews a reduce-only '
        'order, with no leverage write first', (tester) async {
      await _run(tester,
          account: _account([_short(cross: cross)]), isBuy: true, usd: 200);
      final sheets = find.byType(LedgerApprovalSheet, skipOffstage: false);
      expect(sheets, findsOneWidget);
      final intent =
          tester.widget<LedgerApprovalSheet>(sheets).request.intent;
      expect(intent.kind, LedgerActionKind.hlOrder);
      expect(intent.param<bool>('reduceOnly'), isTrue);
      expect(intent.param<bool>('isBuy'), isTrue);
      // The sheet is only looked at: whatever it could not draw here is
      // not this test's concern.
      tester.takeException();
    });
  }

  testWidgets(
      'a 10x cross short opened elsewhere since the ticket read the account '
      'flat: the fresh read before the leverage write refuses the add, no '
      'prompt', (tester) async {
    final venue = _Venue([_short(cross: true)]);
    final r = await _run(tester,
        account: _account(const []), isBuy: false, usd: 100, venue: venue);
    expect(r.error, isA<HlExposureRefusedException>());
    expect(venue.reads, ['']);
    // No leverage sheet, no order sheet.
    expect(find.byType(LedgerApprovalSheet, skipOffstage: false),
        findsNothing);
  });

  testWidgets(
      'the fresh read fails: refused as unknown before the leverage write',
      (tester) async {
    final r = await _run(tester,
        account: _account(const []),
        isBuy: true,
        usd: 100,
        venue: _Venue(null));
    expect(
        r.error,
        isA<HlExposureRefusedException>().having(
            (e) => e.refusal, 'refusal', HlExposureRefusal.positionUnknown));
    expect(find.byType(LedgerApprovalSheet, skipOffstage: false),
        findsNothing);
  });

  testWidgets('an account the Ledger could not read: refused, no prompt',
      (tester) async {
    final r = await _run(tester, account: _account(null), isBuy: true, usd: 100);
    expect(
        r.error,
        isA<HlExposureRefusedException>().having(
            (e) => e.refusal, 'refusal', HlExposureRefusal.positionUnknown));
    expect(find.byType(LedgerApprovalSheet), findsNothing);
  });

  test('the Ledger reads know a builder dex only when it was read', () {
    const xyz = HlMarket(
      coin: 'xyz:TSLA',
      wireCoin: 'xyz:TSLA',
      assetId: 110000,
      kind: HlMarketKind.perp,
      szDecimals: 3,
      maxLeverage: 10,
      onlyIsolated: true,
      markPx: 300,
      midPx: 300,
      prevDayPx: 300,
      dayNtlVlm: 0,
      dex: 'xyz',
    );
    expect(ledgerHlHeldPosition(_account(const []), xyz).known, isFalse);
    expect(ledgerHlHeldPosition(null, _btc).known, isFalse);
    expect(ledgerHlHeldPosition(_account(const []), _btc).known, isTrue);
  });
}
