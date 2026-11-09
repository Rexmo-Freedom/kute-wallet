import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart'
    show kuteSearchLoading, kuteSearchSheetOpen;
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_morph_label.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/receive_arrow_glyph.dart'
    show GlyphPressScope;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';
import 'package:kute/theme/kute_motion.dart';

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
    this.caption,
    this.soon = false,
    this.glyph,
  });

  final String label;

  /// The verb's icon; [glyph], when given, is drawn in its place.
  final IconData icon;

  /// A glyph drawn in code instead of [icon] (the moving Receive arrow,
  /// [ReceiveArrowGlyph]), given the colour and size the icon would have
  /// had, so it follows the button's fill and theme. The button pings it
  /// on each press ([GlyphPressScope]).
  final Widget Function(Color color, double size)? glyph;
  final String trackingId;
  final VoidCallback? onTap;
  final bool strongIcon;
  final bool solid;

  /// A second, quieter line under the label saying what the verb moves
  /// ("\$ & stocks" under Send on Dollars), when the one word is too vague
  /// and a longer label would not fit under a square (founder, 1 November
  /// 2026).
  final String? caption;

  /// Not live yet: drawn at the unavailable opacity, not tappable, with
  /// the caption reading "Soon" (Connect AI, founder 1 November 2026).
  final bool soon;
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
/// The one door to search and to Sal, labelled "Search or Manage with AI".
/// With AI off it is the plain magnifier.
///
/// THE 3D SAL (founder, 31 October 2026): the pill's glyph is the Blender
/// Sal's `search` clip ([SalSprite], sal_sprite.dart) at the icon size,
/// faster (1.8x) while the search sheet is loading results
/// ([kuteSearchLoading]) and `happy` for a beat when they land, then
/// searching again. Until the sheets land it is the static Sal glyph
/// ([KuteDogMagnifier]). The pill is 50 high so the head reads.
///
/// THE PILL'S OPENING (founder, 31 October 2026, "a fintech animation"):
/// tapped, the pill shrinks a hair and fades (1 → 0.96, 120 ms) as the
/// search sheet rises on the app's spring (showKuteModalSheet), and
/// springs back when the sheet closes; it follows [kuteSearchSheetOpen],
/// which the sheet holds while it is up. Under Reduce Motion it stays
/// put. Its frost is its own: the blur under it is the pill's bounds plus
/// 8 px at half the old band's sigma, never a band across the screen
/// (the host paints none for this dock: KuteDockHost.frostBand false).
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
        ? context.l10n.searchOrManageAi
        : context.l10n.searchAction;

    // Android's navigation bar inset ends right under the dock, where
    // iOS leaves the home indicator's breathing room, so Android lifts
    // the dock a little more off it.
    final bottomGap =
        defaultTargetPlatform == TargetPlatform.android ? 12.h : 2.h;
    if (actions.isEmpty && onSearch != null) {
      // No money verbs down here (they sit under the balance, once), and
      // no pill of the dock's own either: the ONE pill of the app is the
      // shell-level bar (kute_shell_bar.dart; founder, 31 October 2026:
      // two bars at once on the Dollars home). The dock keeps the pill's
      // room, so the lists under it still clear the bar.
      final room = SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, bottomGap),
          child: const SizedBox(
              key: ValueKey('dock-bar-room'), height: _kDockPillHeight),
        ),
      );
      return onHeightChanged == null
          ? room
          : _DockHeightReporter(onChanged: onHeightChanged!, child: room);
    }
    final dock = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, bottomGap),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) SizedBox(width: 10.w),
            Expanded(
              child: KuteDockActionButton(
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

/// The money verbs of a surface in one row under its balance, each once:
/// Receive · Send on a bitcoin surface, Add · Withdraw on
/// Investments. The same buttons the dock wore, so nothing changes hands;
/// the dock itself is left to search and Sal.
class KuteActionRow extends StatelessWidget {
  const KuteActionRow({super.key, required this.actions, required this.source});

  final List<KuteDockAction> actions;
  final String source;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(
      key: const ValueKey('kute-action-row'),
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) SizedBox(width: 10.w),
          Expanded(
            child: KuteDockActionButton(
              action: actions[i],
              source: source,
              isLight: isLight,
            ),
          ),
        ],
      ],
    );
  }
}

