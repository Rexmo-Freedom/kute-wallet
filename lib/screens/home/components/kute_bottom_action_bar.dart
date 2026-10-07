import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// One money verb in the dock. Each dock host supplies its own pair, because
/// only the host knows which two verbs its surface runs (Send / Receive on a
/// bitcoin surface, Deposit / Withdraw on Investing and Predictions).
/// [trackingId] is the categorical action key sent to PostHog; a null
/// [onTap] renders the button disabled, same as the old sheet tile did.
/// Verbs wear the neutral chrome by default; [strongIcon] draws its icon
/// in pure black in light mode and pure white in dark, the label in the
/// dock's usual colour. [solid] instead fills the verb with the primary CTA
/// treatment (near-black with white label and icon in light mode, white
/// with near-black in dark), as Portfolio wears it on the venue docks.
class KuteDockAction {
  const KuteDockAction({
    required this.label,
    required this.icon,
    required this.trackingId,
    required this.onTap,
    this.strongIcon = false,
    this.solid = false,
  });

  final String label;
  final IconData icon;
  final String trackingId;
  final VoidCallback? onTap;
  final bool strongIcon;
  final bool solid;
}

/// Shared money dock: the surface's two money verbs plus the square search
/// button. The square used to be a "+" on the account surfaces (accounts and
/// Ask Sal behind it) and a magnifier on the venues; it is search everywhere
/// now (owner decision: each job has one home, and the wallets live in the
/// Financial hub behind the top bar's +). [onSearch] opens the same
/// results-first search sheet on every host, scoped to it; null hides the
/// square. While Sal is available the square's glyph is Sal holding a big
/// magnifying glass up to his eye ([KuteDogMagnifier]): the glass reads as
/// search at a glance, and Sal says he answers too.
/// The one door to search and to Sal, labelled "Search or ask Sal". With AI
/// off it is the plain magnifier.
class KuteBottomActionBar extends ConsumerWidget {
  final VoidCallback? onSearch;
  final String source;
  final List<KuteDockAction> actions;
  final ValueChanged<double>? onHeightChanged;

  const KuteBottomActionBar({
    super.key,
    this.onSearch,
    this.source = 'unknown',
    this.actions = const [],
    this.onHeightChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Same default as the search sheet it opens: Sal is assumed available
    // until the capability check says otherwise.
    final aiEnabled =
        onSearch != null && (ref.watch(aiEnabledProvider).valueOrNull ?? true);
    final searchLabel = aiEnabled
        ? context.l10n.searchOrAskSalShort
        : context.l10n.searchAction;

    final dock = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 2.h),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) SizedBox(width: 10.w),
            Expanded(
              child: _DockActionButton(
                action: actions[i],
                source: source,
                isLight: isLight,
              ),
            ),
          ],
          if (onSearch != null) ...[
            if (actions.isEmpty) const Spacer(),
            SizedBox(width: 10.w),
            Tooltip(
              message: searchLabel,
              // Same neutral square chrome as the header shortcut chip.
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : c.surface,
                  borderRadius: AppRadius.buttonBorder,
                  border: Border.all(
                    color: isLight ? c.border : c.borderSubtle,
                    width: isLight ? 1.0 : 0.5,
                  ),
                  boxShadow: isLight
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: AppRadius.buttonBorder,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: AppRadius.buttonBorder,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      // One tap, one event here; the search sheet then
                      // reports its own search_opened.
                      TrackingService.bottomBarTapped(
                          element: 'dock_search', source: source);
                      onSearch!();
                    },
                    child: Semantics(
                      button: true,
                      label: searchLabel,
                      child: Center(
                        child: aiEnabled
                            // Sal holding a big magnifying glass to his
                            // eye, filling most of the square; still while
                            // a sheet covers the dock or the app is away.
                            ? KuteStillWhenCovered(
                                child: KuteDogMagnifier(
                                  size: 46,
                                  lensColor: c.textPrimary,
                                ),
                              )
                            // The plain magnifier at the same visual size
                            // as Sal's glass (a fixed size, as his is).
                            : Icon(Icons.search_rounded,
                                size: 34, color: c.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
    return onHeightChanged == null
        ? dock
        : _DockHeightReporter(onChanged: onHeightChanged!, child: dock);
  }
}

/// A money verb in the dock, wearing the same neutral chrome as the search
/// square so the three controls read as one row, or, when [KuteDockAction.solid],
/// the primary CTA's monochrome fill (ctaFill / ctaOnColor, no border, and
/// AppButton's 0.35 disabled opacity). Same size, radius and press either
/// way. No tinted fills.
class _DockActionButton extends StatelessWidget {
  const _DockActionButton({
    required this.action,
    required this.source,
    required this.isLight,
  });

  final KuteDockAction action;
  final String source;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = action.onTap != null;
    final solid = action.solid;
    final foreground = solid ? context.ctaOnColor : c.textPrimary;
    final iconColor = !solid && action.strongIcon
        ? (isLight ? Colors.black : Colors.white)
        : foreground;
    return Opacity(
      opacity: enabled ? 1 : (solid ? 0.35 : 0.45),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: solid
              ? context.ctaFill
              : (isLight ? Colors.white : c.surface),
          borderRadius: AppRadius.buttonBorder,
          border: solid
              ? null
              : Border.all(
                  color: isLight ? c.border : c.borderSubtle,
                  width: isLight ? 1.0 : 0.5,
                ),
          boxShadow: isLight && !solid
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.buttonBorder,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: AppRadius.buttonBorder,
            // The theme's dark ripple vanishes on the near-black fill; a
            // wash of the label colour keeps the press visible.
            splashColor: solid ? foreground.withValues(alpha: 0.16) : null,
            highlightColor: solid ? foreground.withValues(alpha: 0.10) : null,
            onTap: !enabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    TrackingService.quickAction(action.trackingId,
                        source: source);
                    action.onTap!();
                  },
            child: Semantics(
              button: true,
              enabled: enabled,
              label: action.label,
              excludeSemantics: true,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, size: 20.sp, color: iconColor),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Report real layout height so large text and safe areas cannot hide the
/// final scroll item behind the floating dock.
class _DockHeightReporter extends SingleChildRenderObjectWidget {
  const _DockHeightReporter({required this.onChanged, required super.child});
  final ValueChanged<double> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderDockHeight(onChanged);

  @override
  void updateRenderObject(
      BuildContext context, _RenderDockHeight renderObject) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderDockHeight extends RenderProxyBox {
  _RenderDockHeight(this.onChanged);
  ValueChanged<double> onChanged;
  double? _previousHeight;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_previousHeight == height) return;
    _previousHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onChanged(height);
    });
  }
}
