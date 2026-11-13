// Shared "No activity yet" empty state: Sal, a headline, and a rotating
// brand-voice tagline. Used on the Home activity feed and on every empty
// Portfolio view (Open, Orders, Activity, Statistics), each with its own
// headline. Kept in one place so every surface stays identical.
//
// Sal is the 3D hero here (founder, 31 October 2026), calm (12 November
// 2026; [SalIdleDirector], sal_sprite.dart): still in the hero pose, one
// beat (a blink, a look around, a stretch) every 8–15 s while on screen,
// asleep after a minute without a touch, awake on the next one. Until that
// sheet exists he sits down and sits (`body_sit_down` → `body_sit`), and
// the painted rig idles until any sheet exists. Quiet under Reduce
// Motion.
//
// The Portfolio screen's three sections (Portfolio, P&L Charts, Activity)
// all draw it the same way (founder, 1 November 2026: "empty states must
// be the same"): the hero Sal at 160, the title 22 w600, the tagline 15
// in textSecondary ([titleWeight], [subtitleSize], [subtitleColor]), each
// section starting the taglines at its own line ([taglineStart]); see
// PortfolioSectionEmpty (portfolio_empty_state.dart).

import 'package:kute/screens/shared/sal_sprite.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_taglines.dart';
import 'package:kute/theme/app_theme.dart';

class NoActivityState extends StatefulWidget {
  /// Outer padding around the GIF + text block. Defaults to the Home
  /// activity-feed inset; Wealth can pass a roomier one when it stands in
  /// for the whole analytics section.
  final EdgeInsetsGeometry? padding;

  /// The headline; null is Home's "No activity yet".
  final String? title;

  /// The smaller Sal, headline and tagline slot (the search sheet's
  /// compact sizes), for a state that sits under other content.
  final bool compact;

  /// See [KuteDogLoop.cycles]: null idles forever (Home); a tab a person
  /// may leave open settles on a calm frame.
  final int? cycles;

  /// Sal's size and the headline's, in design units, when a surface wants
  /// its own (the Portfolio screen's empty state under its strip: 96 and
  /// 15); null is the [compact] or full size.
  final double? salSize;
  final double? titleSize;

  const NoActivityState(
      {super.key,
      this.padding,
      this.title,
      this.subtitle,
      this.compact = false,
      this.cycles,
      this.salSize,
      this.titleSize,
      this.titleWeight,
      this.subtitleSize,
      this.subtitleColor,
      this.taglineStart});

  /// The headline's weight; null is w800 at the default sizes and w600
  /// with a [titleSize].
  final FontWeight? titleWeight;

  /// The tagline's size and colour; null is 14 in textTertiary.
  final double? subtitleSize;
  final Color? subtitleColor;

  /// The tagline the rotation starts on; null is a random one per mount.
  final int? taglineStart;

  /// A fixed line under the title instead of the rotating taglines (an
  /// empty balance's "It starts with your first transaction.").
  final String? subtitle;

  @override
  State<NoActivityState> createState() => _NoActivityStateState();
}

class _NoActivityStateState extends State<NoActivityState>
    with SingleTickerProviderStateMixin {
  // Brand-voice taglines now live in the shared positive set.

  int _currentIndex = 0;
  bool _reduceMotion = false;
  Timer? _rotation;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Random start so each session feels different
    _currentIndex = (widget.taglineStart ??
            DateTime.now().millisecondsSinceEpoch) %
        kKuteTaglineCount;

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.value = 1.0;
    // NOTE: Reduce Motion is read in didChangeDependencies, NOT here —
    // MediaQuery.of(context) is illegal during initState.

    // Rotate quotes every 6 seconds
    _scheduleRotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the OS "reduce motion" setting: the tagline cross-fade below
    // is decorative, so it becomes an instant swap. Sal handles the setting
    // himself inside the rig. Safe here — inherited widgets are available.
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  void _scheduleRotation() {
    // A fixed line never rotates.
    if (widget.subtitle != null) return;
    // A timer the state owns, cancelled on dispose: a delayed future
    // outlived the widget.
    _rotation = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_reduceMotion) {
        // Swap the (informative) tagline instantly, no cross-fade.
        setState(() => _currentIndex = (_currentIndex + 1) % kKuteTaglineCount);
      } else {
        _fadeController.reverse().then((_) {
          if (!mounted) return;
          setState(
              () => _currentIndex = (_currentIndex + 1) % kKuteTaglineCount);
          _fadeController.forward();
        });
      }
      _scheduleRotation();
    });
  }

  @override
  void dispose() {
    _rotation?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final compact = widget.compact;

    final salSize = widget.salSize?.sp ?? (compact ? 120.sp : 160.sp);
    // Centred whatever the parent column's alignment (the Dollars tab's
    // starts its children at the left).
    return Padding(
      padding: widget.padding ?? EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 8.h),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The 3D Sal (founder, 31 October 2026): the hero loop with
            // its one-shots, sleep and wake; until that sheet lands he
            // sits down and sits (`body_sit`), and the rig idles until any
            // sheet exists.
            SalIdleDirector(
              size: salSize,
              fallback: SalSprite.sequence(
                first: 'body_sit_down',
                then: 'body_sit',
                size: salSize,
                fallback: KuteDogIdle(
                  size: salSize,
                  shadowColor: c.textPrimary.withValues(alpha: 0.10),
                  cycles: widget.cycles,
                ),
              ),
            ),
            SizedBox(height: compact ? 12.h : 18.h),
            Text(
              widget.title ?? 'No activity yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: widget.titleSize?.sp ?? (compact ? 17.sp : 22.sp),
                fontWeight: widget.titleWeight ??
                    (widget.titleSize == null
                        ? FontWeight.w800
                        : FontWeight.w600),
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
              height: compact ? 40.h : 56.h,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Text(
                  widget.subtitle ?? kuteTaglines(context.l10n)[_currentIndex],
                  key: ValueKey(widget.subtitle ?? _currentIndex),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.subtitleColor ?? c.textTertiary,
                    fontSize: (widget.subtitleSize ?? 14).sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
