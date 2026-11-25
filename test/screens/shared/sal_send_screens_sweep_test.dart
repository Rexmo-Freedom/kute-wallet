// The send flows show the 3D Sal, never the pixel one (founder, 9
// November 2026: "the last send screen should have our Sal 3D one, not
// the SVG Sal"). A sweep of the screens a send passes through (Bitcoin
// and Dollars: their steps, the shared send widgets, the Move sheet, the
// result sheet, the claim screens) for the pixel Sal's draws: the rig
// painters (kute_dog_rig.dart) and scene widgets (kute_dog_scenes.dart),
// and the flat SVG (kute_dog.svg). The only place either may appear is
// as a SalSprite's `fallback:`, the last resort once his sheet cannot be
// read. The money journey draws its rig behind the same rule
// (sal_journey_decoding_test.dart).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _sendScreens = [
  'lib/screens/pay/components/confirm_send.dart',
  'lib/screens/pay/components/signing_stage.dart',
  'lib/screens/usd/usd_send_screen.dart',
  'lib/screens/shared/send/send_sheet.dart',
  'lib/screens/shared/send/send_flow_widgets.dart',
  'lib/screens/shared/send/send_recipient_step.dart',
  'lib/screens/shared/send/send_contacts_list.dart',
  'lib/screens/shared/send/send_what_step.dart',
  'lib/screens/shared/money_movement_sheet.dart',
  'lib/screens/shared/move_steps_view.dart',
  'lib/screens/shared/transaction_modal.dart',
  'lib/screens/shared/kute_success_overlay.dart',
  'lib/screens/shared/kute_mascot.dart',
  'lib/screens/shared/wallet_icon.dart',
  'lib/screens/share/claim_screen.dart',
  'lib/screens/share/claimed_prompt_sheet.dart',
];

/// The pixel Sal's draws: the rig painters and the scene widgets around
/// them, and the flat SVG.
final List<RegExp> _pixelSal = [
  RegExp(r'\bpaintKuteDog\w*\('),
  RegExp(r'\bKuteDogLoop\('),
  RegExp(r'\bKuteDogNotHere\('),
  RegExp(r'\bKuteDogMagnifier\('),
  RegExp(r'\bKuteDogBitcoin\('),
  RegExp(r'\bKuteDogGlance\('),
  RegExp(r'\bKuteDogConfirmation\('),
  RegExp(r'\bkuteDogAsset\('),
  RegExp(r'kute_dog(_dark)?\.svg'),
];

/// Whether the match at [at] in [src] is the argument of a SalSprite's
/// `fallback:` (the text right before it, comments, whitespace, the SVG
/// widget and the assets folder aside), or the data a WalletVisual
/// carries for BrandMark to resolve into the 3D Sal
/// (`svgAsset: 'lib/assets/kute_dog.svg'`, wallet_icon.dart).
bool _allowed(String src, int at) {
  var before =
      src.substring(0, at).replaceAll(RegExp(r'//[^\n]*'), '').trimRight();
  before = before.replaceFirst(RegExp(r"'lib/assets/$"), '').trimRight();
  before = before.replaceFirst(RegExp(r'SvgPicture\.asset\($'), '').trimRight();
  return before.endsWith('fallback:') || before.endsWith('svgAsset:');
}

void main() {
  test('no send screen draws the pixel Sal but as a SalSprite\'s fallback',
      () {
    final offences = <String>[];
    for (final path in _sendScreens) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path exists');
      final src = file.readAsStringSync();
      for (final pattern in _pixelSal) {
        for (final m in pattern.allMatches(src)) {
          if (_allowed(src, m.start)) continue;
          final line = src.substring(0, m.start).split('\n').length;
          offences.add('$path:$line ${m.group(0)}');
        }
      }
    }
    expect(offences, isEmpty,
        reason: 'the pixel Sal drawn where the person sees it:\n'
            '${offences.join('\n')}');
  });

  test('the widgets the send screens draw Sal with are the 3D Sal', () {
    // KuteMascot (the claim screens) and BrandMark (the Review's From
    // square, the rows' marks) are SalSprites with the rig or the SVG as
    // their fallback only.
    final mascot = File('lib/screens/shared/kute_mascot.dart').readAsStringSync();
    expect(mascot, contains('return SalSprite('));
    expect(mascot, contains('fallback: KuteDogLoop('));
    final mark = File('lib/screens/shared/wallet_icon.dart').readAsStringSync();
    expect(mark, contains('return SalSprite('));
    expect(mark, contains('fallback: SvgPicture.asset(kuteDogAsset(context)'));
    // The result sheet: the rig only as the sprite's fallback, said once.
    final sheet =
        File('lib/screens/shared/kute_success_overlay.dart').readAsStringSync();
    expect(RegExp(r'KuteDogConfirmation\(').allMatches(sheet).length, 1);
    expect(sheet, contains('fallback: KuteDogConfirmation('));
    expect(sheet, contains('onUnavailable:'));
    // The journey: the rig only once a read came back empty.
    final journey =
        File('lib/screens/shared/money_steps_view.dart').readAsStringSync();
    expect(journey, contains('if (SalSpriteCache.failed(name, density)) return SalJourneyDraw.rig;'));
    expect(journey, contains('if (s.salDraw == SalJourneyDraw.rig) {'));
    // Both flows warm him on open; the Dollars send's journey too.
    expect(
        File('lib/screens/pay/components/confirm_send.dart')
            .readAsStringSync(),
        contains('warmSendSal();'));
    expect(File('lib/screens/usd/usd_send_screen.dart').readAsStringSync(),
        contains('warmSendSal(journey: true);'));
  });
}
