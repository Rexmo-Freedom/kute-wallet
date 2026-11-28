// tool/web_pwa_stamp.dart drops the package fonts the compiled web app
// never names from the font manifest, and never one it names.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/web_pwa_stamp.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('font_prune');
    Directory('${root.path}/assets').createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Map<String, Object> family(String name, String asset) => {
        'family': name,
        'fonts': [
          {'asset': asset}
        ],
      };

  void writeManifest(List<Object> families) =>
      File('${root.path}/assets/FontManifest.json')
          .writeAsStringSync(jsonEncode(families));

  List<String> manifestFamilies() =>
      (jsonDecode(File('${root.path}/assets/FontManifest.json')
              .readAsStringSync()) as List)
          .map((f) => (f as Map)['family'] as String)
          .toList();

  test('drops package fonts the code never names, keeps the rest', () {
    writeManifest([
      family('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      family('Inter', 'lib/assets/fonts/Inter-Regular.ttf'),
      family('packages/icons_plus/Iconsax',
          'packages/icons_plus/assets/fonts/Iconsax.ttf'),
      family('packages/bootstrap_icons/BootstrapIcons',
          'packages/bootstrap_icons/fonts/BootstrapIcons.ttf'),
      family('packages/flutter_boxicons/Boxicons',
          'packages/flutter_boxicons/fonts/Boxicons.ttf'),
    ]);
    File('${root.path}/main.dart.js').writeAsStringSync(
        'A.x=new A.aI(61746,"BootstrapIcons","bootstrap_icons",!1)');
    File('${root.path}/main.dart.js_1.part.js')
        .writeAsStringSync("B.y=new A.aI(1,'Boxicons','flutter_boxicons',!1)");

    final pruned = pruneUnusedPackageFonts(root);

    expect(pruned, ['packages/icons_plus/Iconsax']);
    expect(manifestFamilies(), [
      'MaterialIcons',
      'Inter',
      'packages/bootstrap_icons/BootstrapIcons',
      'packages/flutter_boxicons/Boxicons',
    ]);
  });

  test('the app\'s own families stay even when the code never names them',
      () {
    writeManifest([family('Inter', 'lib/assets/fonts/Inter-Regular.ttf')]);
    File('${root.path}/main.dart.js').writeAsStringSync('nothing');
    expect(pruneUnusedPackageFonts(root), isEmpty);
    expect(manifestFamilies(), ['Inter']);
  });

  test('a build without main.dart.js is left alone', () {
    writeManifest([
      family('packages/icons_plus/Iconsax',
          'packages/icons_plus/assets/fonts/Iconsax.ttf'),
    ]);
    expect(pruneUnusedPackageFonts(root), isEmpty);
    expect(manifestFamilies(), ['packages/icons_plus/Iconsax']);
  });
}
