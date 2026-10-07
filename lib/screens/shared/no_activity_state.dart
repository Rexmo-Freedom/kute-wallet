// Shared "No activity yet" empty state: Sal, a headline, and a rotating
// brand-voice tagline. Used on the Home activity feed and on the
// Wealth/Portfolio screen (shown in place of analytics when the account has
// no activity at all yet). Kept in one place so both surfaces stay identical.
//
// Sal used to be a GIF here, on a loop nobody authored and with a
// `_dogController` that was started, repeated and disposed without a single
// widget ever reading it. He is now the painted rig, idling: breathing,
// wagging, blinking, flicking an ear and glancing around on a ten second
// cycle, sharp at any size and quiet when Reduce Motion is on.

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

  const NoActivityState({super.key, this.padding});

  @override
  State<NoActivityState> createState() => _NoActivityStateState();
}

class _NoActivityStateState extends State<NoActivityState>
    with SingleTickerProviderStateMixin {
  // Brand-voice taglines now live in the shared positive set.

  int _currentIndex = 0;
  bool _reduceMotion = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Random start so each session feels different
    _currentIndex = DateTime.now().millisecondsSinceEpoch % kKuteTaglineCount;

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
    _reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  void _scheduleRotation() {
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      if (_reduceMotion) {
        // Swap the (informative) tagline instantly, no cross-fade.
        setState(() => _currentIndex = (_currentIndex + 1) % kKuteTaglineCount);
      } else {
        _fadeController.reverse().then((_) {
          if (!mounted) return;
          setState(() => _currentIndex = (_currentIndex + 1) % kKuteTaglineCount);
          _fadeController.forward();
        });
      }
      _scheduleRotation();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: widget.padding ?? EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 8.h),
      child: Column(
        children: [
          KuteDogIdle(
            size: 112.sp,
            shadowColor: c.textPrimary.withValues(alpha: 0.10),
          ),
          SizedBox(height: 18.h),
          Text(
            'No activity yet',
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.1,
            ),
          ),
          SizedBox(height: 8.h),
          SizedBox(
            height: 56.h,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                kuteTaglines(context.l10n)[_currentIndex],
                key: ValueKey(_currentIndex),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
