// lib/screens/hyperliquid/components/hl_adjust_margin_sheet.dart
//
// Add or remove margin on an ISOLATED Hyperliquid position
// (updateIsolatedMargin). Leverage setting, size and side stay as they
// are; only the money behind the position moves, and with it the
// liquidation price and the Investing balance.
//
// Built like the close-position ticket, piece for piece: the sheet wears
// the move's direction (money into the position green, out of it red),
// the header carries the market's logo, the title and the side and
// leverage chips, an Add / Remove pill pair under it switches the mode
// (Add by default; no Remove on a market that locks isolated margin),
// the one big figure is typed on the pinned keypad,
// $10 / $25 / $50 / Max fill it, a summary says in plain words what the
// tap does with the numbers that change, and the pinned button carries
// the wait. Success is the app's confirmation screen with a receipt; a
// refusal stays on the ticket in plain words.
//
// Money safety: the amount is approved with the same step-up grant as
// every other money action (HlIntents.isolatedMargin binds market, side,
// direction and the exact amount) and the notifier re-checks the
// position, and that the market is the position's own, before signing.
// Spending wallet only: the Ledger signer has no reviewed path for this
// action, so the position screen hides the button for a Ledger position.
//
// Adding is funded exactly as the Investing order slip funds an order
// (founder, 14 October 2026). "Available" and Max are the whole spendable
// Investments (the Investing cash plus Dollars and the Predictions cash
// a move can reach, `investmentsSpendableExcludingProvider`), never the
// Investing cash alone. More than the Investing cash is drawn, in order,
// from Dollars, then the Predictions cash straight into Investing, then
// the person's own bitcoin for X = what the whole Investments balance
// lacks (decided on the wallet at the tap, `decideSlipFunding`); when the
// bitcoin cannot cover X the button reads "Add $X to Investments" and
// opens the Investments Receive sheet. Everything is planned before ONE
// approval that binds the margin change, the Dollars move, the direct
// legs' caps and the Bitcoin leg; then the chain runs headless
// (`MarginFundingRunner`): legs, Dollars, the Investing move, and the
// change signed once the money landed, on the very position it was
// approved for. The sheet may close meanwhile; its steps (the slips'
// `SlipFundingSteps`) show while it is open.
//
// Analytics (hyperliquid_margin_adjust_*): started on open, submitted
// once approved, then exactly one completed (venue accepted) or failed,
// or abandoned when closed without submitting. Each carries `source`
// (where the sheet was opened from: [HlMarginSource]) and `action` (the
// mode at that moment); an Add also carries `funding_source` (the sources
// used, in order) and the exact amount from each. The funding itself
// reports through the slips' `order_funding_*` journey. No ids or
// addresses.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show PendingHyperliquidOrderNotifier, pendingHyperliquidOrderProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/components/deposit/deposit_quick_amounts.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show SlipFundingRoute, decideSlipFunding;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegPlan, BitcoinLegRules;
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendableExcludingProvider, venueCashRefreshProvider;
import 'package:kute/services/one_balance/margin_funding.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingEngine;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show venueCashReachExcludingProvider;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// Test seam: stands in for the one approval a funded Add asks for (the
/// Face ID), with the intent it binds.
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)? debugHlMarginApproval;

/// Where the margin sheet was opened from (the `source` analytics
/// property).
abstract final class HlMarginSource {
  /// "Add margin" beside the Liquidation row of the position screen.
  static const liquidationRow = 'liquidation_row';

  /// The liquidation-risk alert banner.
  static const alertBanner = 'alert_banner';
}

class HlAdjustMarginSheet extends ConsumerStatefulWidget {
  const HlAdjustMarginSheet({
    super.key,
    required this.position,
    required this.market,
    required this.add,
    required this.source,
  });

  final HlPerpPosition position;
  final HlMarket market;

  /// The mode the sheet opens in: true adds margin, false removes it. The
  /// pill pair at the top switches it.
  final bool add;

  /// Where it was opened from ([HlMarginSource]).
  final String source;

  static const routeName = 'hyperliquid-adjust-margin-sheet';

  /// Same route options as the close-position ticket.
  static Future<void> show(
    BuildContext context, {
    required HlPerpPosition position,
    required HlMarket market,
    required bool add,
    required String source,
  }) {
    // One margin ticket at a time.
    return OpenOnce.run(routeName, () => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: true,
      // Drag-to-dismiss bypasses PopScope, so it is off (tap outside still
      // dismisses, and is held while the change is being approved).
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      routeSettings: const RouteSettings(name: routeName),
      builder: (_) =>
          HlAdjustMarginSheet(
              position: position, market: market, add: add, source: source),
    ));
  }

  /// What can be taken out (see [hlRemovableMargin]).
  static double removableMargin(HlPerpPosition p) => hlRemovableMargin(p);

  /// The liquidation price after moving [delta] USD of margin (see
  /// [hlLiquidationAfter]).
  static double? liquidationAfter(HlPerpPosition p, double delta) =>
      hlLiquidationAfter(p, delta);

  @override
  ConsumerState<HlAdjustMarginSheet> createState() =>
      _HlAdjustMarginSheetState();
}

class _HlAdjustMarginSheetState extends ConsumerState<HlAdjustMarginSheet> {
  /// The typed amount in dollars, as the keypad writes it.
  String _amountText = '';

