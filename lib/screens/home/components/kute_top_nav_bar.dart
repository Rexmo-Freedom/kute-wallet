// lib/screens/home/components/kute_top_nav_bar.dart
//
// Integrated top navigation bar: the Bitcoin | Dollars switch
// ([HomeTabSwitch], founder 8 November 2026) filling the bar from the
// page's 16 margin up to the ONE square button on the RIGHT that opens the
// Financial hub (founder, 12 November 2026: "the selector should sort of
// occupy the whole top bar"): the wallet list, switch wallet and Add wallet,
// Notifications in its header and a Settings row. For any other wallet its
// tab chips ([ServiceTabStrip]) fill the row up to the button in the same way.
// Its glyph is a rounded "+" with a small gear badge at its lower right
// (owner decision October 2026: one glyph for "add" and "settings", the two
// jobs behind it; it is the only door to the hub on the shell, and a pushed
// wallet screen opens the hub from its name).
// Mounted at the TOP of the shell so the tabs are always visible and
// consistent across screens; the bottom is the dock.
//
// The bar is now mounted ONCE in the persistent nav shell (see
// lib/screens/app_shell.dart), so it auto-hides via the shared
// [navBarHiddenProvider] instead of a per-screen scroll controller: whichever
// tab page is on screen drives that provider from its own scroll listener,
// and this bar WATCHES it, sliding up off the top edge when hidden.

import 'dart:async';
import 'dart:math' as math;

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/nav_bar_visibility_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/screens/home/components/action_pill.dart';
import 'package:kute/screens/home/components/desktop_top_bar_money.dart';
import 'package:kute/screens/shared/kute_wordmark.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/home/components/home_tab_switch.dart'
    show homeTabSwitchTrackHeight;
import 'package:kute/screens/shared/kute_back_button.dart' show kKuteNavHitSize;
import 'package:kute/screens/shared/wallet_money_actions.dart';
import 'package:kute/theme/app_theme.dart';

/// The hub button's square, in design units (pre-`.w`).
const double _kHubButtonSize = 46;

class KuteTopNavBar extends ConsumerWidget {
  final ActiveNavTab activeTab;

  /// Called when a DIFFERENT tab is tapped — the shell switches its
  /// go_router branch (see AppShell._selectTab). Tapping the ACTIVE tab is
  /// handled inside the pill itself (its deposit-menu affordances), so this
  /// only ever fires for a tab change.
  final void Function(ActiveNavTab)? onSelectTab;

  /// The shell's continuous page position, for the Bitcoin | Dollars
  /// switch's thumb; null with no pager.
  final Animation<double>? pagePosition;

  const KuteTopNavBar({
    super.key,
    required this.activeTab,
    this.onSelectTab,
    this.pagePosition,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // EXPANDED (a laptop): the desktop top bar, which stays put.
    if (kuteWindowIsExpanded(context)) {
      return _KuteDesktopTopBar(
        activeTab: activeTab,
        onSelectTab: onSelectTab,
        pagePosition: pagePosition,
        switchStrip: shellStripIsSwitch(
            ref.watch(shellWalletProvider), ref.watch(shellVenueOwnerProvider)),
      );
    }
    // Shared hide state, written by whichever tab page is on screen from its
    // own scroll listener (reverse = hide, forward / near-top = show).
    final hidden = ref.watch(navBarHiddenProvider);
    // Honor Reduce Motion (2027 accessibility principle): slide the bar
    // instantly for users who opt out of non-essential animation.
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final centred = shellStripIsSwitch(
        ref.watch(shellWalletProvider), ref.watch(shellVenueOwnerProvider));
    // The hub button's slot. The bar's inset puts the square's own edge on
    // the page's 16 margin; the switch starts on the left one.
    final slot = math.max(kKuteNavHitSize, _kHubButtonSize.w);
    final edge = 16.w - (slot - _kHubButtonSize.w) / 2;
    // The switch's 44 pt targets reach above its track on a narrow phone
    // rather than pushing the track down towards the page.
    final top = centred
        ? math.max(0.0, 6.h - (slot - homeTabSwitchTrackHeight()) / 2)
        : 6.h;

    final bar = SafeArea(
      bottom: false,
      // A phone's width from MEDIUM up, centred, never stretched
      // (kute_wide_frames.dart); the switch is clicked there, not swiped.
      child: KutePhoneColumn(
        child: Padding(
          padding: EdgeInsets.fromLTRB(centred ? 16.w : 12.w, top, edge, 6.h),
          // No enclosing band: the switch and the hub button float. The
          // strip's region is bounded by Expanded, so it can never grow under
          // or collide with the button.
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  // The switch's gap to the button's slot.
                  padding: EdgeInsetsDirectional.only(end: centred ? 8.w : 0),
                  child: FloatingActionPill(
                    activeTab: activeTab,
                    onSelectTab: onSelectTab,
                    pagePosition: pagePosition,
                  ),
                ),
              ),
              if (!centred) SizedBox(width: 12.w),
              // The ONE trailing button: the +-and-gear into the Financial
              // hub.
              SizedBox(
                width: slot,
                child: Center(child: _FinancialHubButton(activeTab: activeTab)),
              ),
            ],
          ),
        ),
      ),
    );

    // Slide up off the top edge when hidden (content scrolls underneath).
    return AnimatedSlide(
      offset: hidden ? const Offset(0, -1) : Offset.zero,
      duration: reduceMotion ? Duration.zero : kNavBarSlideDuration,
      curve: Curves.easeOut,
      child: IgnorePointer(ignoring: hidden, child: bar),
    );
  }
}

