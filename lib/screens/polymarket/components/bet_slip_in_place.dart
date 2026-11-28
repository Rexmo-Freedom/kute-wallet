// lib/screens/polymarket/components/bet_slip_in_place.dart
//
// THE BET SLIP IN PLACE (wide layouts; founder, 24 November 2026: "showing
// the graphs on the left with the interfaces on the right"). On EXPANDED a
// market page (a market, an event, a game, a timed round) lays its chart
// and outcomes out on the left and keeps the bet slip open on the right,
// in its own pane, instead of raising it as a bottom sheet.
//
// The page wraps its body in a [BetSlipInPlaceHost] and draws a
// [BetSlipInPlacePane] where the slip goes. Every door that opens a slip
// on the page (the outcomes' Yes / No, a game's sides, a round card's Up /
// Down) still calls [BetSlipSheet.show] exactly as it does on a phone: the
// same guards and the same slip; only the last step changes, the slip
// handed to the host ([BetSlipInPlaceHostState.present]) rather than
// pushed as a sheet. Nothing about money moves here: the slip in the pane
// is the same [BetSlipSheet] with the same state, checks and button
// (bet_slip_sheet.dart's header), drawn without its sheet.
//
// THE PANEL OPENS ON A CLICK (founder, 25 November 2026: "clicking Long
// or Short this side bar appears"; "same thing for Polymarket"). At rest
// the page holds no slip: its right column shows its outcome buttons and
// its figures (kute_desk_market.dart). A click on an outcome (the
// column's buttons, an outcome row's Yes / No, a game's sides, a round
// card's Up / Down) hands the slip to the host, which opens the panel on
// it; the panel's X, Escape and the browser's back close it
// ([BetSlipInPlaceHostState.close]) and the column comes back. A timed
// round's open slip moves to the next round by itself once its round
// reaches its cutoff, as the round card's buttons do, through the card's
// own door, quietly ([offerDefault]: no "slip opened" count, no notice).
//
// A slip that is placing is never replaced: a tap on another outcome then
// does nothing, as the page under a slip sheet took no taps. One whose
// standing order the person may leave is left first (Sal's placing toast
// takes over), exactly as closing its sheet does.

import 'dart:async';

import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import 'package:kute/screens/shared/kute_bar_context.dart' show KuteBarShare;

import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/crypto_round.dart'
    show polyCryptoRoundOf, polyRoundBuyClosed;
import 'package:kute/services/polymarket/fast_bet_window.dart'
    show polyIsFastBetRound;
import 'package:kute/theme/kute_motion.dart';

/// What a slip in the pane tells its host, and what it asks of it.
class BetSlipInPlaceLink {
  BetSlipInPlaceLink._(this._host, {required this.quiet});

  final BetSlipInPlaceHostState _host;

  /// The slip was opened by the page, not by a tap ([offerDefault]).
  final bool quiet;

  /// Whether the slip may give way now (it is not placing). Written by
  /// the slip on each build.
  bool canLeave = true;

  /// Leaves the slip as its sheet's close would (a standing order's
  /// toast); written by the slip.
  VoidCallback? leave;

  /// The page's round Sal button (the trade row's, or its "Send to a
  /// friend" pill's action), drawn beside the slip's button in place.
  KuteBarShare? get share => _host.widget.share;

  /// The slip is done (its order placed, or its OK): a fresh slip on the
  /// same market takes its place.
  void reset() => _host._reset(this);

  /// The panel's X: the page back at rest ([BetSlipInPlaceHostState.close]).
  void close() => _host.close();
}

class BetSlipInPlaceHost extends StatefulWidget {
  const BetSlipInPlaceHost(
      {super.key,
      required this.active,
      this.defaultOpener,
      this.share,
      required this.child});

  /// The page's round Sal button for the slip's button row (see
  /// [BetSlipInPlaceLink.share]); null for none (send mode).
  final KuteBarShare? share;

  /// Slips opened under it go to the pane (EXPANDED); false: as sheets.
  final bool active;

  /// The page's door onto its market as its first button opens it ([side]
  /// 0: Yes, Up; 1: No, Down): a timed round's open slip rolls to the next
  /// round through it, quietly (see the file header).
  final void Function(int side)? defaultOpener;
  final Widget child;

  /// The host over [context], when it takes slips now.
  static BetSlipInPlaceHostState? maybeOf(BuildContext context) {
    final host = context.getInheritedWidgetOfExactType<_HostScope>()?.state;
    return host != null && host.mounted && host.widget.active ? host : null;
  }

  /// Whether the host over [context] has its panel open now (a slip
  /// handed to it and not closed). Rebuilds [context] when that changes.
  static bool isOpenOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HostScope>();
    final host = scope?.state;
    return host != null && host.widget.active && host._open;
  }

  /// The link of the slip in the pane over [context]; null for a slip in
  /// a sheet or a page of its own.
  static BetSlipInPlaceLink? linkOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SlipScope>()?.link;

  @override
  State<BetSlipInPlaceHost> createState() => BetSlipInPlaceHostState();
}

class BetSlipInPlaceHostState extends State<BetSlipInPlaceHost> {
  BetSlipSheet? _slip;

