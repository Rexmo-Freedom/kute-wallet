import 'package:kute/screens/shared/kute_form_panel_route.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart' show showKuteModalSheet;
import 'trailing_stop_sheet.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart'
    show ledgerHlAccountProvider;
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_order_controls.dart';
import 'package:kute/screens/shared/advanced_ticket.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:kute/screens/hyperliquid/components/builder_fee_consent.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/slip_form_body.dart';
import 'package:kute/screens/shared/slip_stat_tiles.dart'
    show SlipFigure, SlipFigures, slipZeroFigure;
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
// Reduce-only closes: a ticket and a separate Advanced page share
// the same reviewed submission path. Ledger approval stays wallet-scoped.

import 'package:flutter/material.dart';
import 'package:kute/platform/kute_wide_frames.dart' show KuteDialogSurfaceMark;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart' show redColor;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/position_rows_card.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart'
    show hlCloseValue, hlLivePnl;
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart'
    show flooredSize, roundPrice, wireRoundedPrice;
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart';
import 'package:kute/screens/hyperliquid/components/hl_protection_rows.dart'
    show hlReadOpenOrders, hlWatchOpenOrders;
import 'package:kute/screens/hyperliquid/components/hl_liquidation_distance.dart'
    show hlLiquidationPrice;

/// How the position is closed. [market] is the simple default (reduce-only
/// IOC market via closePosition); the rest are resting reduce-only orders
/// placed via the order-slip notifier methods.
enum _CloseType {
  market,
  limit,
  stopMarket,
  stopLimit,
  takeMarket,
  takeLimit,
  twap,
}

/// A close the sheet is about to place (Wallet Hardening Phase 1b.3): the
/// intent the user approves and the notifier call with exactly those
/// arguments, built together so they cannot disagree.
class _CloseOrder {
  const _CloseOrder(this.intent, this.place);

  final SensitiveIntent intent;
  final Future<HlOrderResult> Function(AuthGrant grant) place;
}

class _CloseDraft {
  const _CloseDraft(this.amount, this.type, this.slippage, this.limit,
      this.trigger, this.minutes, this.randomize);
  final String amount, limit, trigger, minutes;
  final _CloseType type;
  final double slippage;
  final bool randomize;
}

class HlClosePositionSheet extends ConsumerStatefulWidget {
  final HlPerpPosition position;

  /// The market descriptor for the position's coin — needed for the advanced
  /// (limit/stop/take/TWAP) reduce-only order types. Threaded in from the
  /// detail sheet; when null the sheet resolves it via
  /// [hyperliquidMarketProvider] and, failing that, offers only the simple
  /// Market close (which doesn't need the descriptor).
  final HlMarket? market;
  final String? ledgerWalletId;
  final _CloseDraft? _initialDraft;
  final bool _advancedPage;

  const HlClosePositionSheet({
    super.key,
    required this.position,
    this.market,
    this.ledgerWalletId,
  })  : _initialDraft = null,
        _advancedPage = false;

  const HlClosePositionSheet._advanced({
    required this.position,
    required this.market,
    required this.ledgerWalletId,
    required _CloseDraft draft,
  })  : _initialDraft = draft,
        _advancedPage = true;

  static const routeName = 'hyperliquid-close-position-sheet';

  static void show(
    BuildContext context, {
    required HlPerpPosition position,
    HlMarket? market,
    String? ledgerWalletId,
    String source = 'position_detail',
  }) {
    // One close ticket at a time: a second tap while it slides in does
    // not stack another.
    if (OpenOnce.isOpen(routeName)) return;
    final walletKind = ledgerWalletId != null ? 'ledger' : 'hot';
    TrackingService.setFlowContext(
        flow: 'hl_close',
        step: 'amount',
        venue: 'hyperliquid',
        walletKind: walletKind);
    TrackingService.track('hyperliquid_close_started', params: {
      'venue': 'hyperliquid',
      'coin': position.coin,
      ...VenueAnalytics.hlAssetParams(position.coin),
      'entry_source': source,
      'wallet_kind': walletKind,
      'side': position.isLong ? 'long' : 'short',
      'leverage': position.leverageValue,
      'margin_mode': position.leverageType,
    });
    // Exact mirror of SellSheet.show — same flags, same options.
    unawaited(OpenOnce.run(routeName, () => showKuteModalSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      // Drag-to-dismiss bypasses PopScope (Flutter gap), so disable it —
      // tap-outside still dismisses and IS gated by the PopScope lock
      // while the close is in flight.
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      routeSettings: const RouteSettings(name: routeName),
      builder: (_) => GestureDetector(
        // Tap anywhere outside an Advanced price / duration field to dismiss
        // the OS keyboard those fields raise. Child buttons/inputs still win
        // their own taps; only empty space triggers the unfocus.
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: HlClosePositionSheet(
            position: position, market: market, ledgerWalletId: ledgerWalletId),
      ),
    )));
  }

  /// The position screen's "Protect it": the close ticket's own Advanced
  /// page (stop / take profit types and the trailing stop), opened
  /// straight away on a stop-market close of the whole position, its
  /// trigger left empty for the user to set (validated against the price
  /// before anything is approved). A Ledger position has no stop types on
  /// that page (its signer reviews Market and Limit), so it opens on a
  /// Limit close with its price left empty, the trailing stop under it:
  /// never on a ready market close. Withheld Advanced opens nothing; the
  /// shared sheet says why.
  static void showProtect(
    BuildContext context,
    WidgetRef ref, {
    required HlPerpPosition position,
    required HlMarket market,
    String? ledgerWalletId,
  }) {
    if (OpenOnce.isOpen(routeName)) return;
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    var size = position.szi.abs().toStringAsFixed(6);
    if (size.contains('.')) {
      size = size
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }
    final draft = _CloseDraft(
        size,
        ledgerWalletId == null ? _CloseType.stopMarket : _CloseType.limit,
        1.0,
        '',
        '',
        '30',
        false);
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(OpenOnce.run(
        routeName,
        // The page; the shared panel on EXPANDED (kute_form_panel_route).
        () => navigator.push<_CloseDraft>(kuteFormPanelRoute(
              context,
              settings: const RouteSettings(name: routeName),
              builder: (_) => HlClosePositionSheet._advanced(
                position: position,
                market: market,
                ledgerWalletId: ledgerWalletId,
                draft: draft,
              ),
            ))));
  }

  @override
  ConsumerState<HlClosePositionSheet> createState() =>
      _HlClosePositionSheetState();
}

class _HlClosePositionSheetState extends ConsumerState<HlClosePositionSheet> {
  static const _slippageOptions = [0.5, 1.0, 2.0, 5.0];

  double _fraction = 1.0;
  double _slippagePct = 1.0;
  bool _isClosing = false;

  /// Synchronous re-entrancy guard (mirrors the bet slip's
  /// `_buyInFlight`) — `_isClosing` only flips inside setState.
  bool _closeInFlight = false;

  /// The close's rubber band on the CTA: how far along it is (checks,
  /// approval, sent to the exchange), and how it ended. Presentation
  /// only; set beside [_isClosing], never read by the close itself.
  double? _bandProgress;
  RubberBandOutcome? _bandOutcome;

  /// Moves the band to the close's next phase.
  void _bandTo(double progress) {
    if (!mounted) return;
    setState(() => _bandProgress = progress);
  }

  /// The close worked: the band snaps (a light tap) while the ticket
  /// still holds the close, and the caller waits the bounded moment the
  /// snap takes ([RubberBand.settle]) before it lets go into the
  /// confirmation.
  Future<void> _bandSucceeded() async {
    if (!mounted) return;
    setState(() => _bandOutcome = RubberBandOutcome.success);
    await RubberBand.settle(context);
  }

  String? _errorText;
  Object? _errorDetails;

  // ── Advanced close order type ──────────────────────────────────────
  bool _openingAdvanced = false;
  _CloseType _closeType = _CloseType.market;

  /// Per-type price/duration inputs (only the selected type's fields show).
  /// The Advanced page's floating button, as last measured.
  double _advPrimaryHeight = 96;

  final TextEditingController _limitPxCtrl = TextEditingController();
  final TextEditingController _triggerPxCtrl = TextEditingController();
  final TextEditingController _twapMinutesCtrl =
      TextEditingController(text: '30');
  bool _randomizeTwap = false;

  /// A stop loss already rests on this position: the new one replaces it
  /// (the old one is cancelled only once the new one is accepted, so the
  /// position is never left without a stop between the two) or is added
  /// beside it, as the user chooses on the page.
  bool _replaceStop = true;

  HlPerpPosition get pos => widget.position;

  /// The spending account's resting orders (a Ledger's are not on this
  /// account). [watch] in build, read elsewhere.
  List<HlOpenOrder> _orders({bool watch = false}) {
    if (widget.ledgerWalletId != null) return const <HlOpenOrder>[];
    return watch ? hlWatchOpenOrders(ref) : hlReadOpenOrders(ref);
  }

  bool get _isStopClose =>
      _closeType == _CloseType.stopMarket || _closeType == _CloseType.stopLimit;

