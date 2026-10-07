import 'package:flutter/material.dart';

/// Resolves the kute-dog mascot SVG for the current theme brightness.
///
/// flutter_svg cannot evaluate `@media (prefers-color-scheme: dark)`, so the
/// dark-mode look (dark eye sockets + white pupils, so the eyes stay visible
/// instead of the near-black pupils reading as harsh dots) lives in a separate
/// baked asset picked here rather than in CSS inside the SVG.
const String kuteDogLightAsset = 'lib/assets/kute_dog.svg';
const String kuteDogDarkAsset = 'lib/assets/kute_dog_dark.svg';

/// The mascot asset for [context]'s brightness. Use at any render site that
/// shows the dog in full colour (where the eyes are visible).
String kuteDogAsset(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? kuteDogDarkAsset
        : kuteDogLightAsset;
