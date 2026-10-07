import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/security/address_history.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('address_history_test');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a closed box drops rows without failing', () async {
    await AddressHistory.record(const AddressHistoryEntry(
      venue: 'orchestra',
      role: 'accumulation_deposit',
      chain: 'arbitrum',
      asset: 'USDC',
      address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    ));
    expect(AddressHistory.all(), isEmpty);
  });

  test('rows round-trip in insertion order with their reason', () async {
    await AddressHistory.open();
    final retiredAt = DateTime.utc(2026, 9, 15, 12);
    await AddressHistory.record(AddressHistoryEntry(
      walletId: 'w1',
      venue: 'orchestra',
      role: 'accumulation_deposit',
      chain: 'arbitrum',
      asset: 'USDC',
      address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      createdAt: '2026-07-01T00:00:00Z',
      retiredAt: retiredAt,
      reason: AddressRetireReason.reverify,
      replacedBy: '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
    ));
    await AddressHistory.record(const AddressHistoryEntry(
      venue: 'orchestra',
      role: 'accumulation_deposit',
      chain: 'tron',
      asset: 'USDT',
      address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      reason: AddressRetireReason.catalog,
    ));

    final rows = AddressHistory.all();
    expect(rows, hasLength(2));
    expect(rows[0].walletId, 'w1');
    expect(rows[0].chain, 'arbitrum');
    expect(rows[0].retiredAt, retiredAt);
    expect(rows[0].reason, AddressRetireReason.reverify);
    expect(rows[0].replacedBy, '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359');
    expect(rows[1].reason, AddressRetireReason.catalog);
    expect(rows[1].walletId, isNull);
    expect(rows[1].retiredAt, isNull);
  });

  test('stored rows carry public fields only', () async {
    await AddressHistory.open();
    await AddressHistory.record(const AddressHistoryEntry(
      venue: 'orchestra',
      role: 'accumulation_deposit',
      chain: 'base',
      asset: 'USDC',
      address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      reason: AddressRetireReason.rotation,
    ));
    final raw = Hive.box<String>(AddressHistory.boxName).values.single;
    expect(raw, isNot(contains('amount')));
    expect(raw, isNot(contains('key')));
    expect(raw, contains('"reason":"rotation"'));
  });

  test('corrupt rows are skipped', () async {
    await AddressHistory.open();
    await Hive.box<String>(AddressHistory.boxName).add('not json');
    await AddressHistory.record(const AddressHistoryEntry(
      venue: 'orchestra',
      role: 'accumulation_deposit',
      chain: 'base',
      asset: 'USDC',
      address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
    ));
    expect(AddressHistory.all(), hasLength(1));
  });
}
