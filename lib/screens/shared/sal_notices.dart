// lib/screens/shared/sal_notices.dart
//
// The venues' notices from the top of the screen, as the Sal toast
// (sal_toast.dart; founder, 9 November 2026: "saying prediction placed and
// a success Sal", "haptics when the bet is placed, with a little
// confirmation of Sal on top"). Three verbs, one pill: [placed] for a
// prediction or order that went through (Sal nods once, the check, the
// success beat), [failed] for one that did not (Sal shakes it off once,
// the "!", the failure tap; the bar's Sal keeps still under it), and
// [pending] for one accepted and not finished (Sal waits, the clock, no
// haptic; sal_moments.dart). [detail] is the quieter second line (the market, the
// amount); [onTap] runs when the toast is tapped (open the position).

import 'package:flutter/widgets.dart';
import 'package:kute/screens/shared/sal_toast.dart';

abstract final class SalNotices {
  /// A prediction or order placed.
  static void placed(
    BuildContext context, {
    required String message,
    String? detail,
    VoidCallback? onTap,
  }) =>
      SalToast.show(
        context,
        message: message,
        detail: detail,
        tone: SalToastTone.success,
        onTap: onTap,
      );

  /// A prediction or order that did not go through.
  static void failed(
    BuildContext context, {
    required String message,
    String? detail,
    VoidCallback? onTap,
  }) {
    SalToast.show(
      context,
      message: message,
      detail: detail,
      tone: SalToastTone.failure,
      onTap: onTap,
    );
  }

  /// A prediction or order accepted and not finished yet.
  static void pending(
    BuildContext context, {
    required String message,
    String? detail,
    VoidCallback? onTap,
  }) =>
      SalToast.show(
        context,
        message: message,
        detail: detail,
        tone: SalToastTone.pending,
        onTap: onTap,
      );
}
