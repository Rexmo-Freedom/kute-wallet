// lib/screens/shared/kute_split_screen.dart
//
// ONBOARDING AND LOCK ON A LAPTOP (round three, founder 25 November 2026:
// "lots of screens are vertical only. It must be all occupying full screen
// when we can"). On EXPANDED a step before the wallet opens (set and
// confirm the PIN, unlock, the passkey choice, the survey, the referrer
// code, the recover choice, the lock overlay) is a SPLIT SCREEN that fills
// the window:
//
//   * the LEFT half is the brand: the Start screen's Sal in his spark
//     burst over the tagline, on its breathing glow across the whole half
//     ([StartBrandSide], start.dart);
//   * the RIGHT half is the step's form at phone width
//     ([KuteLayout.paneWidth]), vertically centred, with the step's
//     primary button under the form inside that half: the page's bar
//     drawn in place ([KuteInPlaceBar], kute_dialog.dart), never the
//     floating bar detached at the bottom middle of the window.
//
// MEDIUM keeps the centred column ([KuteFormColumn]); a phone the page as
// it was.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/creation/start.dart' show StartBrandSide;
import 'package:kute/screens/shared/kute_dialog.dart' show KuteInPlaceBar;
import 'package:kute/theme/app_theme.dart';

/// The tallest a split screen's form gets: a phone's page less its status
/// bar and home indicator.
const double kuteSplitFormHeight = 820;

/// The split screen (see the file header). [child] is the step's page.
class KuteSplitScreen extends StatelessWidget {
  const KuteSplitScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    switch (KuteLayout.forWidth(window.width)) {
      case KuteFormFactor.compact:
        return child;
      case KuteFormFactor.medium:
        return KuteFormColumn(child: child);
      case KuteFormFactor.expanded:
        break;
    }
    final c = context.colors;
    final height =
        math.min(window.height - 2 * kuteWideGutter, kuteSplitFormHeight);
    const width = KuteLayout.paneWidth;
    final mq = MediaQuery.of(context);
    final form = MediaQuery(
      // The form's own screen: a phone column, its room, no insets.
      data: mq.copyWith(
        size: Size(width, height),
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
      ),
      child: KuteInPlaceBar(child: child),
    );
    return Material(
      color: c.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: StartBrandSide()),
          Expanded(
            child: DecoratedBox(
              decoration: AppDecorations.screenGradient(context),
              child: Center(
                child: SizedBox(width: width, height: height, child: form),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
