// The hero balance shows the loading shimmer only when there is nothing
// to show: SDK still connecting, no cached balance, and the wallet was
// not created fresh on this device. A brand-new wallet and a cached 0
// render $0.00 at once.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/home.dart' show heroBalanceShowsSkeleton;

void main() {
  test('a brand-new wallet renders 0 instead of the skeleton', () {
    expect(
        heroBalanceShowsSkeleton(
          breezWaking: true,
          btcSats: 0,
          hasCachedBalance: false,
          createdEmpty: true,
        ),
        isFalse);
  });

  test('a cached 0 renders 0 instead of the skeleton', () {
    expect(
        heroBalanceShowsSkeleton(
          breezWaking: true,
          btcSats: 0,
          hasCachedBalance: true,
          createdEmpty: false,
        ),
        isFalse);
  });

  test('a wallet that may hold a balance but has no cache yet waits', () {
    expect(
        heroBalanceShowsSkeleton(
          breezWaking: true,
          btcSats: 0,
          hasCachedBalance: false,
          createdEmpty: false,
        ),
        isTrue);
  });

  test('a connected SDK or a non-zero balance never shows the skeleton', () {
    expect(
        heroBalanceShowsSkeleton(
          breezWaking: false,
          btcSats: 0,
          hasCachedBalance: false,
          createdEmpty: false,
        ),
        isFalse);
    expect(
        heroBalanceShowsSkeleton(
          breezWaking: true,
          btcSats: 1200,
          hasCachedBalance: false,
          createdEmpty: false,
        ),
        isFalse);
  });
}