/// THE DESKTOP TOP BAR (founder, 25 November 2026: "Tabs on top look bad
/// in desktop"; wide_design_2.md, A). On EXPANDED one bar across the
/// window (its gutters, [KuteLayout.paneGap]), [kuteTopBarHeight]
/// tall, in place of the phone strip centred in an empty band:
///   * LEFT: Sal and the wordmark, the lockup the PIN screen shows
///     (kute_pin_scaffold.dart), then the Bitcoin | Dollars switch beside
///     it at its phone size (another wallet's tab strip likewise).
///   * CENTRE: the active tab's balance ([KuteDesktopMoney.balance];
///     founder, 26 November 2026: "the balance always on the top"; 24
///     November 2026: "make the balance bigger in the center"), in the
///     bar's own middle, held clear of the switch and the actions on a
///     narrower window ([_TopBarSlots]).
///   * RIGHT: its actions ([KuteDesktopMoney.actions]), then the hub
///     button. The search stays the floating
///     bar's pill at the foot, as on a phone (founder, 25 November 2026:
///     "put the search on the bottom always"). The actions lose their
///     words under [_labelsMinWidth] and the switch narrows under
///     [_narrowBelow]; the bar is always one row.
/// It does not hide on scroll: a laptop has the room. MEDIUM and phones
/// keep the strip above.
class _KuteDesktopTopBar extends StatelessWidget {
  const _KuteDesktopTopBar({
    required this.activeTab,
    required this.onSelectTab,
    required this.pagePosition,
    required this.switchStrip,
  });

  final ActiveNavTab activeTab;
  final void Function(ActiveNavTab)? onSelectTab;
  final Animation<double>? pagePosition;

  /// The Bitcoin | Dollars switch (else another wallet's tab strip).
  final bool switchStrip;

  /// The switch at its phone size: a phone's column less its gutters and
  /// the hub button's slot.
  static const double _switchWidth = 340;

  /// Another wallet's tab strip, a little wider (its chips scroll).
  static const double _stripWidth = 440;

  /// Narrower than this the switch steps down to [_switchWidthNarrow].
  static const double _narrowBelow = 1200;

  /// The switch on a narrower window, leaving the money its room.
  static const double _switchWidthNarrow = 280;

  /// The actions carry their words from here up; under it, icons with
  /// tooltips (never a second row).
  static const double _labelsMinWidth = 1280;

  /// The same on Dollars, whose row has a fifth pill (Portfolio).
  static const double _labelsMinWidthDollars = 1400;