/// Every action of a surface in ONE compact row under its balance: a squared
/// button with its label under it (Purchase · Swap · Receive · Send on the
/// Bitcoin tab, Add · Send on Investments), so the actions take one row,
/// not two or three (founder, 31 October 2026). A [KuteDockAction.solid]
/// action wears the primary fill (Purchase); the rest the neutral chrome.
/// Same events as the dock's buttons.
class KuteCompactActions extends StatelessWidget {
  const KuteCompactActions(
      {super.key, required this.actions, required this.source});

  final List<KuteDockAction> actions;
  final String source;

  /// The action squares' side.
  static const double squareSize = 52;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Row(
      key: const ValueKey('kute-compact-actions'),
      mainAxisAlignment: MainAxisAlignment.center,
      // Squares line up at the top when one label carries a caption line.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final action in actions)
          Expanded(
            child: _CompactAction(
                action: action, source: source, isLight: isLight, colors: c),
          ),
      ],
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction(
      {required this.action,
      required this.source,
      required this.isLight,
      required this.colors});

  final KuteDockAction action;
  final String source;
  final bool isLight;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final enabled = action.onTap != null && !action.soon;
    final solid = action.solid;
    final foreground = solid ? context.ctaOnColor : c.textPrimary;
    const size = KuteCompactActions.squareSize;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: action.label,
        excludeSemantics: true,
        child: _glyphPress(action, enabled, KutePressable(
          enabled: enabled,
          child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: !enabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    TrackingService.quickAction(action.trackingId,
                        source: source);
                    action.onTap!();
                  },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: size,
                    height: size,
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
                    // The bitcoin and dollar glyphs are thin letterforms
                    // next to the arrows and the ring, so they read a size
                    // up (founder, 1 and 2 November 2026).
                    child: action.glyph?.call(foreground, 22) ??
                        Icon(action.icon,
                            size: action.icon ==
                                        Icons.currency_bitcoin_rounded ||
                                    action.icon == Icons.attach_money_rounded
                                ? 28
                                : 22,
                            color: foreground),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    action.label,
                    // Two lines for a longer verb ("Manage with AI") rather
                    // than an ellipsis.
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (action.caption != null || action.soon)
                    Padding(
                      padding: EdgeInsets.only(top: 1.h),
                      child: Text(
                        action.soon
                            ? context.l10n.actionSoon
                            : action.caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        )),
      ),
    );
  }
}

/// [child] under a [GlyphPressScope] when [action] draws a glyph, so a
/// press anywhere on the button plays the glyph's press.
Widget _glyphPress(KuteDockAction action, bool enabled, Widget child) =>
    action.glyph == null
        ? child
        : GlyphPressScope(enabled: enabled, child: child);

/// A money verb in the dock, wearing the same neutral chrome as the search
/// square so the three controls read as one row, or, when [KuteDockAction.solid],
/// the primary CTA's monochrome fill (ctaFill / ctaOnColor, no border, and
/// AppButton's 0.35 disabled opacity). Same size, radius and press either
/// way. No tinted fills.
class KuteDockActionButton extends StatelessWidget {
  const KuteDockActionButton({
    super.key,
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
      child: _glyphPress(action, enabled, KutePressable(
        enabled: enabled,
        child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: solid ? context.ctaFill : (isLight ? Colors.white : c.surface),
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
                    action.glyph?.call(iconColor, 20.sp) ??
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
        )),
      ),
    );
  }
}

/// The floating pill's height (a hair more with a second line).
const double _kDockPillHeight = 50;
const double _kDockPillTallHeight = 56;

