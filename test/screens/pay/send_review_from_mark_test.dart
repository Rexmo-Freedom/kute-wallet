// The Bitcoin Send's Review wears the 3D Sal on From for the spending
// wallet (founder, 9 November 2026: "the last send screen should have our
// Sal 3D one, not the SVG Sal"): BrandMark's SalSprite, the flat SVG only
// as his fallback; a hardware wallet keeps its own logo. Same size as
// before.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/pay/components/confirm_send.dart'
    show sendReviewFromMark;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart'
    show SendReviewRoute;
import 'package:kute/screens/shared/wallet_icon.dart';

String? _assetOf(SvgPicture p) {
  final loader = p.bytesLoader;
  return loader is SvgAssetLoader ? loader.assetName : null;
}

/// A flat Sal: his SVG drawn anywhere but as a SalSprite's fallback.
final _flatSal = find.byElementPredicate((e) {
  final w = e.widget;
  if (w is! SvgPicture || !(_assetOf(w)?.contains('kute_dog') ?? false)) {
    return false;
  }
  var inSprite = false;
  e.visitAncestorElements((a) {
    inSprite = a.widget is SalSprite;
    return !inSprite;
  });
  return !inSprite;
});

Future<void> _pump(WidgetTester tester, String asset) =>
    tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
          home: Scaffold(body: Center(child: sendReviewFromMark(asset)))),
    ));

void main() {
  testWidgets('the spending wallet: the 3D Sal at the squares\' size',
      (tester) async {
    final visual = WalletVisual.fromWallet(
        walletType: 'spark',
        isHardware: false,
        isWatchOnly: false,
        isDark: false);
    expect(visual.svgAsset, contains('kute_dog'));
    await _pump(tester, visual.svgAsset!);
    expect(find.byType(SalSprite), findsOneWidget);
    expect(_flatSal, findsNothing);
    expect(tester.getSize(find.byType(SalSprite)),
        Size.square(SendReviewRoute.visualSize));
  });

  testWidgets('a Ledger keeps its own logo', (tester) async {
    final visual = WalletVisual.fromWallet(
        walletType: 'ledger',
        isHardware: true,
        isWatchOnly: true,
        isDark: false);
    await _pump(tester, visual.svgAsset!);
    expect(find.byType(SalSprite), findsNothing);
    final logo = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(_assetOf(logo), visual.svgAsset);
    expect(tester.getSize(find.byType(SvgPicture)),
        Size.square(SendReviewRoute.visualSize));
  });
}