  /// Working out or approving the change (or signing one the Investing
  /// cash covers): the ticket holds still and cannot be dismissed.
  bool _busy = false;

  /// The "Add $X to Investments" tap is reading the wallet's bitcoin.
  bool _calculating = false;

  /// Synchronous re-entrancy guard: [_busy] only flips inside setState.
  bool _inFlight = false;
  bool _submitted = false;
  String? _errorText;
  Object? _errorCause;

  /// This ticket's funded change on its way (its record id). The chain
  /// runs whatever happens to the ticket.
  String? _runId;

  /// The X "Add $X to Investments" names, set by the build.
  double? _shownAddUsd;

  /// [_shownAddUsd] and the leg sized at the Add tap: what the tap
  /// converts, never more.
  double? _tapAddUsd;
  BitcoinLegPlan? _tapLeg;

  /// The route's own estimate for the move a shortfall needs (read once
  /// per distinct shortfall, a moment after the amount settles).
  ({double shortfallUsd, double fundUsd, double arrivingUsd})? _heldFund;
  String? _fundKey;
  Timer? _fundTimer;

  /// Holds the wallet's own Spark address (the Bitcoin leg's pinned
  /// recipient) from when "Add $X" first shows.
  ProviderSubscription<AsyncValue<String>>? _ownSparkWarm;
  bool _ownSparkWarmed = false;

  HlMarket get _market => widget.market;

  /// The mode: true adds margin, false removes it. A market that locks
  /// isolated margin (strictIsolated) only takes margin in.
  late bool _add = widget.add || widget.market.isolatedMarginLocked;
  Color get _side => sideTintForMoneyIn(_add);

  /// The position as the account reads it now (the snapshot it was
  /// opened on until the first refresh lands).
  HlPerpPosition _live(WidgetRef ref) =>
      ref
          .watch(hyperliquidPerpPositionsProvider)
          .where((p) => p.coin == widget.position.coin)
          .firstOrNull ??
      widget.position;

  Map<String, Object> _params([double? amount]) => {
        'venue': 'hyperliquid',
        'action': _add ? 'add' : 'remove',
        'source': widget.source,
        'coin': _market.coin,
        ...VenueAnalytics.hlAssetParams(_market.coin, kind: 'perp'),
        'leverage': widget.position.leverageValue,
        'wallet_kind': 'hot',
        if (amount != null) ...TrackingService.moneyParams(amountUsd: amount),
      };

  @override
  void initState() {
    super.initState();
    TrackingService.track('hyperliquid_margin_adjust_started',
        params: _params());
  }

  @override
  void dispose() {
    _fundTimer?.cancel();
    _ownSparkWarm?.close();
    if (!_submitted) {
      try {
        TrackingService.track('hyperliquid_margin_adjust_abandoned',
            params: _params(_amount));
      } catch (_) {}
    }
    super.dispose();
  }

  double? get _amount {
    final v = double.tryParse(_amountText);
    return v == null || !v.isFinite || v <= 0 ? null : v;
  }

  /// The Investing balance (perp cash on every dex plus spot USDC).
  double _cash(HyperliquidTradingState? state) => state?.availableUsdc ?? 0;

  /// Dollars on the spending account, read live. Zero when unreadable.
  double _dollars({bool watch = false}) {
    try {
      final v = watch ? ref.watch(usdBalanceProvider) : ref.read(usdBalanceProvider);
      return v.isFinite && v > 0 ? v : 0;
    } catch (_) {
      return 0;
    }
  }

  /// What the rest of Investments can bring beyond the Investing cash
  /// (Dollars plus the Predictions cash, net of pull costs): the order
  /// slip's own figure. Zero while new deposits into Investing are
  /// withheld.
  double _otherSpendable({required bool blocked}) {
    if (blocked) return 0;
    try {
      ref.watch(venueCashRefreshProvider);
    } catch (_) {}
    try {
      final v = ref
          .watch(investmentsSpendableExcludingProvider(
              OneBalanceVenue.investing))
          .maxUsd;
      return v.isFinite && v > 0 ? v : 0;
    } catch (_) {
      return _dollars(watch: true);
    }
  }

  /// Dollars plus the Predictions cash a move can reach, read through the
  /// one-balance engine; Dollars until it answers.
  double _reach(double dollarsUsd) {
    try {
      return ref
              .watch(venueCashReachExcludingProvider(OneBalanceVenue.investing))
              .valueOrNull ??
          dollarsUsd;
    } catch (_) {
      return dollarsUsd;
    }
  }

  /// `hyperliquid.deposit` withheld: nothing moves into Investing, so
  /// only the Investing cash can be added.
  String? _depositBlock() {
    try {
      return ref
          .watch(runtimeCapabilitiesProvider)
          .blockReason('hyperliquid.deposit');
    } catch (_) {
      return null;
    }
  }

  /// The move [shortfallUsd] needs: the route's estimate once read, else
  /// the near-flat route cost allowance (the controller sizes it exactly
  /// at the tap).
  ({double fundUsd, double arrivingUsd}) _fundFor(double shortfallUsd) {
    final held = _heldFund;
    if (held != null && (held.shortfallUsd - shortfallUsd).abs() < 0.005) {
      return (fundUsd: held.fundUsd, arrivingUsd: held.arrivingUsd);
    }
    return HlAdjustMarginSheetFunding.fallback(shortfallUsd);
  }

