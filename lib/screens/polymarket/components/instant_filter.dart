// lib/screens/polymarket/components/instant_filter.dart
//
// The filter on top of the Instant screen (instant_screen.dart): which
// coin's card is on screen and how long a round runs, in the app's own
// side-scrolling rows of pills (poly_browse_bar.dart). Two rows, since
// these are two questions: picking one never changes the other's row. The
// rows offer what the venue runs (the screen reads that); the pick is
// remembered (polymarket_instant_provider.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart' show PolySub;
import 'package:kute/providers/polymarket_instant_provider.dart';
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoRoundAssets;
import 'package:kute/screens/polymarket/components/crypto_asset_logo.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';
import 'package:kute/services/tracking_service.dart';

class PolyInstantFilter extends ConsumerWidget {
  const PolyInstantFilter({
    super.key,
    required this.assets,
    required this.lengths,
    required this.asset,
    required this.length,
  });

  /// The assets on offer at [length], in the coins' usual order.
  final List<String> assets;
  final List<String> lengths;
  final String asset;
  final String length;

  void _pick(WidgetRef ref, PolyInstantChoice next, String changed) {
    HapticFeedback.selectionClick();
    TrackingService.track('predictions_instant_filter_changed', params: {
      'asset': next.asset,
      'length': next.length,
      'changed': changed,
    });
    ref.read(polyInstantChoiceProvider.notifier).pick(next);
  }

  Widget? _logo(String ticker) {
    for (final c in kCryptoRoundAssets) {
      if (c.asset == ticker) return CryptoAssetLogo(config: c, size: 14.sp);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final choice = PolyInstantChoice(asset: asset, length: length);
    final assetAt = assets.indexOf(asset);
    final lengthAt = lengths.indexOf(length);
    return Padding(
      padding: EdgeInsets.only(top: 8.h, bottom: 4.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PolyAutoScrollRow(
            key: const ValueKey('instant-filter-assets'),
            height: kutePillRowHeight(),
            itemCount: assets.length,
            selectedIndex: assetAt < 0 ? null : assetAt,
            itemBuilder: (context, i) => KutePill(
              key: ValueKey('instant-asset-${assets[i]}'),
              label: assets[i],
              leading: _logo(assets[i]),
              selected: assets[i] == asset,
              onTap: () {
                if (assets[i] == asset) return;
                _pick(ref, choice.copyWith(asset: assets[i]), 'asset');
              },
            ),
          ),
          SizedBox(height: 8.h),
          PolyAutoScrollRow(
            key: const ValueKey('instant-filter-lengths'),
            height: kutePillRowHeight(),
            itemCount: lengths.length,
            selectedIndex: lengthAt < 0 ? null : lengthAt,
            itemBuilder: (context, i) => KutePill(
              key: ValueKey('instant-length-${lengths[i]}'),
              label: polySubLabel(l10n, PolySub(lengths[i])),
              selected: lengths[i] == length,
              onTap: () {
                if (lengths[i] == length) return;
                _pick(ref, choice.copyWith(length: lengths[i]), 'length');
              },
            ),
          ),
        ],
      ),
    );
  }
}
