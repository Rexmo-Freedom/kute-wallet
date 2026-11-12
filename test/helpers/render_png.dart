// On-demand renders to PNG for a look by eye (the slip's OK and Sal's
// placing toast): the app's Inter and the Material icon font loaded, and
// a RepaintBoundary written out at 2x.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inter (as the app and GoogleFonts name it) and the Material icons, so a
/// render draws words and glyphs rather than boxes.
Future<void> loadRenderFonts() async {
  for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
    final inter = FontLoader(family);
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons =
      File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && icons.existsSync()) {
    final bytes = icons.readAsBytesSync();
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  }
}

/// Writes the boundary under [key] to [path].
Future<void> writeRenderPng(
    WidgetTester tester, GlobalKey key, String path) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $path');
}

/// Writes the whole view to [path]: the page with every route over it (a
/// sheet, a dialog), which a boundary inside the page does not hold. The
/// cards' soft shadows are drawn as on a phone (flutter_test paints them
/// flat), then flat again for the binding's check.
Future<void> writeViewPng(WidgetTester tester, String path) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  debugDisableShadows = true;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  // ignore: avoid_print
  print('RENDER wrote $path');
}
