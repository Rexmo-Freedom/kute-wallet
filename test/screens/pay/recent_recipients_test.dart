import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/spark_contacts_fixtures.dart';

void main() {
  final history = [
    lnSend('alice@getalby.com', 1000, DateTime(2026, 9, 1)),
    lnSend('bob@walletofsatoshi.com', 2000, DateTime(2026, 9, 2)),
    lnSend(null, 9000, DateTime(2026, 9, 4)), // one-time invoice
  ];

  group('Send screen "Recent recipients"', () {
    test('reads SDK contacts, newest updatedAt first, up to five', () {
      final contacts = [
        for (var i = 0; i < 7; i++) contact('user$i@kute.money', 100 + i),
      ];
      final rows = recentRecipientsFor(
        sparkSource: true,
        contacts: AsyncData(contacts),
        txs: history,
      );
      expect(rows.map((r) => r.address), [
        'user6@kute.money',
        'user5@kute.money',
        'user4@kute.money',
        'user3@kute.money',
        'user2@kute.money',
      ]);
    });

    test('amount and date come from the last payment to the address', () {
      final rows = recentRecipientsFor(
        sparkSource: true,
        contacts: AsyncData([
          contact('Bob@WalletOfSatoshi.com', 500),
          contact('erin@kute.money', 400),
        ]),
        txs: history,
      );
      expect(rows.first.address, 'Bob@WalletOfSatoshi.com');
      expect(rows.first.sats, 2000);
      expect(rows.first.when, DateTime(2026, 9, 2));
      // No payment to it here: the contact's own date, no amount.
      expect(rows.last.sats, isNull);
      expect(rows.last.when, DateTime.fromMillisecondsSinceEpoch(400 * 1000));
    });

    test('one row per address even if two devices added it', () {
      final rows = recentRecipientsFor(
        sparkSource: true,
        contacts: AsyncData([
          contact('alice@getalby.com', 300, id: 'a'),
          contact('ALICE@getalby.com', 200, id: 'b'),
        ]),
        txs: const [],
      );
      expect(rows.map((r) => r.address), ['alice@getalby.com']);
    });

    test('falls back to the history while loading, on error, or empty', () {
      for (final state in <AsyncValue<List<Contact>>?>[
        null,
        const AsyncLoading(),
        AsyncError(StateError('sdk'), StackTrace.empty),
        const AsyncData([]),
      ]) {
        final rows = recentRecipientsFor(
            sparkSource: true, contacts: state, txs: history);
        expect(rows.map((r) => r.address),
            ['bob@walletofsatoshi.com', 'alice@getalby.com'],
            reason: '$state');
        expect(rows.first.sats, 2000);
      }
    });

    test('a cold source shows nothing', () {
      expect(
        recentRecipientsFor(
          sparkSource: false,
          contacts: AsyncData([contact('alice@getalby.com', 100)]),
          txs: history,
        ),
        isEmpty,
      );
    });
  });

  group('the history-derived list', () {
    test('keeps Lightning addresses only, newest payment, one per address',
        () {
      final rows = recentRecipientsFromHistory(lastLnAddressSends([
        ...history,
        lnSend('ALICE@getalby.com', 50, DateTime(2026, 8, 1)),
        lnSend('carol@kute.money', 70, DateTime(2026, 9, 9),
            type: PaymentType.receive),
      ]));
      expect(rows.map((r) => r.address),
          ['bob@walletofsatoshi.com', 'alice@getalby.com']);
    });
  });

  testWidgets('a row with a date and no amount shows just the date',
      (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: SendToListRow(
            colors: AppColorsExtension.light(),
            leading: const Icon(Icons.person_rounded),
            title: 'erin@kute.money',
            trailingSubtitle: 'Oct 5',
            onTap: () {},
          ),
        ),
      ),
    ));
    expect(find.text('erin@kute.money'), findsOneWidget);
    expect(find.text('Oct 5'), findsOneWidget);
  });
}