  /// Asks the route what moving [shortfallUsd] costs, once per distinct
  /// shortfall, a moment after the amount settles. Read, never moved.
  void _scheduleFundEstimate(double shortfallUsd) {
    final key = shortfallUsd.toStringAsFixed(2);
    if (_fundKey == key) return;
    _fundKey = key;
    _fundTimer?.cancel();
    if (shortfallUsd <= 0) return;
    _fundTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted || _fundKey != key) return;
      try {
        final target = OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
        final quote = await ref
            .read(hyperliquidVenueFunderProvider)
            .estimate(target)
            .timeout(const Duration(seconds: 6));
        final fund =
            HyperliquidVenueFunder.fundUsdFor(shortfallUsd: target, quote: quote);
        if (!mounted || _fundKey != key) return;
        setState(() => _heldFund = (
              shortfallUsd: shortfallUsd,
              fundUsd: fund,
              arrivingUsd: target,
            ));
      } catch (_) {}
    });
  }

  /// From the first time "Add $X" shows, holds the wallet's own Spark
  /// address so the tap finds it ready. Once per ticket.
  void _warmBitcoinLeg() {
    if (_ownSparkWarmed) return;
    _ownSparkWarmed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ownSparkWarm != null) return;
      try {
        if (pickSpendingWallet(ref.read(settingsProvider)) == null) return;
        _ownSparkWarm = ref.listenManual(sparkSelfAddressProvider, (_, next) {
          if (next.hasError) {
            _ownSparkWarm?.close();
            _ownSparkWarm = null;
          }
        });
      } catch (_) {}
    });
  }

  void _setAmount(String v) {
    if (v == _amountText) return;
    setState(() {
      _amountText = v;
      // A new figure is a new attempt.
      _errorText = null;
      _errorCause = null;
    });
  }

  /// Switches between adding and removing. The figure typed for one is
  /// not a figure for the other (Max differs), so it starts afresh.
  void _setMode(bool add) {
    if (_busy || _inFlight || _calculating || add == _add) return;
    HapticFeedback.selectionClick();
    setState(() {
      _add = add;
      _amountText = '';
      _errorText = null;
      _errorCause = null;
    });
  }

  void _fillMax(double limit) {
    if (limit <= 0) return;
    HapticFeedback.selectionClick();
    _setAmount(limit.toStringAsFixed(2));
  }

  /// The live funded change for this market, this ticket's or one started
  /// before it was reopened.
  FundedOrderRecord? _activeRun(List<FundedOrderRecord> records) {
    FundedOrderRecord? any;
    for (final r in records) {
      if (!r.stage.active ||
          r.label.kind != FundedOrderKind.margin ||
          r.label.venue != OneBalanceVenue.investing ||
          r.label.marketKey != _market.coin) {
        continue;
      }
      if (r.id == _runId) return r;
      any ??= r;
    }
    return any;
  }

  /// Another funded order or change on Investing is on its way: a second
  /// never takes its money or its approval.
  bool _fundingBusyElsewhere() {
    try {
      if (FundedOrdersNotifier.activeOf(
              ref.read(fundedOrdersProvider), OneBalanceVenue.investing) !=
          null) {
        return true;
      }
      return PendingHyperliquidOrderNotifier.isActive(
          ref.read(pendingHyperliquidOrderProvider));
    } catch (_) {
      return false;
    }
  }

  Future<void> _confirm(double limit, HlPerpPosition pos,
      {bool fromAdd = false}) async {
    final amount = _amount;
    if (_inFlight || _busy || amount == null) return;
    if (!_add && amount > limit + 1e-9) return;
    final l10n = context.l10n;
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) {
      setState(() {
        _errorCause = null;
        _errorText = l10n.depositActionWalletUnavailable;
      });
      return;
    }
    _inFlight = true;
    try {
      HapticFeedback.mediumImpact();
      final cash = _cash(ref.read(hyperliquidTradingProvider).valueOrNull);
      final shortfall = _add
          ? ShortfallRules.shortfallUsd(requiredUsd: amount, readyUsd: cash)
          : 0.0;
      if (shortfall > 0) {
        await _confirmFunded(amount, cash, pos, walletId, fromAdd: fromAdd);
      } else {
        await _confirmDirect(amount, pos, walletId);
      }
    } finally {
      _inFlight = false;
    }
  }

  /// A change the Investing cash covers (any Remove, an Add within the
  /// cash): one approval, signed here.
  Future<void> _confirmDirect(
      double amount, HlPerpPosition pos, String walletId) async {
    final l10n = context.l10n;
    final usd = _add ? amount : -amount;
    // The confirmation lives on the root navigator, past this sheet.
    final rootNav = Navigator.of(context, rootNavigator: true);
    final preview = _Figures.of(
      pos,
      cash: _cash(ref.read(hyperliquidTradingProvider).valueOrNull),
      liveMid: ref.read(hyperliquidLiveMidProvider(pos.coin)),
      delta: usd,
    );
    final params = {
      ..._params(amount),
      if (_add) ...MarginFundingPlan.investingOnlyParams(amount),
    };
    final change = HlIntents.isolatedMargin(
      walletId: walletId,
      market: _market,
      positionIsLong: pos.isLong,
      usd: usd,
    );
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: change,
      reason: l10n.hlMarginStepUp(_market.coin),
      amountUsd: amount,
    );
    if (grant == null || !mounted) return;
    _submitted = true;
    TrackingService.track('hyperliquid_margin_adjust_submitted',
        params: params);
    setState(() {
      _busy = true;
      _errorText = null;
      _errorCause = null;
    });
    try {
      await ref.read(hyperliquidTradingProvider.notifier).adjustIsolatedMargin(
            market: _market,
            position: pos,
            usd: usd,
            grant: grant,
          );
    } catch (e) {
      TrackingService.track('hyperliquid_margin_adjust_failed', params: {
        ...params,
        'error_category': e is AuthGrantException
            ? 'approval_expired'
            : TrackingService.errorCategory(e),
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorCause = e;
        // A StateError stopped before anything was signed (the position
        // changed, or the market allows no removal).
        _errorText = e is StateError
            ? l10n.ledgerErrorDetailsChanged
            : hlTradeErrorMessage(l10n, e);
      });
      return;
    }
    TrackingService.track('hyperliquid_margin_adjust_completed',
        params: params);
    if (!mounted) return;
    _showDone(rootNav, amount, pos, preview);
  }

  /// More than the Investing cash: the order slip's funding, decided here
  /// on fresh figures, then ONE approval and the headless chain.
  Future<void> _confirmFunded(
      double amount, double cash, HlPerpPosition pos, String walletId,
      {required bool fromAdd}) async {
    final l10n = context.l10n;
    // One funded order or change on Investing at a time.
    if (_activeRun(ref.read(fundedOrdersProvider)) != null ||
        _fundingBusyElsewhere()) {
      setState(() {
        _errorCause = null;
        _errorText = l10n.slipDepositIncomingNote;
      });
      return;
    }
    // Validated before any money moves: an isolated perp position, and
    // neither the change (`hyperliquid.close`, what signing it checks) nor
    // the move into Investing withheld.
    if (_market.isSpot || pos.isCross) {
      setState(() {
        _errorCause = null;
        _errorText = l10n.ledgerErrorDetailsChanged;
      });
      return;
    }
    String? block;
    try {
      final caps = ref.read(runtimeCapabilitiesProvider);
      block = caps.blockReason('hyperliquid.close') ??
          caps.blockReason('hyperliquid.deposit');
    } catch (_) {}
    if (block != null) {
      setState(() {
        _errorCause = null;
        _errorText = block;
      });
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final preview = _Figures.of(
      pos,
      cash: cash,
      liveMid: ref.read(hyperliquidLiveMidProvider(pos.coin)),
      delta: amount,
    );
    setState(() {
      _busy = true;
      _errorText = null;
      _errorCause = null;
    });
    MarginFundingDecision decision;
    try {
      decision = await decideMarginFunding(
        container.read,
        amountUsd: amount,
        readyUsd: cash,
        dollarsUsd: _dollars(),
        shownAddUsd: fromAdd ? _tapAddUsd : null,
        tapLeg: fromAdd ? _tapLeg : null,
      );
    } catch (e) {
      decision = MarginFundingUnavailable('unknown', error: e);
    }
    if (!mounted) return;
    final MarginFundingPlan plan;
    switch (decision) {
      case MarginFundingPlanned(plan: final planned):
        plan = planned;
      case MarginFundingNeedsReceive(:final addUsd):
        setState(() => _busy = false);
        await _openInvestmentsReceive(addUsd);
        return;
      case MarginFundingAddChanged():
        // The button names the new X on the next build; nothing moved.
        setState(() => _busy = false);
        return;
      case MarginFundingUnavailable(:final error):
        setState(() {
          _busy = false;
          _errorCause = error;
          _errorText = error == null
              ? l10n.errorCopyGeneric
              : hlTradeErrorMessage(l10n, error);
        });
        return;
    }

    final change = HlIntents.isolatedMargin(
      walletId: walletId,
      market: _market,
      positionIsLong: pos.isLong,
      usd: amount,
    );
    // The ONE approval: the change, the Dollars that may move into
    // Investing for it, the Predictions legs straight into Investing and
    // the Bitcoin leg. Long enough for the money to land.
    final approved = change.copyWith(
      limits: {...change.limits, ...plan.grantLimits()},
      ttl: AuthGrants.autofireTtl,
    );
    final params = {..._params(amount), ...plan.analyticsParams()};
    final reason = l10n.hlMarginStepUp(_market.coin);
    var declined = false;
    final runner = container.read(marginFundingRunnerProvider);
    final run = await runner.startApproved(
      plan: plan,
      target: MarginTarget(
        market: _market,
        position: pos,
        change: change,
        label: FundedOrderLabel(
          venue: OneBalanceVenue.investing,
          orderUsd: amount,
          side: pos.isLong ? l10n.longLabel : l10n.shortLabel,
          market: FundedOrderLabel.shortName(_market.coin),
          marketKey: _market.coin,
          kind: FundedOrderKind.margin,
        ),
      ),
      approve: () async {
        final seam = debugHlMarginApproval;
        final AuthGrant? grant;
        if (seam != null) {
          grant = await seam(approved);
        } else if (!mounted) {
          grant = null;
        } else {
          grant = await requireFreshAuthGrant(
            context,
            ref,
            intent: approved,
            reason: reason,
            amountUsd: amount,
          );
        }
        declined = grant == null;
        return grant;
      },
    );
    if (run == null) {
      if (declined) {
        TrackingService.track('order_funding_abandoned', params: {
          'venue': 'hyperliquid',
          'stage': 'approval',
          'funding_source': plan.sources.join(','),
        });
      }
      if (mounted) setState(() => _busy = false);
      return;
    }
    _submitted = true;
    TrackingService.track('hyperliquid_margin_adjust_submitted',
        params: params);
    if (mounted) {
      setState(() {
        _busy = false;
        _runId = run.id;
      });
    }
    unawaited(run.ended.then((end) {
      // Reported whatever happened to the ticket.
      final error = runner.errorOf(run.id);
      if (end == MarginFundedEnd.signed) {
        TrackingService.track('hyperliquid_margin_adjust_completed',
            params: params);
      } else {
        TrackingService.track('hyperliquid_margin_adjust_failed', params: {
          ...params,
          'funding_end': end.name,
          'error_category': error is AuthGrantException
              ? 'approval_expired'
              : TrackingService.errorCategory(error ?? end.name),
        });
      }
      if (mounted) _onRunEnded(run.id, end, error, rootNav, amount, pos, preview);
    }));
  }

  /// This ticket's funded change ended while it is open.
  void _onRunEnded(String id, MarginFundedEnd end, Object? error,
      NavigatorState rootNav, double amount, HlPerpPosition pos,
      _Figures preview) {
    if (_runId != id) return;
    final l10n = context.l10n;
    if (end == MarginFundedEnd.signed) {
      setState(() => _runId = null);
      _showDone(rootNav, amount, pos, preview);
      return;
    }
    String? message(Object? e) => e == null || e is String
        ? null
        : (e is StateError || e is AuthGrantException
            ? hlTradeErrorMessage(l10n, e)
            : HotSettlement.messageFor(e, l10n) ?? hlTradeErrorMessage(l10n, e));
    setState(() {
      _runId = null;
      _errorCause = error is String ? null : error;
      _errorText = switch (end) {
        MarginFundedEnd.signed => null,
        // The "Tap to add margin" note says it; the button is the change
        // again.
        MarginFundedEnd.ready => null,
        MarginFundedEnd.changed => l10n.ledgerErrorDetailsChanged,
        MarginFundedEnd.refunded => l10n.slipFundingBitcoinBack,
        MarginFundedEnd.maybeSent => l10n.settlementFundingUnknownBody,
        MarginFundedEnd.stopped => message(error) ?? l10n.hlFundsTimeout,
        MarginFundedEnd.notSent => message(error) ?? l10n.errorCopyGeneric,
      };
    });
  }

  void _showDone(NavigatorState rootNav, double amount, HlPerpPosition pos,
      _Figures preview) {
    final l10n = context.l10n;
    // Released first: the ticket holds itself while busy, and a held
    // ticket would refuse its own hand-off to the confirmation.
    setState(() => _busy = false);
    Navigator.of(context).pop();
    pushKuteSuccessOverlay(
      navigator: rootNav,
      overlay: KuteConfirmation(
        message: _add ? l10n.hlMarginAdded : l10n.hlMarginRemoved,
        showCloseButton: true,
        onDone: () => rootNav.pop(),
        detail: l10n.investingBalanceUpdating,
        receipt: TradeReceipt(
          leading: _artwork(),
          title: _market.coin,
          subtitle: pos.isLong ? l10n.longLabel : l10n.shortLabel,
          rows: {
            _add ? l10n.hlMarginAdd : l10n.hlMarginRemove: formatHlUsd(amount),
            if (preview.moneyAfter != null)
              l10n.hlPositionMoney: '≈ ${formatHlUsd(preview.moneyAfter!)}',
            if (preview.liqAfter != null)
              l10n.chartLiquidationPrice:
                  '≈ ${formatHlPrice(preview.liqAfter!, decimalCap: _market.pxDecimalCap)}',
            l10n.moveInvestingBalance:
                '≈ ${formatHlUsd(math.max(0, preview.cashAfter))}',
          },
        ),
      ),
    );
  }

  /// "Add $X to Investments": decided on the spending bitcoin, read fresh
  /// when the app's figures are not in yet ("Calculating…" meanwhile),
  /// the order slip's same decision. Bitcoin covers X: the tap is the
  /// change itself, funded through Investments under its one approval.
  /// It does not: the Investments Receive sheet. Nothing could be read:
  /// a message, nothing moves.
  Future<void> _openDepositDoor(HlPerpPosition pos) async {
    final shown = _shownAddUsd;
    if (_calculating || _busy || _inFlight || shown == null || shown <= 0) {
      return;
    }
    final read = ProviderScope.containerOf(context, listen: false).read;
    setState(() => _calculating = true);
    final SlipFundingRoute route;
    BitcoinLegPlan? leg;
    try {
      final decision = await decideSlipFunding(read, addUsd: shown);
      route = decision.route;
      leg = decision.plan;
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
    if (!mounted) return;
    switch (route) {
      case SlipFundingRoute.bitcoin:
        _tapAddUsd = shown;
        _tapLeg = leg;
        try {
          await _confirm(double.infinity, pos, fromAdd: true);
        } finally {
          _tapAddUsd = null;
          _tapLeg = null;
        }
      case SlipFundingRoute.insufficient:
        await _openInvestmentsReceive(shown);
      case SlipFundingRoute.unavailable:
        setState(() {
          _errorCause = null;
          _errorText = context.l10n.errorCopyGeneric;
        });
    }
  }

  /// The Investments Receive sheet for an X the bitcoin cannot cover; the
  /// ticket stays open underneath.
  Future<void> _openInvestmentsReceive(double addUsd) async {
    if (!mounted) return;
    // What the Investing cash lacks for the margin typed.
    final shortfall = ShortfallRules.shortfallUsd(
        requiredUsd: _amount ?? 0,
        readyUsd: _cash(ref.read(hyperliquidTradingProvider).valueOrNull));
    setState(() => _calculating = true);
    try {
      // `slip_top_up_opened` is sent by openSlipReceive itself.
      await openSlipReceive(context,
          venue: SlipVenue.investing,
          addUsd: addUsd,
          shortfallUsd: shortfall,
          entrySource: kMarginEntrySource);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorCause = null;
          _errorText = context.l10n.errorCopyGeneric;
        });
      }
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Widget _artwork() => HlCoinIcon(
      coin: _market.coin,
      wireCoin: _market.wireCoin,
      iconUrl: _market.iconUrl,
      category: _market.category,
      size: 36);

  @override
  Widget build(BuildContext context) {
    final c = sideTintPalette(context.colors, _side);
    final l10n = context.l10n;
    final state = ref.watch(hyperliquidTradingProvider).valueOrNull;
    final pos = _live(ref);
    final liveMid = ref.watch(hyperliquidLiveMidProvider(pos.coin));
    final amount = _amount;
    final cash = _cash(state);

    // ── What the change can draw on ─────────────────────────────────
    // Add: the whole spendable Investments, as the order slip shows it;
    // Max the largest addition its own funding check passes on it.
    // Remove: what the venue lets come out.
    final depositBlock = _add ? _depositBlock() : null;
    final dollars = _add ? _dollars(watch: true) : 0.0;
    final other =
        _add ? _otherSpendable(blocked: depositBlock != null) : 0.0;
    final available = _add
        ? slipAvailableUsd(venueUsd: cash, otherSpendableUsd: other)
        : hlRemovableMargin(pos);
    // Beyond Dollars only when there is Predictions cash to reach.
    final reach =
        other > dollars + 1e-9 ? math.min(other, _reach(dollars)) : dollars;
    final double maxUsd;
    if (!_add) {
      maxUsd = available;
    } else if (other <= 0) {
      maxUsd = ((cash * 100) + 1e-6).floorToDouble() / 100;
    } else {
      final held = _heldFund;
      maxUsd = slipMaxFundableUsd(
        upperUsd: available,
        fits: (margin) {
          final short =
              ShortfallRules.shortfallUsd(requiredUsd: margin, readyUsd: cash);
          if (short <= 0) return true;
          // The route's cost is near flat: the last estimate's cost stands
          // for any size, never under the fallback allowance.
          final heldCost = held == null
              ? 0.0
              : math.max(0.0, held.fundUsd - held.arrivingUsd);
          final fund = math.max(_fundFor(short).fundUsd,
              OrderFundingEngine.targetUsd(shortfallUsd: short) + heldCost);
          return fund * (1 + kSlipMaxMoveHeadroom) <= reach + 1e-9;
        },
      );
    }

    // ── The typed amount ────────────────────────────────────────────
    final shortfall = _add && amount != null
        ? ShortfallRules.shortfallUsd(requiredUsd: amount, readyUsd: cash)
        : 0.0;
    if (_add) _scheduleFundEstimate(shortfall);
    final fund = shortfall > 0 ? _fundFor(shortfall).fundUsd : null;
    final investmentsUsd = fund == null || dollars + 1e-9 >= fund
        ? dollars
        : math.max(dollars, _reach(dollars));
    final canFund = fund == null ||
        (depositBlock == null && investmentsUsd + 1e-9 >= fund);
    // The whole Investments balance is short of the move: "Add $X to
    // Investments", X exactly what the bitcoin would add.
    final addX = fund == null || canFund || depositBlock != null
        ? 0.0
        : BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: investmentsUsd);
    _shownAddUsd = addX > 0 ? addX : null;
    if (_shownAddUsd != null) _warmBitcoinLeg();

    // ── A funded change on its way, or stopped ──────────────────────
    final records = ref.watch(fundedOrdersProvider);
    final run = _activeRun(records);
    final runSteps = run == null
        ? null
        : [
            if (run.fromBitcoin)
              l10n.slipStepAddingToInvestments(formatHlUsd(run.addUsd)),
            l10n.slipStepPreparingOrder,
            l10n.hlMarginStepAdding(
                formatHlUsd(run.label.orderUsd), _market.coin),
          ];
    final runStep = run == null
        ? null
        : switch (run.stage) {
            FundedOrderStage.adding => 0,
            FundedOrderStage.preparing => run.fromBitcoin ? 1 : 0,
            _ => run.fromBitcoin ? 2 : 1,
          };
    final ready = run != null || _busy || !_add
        ? null
        : FundedOrdersNotifier.readyOn(records, OneBalanceVenue.investing,
            _market.coin, DateTime.now(),
            kind: FundedOrderKind.margin);
    final locked = _busy || _calculating || run != null;

    final over = amount != null && amount > available + 1e-9;
    final door = _add && _shownAddUsd != null;
    final canConfirm = !locked &&
        amount != null &&
        (_add ? canFund : !over) &&
        available > 0;
    final failed = _errorText != null;
    final figures = _Figures.of(
      pos,
      cash: cash,
      liveMid: liveMid,
      delta: (amount ?? 0) * (_add ? 1 : -1),
    );
    final price = _market.pxDecimalCap;

    String move(double from, double to, String Function(double) fmt) =>
        '${fmt(from)} → ${fmt(to)}';

    final sheet = Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: _side,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                  child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 14.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ───────────────────────────────────────
                    Row(
                      children: [
                        _artwork(),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _add
                                    ? l10n.hlMarginAddTitle(_market.coin)
                                    : l10n.hlMarginRemoveTitle(_market.coin),
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
                                  HlMetaChip(text: '${pos.leverageValue}x'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          // A funded change on its way keeps going when
                          // the ticket closes.
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          icon: Icon(Icons.close_rounded,
                              color: c.textPrimary, size: 22.sp),
                        ),
                      ],
                    ),
                    // ── Mode ─────────────────────────────────────────
                    // Add / Remove, the app's pill pair. No Remove on a
                    // market that locks isolated margin.
                    if (!_market.isolatedMarginLocked) ...[
                      SizedBox(height: 14.h),
                      KutePillTabs(
                        key: const ValueKey('hl-margin-mode'),
                        horizontalPadding: 0,
                        items: [
                          KutePillItem(label: l10n.hlMarginModeAdd),
                          KutePillItem(label: l10n.hlMarginModeRemove),
                        ],
                        selectedIndex: _add ? 0 : 1,
                        onTap: (i) {
                          if (run == null) _setMode(i == 0);
                        },
                      ),
                    ],
                    SizedBox(height: 18.h),

                    // ── Amount ───────────────────────────────────────
                    // Typed on the pinned keypad; the line under it is
                    // what the change can draw on (tap fills Max).
                    BigAmountDisplay(
                      prefix: r'$',
                      amountText: _amountText,
                      availableLabel: _add
                          ? l10n.hlMarginCanAdd(formatHlUsd(available))
                          : l10n.hlMarginCanRemove(formatHlUsd(available)),
                      availableExceeded: over,
                      onAvailableTap: locked ? null : () => _fillMax(maxUsd),
                    ),
                    SizedBox(height: 14.h),
                    AmountQuickChips(
                      enabled: !locked && maxUsd > 0,
                      chips: moveQuickAmountChips(
                        amountIsUsd: true,
                        maxLabel: l10n.max,
                        exceedsAvailable: (usd) => usd > available + 1e-9,
                        onDollars: (usd) {
                          HapticFeedback.selectionClick();
                          _setAmount(moveQuickAmountTyped(usd));
                        },
                        onPercent: (_, {chip}) => _fillMax(maxUsd),
                      ),
                    ),
                    SizedBox(height: 14.h),

                    // ── What it does ─────────────────────────────────
                    PolySlipSection(children: [
                      Text(
                        amount == null
                            ? (_add
                                ? l10n.hlMarginAddExplain
                                : l10n.hlMarginRemoveExplain)
                            : [
                                _add
                                    ? l10n.hlMarginAddSummary(
                                        formatHlUsd(amount))
                                    : l10n.hlMarginRemoveSummary(
                                        formatHlUsd(amount)),
                                if (figures.liqBefore != null &&
                                    figures.liqAfter != null)
                                  l10n.hlMarginLiqMoves(
                                      formatHlPrice(figures.liqBefore!,
                                          decimalCap: price),
                                      formatHlPrice(figures.liqAfter!,
                                          decimalCap: price)),
                                l10n.hlMarginCashMoves(
                                    formatHlUsd(figures.cashBefore),
                                    formatHlUsd(
                                        math.max(0, figures.cashAfter))),
                              ].join(' '),
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            height: 1.4),
                      ),
                      if (amount != null) ...[
                        if (figures.moneyBefore != null &&
                            figures.moneyAfter != null) ...[
                          SizedBox(height: 12.h),
                          PolySlipDetailRow(
                              label: l10n.hlPositionMoney,
                              value: move(figures.moneyBefore!,
                                  figures.moneyAfter!, formatHlUsd)),
                        ],
                        if (figures.liqBefore != null &&
                            figures.liqAfter != null) ...[
                          SizedBox(height: 8.h),
                          PolySlipDetailRow(
                              label: l10n.chartLiquidationPrice,
                              value: move(
                                  figures.liqBefore!,
                                  figures.liqAfter!,
                                  (v) => formatHlPrice(v,
                                      decimalCap: price))),
                        ],
                        SizedBox(height: 8.h),
                        PolySlipDetailRow(
                            label: l10n.moveInvestingBalance,
                            value: move(figures.cashBefore,
                                math.max(0, figures.cashAfter), formatHlUsd)),
                        if (figures.leverageAfter != null) ...[
                          SizedBox(height: 8.h),
                          PolySlipDetailRow(
                              label: l10n.hlMarginLeverageAfter,
                              value:
                                  '${figures.leverageAfter!.toStringAsFixed(1)}x'),
                        ],
                      ],
                    ]),
                    if (over && !_add) ...[
                      SizedBox(height: 10.h),
                      Text(l10n.hlMarginTooMuch,
                          style: TextStyle(color: c.error, fontSize: 13.sp)),
                    ],
                    if (_errorText != null) ...[
                      SizedBox(height: 10.h),
                      HlTradeErrorNotice(
                          message: _errorText!, error: _errorCause),
                    ],
                  ],
                ),
              )),

              // ── Keypad, pinned ─────────────────────────────────────
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: AmountKeypad(
                  value: _amountText,
                  maxDecimals: 2,
                  enabled: !locked,
                  onChanged: _setAmount,
                ),
              ),

              // ── CTA, pinned ────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w,
                    math.max(16.h, MediaQuery.of(context).padding.bottom)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_add &&
                        depositBlock != null &&
                        amount != null &&
                        shortfall > 0)
                      CapabilityBlockNote(depositBlock),
                    if (ready != null)
                      SlipFundingReadyNote(
                        amount: formatHlUsd(ready.addUsd),
                        text: l10n.hlMarginFundingReady(
                            formatHlUsd(ready.addUsd)),
                      ),
                    if (runSteps != null && runStep != null)
                      // The funded change's own step, busy, on the one
                      // button.
                      PolySlipCta(
                        label: runSteps[runStep],
                        onTap: () {},
                        enabled: false,
                        isBusy: true,
                        busyLabel: runSteps[runStep],
                        color: _side,
                      )
                    else if (door)
                      // The whole Investments balance cannot fund it: the
                      // door, never wearing the change's direction.
                      PolySlipCta(
                        label: l10n.slipAddToInvestments(
                            formatHlUsd(_shownAddUsd!)),
                        onTap: () => _openDepositDoor(pos),
                        enabled: !locked,
                        isBusy: _calculating || _busy,
                        busyLabel: _calculating
                            ? l10n.feeUiCalculating
                            : l10n.loading,
                        color: _side,
                        neutral: true,
                      )
                    else
                      PolySlipCta(
                        label: failed
                            ? l10n.retry
                            : (_add ? l10n.hlMarginAdd : l10n.hlMarginRemove),
                        onTap: () => _confirm(available, pos),
                        enabled: canConfirm,
                        isBusy: _busy || _calculating,
                        busyLabel: _calculating
                            ? l10n.feeUiCalculating
                            : l10n.loading,
                        color: _side,
                      ),
                    if (runSteps != null && runStep != null)
                      SlipFundingSteps(
                        steps: runSteps,
                        active: runStep,
                        slow: run!.slow,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // A change being approved cannot be dismissed out from under itself;
    // a funded one on its way runs on whether the ticket is open or not.
    return PopScope(
        canPop: !_busy,
        child: SideTintedSubtree(side: _side, child: sheet));
  }
}

