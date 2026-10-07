import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/spark_contacts_fixtures.dart';

class _Sdk extends Mock implements BreezSdk {}

class _Wrapper extends Mock implements BreezSdkSpark {}

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: false,
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

class _MemoryStore implements ContactsMigrationStore {
  final seeded = <String>{};
  @override
  Future<bool> isSeeded(String walletId) async => seeded.contains(walletId);
  @override
  Future<void> markSeeded(String walletId) async => seeded.add(walletId);
}

/// An in-memory stand-in for the SDK's contacts table, with a clock in
/// whole seconds as the SDK keeps it.
class _ContactsTable {
  final rows = <Contact>[];
  int now = 1000;
  int _next = 0;
  bool failList = false;

  void wire(_Sdk sdk) {
    when(() => sdk.listContacts(request: any(named: 'request')))
        .thenAnswer((_) async {
      if (failList) throw const SdkError.generic('storage');
      // The SDK orders by name.
      return [...rows]..sort((a, b) => a.name.compareTo(b.name));
    });
    when(() => sdk.addContact(request: any(named: 'request')))
        .thenAnswer((inv) async {
      final r = inv.namedArguments[#request] as AddContactRequest;
      final c = Contact(
        id: 'id-${(_next++).toString().padLeft(4, '0')}',
        name: r.name,
        paymentIdentifier: r.paymentIdentifier,
        createdAt: BigInt.from(now),
        updatedAt: BigInt.from(now),
      );
      rows.add(c);
      return c;
    });
    when(() => sdk.updateContact(request: any(named: 'request')))
        .thenAnswer((inv) async {
      final r = inv.namedArguments[#request] as UpdateContactRequest;
      final i = rows.indexWhere((c) => c.id == r.id);
      final c = Contact(
        id: r.id,
        name: r.name,
        paymentIdentifier: r.paymentIdentifier,
        createdAt: rows[i].createdAt,
        updatedAt: BigInt.from(now),
      );
      rows[i] = c;
      return c;
    });
  }

  Contact seedRemote(String address, int at) {
    final c = Contact(
      id: 'remote-$address',
      name: address,
      paymentIdentifier: address,
      createdAt: BigInt.from(at),
      updatedAt: BigInt.from(at),
    );
    rows.add(c);
    return c;
  }
}

final _txs = StateProvider<List<SparkTransaction>>((_) => const []);

void main() {
  late _Sdk sdk;
  late _Wrapper wrapper;
  late _MemoryStore store;
  late _ContactsTable table;
  late StreamController<void> synced;
  late bool hasSynced;
  late ProviderContainer container;

  final history = [
    lnSend('carol@kute.money', 3000, DateTime(2026, 9, 3)),
    lnSend('alice@getalby.com', 1000, DateTime(2026, 9, 1)),
    lnSend('BOB@walletofsatoshi.com', 2000, DateTime(2026, 9, 2)),
    lnSend('bob@walletofsatoshi.com', 500, DateTime(2026, 8, 1)),
    lnSend(null, 9000, DateTime(2026, 9, 4)), // one-time invoice
    lnSend('dave@kute.money', 7000, DateTime(2026, 9, 5),
        type: PaymentType.receive),
  ];

  setUpAll(() {
    registerFallbackValue(const ListContactsRequest());
    registerFallbackValue(
        const AddContactRequest(name: 'n', paymentIdentifier: 'a@b.c'));
    registerFallbackValue(const UpdateContactRequest(
        id: 'i', name: 'n', paymentIdentifier: 'a@b.c'));
  });

  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        breezSDKProvider.overrideWith((_) async => wrapper),
        contactsMigrationStoreProvider.overrideWithValue(store),
        mergedTransactionsProvider.overrideWith((ref) => Transaction(
              bitcoinTransactions: const [],
              sparkTransactions: ref.watch(_txs),
              sparkUnclaimedDeposits: const [],
            )),
      ]);

  setUp(() {
    sdk = _Sdk();
    wrapper = _Wrapper();
    store = _MemoryStore();
    table = _ContactsTable()..wire(sdk);
    synced = StreamController<void>.broadcast();
    hasSynced = true;
    when(() => wrapper.instance).thenAnswer((_) => sdk);
    when(() => wrapper.hasSynced).thenAnswer((_) => hasSynced);
    when(() => wrapper.syncedStream).thenAnswer((_) => synced.stream);
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    await synced.close();
  });

  List<RecentRecipient> rows(ProviderContainer c) => recentRecipientsFor(
        sparkSource: true,
        contacts: c.read(sparkContactsProvider),
        txs: c.read(mergedTransactionsProvider).sparkTransactions,
      );