  /// The panel is open: a slip was handed in and not closed. The slip
  /// stays a moment after a close, so it slides out whole.
  bool _open = false;
  Timer? _clear;
  int _generation = 0;
  BetSlipInPlaceLink? _link;
  bool _quiet = false;
  bool _scheduled = false;
  Timer? _tick;
  int _side = 0;

  void Function(int side)? get _opener =>
      widget.active ? widget.defaultOpener : null;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _sync();
  }

  /// Escape closes the open panel, while this page is the one on top.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted ||
        !widget.active ||
        !_open) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    close();
    return true;
  }

  /// The panel closed: the page back at rest, its column in view. A slip
  /// that is placing stays (false), as its sheet could not be closed
  /// then; one whose standing order the person may leave is left first.
  bool close() {
    if (!mounted || !_open) return false;
    final link = _link;
    if (link != null && !link.canLeave) return false;
    link?.leave?.call();
    setState(() {
      _open = false;
      _generation++;
    });
    _clear?.cancel();
    // After the slide out (kute_desk_market.dart).
    _clear = Timer(KuteMotion.settleDuration + const Duration(milliseconds: 60),
        () {
      if (!mounted || _open) return;
      setState(() {
        _slip = null;
        _link = null;
        _generation++;
      });
    });
    return true;
  }

  @override
  void didUpdateWidget(BetSlipInPlaceHost old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// While the host takes slips and has a door: once a second the open
  /// slip is looked at ([_onTick]).
  void _sync() {
    if (_opener == null) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// A quiet open is running ([offerDefault]): [BetSlipSheet.show] shows
  /// no notice and counts nothing.
  bool get quietOpen => _quiet;

  /// Takes [slip] into the pane; false when the host does not take slips
  /// now (the caller then shows the sheet). A slip that is placing stays.
  bool present(BetSlipSheet slip) {
    if (!mounted || !widget.active) return false;
    final link = _link;
    if (link != null && !link.canLeave) return true;
    link?.leave?.call();
    _clear?.cancel();
    setState(() {
      _slip = slip;
      _open = true;
      _generation++;
      _link = BetSlipInPlaceLink._(this, quiet: _quiet);
    });
    return true;
  }

  void _openDefault(int side) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      final opener = _opener;
      if (!mounted || !widget.active || !_open || opener == null) {
        return;
      }
      _quiet = true;
      try {
        opener(side);
      } finally {
        _quiet = false;
      }
    });
  }

  void _reset(BetSlipInPlaceLink link) {
    if (!mounted || link != _link) return;
    setState(() {
      _generation++;
      _link = BetSlipInPlaceLink._(this, quiet: link.quiet);
    });
  }

  /// A timed round's open slip follows the round card past its cutoff:
  /// once its round takes no more bets, the card's door opens the next
  /// one, on the same side.
  void _onTick() {
    if (!mounted || _opener == null || !_open) return;
    final slip = _slip;
    final link = _link;
    if (slip == null) return;
    if (link == null || !link.canLeave) return;
    final slug = slip.marketSlug;
    if (slug == null ||
        polyCryptoRoundOf(slug, endDate: slip.marketEndAt) == null ||
        !polyRoundBuyClosed(slug,
            endDate: slip.marketEndAt,
            // The slip's own door clock (tests move it by hand).
            // ignore: invalid_use_of_visible_for_testing_member
            now: BetSlipSheet.debugClock())) {
      return;
    }
    link.leave?.call();
    _side = slip.initialOutcomeIndex == 1 ? 1 : 0;
    setState(() {
      _slip = null;
      _link = null;
      _generation++;
    });
    _openDefault(_side);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _tick?.cancel();
    _clear?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HostScope(
        state: this,
        generation: _generation,
        // The browser's back (and the page's own) closes the open panel
        // first; the page is left with the next one.
        child: PopScope(
          canPop: !(widget.active && _open),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) close();
          },
          child: widget.child,
        ),
      );
}

class _HostScope extends InheritedWidget {
  const _HostScope(
      {required this.state, required this.generation, required super.child});

  final BetSlipInPlaceHostState state;
  final int generation;

  @override
  bool updateShouldNotify(_HostScope old) => old.generation != generation;
}

class _SlipScope extends InheritedWidget {
  const _SlipScope({required this.link, required super.child});

  final BetSlipInPlaceLink link;

  @override
  bool updateShouldNotify(_SlipScope old) => old.link != link;
}

/// The slip in the page's pane (see the file header); [empty] while the
/// pane holds none (a market over, a round with no prices yet).
class BetSlipInPlacePane extends StatelessWidget {
  const BetSlipInPlacePane({super.key, this.empty = const SizedBox.shrink()});

  final Widget empty;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HostScope>();
    final host = scope?.state;
    final slip = host?._slip;
    final link = host?._link;
    if (host == null || slip == null || link == null) return empty;
    return _SlipScope(
      link: link,
      child: KeyedSubtree(
        key: ValueKey('bet-slip-in-place-${host._generation}'),
        // As the sheet wraps it (BetSlipSheet._present).
        child: FastBetScope(
          active: slip.ledgerWalletId == null &&
              polyIsFastBetRound(slip.marketSlug),
          child: slip,
        ),
      ),
    );
  }
}