  @override
  Widget build(BuildContext context) {
    final window = kuteWindowWidth(context);
    final narrow = window < _narrowBelow;
    // It stays put while the page scrolls under it, so it is drawn on the
    // page's own background across the window: a scrolled card never
    // shows through the switch.
    return ColoredBox(
      color: context.colors.background,
      child: SafeArea(
        bottom: false,
        // Across the whole window (founder, 24 November 2026: "occupy
        // full screen?"): the lockup on the window's left gutter, the
        // Dollars browse's edge under it, the hub on the right gutter.
        child: Center(
          heightFactor: 1,
          child: SizedBox(
            key: const ValueKey('kute-desktop-top-bar'),
            height: kuteTopBarHeight,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: KuteLayout.paneGap),
              child: CustomMultiChildLayout(
                delegate: _TopBarSlots(),
                children: [
                  LayoutId(
                    id: _TopBarSlot.left,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _KuteLockup(),
                        SizedBox(width: narrow ? 20 : 28),
                        SizedBox(
                          width: switchStrip
                              ? (narrow ? _switchWidthNarrow : _switchWidth)
                              : _stripWidth,
                          child: FloatingActionPill(
                            activeTab: activeTab,
                            onSelectTab: onSelectTab,
                            pagePosition: pagePosition,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The active tab's balance in the bar's centre, its
                  // actions at the right, as the fintech desktops put
                  // the money (desktop_top_bar_money.dart).
                  LayoutId(
                    id: _TopBarSlot.centre,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: KuteDesktopMoney.balance(activeTab: activeTab),
                    ),
                  ),
                  LayoutId(
                    id: _TopBarSlot.right,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KuteDesktopMoney.actions(
                            activeTab: activeTab,
                            labels: window >=
                                (activeTab == ActiveNavTab.usd
                                    ? _labelsMinWidthDollars
                                    : _labelsMinWidth)),
                        const SizedBox(width: 16),
                        _FinancialHubButton(activeTab: activeTab),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TopBarSlot { left, centre, right }

/// The desktop top bar's three places: the left group at the left edge,
/// the right group at the right edge, and the balance in the bar's TRUE
/// centre (the window's, not the middle of whatever room is left), moved
/// off it only as far as keeping [_gap] from either group asks, and
/// scaled down (its [FittedBox]) if even that room is too little.
class _TopBarSlots extends MultiChildLayoutDelegate {
  _TopBarSlots();

  static const double _gap = 20;

  @override
  void performLayout(Size size) {
    final left = layoutChild(_TopBarSlot.left, BoxConstraints.loose(size));
    final right = layoutChild(
        _TopBarSlot.right,
        BoxConstraints.loose(
            Size(math.max(0, size.width - left.width), size.height)));
    final room =
        math.max(0.0, size.width - left.width - right.width - 2 * _gap);
    final centre = layoutChild(
        _TopBarSlot.centre, BoxConstraints.loose(Size(room, size.height)));
    double middle(Size child) => (size.height - child.height) / 2;
    positionChild(_TopBarSlot.left, Offset(0, middle(left)));
    positionChild(
        _TopBarSlot.right, Offset(size.width - right.width, middle(right)));
    final least = left.width + _gap;
    final most = math.max(least, size.width - right.width - _gap - centre.width);
    final x = ((size.width - centre.width) / 2).clamp(least, most);
    positionChild(_TopBarSlot.centre, Offset(x, middle(centre)));
  }

  @override
  bool shouldRelayout(_TopBarSlots oldDelegate) => false;
}

/// Sal and the wordmark as one lockup, as the PIN screen shows them.
class _KuteLockup extends StatelessWidget {
  const _KuteLockup();

  @override
  Widget build(BuildContext context) {
    return const Row(
      key: ValueKey('kute-top-bar-lockup'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SalSprite(
          clip: 'blink',
          size: 36,
          fallback: SizedBox(width: 36, height: 36),
        ),
        SizedBox(width: 8),
        KuteWordmark(size: 24),
      ],
    );
  }
}

/// The Financial hub door: the "+"-with-a-gear glyph ([HubPlusGearGlyph])
/// in the neutral square chip (founder, 8 November 2026: "should be square
/// like it was before"), right of the tab strip. It opens the hub sheet: wallets and Add wallet, with
/// Settings and Notifications side by side in its header. The
/// `wallet_actions_opened` source names the tab it was opened on:
/// home_plus | usd_plus | trading_plus | predictions_plus | bank_plus.
class _FinancialHubButton extends StatefulWidget {
  const _FinancialHubButton({required this.activeTab});

  final ActiveNavTab activeTab;

  @override
  State<_FinancialHubButton> createState() => _FinancialHubButtonState();
}

class _FinancialHubButtonState extends State<_FinancialHubButton> {
  /// Pinged on each press, so the glyph's gear turns a quick tooth.
  final _pressed = _Ping();

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      button: true,
      label: context.l10n.financialHubAndSettings,
      child: GestureDetector(
        key: const ValueKey('financial-hub-button'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _pressed.ping(),
        onTap: () {
          HapticFeedback.selectionClick();
          showWalletMoneyActions(context,
              source: switch (widget.activeTab) {
                ActiveNavTab.home => 'home_plus',
                ActiveNavTab.usd => 'usd_plus',
                ActiveNavTab.trading => 'trading_plus',
                ActiveNavTab.predictions => 'predictions_plus',
                ActiveNavTab.bank => 'bank_plus',
              });
        },
        // The same neutral square chip the dock's button and the header
        // shortcuts wear: rounded square, the light-mode white fill with
        // its soft lift, a hairline rather than a full-weight rim.
        // The target stays 44 pt on a narrow phone, where the square scales.
        child: SizedBox.square(
          dimension: math.max(kKuteNavHitSize, _kHubButtonSize.w),
          child: Center(
            child: Container(
              key: const ValueKey('financial-hub-square'),
              width: _kHubButtonSize.w,
              height: _kHubButtonSize.w,
              alignment: Alignment.center,
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
              child: HubPlusGearGlyph(
                  color: c.textPrimary, size: 24.sp, pressed: _pressed),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// One play of the hub glyph, a swap of prominence: the gear grows and
/// moves in towards the centre (turning a tooth) while the "+" shrinks
/// back to the top left, it holds there, then they swap back (the gear
/// turning another tooth) to the rest frame. As fractions of the play:
/// the swap in ends at [_kHubInEnd], the swap back starts at
/// [_kHubOutStart].
const int _kHubBeatMs = 1700;
const double _kHubInEnd = 650 / 1700;
const double _kHubOutStart = 1050 / 1700;

/// A press: the same swap, quickly.
const int _kHubPressMs = 500;
const double _kHubPressInEnd = 190 / 500;
const double _kHubPressOutStart = 280 / 500;

/// How prominent the gear is at [v] (0..1 through a play): 0 at rest, 1
/// while held, eased in and out between.
double _hubSwap(double v, double inEnd, double outStart) {
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 - Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// The gear's turn at [v], in teeth: one on the way in, one on the way
/// back, so it ends where it began (six teeth, 60° a tooth).
double _hubTurn(double v, double inEnd, double outStart) {
  if (v <= 0 || v >= 1) return 0;
  if (v < inEnd) return Curves.easeInOut.transform(v / inEnd);
  if (v <= outStart) return 1;
  return 1 + Curves.easeInOut.transform((v - outStart) / (1 - outStart));
}

/// One glyph for the hub's two jobs: a thick rounded "+" (add) with a
/// small solid gear badge over its lower-right (settings), the gear in a
/// cut-out ring so the two shapes stay apart. On the 24-unit grid of the
/// app's rounded header icons with 2-unit strokes; painted in device
/// pixels so the plus lands on whole pixels, and the cut-out is cleared
/// rather than filled, so the chip's own colour shows through in light
/// and dark. Takes [color] straight from the theme.
///
/// Motion is a short beat, not a loop: when it appears and then once every
/// [interval], the two swap prominence ([_kHubBeatMs]): the gear grows in
/// towards the centre, turning, as the "+" shrinks back to the top left;
/// a hold; then they swap back. Each press plays a quick swap
/// ([_kHubPressMs], via [pressed]). The gear keeps its cut-out ring at
/// every frame, so the two never merge. Nothing ticks in between. No new play
/// starts while another route covers this one (one in flight finishes;
/// coming back into view plays once), and it holds still while the app is
/// in the background, while its tickers are off, and for good under
/// Reduce Motion.
class HubPlusGearGlyph extends StatefulWidget {
  const HubPlusGearGlyph({
    super.key,
    required this.color,
    this.size = 24,
    this.pressed,
    this.interval = const Duration(seconds: 9),
  });

  final Color color;
  final double size;

  /// Notifies on each press of the button around the glyph.
  final Listenable? pressed;

  /// Rest between plays.
  final Duration interval;

  @override
  State<HubPlusGearGlyph> createState() => _HubPlusGearGlyphState();
}

class _HubPlusGearGlyphState extends State<HubPlusGearGlyph>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  Timer? _next;
  bool _reduce = false;
  bool _tickerOff = false;
  bool _covered = false;
  bool _foreground = true;

  /// Whether the play in flight is a press (gear only, quick).
  bool _press = false;

  bool get _halted => _reduce || _tickerOff || !_foreground;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: _kHubBeatMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_covered && !_halted) {
          _schedule(widget.interval);
        }
      });
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.pressed?.addListener(_onPressed);
  }

  @override
  void didUpdateWidget(HubPlusGearGlyph old) {
    super.didUpdateWidget(old);
    if (old.pressed != widget.pressed) {
      old.pressed?.removeListener(_onPressed);
      widget.pressed?.addListener(_onPressed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _tickerOff = !TickerMode.valuesOf(context).enabled;
    _covered = !(ModalRoute.isCurrentOf(context) ?? true);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// Plays on appearing (and on coming back into view), rests otherwise.
  void _sync() {
    if (_halted) {
      _cancel();
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0;
      return;
    }
    if (_covered) {
      _cancel();
      return;
    }
    if (_controller.isAnimating || _next != null) return;
    _play(press: false);
  }

  void _onPressed() {
    if (_halted || _controller.isAnimating) return;
    _cancel();
    _play(press: true);
  }

  void _play({required bool press}) {
    _press = press;
    _controller.duration =
        Duration(milliseconds: press ? _kHubPressMs : _kHubBeatMs);
    _controller.forward(from: 0);
  }

  void _schedule(Duration wait) {
    _cancel();
    _next = Timer(wait, () {
      _next = null;
      if (!mounted || _halted || _covered) return;
      _play(press: false);
    });
  }

  void _cancel() {
    _next?.cancel();
    _next = null;
  }

  @override
  void dispose() {
    widget.pressed?.removeListener(_onPressed);
    WidgetsBinding.instance.removeObserver(this);
    _cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final size = Size.square(widget.size);
    if (_reduce) {
      return CustomPaint(
          size: size, painter: _HubPlusGearPainter(widget.color, dpr));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          var swap = 0.0, turn = 0.0;
          if (_controller.isAnimating) {
            final v = _controller.value;
            final inEnd = _press ? _kHubPressInEnd : _kHubInEnd;
            final outStart = _press ? _kHubPressOutStart : _kHubOutStart;
            swap = _hubSwap(v, inEnd, outStart);
            turn = _hubTurn(v, inEnd, outStart);
          }
          return CustomPaint(
            size: size,
            painter:
                _HubPlusGearPainter(widget.color, dpr, swap: swap, turn: turn),
          );
        },
      ),
    );
  }
}

class _HubPlusGearPainter extends CustomPainter {
  const _HubPlusGearPainter(this.color, this.dpr,
      {this.swap = 0, this.turn = 0});

  final Color color;
  final double dpr;

  /// How prominent the gear is: 0 the rest frame (big "+", gear badge),
  /// 1 the swap held (big gear, small "+" at the top left).
  final double swap;

  /// How many teeth (60° each) the gear has turned.
  final double turn;

  // On the 24-unit grid, at rest: the plus about (11, 11), arms 7 either
  // way, 2-unit strokes; the gear badge about (18.5, 18.5), six teeth,
  // its cut-out and its hole. Held: the plus about (4, 4), arms 2.8,
  // 1.6-unit strokes, and the gear about (13.5, 13.5) at [_gearBig] times
  // its size, its cut-out clear of the plus, so neither covers the other.
  static const double _plus = 11;
  static const double _arm = 7;
  static const double _stroke = 2;
  static const double _plusSmall = 4;
  static const double _armSmall = 2.8;
  static const double _strokeSmall = 1.6;
  static const double _gear = 18.5;
  static const double _gearIn = 13.5;
  static const double _gearBig = 9 / 5.4;
  static const int _teeth = 6;
  static const double _tip = 5.4;
  static const double _root = 4.1;
  static const double _tipHalf = 0.26; // radians either side of a tooth
  static const double _rootHalf = 0.3;
  static const double _gap = 1.5;
  static const double _hole = 1.7;

  /// The filled gear, centred on [centre], [k] device px a unit, turned
  /// [rotation] radians.
  static Path _gearPath(Offset centre, double k, double rotation) {
    final rTip = _tip * k, rRoot = _root * k;
    Offset polar(double r, double a) =>
        centre + Offset(r * math.cos(a), r * math.sin(a));
    const pitch = 2 * math.pi / _teeth;
    // Half a pitch off vertical: a gap at the top, as the candidate sat.
    final start = -math.pi / 2 + pitch / 2 + rotation;
    final tipRect = Rect.fromCircle(center: centre, radius: rTip);
    final rootRect = Rect.fromCircle(center: centre, radius: rRoot);
    final gear = Path();
    for (var i = 0; i < _teeth; i++) {
      final a = start + i * pitch;
      if (i == 0) {
        final p0 = polar(rRoot, a - _rootHalf);
        gear.moveTo(p0.dx, p0.dy);
      } else {
        gear.arcTo(
            rootRect, a - pitch + _rootHalf, pitch - 2 * _rootHalf, false);
      }
      final up = polar(rTip, a - _tipHalf);
      gear.lineTo(up.dx, up.dy);
      gear.arcTo(tipRect, a - _tipHalf, 2 * _tipHalf, false);
      final down = polar(rRoot, a + _rootHalf);
      gear.lineTo(down.dx, down.dy);
    }
    gear.arcTo(rootRect, start + (_teeth - 1) * pitch + _rootHalf,
        pitch - 2 * _rootHalf, false);
    gear.close();
    return gear;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(1 / dpr);
    // Device pixels per grid unit; the grid centred in the square.
    final side = size.shortestSide * dpr;
    final k = side / 24;
    canvas.translate(((size.width * dpr - side) / 2).roundToDouble(),
        ((size.height * dpr - side) / 2).roundToDouble());

    // A layer, so the gear's cut-out clears the plus to the chip beneath.
    canvas.saveLayer(Rect.fromLTWH(-k, -k, 26 * k, 26 * k), Paint());

    double lerp(double a, double b) => a + (b - a) * swap;

    // The plus: a whole number of device pixels wide, centred so both
    // strokes' edges land on pixel boundaries, at every frame.
    final w = math.max(1, (lerp(_stroke, _strokeSmall) * k).round()).toDouble();
    double onGrid(double v) =>
        w % 2 == 0 ? v.roundToDouble() : (v - 0.5).roundToDouble() + 0.5;
    final at = lerp(_plus, _plusSmall) * k;
    final pc = Offset(onGrid(at), onGrid(at));
    final arm = (lerp(_arm, _armSmall) * k).roundToDouble();
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(pc - Offset(arm, 0), pc + Offset(arm, 0), pen);
    canvas.drawLine(pc - Offset(0, arm), pc + Offset(0, arm), pen);

    // The gear in its cut-out (a fixed-width ring at every size), and its
    // hole.
    final g = lerp(_gear, _gearIn) * k;
    final gc = Offset(g, g);
    final gk = k * lerp(1, _gearBig);
    final badge = _gearPath(gc, gk, turn * 2 * math.pi / _teeth);
    final clear = Paint()..blendMode = BlendMode.clear;
    canvas.drawPath(badge, clear);
    canvas.drawPath(
        badge,
        Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = _gap * 2 * k);
    canvas.drawPath(badge, Paint()..color = color);
    canvas.drawCircle(gc, _hole * gk, clear);

    canvas.restore(); // layer
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HubPlusGearPainter old) =>
      old.color != color ||
      old.dpr != dpr ||
      old.swap != swap ||
      old.turn != turn;
}
