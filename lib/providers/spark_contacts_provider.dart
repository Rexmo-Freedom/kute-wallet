import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/transactions_model.dart'
    show SparkTransaction, TransactionType;
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;

// The spending wallet's contacts, kept by the Breez SDK.
//
// The SDK stores contacts in the wallet's own database and, with the
// default config the app uses (real-time sync on), syncs them to every
// device running the same wallet. A contact is a name plus a payment
// identifier, and the SDK only accepts a Lightning address
// (user@domain) as the identifier.
//
// The Send screen's "Recent recipients" list reads from here. The app
// has no naming step, so a contact's name is its Lightning address.
// A successful Lightning-address send adds the recipient, or bumps its
// `updatedAt` so it reads as the most recently used.

/// How many rows "Recent recipients" shows.
const int kRecentRecipientsLimit = 5;

/// The SDK rejects contact names longer than 100 bytes.
const int _kContactNameMax = 100;

/// One row of "Recent recipients". [sats] is null when no sent payment
/// to [address] is in the history, and the row then shows no amount.
typedef RecentRecipient = ({String address, int? sats, DateTime when});

/// The last sent payment to one Lightning address.
typedef LnAddressSend = ({String address, int sats, DateTime when});

/// Every Lightning address this history paid, newest payment first, one
/// entry per address (case-insensitive), keyed by the lower-cased
/// address. LNURL-pay payments carry the address; one-time invoices and
/// on-chain outputs are not reusable destinations and never appear.
Map<String, LnAddressSend> lastLnAddressSends(
    Iterable<SparkTransaction> txs) {
  final sent = txs.where((t) => t.type == TransactionType.sent).toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final out = <String, LnAddressSend>{};
  for (final t in sent) {
    final d = t.details?.details;
    if (d is! PaymentDetails_Lightning) continue;
    final address = d.lnurlPayInfo?.lnAddress?.trim() ?? '';
    if (address.isEmpty) continue;
    out.putIfAbsent(address.toLowerCase(),
        () => (address: address, sats: t.amountSats, when: t.timestamp));
  }
  return out;
}

/// The list as the app derived it before SDK contacts: the last few
/// Lightning addresses paid, newest first.
List<RecentRecipient> recentRecipientsFromHistory(
    Map<String, LnAddressSend> lastSends,
    {int limit = kRecentRecipientsLimit}) {
  return [
    for (final s in lastSends.values.take(limit))
      (address: s.address, sats: s.sats, when: s.when),
  ];
}

DateTime _secondsToDate(BigInt secs) =>
    DateTime.fromMillisecondsSinceEpoch(secs.toInt() * 1000);

/// Contacts to rows: newest `updatedAt` first, one row per identifier
/// (a contact added on two devices before they synced shows once), up
/// to [limit]. Amount and date come from the last sent payment to the
/// identifier; without one, the date is the contact's `updatedAt` and
/// there is no amount.
///
/// `updatedAt` is in whole seconds, so contacts written in the same
/// second tie (the migration seeds several at once, and a send right
/// after it can land in that second too). Ties go first to a contact
/// with no sent payment in the history (a send whose payment row has
/// not landed yet), then to the newer last payment, then to the newer
/// id (UUID v7, time ordered).
List<RecentRecipient> recentRecipientsFromContacts(
  List<Contact> contacts,
  Map<String, LnAddressSend> lastSends, {
  int limit = kRecentRecipientsLimit,
}) {
  DateTime? lastPaid(Contact c) =>
      lastSends[c.paymentIdentifier.trim().toLowerCase()]?.when;
  final sorted = [...contacts]..sort((a, b) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      final pa = lastPaid(a);
      final pb = lastPaid(b);
      if (pa == null && pb != null) return -1;
      if (pb == null && pa != null) return 1;
      if (pa != null && pb != null) {
        final byPaid = pb.compareTo(pa);
        if (byPaid != 0) return byPaid;
      }
      return b.id.compareTo(a.id);
    });
  final seen = <String>{};
  final out = <RecentRecipient>[];
  for (final c in sorted) {
    final address = c.paymentIdentifier.trim();
    if (address.isEmpty || !seen.add(address.toLowerCase())) continue;
    final last = lastSends[address.toLowerCase()];
    out.add(last != null
        ? (address: address, sats: last.sats, when: last.when)
        : (address: address, sats: null, when: _secondsToDate(c.updatedAt)));
    if (out.length >= limit) break;
  }
  return out;
}