/// THE FLOATING SAL PILL, the one chrome of the bar everywhere (the docks on
/// Home and Dollars, the shell bar over everything else): Sal's clip, a label
/// and an optional second line, in the pill's own frost; in light mode the
/// primary button's dark fill with white words, the second line quieter,
/// white in dark mode (kute_bar_surface.dart). When the context
/// changes ("Search investments or Manage with AI" ↔ "Search predictions or
/// manage with AI" on the Dollars tab) it morphs EXACTLY as the bar's primary
/// button does (kute_morph_label.dart): the width springs on the chip spring
/// ([KuteMorphSize]), the old words slide up and out while the new ones rise
/// from below ([KuteMorphLabel]), and Sal's clip crossfades ([KuteMorphFace]).
/// At once under Reduce Motion.
class KuteSalPill extends StatelessWidget {
  const KuteSalPill({
    super.key,
    required this.label,
    this.sublabel,
    this.clip = 'search',
    this.aiEnabled = true,
    this.collapsed = false,
    this.salCue = 0,
    this.salSize = kSalPillGlyphSize,
    this.badge,
    this.onSalFrame,
    required this.onTap,
  });

  final String label;
  final String? sublabel;
  final String clip;
  final bool aiEnabled;

  /// The pill folded to Sal alone, a [collapsedSize] circle (the shell bar
  /// while a market page scrolls down): the text slides out and the width
  /// follows it on the chip spring; the tap still opens the same sheet.
  final bool collapsed;

  /// Bumped to play [clip] from its start once at 1.3x and then loop (the
  /// bar arriving on a market page); 0 plays it as it is.
  final int salCue;
  final VoidCallback onTap;

  /// Sal's side in the pill ([kSalPillGlyphSize]); the round share button
  /// draws him smaller, the whole head inside its circle.
  final double salSize;

  /// Drawn over the collapsed circle at its bottom right, past its edge
  /// (the round share button's share badge), pressed with it; null: none.
  final Widget? badge;

  /// Every frame Sal's clip shows ([SalSprite.onFrame]): repaint from it.
  final ValueChanged<SalSpriteFrame>? onSalFrame;

