// The error line: only when the connection reads slow, only when the order
// is proven not sent. No banner, no VPN. Unknown stays unknown.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/polymarket/components/polymarket_error_copy.dart';
import 'package:kute/services/http/connection_health.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/order_connection.dart';
import 'package:kute/services/polymarket/placement_waits.dart';

void main() {
  final l10n = l10nForLanguage('en');
  late ConnectionHealth slow;
  late ConnectionHealth fine;
  setUp(() {
    slow = ConnectionHealth()..debugMakeSlow();
    fine = ConnectionHealth();
  });

  test('slow and proven not sent shows the new line', () {
    for (final e in <Object>[
      const PolymarketOrderNeverSent(),
      TimeoutException('book read'),
      const SocketException('offline'),
      const PolymarketSetupIncomplete(cause: SocketException('offline')),
    ]) {
      expect(polymarketSlowConnectionLine(l10n, e, health: slow),
          l10n.betConnectionSlowNotSent,
          reason: '$e');
    }
  });

  test('a healthy connection never gets the line', () {
    expect(
        polymarketSlowConnectionLine(l10n, const PolymarketOrderNeverSent(),
            health: fine),
        isNull);
  });

  test('unknown is never "did not go through", however slow', () {
    for (final e in <Object>[
      const PolymarketOrderOutcomeUnknown(orderId: '0x1', lookedUp: true),
      const PendingPolymarketOrder(),
      const PolymarketOrderCheckUnavailable(),
      const PolymarketOrderInProgress(),
      const ResolvedPolymarketOrder(accepted: true),
    ]) {
      expect(polymarketSlowConnectionLine(l10n, e, health: slow), isNull,
          reason: '$e');
    }
  });

  test('a refusal is the venue\'s answer, not the connection', () {
    expect(polymarketSlowConnectionLine(l10n, StateError('x'), health: slow),
        isNull);
    expect(
        polymarketSlowConnectionLine(
            l10n, const PolymarketSetupIncomplete(timedOut: true),
            health: slow),
        isNull);
  });

  test('the line is short and blames no VPN in any language', () {
    for (final f in Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))) {
      final line = (jsonDecode(f.readAsStringSync())
          as Map)['betConnectionSlowNotSent'] as String?;
      expect(line, isNotNull, reason: f.path);
      expect(line!.toLowerCase(), isNot(contains('vpn')), reason: f.path);
      expect(line.length, lessThan(90), reason: f.path);
    }
  });

  testWidgets(
      'proven not sent on a healthy connection: the sell copy says '
      'Polymarket could not be reached', (tester) async {
    late String line;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        line = polymarketErrorCopy(context, const PolymarketOrderNeverSent());
        return const SizedBox();
      }),
    ));
    await tester.pump();
    expect(line, l10n.betConnectionUnavailable);
  });

  test('the analytics carry a boolean and a count, nothing else', () {
    PolymarketOrderAttempts.last = 3;
    final p = polymarketOrderConnectionParams();
    expect(p.keys.toSet(), {'connection_slow', 'attempts'});
    expect(p['connection_slow'], isA<bool>());
    expect(p['attempts'], 3);
    PolymarketOrderAttempts.last = 0;
  });
}