/// What "Recent recipients" shows for the picked source. A cold or
/// on-chain source gets nothing. A Spark source reads the SDK contacts;
/// while they load, when the SDK is not ready or the call failed, or
/// before the first contact exists, it falls back to the history-derived
/// list so the section never disappears.
List<RecentRecipient> recentRecipientsFor({
  required bool sparkSource,
  required AsyncValue<List<Contact>>? contacts,
  required Iterable<SparkTransaction> txs,
}) {
  if (!sparkSource) return const [];
  final lastSends = lastLnAddressSends(txs);
  final list = contacts == null || contacts.hasError
      ? null
      : contacts.valueOrNull;
  if (list == null || list.isEmpty) {
    return recentRecipientsFromHistory(lastSends);
  }
  return recentRecipientsFromContacts(list, lastSends);
}

/// A destination worth keeping as a contact: a Lightning address. The
/// SDK accepts nothing else, and invoices or on-chain outputs are one
/// time.
bool isReusableLnAddress(String value) {
  final v = value.trim();
  final at = v.indexOf('@');
  return at > 0 && at < v.length - 1 && !v.contains(RegExp(r'\s'));
}

String contactNameFor(String address) {
  final a = address.trim();
  return a.length <= _kContactNameMax ? a : a.substring(0, _kContactNameMax);
}

/// Whether this device already seeded SDK contacts from the payment
/// history, per spending wallet.
abstract class ContactsMigrationStore {
  Future<bool> isSeeded(String walletId);
  Future<void> markSeeded(String walletId);
}

class HiveContactsMigrationStore implements ContactsMigrationStore {
  static const _box = 'settings';
  static String _key(String walletId) => 'spark_contacts_seeded_v1_$walletId';

  Future<Box<dynamic>> _open() async =>
      Hive.isBoxOpen(_box) ? Hive.box(_box) : await Hive.openBox(_box);

  @override
  Future<bool> isSeeded(String walletId) async =>
      (await _open()).get(_key(walletId)) == true;

  @override
  Future<void> markSeeded(String walletId) async =>
      (await _open()).put(_key(walletId), true);
}

final contactsMigrationStoreProvider =
    Provider<ContactsMigrationStore>((ref) => HiveContactsMigrationStore());

final sparkContactsProvider =
    AsyncNotifierProvider<SparkContactsNotifier, List<Contact>>(
        SparkContactsNotifier.new);

class SparkContactsNotifier extends AsyncNotifier<List<Contact>> {
  BreezSdk? _sdk;
  String? _walletId;
  bool _synced = false;
  bool _seeded = false;
  Future<bool>? _seeding;

  @override
  Future<List<Contact>> build() async {
    _sdk = null;
    _walletId = null;
    _synced = false;
    _seeded = false;
    _seeding = null;
    final walletId = ref
        .watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
    final wrapper = await ref.watch(breezSDKProvider.future);
    final sdk = wrapper.instance;
    if (walletId == null || walletId.isEmpty || sdk == null) {
      throw StateError('The spending wallet is not connected.');
    }
    _sdk = sdk;
    _walletId = walletId;
    _synced = wrapper.hasSynced;

    // Contacts from the wallet's other devices land with a sync.
    final sub = wrapper.syncedStream.listen((_) {
      if (!identical(_sdk, sdk)) return;
      _synced = true;
      unawaited(_maybeSeed().then((_) => refresh()));
    });
    ref.onDispose(sub.cancel);
    // The history the seed reads from fills in after connect.
    ref.listen(mergedTransactionsProvider, (_, __) {
      unawaited(_maybeSeed().then((seededNow) {
        if (seededNow) return refresh();
      }));
    });

    await _maybeSeed();
    return _list(sdk);
  }

  Future<List<Contact>> _list(BreezSdk sdk) =>
      sdk.listContacts(request: const ListContactsRequest());

  /// Re-reads the contacts. Failures surface as an error state, which
  /// the Send screen answers with the history-derived list.
  Future<void> refresh() async {
    final sdk = _sdk;
    if (sdk == null) return;
    try {
      final list = await _list(sdk);
      if (!identical(sdk, _sdk)) return;
      final prev = state.valueOrNull;
      if (prev != null && !state.hasError && listEquals(prev, list)) return;
      state = AsyncData(list);
    } catch (e, st) {
      if (identical(sdk, _sdk)) state = AsyncError(e, st);
    }
  }

