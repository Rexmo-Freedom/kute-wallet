// tool/asset_gallery/main.dart
//
// The asset gallery as its own app (see asset_gallery.dart), for the web:
//
//   flutter build web --release -t tool/asset_gallery/main.dart -o <dir>
//
// `?dark` in the URL shows the dark theme, `?sections=wallets,sal` only
// those sections. The page logs its frame rate and how long the first
// wallet mark took to draw to the browser console.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:kute/theme/app_theme.dart';

import 'asset_gallery.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(LiquidGlassWidgets.initialize());
  final query = kIsWeb ? Uri.base.queryParameters : const <String, String>{};
  final dark = query.containsKey('dark');
  // `?sections=wallets,sal` shows only those (see AssetGallery's names).
  final sections = query['sections']?.split(',').toSet();
  runApp(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: Scaffold(body: SafeArea(child: AssetGallery(sections: sections))),
    ),
  ));
}
