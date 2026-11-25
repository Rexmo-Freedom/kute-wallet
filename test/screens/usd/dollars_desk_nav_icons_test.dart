import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/usd/dollars_desk_nav_icons.dart';

/// What a mark draws, for comparing two of them.
Object _drawn(DeskNavMark m) => m.icon ?? m.asset!;

void main() {
  test('every section, category and subcategory has its own mark', () {
    for (final id in ['activity', 'investing', 'predictions']) {
      expect(kDeskNavMarks['section:$id'], isNotNull, reason: id);
    }
    final hlTabs = [
      for (final t in HlBrowseTab.values) kDeskNavMarks['hl:${t.key}'],
      kDeskNavMarks['hl:watchlist-create'],
    ];
    expect(hlTabs, everyElement(isNotNull));
    expect({for (final m in hlTabs) _drawn(m!)}.length, hlTabs.length,
        reason: 'no repeat among Investing categories');
    final hlSubs = [
      for (final s in HlBrowseSub.values) kDeskNavMarks['hl:sub:${s.key}'],
    ];
    expect(hlSubs, everyElement(isNotNull));
    expect({for (final m in hlSubs) _drawn(m!)}.length, hlSubs.length,
        reason: 'no repeat among Investing subcategories');
    final poly = [
      for (final p in PolyPill.values) kDeskNavMarks['poly:${p.key}'],
      kDeskNavMarks['poly:five-minute'],
    ];
    expect(poly, everyElement(isNotNull));
    expect({for (final m in poly) _drawn(m!)}.length, poly.length,
        reason: 'no repeat among Predictions topics');
  });

  test('every bundled mark exists', () {
    for (final m in kDeskNavMarks.values) {
      if (m.asset != null) {
        expect(File(m.asset!).existsSync(), isTrue, reason: m.asset);
      }
    }
  });
}