  /// The market descriptor for advanced order types — the threaded-in copy,
  /// else the live provider lookup. Null when the coin isn't in the loaded
  /// universe (advanced types then stay disabled; Market close still works).
  HlMarket? get _market =>
      widget.market ?? ref.read(hyperliquidAccountMarketProvider(pos.coin));

  bool get _isMarketClose => _closeType == _CloseType.market;

  /// A non-market close type or custom slippage is Advanced. While the
  /// policy withholds Advanced the page does not open (the tap shows the
  /// shared sheet); if it is withdrawn while open, it cannot submit.
  bool get _usesAdvanced => !_isMarketClose || _slippagePct != 1.0;

  String? get _advancedBlock => _usesAdvanced
      ? ref.watch(runtimeCapabilitiesProvider).blockReason('trading.advanced')
      : null;

  bool get _isLimitClose => _closeType == _CloseType.limit;

  bool get _isTwapClose => _closeType == _CloseType.twap;

  bool get _isTriggerClose =>
      _closeType == _CloseType.stopMarket ||
      _closeType == _CloseType.stopLimit ||
      _closeType == _CloseType.takeMarket ||
      _closeType == _CloseType.takeLimit;

  bool get _isTriggerLimit =>
      _closeType == _CloseType.stopLimit || _closeType == _CloseType.takeLimit;

  String get _displayCoin => _market?.coin ?? HlMarket.baseCoin(pos.coin);
  /// Null on the web when there is no logo to draw: the header then has
  /// no box and no gap (hlLogoShown).
  Widget? _marketArtwork() => hlLogoOrNull(
      () => _marketArtworkIcon(),
      coin: _displayCoin,
      wireCoin: _market?.wireCoin ?? pos.coin,
      iconUrl: _market?.iconUrl,
      category: _market?.category);

  Widget _marketArtworkIcon() => HlCoinIcon(
      coin: _displayCoin,
      wireCoin: _market?.wireCoin ?? pos.coin,
      iconUrl: _market?.iconUrl,
      category: _market?.category,
      size: 36);

  /// Total closable size (coin units), off the exchange-reported szi.
  double get _totalSize => pos.szi.abs();

  /// Typed close amount in coin units — the SOURCE OF TRUTH for a custom
  /// close. The preset chips just fill it, and [_fraction] is derived from it
  /// (so `closePosition(fraction:)` stays the sizing path). For the advanced
  /// resting order types the close SIZE (coin units) is the typed value.
  final TextEditingController _amountCtrl = TextEditingController();
  bool _syncingText = false;

  /// The figure typed on the keypad, in dollars: what is closed, at the
  /// live mark. Each key turns it into the coin size in [_amountCtrl]
  /// (the whole position once it reaches the position's value), so every
  /// order path keeps sizing off [_amountCtrl].
  String _usdText = '';

  // Analytics (root sheet only): flow timing, why it stopped, submission.
  final DateTime _openedAt = DateTime.now();
  String _flowStep = 'amount';
  String? _stopReason;
  String? _lastErrorCategory;
  bool _closeSubmitted = false;
  String _amountMethod = 'none';
  late final String _settingsScope = 'hl_close_${identityHashCode(this)}';

  Map<String, Object> _closeInputs() {
    final size = _closeSize;
    final fraction =
        _totalSize > 0 ? (size / _totalSize).clamp(0.0, 1.0) : 0.0;
    final px = pos.szi.abs() > 0
        ? pos.positionValue / pos.szi.abs()
        : pos.entryPx;
    final notional = size * px;
    return {
      'venue': 'hyperliquid',
      'coin': pos.coin,
      'kind': 'perp',
      ...VenueAnalytics.hlAssetParams(pos.coin),
      'wallet_kind': widget.ledgerWalletId != null ? 'ledger' : 'hot',
      'side': pos.isLong ? 'long' : 'short',
      'leverage': pos.leverageValue,
      'margin_mode': pos.leverageType,
      'close_scope': fraction >= 0.999 ? 'full' : 'partial',
      'fraction_pct': (fraction * 100).round().clamp(0, 100),
      ...TrackingService.moneyParams(amountUsd: notional),
      'notional_usd': (notional * 100).round() / 100,
      // The root ticket is typed in dollars, the Advanced page in coins.
      'size_unit': widget._advancedPage ? 'coin' : 'usd',
      'amount_method': _amountMethod,
      'order_type': _closeType.name,
      'advanced_used': _usesAdvanced,
      'slippage_bps': VenueAnalytics.bps(_slippagePct),
      if ((_isLimitClose || _isTriggerLimit) && _parsePx(_limitPxCtrl) != null)
        'limit_price': _parsePx(_limitPxCtrl)!,
      if (_isTriggerClose && _parsePx(_triggerPxCtrl) != null)
        'trigger_price': _parsePx(_triggerPxCtrl)!,
      if (_isTwapClose) 'twap_minutes': _parseInt(_twapMinutesCtrl) ?? 0,
      if (_isTwapClose) 'twap_randomized': _randomizeTwap,
      'reduce_only': true,
    };
  }

  void _trackStep(String step) {
    if (_flowStep == step) return;
    _flowStep = step;
    TrackingService.setFlowStep(step);
    TrackingService.track('hl_close_step', params: {
      'step': step,
      ..._closeInputs(),
    });
  }

  void _stopped(String reason, {Object? error}) {
    _stopReason = reason;
    if (error != null) _lastErrorCategory = TrackingService.errorCategory(error);
  }

