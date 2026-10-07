import 'trailing_stop_sheet.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_order_controls.dart';
import 'package:kute/screens/ledger/hyperliquid/ledger_hl_execution_target.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:kute/screens/hyperliquid/components/builder_fee_consent.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
// Reduce-only closes: a tinted ticket and a separate Advanced page share
// the same reviewed submission path. Ledger approval stays wallet-scoped.

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
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
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/theme/app_theme.dart';

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
    unawaited(OpenOnce.run(routeName, () => showModalBottomSheet(
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
  String? _errorText;
  Object? _errorDetails;

  // ── Advanced close order type ──────────────────────────────────────
  bool _openingAdvanced = false;
  _CloseType _closeType = _CloseType.market;

  /// Per-type price/duration inputs (only the selected type's fields show).
  final TextEditingController _limitPxCtrl = TextEditingController();
  final TextEditingController _triggerPxCtrl = TextEditingController();
  final TextEditingController _twapMinutesCtrl =
      TextEditingController(text: '30');
  bool _randomizeTwap = false;

  HlPerpPosition get pos => widget.position;

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
  Widget _marketArtwork() => HlCoinIcon(
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

  // Analytics (root sheet only): flow timing, why it stopped, submission.
  final DateTime _openedAt = DateTime.now();
  String _flowStep = 'amount';
  String? _stopReason;
  String? _lastErrorCategory;
  bool _closeSubmitted = false;
  String _amountMethod = 'prefill';
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
      'size_unit': 'coin',
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
    // Default to a full close, shown in the field so the user can edit it down
    // to any custom size (adapts to THIS position — its coin, its max size).
    _fraction = 1.0;
    _amountCtrl.text = _fmtSize(_totalSize);
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

  /// Decimals the keypad lets the user type for a coin size. Matches
  /// [_fmtSize], which is what the presets and the initial full close put
  /// in the field, so a prefilled value is always retypeable.
  static const int _sizeDecimals = 6;

  /// A key on the built-in keypad. `_amountCtrl` stays the source of truth,
  /// so this only writes the new string and lets [_onAmountChanged] derive
  /// `_fraction`. The extra repaint covers keystrokes that leave the parsed
  /// size alone but change what the big number reads ('1' → '1.').
  void _onKeypadAmount(String v) {
    if (v == _amountCtrl.text) return;
    _amountCtrl.text = v;
    setState(() {});
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
    setState(() => _fraction = 1.0);
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
          .push<_CloseDraft>(MaterialPageRoute(
        settings: const RouteSettings(name: HlClosePositionSheet.routeName),
        fullscreenDialog: true,
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
      if (_isTriggerClose) {
        if (_triggerPxCtrl.text.trim().isEmpty) {
          _triggerPxCtrl.text = _fmtPx(mark);
        }
        if (_isTriggerLimit && _limitPxCtrl.text.trim().isEmpty) {
          _limitPxCtrl.text = _fmtPx(mark);
        }
      }
    });
  }

  // ── Confirm ────────────────────────────────────────────────────────

  Future<void> _handleClose() async {
    if (_closeInFlight || _isClosing) return;
    _closeInFlight = true;
    setState(() {
      _isClosing = true;
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
        _trackSubmitted();
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
        setState(() => _isClosing = false);
        final nav = Navigator.of(context, rootNavigator: true);
        final result = outcome?.result;
        if (outcome?.isSuccess == true && result != null) {
          if (result.filledSz > 0 || _isMarketClose) {
            _showClosedResult(nav, result, checkOpenOrders: _isLimitClose);
          } else {
            _showCloseAccepted(nav);
          }
        } else if (outcome?.isPending == true) {
          // An ambiguous submission is not a confirmed close: leave its
          // reconciliation to the pending action without a success haptic.
          _popToHost(nav);
        } else {
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
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: approved.intent,
      reason: context.l10n.stepUpReasonOrder(
          '${pos.coin} · ${hlKindLabel(context.l10n, isSpot: false)}'),
      amountUsd: _closeSize * _markNow(),
    );
    if (grant == null || !mounted) {
      if (grant == null) _stopped('signing_declined');
      return;
    }

    _trackSubmitted();
    setState(() {
      _isClosing = true;
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
    final order = await _closeOrder(walletId);
    final result = await order.place(grant);

    if (!mounted) return;
    _showClosedResult(nav, result);
  }

  void _showClosedResult(NavigatorState nav, HlOrderResult result,
      {bool checkOpenOrders = false}) {
    final l10n = context.l10n;
    _popToHost(nav);

    // Actual fill figures — never the requested size (IOC can
    // partially fill; the remainder is cancelled by definition).
    final closedSz = result.filledSz;
    final avgPx = result.avgPx;
    final direction = pos.isLong ? 1.0 : -1.0;
    final realizedPnl =
        closedSz > 0 ? (avgPx - pos.entryPx) * closedSz * direction : 0.0;
    final remaining = (pos.szi.abs() - closedSz).clamp(0.0, double.infinity);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: KuteConfirmation(
        message: closedSz <= 0
            ? l10n.investingNoFillConfirmed
            : remaining > 0.00000001
                ? l10n.investingPartiallyClosed
                : l10n.investingPositionClosed,
        success: closedSz > 0,
        showCloseButton: true,
        onDone: () => nav.pop(),
        detail: checkOpenOrders && remaining > 0.00000001
            ? l10n.investingCloseRemainderNote
            : l10n.investingBalanceUpdating,
        receipt: TradeReceipt(
            leading: _marketArtwork(),
            title: _displayCoin,
            subtitle: pos.isLong ? l10n.longLabel : l10n.shortLabel,
            rows: {
              l10n.investingAmountClosed:
                  '${formatHlSize(closedSz)} $_displayCoin',
              l10n.investingExitPrice:
                  formatHlPrice(avgPx, decimalCap: _market?.pxDecimalCap),
              l10n.investingProfitBeforeCosts:
                  '${realizedPnl >= 0 ? '+' : '−'}\$${realizedPnl.abs().toStringAsFixed(2)}',
              if (remaining > 0.00000001)
                l10n.investingStillOpen:
                    '${formatHlSize(remaining)} $_displayCoin',
            }),
      ),
    );
  }

  /// Limit / Stop / Take / TWAP — all REDUCE-ONLY resting orders sized in coin
  /// units off the typed amount. The closing side is the OPPOSITE of the
  /// position (long → isLong:false to reduce). These don't fill immediately,
  /// so on success we pop with a "close order placed" resting confirmation.
  Future<void> _runAdvancedClose(
      NavigatorState nav, String walletId, AuthGrant grant) async {
    // Rebuilt from the sheet as it is now (see _runMarketClose).
    final order = await _closeOrder(walletId);
    final result = await order.place(grant);

    if (!mounted) return;
    if (result.filledSz > 0) {
      _showClosedResult(nav, result, checkOpenOrders: true);
      return;
    }
    _showCloseAccepted(nav);
  }

  void _showCloseAccepted(NavigatorState nav) {
    final amount = '${formatHlSize(_closeSize)} $_displayCoin';
    _popToHost(nav);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: HlOrderAcceptedOverlay(
        coin: _displayCoin,
        market: _market,
        amount: amount,
        isClose: true,
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
    if (_market == null) {
      return context.l10n.closeOrderDetailsUnavailable;
    }
    if (_isLimitClose) {
      if (_parsePx(_limitPxCtrl) == null) {
        return context.l10n.slipEnterLimitPrice;
      }
    } else if (_isTriggerClose) {
      if (_parsePx(_triggerPxCtrl) == null) {
        return context.l10n.slipEnterTriggerPrice;
      }
      if (_isTriggerLimit && _parsePx(_limitPxCtrl) == null) {
        return context.l10n.slipEnterLimitPrice;
      }
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

    final ticket = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
            child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: IgnorePointer(
              ignoring: _isClosing,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 12.h),
                  HlAdvancedSection(title: _displayCoin, children: [
                    Text(
                        '${pos.isLong ? context.l10n.longLabel : context.l10n.shortLabel} · ${pos.leverageValue}x',
                        style: TextStyle(color: c.textSecondary)),
                    SizedBox(height: 12.h),
                    HlNumericField(
                        label: context.l10n.amount,
                        valueFontSize: 28.sp,
                        onChanged: (_) {},
                        controller: _amountCtrl,
                        prefix: _displayCoin,
                        readOnly: _isClosing,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ]),
                    SizedBox(height: 8.h),
                    Text(
                        '${context.l10n.available}: ${formatHlSize(_totalSize)} $_displayCoin',
                        style: TextStyle(color: c.textSecondary)),
                  ]),
                  HlAdvancedSection(
                      title: context.l10n.investingOrderType,
                      children: [_buildAdvancedContent(c)]),
                  _buildFeeSummary(mark, closeSz),
                  if (_errorText != null)
                    HlTradeErrorNotice(
                        message: _errorText!, error: _errorDetails),
                  if (paramError != null)
                    Text(paramError, style: TextStyle(color: c.error)),
                  SizedBox(height: 16.h),
                ],
              )),
        )),
        Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_advancedBlock case final reason?)
                CapabilityBlockNote(reason),
              PolySlipCta(
                color: AppColors.marketDown,
                isBusy: _isClosing,
                enabled: canConfirm && !_isClosing && _advancedBlock == null,
                onTap: _handleClose,
                label: failed ? context.l10n.retry : _ctaLabel(),
                busyLabel: context.l10n.loading,
              ),
            ])),
      ],
    );
    if (widget._advancedPage) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _backFromAdvanced();
        },
        child: KeyboardDismissOnTap(
            child: PolySlipAdvancedScaffold(
          title: context.l10n.walletsAdvanced,
          onBack: _backFromAdvanced,
          canPop: !_isClosing,
          body: ticket,
        )),
      );
    }

    // The ticket's identity row, pinned above the form the way the buy
    // slip pins its header: only the form scrolls, and it scrolls under
    // this row instead of carrying it away.
    final header = Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 0),
      child: Row(
        children: [
          _marketArtwork(),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.closeTitle(_displayCoin),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3.h),
                Row(
                  children: [
                    HlSideChip(
                      text: pos.isLong ? 'LONG' : 'SHORT',
                      color: c.textPrimary,
                    ),
                    SizedBox(width: 6.w),
                    HlMetaChip(
                      text: '${pos.leverageValue}x',
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed:
                _isClosing ? null : () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_rounded, color: c.textPrimary, size: 22.sp),
          ),
        ],
      ),
    );
    // The buy slip's frame, to the scroll: the header and the pinned
    // keypad and button around one clamping form that scrolls on its own
    // (never the route's primary scroll controller), and a height cap that
    // leaves room for a keyboard.
    final sheet = Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              Flexible(
                  child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                primary: false,
                padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 14.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Amount to close ─────────────────────────────────
                    // The one big figure, typed on the keypad pinned below
                    // (no focused field, so the OS keyboard never covers
                    // the preview). The small Max beside it (as on the buy
                    // slips) fills the whole position again after an edit,
                    // and `_amountCtrl` stays the single source of truth.
                    BigAmountDisplay(
                      amountText: _amountCtrl.text,
                      suffix: ' $_displayCoin',
                      conversionLabel: formatHlUsd(closeSz * mark),
                      availableLabel:
                          '${context.l10n.available}: ${formatHlSize(_totalSize)} $_displayCoin',
                      trailing: _totalSize > 0
                          ? AmountMaxChip(
                              label: context.l10n.max,
                              semanticLabel: context.l10n.amountUseMaximum,
                              onTap: _isClosing ? null : _useWholePosition,
                            )
                          : null,
                    ),
                    SizedBox(height: 14.h),

                    // ── Advanced page ────────────────────────────────────
                    // Inert while a close is in flight; the button above
                    // it carries the wait.
                    IgnorePointer(
                      ignoring: _isClosing,
                      child: _buildAdvancedSection(c),
                    ),
                    SizedBox(height: 14.h),

                    // ── Preview ───────────────────────────────────────────
                    _buildFeeSummary(mark, closeSz),
                    if (_errorText != null) ...[
                      SizedBox(height: 10.h),
                      HlTradeErrorNotice(
                          message: _errorText!, error: _errorDetails),
                    ] else if (paramError != null) ...[
                      SizedBox(height: 10.h),
                      Text(
                        paramError,
                        style: TextStyle(color: redColor, fontSize: 13.sp),
                      ),
                    ],
                  ],
                ),
              )),

              // ── Keypad, pinned ──────────────────────────────────────
              // Drives the close amount only. An Advanced price or
              // duration field still uses the OS keyboard, so the pad
              // steps aside while that keyboard is up rather than
              // stacking two keyboards.
              if (MediaQuery.viewInsetsOf(context).bottom <= 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: AmountKeypad(
                    value: _amountCtrl.text,
                    maxDecimals: _sizeDecimals,
                    enabled: !_isClosing,
                    onChanged: _onKeypadAmount,
                  ),
                ),

              // ── CTA, pinned ─────────────────────────────────────────
              // Close is a market action (money out of the position),
              // so it wears the directional down token, mirroring the
              // Long/Short entry pair — not the app-wide destructive
              // error red. It also carries the wait: an in-flight close
              // spins here rather than swapping the ticket for a panel.
              //
              // The greater of a comfortable gap and the system inset,
              // never both added together.
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w,
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
                    busyLabel: context.l10n.loading,
                    color: AppColors.marketDown,
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    // An in-flight close cannot be dismissed out from under itself. The
    // flag is released before the sheet closes itself on success (see
    // _popToHost), so the hand-off to the confirmation is never refused.
    return PopScope(
        canPop: !_isClosing,
        child: SideTintedSubtree(side: AppColors.marketDown, child: sheet));
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

  Widget _buildAdvancedSection(AppColorsExtension c) => PolySlipAdvancedRow(
        onTap: _openAdvanced,
        trailingText: _isMarketClose ? null : _closeTypeLabel(),
      );

  Widget _buildAdvancedContent(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_market != null) ...[
            _buildTypePicker(c),
            _buildPriceInputs(c),
            ListTile(contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.investingTrailingStop),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openTrailingStop),
          ],
          if (_isMarketClose) ...[
            SizedBox(height: 16.h),
            _buildSlippageRow(c),
          ],
        ],
      ),
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
    _showCloseAccepted(Navigator.of(context, rootNavigator: true));
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

  /// Per-type price / trigger / duration inputs — only the selected type's
  /// fields render (mirrors the order slip's _buildPriceInputs).
  Widget _buildPriceInputs(AppColorsExtension c) {
    switch (_closeType) {
      case _CloseType.market:
        return const SizedBox.shrink();
      case _CloseType.limit:
        return Padding(
          padding: EdgeInsets.only(top: 16.h),
          child: _priceField(c, _limitPxCtrl, context.l10n.betLimitPrice),
        );
      case _CloseType.stopMarket:
      case _CloseType.takeMarket:
        return Padding(
          padding: EdgeInsets.only(top: 16.h),
          child: _priceField(c, _triggerPxCtrl, context.l10n.slipTriggerPrice),
        );
      case _CloseType.stopLimit:
      case _CloseType.takeLimit:
        return Padding(
          padding: EdgeInsets.only(top: 16.h),
          child: Column(
            children: [
              _priceField(c, _triggerPxCtrl, context.l10n.slipTriggerPrice),
              SizedBox(height: 12.h),
              _priceField(c, _limitPxCtrl, context.l10n.betLimitPrice),
            ],
          ),
        );
      case _CloseType.twap:
        return Padding(
          padding: EdgeInsets.only(top: 16.h),
          child: Column(
            children: [
              _intField(
                  c, _twapMinutesCtrl, context.l10n.closeTwapMinutes),
              SizedBox(height: 12.h),
              _buildCheckbox(
                c,
                context.l10n.slipRandomizeTiming,
                _randomizeTwap,
                (v) {
                  _settingChanged('twap_randomized', v);
                  setState(() => _randomizeTwap = v);
                },
              ),
            ],
          ),
        );
    }
  }

  // ── Slippage / preview / panels ─────────────────────────────────────

  Widget _buildSlippageRow(AppColorsExtension c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.maxSlippage,
              style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
          SizedBox(height: 8.h),
          HlSegmentTrack(segments: [
            for (final option in _slippageOptions)
              HlTrackSegment(
                  label: '$option%',
                  selected: _slippagePct == option,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _settingChanged(
                        'slippage_bps', VenueAnalytics.bps(option));
                    setState(() => _slippagePct = option);
                  }),
          ]),
        ],
      );

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

  // ── Small field builders (mirror the order slip) ────────────────────

  Widget _priceField(
      AppColorsExtension c, TextEditingController controller, String label) {
    return _labeledField(
      c,
      label,
      controller,
      prefix: r'$',
      formatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
    );
  }

  Widget _intField(
      AppColorsExtension c, TextEditingController controller, String label) {
    return _labeledField(
      c,
      label,
      controller,
      formatters: [FilteringTextInputFormatter.digitsOnly],
    );
  }

  Widget _labeledField(
          AppColorsExtension c, String label, TextEditingController controller,
          {String? prefix, required List<TextInputFormatter> formatters}) =>
      HlNumericField(
        label: label,
        readOnly: _isClosing,
        controller: controller,
        prefix: prefix,
        inputFormatters: formatters,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildCheckbox(
    AppColorsExtension c,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Row(
        children: [
          Icon(
            value
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            color: value ? kHlAccent : c.textTertiary,
            size: 20.sp,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
