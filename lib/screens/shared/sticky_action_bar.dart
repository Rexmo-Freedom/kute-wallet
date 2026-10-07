import 'package:flutter/material.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_blur.dart';

/// Pinned bottom bar for a screen's primary action, with the same frosted
/// chrome as the market sheets' Yes/No and Invest/Short bars. The child
/// provides its own horizontal padding; the bar adds the bottom safe area.
class KuteStickyActionBar extends StatelessWidget {
  const KuteStickyActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRect(
      child: KuteBlur(
        sigmaX: 18,
        sigmaY: 18,
        child: Container(
          decoration: BoxDecoration(
            color: (context.isDark ? c.surface : c.background)
                .withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(color: c.borderSubtle, width: 0.5),
            ),
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}
