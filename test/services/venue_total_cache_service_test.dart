import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/venue_total_cache_service.dart';

void main() {
  test(
      'complete Investments display survives storage reopen, partial reads do not overwrite it',
      () async {
    final dir = await Directory.systemTemp.createTemp('investments_display');
    Hive.init(dir.path);
    try {
      await Hive.openBox<double>(VenueTotalCacheService.boxName);
      resolveInvestmentsDisplay(
          walletId: 'wallet', total: 102, invested: 63, known: true);
      await Hive.box<double>(VenueTotalCacheService.boxName).flush();
      await Hive.close();
      await Hive.openBox<double>(VenueTotalCacheService.boxName);
      expect(
          resolveInvestmentsDisplay(
              walletId: 'wallet', total: 0, invested: 0, known: false),
          (total: 102.0, invested: 63.0, stale: true));
      expect(
          resolveInvestmentsDisplay(
                  walletId: 'wallet', total: 1, invested: 0, known: false)
              .total,
          102);
      expect(
          resolveInvestmentsDisplay(
              walletId: 'wallet', total: 0, invested: 0, known: true),
          (total: 0.0, invested: 0.0, stale: false));
    } finally {
      await Hive.close();
      await dir.delete(recursive: true);
    }
  });
}
