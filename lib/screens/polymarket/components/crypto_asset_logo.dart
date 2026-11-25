// lib/screens/polymarket/components/crypto_asset_logo.dart
//
// A round's coin, at any size: the round card's header, the other coins'
// rows under it (Predictions › Crypto › 5 Min) and the round's own sheet.
//
// EVERY COIN IS THE SAME CIRCLE (founder, 12 November 2026, XRP's bare X
// drawn edge to edge beside Ethereum's and Solana's discs: "looks
// oversized"): the bundled logo clipped to a circle of [size] (a raster
// is the coin's own disc; an SVG brings its disc), and a logo that is a
// bare mark with no disc ([CryptoAssetConfig.markDisc], XRP) is drawn
// white at a little over half the size on a disc of the coin's colour,
// with a hairline ring in the dark theme, where that disc is as dark as
// the card. Polymarket.com's own logo for a coin the app bundles none of.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/providers/polymarket_provider.dart' show CryptoAssetConfig;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/theme/app_theme.dart';

class CryptoAssetLogo extends StatelessWidget {
  const CryptoAssetLogo({super.key, required this.config, required this.size});

  final CryptoAssetConfig config;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = config.logoUrl;
    if (url != null) {
      return PolyCrestImage(
        url: url,
        size: size,
        radius: size / 2,
        fit: BoxFit.contain,
        label: config.asset,
        fallback: SizedBox(width: size, height: size),
      );
    }
    final disc = config.markDisc;
    if (disc != null) {
      return Container(
        key: ValueKey('crypto-asset-logo-${config.asset}'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disc,
          shape: BoxShape.circle,
          border: context.isDark
              ? Border.all(color: context.colors.border, width: 1)
              : null,
        ),
        child: SvgPicture.asset(
          config.logoPath,
          width: size * 0.54,
          height: size * 0.54,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      );
    }
    return SizedBox(
      key: ValueKey('crypto-asset-logo-${config.asset}'),
      width: size,
      height: size,
      child: ClipOval(
        child: config.isSvg
            ? SvgPicture.asset(config.logoPath,
                width: size, height: size, fit: BoxFit.cover)
            : Image.asset(config.logoPath,
                width: size, height: size, fit: BoxFit.cover),
      ),
    );
  }
}