/// The figures a margin change moves, before and after moving [delta]
/// dollars (positive = added). Estimates of what the venue will report:
/// the receipt and the summary mark them as such.
class _Figures {
  const _Figures({
    required this.moneyBefore,
    required this.moneyAfter,
    required this.liqBefore,
    required this.liqAfter,
    required this.cashBefore,
    required this.cashAfter,
    required this.leverageAfter,
  });

  final double? moneyBefore, moneyAfter, liqBefore, liqAfter, leverageAfter;
  final double cashBefore, cashAfter;

  factory _Figures.of(HlPerpPosition p,
      {required double cash, required double? liveMid, required double delta}) {
    final money = hlPositionMoney(p, liveMid: liveMid);
    final liq = p.liquidationPx;
    final marginAfter = p.marginUsed + delta;
    return _Figures(
      moneyBefore: money,
      moneyAfter: money == null ? null : money + delta,
      liqBefore: liq != null && liq.isFinite && liq > 0 ? liq : null,
      liqAfter: hlLiquidationAfter(p, delta),
      cashBefore: cash,
      cashAfter: cash - delta,
      leverageAfter:
          marginAfter > 0 ? p.positionValue.abs() / marginAfter : null,
    );
  }
}

/// The sheet's funding figures, for tests.
abstract final class HlAdjustMarginSheetFunding {
  /// The move a shortfall of [shortfallUsd] needs before the route's own
  /// estimate is in: the engine's target grossed up by the route's
  /// fallback share plus its near-flat cost allowance, to the cent. The
  /// tap sizes it exactly ([sizeMarginFunding]).
  static ({double fundUsd, double arrivingUsd}) fallback(
      double shortfallUsd) {
    final target = OrderFundingEngine.targetUsd(shortfallUsd: shortfallUsd);
    if (target <= 0) return (fundUsd: 0, arrivingUsd: 0);
    final fund = target / (1 - ShortfallRules.fallbackRouteFee) +
        kHlMarginFundingFlatUsd;
    return (
      fundUsd: ((fund * 100) - 1e-9).ceilToDouble() / 100,
      arrivingUsd: target,
    );
  }
}

/// A flat allowance for the Dollars → Investing route's cost, used only for
/// the margin sheet's figures before the route's estimate is in.
const double kHlMarginFundingFlatUsd = 1.25;
