// lib/services/icon_cache/icon_warmup.dart
//
// Boot step: open the icon disk caches and, once the first frame is up,
// load the logos drawn on the previous launch back into memory, so the
// Investing lists and the Send/Receive grids draw them on their first
// frame. Never blocks boot and never throws.

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/providers/asset_icon_provider.dart' show SafeSvgNetwork;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart'
    show HlIconPrefetch;
import 'package:kute/services/icon_cache/icon_disk_cache.dart';

/// Compiled pictures flutter_svg keeps (its default is 100). One list of
/// Investing markets plus the coin grids already passes that, and an
/// evicted logo is compiled again in an isolate the next time it scrolls
/// in. A compiled logo is a few kilobytes.
const int kSvgPictureCacheSize = 500;

void startIconWarmup() {
  svg.cache.maximumSize = kSvgPictureCacheSize;
  IconCaches.init();
  // After the first frame: boot work comes first, the warm-up is a few
  // hundred small file reads and picture compiles in the background.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    unawaited(HlIconPrefetch.warmFromDisk());
    unawaited(SafeSvgNetwork.warmFromDisk());
  });
}
