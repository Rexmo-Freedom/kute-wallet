// lib/screens/share/brag/brag_lines.dart
//
// SAL'S ONE-LINER IN THE BRAG SHARE MESSAGE (founder, 1 November 2026:
// "Sal should be like 'I am better'"; since the restrained cards it is the
// message's line, never on the image). A rotating pool per tone
// ([BragTone]): cocky on a gain, unbothered on a loss, deadpan when flat.
// The message leaves the phone (WhatsApp, Instagram), so every line is
// PG: no profanity, no slurs, nothing about other people. The preview
// picks a seed once when it opens; [bragLine] maps the seed into the
// tone's pool.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/share/brag/brag_data.dart' show BragTone;

/// The lines Sal may say for [tone].
List<String> bragLines(AppLocalizations l10n, BragTone tone) => switch (tone) {
      BragTone.bigWin || BragTone.win => [
          l10n.bragLineBeatThat,
          l10n.bragLineNotLuck,
          l10n.bragLineYourMove,
          l10n.bragLineToldYouSo,
          l10n.bragLineLookEasy,
          l10n.bragLineUpOnly,
        ],
      BragTone.smallWin => [l10n.bragLineSmallWins],
      BragTone.loss => [
          l10n.bragLineDownBad,
          l10n.bragLineCharacter,
          l10n.bragLineBuyTheDip,
        ],
      BragTone.flat => [l10n.bragLinePatience],
    };

/// The line for [tone] at [seed] (any int; the preview's random pick).
String bragLine(AppLocalizations l10n, BragTone tone, int seed) {
  final pool = bragLines(l10n, tone);
  return pool[seed.abs() % pool.length];
}