  /// The collapsed circle's side.
  static const double collapsedSize = 52;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    // DARK IN LIGHT MODE (founder, 7 November 2026; kute_bar_surface.dart):
    // the primary button's fill and white words, the second line quieter;
    // a white pill blended into the white cards behind it. White in dark
    // mode (founder, 2 November 2026: on dark the white pill reads far
    // better than the surface grey), its ink dark there.
    final fill =
        isLight ? KuteBarSurface.fill(context) : KuteBarSurface.whiteFill;
    final labelColor =
        isLight ? KuteBarSurface.ink : KuteBarSurface.inkOnWhite;
    final sublabelColor =
        isLight ? KuteBarSurface.quietInk : KuteBarSurface.quietInkOnWhite;
    final glyphColor = isLight ? KuteBarSurface.ink : c.textPrimary;
    final reduce = kuteReduceMotion(context);
    final height = collapsed
        ? collapsedSize
        : (sublabel == null ? _kDockPillHeight : _kDockPillTallHeight);
    // Reduce Motion: at once.
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: TextStyle(
            color: labelColor,
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        if (sublabel != null)
          Text(
            sublabel!,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: TextStyle(
              color: sublabelColor,
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      label: sublabel == null ? label : '$label, $sublabel',
      excludeSemantics: true,
      child: _Frosted(
        child: KutePressable(
          child: _withBadge(AnimatedContainer(
            key: const ValueKey('dock-search-pill'),
            duration: duration,
            curve: reduce ? Curves.linear : KuteMotion.chip,
            height: height,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(_kDockPillTallHeight / 2),
              // The light hairline keeps the dark pill apart from dark
              // content (the black Purchase square, a dark share card).
              border: Border.all(
                color: isLight ? KuteBarSurface.edge : Colors.white,
                width: isLight ? KuteBarSurface.edgeWidth : 0.5,
              ),
              // ONE shadow in both modes, at the same blur (transparent
              // in dark): the chip spring overshoots past 1, and a theme
              // switch lerping a shadow towards none scaled its blur
              // negative (the red "Text shadow blur radius should be
              // non-negative" screen on every light/dark toggle).
              boxShadow: [KuteBarSurface.shadow(visible: isLight)],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(_kDockPillTallHeight / 2),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                borderRadius: BorderRadius.circular(_kDockPillTallHeight / 2),
                onTap: onTap,
                child: AnimatedPadding(
                  duration: duration,
                  curve: reduce ? Curves.linear : KuteMotion.settle,
                  // Collapsed: the glyph ([salSize], 38) centred in the
                  // circle, the border counted in its side.
                  padding: collapsed
                      ? EdgeInsets.symmetric(
                          horizontal: (collapsedSize - salSize) / 2 -
                              (isLight ? 1.0 : 0.5))
                      : EdgeInsets.fromLTRB(8.w, 0, 18.w, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      aiEnabled
                          ? _SalPillGlyph(
                              lensColor: glyphColor,
                              clip: clip,
                              cue: salCue,
                              size: salSize,
                              onFrame: onSalFrame)
                          : Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6.w),
                              child: Icon(Icons.search_rounded,
                                  size: 22, color: glyphColor),
                            ),
                      // The width follows the text on the chip spring;
                      // the text itself slides up and out, in from below
                      // (the primary button's morph, kute_morph_label.dart).
                      // Collapsed, the text (and its gap) is gone: the
                      // leaving words overflow the empty box, so the width
                      // springs down while they slide out under the
                      // shrinking edge, not after they have gone.
                      Flexible(
                        child: KuteMorphSize(
                          alignment: Alignment.centerLeft,
                          child: KuteMorphLabel(
                            child: collapsed
                                ? const SizedBox.shrink(
                                    key: ValueKey('sal-pill-collapsed'))
                                : Padding(
                                    key: ValueKey('$label|$sublabel'),
                                    padding: EdgeInsets.only(left: 6.w),
                                    // The two lines are sized in .sp: on a
                                    // tablet they outgrow the 56 pill, so
                                    // they scale down there (never up),
                                    // laid out in the pill's width as ever
                                    // (a long label still fades at its end).
                                    child: LayoutBuilder(
                                      builder: (context, box) => FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth: box.maxWidth),
                                          child: text,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )),
        ),
      ),
    );
  }

  /// [pill] with [badge] over its bottom right, past the circle's edges
  /// by [kSalPillBadgeOverhang]; the badge takes no taps of its own.
  Widget _withBadge(Widget pill) {
    final badge = this.badge;
    if (badge == null) return pill;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        Positioned(
          right: -kSalPillBadgeOverhang,
          bottom: -kSalPillBadgeOverhang,
          child: IgnorePointer(child: badge),
        ),
      ],
    );
  }
}

/// Sal's side in the Sal pill and its collapsed circle (the toast's too:
/// kute_bar_surface.dart).
const double kSalPillGlyphSize = KuteBarSurface.salSize;

/// How far a [KuteSalPill.badge] (26 across with its ring) stands past
/// the collapsed circle's right and bottom edges: its centre sits on the
/// circle's 45 degree radius, 4 inside the edge.
const double kSalPillBadgeOverhang = 2.5;

/// Sal in the pill (see [KuteBottomActionBar]): the `search` clip, 1.8x
/// while results load, `happy` for 600 ms when they land, then `search`
/// again. The static glyph until the sheets exist. A [cue] (the bar
/// arriving on a market page) plays the clip from its start once at 1.3x,
/// then looping. A reaction ([SalReactions], sal_reactions.dart: a cheer
/// for money in, a wink for a fill, a shake for an error, a think for a
/// long load) plays once over whatever he wears and crossfades back.
class _SalPillGlyph extends StatefulWidget {
  const _SalPillGlyph({
    required this.lensColor,
    this.clip = 'search',
    this.cue = 0,
    this.size = kSalPillGlyphSize,
    this.onFrame,
  });

  final Color lensColor;

  /// The context's clip at rest (`search`, `share`, `idle`).
  final String clip;

  /// See [KuteSalPill.salCue].
  final int cue;

  /// See [KuteSalPill.salSize].
  final double size;

  /// See [KuteSalPill.onSalFrame].
  final ValueChanged<SalSpriteFrame>? onFrame;

  @override
  State<_SalPillGlyph> createState() => _SalPillGlyphState();
}

class _SalPillGlyphState extends State<_SalPillGlyph> {
  bool _loading = false;
  bool _happy = false;
  bool _intro = false;
  Timer? _happyTimer;
  SalReactionEvent? _reaction;

  @override
  void initState() {
    super.initState();
    _loading = kuteSearchLoading.value;
    kuteSearchLoading.addListener(_onLoading);
    SalReactions.current.addListener(_onReaction);
    _reaction = SalReactions.current.value;
    _intro = widget.cue != 0;
  }

  void _onReaction() {
    final event = SalReactions.current.value;
    if (event == null || event == _reaction) return;
    setState(() => _reaction = event);
  }

  /// The reaction played (or could not be read): back to the context's clip.
  void _reactionDone(SalReactionEvent event) {
    SalReactions.clear(event);
    if (mounted && _reaction == event) setState(() => _reaction = null);
  }

  @override
  void didUpdateWidget(covariant _SalPillGlyph old) {
    super.didUpdateWidget(old);
    if (old.cue != widget.cue) {
      _intro = widget.cue != 0;
    } else if (old.clip != widget.clip) {
      // Another clip took over mid-intro: it plays as it is.
      _intro = false;
    }
  }

  void _onLoading() {
    final loading = kuteSearchLoading.value;
    if (loading == _loading) return;
    // A search that lasts 2 s: Sal thinks (sal_reactions.dart).
    SalReactions.loading(kuteSearchLoading, loading);
    final landed = _loading && !loading;
    setState(() {
      _loading = loading;
      if (landed) _happy = true;
    });
    if (landed) {
      _happyTimer?.cancel();
      _happyTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _happy = false);
      });
    }
  }