  void _trackSubmitted() {
    _closeSubmitted = true;
    _flowStep = 'submitted';
    TrackingService.setFlowStep('submitted');
    final inputs = _closeInputs();
    VenueAnalytics.stage('hl', pos.coin, {
      for (final k in const [
        'close_scope', 'fraction_pct', 'amount_method', 'slippage_bps',
        'advanced_used', 'twap_minutes', 'twap_randomized',
      ])
        if (inputs[k] != null) k: inputs[k]!,
      'entry_source': 'close_sheet',
    });
    TrackingService.track('hyperliquid_close_submitted', params: {
      ...inputs,
      'time_in_flow_ms': DateTime.now().difference(_openedAt).inMilliseconds,
      'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
          DateTime.now().difference(_openedAt)),
    });
  }

  void _settingChanged(String setting, Object value) {
    VenueAnalytics.settingChanged('hl_close_setting_changed',
        setting: setting,
        value: value,
        scope: _settingsScope,
        extra: {
          'coin': pos.coin,
          ...VenueAnalytics.hlAssetParams(pos.coin),
          'wallet_kind': widget.ledgerWalletId != null ? 'ledger' : 'hot',
        });
  }

  @override
  void initState() {
    super.initState();
    // Opens empty, like the Predictions sell sheet: the user types what to
    // close, or taps Max for the whole position. Nothing is closed by
    // default, so a quick confirm never closes more than was asked.
    _fraction = 0;
    _amountCtrl.text = '';
    _usdText = '';
    final draft = widget._initialDraft;
    if (draft != null) _applyDraft(draft);
    _amountCtrl.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    if (!widget._advancedPage) {
      if (!_closeSubmitted) {
        try {
          TrackingService.track('hyperliquid_close_abandoned', params: {
            ..._closeInputs(),
            'step': _flowStep,
            'reason': _stopReason ?? 'user_closed',
            if (_lastErrorCategory != null)
              'last_error_category': _lastErrorCategory!,
            'time_in_flow_ms':
                DateTime.now().difference(_openedAt).inMilliseconds,
            'time_in_flow_bucket': VenueAnalytics.timeInFlowBucket(
                DateTime.now().difference(_openedAt)),
          });
        } catch (_) {}
      }
      TrackingService.clearFlowContext('hl_close');
      VenueAnalytics.resetSettings(_settingsScope);
    }
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _limitPxCtrl.dispose();
    _triggerPxCtrl.dispose();
    _twapMinutesCtrl.dispose();
    super.dispose();
  }

  /// Plain size string for the editable field (trimmed trailing zeros, no
  /// separators) so it round-trips cleanly through double.parse.
  String _fmtSize(double v) {
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// Plain price string for a price field prefill (trimmed trailing zeros).
  String _fmtPx(double v) {
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// The typed close SIZE in coin units (source of truth for every path).
  /// Clamped to the position size so a custom close can't oversize.
  double get _closeSize {
    final parsed =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return 0;
    return parsed.clamp(0.0, _totalSize).toDouble();
  }

  double? _parsePx(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return (v != null && v > 0) ? v : null;
  }

  int? _parseInt(TextEditingController c) => int.tryParse(c.text.trim());

  void _onAmountChanged() {
    if (_syncingText) return;
    _amountMethod = 'keypad';
    final parsed =
        double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    final total = _totalSize;
    // A new figure is a new attempt, so the last failure stops describing
    // it and the button goes back to being the close.
    if (parsed == null || parsed <= 0 || total <= 0) {
      setState(() {
        _fraction = 0;
        _errorText = null;
        _errorDetails = null;
      });
      return;
    }
    setState(() {
      _fraction = (parsed / total).clamp(0.0, 1.0);
      _errorText = null;
      _errorDetails = null;
    });
  }

  /// The dollar figure the keypad and Max write for [size] coins at the
  /// live mark ('' for none), the way the Predictions sell sheet seeds its
  /// own: whole dollars plain, else two decimals.
  String _usdForSize(double size) {
    final usd = size * _markNow();
    if (!usd.isFinite || usd <= 0) return '';
    return usd == usd.roundToDouble()
        ? usd.toStringAsFixed(0)
        : usd.toStringAsFixed(2);
  }

  /// A key on the built-in keypad: the dollar figure, turned into the coin
  /// size [_amountCtrl] holds (the source of truth for every order path,
  /// which [_onAmountChanged] derives `_fraction` from). The position's
  /// whole value, or more, is the whole position, never a fraction a
  /// cent's rounding short of it.
  void _onKeypadUsd(String v) {
    if (v == _usdText) return;
    final usd = double.tryParse(v) ?? 0;
    final mark = _markNow();
    final whole = double.tryParse(_usdForSize(_totalSize)) ?? 0;
    final String size;
    if (usd <= 0 || mark <= 0) {
      size = '';
    } else if (usd >= whole) {
      size = _fmtSize(_totalSize);
    } else {
      size = _fmtSize(usd / mark);
    }
    _usdText = v;
    if (size != _amountCtrl.text) {
      _amountCtrl.text = size;
    } else {
      _amountMethod = 'keypad';
    }
    // A new figure is a new attempt (as [_onAmountChanged] says).
    setState(() {
      _errorText = null;
      _errorDetails = null;
    });
  }

  /// The position size IS the quick-amount control: there is no percent
  /// row on this ticket, so tapping the line under the figure fills the
  /// field with the whole position (what the old 100% chip did).
  void _useWholePosition() {
    _amountMethod = 'max';
    HapticFeedback.selectionClick();
    TrackingService.track('investing_close_available_tapped');
    _syncingText = true;
    _amountCtrl.text = _fmtSize(_totalSize);
    _amountCtrl.selection =
        TextSelection.collapsed(offset: _amountCtrl.text.length);
    _syncingText = false;
    setState(() {
      _fraction = 1.0;
      _usdText = _usdForSize(_totalSize);
      _errorText = null;
      _errorDetails = null;
    });
  }

  /// Live mark for previews / prefills — falls back to the snapshot-implied
  /// mark when the WS hasn't ticked yet.
  double _markNow() {
    final liveMid = ref.read(hyperliquidLiveMidProvider(pos.coin));
    final snapshotMark =
        pos.szi.abs() > 0 ? pos.positionValue / pos.szi.abs() : pos.entryPx;
    return liveMid ?? snapshotMark;
  }

  _CloseDraft get _draft => _CloseDraft(
      _amountCtrl.text,
      _closeType,
      _slippagePct,
      _limitPxCtrl.text,
      _triggerPxCtrl.text,
      _twapMinutesCtrl.text,
      _randomizeTwap);

  void _applyDraft(_CloseDraft draft) {
    _syncingText = true;
    _amountCtrl.text = draft.amount;
    _syncingText = false;
    _closeType = draft.type;
    _slippagePct = draft.slippage;
    _limitPxCtrl.text = draft.limit;
    _triggerPxCtrl.text = draft.trigger;
    _twapMinutesCtrl.text = draft.minutes;
    _randomizeTwap = draft.randomize;
    _fraction = _totalSize > 0 ? (_closeSize / _totalSize).clamp(0.0, 1.0) : 0;
    _usdText = _usdForSize(_closeSize);
    _errorText = null;
  }

  Future<void> _openAdvanced() async {
    if (_openingAdvanced || _isClosing) return;
    // Withheld Advanced opens nothing; the shared sheet says why.
    if (!advancedTradingOffered(
        context, ref.read(runtimeCapabilitiesProvider))) {
      return;
    }
    _openingAdvanced = true;
    HapticFeedback.selectionClick();
    _trackStep('advanced');
    try {
      final draft = await Navigator.of(context, rootNavigator: true)
          // The page; the shared panel on EXPANDED (kute_form_panel_route).
          .push<_CloseDraft>(kuteFormPanelRoute(
        context,
        settings: const RouteSettings(name: HlClosePositionSheet.routeName),
        builder: (_) => HlClosePositionSheet._advanced(
          position: pos,
          market: _market,
          ledgerWalletId: widget.ledgerWalletId,
          draft: _draft,
        ),
      ));
      if (mounted && draft != null) setState(() => _applyDraft(draft));
    } finally {
      _openingAdvanced = false;
    }
  }

  void _backFromAdvanced() {
    if (!_isClosing) Navigator.of(context).pop(_draft);
  }

  void _onSelectType(_CloseType t) {
    if (_closeType == t) return;
    HapticFeedback.selectionClick();
    _settingChanged('order_type', t.name);
    setState(() {
      _closeType = t;
      _errorText = null;
      final mark = _markNow();
      if (t == _CloseType.limit && _limitPxCtrl.text.trim().isEmpty) {
        _limitPxCtrl.text = _fmtPx(mark);
      }
      // A stop or take is never prefilled at the price now: a trigger at
      // the mark fires at once. Its fields stay empty for the user to set
      // (and are checked against the price before any approval).
    });
  }

  // ── Confirm ────────────────────────────────────────────────────────

  Future<void> _handleClose() async {
    if (_closeInFlight || _isClosing) return;
    _closeInFlight = true;
    setState(() {
      _isClosing = true;
      // The tap takes the band's first pull; time and the phases below
      // build it from there.
      _bandProgress = null;
      _bandOutcome = null;
      _errorText = null;
      _errorDetails = null;
    });
    try {
      if (_usesAdvanced) {
        await RuntimeCapabilitiesService.instance
            .ensureAllowed('trading.advanced');
      }
      await _handleCloseInner();
    } catch (e) {
      if (mounted) setState(() => _errorText = _messageFor(e));
    } finally {
      _closeInFlight = false;
      if (mounted) setState(() => _isClosing = false);
    }
  }

  /// A close stopped before anything was submitted.
  void _trackBlocked(String reason) {
    _stopped(reason);
    TrackingService.track('hyperliquid_order_blocked', params: {
      ..._closeInputs(),
      'action': 'close',
      'reason': reason,
      'coin': pos.coin,
      'wallet_kind': widget.ledgerWalletId != null ? 'ledger' : 'hot',
    });
  }

  Future<void> _handleCloseInner() async {
    HapticFeedback.mediumImpact();

    // Reducing an existing position has its own permission, preserved when
    // opening new investments is blocked. The provider checks it fresh.
    if (!ref.read(runtimeCapabilitiesProvider).allows('hyperliquid.close')) {
      _trackBlocked('capability');
      showMessageSnackBar(
        context: context,
        message: context.l10n.ledgerErrorTradingDisabled,
        error: true,
      );
      return;
    }
    if (!mounted) return;

    if (widget.ledgerWalletId != null) {
      final market = _market;
      if (market == null ||
          (!_isMarketClose && !_isLimitClose) ||
          (_isLimitClose && _parsePx(_limitPxCtrl) == null)) {
        setState(() => _errorText = context.l10n.closeMarketUnavailable);
        return;
      }
      setState(() {
        _isClosing = true;
        _errorText = null;
      });
      _trackStep('review');
      try {
        final closeSize = _closeSize;
        final totalSize = _totalSize;
        final notionalUsd = closeSize * _markNow();
        final isMarketClose = _isMarketClose;
        // A Ledger's orders are not on the hot account and each cancel
        // needs the device, so a whole close leaves its stops and takes:
        // said on the receipt (counted when the Ledger's orders read),
        // never silently.
        final ledgerLeftovers = totalSize > 0 &&
                closeSize >= totalSize * (1 - 1e-9)
            ? _ledgerProtectiveCount()
            : null;
        _trackSubmitted();
        _bandTo(0.5);
        final outcome = await runLedgerHlClose(context, ref,
            walletId: widget.ledgerWalletId!,
            position: pos,
            market: market,
            size: closeSize,
            slippagePct: _slippagePct,
            limitPrice: _isLimitClose ? _parsePx(_limitPxCtrl) : null);
        final closed = outcome?.result;
        if (outcome?.isSuccess == true &&
            closed != null &&
            (closed.filledSz > 0 || isMarketClose)) {
          final fraction =
              totalSize > 0 ? (closeSize / totalSize).clamp(0.0, 1.0) : 1.0;
          TrackingService.hyperliquidPositionClosed(
            coin: pos.coin,
            fractionPct: (fraction * 100).round().clamp(1, 100),
            payoutUsd: closed.filledSz * closed.avgPx,
            pnlUsd: pos.unrealizedPnl * fraction,
            wasLong: pos.isLong,
            leverage: pos.leverageValue,
            walletKind: 'ledger',
            orderType: isMarketClose ? 'market' : 'limit',
            notionalUsd: notionalUsd,
          );
        }
        if (!mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        final result = outcome?.result;
        if (outcome?.isSuccess == true && result != null) {
          // Still holding the close: the band snaps first, then the
          // ticket lets go into the confirmation (_popToHost).
          final fullyClosed =
              totalSize > 0 && result.filledSz >= totalSize * (1 - 1e-9);
          if (result.filledSz > 0 || _isMarketClose) {
            await _showClosedResult(nav, result,
                checkOpenOrders: _isLimitClose,
                ledgerLeftovers: fullyClosed ? ledgerLeftovers : null);
          } else {
            await _showCloseAccepted(nav,
                note: ledgerLeftovers == null
                    ? null
                    : context.l10n.hlLeftLedgerStopsOpen);
          }
        } else if (outcome?.isPending == true) {
          // An ambiguous submission is not a confirmed close: leave its
          // reconciliation to the pending action without a success haptic.
          _popToHost(nav);
        } else {
          setState(() => _isClosing = false);
          _stopped('signing_declined');
        }
      } catch (e, st) {
        _lastErrorCategory = TrackingService.errorCategory(e);
        TrackingService.hyperliquidOrderFailed(
          coin: pos.coin,
          reason: TrackingService.errorCategory(e),
          action: 'close',
          orderType: _closeType.name,
          isBuy: !pos.isLong,
          notionalUsd: _closeSize * _markNow(),
          leverage: pos.leverageValue,
          walletKind: 'ledger',
          stackTrace: st,
          extra: hlFailureParams(e),
        );
        if (mounted) {
          setState(() {
            _isClosing = false;
            _errorText = _messageFor(e);
          });
        }
      }
      return;
    }

    if (!await ensureHotHlBuilderFeeConsent(context, ref)) {
      _trackBlocked('builder_fee');
      return;
    }
    if (!mounted) return;

    // Phase 1b.3: build the close first (input errors surface before any
    // prompt), then ask for a fresh approval bound to exactly that close.
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) {
      _trackBlocked('no_wallet');
      setState(() {
        _errorDetails = null;
        _errorText = context.l10n.depositActionWalletUnavailable;
      });
      return;
    }
    _CloseOrder? approved;
    try {
      approved = await _closeOrder(walletId);
    } catch (e) {
      if (e is StateError) _trackBlocked('invalid_input');
      if (!mounted) return;
      setState(() => _errorText = _messageFor(e));
      return;
    }
    if (!mounted) return;
    _trackStep('approval');
    _bandTo(0.45);
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: approved.intent,
      reason: context.l10n.stepUpReasonOrder(
          '${pos.coin} · ${hlKindLabel(context.l10n, isSpot: false)}'),
      amountUsd: _closeSize * _markNow(),
      smallAction: SmallActionContext.usd(_closeSize * _markNow()),
    );
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }
    // The price moved while the approval was up: a stop or take re-checked
    // against the price now, right before signing. Crossed, nothing is
    // sent and the sheet says why with its own inline line ([_paramError],
    // read from the same price), the button off.
    if (_isTriggerClose && _paramError != null) {
      grant.revoke();
      _trackBlocked('price_moved');
      setState(() {
        _errorDetails = null;
        _errorText = null;
      });
      return;
    }

    _trackSubmitted();
    setState(() {
      _isClosing = true;
      // Approved and sent: waiting on the exchange's answer.
      _bandProgress = 0.65;
      _errorText = null;
    });
    // Capture the root navigator BEFORE any pops — `context` dies with
    // the sheet.
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      if (_isMarketClose) {
        await _runMarketClose(nav, walletId, grant);
      } else {
        await _runAdvancedClose(nav, walletId, grant);
      }
    } catch (e) {
      _lastErrorCategory = TrackingService.errorCategory(e);
      if (e is AuthGrantException) {
        // Nothing was signed. Drift (a flipped position, a changed size or
        // order type) shows "Review again"; a stale grant stops quietly.
        if (!mounted) {
          trackGrantFailure(e, action: SensitiveAction.hlOrder);
          return;
        }
        setState(() => _isClosing = false);
        await handleGrantFailure(context, e, action: SensitiveAction.hlOrder);
        return;
      }
      if (!mounted) return;
      setState(() {
        _isClosing = false;
        _errorText = _messageFor(e);
      });
    }
  }

  /// The close the sheet is about to place, from the sheet as it is now
  /// (Wallet Hardening Phase 1b.3): the intent the user approves and the
  /// notifier call with exactly those arguments. Throws StateError for
  /// missing inputs.
  Future<_CloseOrder> _closeOrder(String walletId) async {
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final closeSize = _closeSize;
    // Closing side = opposite of the position side (long → sell to reduce).
    final closeIsLong = !pos.isLong;
    const source = 'close_position';
    HlMarket advancedMarket() {
      final m = _market;
      if (m == null) {
        throw StateError('Market unavailable for advanced close');
      }
      return m;
    }

    switch (_closeType) {
      case _CloseType.market:
        final cached = _market;
        final market = (cached != null && !cached.isSpot)
            ? cached
            : await trading.resolvePerpMarket(pos.coin);
        final fraction = _fraction;
        final slippagePct = _slippagePct;
        return _CloseOrder(
          HlIntents.close(
            walletId: walletId,
            market: market,
            positionIsLong: pos.isLong,
            fraction: fraction,
            slippagePct: slippagePct,
          ),
          (grant) => trading.closePosition(
            coin: pos.coin,
            fraction: fraction,
            slippagePct: slippagePct,
            grant: grant,
          ),
        );
      case _CloseType.limit:
        final market = advancedMarket();
        final px = _parsePx(_limitPxCtrl);
        if (px == null) throw StateError('Enter a limit price.');
        return _CloseOrder(
          HlIntents.limit(
            walletId: walletId,
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            px: px,
            tif: 'Gtc',
            postOnly: false,
            reduceOnly: true,
          ),
          (grant) => trading.placeLimit(
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            px: px,
            tif: 'Gtc',
            postOnly: false,
            reduceOnly: true,
            source: source,
            grant: grant,
          ),
        );
      case _CloseType.stopMarket:
      case _CloseType.takeMarket:
        final market = advancedMarket();
        final trig = _parsePx(_triggerPxCtrl);
        if (trig == null) throw StateError('Enter a trigger price.');
        final tpsl = _closeType == _CloseType.takeMarket ? 'tp' : 'sl';
        return _CloseOrder(
          HlIntents.trigger(
            walletId: walletId,
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            triggerPx: trig,
            isMarket: true,
            tpsl: tpsl,
            reduceOnly: true,
          ),
          (grant) => trading.placeTrigger(
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            triggerPx: trig,
            isMarket: true,
            tpsl: tpsl,
            reduceOnly: true,
            source: source,
            grant: grant,
          ),
        );
      case _CloseType.stopLimit:
      case _CloseType.takeLimit:
        final market = advancedMarket();
        final trig = _parsePx(_triggerPxCtrl);
        final limitPx = _parsePx(_limitPxCtrl);
        if (trig == null) throw StateError('Enter a trigger price.');
        if (limitPx == null) throw StateError('Enter a limit price.');
        final tpsl = _closeType == _CloseType.takeLimit ? 'tp' : 'sl';
        return _CloseOrder(
          HlIntents.trigger(
            walletId: walletId,
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            triggerPx: trig,
            isMarket: false,
            tpsl: tpsl,
            limitPx: limitPx,
            reduceOnly: true,
          ),
          (grant) => trading.placeTrigger(
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            triggerPx: trig,
            isMarket: false,
            tpsl: tpsl,
            limitPx: limitPx,
            reduceOnly: true,
            source: source,
            grant: grant,
          ),
        );
      case _CloseType.twap:
        final market = advancedMarket();
        final minutes = _parseInt(_twapMinutesCtrl);
        if (minutes == null ||
            minutes < HyperliquidExchangeService.minTwapMinutes ||
            minutes > HyperliquidExchangeService.maxTwapMinutes) {
          throw StateError('Duration must be between 5 minutes and 7 days.');
        }
        final randomize = _randomizeTwap;
        return _CloseOrder(
          HlIntents.twap(
            walletId: walletId,
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            durationMinutes: minutes,
            randomize: randomize,
            reduceOnly: true,
          ),
          (grant) => trading.placeTwap(
            market: market,
            isLong: closeIsLong,
            size: closeSize,
            durationMinutes: minutes,
            randomize: randomize,
            reduceOnly: true,
            source: source,
            grant: grant,
          ),
        );
    }
  }

  /// The simple, unchanged default: a reduce-only IOC market close sized off
  /// the exchange-reported szi (fraction = typedSize / totalSize). Shows the
  /// immediate-fill success overlay.
  Future<void> _runMarketClose(
      NavigatorState nav, String walletId, AuthGrant grant) async {
    // Rebuilt from the sheet as it is now. A changed size or slippage, or a
    // flipped position, makes closePosition throw ReauthRequired before it
    // signs.
    // A whole-position close: its left-over stops, takes and trailing
    // stops, listed before the close, are cancelled by the notifier once
    // the position is gone (its one place for every close path); this
    // waits for that cancel to say on the receipt what it did. A partial
    // close leaves them (reduce-only caps them at what is left). The venue
    // is not relied on to cancel them.
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final order = await _closeOrder(walletId);
    final result = await order.place(grant);

    ({int cancelled, int failed})? swept;
    if (_totalSize > 0 && result.filledSz >= _totalSize * (1 - 1e-9)) {
      final sweep = trading.leftoverSweepFor(pos.coin);
      if (sweep != null) {
        try {
          swept = await sweep;
        } catch (_) {
          swept = null;
        }
      }
    }
    if (!mounted) return;
    await _showClosedResult(nav, result, leftovers: swept);
  }

  Future<void> _showClosedResult(NavigatorState nav, HlOrderResult result,
      {bool checkOpenOrders = false,
      ({int cancelled, int failed})? leftovers,
      int? ledgerLeftovers}) async {
    // What this close asked for: a resting close order has a remainder
    // only when it filled less than that, never because the position is
    // bigger than the close (a fully filled 50% close leaves nothing
    // resting).
    final requested = _closeSize;
    final l10n = context.l10n;
    if (result.filledSz > 0) await _bandSucceeded();
    _popToHost(nav);

    // Actual fill figures — never the requested size (IOC can
    // partially fill; the remainder is cancelled by definition).
    final closedSz = result.filledSz;
    final avgPx = result.avgPx;
    final direction = pos.isLong ? 1.0 : -1.0;
    final realizedPnl =
        closedSz > 0 ? (avgPx - pos.entryPx) * closedSz * direction : 0.0;
    final remaining = (pos.szi.abs() - closedSz).clamp(0.0, double.infinity);
    final filled = closedSz > 0;
    final partial = remaining > 0.00000001;
    final orderRemainder = requested - closedSz > 0.00000001;
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: KuteConfirmation(
        message: !filled
            ? l10n.investingNoFillConfirmed
            : partial
                ? l10n.investingPartiallyClosed
                : l10n.investingPositionClosed,
        // Nothing filled: the position is as it was.
        tone: filled
            ? KuteConfirmationTone.success
            : KuteConfirmationTone.failure,
        onDone: () => nav.pop(),
        amount: filled ? '${formatHlSize(closedSz)} $_displayCoin' : null,
        contextLine:
            '${pos.isLong ? l10n.longLabel : l10n.shortLabel} · $_displayCoin',
        rows: filled
            ? {
                l10n.investingExitPrice:
                    formatHlPrice(avgPx, decimalCap: _market?.pxDecimalCap),
                l10n.investingProfitBeforeCosts:
                    '${realizedPnl >= 0 ? '+' : '−'}\$${realizedPnl.abs().toStringAsFixed(2)}',
                if (partial)
                  l10n.investingStillOpen:
                      '${formatHlSize(remaining)} $_displayCoin',
                if ((leftovers?.cancelled ?? 0) > 0)
                  l10n.hlProtectOrdersCancelledRow: '${leftovers!.cancelled}',
                if ((leftovers?.failed ?? 0) > 0)
                  l10n.hlProtectOrdersNotCancelledRow: '${leftovers!.failed}',
                if ((ledgerLeftovers ?? 0) > 0)
                  l10n.hlProtectOrdersNotCancelledRow: '$ledgerLeftovers',
              }
            : const {},
        detail: !filled
            ? null
            : (leftovers?.failed ?? 0) > 0
                ? l10n.hlProtectCancelAfterCloseFailed
                : ledgerLeftovers != null
                    ? l10n.hlLeftLedgerStopsOpen
                    : checkOpenOrders && orderRemainder
                    ? l10n.investingCloseRemainderNote
                    : l10n.investingBalanceUpdating,
      ),
    );
  }

  /// Limit / Stop / Take / TWAP — all REDUCE-ONLY resting orders sized in coin
  /// units off the typed amount. The closing side is the OPPOSITE of the
  /// position (long → isLong:false to reduce). These don't fill immediately,
  /// so on success we pop with a "close order placed" resting confirmation.
  Future<void> _runAdvancedClose(
      NavigatorState nav, String walletId, AuthGrant grant) async {
    // A replacing stop loss: the old ones are cancelled only after the
    // new one is accepted, so the position always has a stop.
    final toReplace = _isStopClose && _replaceStop
        ? hlStopLossesFor(_orders(), pos.coin)
        : const <HlOpenOrder>[];
    final trading = ref.read(hyperliquidTradingProvider.notifier);
    final replaceFailed = context.l10n.hlProtectReplaceCancelFailed;
    // Rebuilt from the sheet as it is now (see _runMarketClose).
    final order = await _closeOrder(walletId);
    final result = await order.place(grant);

    String? note;
    if (toReplace.isNotEmpty) {
      try {
        await trading.cancelOrdersList(toReplace, reason: 'replace_stop');
      } catch (_) {
        note = replaceFailed;
      }
    }
    if (!mounted) return;
    if (result.filledSz > 0) {
      await _showClosedResult(nav, result, checkOpenOrders: true);
      return;
    }
    await _showCloseAccepted(nav, note: note);
  }

  /// [snap] false when the band that worked was another sheet's (the
  /// trailing stop's, which snapped before it closed).
  Future<void> _showCloseAccepted(NavigatorState nav,
      {bool snap = true, String? note}) async {
    final amount = '${formatHlSize(_closeSize)} $_displayCoin';
    if (snap) await _bandSucceeded();
    _popToHost(nav);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: HlOrderAcceptedOverlay(
        coin: _displayCoin,
        market: _market,
        amount: amount,
        isClose: true,
        viewOrders: widget.ledgerWalletId == null,
        note: note,
      ),
    );
  }

  /// Pop the sheet (and anything stacked above the host), by route name
  /// rather than a plain pop, the way the Predictions tickets close
  /// themselves.
  ///
  /// The close is RELEASED first. The ticket traps itself while an order
  /// is in flight and this flag is what arms that trap, so leaving it set
  /// would refuse the hand-off and leave a finished close sitting under
  /// its own confirmation.
  void _popToHost(NavigatorState nav) {
    if (mounted && _isClosing) setState(() => _isClosing = false);
    nav.popUntil((route) {
      if (route is ModalBottomSheetRoute) return false;
      if (route is PopupRoute) return false;
      if (route.settings.name == HlClosePositionSheet.routeName) {
        return false;
      }
      if (route is PageRoute && route.fullscreenDialog) return false;
      return true;
    });
  }

  String _messageFor(Object e) {
    _errorDetails = e;
    return hlTradeErrorMessage(context.l10n, e);
  }

  /// Per-type input validity (advanced types only). Null when placeable.
  String? get _paramError {
    if (_isMarketClose) return null;
    final market = _market;
    if (market == null) {
      return context.l10n.closeOrderDetailsUnavailable;
    }
    // A size the market's lot floors to nothing would only fail after the
    // approval: said here, the button off.
    if (_closeSize > 0 && flooredSize(_closeSize, market.szDecimals) <= 0) {
      return context.l10n.amountIsTooSmall;
    }
    if (_isLimitClose) {
      if (_parsePx(_limitPxCtrl) == null) {
        return context.l10n.slipEnterLimitPrice;
      }
    } else if (_isTriggerClose) {
      final trigger = _parsePx(_triggerPxCtrl);
      if (trigger == null) {
        return context.l10n.slipEnterTriggerPrice;
      }
      final limit = _isTriggerLimit ? _parsePx(_limitPxCtrl) : null;
      if (_isTriggerLimit && limit == null) {
        return context.l10n.slipEnterLimitPrice;
      }
      // On the protective side of the price now, or it fires at once:
      // a long's stop under it and take over it, a short's the mirror; a
      // limit at or past its trigger on the closing side.
      final issue = hlProtectIssueText(
          context.l10n,
          hlProtectIssue(
              closeIsBuy: !pos.isLong,
              tpsl: _isStopClose ? 'sl' : 'tp',
              trigger: trigger,
              mark: _markNow(),
              limitPx: limit));
      if (issue != null) return issue;
    } else if (_isTwapClose) {
      final m = _parseInt(_twapMinutesCtrl);
      if (m == null ||
          m < HyperliquidExchangeService.minTwapMinutes ||
          m > HyperliquidExchangeService.maxTwapMinutes) {
        return context.l10n.slipTwapDurationRange;
      }
    }
    return null;
  }

  /// A stop at or past the liquidation price would never fire before the
  /// venue liquidates the position: said, not blocked.
  String? get _stopWarning {
    if (!_isStopClose) return null;
    final trigger = _parsePx(_triggerPxCtrl);
    if (trigger == null) return null;
    return hlStopPastLiquidation(
            closeIsBuy: !pos.isLong,
            trigger: trigger,
            liquidation: hlLiquidationPrice(pos))
        ? context.l10n.hlProtectStopPastLiquidation
        : null;
  }

  /// The Ledger's protective orders on this coin, from its last account
  /// read: null when there are none, -1 when its orders could not be read
  /// (they may still be there).
  int? _ledgerProtectiveCount() {
    final id = widget.ledgerWalletId;
    if (id == null) return null;
    final orders =
        ref.read(ledgerHlAccountProvider(id)).valueOrNull?.openOrders;
    if (orders == null) return -1;
    final n = hlProtectiveOrdersFor(orders, pos.coin).length;
    return n == 0 ? null : n;
  }

  /// A whole-position close (market, or a limit or TWAP sized to all of
  /// it) also cancels the position's resting stops, takes and trailing
  /// stops once the position is gone (each could otherwise close a
  /// position opened later): said before it is sent.
  Widget? _leftoversNote(AppColorsExtension c, {Color? color}) {
    final whole = _isMarketClose
        ? _fraction >= 0.999
        : (_isLimitClose || _isTwapClose) &&
            _totalSize > 0 &&
            _closeSize >= _totalSize * (1 - 1e-9);
    if (!whole) return null;
    final left = hlProtectiveOrdersFor(_orders(watch: true), pos.coin);
    if (left.isEmpty) return null;
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Text(
        context.l10n.hlProtectCloseCancelsOrders(left.length),
        key: const ValueKey('hl-close-leftovers-note'),
        style: TextStyle(color: color ?? c.textSecondary, fontSize: 13.sp),
      ),
    );
  }

  /// A stop loss already rests on this position: said, with the choice to
  /// replace it or add a second one (Protect it, the stop types).
  Widget? _existingStopChoice(AppColorsExtension c) {
    if (!_isStopClose) return null;
    final stops = hlStopLossesFor(_orders(watch: true), pos.coin);
    if (stops.isEmpty) return null;
    final first = stops.first;
    final px = formatHlPrice(first.triggerPx ?? first.limitPx,
        decimalCap: _market?.pxDecimalCap);
    return Padding(
      key: const ValueKey('hl-protect-existing-stop'),
      padding: EdgeInsets.only(top: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stops.length == 1
                ? context.l10n.hlProtectExistingStop(px)
                : context.l10n.hlProtectExistingStops(stops.length),
            style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
          ),
          SizedBox(height: 8.h),
          HlSegmentTrack(segments: [
            HlTrackSegment(
                label: context.l10n.hlProtectReplaceStop,
                selected: _replaceStop,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _settingChanged('replace_stop', true);
                  setState(() => _replaceStop = true);
                }),
            HlTrackSegment(
                label: context.l10n.hlProtectAddStop,
                selected: !_replaceStop,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _settingChanged('replace_stop', false);
                  setState(() => _replaceStop = false);
                }),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget._advancedPage
        ? context.colors
        : sideTintPalette(context.colors, AppColors.marketDown);

    // Live mark for the preview — falls back to the snapshot-implied
    // mark when the WS hasn't ticked yet.
    final liveMid = ref.watch(hyperliquidLiveMidProvider(pos.coin));
    final snapshotMark =
        pos.szi.abs() > 0 ? pos.positionValue / pos.szi.abs() : pos.entryPx;
    final mark = liveMid ?? snapshotMark;

    final closeSz = _closeSize;
    final paramError = _paramError;
    final enteredSize = double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    final canConfirm = enteredSize != null &&
        enteredSize.isFinite &&
        enteredSize > 0 &&
        enteredSize <= _totalSize &&
        paramError == null;
    final failed = _errorText != null;

    if (widget._advancedPage) {
      final l = context.l10n;
      // The page: the form scrolls under the one button, which floats at
      // the foot (AdvancedTicketFrame); a reason over it sits on the
      // page's own ground. Its room is measured, so the last card clears it.
      final cta = PolySlipCta(
        color: AppColors.marketDown,
        isBusy: _isClosing,
        bandProgress: _bandProgress,
        bandOutcome: _bandOutcome,
        bandExpected: const Duration(seconds: 2),
        enabled: canConfirm && !_isClosing && _advancedBlock == null,
        onTap: _handleClose,
        label: failed ? l.retry : _ctaLabel(),
        busyLabel: l.loading,
        disabledLabel: canConfirm ? null : l.barNeedAmount,
      );
      final primary = HlReportSize(
        onSize: (size) {
          if (!mounted || (size.height - _advPrimaryHeight).abs() < 0.5) {
            return;
          }
          setState(() => _advPrimaryHeight = size.height);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_advancedBlock case final reason?) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c.background.withValues(alpha: 0), c.background],
                  ),
                ),
                child: SizedBox(height: 28.h, width: double.infinity),
              ),
              ColoredBox(
                color: c.background,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: CapabilityBlockNote(reason),
                ),
              ),
            ],
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
              child: cta,
            ),
          ],
        ),
      );
      final form = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // What is held, then the size to close as the hero.
          Text(
            '$_displayCoin · ${pos.isLong ? l.longLabel : l.shortLabel} · ${pos.leverageValue}x',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 12.h),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.amount,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4.h),
              AdvancedHeroAmount(
                key: const ValueKey('hl-close-adv-amount'),
                controller: _amountCtrl,
                prefix: '',
                readOnly: _isClosing,
                caption:
                    '${l.available}: ${formatHlSize(_totalSize)} $_displayCoin',
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
              ),
            ],
          ),
          SizedBox(height: 24.h),
          _advancedHeading(c, l.investingOrderType),
          _buildAdvancedContent(c, mark),
          SizedBox(height: 24.h),
          _advancedHeading(c, l.details),
          AdvancedSummaryCard(
            key: const ValueKey('hl-close-adv-summary'),
            footer: [_buildFeeSummary(mark, closeSz)],
          ),
          if (_errorText != null) ...[
            SizedBox(height: 10.h),
            HlTradeErrorNotice(message: _errorText!, error: _errorDetails),
          ],
          if (paramError != null) ...[
            SizedBox(height: 10.h),
            Text(paramError,
                style: TextStyle(color: c.error, fontSize: 13.sp)),
          ],
          if (paramError == null && _stopWarning != null) ...[
            SizedBox(height: 10.h),
            Text(_stopWarning!,
                key: const ValueKey('hl-protect-liq-warning'),
                style: TextStyle(color: c.warning, fontSize: 13.sp)),
          ],
          if (_leftoversNote(c) case final note?) note,
        ],
      );
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backFromAdvanced();
        },
        child: KeyboardDismissOnTap(
          child: AdvancedTicketFrame(
            title: l.walletsAdvanced,
            scrollKey: const ValueKey('hl-close-adv-scroll'),
            onBack: _backFromAdvanced,
            canPop: !_isClosing,
            primaryHeight: _advPrimaryHeight,
            primary: primary,
            children: [
              hlAdvancedSwitchTheme(
                context,
                child: IgnorePointer(ignoring: _isClosing, child: form),
              ),
            ],
          ),
        ),
      );
    }

    // The ticket's identity row, pinned above the form the way the buy
    // slip pins its header, and the very header the Predictions tickets
    // use: the coin's logo, the title (two lines at most) and the round
    // close X. The side and size are the pill under it; no leverage chip.
    final header = PolySlipHeader(
      marketQuestion: context.l10n.closeTitle(_displayCoin),
      leading: _marketArtwork(),
      maxLines: 2,
    );

    // The close's two figures, off the position screen's own reading
    // (hlCloseValue: the margin plus the profit or loss) for the share
    // being closed, at the price it closes at, and the fee the Advanced
    // page itemises: what comes back after the fee, and the profit or
    // loss on that share after it, against its margin.
    final orderPx = (_isLimitClose || _isTriggerLimit)
        ? (_parsePx(_limitPxCtrl) ?? mark)
        : _isTriggerClose
            ? (_parsePx(_triggerPxCtrl) ?? mark)
            : mark;
    final share =
        _totalSize > 0 ? (closeSz / _totalSize).clamp(0.0, 1.0) : 0.0;
    final fee = watchHyperliquidOrderFeeUsd(
      ref,
      HyperliquidFeeLeg(
          notional: closeSz * orderPx,
          spot: false,
          buy: false,
          dex: _market?.dex ?? (pos.coin.contains(':') ? 'unknown' : '')),
      useHotAccount: widget.ledgerWalletId == null,
      address: widget.ledgerWalletId == null
          ? null
          : ref
              .watch(ledgerIdentityProvider(widget.ledgerWalletId!))
              ?.evmAddress,
      builder: !_isTwapClose,
    );
    final grossBack = hlCloseValue(pos, liveMid: orderPx) * share;
    final back = grossBack - (fee ?? 0);
    final pnl = hlLivePnl(pos, liveMid: orderPx) * share - (fee ?? 0);
    // Green and red do not read on the red sheet: the sign carries the
    // direction, in the sheet's ink.
    final pnlColor =
        closeSz <= 0 || pnl.abs() < 0.005 ? c.textSecondary : c.textPrimary;
    final wholeValue = _totalSize * mark;
    final overWhole = (double.tryParse(_usdText) ?? 0) >
        (double.tryParse(_usdForSize(_totalSize)) ?? 0);

    // The buy slip's frame, to the scroll: the header and the pinned
    // keypad and button around one clamping form that scrolls on its own
    // (never the route's primary scroll controller), and a height cap that
    // leaves room for a keyboard.
    final sheet = Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Close is money out of the position: the sheet wears the down
      // colour, as the Predictions sell ticket does.
      decoration: BoxDecoration(
        color: AppColors.marketDown,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (MediaQuery.of(context).size.height * 0.92 -
                    MediaQuery.of(context).viewInsets.bottom)
                .clamp(0.0, double.infinity),
          ),
          child: SlipFit(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              // The form over the pinned keypad, fitted to the screen: the
              // keypad gives its room first, then the ticket goes compact,
              // and only then does the form scroll (SlipFormBody).
              Flexible(
                  child: SlipFormBody(
                expandForMessage: false,
                form: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 14.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // What is held, in its side's colour: "Long · 0.5 BTC".
                    PositionSidePill(
                      key: const ValueKey('hl-close-held'),
                      text:
                          '${pos.isLong ? context.l10n.longLabel : context.l10n.shortLabel}'
                          ' · ${formatHlSize(_totalSize)} $_displayCoin',
                      color: c.textPrimary,
                      up: pos.isLong,
                    ),
                    SlipGap(18.h),
                    // ── Amount to close ─────────────────────────────────
                    // The one big figure, in dollars, typed on the keypad
                    // pinned below (no focused field, so the OS keyboard
                    // never covers the preview), with one quiet line: the
                    // position's value now. The small Max beside it (as on
                    // the buy slips) fills the whole position again after
                    // an edit; `_amountCtrl` stays the single source of
                    // truth for the size.
                    BigAmountDisplay(
                      prefix: r'$',
                      amountText: _usdText,
                      availableLabel:
                          '${context.l10n.slipPositionValue} ${formatHlUsd(wholeValue)}',
                      availableExceeded: overWhole,
                      // Max, then the Advanced pill: inert while a close
                      // is in flight (the button below carries the wait).
                      trailing: SlipAmountPills(
                        max: _totalSize > 0
                            ? AmountMaxChip(
                                label: context.l10n.max,
                                semanticLabel: context.l10n.amountUseMaximum,
                                onTap: _isClosing ? null : _useWholePosition,
                              )
                            : null,
                        advanced: SlipAdvancedButton(
                          onTap: _openAdvanced,
                          modified: _advancedSummary != null,
                          enabled: !_isClosing,
                        ),
                      ),
                    ),
                    // Advanced is the pill beside Max; when it is not the
                    // default, a chip under the amount says what it is.
                    if (_advancedSummary case final summary?) ...[
                      SlipGap(10.h),
                      SlipAdvancedChip(text: summary, onTap: _openAdvanced),
                    ],
                    SlipGap(20.h),

                    // ── What comes back ───────────────────────────────────
                    // Two figures, no boxes, zero until something is typed.
                    SlipFigures(
                      left: SlipFigure(
                        key: const ValueKey('hl-close-proceeds'),
                        label: context.l10n.youReceive,
                        value: share > 0
                            ? formatHlUsd(math.max(
                                0.0, fee == null ? grossBack : back))
                            : slipZeroFigure(formatHlUsd(0)),
                      ),
                      right: SlipFigure(
                        key: const ValueKey('hl-close-pnl'),
                        label: context.l10n.portfolioProfitLoss,
                        value: share <= 0 || pnl.abs() < 0.005
                            ? slipZeroFigure(formatHlUsd(0))
                            : '${pnl < 0 ? '−' : '+'}${formatHlUsd(pnl.abs())}',
                        valueColor: pnlColor,
                      ),
                    ),
                    if (_errorText != null) ...[
                      SlipGap(10.h),
                      HlTradeErrorNotice(
                          message: _errorText!, error: _errorDetails),
                    ] else if (paramError != null) ...[
                      SizedBox(height: 10.h),
                      Text(
                        paramError,
                        style: TextStyle(color: redColor, fontSize: 13.sp),
                      ),
                    ],
                    if (_leftoversNote(c, color: c.textPrimary)
                        case final note?)
                      note,
                  ],
                ),
              ),

              // ── Keypad, pinned ──────────────────────────────────────
              // Drives the close amount, in dollars. Always there: the
              // price and duration fields that raise the OS keyboard live
              // on the Advanced page, not on this ticket.
              input: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: AmountKeypad(
                  value: _usdText,
                  maxDecimals: 2,
                  enabled: !_isClosing,
                  onChanged: _onKeypadUsd,
                ),
              ),
              )),

              // ── CTA, pinned ─────────────────────────────────────────
              // On the red sheet the button is the sheet's white with dark
              // letters (white buttons never take a coloured label). The
              // money stays in Investing, so there is no journey: an
              // in-flight close spins here rather than swapping the
              // ticket for a panel.
              //
              // The greater of a comfortable gap and the system inset,
              // never both added together.
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w,
                    math.max(16.h, MediaQuery.of(context).padding.bottom)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_advancedBlock case final reason?)
                    CapabilityBlockNote(reason),
                  PolySlipCta(
                    label: failed ? context.l10n.retry : _ctaLabel(),
                    onTap: _handleClose,
                    enabled:
                        canConfirm && !_isClosing && _advancedBlock == null,
                    isBusy: _isClosing,
                    bandProgress: _bandProgress,
                    bandOutcome: _bandOutcome,
                    bandExpected: const Duration(seconds: 2),
                    busyLabel: context.l10n.loading,
                    color: AppColors.marketDown,
                    neutral: true,
                    disabledLabel: canConfirm ? null : context.l10n.barNeedAmount,
                  ),
                ]),
              ),
            ],
          ),
          ),
        ),
      ),
    );

    // An in-flight close cannot be dismissed out from under itself. The
    // flag is released before the sheet closes itself on success (see
    // _popToHost), so the hand-off to the confirmation is never refused.
    return PopScope(
        canPop: !_isClosing,
        child: SideTintedSubtree(
            side: AppColors.marketDown,
            // A side panel on EXPANDED wears the sheet's colour to its
            // foot, the primary on it (kute_dialog.dart).
            child: KuteDialogSurfaceMark(color: AppColors.marketDown, child: sheet)));
  }

  String _ctaLabel() {
    final l10n = context.l10n;
    if (_isMarketClose) {
      return l10n.closeNowPercent((_fraction * 100).round());
    }
    return switch (_closeType) {
      _CloseType.market => l10n.closeMarketCta,
      _CloseType.limit => l10n.closeLimitCta,
      _CloseType.stopMarket => l10n.closeStopMarketCta,
      _CloseType.stopLimit => l10n.closeStopLimitCta,
      _CloseType.takeMarket => l10n.closeTakeMarketCta,
      _CloseType.takeLimit => l10n.closeTakeLimitCta,
      _CloseType.twap => l10n.closeTwapCta,
    };
  }

  String _closeTypeLabel() {
    switch (_closeType) {
      case _CloseType.market:
        return context.l10n.ledgerOrderMarketPrice;
      case _CloseType.limit:
        return context.l10n.betOrderTypeLimit;
      case _CloseType.stopMarket:
        return context.l10n.slipStopMarket;
      case _CloseType.stopLimit:
        return context.l10n.slipStopLimit;
      case _CloseType.takeMarket:
        return context.l10n.slipTakeMarket;
      case _CloseType.takeLimit:
        return context.l10n.slipTakeLimit;
      case _CloseType.twap:
        return 'TWAP';
    }
  }

  // ── Advanced section ────────────────────────────────────────────────

  /// What Advanced is set to when it is not a market close (the close's
  /// type), for the chip under the amount; null: the default.
  String? get _advancedSummary => _isMarketClose ? null : _closeTypeLabel();

  /// A group's heading on the Advanced page.
  Widget _advancedHeading(AppColorsExtension c, String text) => Padding(
        padding: EdgeInsets.only(bottom: 10.h),
        child: Text(
          text,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      );

  Widget _buildAdvancedContent(AppColorsExtension c, double mark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_market != null) ...[
          _buildTypePicker(c),
          ..._buildPriceInputs(c, mark),
          if (_existingStopChoice(c) case final choice?) choice,
          SizedBox(height: 12.h),
          // Its own Material: the card's fill would hide the tile's ink.
          // Sized by the close amount: with none typed it says so and
          // takes no tap.
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: AppDecorations.card(context),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                  key: const ValueKey('hl-close-trailing-stop'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      pos.isLong
                          ? Icons.trending_down_rounded
                          : Icons.trending_up_rounded,
                      size: 20,
                      color: c.textSecondary),
                  minLeadingWidth: 20,
                  title: Text(context.l10n.investingTrailingStop),
                  subtitle: _closeSize > 0
                      ? null
                      : Text(context.l10n.barNeedAmount,
                          style: TextStyle(color: c.textSecondary)),
                  enabled: _closeSize > 0 && !_isClosing,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _closeSize > 0 ? _openTrailingStop : null),
            ),
          ),
        ],
        if (_isMarketClose) ...[
          SizedBox(height: 16.h),
          _buildSlippageRow(c),
        ],
      ],
    );
  }

  Widget _buildTypePicker(AppColorsExtension c) => Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: HlSegmentTrack(segments: [
          HlTrackSegment(
              label: context.l10n.ledgerOrderMarketPrice,
              selected: _isMarketClose,
              onTap: () => _onSelectType(_CloseType.market)),
          HlTrackSegment(
              label: context.l10n.betOrderTypeLimit,
              selected: _isLimitClose,
              onTap: () => _onSelectType(_CloseType.limit)),
          if (widget.ledgerWalletId == null)
            HlTrackSegment(
                label: !_isMarketClose && !_isLimitClose
                    ? _closeTypeLabel()
                    : context.l10n.receiveMoreOptions,
                selected: !_isMarketClose && !_isLimitClose,
                chevron: true,
                onTap: _openMoreCloseTypes),
        ]),
      );

  Future<void> _openTrailingStop() async {
    final market = _market;
    final walletId =
        widget.ledgerWalletId ??
        pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (_isClosing || market == null || walletId == null || _closeSize <= 0) {
      return;
    }
    final result = await HlTrailingStopSheet.show(
      context,
      market: market,
      size: _closeSize,
      isBuy: !pos.isLong,
      reduceOnly: true,
      leverage: pos.leverageValue,
      isCross: pos.leverageType == 'cross',
      walletId: walletId,
      ledger: widget.ledgerWalletId != null,
    );
    if (!mounted || result == null) return;
    await _showCloseAccepted(Navigator.of(context, rootNavigator: true),
        snap: false);
  }

  Future<void> _openMoreCloseTypes() async {
    final picked = await showHlOrderTypePicker<_CloseType>(context,
        selected: _closeType,
        items: [
          (_CloseType.stopLimit, context.l10n.slipStopLimit),
          (_CloseType.stopMarket, context.l10n.slipStopMarket),
          (_CloseType.takeLimit, context.l10n.slipTakeLimit),
          (_CloseType.takeMarket, context.l10n.slipTakeMarket),
          (_CloseType.twap, 'TWAP'),
        ]);
    if (mounted && picked != null) _onSelectType(picked);
  }

  /// [px] written into [ctrl] as the wire sends it.
  void _setPx(TextEditingController ctrl, double px) {
    if (!(px > 0) || !px.isFinite) return;
    final m = _market;
    String text;
    try {
      text = m == null
          ? _fmtPx(px)
          : roundPrice(px, szDecimals: m.szDecimals, isSpot: false);
    } catch (_) {
      text = _fmtPx(px);
    }
    setState(() => ctrl.text = text);
  }

  /// One venue tick up or down from the typed price (or from [base]).
  void _stepPx(TextEditingController ctrl, int dir, double base) {
    final cur = _parsePx(ctrl) ?? base;
    if (!(cur > 0)) return;
    final tick = hlPriceTick(dir < 0 ? cur * (1 - 1e-9) : cur,
        szDecimals: _market?.szDecimals ?? 0, isSpot: false);
    _setPx(ctrl, cur + dir * tick);
  }

  /// A price stepper and, under it, presets at [pcts] from [base] (a
  /// chip only writes the field; the checks judge it).
  List<Widget> _priceStepper(AppColorsExtension c,
      TextEditingController ctrl, String key, String label, double base,
      {required List<double> pcts, bool snap = false}) {
    final l = context.l10n;
    final cap = _market?.pxDecimalCap;
    final prices = [for (final p in pcts) base * (1 + p / 100)];
    double? wire(double v) => _market == null
        ? v
        : wireRoundedPrice(v, szDecimals: _market!.szDecimals, isSpot: false);
    final now = wire(_parsePx(ctrl) ?? -1);
    final at = now == null ? -1 : prices.indexWhere((p) => wire(p) == now);
    return [
      HlStepField(
        key: ValueKey('hl-close-stepper-$key'),
        fieldKey: ValueKey('hl-close-field-$key'),
        controller: ctrl,
        label: label,
        prefix: r'$',
        formatPrice: (v) => formatHlPrice(v, decimalCap: cap),
        readOnly: _isClosing,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        onChanged: (_) => setState(() {}),
        onStep: (dir) => _stepPx(ctrl, dir, base),
        // A trigger is never snapped to the price now: it would fire at
        // once.
        trailing: snap && base > 0
            ? '${l.ledgerOrderMarketPrice} ${formatHlPrice(base, decimalCap: cap)}'
            : null,
        onTrailing: snap ? () => _setPx(ctrl, base) : null,
      ),
      if (base > 0)
        Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: AdvancedChips(
            key: ValueKey('hl-close-chips-$key'),
            labels: [
              for (final p in pcts)
                '${p < 0 ? '−' : '+'}${p.abs().toStringAsFixed(0)}%'
            ],
            selected: at < 0 ? null : at,
            onSelected: _isClosing ? (_) {} : (i) => _setPx(ctrl, prices[i]),
          ),
        ),
    ];
  }

  /// Per-type price / trigger / duration inputs — only the selected type's
  /// fields render (mirrors the order slip's _buildPriceInputs), each a
  /// stepper.
  List<Widget> _buildPriceInputs(AppColorsExtension c, double mark) {
    final l = context.l10n;
    // A close sells a long (rests above the price) and buys back a short.
    final up = pos.isLong ? 1.0 : -1.0;
    final isStop = _closeType == _CloseType.stopMarket ||
        _closeType == _CloseType.stopLimit;
    final triggerPcts = [
      for (final p in const [2.0, 5.0, 10.0]) (isStop ? -up : up) * p
    ];
    final limitPcts = [for (final p in const [1.0, 2.0, 5.0]) up * p];
    switch (_closeType) {
      case _CloseType.market:
        return const [];
      case _CloseType.limit:
        return [
          SizedBox(height: 12.h),
          ..._priceStepper(c, _limitPxCtrl, 'limit', l.betLimitPrice, mark,
              pcts: limitPcts, snap: true),
        ];
      case _CloseType.stopMarket:
      case _CloseType.takeMarket:
        return [
          SizedBox(height: 12.h),
          ..._priceStepper(
              c, _triggerPxCtrl, 'trigger', l.slipTriggerPrice, mark,
              pcts: triggerPcts),
        ];
      case _CloseType.stopLimit:
      case _CloseType.takeLimit:
        return [
          SizedBox(height: 12.h),
          ..._priceStepper(
              c, _triggerPxCtrl, 'trigger', l.slipTriggerPrice, mark,
              pcts: triggerPcts),
          SizedBox(height: 10.h),
          ..._priceStepper(c, _limitPxCtrl, 'limit', l.betLimitPrice,
              _parsePx(_triggerPxCtrl) ?? mark,
              pcts: limitPcts, snap: true),
        ];
      case _CloseType.twap:
        return [
          SizedBox(height: 12.h),
          HlStepField(
            key: const ValueKey('hl-close-stepper-twap'),
            fieldKey: const ValueKey('hl-close-field-twap'),
            controller: _twapMinutesCtrl,
            label: l.closeTwapMinutes,
            decimal: false,
            readOnly: _isClosing,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            onStep: (dir) {
              final cur = _parseInt(_twapMinutesCtrl) ?? 5;
              setState(() =>
                  _twapMinutesCtrl.text = '${math.max(5, cur + dir * 5)}');
            },
          ),
          SizedBox(height: 10.h),
          HlSwitchRow(
            label: l.slipRandomizeTiming,
            value: _randomizeTwap,
            card: true,
            onChanged: (v) {
              _settingChanged('twap_randomized', v);
              setState(() => _randomizeTwap = v);
            },
          ),
        ];
    }
  }

  // ── Slippage / preview / panels ─────────────────────────────────────

  Widget _buildSlippageRow(AppColorsExtension c) {
    final at = _slippageOptions.indexOf(_slippagePct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.maxSlippage,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8.h),
        AdvancedChips(
          key: const ValueKey('hl-close-slippage'),
          labels: [for (final option in _slippageOptions) '$option%'],
          selected: at < 0 ? null : at,
          onSelected: (i) {
            final option = _slippageOptions[i];
            _settingChanged('slippage_bps', VenueAnalytics.bps(option));
            setState(() => _slippagePct = option);
          },
        ),
      ],
    );
  }

  Widget _buildFeeSummary(double mark, double closeSz) => HyperliquidFeeSummary(
        notional: closeSz *
            ((_isLimitClose || _isTriggerLimit)
                ? (_parsePx(_limitPxCtrl) ?? mark)
                : _isTriggerClose
                    ? (_parsePx(_triggerPxCtrl) ?? mark)
                    : mark),
        spot: false,
        buy: false,
        useHotAccount: widget.ledgerWalletId == null,
        address: widget.ledgerWalletId == null
            ? null
            : ref
                .watch(ledgerIdentityProvider(widget.ledgerWalletId!))
                ?.evmAddress,
        builder: !_isTwapClose,
        dex: _market?.dex ?? (pos.coin.contains(':') ? 'unknown' : ''),
      );

}
