import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// CacheManager's public file type is supplied by this transitive package.
// ignore: depend_on_referenced_packages
import 'package:file/memory.dart';
// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:mocktail/mocktail.dart';

class _Cache extends Mock implements BaseCacheManager {}

class _File extends Mock implements fs.File {}

void main() {
  const url =
      'https://polymarket-upload.s3.us-east-2.amazonaws.com/Team%20crest';
  const fallback = SizedBox(key: ValueKey('fallback'), width: 48, height: 48);

  testWidgets(
      'large raster sniff reads only a prefix before sized image decode',
      (tester) async {
    final cache = _Cache();
    final file = _File();
    final png = File('lib/assets/bitcoin-logo.png').readAsBytesSync();
    final bytes = Uint8List(3 * 1024 * 1024)..setRange(0, png.length, png);
    when(() => file.path).thenReturn('/tracked-large-raster');
    when(() => file.length()).thenAnswer((_) async => bytes.length);
    when(() => file.openRead(0, 4096))
        .thenAnswer((_) => Stream.value(bytes.sublist(0, 4096)));
    when(() => file.readAsBytes()).thenAnswer((_) async => bytes);
    when(() => cache.getSingleFile(url)).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    verify(() => file.openRead(0, 4096)).called(1);
    // The sole full read belongs to Flutter's decoder; sniffing never adds a
    // second full buffer per thumbnail. Its decoded size remains capped.
    verify(() => file.readAsBytes()).called(1);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized SVG falls back before reading the full document',
      (tester) async {
    final cache = _Cache();
    final file = _File();
    when(() => file.length()).thenAnswer((_) async => 3 * 1024 * 1024);
    when(() => file.openRead(0, 4096)).thenAnswer((_) => Stream.value(
          utf8.encode('<svg xmlns="http://www.w3.org/2000/svg">'),
        ));
    when(() => cache.getSingleFile(url)).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    verifyNever(() => file.readAsBytes());
    expect(tester.takeException(), isNull);
  });

  testWidgets('raster bytes render even when the URL advertises SVG',
      (tester) async {
    final cache = _Cache();
    final file = MemoryFileSystem().file('/raster')
      ..writeAsBytesSync(File('lib/assets/bitcoin-logo.png').readAsBytesSync());
    when(() => cache.getSingleFile('$url.svg')).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: '$url.svg',
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('extensionless SVG artwork renders from cached provider bytes',
      (tester) async {
    final cache = _Cache();
    final file = MemoryFileSystem().file('/crest')
      ..writeAsBytesSync(utf8.encode(
        '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg" width="48" height="48"><rect width="48" height="48" fill="#00a86b"/></svg>',
      ));
    when(() => cache.getSingleFile(url)).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    expect(tester.takeException(), isNull);
    verify(() => cache.getSingleFile(url)).called(1);
  });

  testWidgets('bad artwork response and failed fetch show a stable fallback',
      (tester) async {
    final cache = _Cache();
    final file = MemoryFileSystem().file('/bad')
      ..writeAsBytesSync(utf8.encode('Not an image'));
    when(() => cache.getSingleFile(url)).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);

    when(() => cache.getSingleFile('$url.svg'))
        .thenThrow(Exception('unavailable'));
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: '$url.svg',
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('served as SVG (cached .svg) renders even past the sniffed prefix',
      (tester) async {
    final cache = _Cache();
    // A long comment pushes `<svg` beyond the bytes the sniff reads; the
    // served content type (the cache names the file .svg) decides.
    final file = MemoryFileSystem().file('/flag.svg')
      ..writeAsBytesSync(utf8.encode(
        '<?xml version="1.0"?><!-- ${'x' * 5000} -->'
        '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">'
        '<rect width="48" height="48" fill="#00a86b"/></svg>',
      ));
    when(() => cache.getSingleFile(url)).thenAnswer((_) async => file);
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      fallback: fallback,
      cacheManager: cache,
    ))));
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a fallback a failed image shows initials, not a gap',
      (tester) async {
    final cache = _Cache();
    when(() => cache.getSingleFile(url)).thenThrow(Exception('unavailable'));
    await tester.pumpWidget(MaterialApp(
        home: PolyCrestImage(
      url: url,
      size: 48,
      radius: 8,
      label: 'Premier League',
      cacheManager: cache,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(PolyArtworkFallback), findsOneWidget);
    expect(find.text('PL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
