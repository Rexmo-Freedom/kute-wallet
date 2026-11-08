// lib/screens/polymarket/components/crypto_asset_logo.dart
//
// A round's coin, at any size: the round card's header, the Instant
// filter's chips and the Instant card on the category sheet. The bundled
// logo, on the asset's brand colour when it is a raster; polymarket.com's
// own for a coin the app bundles none of.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/providers/polymarket_provider.dart' show CryptoAssetConfig;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';

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
    if (config.isSvg) {
      return SvgPicture.asset(config.logoPath,
          width: size, height: size, fit: BoxFit.contain);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: config.brandColor,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      alignment: Alignment.center,
      child:
          Image.asset(config.logoPath, width: size * 0.68, height: size * 0.68),
    );
  }
}