  /// One-time migration: seed contacts from the Lightning addresses the
  /// history paid (the list the app showed before), so the section is
  /// not empty after the update. Waits for the SDK's first sync, which
  /// already carries contacts other devices added, so a second device
  /// does not add them twice. Marked done only once every address is
  /// added (or rejected by the SDK as not a Lightning address); until
  /// then it retries on the next sync or history change.
  ///
  /// Completes with true when this call added the seed.
  Future<bool> _maybeSeed() {
    if (_seeded || !_synced || _sdk == null) return Future.value(false);
    return _seeding ??= _seed().whenComplete(() => _seeding = null);
  }

  Future<bool> _seed() async {
    final sdk = _sdk;
    final walletId = _walletId;
    if (sdk == null || walletId == null) return false;
    try {
      final store = ref.read(contactsMigrationStoreProvider);
      if (await store.isSeeded(walletId)) {
        if (identical(sdk, _sdk)) _seeded = true;
        return false;
      }
      final derived = recentRecipientsFromHistory(lastLnAddressSends(
          ref.read(mergedTransactionsProvider).sparkTransactions));
      if (derived.isEmpty) return false;
      final existing = await _list(sdk);
      final known = {
        for (final c in existing) c.paymentIdentifier.trim().toLowerCase()
      };
      var complete = true;
      // Oldest first, so creation order (the ids) matches the history.
      for (final r in derived.reversed) {
        if (!known.add(r.address.toLowerCase())) continue;
        try {
          await sdk.addContact(
              request: AddContactRequest(
                  name: contactNameFor(r.address),
                  paymentIdentifier: r.address));
        } on SdkError_InvalidInput {
          // Not a Lightning address to the SDK: nothing to keep.
        } catch (_) {
          complete = false;
        }
      }
      if (!complete || !identical(sdk, _sdk)) return false;
      await store.markSeeded(walletId);
      _seeded = true;
      return true;
    } catch (_) {
      // Retried on the next sync or history change.
      return false;
    }
  }

  /// After a successful Lightning-address send: add the recipient as a
  /// contact, or bump the existing one so it reads as the most recently
  /// used. Best effort; a failure never touches the send.
  Future<void> recordSent(String address) async {
    final id = address.trim();
    if (!isReusableLnAddress(id)) return;
    try {
      await future;
      final sdk = _sdk;
      if (sdk == null) return;
      // A send means the SDK is up; seed first so the history's older
      // recipients never outrank this one.
      _synced = true;
      await _maybeSeed();
      final matches = (await _list(sdk))
          .where((c) => c.paymentIdentifier.trim().toLowerCase() ==
              id.toLowerCase())
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (matches.isEmpty) {
        await sdk.addContact(
            request: AddContactRequest(
                name: contactNameFor(id), paymentIdentifier: id));
      } else {
        final c = matches.first;
        await sdk.updateContact(
            request: UpdateContactRequest(
                id: c.id, name: c.name, paymentIdentifier: c.paymentIdentifier));
      }
      await refresh();
    } catch (_) {
      // The list falls back to history; the next send tries again.
    }
  }

  Future<Contact> addContact(
      {required String name, required String paymentIdentifier}) async {
    final sdk = await _ready();
    final c = await sdk.addContact(
        request:
            AddContactRequest(name: name, paymentIdentifier: paymentIdentifier));
    await refresh();
    return c;
  }

  Future<Contact> updateContact(Contact contact,
      {String? name, String? paymentIdentifier}) async {
    final sdk = await _ready();
    final c = await sdk.updateContact(
        request: UpdateContactRequest(
            id: contact.id,
            name: name ?? contact.name,
            paymentIdentifier: paymentIdentifier ?? contact.paymentIdentifier));
    await refresh();
    return c;
  }

  Future<void> deleteContact(String id) async {
    final sdk = await _ready();
    await sdk.deleteContact(id: id);
    await refresh();
  }

  Future<BreezSdk> _ready() async {
    await future;
    final sdk = _sdk;
    if (sdk == null) throw StateError('The spending wallet is not connected.');
    return sdk;
  }

  @visibleForTesting
  bool get seeded => _seeded;
}