  group('migration', () {
    test('seeds the history-derived addresses once, keeping their order',
        () async {
      container.read(_txs.notifier).state = history;
      final contacts = await container.read(sparkContactsProvider.future);

      expect(contacts.map((c) => c.paymentIdentifier), hasLength(3));
      verify(() => sdk.addContact(request: any(named: 'request'))).called(3);
      expect(store.seeded, {'spending'});
      // Seeded in one second: order still follows the history.
      expect(rows(container).map((r) => r.address), [
        'carol@kute.money',
        'BOB@walletofsatoshi.com',
        'alice@getalby.com',
      ]);
      expect(rows(container).first.sats, 3000);

      // A later session (new container, same device) does not seed again.
      container.dispose();
      container = makeContainer();
      container.read(_txs.notifier).state = history;
      await container.read(sparkContactsProvider.future);
      verifyNever(() => sdk.addContact(request: any(named: 'request')));
      expect(table.rows, hasLength(3));
    });

    test('waits for the first sync, then seeds', () async {
      hasSynced = false;
      container.read(_txs.notifier).state = history;
      expect(await container.read(sparkContactsProvider.future), isEmpty);
      verifyNever(() => sdk.addContact(request: any(named: 'request')));
      expect(store.seeded, isEmpty);

      synced.add(null);
      await pumpEventQueue();
      expect(store.seeded, {'spending'});
      expect(container.read(sparkContactsProvider).value, hasLength(3));
    });

    test('waits for the history, then seeds', () async {
      expect(await container.read(sparkContactsProvider.future), isEmpty);
      expect(store.seeded, isEmpty);

      container.read(_txs.notifier).state = history;
      await pumpEventQueue();
      expect(store.seeded, {'spending'});
      expect(container.read(sparkContactsProvider).value, hasLength(3));
    });

    test('skips addresses another device already added', () async {
      table.seedRemote('alice@getalby.com', 900);
      container.read(_txs.notifier).state = history;
      await container.read(sparkContactsProvider.future);
      final added = verify(() =>
              sdk.addContact(request: captureAny(named: 'request')))
          .captured
          .cast<AddContactRequest>()
          .map((r) => r.paymentIdentifier);
      expect(added, ['BOB@walletofsatoshi.com', 'carol@kute.money']);
      expect(table.rows, hasLength(3));
    });

    test('a failed add leaves the migration open for the next try',
        () async {
      when(() => sdk.addContact(request: any(named: 'request')))
          .thenThrow(const SdkError.generic('offline'));
      container.read(_txs.notifier).state = history;
      await container.read(sparkContactsProvider.future);
      expect(store.seeded, isEmpty);
    });
  });

  group('recordSent', () {
    test('adds a new Lightning address, named after itself', () async {
      await container.read(sparkContactsProvider.future);
      await container
          .read(sparkContactsProvider.notifier)
          .recordSent(' erin@kute.money ');
      final c = table.rows.single;
      expect(c.name, 'erin@kute.money');
      expect(c.paymentIdentifier, 'erin@kute.money');
      expect(container.read(sparkContactsProvider).value, [c]);
      // No payment row yet: the date is the contact's, no amount.
      final r = rows(container).single;
      expect(r.sats, isNull);
      expect(r.when, DateTime.fromMillisecondsSinceEpoch(1000 * 1000));
    });

    test('bumps an existing contact to the top instead of adding', () async {
      container.read(_txs.notifier).state = history;
      await container.read(sparkContactsProvider.future);
      expect(rows(container).last.address, 'alice@getalby.com');

      table.now = 2000;
      await container
          .read(sparkContactsProvider.notifier)
          .recordSent('Alice@GetAlby.com');
      verify(() => sdk.updateContact(request: any(named: 'request')))
          .called(1);
      expect(table.rows, hasLength(3));
      expect(rows(container).first.address, 'alice@getalby.com');
    });

    test('seeds the history first so it never outranks the new send',
        () async {
      hasSynced = false;
      container.read(_txs.notifier).state = history;
      await container.read(sparkContactsProvider.future);
      await container
          .read(sparkContactsProvider.notifier)
          .recordSent('erin@kute.money');
      expect(store.seeded, {'spending'});
      expect(rows(container).first.address, 'erin@kute.money');
      expect(table.rows, hasLength(4));
    });

    test('ignores destinations that are not Lightning addresses', () async {
      await container.read(sparkContactsProvider.future);
      final n = container.read(sparkContactsProvider.notifier);
      await n.recordSent('lnbc10u1p0example');
      await n.recordSent('bc1qexampleaddress');
      await n.recordSent('');
      verifyNever(() => sdk.addContact(request: any(named: 'request')));
    });
  });

  group('fallback', () {
    test('a failing contacts call falls back to the history list', () async {
      table.failList = true;
      container.read(_txs.notifier).state = history;
      await expectLater(
          container.read(sparkContactsProvider.future), throwsA(anything));
      expect(container.read(sparkContactsProvider).hasError, isTrue);
      expect(rows(container).map((r) => r.address), [
        'carol@kute.money',
        'BOB@walletofsatoshi.com',
        'alice@getalby.com',
      ]);
    });

    test('an SDK that is not connected falls back to the history list',
        () async {
      when(() => wrapper.instance).thenAnswer((_) => null);
      container.read(_txs.notifier).state = history;
      await expectLater(
          container.read(sparkContactsProvider.future), throwsA(anything));
      expect(rows(container), hasLength(3));
    });
  });
}
