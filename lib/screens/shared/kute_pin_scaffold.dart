import 'dart:math' as math;
// lib/screens/shared/kute_pin_scaffold.dart
//
// One layout for every PIN screen before the wallet opens: create,
// confirm and unlock.
//
// The three were laid out as `Expanded(flex: 3)` over `Expanded(flex: 5)`,
// which is a ratio rather than a design. On a tall phone the title floated
// in the middle of a void; on a short one the dots crowded the pad. All
// three also carried a `BorderRadius.vertical(top: 32)` on a transparent
// container, a sheet corner painting nothing, left behind by a shape these
// screens no longer have.
//
// So the geometry is fixed and shared: the brand at the top, the question
// under it, the dots, then whatever space is left, then the pad and one
// footer slot above the home indicator. Every screen reads the same and
// none of them move when the next one loads.
//
// SAL IN THE LOCKUP (founder, 31 October 2026): the 3D face sits at the
// left of the "kute." wordmark, 44 px, 10 px before it, the two centred
// as one lockup. He blinks at rest, follows the digits with his curious
// face ([salMood] `curious`), is sad once on a wrong PIN (one loop, with
// the dots' shake) and happy for the beat before the app opens.
// [PinSalMoodMixin] gives the four PIN screens that one state machine.
// Reduce Motion: the sprite's first frame, still.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_wordmark.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

/// The Sal of the lockup on a PIN screen: `blink` at rest, `curious`
/// while digits are typed, `sad` once on a wrong PIN, `happy` on success.
/// [salSad] and [salHappy] set an override; [salMoodFor] reads the mood
/// for the digits typed. The timer dies with the screen.
mixin PinSalMoodMixin<T extends StatefulWidget> on State<T> {
  String? _salOverride;
  Timer? _salTimer;

  /// One sad loop (the clip's two seconds), then back to the digits.
  void salSad() {
    if (!mounted) return;
    _salTimer?.cancel();
    setState(() => _salOverride = 'sad');
    _salTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _salOverride = null);
    });
  }

  /// Happy until the screen goes.
  void salHappy() {
    if (!mounted) return;
    _salTimer?.cancel();
    setState(() => _salOverride = 'happy');
  }

  /// The clip for [digits] typed so far, under any override.
  String salMoodFor(int digits) =>
      _salOverride ?? (digits > 0 ? 'curious' : 'blink');

  @override
  void dispose() {
    _salTimer?.cancel();
    super.dispose();
  }
}

class KutePinScaffold extends StatelessWidget {
  const KutePinScaffold({
    super.key,
    required this.title,
    required this.dots,
    required this.keypad,
    this.subtitle,
    this.subtitleIsError = false,
    this.step,
    this.notice,
    this.footer,
    this.leading,
    this.showWordmark = true,
    this.salMood = 'blink',
  });

  /// Sal's clip in the lockup (see the file header and [PinSalMoodMixin]).
  final String salMood;

  /// The question, e.g. "Create a PIN".
  final String title;

  /// The line under it. An error takes the error colour and the heavier
  /// weight, because a wrong PIN is the one thing on this screen the
  /// person has to read.
  final String? subtitle;
  final bool subtitleIsError;

  /// "Step 1 of 2" on the create flow, so confirming does not look like
  /// the same screen shown twice.
  final String? step;

  /// A quiet block between the subtitle and the dots, for the one thing
  /// a screen has to say that is neither the question nor the answer.
  final Widget? notice;

  final Widget dots;
  final Widget keypad;

  /// The single action or link under the pad.
  final Widget? footer;

  /// A back control in the top left. Null on the unlock screen, which
  /// has nowhere to go back to.
  final Widget? leading;

  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Stack(
            children: [
              if (leading != null)
                Positioned(top: 4.h, left: 4.w, child: leading!),
              Column(
                children: [
                  SizedBox(height: 28.h),
                  if (showWordmark) ...[
                    // Sal and the wordmark as one lockup.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SalSprite(
                          key: const ValueKey('pin-sal'),
                          clip: salMood,
                          size: 44,
                          // The sad face plays once; the others loop.
                          loop: salMood == 'sad' ? false : null,
                          fallback: const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 10),
                        const KuteWordmark(size: 30),
                      ],
                    ),
                    SizedBox(height: 28.h),
                  ],
                  if (step != null) ...[
                    Text(
                      step!,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8.h),
                  ],
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28.w),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.05,
                      ),
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: 10.h),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28.w),
                      child: Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: subtitleIsError ? c.error : c.textTertiary,
                          fontSize: 15.sp,
                          fontWeight: subtitleIsError
                              ? FontWeight.w700
                              : FontWeight.w500,
                          letterSpacing: -0.1,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                  if (notice != null) ...[
                    SizedBox(height: 18.h),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 28.w),
                      child: notice!,
                    ),
                  ],
                  SizedBox(height: 32.h),
                  dots,
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: keypad,
                  ),
                  SizedBox(height: 20.h),
                  // The footer slot always occupies its height, whether or
                  // not anything is in it, so the pad never shifts when a
                  // link appears or a button fades in.
                  SizedBox(
                    height: 56.h,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: Center(child: footer ?? const SizedBox.shrink()),
                    ),
                  ),
                  // The greater of a comfortable gap and the home-indicator
                  // inset, never both: PlatformSafeArea leaves the bottom
                  // to the screen on iOS, so the footer clears the bar here.
                  // Read below PlatformSafeArea, where Android's inset is
                  // already consumed, so Android doesn't get it twice.
                  Builder(
                    builder: (context) => SizedBox(
                        height: math.max(
                            12.h, MediaQuery.of(context).padding.bottom)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
