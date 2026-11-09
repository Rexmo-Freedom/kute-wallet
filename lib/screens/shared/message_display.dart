// lib/screens/shared/message_display.dart
//
// The app's messages from the top of the screen. Since 9 November 2026
// (founder: "substitute the toolbar on top of an error or something with a
// modern Sal one") every one of them is the Sal toast (sal_toast.dart):
// the three helpers here keep their signatures, so their call sites did
// not change, and draw it in the tone they stand for: an error is a
// failure (Sal sad, the "!", the failure tap; the bar's Sal shakes his
// head too), information is information (Sal's calm blink, no mark), and
// a plain success is a success (Sal happy, the check, the success beat).
//
// [duration]: the old default (4 s) means the tone's own time
// (SalToast.durationFor: 2.5 s for a success, 3 s for information, 6 s
// for a failure); a caller that asks for a time of its own is honoured.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/theme/app_theme.dart';

/// The signature's default: the tone decides.
const Duration _toneDecides = Duration(seconds: 4);

Duration? _own(Duration duration) =>
    duration == _toneDecides ? null : duration;

void showMessageSnackBarInfo({
  required BuildContext context,
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  SalToast.show(
    context,
    message: message,
    tone: SalToastTone.info,
    duration: _own(duration),
  );
}

void showMessageSnackBar({
  required BuildContext context,
  required String message,
  required bool error,
  bool info = false,
  Duration duration = const Duration(seconds: 4),
}) {
  final SalToastTone tone;
  if (error) {
    tone = SalToastTone.failure;
    // Sal in the bar shakes his head with the toast (sal_reactions.dart).
    SalReactions.play(SalReaction.shakeNo);
  } else if (info) {
    tone = SalToastTone.info;
  } else {
    tone = SalToastTone.success;
  }
  SalToast.show(
    context,
    message: message,
    tone: tone,
    duration: _own(duration),
  );
}

/// A toast with a tap action, for an in-app alert that points somewhere
/// (a trade alert opening the position it is about). [accentColor] says
/// what it is: the error red is a failure, the success green a success,
/// anything else information; the alert's own haptic already played, so
/// the toast plays none. [icon] is kept for the callers; Sal is the glyph.
void showMessageBanner({
  required BuildContext context,
  required String message,
  required IconData icon,
  required Color accentColor,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 6),
}) {
  SalToast.show(
    context,
    message: message,
    tone: accentColor == AppColors.error
        ? SalToastTone.failure
        : accentColor == AppColors.success
            ? SalToastTone.success
            : SalToastTone.info,
    onTap: onTap,
    duration: duration,
    haptic: false,
  );
}