  @override
  void dispose() {
    _happyTimer?.cancel();
    kuteSearchLoading.removeListener(_onLoading);
    SalReactions.current.removeListener(_onReaction);
    // A load this glyph reported ends with it.
    SalReactions.loading(kuteSearchLoading, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final rig = KuteStillWhenCovered(
        child: KuteDogMagnifier(
            size: size * 34 / kSalPillGlyphSize,
            lensColor: widget.lensColor));
    final reaction = _reaction;
    final clip = reaction != null
        ? reaction.clip
        : _loading
            ? 'search'
            : (_happy ? 'happy' : widget.clip);
    final intro = reaction == null && _intro && clip == widget.clip;
    final oneShot = intro || reaction != null;
    // The clip switch crossfades as the primary button's Sal does
    // (KuteMorphFace: 150 ms, at once under Reduce Motion).
    // A new cue restarts the clip (its key), so the intro begins at
    // frame 0; once through, the same sprite loops on from its last frame.
    // A reaction is keyed by its number, so the same one twice plays twice.
    return KuteMorphFace(
      child: SalSprite(
        key: ValueKey(reaction != null
            ? 'reaction-$clip#${reaction.seq}'
            : '$clip#${widget.cue}'),
        clip: clip,
        size: size,
        speed: _loading && reaction == null ? 1.4 : (intro ? 1.3 : 1.0),
        loop: oneShot ? false : null,
        onComplete: reaction != null
            ? () => _reactionDone(reaction)
            : intro
                ? () {
                    if (mounted) setState(() => _intro = false);
                  }
                : null,
        // A reaction clip that is not there: back to the context's clip.
        onUnavailable: reaction != null ? () => _reactionDone(reaction) : null,
        onFrame: widget.onFrame,
        // A clip that cannot be read: `happy` stands in for the share and
        // idle faces and a reaction, the rig (the magnifier, search's
        // glyph) under that and for search.
        fallback: clip == 'share' || clip == 'idle' || reaction != null
            ? SalSprite(clip: 'happy', size: size, fallback: rig)
            : rig,
      ),
    );
  }
}

/// A floating control's own frost: the blur under its bounds plus 8 px
/// (half the old band's sigma), never a band across the screen.
class _Frosted extends StatelessWidget {
  const _Frosted({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -8,
            right: -8,
            top: -8,
            bottom: -8,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(31),
                child: const KuteBlur(
                  sigmaX: 2.0,
                  sigmaY: 2.0,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
          child,
        ],
      );
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
