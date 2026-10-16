import 'package:kute/screens/shared/side_tint_palette.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/orchestra_fee_summary.dart';
// lib/screens/home/components/deposit_sheet.dart
// (formerly move_sheet.dart: the move_* PostHog events keep their names.)
//
// Full-screen deposit amount entry (Phantom Buy-style) opened from every
// deposit/withdraw door: X-close + operation title, the route row, one
// big typed number driven by a custom keypad, $10 / $25 / $50 / Max
// chips, and the CTA. Every door opens it locked to one venue or rail
// ([MoveLockedSide]): Add to Predictions / Investing, the two withdrawals,
// the Dollar deposit, Buy bitcoin (Cash App, the bank rail, the dollar
// balance), the Ledger venue flows and the slip top-ups. It never moves
// bitcoin between the spending account and a savings wallet. Internally
// the typed amount maps onto the historical 0..1 `_ratio` of the
// max-convertible balance, so the dispatch matrix below is untouched.
//
// The Dollar deposit door (the Investments dock's Deposit) is also the
// home of Receive: its From picker leads with a Receive row that closes
// the sheet and opens the Dollars receive screen (an address for
// whatever coin is being sent, dollars land), over the ways to pay
// (Bitcoin, Cash App while the policy offers it).
//
// Routing under the hood:
//   - BTC → USDC: Spark sends sats; Orchestra (Flashnet) delivers
//     **native** USDC on Polygon directly into the user's Safe.
//   - USDC → BTC: Safe sends **native** USDC to Orchestra's deposit
//     address; Orchestra credits the user's Spark wallet.
//
// We deliberately route the convert flow through native USDC (not
// USDC.e). USDC.e remains the wire format only for the Polymarket
// deposit/bet path, where pUSD wraps USDC.e specifically.

import 'dart:async';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/home/components/deposit/deposit_flow_outcome.dart';
import 'package:kute/screens/home/components/deposit/deposit_route_card.dart';
import 'package:kute/screens/home/components/deposit/deposit_quick_amounts.dart';
import 'package:kute/screens/home/components/deposit/deposit_summary_card.dart';

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:flutter/services.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'dart:math' as math;

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/constants/feature_flags.dart'
    show
        kLedgerCashAppAddressCheckEnabled,
        kLedgerInvestingEnabled,
        kLedgerPolymarketWithdrawEnabled;
import 'package:kute/screens/ledger/funding/ledger_deposit_source_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_fund_investing_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_fund_predictions_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_withdraw_investing_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_withdraw_predictions_sheet.dart';
import 'package:kute/screens/ledger/funding/ledger_polymarket_funding_explainer_sheet.dart';
import 'package:kute/services/funding/ledger_polymarket_funding_service.dart'
    show LedgerPmFundingDirection;
import 'package:kute/services/funding/ledger_hypercore_funding_service.dart'
    show kHypercoreUsdcDecimals;
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart'
    show PolymarketAccountKind;
import 'package:kute/screens/ledger/ledger_verify_address_sheet.dart';
import 'package:kute/services/hardware/ledger/ledger_verified_address_store.dart';
import 'package:kute/helpers/cash_app_purchase_session.dart';
import 'package:kute/helpers/cash_app_destination.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_move_max_provider.dart';
import 'package:kute/services/funding/ledger_cash_app_recipient.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/providers/cash_app_payment_window_provider.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraOnrampResponse;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/orchestra_routes.dart'
    show
        cashAppExchangeStatus,
        kOrchestraUsdAssetCode,
        kOrchestraUsdChain,
        orchestraExchangeStatusIsTerminal,
        reportDiscoveredOrchestraOrder;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/polymarket_usdc_cache_service.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdSdkBalanceProvider, usdDrainBaseUnits;
import 'package:kute/providers/asset_icon_provider.dart'
    show kInvestmentsIcon, kUsdMarkAsset;
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/screens/home/components/move_sent_overlay.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show RouteKey, kMoneyCatalogMaxAge;
import 'package:kute/providers/orchestra_supported_routes_provider.dart'
    show orchestraSupportedRoutesProvider;
import 'package:kute/services/investment_provider_availability.dart'
    show InvestmentProviderAvailability;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashDestination,
        VenueCashFor,
        VenueCashPlan,
        VenueCashPullOutcome,
        venueCashPullerProvider;
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendableProvider, venueCashRefreshProvider;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegSent, BitcoinToDollarsLeg;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show
        MultiSourceMove,
        MultiSourceMoveStore,
        multiSourceMovesProvider,
        trackMultiSourceMoveRetry;
import 'package:kute/screens/shared/venue_cash_pull_copy.dart';
import 'package:kute/screens/shared/move_steps_view.dart'
    show MoveStepsSection;
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show
        ledgerInvestmentAllowed,
        ledgerVenueEntryCapability,
        showLedgerInvestmentUnavailable;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration, withSettlementOrderId;
import 'package:kute/services/orchestra/arrival_target.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementFundingProof,
        SettlementQuoteResult,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show CctpUnavailable, hypercoreCctpWithdrawalProvider;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart'
    show HyperCoreMoveRail;
import 'package:kute/services/orchestra/cash_app_onramp_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/orchestra/move_rate_sample.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedback, moneyFailureFeedbackAfterBand;
import 'package:kute/screens/shared/rubber_band_progress.dart'
    show RubberBand, RubberBandBusy, RubberBandOutcome;
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart' show MoveSteps;
import 'package:kute/services/one_balance/money_steps.dart' show MoneyStepStatus;
import 'package:kute/services/one_balance/buy_bitcoin_fanout.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart'
    show approvedPurchaseStepUp, buyBitcoinFromDollars, kDollarsToBtcRoute;
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show bitcoinPurchaseFinisherProvider, PendingBitcoinPurchaseStore;
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Cash App brand green (their published mark color).
const Color _kCashAppGreen = Color(0xFF00D632);

// Technical guards, not business settings: the smallest amounts the
// Orchestra routes will quote (the live route limits and the quote itself
// stay authoritative). Kute's fees always come from the backend quote.
const int _kMinSats = 1000; // Orchestra minimum for BTC→USD leg
const double _kMinUsdc = 1.0; // Minimum USD for USD→BTC leg

/// Fiat currencies the BANK rail offers. EUR only for now: the bank
/// onramp is Europe-only (user decision, September 2026). USD and CHF
/// keep their symbol / flag plumbing (`_fiatSymbol` / `_fiatFlag`) so
/// they return by adding them back here; with a single entry the
/// currency pill is locked and the picker never opens. The Cash App
/// source is USD-locked on its own (the Flashnet onramp is
/// USD-denominated) and never reads this list.
const List<String> _kBankFiatCurrencies = ['EUR'];

/// The door the sheet opened on. Every entry is locked to one: venue
/// deposits pin the destination and let users choose Bitcoin, Cash App,
/// or the upcoming bank rail; withdrawals pin the venue source.
enum MoveLockedSide {
  depositToPredictions,
  withdrawFromPredictions,
  depositToHyperliquid,
  withdrawFromHyperliquid,

  /// The Dollar deposit door: the To side is pinned to the spending
  /// account's dollar balance and the From side stays pickable, exactly
  /// like the venue deposits above. Routes spending Bitcoin through
  /// Orchestra to the dollar asset. It is the ONE way dollars are
  /// funded, so it wears one label (`dollarDeposit`) and the shared
  /// dollar mark wherever it appears — bitcoin paying for dollars is
  /// this door with Bitcoin picked as the source, not a door of its
  /// own. Nothing user-facing names the token or its chain.
  depositToUsd,

  /// Fiat (bank account) legs. Direction semantics: deposit = FIAT IS
  /// THE SOURCE (bank → Bitcoin), so the From side is pinned to
  /// 'Bank account · Bank transfer'; withdraw = fiat is the DESTINATION
  /// (Bitcoin → bank), pinning the To side. Fiat rails are not live:
  /// both states render the same coming-soon amount screen — the keypad
  /// works, the CTA never enables, nothing dispatches.
  depositFromFiat,
  withdrawToFiat,

  /// Buy-to-pool: the "Buy" money door on the Predictions / Trading
  /// screens. Opens the SAME "Buy bitcoin" fiat state as
  /// [depositFromFiat] (From pinned to 'Bank account · Bank transfer',
  /// `_sourceFiat`, typed fiat amount) but with the To chip PRESET to
  /// the pool (Predictions / Trading). Inert like every fiat leg —
  /// bank transfers are coming soon. Title stays 'Buy bitcoin'.
  buyToPredictions,
  buyToHyperliquid,
}

/// The door the SPENDING wallet's Move sheet opens for [side] (one
/// balance, October 2026). The spending wallet has no venue doors:
/// money reaches Investing and Predictions through an order funded from
/// Dollars alone, and comes back through the sweeper. So a venue deposit
/// or buy asked for on it opens the Dollars deposit door instead (the
/// same ways in — bitcoin, Cash App while offered, other coins — and no
/// venue as a source or destination anywhere in it or its pickers), and
/// a venue withdrawal opens nothing (null): there is no such door. A
/// Ledger ([ledger]) keeps every one of its doors, which are its own
/// accounts'.
MoveLockedSide? spendingWalletLockedSide(MoveLockedSide side,
    {required bool ledger}) {
  if (ledger) return side;
  switch (side) {
    case MoveLockedSide.depositToPredictions:
    case MoveLockedSide.depositToHyperliquid:
    case MoveLockedSide.buyToPredictions:
    case MoveLockedSide.buyToHyperliquid:
      return MoveLockedSide.depositToUsd;
    case MoveLockedSide.withdrawFromPredictions:
    case MoveLockedSide.withdrawFromHyperliquid:
      return null;
    case MoveLockedSide.depositToUsd:
    case MoveLockedSide.depositFromFiat:
    case MoveLockedSide.withdrawToFiat:
      return side;
  }
}

/// Where Continue goes in a Ledger-context Move sheet.
enum LedgerMoveRoute {
  /// The Ledger's own flow: BTC → venue deposit or venue → BTC withdraw,
  /// each confirmed on the device.
  deviceFlow,

  /// Cash App pays; the onramp delivers to the Ledger's verified venue
  /// account. Nothing is signed and no Bitcoin leaves the device.
  cashAppOnramp,

  /// Anything else: the sheet shows "details changed" and dispatches
  /// nothing.
  blocked,
}

/// Pure routing rule for a Ledger Move sheet ([ledgerWalletId] set).
/// [identityVerifiedAndUnchanged]: the Ledger's EVM identity was verified
/// when the sheet opened and still is the same one. A caller-supplied
/// venue wallet ([hasVenueWallet]) is a different sheet shape and never
/// mixes with a Ledger move.
@visibleForTesting
LedgerMoveRoute ledgerMoveRoute({
  required bool featureEnabled,
  required bool hasVenueWallet,
  required bool identityVerifiedAndUnchanged,
  required String ledgerWalletId,
  required MoveLockedSide lockedSide,
  required bool fromBtc,
  required bool fromHyperliquid,
  required bool sourceCashApp,
  required bool sourceFiat,
  required String? sourceWalletId,
  required String? destWalletId,
  required bool destPredictions,
  required bool destHyperliquid,
  required bool destFiat,
}) {
  if (!featureEnabled || hasVenueWallet || !identityVerifiedAndUnchanged) {
    return LedgerMoveRoute.blocked;
  }
  switch (lockedSide) {
    case MoveLockedSide.depositToPredictions:
    case MoveLockedSide.depositToHyperliquid:
      return fromBtc &&
              !sourceCashApp &&
              !sourceFiat &&
              sourceWalletId == ledgerWalletId &&
              destWalletId == null
          ? LedgerMoveRoute.deviceFlow
          : LedgerMoveRoute.blocked;
    case MoveLockedSide.withdrawFromPredictions:
    case MoveLockedSide.withdrawFromHyperliquid:
      return !fromBtc &&
              !sourceCashApp &&
              !sourceFiat &&
              destWalletId == ledgerWalletId &&
              sourceWalletId == null
          ? LedgerMoveRoute.deviceFlow
          : LedgerMoveRoute.blocked;
    case MoveLockedSide.buyToPredictions:
    case MoveLockedSide.buyToHyperliquid:
      final predictions = lockedSide == MoveLockedSide.buyToPredictions;
      return sourceCashApp &&
              !sourceFiat &&
              !fromBtc &&
              !fromHyperliquid &&
              sourceWalletId == null &&
              destWalletId == null &&
              !destFiat &&
              destPredictions == predictions &&
              destHyperliquid == !predictions
          ? LedgerMoveRoute.cashAppOnramp
          : LedgerMoveRoute.blocked;
    default:
      return LedgerMoveRoute.blocked;
  }
}

/// The payment rail a Move sheet opens on, once the door has seeded its
/// source. [none] means the door opened on a balance or a wallet;
/// [natural] means it seeded a rail that is not on offer, so it opens on
/// its own non-fiat source instead (see [_DepositSheetState]'s
/// `_openOnNaturalSource`).
enum MoveOpeningRail { none, bank, cashApp, natural }

/// Pure opening rule for the payment rails (see [DepositSheet] initState).
///
/// [seededRail]: the door's own seeding put a payment rail on the From
/// side (the buy doors, "Deposit more", the unlocked fiat entry).
/// [cashAppDefault]: this door opens on Cash App when it can (the locked
/// buy doors and an explicit Cash App request). [cashAppOverBitcoin]: an
/// explicit Cash App request on a door that opens on Bitcoin (the
/// dollars door). [cashAppVisible] / [bankVisible]: the runtime policy
/// offers that onramp ([onrampVisible]).
///
/// AN ONRAMP THE POLICY DOES NOT OFFER IS NEVER SHOWN, SO NEVER OPENED ON
/// (founder decision, October 2026). A Cash App door opens on Cash App
/// while it is offered; otherwise on the bank when the door seeded it and
/// the policy offers it; otherwise on the door's natural non-fiat source:
/// Buy bitcoin on the dollar balance, the venue buys on spending bitcoin,
/// and the dollars door simply stays on its Bitcoin source.
@visibleForTesting
MoveOpeningRail moveOpeningRail({
  required bool seededRail,
  required bool cashAppDefault,
  required bool cashAppOverBitcoin,
  required bool cashAppVisible,
  required bool bankVisible,
}) {
  if (!seededRail && !cashAppOverBitcoin) return MoveOpeningRail.none;
  if (cashAppDefault && cashAppVisible) return MoveOpeningRail.cashApp;
  if (!seededRail) return MoveOpeningRail.none;
  if (bankVisible) return MoveOpeningRail.bank;
  if (cashAppVisible) return MoveOpeningRail.cashApp;
  return MoveOpeningRail.natural;
}

Future<void> showDepositSheet(
  BuildContext context, {
  /// The door this sheet opens on (see [MoveLockedSide]).
  required MoveLockedSide lockedSide,

  /// Pre-selects the source: `'usd'` opens a venue deposit on the dollar
  /// balance (a slip top-up the dollars cover on their own).
  String? initialSourceAsset,

  /// Wallet a fiat deposit would credit when opened with
  /// [MoveLockedSide.depositFromFiat] (the Add Funds sheet resolves the
  /// spending wallet and threads it here). Display-only while fiat
  /// rails are coming soon — it drives the To chip label.
  String? fiatDepositWalletId,

  /// Ledger account receiving a fiat venue deposit. Never uses a hot signer.
  String? venueWalletId,

  /// Pins both the Bitcoin wallet and venue account to this Ledger. This
  /// context only supports the four venue deposit/withdraw directions.
  String? ledgerWalletId,

  /// Prefill: seed the typed amount with this USD target on the
  /// destination side (e.g. the exact bet that was short on balance).
  /// Clamped to the source balance once the rate loads.
  double? initialTargetUsd,

  /// Opens with Cash App selected; the destination is preserved.
  bool cashAppSource = false,

  /// Runs once when a move from this sheet went through (submitted, or a
  /// Cash App purchase paid), after the sheet closed. A slip that opened
  /// the sheet to top up uses it to know the person is back on it.
  VoidCallback? onCompleted,
}) async {
  // New money into a Ledger's own Predictions or Investing account answers
  // to Ledger Predictions / Ledger Investing first, whichever door opened
  // the move (the Ledger account dock, a Ledger slip's deposit door, a
  // Cash App "buy again"). Withdrawals are exits and pass.
  final ledgerGate = ledgerVenueEntryCapability(
    ledgerWalletId: ledgerWalletId ?? venueWalletId,
    toPredictions: lockedSide == MoveLockedSide.depositToPredictions ||
        lockedSide == MoveLockedSide.buyToPredictions,
    toInvesting: lockedSide == MoveLockedSide.depositToHyperliquid ||
        lockedSide == MoveLockedSide.buyToHyperliquid,
  );
  if (ledgerGate != null && !ledgerInvestmentAllowed(ledgerGate)) {
    await showLedgerInvestmentUnavailable(context, ledgerGate);
    return;
  }
  if (!context.mounted) return;
  // The spending wallet has no venue doors (see [spendingWalletLockedSide]).
  final side = spendingWalletLockedSide(lockedSide,
      ledger: (ledgerWalletId ?? venueWalletId) != null);
  if (side == null) return;
  // Full-screen amount entry pushed on the ROOT navigator so it floats
  // above the persistent shell nav bar — same rule the modal sheets
  // followed. Not awaited, matching the fire-and-forget contract the
  // bottom-sheet version had.
  // ignore: discarded_futures
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DepositSheet(
        initialSourceAsset: initialSourceAsset,
        lockedSide: side,
        fiatDepositWalletId: fiatDepositWalletId,
        venueWalletId: venueWalletId,
        ledgerWalletId: ledgerWalletId,
        initialTargetUsd: initialTargetUsd,
        cashAppSource: cashAppSource,
        onCompleted: onCompleted,
      ),
    ),
  );
}

/// A sheet opened from inside the tinted Move subtree must NOT inherit
/// that palette: its translucent ink tiers are meant for cards sitting on
/// the side colour, so a picker painting its own fill with `c.surface`
/// comes out see-through. Resolve the app's real palette from above the
/// tint and hand it back to the sheet.
/// The app's real palette, captured by [_DepositSheetState.build] ABOVE the
/// tint. Read it rather than another element's context: looking an
/// inherited widget up through a foreign context registers that element
/// as a dependent and outlives the widget that asked.
AppColorsExtension? _moveBaseColors;

AppColorsExtension _untintedColors(BuildContext context) =>
    _moveBaseColors ?? context.colors;

Widget _untinted(BuildContext context, Widget child) {
  final base = _moveBaseColors;
  if (base == null) return child;
  final theme = Theme.of(context);
  return Theme(
    data: theme.copyWith(
      extensions: [
        ...theme.extensions.values.where((e) => e is! AppColorsExtension),
        base,
      ],
    ),
    child: child,
  );
}

/// Test seam: stands in for the one approval a purchase of bitcoin asks
/// before venue cash moves for it. Receives the purchase intent (with its
/// leg caps) and answers with a grant for it, or null (declined).
@visibleForTesting
Future<AuthGrant?> Function(SensitiveIntent intent)? debugBuyBitcoinApproval;

/// Test seam: stands in for the Bitcoin → Dollars leg the plain Dollars
/// door sends ([BitcoinToDollarsLeg.send]), answering once the bitcoin
/// left. [onSending] runs right before the payment, as the leg's own does.
@visibleForTesting
Future<BitcoinLegSent> Function(
    {required double approxUsd,
    required void Function() onSending})? debugBitcoinToDollarsSend;

class DepositSheet extends ConsumerStatefulWidget {
  final String? initialSourceAsset;
  final MoveLockedSide lockedSide;
  final String? fiatDepositWalletId;
  final String? venueWalletId;
  final String? ledgerWalletId;

  /// Prefill: seed the typed amount with this USD outcome on the
  /// destination side (e.g. the bet amount that was short). Applied once
  /// the rate loads; clamped to the source balance.
  final double? initialTargetUsd;

  /// Pre-locks the buy SOURCE to Cash App (see [showDepositSheet]).
  final bool cashAppSource;

  /// See [showDepositSheet].
  final VoidCallback? onCompleted;

  const DepositSheet({
    super.key,
    this.initialSourceAsset,
    required this.lockedSide,
    this.fiatDepositWalletId,
    this.venueWalletId,
    this.ledgerWalletId,
    this.initialTargetUsd,
    this.cashAppSource = false,
    this.onCompleted,
  });

  @override
  ConsumerState<DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends ConsumerState<DepositSheet> {
  bool get _isLedgerMove => widget.ledgerWalletId != null;
  LedgerIdentity? _ledgerIdentityAtOpen;
  LedgerMoveMax? _ledgerMaximumAtReview;

  /// Which Ledger flow this sheet may run right now (see [ledgerMoveRoute]).
  LedgerMoveRoute get _ledgerRoute => !_isLedgerMove
      ? LedgerMoveRoute.blocked
      : ledgerMoveRoute(
          featureEnabled: kLedgerInvestingEnabled,
          hasVenueWallet: widget.venueWalletId != null,
          identityVerifiedAndUnchanged:
              _ledgerIdentityAtOpen?.hasVerifiedEvm == true &&
                  ref.read(ledgerIdentityProvider(widget.ledgerWalletId!)) ==
                      _ledgerIdentityAtOpen,
          ledgerWalletId: widget.ledgerWalletId!,
          lockedSide: _lockedSide,
          fromBtc: _fromBtc,
          fromHyperliquid: _fromHyperliquid,
          sourceCashApp: _sourceCashApp,
          sourceFiat: _sourceFiat,
          sourceWalletId: _sourceWalletId,
          destWalletId: _destWalletId,
          destPredictions: _destPredictions,
          destHyperliquid: _destHyperliquid,
          destFiat: _destFiat,
        );

  /// The BTC-source (deposit) / venue-source (withdraw) device flow.
  bool get _ledgerContextValid => _ledgerRoute == LedgerMoveRoute.deviceFlow;

  /// A Ledger venue deposit whose funding source was switched to Cash App
  /// ([_switchToFiatVenueSource]). The onramp delivers straight to this
  /// Ledger's venue account (the Ledger-verified EVM identity pinned at
  /// open), so no hot signer and no Bitcoin leave the device. Every other
  /// Ledger move keeps the BTC-source checks in [_ledgerContextValid].
  bool get _ledgerCashAppSourceValid =>
      _ledgerRoute == LedgerMoveRoute.cashAppOnramp;

  /// Either Ledger shape this sheet can run: the BTC-source device flow
  /// or a Cash App deposit into the Ledger's venue account.
  bool get _ledgerMoveValid =>
      _ledgerContextValid || _ledgerCashAppSourceValid;

  /// The Ledger whose venue account a Cash App onramp funds: the caller's
  /// venue wallet, or this Ledger move after a switch to Cash App.
  String? get _cashAppLedgerVenueWalletId =>
      widget.venueWalletId ??
      (_ledgerCashAppSourceValid ? widget.ledgerWalletId : null);

  void _pinLedgerEndpoints() {
    _sourceWalletId = _fromBtc ? widget.ledgerWalletId : null;
    _destWalletId = _fromBtc ? null : widget.ledgerWalletId;
    _sourceFiat = false;
    _sourceCashApp = false;
    _destFiat = false;
    _destAsset = 'btc';
  }

  /// Selected fraction of the max-convertible balance (0..1). The
  /// historical slider position — every dispatch getter still derives
  /// from it, but it's now DRIVEN by [_typedAmount] via
  /// [_syncRatioFromTyped] instead of a slider.
  double _ratio = 0;

  /// "Send everything" was asked for: the 100% chip or a tap on the
  /// available balance, and nothing typed since. Only this arms a drain
  /// (the rail's own send-all, fee out of the balance). A typed amount,
  /// however close to the balance, is that amount with the fee on top:
  /// inferring the drain from a ratio of 0.99 turned a typed 99% into
  /// "move the whole wallet", and the review showed the typed figure.
  bool _drainArmed = false;

  /// The raw keypad-typed amount for the non-fiat flows ('' == 0).
  /// USD-denominated when the flow touches a USD pool
  /// (Predictions / Trading), sats-or-BTC (per the user's btcFormat)
  /// for wallet-to-wallet BTC moves. The fiat flows keep their own
  /// [_typedFiatAmountController].
  String _typedAmount = '';
  bool _loadingRate = true;
  int _rateRequest = 0;
  bool _processing = false;

  /// The confirm's rubber band: the last phase the move reached (0..1,
  /// null for time alone) and how it ended ([RubberBandBusy]).
  double? _bandProgress;
  RubberBandOutcome? _bandOutcome;
  bool _fromBtc = true; // source-side asset: always BTC under always-BTC
  /// Destination-side asset. Always-BTC architecture: only BTC moves
  /// between wallets. USDC is no longer a user-pickable destination.
  String _destAsset = 'btc'; // 'btc' only
  /// Predictions destination intent — `true` when the user picked
  /// Predictions as the To-side. Routes BTC → USDC.e via Orchestra
  /// (same path as the deposit flow in `polymarket_screen`) and
  /// fires a `wrapIncomingUsdcEToPusd()` post-hook so the proceeds
  /// rest as pUSD per task #170.
  bool _destPredictions = false;

  /// Investing deposits deliver USDC directly to the user's HyperCore account.
  bool _destHyperliquid = false;

  /// Dollars destination — the spending account's dollar balance. Set by
  /// the [MoveLockedSide.depositToUsd] door (routing spending Bitcoin
  /// through Orchestra to the dollar asset on the same Spark wallet, see
  /// [_dispatchBtcToUsd]) and by the To-side picker on the two venue
  /// withdrawals, where dollars are the alternative to bitcoin for what
  /// the cash-out delivers. The unlocked Exchange never offers it.
  ///
  /// It says only WHERE the money lands. Everything that meant "the buy
  /// dollars door" reads [_buyingDollars] instead, because on a
  /// withdrawal the pinned side is the source and the door is still a
  /// withdrawal.
  bool _destUsd = false;

  /// The two venue cash-outs. Their lock pins the SOURCE, so unlike every
  /// other locked door the destination is a real choice: the spending
  /// account's bitcoin (the default) or its dollars.
  bool get _isVenueWithdraw =>
      _lockedSide == MoveLockedSide.withdrawFromPredictions ||
      _lockedSide == MoveLockedSide.withdrawFromHyperliquid;

  /// The "Buy dollars" door: dollars are the destination AND the move is
  /// a purchase rather than a cash-out. Titles, verbs, the rate sample
  /// and the fiat-destination rules all mean this, never the bare flag.
  bool get _buyingDollars => _destUsd && !_isVenueWithdraw;

  /// Native HyperCore USDC is the source for Investing withdrawals.
  bool _fromHyperliquid = false;

  /// Dollars as the SOURCE — the spending account's own dollar balance
  /// paying a venue deposit. Only the two venue-deposit doors offer it
  /// (see [_dollarsSourceAllowed]); every other source pick clears it,
  /// so a stale flag can never send dollars down a bitcoin path.
  ///
  /// It rides with `_fromBtc == false`, which the rest of the sheet reads
  /// as "the amount is USD-denominated". That is exactly right for
  /// dollars, but `!_fromBtc` alone has always meant "the Predictions
  /// balance", so every branch that assumed so now tests this flag too.
  bool _sourceUsd = false;

  /// The doors where the dollar balance may pay: the two venue deposits
  /// and the buy-bitcoin door. In every one of them the money leaves as
  /// the dollar token and Orchestra converts it on the way in, the same
  /// shape as the bitcoin leg beside it.
  ///
  /// [MoveLockedSide.depositFromFiat] is the "Buy bitcoin" door. Dollars
  /// there buy spending bitcoin on a real catalogue route (the dollar
  /// token and bitcoin are both Spark-native), so the purchase settles
  /// instantly instead of waiting on a fiat rail.
  ///
  /// Read live off `_lockedSide`, which the swap button mutates: flipping
  /// the buy door into its sell twin ([MoveLockedSide.withdrawToFiat])
  /// drops this, and with it `_dollarsAreSource`.
  /// The buy door credits a NAMED wallet when it is opened from a cold
  /// account, and the dollar balance is the spending account's money.
  /// Paying for a hardware wallet's bitcoin out of it crosses two
  /// accounts in one tap, so a purchase into cold storage offers the
  /// payment rails only: Cash App and the bank (owner decision).
  bool get _dollarsSourceAllowed =>
      !_isLedgerMove &&
      (_lockedSide == MoveLockedSide.depositToHyperliquid ||
          _lockedSide == MoveLockedSide.depositToPredictions ||
          (_lockedSide == MoveLockedSide.depositFromFiat &&
              widget.fiatDepositWalletId == null));

  /// THE ONE TEST every dollar-source branch uses. [_sourceUsd] is the
  /// user's pick; this is the pick AND the absence of every other source,
  /// re-derived on each read. That means any handler that installs
  /// another source — bitcoin, a savings wallet, a venue, a fiat rail —
  /// or any flip off these doors turns the dollar source off by
  /// construction, with no bookkeeping to forget.
  bool get _dollarsAreSource =>
      _sourceUsd &&
      _dollarsSourceAllowed &&
      !_fromBtc &&
      !_fromHyperliquid &&
      !_sourceFiat &&
      !_sourceCashApp &&
      _sourceWalletId == null;

  /// The dollar balance, in dollars.
  double get _availableUsd => ref.read(usdBalanceProvider);

  /// Dollars buying spending bitcoin also reach venue cash: Dollars
  /// first, the rest pulled home from Predictions and Investing before
  /// the purchase (lib/services/one_balance/venue_cash_source.dart).
  bool get _dollarsReachVenueCash =>
      _dollarsAreSource &&
      !_destPredictions &&
      !_destHyperliquid &&
      !_destUsd &&
      !_destFiat &&
      _destAsset == 'btc' &&
      _sourceWalletId == null &&
      _destWalletId == null;

  /// What the dollar source can pay: Dollars, plus the venue cash the
  /// engine can bring into a purchase, net of the planned move costs (the
  /// Max, never less than Dollars). Read from the last known values
  /// ([investmentsSpendableProvider]): never loading.
  ///
  /// It is also the From row's figure (founder decision 13 October 2026):
  /// the row shows what can actually be bought, so any amount up to the
  /// shown number goes through and "insufficient" starts a cent above it.
  double get _dollarsSourceUsd {
    final dollars = _availableUsd;
    if (!_dollarsReachVenueCash) return dollars;
    final max = ref.read(investmentsSpendableProvider).maxUsd;
    return max > dollars ? max : dollars;
  }

  /// While venue cash is coming home for a purchase: one line per leg,
  /// on the sheet's quiet caption line.
  String? _pullProgress;

  /// The Buy bitcoin whose steps (each leg, the purchase, the arrival)
  /// show on that line while it runs, once its record is written.
  String? _stepsMoveId;

  /// The multi-source move a purchase's venue cash went under, and the
  /// amount it was for: Retry of the same amount continues it (money
  /// already moved is reused, never pulled twice) and the purchase joins
  /// its one Activity row.
  String? _moveId;
  double? _moveUsd;

  /// The last pull stopped with a leg that did not go: the button is
  /// Retry for the remainder until the amount changes.
  bool _retryPull = false;

  /// The purchase's ONE approval when venue cash is part of it: asked
  /// before any leg moves, it covers the legs (their caps) and the
  /// purchase itself, which consumes it instead of asking again.
  AuthGrant? _purchaseGrant;

  /// The live lock. Seeded from `widget.lockedSide` but mutable: the swap
  /// button inverts a venue exchange between withdraw (venue → BTC) and
  /// deposit (BTC → venue), so the picker-locks and direction follow the
  /// flip.
  late MoveLockedSide _lockedSide = widget.lockedSide;

  /// Fiat (bank account) side pins. `depositFromFiat` sets
  /// `_sourceFiat` (bank → Bitcoin), `withdrawToFiat` sets `_destFiat`
  /// (Bitcoin → bank). Mutable because the swap button flips one lock
  /// into the other, mirroring the Predictions/Hyperliquid pairs.
  bool _sourceFiat = false;
  bool _destFiat = false;

  /// Whether the bank rail may appear at all: only while the runtime
  /// policy offers `onramp.bank` (seeded coming-soon on the backend, so
  /// hidden today). An unavailable policy does not offer it. Nothing in
  /// the sheet may select a bank side while this is false. Build watches
  /// the policy, so this follows it live.
  bool get _bankRailAllowed =>
      onrampVisible(ref.read(runtimeCapabilitiesProvider), kOnrampBank);

  /// Whether Cash App may appear at all: only while the runtime policy
  /// offers `onramp.cashapp`. Hidden, it is never listed, never opened on
  /// and never switched to; a sheet sitting on it when the policy
  /// withdraws it moves to its natural source
  /// ([_onOnrampPolicyChanged]).
  bool get _cashAppVisible =>
      onrampVisible(ref.read(runtimeCapabilitiesProvider), kOnrampCashApp);

  /// A buy door has a rail to open on. "Add funds" exists only then.
  bool get _anyOnrampVisible => _cashAppVisible || _bankRailAllowed;

  /// Cash App funds a Lightning invoice; Orchestra delivers the selected asset.
  bool _sourceCashApp = false;

  CashAppDestination get _cashAppDestination => _destHyperliquid
      ? CashAppDestination.investing
      : _destPredictions
          ? CashAppDestination.predictions
          // The buy-dollars door keeps its destination when the payment
          // method changes: the onramp delivers the dollar asset itself,
          // so the sheet that says dollars buys dollars.
          : _buyingDollars
              ? CashAppDestination.dollars
              : _fiatDestColdWallet != null
                  ? CashAppDestination.bitcoinWallet
                  : CashAppDestination.spending;

  CashAppDestination? _pendingCashAppDestination;

  /// The Ledger whose venue account the live Cash App order funds, pinned
  /// when the order was created (null for a hot-wallet purchase).
  String? _pendingCashAppLedgerWalletId;

  /// In-flight Cash App onramp order. Non-null flips the whole sheet
  /// to the quiet waiting state (Cash App was launched, the 5s poll
  /// drives the stage line) or, when the payment link could not be
  /// launched, to the in-app handoff page (Open Cash App + QR + copy).
  late final _cashAppSession =
      CashAppPurchaseSession(storedOrders: () => ref.read(swapOrdersProvider));
  OrchestraOnrampResponse? get _cashAppOrder => _cashAppSession.order;
  double _cashAppUsd = 0;
  Timer? _cashAppPoll;
  bool get _cashAppPaymentSeen => _cashAppSession.paymentReceived;
  bool get _cashAppWindowEnded => _cashAppSession.paymentWindowEnded;
  String? _cashAppRequestFingerprint;
  String? _cashAppIdempotencyKey;
  bool _cashAppCopied = false;

  /// True when the automatic launch after Continue failed (no handler
  /// for the link): render the full handoff page so the user is never
  /// stranded without a way to pay.
  bool _cashAppLinkFallback = false;

  /// Live Flashnet fiat band (GET limits through the backend proxy);
  /// null until loaded — validation falls back to the documented
  /// constants on [OrchestraService].
  double? _cashAppMinUsd;
  double? _cashAppMaxUsd;

  /// Resolved on-chain delivery address when the fiat buy credits a
  /// COLD wallet (hardware / watch-only xpub / tracked address) — see
  /// [_fiatDestColdWallet]. Resolved up front (initState / Cash App
  /// pick) via [walletAddressProvider]: the tracked address itself for
  /// external-address wallets, BDK's next-unused receive address for
  /// xpub wallets (the SAME derivation the wallet's own Receive screen
  /// shows). Keyed by [_coldDestAddressWalletId] so a re-picked
  /// destination never reuses another wallet's address. When
  /// resolution fails, Continue blocks with a clear error — the buy
  /// must NEVER silently fall back to the Spark spending address.
  String? _coldDestAddress;
  String? _coldDestAddressWalletId;
  bool _coldDestResolving = false;

  /// Fiat currency for the typed amount. The bank rail offers
  /// [_kBankFiatCurrencies] (EUR only for now, SEPA for Kute's
  /// European base); the Cash App source overrides this to USD and
  /// every switch back to the bank rail resets it to the bank default.
  String _fiatCurrency = _kBankFiatCurrencies.first;

  /// Typed fiat amount (user decision: enter the amount, not just a
  /// slider — fiat has no in-app balance for the % slider to scale).
  /// Drives the estimated-BTC line.
  final TextEditingController _typedFiatAmountController =
      TextEditingController();

  /// True when either side is pinned to a fiat rail — the sheet then
  /// swaps the % slider for the typed-amount entry. The BANK sides stay
  /// the coming-soon screen (CTA never enables, nothing dispatches);
  /// the Cash App source is the live exception — same typed-fiat entry,
  /// but Continue creates the Flashnet onramp.
  bool get _isFiatMode => _sourceFiat || _destFiat || _sourceCashApp;

  /// Effective Cash App fiat band — live limits when loaded, the
  /// documented constants otherwise.
  double get _cashAppMinFiat =>
      _cashAppMinUsd ?? OrchestraService.onrampMinFiatUsd;
  double get _cashAppMaxFiat =>
      _cashAppMaxUsd ?? OrchestraService.onrampMaxFiatUsd;

  /// True when the typed USD amount sits inside the Flashnet band.
  bool get _cashAppAmountValid {
    final usd = _typedFiatAmount;
    return usd >= _cashAppMinFiat && usd <= _cashAppMaxFiat;
  }

  /// Last coming-soon side reported to analytics, so rebuilds and
  /// repeated picks of the same side don't spam the event. 'deposit'
  /// when fiat is the source, 'withdraw' when it's the destination.
  String? _fiatComingSoonTracked;

  /// PostHog: the coming-soon fiat screen became visible (or flipped
  /// side). No monetary values — only which side was shown.
  void _trackFiatComingSoon() {
    final side = _sourceFiat
        ? 'deposit'
        : _destFiat
            ? 'withdraw'
            : null;
    if (side == null || side == _fiatComingSoonTracked) {
      return;
    }
    _fiatComingSoonTracked = side;
    TrackingService.track('fiat_coming_soon_viewed', params: {'side': side});
  }

  /// The sheet title, named after the live direction + surface rather
  /// than a flat "Exchange" (user decision): a selected venue or the
  /// dollar balance first, otherwise the lock's own name.
  String get _sheetTitle {
    if (_destPredictions) return context.l10n.moveAddPredictions;
    if (_destHyperliquid) return context.l10n.moveAddInvesting;
    if (_buyingDollars) return context.l10n.dollarDeposit;
    switch (_lockedSide) {
      case MoveLockedSide.depositToPredictions:
        return context.l10n.moveAddPredictions;
      case MoveLockedSide.withdrawFromPredictions:
        return context.l10n.moveWithdrawPredictions;
      case MoveLockedSide.depositToHyperliquid:
        return context.l10n.moveAddInvesting;
      case MoveLockedSide.withdrawFromHyperliquid:
        return context.l10n.moveWithdrawInvesting;
      case MoveLockedSide.depositToUsd:
        return context.l10n.dollarDeposit;
      case MoveLockedSide.depositFromFiat:
      case MoveLockedSide.buyToPredictions:
      case MoveLockedSide.buyToHyperliquid:
        // A selected venue is named above; ordinary purchases buy Bitcoin.
        return context.l10n.moveBuyBitcoin;
      case MoveLockedSide.withdrawToFiat:
        return context.l10n.moveSellBitcoin;
    }
  }

  String get _actionVerb {
    if (_sourceFiat || _sourceCashApp) return context.l10n.moveBuy;
    if (_destFiat) return context.l10n.moveSell;
    // Dollars are bought, not added to a venue. A cash-out that lands
    // in dollars is still a withdrawal, so it falls through below.
    if (_buyingDollars) return context.l10n.moveBuy;
    if (_destPredictions || _destHyperliquid) return context.l10n.moveAdd;
    if (_fromHyperliquid || (!_fromBtc && _sourceWalletId == null)) {
      return context.l10n.moveWithdraw;
    }
    // Every other door is a deposit (a Ledger's bitcoin into its venue).
    return context.l10n.moveAdd;
  }

  String _moveFailure(Object error) =>
      HotSettlement.messageFor(error, context.l10n) ??
      userErrorCopy(context, error, fallback: context.l10n.moveFailure);

  // ─── Move funnel (product analytics) ────────────────────────────

  final MoveFlowOutcome _moveOutcome = MoveFlowOutcome();
  Map<String, Object> get _lastMoveInputs => _moveOutcome.lastInputs;
  set _lastMoveInputs(Map<String, Object> inputs) =>
      _moveOutcome.lastInputs = inputs;
  String? _moveAmountMethod;

  String? _walletKindOf(String? walletId) {
    if (walletId == null) return null;
    final w = ref
        .read(settingsProvider)
        .wallets
        .where((w) => w.id == walletId)
        .firstOrNull;
    if (w == null) return null;
    return TrackingService.walletKind(
      isLedger: w.isLedger,
      isHardware: w.isHardware,
      isWatchOnly: w.isWatchOnly,
      isSigner: w.isSigner,
      isExternalAddress: w.isExternalAddress,
    );
  }

  /// The route (from/to asset and network), the venue it touches, the
  /// funding source and the wallet kinds on both ends.
  Map<String, Object> _moveRouteParams() {
    final String fromAsset, fromNetwork;
    if (_sourceCashApp) {
      fromAsset = 'usd';
      fromNetwork = 'cashapp';
    } else if (_sourceFiat) {
      fromAsset = _fiatCurrency.toLowerCase();
      fromNetwork = 'bank';
    } else if (_fromBtc) {
      fromAsset = 'btc';
      fromNetwork = _sourceWalletId == null ? 'spark' : 'bitcoin';
    } else if (_dollarsAreSource) {
      fromAsset = 'usd';
      fromNetwork = 'spark';
    } else if (_fromHyperliquid) {
      fromAsset = 'usdc';
      fromNetwork = 'hypercore';
    } else {
      fromAsset = 'usdc';
      fromNetwork = 'polygon';
    }
    final String toAsset, toNetwork;
    if (_destFiat) {
      toAsset = _fiatCurrency.toLowerCase();
      toNetwork = 'bank';
    } else if (_destHyperliquid) {
      toAsset = 'usdc';
      toNetwork = 'hypercore';
    } else if (_destPredictions) {
      toAsset = 'usdc';
      toNetwork = 'polygon';
    } else if (_destUsd) {
      toAsset = 'usd';
      toNetwork = 'spark';
    } else {
      toAsset = 'btc';
      toNetwork = _destWalletId == null ? 'spark' : 'bitcoin';
    }
    final venueSource = !_fromBtc && !_dollarsAreSource && !_isFiatMode;
    final venue = _destHyperliquid || _fromHyperliquid
        ? 'hyperliquid'
        : _destPredictions || venueSource
            ? 'polymarket'
            : null;
    final sourceKind = _isFiatMode
        ? null
        : _walletKindOf(_sourceWalletId ?? widget.ledgerWalletId) ??
            (_fromBtc || _dollarsAreSource ? 'hot' : null);
    final destKind = _walletKindOf(_destWalletId);
    final String fundingSource;
    if (_sourceCashApp) {
      fundingSource = 'cashapp';
    } else if (_sourceFiat) {
      fundingSource = 'bank_transfer';
    } else if (_dollarsAreSource) {
      fundingSource = 'dollars';
    } else if (venueSource) {
      fundingSource = 'venue_balance';
    } else if (_sourceWalletId == null && !_isLedgerMove) {
      fundingSource = 'spending_btc';
    } else {
      fundingSource = 'savings_btc';
    }
    return {
      ...TrackingService.routeParams(
        fromAsset: fromAsset,
        fromNetwork: fromNetwork,
        toAsset: toAsset,
        toNetwork: toNetwork,
        provider: _sourceCashApp
            ? 'orchestra'
            : _isFiatMode
                ? null
                : _isLedgerMove
                    ? 'ledger'
                    : 'orchestra',
        venue: venue,
      ),
      'locked_side': _lockedSide.name,
      'direction': _isVenueWithdraw ? 'withdraw' : 'deposit',
      'funding_source': fundingSource,
      if (sourceKind != null) 'wallet_kind': sourceKind,
      if (destKind != null) 'dest_wallet_kind': destKind,
    };
  }

  /// Route plus what the user has entered so far (exact amounts).
  Map<String, Object> _moveFlowInputs() {
    try {
      double? usd;
      double? amount;
      String asset;
      int? sats;
      if (_isFiatMode) {
        final fiat = _typedFiatAmount;
        usd = _sourceCashApp && fiat > 0 ? fiat : null;
        amount = fiat > 0 ? fiat : null;
        asset = _sourceCashApp ? 'usd' : _fiatCurrency;
      } else if (_fromBtc) {
        final selected = _selectedSats;
        sats = selected > 0 ? selected : null;
        amount = sats == null ? null : sats / 1e8;
        usd = _selectedUsdOutput > 0 ? _selectedUsdOutput : null;
        asset = 'btc';
      } else {
        final selected = _selectedUsdcFromRatio;
        usd = selected > 0 ? selected : null;
        amount = usd;
        asset = _dollarsAreSource ? 'usd' : 'usdc';
      }
      final inputs = <String, Object>{
        ..._moveRouteParams(),
        'amount_unit': _isFiatMode ? _fiatCurrency.toLowerCase() : 'usd',
        if (_moveAmountMethod != null) 'amount_method': _moveAmountMethod!,
        if (_ratio > 0) 'balance_share_pct': (_ratio * 100).round(),
        'rate_loaded': _usdPerBtc > 0,
        ...TrackingService.moneyParams(
          amountUsd: usd,
          amount: amount,
          asset: asset,
          amountSats: sats,
          currency: _isFiatMode ? _fiatCurrency : null,
          amountFiat: _isFiatMode ? amount : null,
        ),
      };
      _lastMoveInputs = inputs;
      return inputs;
    } catch (_) {
      return _lastMoveInputs;
    }
  }

  void _trackMoveSubmitted() => _moveOutcome.submitted(_moveFlowInputs());

  /// The move left the sheet; settlement reports its own outcome.
  void _trackMoveCompleted({String outcome = 'submitted'}) {
    _moveOutcome.completed(outcome: outcome);
    widget.onCompleted?.call();
  }

  /// A Ledger device flow opened from this sheet submitted the move.
  void _trackLedgerMoveSubmitted() {
    _trackMoveSubmitted();
    _trackMoveCompleted();
  }

  // ─── Buy (Cash App onramp) funnel ───────────────────────────────

  bool _buyOutOfBandTracked = false;

  Map<String, Object> _buyFlowInputs() {
    final usd = _typedFiatAmount;
    final destination = _cashAppDestination;
    return {
      'provider': 'cashapp',
      'venue': 'cashapp',
      'destination': destination.name,
      'destination_asset': destination.asset.toLowerCase(),
      'destination_network': destination.chain.toLowerCase(),
      if (_isLedgerMove || widget.venueWalletId != null)
        'wallet_kind': 'ledger'
      else if (_walletKindOf(_fiatDestColdWallet?.id) case final k?)
        'wallet_kind': k
      else
        'wallet_kind': 'hot',
      'limits_loaded': _cashAppMinUsd != null,
      ...TrackingService.moneyParams(
        amountUsd: usd > 0 ? usd : null,
        amount: usd > 0 ? usd : null,
        asset: 'usd',
        currency: 'USD',
        amountFiat: usd > 0 ? usd : null,
      ),
    };
  }

  void _startBuyFlow(String entrySource) {
    if (TrackingService.moneyFlowActive('buy')) return;
    _buyOutOfBandTracked = false;
    TrackingService.moneyFlowStarted(
      'buy',
      entrySource: entrySource,
      venue: 'cashapp',
      walletKind: _isLedgerMove || widget.venueWalletId != null
          ? 'ledger'
          : null,
      props: _buyFlowInputs(),
    );
  }

  void _trackBuyAmountTyped() {
    if (!_sourceCashApp) return;
    final usd = _typedFiatAmount;
    if (usd <= 0) return;
    TrackingService.moneyFlowStep('buy', 'amount_entered',
        props: _buyFlowInputs());
    if (!_cashAppAmountValid && !_buyOutOfBandTracked) {
      _buyOutOfBandTracked = true;
      TrackingService.track('cashapp_amount_out_of_band', params: {
        ..._buyFlowInputs(),
        'side': usd < _cashAppMinFiat ? 'below_minimum' : 'above_limit',
      });
      TrackingService.moneyFlowError(
          'buy', usd < _cashAppMinFiat ? 'below_minimum' : 'above_limit');
    }
  }

  void _trackMoveFailed(Object e, {String? stage}) {
    final category = _moveFailReason(e);
    final resolvedStage = stage ??
        switch (category) {
          'user_cancelled' => 'approval',
          'quote_rejected' || 'expired' => 'quote',
          _ => 'dispatch',
        };
    _moveOutcome.failed(category, stage: resolvedStage);
    // A declined or lapsed approval and a cancel are the person's own
    // stop, not a failure: the sheet resets quietly.
    if (!_isApprovalStop(e) &&
        e != 'user_cancelled' &&
        category != 'user_cancelled' &&
        resolvedStage != 'approval') {
      _moveFailedFeedback();
    }
  }

  /// The move or convert failed (`move_failed`, or an error shown): the
  /// soft release every money action ends with ([moneyFailureFeedback],
  /// once per failure however many paths report it). Never for a
  /// declined approval or a cancel.
  void _moveFailedFeedback() {
    if (!mounted) return;
    if (_bandOn) {
      // The confirm's band lets go quietly; the one soft tap plays once
      // it has (the rumble stopped first), never twice.
      moneyFailureFeedbackAfterBand(() => mounted && _processing);
    } else {
      unawaited(moneyFailureFeedback());
    }
  }

  /// Whether the confirm wears the rubber band: every hot move from this
  /// sheet. The Ledger's device flows and the fiat screens keep their own.
  bool get _bandOn => !_isLedgerMove && !_isFiatMode;

  /// The move reached a phase [progress] of the way to submitted (the
  /// approval, the quote, a leg sent): the band jumps to it.
  void _bandStep(double progress) {
    if (!mounted || !_processing) return;
    final now = _bandProgress ?? 0;
    if (progress <= now) return;
    setState(() => _bandProgress = progress);
  }

  /// Every leg of the move is submitted: the band snaps (the money-success
  /// haptic) and is seen doing it before the sheet closes
  /// ([RubberBand.settle]: at once under Reduce Motion). The caller
  /// checks `mounted` again before it closes the sheet.
  Future<void> _snapBeforeLeaving() async {
    if (!mounted || !_bandOn) return;
    // The band has to have been seen pulling before it can snap: a move
    // that went through within one frame of the tap gets that frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _bandOutcome = RubberBandOutcome.success);
    await RubberBand.settle(context);
  }


  String? _error;
  double _usdPerBtc = 0; // estimated rate (USDC per BTC)

  /// The Ledger's bitcoin wallet when it is the source of a Ledger move
  /// ([_pinLedgerEndpoints]). `null` = the spending wallet.
  String? _sourceWalletId;

  /// The Ledger's bitcoin wallet when a Ledger withdrawal lands on it
  /// ([_pinLedgerEndpoints]). `null` = the spending wallet.
  String? _destWalletId;

  /// The source balance the amount was judged against when Continue was
  /// tapped, held while that move is in flight ([_processing]).
  ///
  /// The move spends this balance. Once the sats leave, the live figure
  /// drops under the amount on screen while the sheet is still up with
  /// its spinner, and judging the amount being sent against what is left
  /// of it flashed "Insufficient balance" (and "$0.00 available") until
  /// the sheet closed. Max showed it every time, since Max is the whole
  /// balance. Display and validation only: every dispatch read before
  /// funds move is taken before the hold starts, and the quote's
  /// gross-up cap reads [_liveAvailableSats].
  int? _availableSatsAtSubmit;
  double? _availableUsdcAtSubmit;

  int get _availableSats => _processing && _availableSatsAtSubmit != null
      ? _availableSatsAtSubmit!
      : _liveAvailableSats;

  int get _liveAvailableSats {
    if (_isLedgerMove && !_fromBtc) return 0;
    if (_sourceWalletId != null) {
      // The Ledger's bitcoin — read from the per-wallet balance cache
      // (warmed in background by `BackgroundSyncService`). Falls back
      // to 0 if the cache hasn't been populated yet.
      final b = ref.read(walletBalanceCacheProvider)[_sourceWalletId];
      return b?.onChainBtcBalance ?? 0;
    }
    // Spending BTC source. `balanceNotifierProvider` is bound to the
    // currently-active wallet — when the user opens Move while parked
    // on a savings card it returns the savings balance, even though
    // the From chip is labelled "Spending wallet". Pull the spending
    // wallet's balance from the per-wallet cache instead so the
    // displayed source amount actually matches the spending pool.
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending != null && spending.id != settings.activeWalletId) {
      final cache = ref.read(walletBalanceCacheProvider);
      final b = cache[spending.id];
      if (b != null) {
        return b.onChainBtcBalance + b.sparkBitcoinbalance;
      }
    }
    final live = ref.read(balanceNotifierProvider);
    return live.sparkBitcoinbalance + live.onChainBtcBalance;
  }

  /// MAX sendable sats for the BTC source. No hardcoded haircut: the
  /// Orchestra quote prices the leg, and a Ledger's maximum comes from
  /// its own device-side estimate.
  int get _maxConvertibleSats => _maxConvertibleSatsOf(_availableSats);

  int _maxConvertibleSatsOf(int available) {
    if (_isLedgerMove && !_fromBtc) return 0;
    if (_isLedgerMove) {
      final maximum = _ledgerMaximum;
      return maximum == null ? 0 : math.min(available, maximum.maxSats);
    }
    return available > 0 ? available : 0;
  }

  /// Held like [_availableSats] while a move is in flight.
  double get _availableUsdc => _processing && _availableUsdcAtSubmit != null
      ? _availableUsdcAtSubmit!
      : _liveAvailableUsdc;

  double get _liveAvailableUsdc {
    if (_isLedgerMove) return _ledgerAvailableUsdc ?? 0;
    // Dollars as the source: the spending account's own dollar balance.
    // Checked first so it can never read a venue pool by accident — it
    // is a third pool, not a flavour of either.
    if (_dollarsAreSource) return _dollarsSourceUsd;
    // HyperCore refunds arrive in spot. Native funding spends that cash
    // first, then transfers any shortfall from withdrawable perp cash.
    if (_fromHyperliquid) {
      final account = ref.read(hyperliquidAccountProvider).valueOrNull;
      if (account == null) return 0;
      return hypercoreAvailableUsdc(account.withdrawable, account.spotBalances);
    }
    return ref.read(polymarketBalanceProvider);
  }

  double? get _ledgerAvailableUsdc {
    final walletId = widget.ledgerWalletId!;
    if (!_ledgerContextValid) return null;
    if (_fromHyperliquid) {
      final data = ref.read(ledgerHlAccountProvider(walletId)).valueOrNull;
      final snapshot = data?.account;
      if (snapshot == null ||
          data?.address?.toLowerCase() !=
              _ledgerIdentityAtOpen?.evmAddress?.toLowerCase()) {
        return null;
      }
      final available =
          hypercoreAvailableUsdc(snapshot.withdrawable, snapshot.spotBalances);
      return available.isFinite && available >= 0 ? available : null;
    }
    final data = ref.read(ledgerPmAccountProvider(walletId)).valueOrNull;
    if (data?.eoa?.toLowerCase() !=
            _ledgerIdentityAtOpen?.evmAddress?.toLowerCase() ||
        data?.account?.kind != PolymarketAccountKind.depositWallet ||
        data?.pusdBalance == null ||
        data?.usdceBalance == null) {
      return null;
    }
    // A fresh account read and unwrap review revalidate this upper bound.
    // Positions are never included in withdrawable cash.
    return (data!.pusdBalance! + data.usdceBalance!).toDouble() / 1e6;
  }

  LedgerMoveMax? get _ledgerMaximum {
    if (_processing) return _ledgerMaximumAtReview;
    final estimate = ref.read(ledgerMoveMaxProvider(widget.ledgerWalletId!));
    // Riverpod can retain the previous data during refresh/error. It is not
    // authority for a new amount after the inputs or selected fee changed.
    return estimate.isLoading || estimate.hasError
        ? null
        : estimate.valueOrNull;
  }

  // Balance providers expose numeric fallbacks while connecting. Keep those
  // separate from a confirmed zero before suggesting a deposit.
  String? get _sourceBalanceState {
    if (_isFiatMode) return null;
    if (_isLedgerMove) {
      if (!_ledgerContextValid) return context.l10n.ledgerErrorDetailsChanged;
      if (!_fromBtc && _ledgerAvailableUsdc == null) {
        return context.l10n.ledgerWithdrawBalanceUnavailable;
      }
      if (_fromBtc &&
          !ref
              .read(walletBalanceCacheProvider)
              .containsKey(widget.ledgerWalletId)) {
        return context.l10n.ledgerWithdrawBalanceUnavailable;
      }
      if (_fromBtc && !_loadingRate && _usdPerBtc <= 0) {
        return context.l10n.ledgerPriceUnavailable;
      }
      if (_fromBtc && _availableSats > 0 && _ledgerMaximum == null) {
        return ref.read(ledgerMoveMaxProvider(widget.ledgerWalletId!)).isLoading
            ? context.l10n.feeUiCalculating
            : context.l10n.feeUiEstimateUnavailable;
      }
      return null;
    }
    if (!_fromBtc) {
      if (_dollarsAreSource) {
        // The dollar balance answers from the SDK, with a settled-ledger
        // fallback while that is connecting, so it always has a number.
        final balance = ref.read(usdSdkBalanceProvider);
        if (balance.hasValue) return null;
        // Buying bitcoin from Investments shows the last known balance at
        // once (the settled ledger stands in) and follows the SDK when it
        // answers: no loading text.
        if (_dollarsReachVenueCash && !balance.hasError) return null;
        return balance.hasError ? 'Balance unavailable' : 'Updating balance';
      }
      if (_fromHyperliquid) {
        final balance = ref.read(hyperliquidAccountProvider);
        if (balance.hasValue) return null;
        return balance.hasError ? 'Balance unavailable' : 'Updating balance';
      }
      final balance = ref.read(polymarketTradingProvider);
      if (balance.valueOrNull?.usdcBalance != null) return null;
      return balance.hasError ? 'Balance unavailable' : 'Updating balance';
    }
    final source = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (source != null &&
        ref.read(walletBalanceCacheProvider).containsKey(source)) {
      return null;
    }
    final balance = ref.read(sparkBitcoinBalanceProvider);
    if (balance.hasValue) return null;
    return balance.hasError ? 'Balance unavailable' : 'Updating balance';
  }

  bool get _sourceHasFunds {
    if (!_fromBtc) return _availableUsdc > 0;
    if (_availableSats > 0) return true;
    if (_sourceWalletId != null) return false;
    final source = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (source != null &&
        ref.read(walletBalanceCacheProvider).containsKey(source)) {
      return false;
    }
    return (ref.read(sparkBitcoinBalanceProvider).valueOrNull ?? BigInt.zero) >
        BigInt.zero;
  }

  void _retrySourceBalance() {
    TrackingService.track('move_quote_retry_tapped',
        params: _moveRouteParams());
    if (_isLedgerMove) {
      final walletId = widget.ledgerWalletId!;
      ref.invalidate(ledgerHlAccountProvider(walletId));
      ref.invalidate(ledgerPmAccountProvider(walletId));
      ref.invalidate(ledgerMoveMaxProvider(walletId));
      if (_usdPerBtc <= 0) _refreshSelectedFundingRoute();
      if (_fromBtc && ref.read(bdkScopeWalletIdProvider) == walletId) {
        unawaited(BackgroundSyncService().scanBdkScope(source: 'move'));
      }
      return;
    }
    if (!_fromBtc) {
      if (_dollarsAreSource) {
        ref.invalidate(usdSdkBalanceProvider);
      } else if (_fromHyperliquid) {
        ref.invalidate(hyperliquidAccountProvider);
      } else {
        ref.invalidate(polymarketTradingProvider);
      }
    } else {
      ref.invalidate(sparkBitcoinBalanceProvider);
    }
  }

  /// Every door is wired: spending bitcoin and dollars to and from the
  /// venues through Orchestra, and a Ledger's own device flows. A savings
  /// wallet never pairs with a venue or with the spending account here.
  bool get _isSupportedSwap => !_isLedgerMove || _ledgerMoveValid;

  int get _selectedSats {
    if (_isLedgerMove) {
      if (!_fromBtc) return 0;
      if (_usdPerBtc <= 0 || !_usdPerBtc.isFinite) return 0;
      final sats = (_typedAmountValue / _usdPerBtc * 1e8).round();
      return sats >= _kMinSats && sats <= _maxConvertibleSats ? sats : 0;
    }
    final cap = _maxConvertibleSats;
    if (cap <= 0) {
      return 0;
    }
    final sats = (_ratio * cap).round();
    return sats < _kMinSats ? 0 : sats;
  }

  double get _selectedUsdcFromRatio {
    if (_isLedgerMove) {
      final usd = _typedAmountValue;
      return usd >= _kMinUsdc && usd <= _availableUsdc ? usd : 0;
    }
    final cap = _availableUsdc;
    if (cap <= 0) {
      return 0;
    }
    final usdc = _ratio * cap;
    return usdc < _kMinUsdc ? 0 : usdc;
  }

  /// The chain the money actually leaves from, for the fee estimate.
  /// Dollars are their own pool: reading them as the Predictions balance
  /// asked Orchestra to price a leg that does not exist, which is why
  /// the block said the estimate was unavailable.
  String get _sourceFeeChain => _fromBtc
      ? (_sourceWalletId == null ? 'spark' : 'bitcoin')
      : _dollarsAreSource
          ? kOrchestraUsdChain
          : _fromHyperliquid
              ? 'hypercore'
              : 'polygon';

  /// The asset that leaves, paired with [_sourceFeeChain].
  String get _sourceFeeAsset => _fromBtc
      ? 'BTC'
      : _dollarsAreSource
          ? kOrchestraUsdAssetCode
          : _fromHyperliquid
              ? 'USDC'
              : 'USDC.e';

  double get _selectedUsdOutput {
    if (_selectedSats == 0 || _usdPerBtc == 0) {
      return 0;
    }
    return (_selectedSats / 1e8) * _usdPerBtc;
  }

  int get _selectedSatsOutput {
    if (_selectedUsdcFromRatio == 0 || _usdPerBtc == 0) {
      return 0;
    }
    return ((_selectedUsdcFromRatio / _usdPerBtc) * 1e8).round();
  }

  // ─── Typed amount → ratio mapping ──────────────────────────────────
  //
  // The keypad types ONE number; everything below maps it onto the
  // 0..1 `_ratio` the dispatch matrix has always consumed, so no
  // dispatch path changes.

  // Outside the fiat screens the typed number is always dollars: every
  // door touches a dollar pool (a venue or the Dollars), so there is no
  // bitcoin-typed amount.

  /// Parsed typed amount; 0 when empty/unparseable.
  double get _typedAmountValue =>
      double.tryParse(_typedAmount.isEmpty ? '0' : _typedAmount) ?? 0;

  /// True while the money is arriving from OUTSIDE: a payment rail, not
  /// a balance the person already holds. The only move that wears a
  /// colour.
  ///
  /// It used to be true for the whole buy door whatever paid for it, so
  /// paying from dollars or from a venue balance turned the screen green
  /// as well. Those are not onramps, they are money moving between
  /// accounts the person already has, and the green is what tells the
  /// two apart (owner decision).
  bool get _isBuyFlow => _sourceFiat || _sourceCashApp;

  /// Recomputes `_ratio` from the typed amount. Over-typed amounts
  /// clamp to 1.0 (== Max), so dispatch sends at most the balance; the
  /// available line turns red via [_typedExceedsAvailable].
  void _syncRatioFromTyped() {
    double r = 0;
    final usd = _typedAmountValue;
    if (usd > 0) {
      if (!_fromBtc) {
        final cap = _availableUsdc;
        if (cap > 0) {
          r = usd / cap;
        }
      } else if (_usdPerBtc > 0) {
        // BTC source aimed at a USD pool — map through the rate.
        final neededSats = (usd / _usdPerBtc * 1e8).round();
        final cap = _maxConvertibleSats;
        if (cap > 0) {
          r = neededSats / cap;
        }
      }
    }
    _ratio = r.clamp(0.0, 1.0);
  }

  /// True when the typed amount exceeds what the source can cover —
  /// the balance line turns red and dispatch clamps to the maximum.
  bool get _typedExceedsAvailable {
    final usd = _typedAmountValue;
    if (usd <= 0) {
      return false;
    }
    if (!_fromBtc) {
      return usd > _availableUsdc + 0.005;
    }
    if (_usdPerBtc <= 0) {
      return false;
    }
    final neededSats = (usd / _usdPerBtc * 1e8).round();
    return neededSats > _maxConvertibleSats;
  }

  /// Keypad edit → typed amount + ratio.
  void _onTypedAmountChanged(String v, {bool drain = false}) {
    setState(() {
      _typedAmount = v;
      _drainArmed = drain;
      _syncRatioFromTyped();
    });
    _moveAmountMethod ??= 'keypad';
    if (v.isNotEmpty) {
      TrackingService.moneyFlowStep('move', 'amount_entered',
          props: _moveFlowInputs());
    }
  }

  /// Whether a dollar chip is above what the source can cover: the test
  /// [_typedExceedsAvailable] applies to a typed amount, asked of a
  /// figure nobody has typed yet. Display only (the chip reads dimmed).
  bool _chipExceedsAvailable(int usd) {
    if (_isFiatMode) {
      // Outside money has no balance to exceed; Cash App has a band.
      return _sourceCashApp &&
          (usd < _cashAppMinFiat || usd > _cashAppMaxFiat);
    }
    if (!_fromBtc) return usd > _availableUsdc + 0.005;
    // No price to value the bitcoin with: nothing is in reach yet.
    if (_usdPerBtc <= 0) return true;
    return (usd / _usdPerBtc * 1e8).round() > _maxConvertibleSats;
  }

  /// A fixed-amount chip on the fiat screens (Cash App, the bank rail):
  /// writes the typed fiat amount, exactly as the keypad does there.
  /// These screens spend outside money, so they have no Max.
  void _applyFiatAmountChip(int amount) {
    HapticFeedback.selectionClick();
    if (_processing || !_isFiatMode) return;
    TrackingService.track('move_amount_percent_tapped', params: {
      'chip': '$amount',
      ..._moveRouteParams(),
    });
    setState(() =>
        _typedFiatAmountController.text = moveQuickAmountTyped(amount));
    _trackBuyAmountTyped();
  }

  /// A dollar chip: types that figure, exactly as the keypad would.
  void _applyAmountDollars(int usd) {
    HapticFeedback.selectionClick();
    if (_processing || _isFiatMode) return;
    _moveAmountMethod = 'chip_$usd';
    TrackingService.track('move_amount_percent_tapped', params: {
      'chip': '$usd',
      ..._moveRouteParams(),
    });
    _onTypedAmountChanged(moveQuickAmountTyped(usd));
  }

  /// Writes a fraction of the spendable source into the amount.
  ///
  /// The ceiling is the convertible maximum, which already has the live
  /// network-fee quote taken out of it, so 100% is the drain: everything
  /// that can actually leave, with the fee covered rather than added on
  /// top. Typing that same figure arms the same drain through
  /// [_syncRatioFromTyped], so the chip and the keypad agree.
  ///
  /// [chip] only names the chip in analytics (the Max chip sends `max`).
  void _applyAmountPercent(double ratio, {String? chip}) {
    HapticFeedback.selectionClick();
    if (_processing || _isFiatMode) return;
    _moveAmountMethod = ratio >= 1 ? 'max' : 'percent_${(ratio * 100).round()}';
    TrackingService.track('move_amount_percent_tapped', params: {
      'percent': (ratio * 100).round(),
      if (chip != null) 'chip': chip,
      ..._moveRouteParams(),
    });
    final typed = _usdShareTyped(ratio);
    if (typed == null) return;
    _onTypedAmountChanged(typed, drain: ratio >= 1);
  }

  /// [ratio] of the spendable source as the dollar keypad types it, or
  /// null when that is nothing. A bitcoin source is valued at the sheet's
  /// price, so Max on a dollar keypad is only as current as that price.
  String? _usdShareTyped(double ratio) {
    final ceiling = _fromBtc
        ? (_usdPerBtc > 0 ? (_maxConvertibleSats / 1e8) * _usdPerBtc : 0.0)
        : _availableUsdc;
    final target = ceiling * ratio;
    if (target <= 0) return null;
    // Round down so 100% can never land a cent above the balance.
    final floored = (target * 100).floor() / 100;
    if (floored <= 0) return null;
    return floored.toStringAsFixed(2);
  }

  /// Switches THIS sheet to a fiat source for a venue deposit.
  ///
  /// Picking Cash App from the Ledger funding sheet used to hand the
  /// choice back and open a second Move sheet on top of this one. The
  /// user had asked to change where the money comes from, not to start
  /// again, and a sheet appearing over a sheet is how that read. The
  /// same move sheet re-locks itself now, exactly as it would have been
  /// configured had it opened on that door.
  void _switchToFiatVenueSource(LedgerDepositSource source,
      {required bool predictions}) {
    // The Ledger funding sheet lists only the rails the policy offers; a
    // hidden rail is never switched to even if a caller asks for one.
    if (source == LedgerDepositSource.bank && !_bankRailAllowed) return;
    if (source == LedgerDepositSource.cashApp && !_cashAppVisible) return;
    setState(() {
      _lockedSide = predictions
          ? MoveLockedSide.buyToPredictions
          : MoveLockedSide.buyToHyperliquid;
      _sourceCashApp = source == LedgerDepositSource.cashApp;
      _sourceFiat = source != LedgerDepositSource.cashApp;
      _sourceUsd = false;
      _sourceWalletId = null;
      _fromBtc = false;
      _fromHyperliquid = false;
      _destAsset = 'btc';
      _destPredictions = predictions;
      _destHyperliquid = !predictions;
      _destWalletId = null;
      _destFiat = false;
      _error = null;
      _processing = false;
      _typedFiatAmountController.clear();
      _resetTypedAmount();
    });
    TrackingService.track('move_ledger_source_switched', params: {
      'source': source.name,
      'venue': predictions ? 'predictions' : 'investing',
    });
    if (source == LedgerDepositSource.cashApp) _startBuyFlow('ledger_move');
    _fetchCashAppLimits();
  }

  /// Inverse of [_switchToFiatVenueSource] inside a Ledger move: the
  /// Ledger's bitcoin funds the venue again through the device flow.
  void _switchToLedgerBitcoinSource({required bool predictions}) {
    setState(() {
      _lockedSide = predictions
          ? MoveLockedSide.depositToPredictions
          : MoveLockedSide.depositToHyperliquid;
      _fromBtc = true;
      _fromHyperliquid = false;
      _sourceUsd = false;
      _destPredictions = predictions;
      _destHyperliquid = !predictions;
      _pinLedgerEndpoints();
      _error = null;
      _processing = false;
      _typedFiatAmountController.clear();
      _resetTypedAmount();
    });
    TrackingService.track('move_ledger_source_switched', params: {
      'source': LedgerDepositSource.bitcoin.name,
      'venue': predictions ? 'predictions' : 'investing',
    });
  }

  /// The door's own non-fiat source, for a door whose payment rail the
  /// policy does not offer (see [moveOpeningRail]). Never a hidden rail:
  /// Buy bitcoin pays from the dollar balance; the venue buys become the
  /// venue deposit from spending bitcoin; the dollars door and the venue
  /// deposits take spending bitcoin. Sets fields only: initState needs no
  /// setState, and the live path wraps it in one. A door with no such
  /// source ([_noNaturalSource]) never comes here: it closes instead.
  void _openOnNaturalSource() {
    _sourceFiat = false;
    _sourceCashApp = false;
    _sourceUsd = false;
    _sourceWalletId = null;
    _fromHyperliquid = false;
    _destFiat = false;
    _destAsset = 'btc';
    _fiatCurrency = _kBankFiatCurrencies.first;
    switch (_lockedSide) {
      case MoveLockedSide.buyToPredictions:
        _lockedSide = MoveLockedSide.depositToPredictions;
        _fromBtc = true;
      case MoveLockedSide.buyToHyperliquid:
        _lockedSide = MoveLockedSide.depositToHyperliquid;
        _fromBtc = true;
      case MoveLockedSide.depositFromFiat:
        _sourceUsd = true;
        _fromBtc = false;
      default:
        _fromBtc = true;
    }
  }

  /// A buy door with nothing to fall back on once its payment rails are
  /// gone: a Ledger venue buy (its rails are its only sources) and a
  /// purchase into a savings wallet (dollars never pay into one, and the
  /// sheet never turns a purchase into a move from the spending account).
  bool get _noNaturalSource =>
      widget.venueWalletId != null ||
      (_lockedSide == MoveLockedSide.depositFromFiat &&
          !_dollarsSourceAllowed);

  /// Receive picked on the Investments deposit's From picker: the
  /// Dollars receive screen (its own route, `receiveDollars`) in this
  /// sheet's place — the sheet closes, the way a deposit paid another
  /// way would not have kept it either. The picker has already popped
  /// itself. `usd_receive_opened` fires from the screen's initState with
  /// the entry source marked here.
  void _openReceive() {
    final router = GoRouter.of(context);
    TrackingService.markEntrySource('usd_receive', 'deposit_sheet');
    Navigator.of(context).pop();
    router.pushNamed('receiveDollars');
  }

  /// A buy door whose payment rails are all withheld and that has no
  /// natural source ([_noNaturalSource]) has no purpose left: the door
  /// closes rather than show a hidden rail, and says so in the "Buy
  /// unavailable" sheet like every Buy door.
  void _closeRaillessBuy() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final root = Navigator.of(context, rootNavigator: true).context;
      final closed = await Navigator.of(context).maybePop();
      if (closed && root.mounted) unawaited(showBuyUnavailableSheet(root));
    });
  }

  /// The runtime policy changed while the sheet is open. A rail it no
  /// longer offers leaves the screen: the From side moves to the door's
  /// natural source, exactly as if the door had opened without it, or
  /// the door closes when it has none. A purchase already created keeps
  /// its own screen; nothing is pulled away mid-payment.
  void _onOnrampPolicyChanged() {
    if (!mounted || _processing || _cashAppOrder != null) return;
    final railGone = (_sourceCashApp && !_cashAppVisible) ||
        (_sourceFiat && !_bankRailAllowed);
    if (!railGone) return;
    if (_isLedgerMove) {
      _switchToLedgerBitcoinSource(predictions: _destPredictions);
      return;
    }
    if (_noNaturalSource) {
      _closeRaillessBuy();
      return;
    }
    setState(() {
      _openOnNaturalSource();
      _error = null;
      _typedFiatAmountController.clear();
      _resetTypedAmount();
    });
    _refreshSelectedFundingRoute();
  }

  /// Clears the typed amount + ratio — called on every route change
  /// (side pick, swap, lock flip) since the denomination and the
  /// balance it maps against may both have changed.
  void _resetTypedAmount() {
    _typedAmount = '';
    _ratio = 0;
    _drainArmed = false;
  }

  @override
  void initState() {
    super.initState();
    // The screen name stays 'move_sheet' (and every move_* event keeps its
    // name) for PostHog dashboard continuity.
    TrackingService.screenView('move_sheet');
    if (_isLedgerMove) {
      _ledgerIdentityAtOpen =
          ref.read(ledgerIdentityProvider(widget.ledgerWalletId!));
    }
    _lockedSide = widget.lockedSide;
    if (_lockedSide == MoveLockedSide.depositToPredictions) {
      // Deposit → Predictions: pick any BTC source; To locked to Predictions.
      _sourceWalletId = null;
      _fromBtc = true;
      _destAsset = 'btc';
      _destPredictions = true;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.withdrawFromPredictions) {
      // Withdraw ← Predictions: From locked to Predictions USDC; To
      // pinned to spending BTC (pools cash out to the spending wallet
      // only, so the To chip has no picker in this lock).
      _sourceWalletId = null;
      _fromBtc = false;
      _destAsset = 'btc';
      _destPredictions = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.depositToHyperliquid) {
      // Deposit spending BTC directly to native HyperCore USDC via Orchestra.
      _sourceWalletId = null;
      _fromBtc = true;
      _destAsset = 'btc';
      _destHyperliquid = true;
      _destPredictions = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.withdrawFromHyperliquid) {
      // Withdraw ← Hyperliquid (Trading): the reversed twin of the deposit
      // above. From side pinned to the Trading (Hyperliquid) USDC balance
      // (`_fromHyperliquid = true`, `_fromBtc = false`); To side pinned
      // to spending BTC, no picker (pools cash out to the spending
      // wallet only). Mirrors `withdrawFromPredictions` but sourced from
      // the native HyperCore balance instead of the Polymarket balance.
      // Orchestra receives native USDC and delivers spending BTC.
      _sourceWalletId = null;
      _fromBtc = false;
      _fromHyperliquid = true;
      _destAsset = 'btc';
      _destHyperliquid = false;
      _destPredictions = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.depositToUsd) {
      // Buy dollars: To pinned to the dollar balance, From left pickable
      // so the money can come from a Bitcoin wallet or the bank rail —
      // the same shape as the venue deposits above. Orchestra carries
      // the leg (spending BTC → dollars, both on Spark).
      _sourceWalletId = null;
      _fromBtc = true;
      _destAsset = 'btc';
      _destUsd = true;
      _destPredictions = false;
      _destHyperliquid = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.depositFromFiat) {
      // Buy bitcoin: From is a payment method (Cash App, the bank rail
      // while it is offered, or the dollar balance); To is the spending
      // account, or the savings wallet the door was opened for
      // ([DepositSheet.fiatDepositWalletId]). Bank transfers stay inert —
      // the CTA never enables while the bank rail is selected.
      //
      // DOLLARS LEAD ON THE SPENDING ACCOUNT (owner decision). Money
      // already in the dollar balance buys bitcoin on a real catalogue
      // route and settles at once, where a payment rail has to bring
      // outside money in first. So the door opens on dollars whenever
      // there are dollars to spend, and falls back to the rails when
      // there are none, which is the only case where offering them
      // first is the honest answer. Every rail stays one tap away. An
      // explicit Cash App request (Activity's "Create new purchase")
      // repeats a Cash App purchase, so it opens on Cash App instead.
      // Investments' venue cash the engine can reach counts: the
      // purchase pays from Dollars first and brings the rest in.
      final dollarsLead = !widget.cashAppSource &&
          widget.fiatDepositWalletId == null &&
          (ref.read(usdBalanceProvider) > 0 ||
              ref.read(investmentsSpendableProvider).totalUsd > 0);
      _sourceUsd = dollarsLead;
      _sourceFiat = !dollarsLead;
      _sourceWalletId = null;
      _fromBtc = false;
      _destAsset = 'btc';
      _destPredictions = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.buyToPredictions) {
      // Buy → Predictions: identical fiat seeding to depositFromFiat
      // (From pinned to Bank account · Bank transfer, `_sourceFiat`,
      // typed amount) but the To chip is PRESET to Predictions. Inert
      // like every fiat leg.
      _sourceFiat = true;
      _sourceWalletId = null;
      _fromBtc = false;
      _destAsset = 'btc';
      _destPredictions = true;
      _destHyperliquid = false;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.buyToHyperliquid) {
      // Keep the selected venue even when deposits are disabled; execution
      // stops with an error instead of changing where the money will arrive.
      _sourceFiat = true;
      _sourceWalletId = null;
      _fromBtc = false;
      _destAsset = 'btc';
      _destPredictions = false;
      _destHyperliquid = true;
      _destWalletId = null;
    } else if (_lockedSide == MoveLockedSide.withdrawToFiat) {
      // Withdraw to bank (coming soon): To pinned to Bank account ·
      // Bank transfer; From pinned to spending BTC. Inert like every
      // fiat leg.
      _destFiat = true;
      _sourceWalletId = null;
      _fromBtc = true;
      _destAsset = 'btc';
      _destPredictions = false;
      _destWalletId = null;
    }
    // CASH APP IS THE DEFAULT PURCHASE SOURCE (user decision, September
    // 2026): every locked fiat-buy door (the Purchase buttons on Home and
    // the wallet detail, the buy-to-pool doors, "Deposit more") opens
    // with the From chip already on Cash App (USD, the live Flashnet
    // band).
    //
    // AN ONRAMP THE POLICY DOES NOT OFFER IS NEVER SHOWN (founder
    // decision, October 2026): with Cash App withheld those doors open on
    // their natural non-fiat source instead, and the bank only ever opens
    // while the policy offers it. See [moveOpeningRail] for the rule.
    final cashAppDefault = widget.cashAppSource ||
        _lockedSide == MoveLockedSide.depositFromFiat ||
        _lockedSide == MoveLockedSide.buyToPredictions ||
        _lockedSide == MoveLockedSide.buyToHyperliquid;
    // The dollars door opens on a Bitcoin source rather than a fiat
    // rail, so an explicit Cash App request there has nothing to
    // replace unless it can take the source over from Bitcoin too.
    final openingRail = moveOpeningRail(
      seededRail: _sourceFiat,
      cashAppDefault: cashAppDefault,
      cashAppOverBitcoin:
          widget.cashAppSource && _lockedSide == MoveLockedSide.depositToUsd,
      cashAppVisible: _cashAppVisible,
      bankVisible: _bankRailAllowed,
    );
    if (openingRail == MoveOpeningRail.cashApp) {
      _sourceFiat = false;
      _sourceCashApp = true;
      _fromBtc = false;
      _fiatCurrency = 'USD';
      _destAsset = 'btc';
    } else if (openingRail == MoveOpeningRail.natural) {
      if (!_noNaturalSource) {
        _openOnNaturalSource();
      } else if (widget.venueWalletId == null) {
        // A purchase into a savings wallet with no rail on offer: the
        // door closes on the "Buy unavailable" sheet rather than turn
        // into a move from the spending account.
        _closeRaillessBuy();
      }
    }
    if (widget.venueWalletId != null) {
      // A Ledger venue buy: the payment rails are its only sources.
      // Cash App when asked for and offered; otherwise the bank while
      // the policy offers it, and Cash App again while it does not.
      // With neither on offer the door has no purpose and closes
      // ([_closeRaillessBuy]).
      final cashApp = _cashAppVisible &&
          (widget.cashAppSource || !_bankRailAllowed);
      _sourceWalletId = null;
      _sourceCashApp = cashApp;
      _sourceFiat = !cashApp && _bankRailAllowed;
      _fromBtc = false;
      _fromHyperliquid = false;
      _destWalletId = null;
      _destFiat = false;
      _destPredictions = widget.lockedSide == MoveLockedSide.buyToPredictions;
      _destHyperliquid = widget.lockedSide == MoveLockedSide.buyToHyperliquid;
      _fiatCurrency = _sourceCashApp ? 'USD' : _kBankFiatCurrencies.first;
      if (!_sourceCashApp && !_sourceFiat) _closeRaillessBuy();
    }
    // A slip's top-up opens on the Dollars when they cover it on their own
    // (`initialSourceAsset: 'usd'`); bitcoin is these doors' default.
    if (widget.initialSourceAsset == 'usd' &&
        _dollarsSourceAllowed &&
        (_lockedSide == MoveLockedSide.depositToPredictions ||
            _lockedSide == MoveLockedSide.depositToHyperliquid)) {
      _sourceUsd = true;
      _fromBtc = false;
    }
    if (_isLedgerMove) _pinLedgerEndpoints();
    // Direction-aware open event (user decision: every deposit and
    // withdraw surface on Investing and Predictions must be trackable
    // on its own) — the bare screen view can't split the funnels.
    // `locked_side` is the door the caller opened (a buy-to-pool door
    // reports as such even after demoting to the plain buy above);
    // `buy_source` says which payment method a fiat buy STARTED on now
    // that Cash App is the default and no pick event fires for it.
    TrackingService.moneyFlowStarted(
      'move',
      event: 'move_sheet_opened',
      abandonEvent: 'move_sheet_abandoned',
      entrySource: TrackingService.takeEntrySource('move',
          fallback: widget.lockedSide.name),
      walletKind: _isLedgerMove ? 'ledger' : null,
      props: {
        'locked_side': widget.lockedSide.name,
        if (_isLedgerMove) 'wallet_kind': 'ledger',
        if (_sourceCashApp || _sourceFiat)
          'buy_source': _sourceCashApp ? 'cashapp' : 'bank_transfer',
        if ((widget.initialTargetUsd ?? 0) > 0) 'target_usd_prefilled': true,
        ..._moveRouteParams(),
      },
    );
    if (_sourceCashApp) _startBuyFlow(widget.lockedSide.name);
    // Onramp visibility follows the policy live: a rail withdrawn while
    // the sheet sits on it is replaced by the door's natural source, or
    // the door closes when it has none.
    ref.listenManual(
        runtimeCapabilitiesProvider, (_, __) => _onOnrampPolicyChanged());
    if (_isFiatMode) {
      // Fiat mode estimates via `inputToSatsProvider` (the app-wide
      // fiat rate cache), not the Orchestra sample quote — skip the
      // fetch so a failed Orchestra call can't paint a spurious error
      // banner on a bank flow that never touches Orchestra.
      _loadingRate = false;
      // The sheet opened straight onto the coming-soon fiat screen
      // (no-op for the live Cash App source — both side flags are off).
      _trackFiatComingSoon();
      if (_sourceCashApp) {
        _fetchCashAppLimits();
      }
      // Cold-wallet buy context (Purchase from a hardware / tracked
      // wallet's detail screen): resolve the on-chain delivery address
      // UP FRONT so Continue never waits on BDK, and a failure is
      // known before any order is created.
      if ((_sourceFiat || _sourceCashApp) && _fiatDestColdWallet != null) {
        // ignore: discarded_futures
        _resolveColdDestAddress();
      }
    } else {
      _fetchInitialRate();
      _warmUpMove();
    }

    // A 100% move reads the SDK's cached balance at confirm without
    // waiting for a sync (see [sparkDrainBalanceSats], [usdDrainBaseUnits]).
    // Start one shared background sync now, never awaited, so that cache
    // is fresh by then.
    if (!_isLedgerMove) {
      final sdk = BreezSdkSpark().instance;
      if (sdk != null) kickSharedSyncWallet(sdk);
    }

    // Refresh the SOURCE wallet's UTXOs once before the user types —
    // but ONLY when SENDING from a Ledger's bitcoin (`_sourceWalletId`
    // non-null) AND that source is the scoped wallet (so scanBdkScope
    // targets it). Moving FROM spending needs no BDK scan — keep syncs
    // minimal. Single-shot only — BDK Electrum scans crash under
    // continuous load, so we never loop here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final sourceId = _sourceWalletId;
      final bdkScope = ref.read(bdkScopeWalletIdProvider);
      if (sourceId != null && bdkScope == sourceId) {
        // ignore: discarded_futures
        BackgroundSyncService().scanBdkScope(source: 'move');
      }
    });
  }

  @override
  void dispose() {
    _purchaseGrant?.revoke();
    _moveOutcome.closed();
    TrackingService.moneyFlowAbandoned('buy', props: _lastMoveInputs);
    _cashAppPoll?.cancel();
    _typedFiatAmountController.dispose();
    super.dispose();
  }

  /// Refreshes the live Flashnet fiat band. Silent on failure — the
  /// documented constants keep validating.
  void _refreshSelectedFundingRoute() {
    if (_sourceCashApp) {
      _fetchCashAppLimits();
    } else if (!_isFiatMode) {
      _fetchInitialRate();
    }
  }

  Future<void> _fetchCashAppLimits() async {
    // On-chain delivery (cold-wallet destination) may carry a higher
    // minimum than Spark; the chain hint lets a per-chain limits
    // endpoint answer with the right band. Endpoints that don't
    // distinguish return the global band, and Flashnet's own order
    // validation stays the backstop.
    final destination = _cashAppDestination;
    _cashAppMinUsd = null;
    _cashAppMaxUsd = null;
    final res = await OrchestraService.getOnrampLimits(
        destinationChain: destination.chain,
        destinationAsset: destination.asset);
    final limits = res.data;
    if (limits == null) {
      TrackingService.track('cashapp_limits_result', params: {
        'outcome': 'failed',
        'destination': destination.name,
      });
      TrackingService.moneyFlowError('buy', 'network');
    }
    if (!mounted || limits == null || destination != _cashAppDestination) {
      return;
    }
    setState(() {
      _cashAppMinUsd = limits.minFiatUsd;
      _cashAppMaxUsd = limits.maxFiatUsd;
    });
  }

  /// The Predictions deposit wallet a Predictions move pays into: the live
  /// account's, else the one the device remembers for the spending wallet
  /// (no network), else the one the account start is resolving, awaited on
  /// its own rather than behind credentials and data reads. Null when it
  /// cannot be read. Only ever the quote request's input: the settlement
  /// runner resolves the same address from the wallet and refuses a quote
  /// whose recipient differs.
  Future<String?> _resolveEvmAddress() async {
    var evm =
        ref.read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    if (evm == null || evm.isEmpty) {
      final spending = pickSpendingWallet(ref.read(settingsProvider));
      if (spending != null) {
        evm = PolymarketAccountCache.read(spending.id)?.depositAddress;
      }
    }
    if (evm == null || evm.isEmpty) {
      try {
        evm = await ref.read(polymarketTradingProvider.notifier).depositAddress();
      } catch (_) {}
    }
    return evm == null || evm.isEmpty ? null : evm;
  }

  /// The address this move's quote (or Cash App order) will name for a
  /// [chain] destination, taken from what the sheet already resolved and
  /// never awaited, so it never holds an estimate up. An estimate asked
  /// without it prices a HyperCore destination as an account Hyperliquid
  /// has never seen, the one-time activation (about $1.22) on every
  /// deposit. Null while unknown. Build passes `ref.watch` as [read] so
  /// the fee block asks again once the address lands. It goes to
  /// Orchestra's estimate only, never to analytics or logs.
  String? _estimateRecipientFor(String chain,
      {required T Function<T>(ProviderListenable<T> provider) read}) {
    final ledgerWalletId = widget.venueWalletId ?? widget.ledgerWalletId;
    if (_isLedgerMove && ledgerWalletId != null) {
      // A Ledger lands on HyperCore in its own device-verified EVM
      // account (LedgerHypercoreFundingService, _ledgerCashAppRecipient).
      // Its Predictions deposit wallet is resolved at the tap: unknown.
      if (chain != 'hypercore') return null;
      final identity = read(ledgerIdentityProvider(ledgerWalletId));
      return identity != null && identity.hasVerifiedEvm
          ? identity.evmAddress
          : null;
    }
    switch (chain) {
      case 'hypercore':
        return read(hyperliquidAddressProvider).valueOrNull;
      case 'polygon':
        // [_resolveEvmAddress] without its network fallback.
        final live = read(polymarketTradingProvider
            .select((s) => s.valueOrNull?.proxyWalletAddress));
        if (live != null && live.isNotEmpty) return live;
        final spending = pickSpendingWallet(ref.read(settingsProvider));
        return spending == null
            ? null
            : PolymarketAccountCache.read(spending.id)?.depositAddress;
      case 'spark':
        return read(sparkSelfAddressProvider).valueOrNull;
    }
    return null;
  }

  /// The Investing account is still being derived for a [chain] fee block
  /// that needs it: the block waits rather than show the activation for
  /// a moment. Build only.
  bool _estimateRecipientPending(String chain) {
    if (_isLedgerMove || chain != 'hypercore') {
      return false;
    }
    final account = ref.watch(hyperliquidAddressProvider);
    return account.isLoading && !account.hasValue;
  }

  /// [_resolveEvmAddress] for a dispatch. Read live at the tap, never a
  /// copy kept from when the sheet opened. The account is normally up by
  /// now (the sheet starts it waking as it opens); when Continue beat it,
  /// the sheet shows its processing state while it is awaited, so a
  /// second tap cannot start a second move.
  Future<String?> _evmAddressForDispatch() async {
    final live =
        ref.read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    if (live != null && live.isNotEmpty) return live;
    setState(() => _processing = true);
    final evm = await _resolveEvmAddress();
    if (mounted) setState(() => _processing = false);
    return evm;
  }

  /// Starts, while the person types, the reads Continue would otherwise
  /// make one after another before the signing prompt: the policy, a
  /// fresh route catalogue, the venue's own location answer, the
  /// wallet's addresses and the settlement store. They are only warmed
  /// here. Continue runs every check again through the same freshness
  /// rules (the policy and catalogue ages, the venue answer's cache), so
  /// a warm value never stands in for a check, and nothing here quotes,
  /// signs or sends.
  void _warmUpMove() {
    if (_isLedgerMove || _isFiatMode) return;
    // An autoDispose provider asks the SDK again on every read, and one
    // move reads the Spark self address up to five times. Held for the
    // sheet's life it is asked once; it still rebuilds with the SDK, so
    // another wallet's address is never served. A failed answer is let
    // go, so the next read asks again exactly as it did before.
    ProviderSubscription<AsyncValue<String>>? sparkSelf;
    sparkSelf = ref.listenManual(sparkSelfAddressProvider, (_, next) {
      if (next.hasError) sparkSelf?.close();
    });
    unawaited(RuntimeCapabilitiesService.instance.refresh());
    unawaited(ref
        .read(orchestraSupportedRoutesProvider.notifier)
        .refreshIfOlderThan(kMoneyCatalogMaxAge)
        .then<void>((_) {}, onError: (_) {}));
    unawaited(HotSettlement.runner().then<void>((_) {}, onError: (_) {}));
    if (_destHyperliquid || _fromHyperliquid) {
      unawaited(ref
          .read(hyperliquidAddressProvider.future)
          .then<void>((_) {}, onError: (_) {}));
    }
    // New exposure asks the venue where the person is before the quote.
    if (_destHyperliquid) {
      unawaited(InvestmentProviderAvailability.instance.hyperliquid());
    } else if (_destPredictions) {
      unawaited(InvestmentProviderAvailability.instance.polymarket());
    }
  }

  Future<void> _fetchInitialRate() async {
    final request = ++_rateRequest;
    var showedHeld = false;
    try {
      final investing = _destHyperliquid || _fromHyperliquid;
      // The dollars door samples its OWN leg (bitcoin → dollars, both on
      // the same chain) so the rate the big number is mapped against is
      // the one the dispatch will actually quote. A venue withdrawal
      // samples the venue's exit leg: its deposit leg answers to the
      // deposit gate, which a withdrawal must never depend on.
      final sample = moveRateSample(
        ledger: _isLedgerMove,
        venueSource: !_fromBtc && !_dollarsAreSource,
        fromHyperliquid: _fromHyperliquid,
        investing: investing,
        buyingDollars: _buyingDollars,
      );
      // The sample asks for the address the move will deliver to, so a
      // HyperCore account Hyperliquid already knows is not priced with
      // the one-time activation; it is part of the held sample's key.
      var recipient =
          _estimateRecipientFor(sample.destinationChain, read: ref.read);
      String keyFor(String? to) =>
          '${sample.sourceChain}:${sample.sourceAsset}>'
          '${sample.destinationChain}:${sample.destinationAsset}'
          '>${OrchestraService.estimateRecipient(to) ?? ''}';
      final held = _isLedgerMove ? null : _rateSamples[keyFor(recipient)];
      if (held != null &&
          DateTime.now().difference(held.at) < _rateSampleMaxAge &&
          mounted) {
        showedHeld = true;
        _applyRate(held.rate, prefill: true);
      } else if (_dollarsReachVenueCash && !_isLedgerMove && mounted) {
        // Dollars paying for bitcoin type dollars: the price only labels
        // the estimate, so the app's cached BTC/USD rate puts the screen
        // up at once and the route's own sample replaces it when it
        // lands. Every dispatch quotes afresh.
        final cached = _cachedUsdPerBtc();
        if (cached != null) {
          showedHeld = true;
          _applyRate(cached, prefill: true);
        }
      }
      // The Predictions account only names where the money lands or
      // refunds, and the dispatch reads it live at the tap; the price
      // sample does not need it. It is woken beside the estimate instead
      // of awaited in front of it: an account still waking up (seed,
      // credentials, first balance reads) held the big number on its
      // skeleton for seconds before the estimate was even asked for.
      if (!investing && !_buyingDollars && !_isLedgerMove) {
        unawaited(_resolveEvmAddress());
      }
      // The Investing account is derived as the sheet opens. When it has
      // not landed yet it is waited for briefly: without it a $100
      // sample prices the activation in, about 1% off the rate.
      if (recipient == null &&
          !_isLedgerMove &&
          sample.destinationChain == 'hypercore') {
        try {
          recipient = await ref
              .read(hyperliquidAddressProvider.future)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
        if (!mounted || request != _rateRequest) return;
      }
      final result = await OrchestraService.getEstimate(
        sourceChain: sample.sourceChain,
        sourceAsset: sample.sourceAsset,
        destinationChain: sample.destinationChain,
        destinationAsset: sample.destinationAsset,
        amount: sample.amount,
        recipientAddress: recipient,
      );
      if (!mounted || request != _rateRequest || _isFiatMode) return;
      final est = result.data;
      if (est == null) {
        if (mounted) {
          setState(() {
            _loadingRate = false;
            if (!showedHeld) _error = context.l10n.ledgerPriceUnavailable;
          });
        }
        return;
      }
      final rate = sample.usdPerBtc(est.estimatedOut);
      if (rate == null) {
        throw StateError('Invalid conversion rate');
      }
      TrackingService.track('move_quote_result', params: {
        'outcome': 'ok',
        ..._moveRouteParams(),
      });
      if (!_isLedgerMove) {
        _rateSamples[keyFor(recipient)] = (rate: rate, at: DateTime.now());
      }
      if (mounted) _applyRate(rate, prefill: !showedHeld);
    } catch (e) {
      if (mounted && request == _rateRequest && !_isFiatMode) {
        TrackingService.track('move_quote_result', params: {
          'outcome': 'failed',
          'error_category': TrackingService.errorCategory(e),
          ..._moveRouteParams(),
        });
        TrackingService.moneyFlowError('move', 'quote_rejected');
        setState(() {
          _loadingRate = false;
          // A price from the last minute is already on screen: keep it
          // rather than call the price unavailable beside it.
          if (!showedHeld) {
            _error = _isLedgerMove
                ? context.l10n.ledgerPriceUnavailable
                : _moveFailure(e);
          }
        });
      }
    }
  }

  /// The app-wide BTC/USD price (the currency cache, restored from disk
  /// at launch), or null when it has none that is plausible.
  double? _cachedUsdPerBtc() {
    final perUsd =
        double.tryParse('${ref.read(currencyProvider).rates['BTC'] ?? ''}');
    if (perUsd == null || !perUsd.isFinite || perUsd <= 0) return null;
    final usdPerBtc = 1 / perUsd;
    return usdPerBtc > 1000 && usdPerBtc < 10000000 ? usdPerBtc : null;
  }

  /// The last price sample per route, so a sheet reopened (or a source
  /// switched back) within a minute shows its price at once instead of a
  /// skeleton. It only maps the typed amount and labels the estimate:
  /// every dispatch quotes afresh, and the new sample replaces it the
  /// moment it lands. Hot moves only; a Ledger maps its device amount
  /// from the price, so it always waits for a fresh one.
  static final Map<String, ({double rate, DateTime at})> _rateSamples = {};
  static const Duration _rateSampleMaxAge = Duration(minutes: 1);

  /// Puts [rate] on screen. [prefill] lands the caller's USD target; a
  /// target a held price already landed, still untouched, is re-aimed at
  /// the fresh price rather than left on the held one.
  void _applyRate(double rate, {required bool prefill}) {
    setState(() {
      _loadingRate = false;
      _usdPerBtc = rate;
      // Rate is up — remap anything typed while it loaded (the big
      // number was skeletoned, but the keypad wasn't blocked).
      _syncRatioFromTyped();
      // Prefill (bet-slip handoff and friends): land the requested
      // USD outcome in the TYPED amount so the big number shows it
      // the moment the rate is up, and aim the ratio at it, clamped
      // to what the source can cover. A small 2% pad on the ratio
      // absorbs rate drift between quote and dispatch.
      final target = widget.initialTargetUsd;
      final landed =
          target != null && _typedAmount == target.toStringAsFixed(2);
      if ((prefill || landed) &&
          target != null &&
          target > 0 &&
          _dollarsAreSource) {
        // Dollars pay a dollar figure: the typed amount IS the target.
        _typedAmount = target.toStringAsFixed(2);
        _syncRatioFromTyped();
      } else if ((prefill || landed) &&
          target != null &&
          target > 0 &&
          rate > 0) {
        final available = _availableSats;
        if (available > 0) {
          final neededSats = ((target * 1.02) / rate * 1e8).ceil();
          _ratio = (neededSats / available).clamp(0.0, 1.0);
          _typedAmount = target.toStringAsFixed(2);
        }
      }
      // Max stays Max on a new price. On a dollar keypad it wrote the
      // whole balance at the price then on screen, often the held one
      // above, so a fresh price even a dollar lower left an amount the
      // balance no longer covered: "Insufficient balance" and "Add funds"
      // on the figure Max itself chose. Re-aimed in this same frame.
      if (_drainArmed && _fromBtc && !_processing) {
        final max = _usdShareTyped(1);
        if (max != null) {
          _typedAmount = max;
          _syncRatioFromTyped();
        }
      }
    });
  }

  // ── Step-up (Wallet Hardening Phase 1b.3, 1b.4) ─────────────────────
  //
  // Every dispatcher asks for a fresh approval bound to what it is about to
  // move, once routes, quotes and provider deposit addresses exist:
  // `venueDeposit` into Predictions or Investing, `venueWithdraw` out of
  // them. A declined prompt stops quietly with nothing moved.

  String _btcApprovalLabel(int sats) =>
      '₿${sats.toFormattedString(ref.read(settingsProvider).btcFormat)}';

  String _usdApprovalLabel(double usd) => '\$${usd.toStringAsFixed(2)}';

  /// Prompts for [intent]. Null when the user declined.
  Future<AuthGrant?> _approveMove(
    SensitiveIntent intent, {
    required String amountLabel,
    double? amountUsd,
    String? reasonOverride,
  }) async {
    if (!mounted) {
      return null;
    }
    final l10n = context.l10n;
    return requireFreshAuthGrant(
      context,
      ref,
      intent: intent,
      reason: reasonOverride ?? switch (intent.action) {
        SensitiveAction.venueDeposit => l10n.stepUpReasonDeposit(amountLabel),
        SensitiveAction.venueWithdraw => l10n.stepUpReasonWithdraw(amountLabel),
        _ => l10n.stepUpReasonSend(amountLabel),
      },
      amountUsd: amountUsd,
    );
  }

  /// Settlement runner step-up hook for an Orchestra move whose funding call
  /// takes no grant (a Spark send, a HyperCore send). Approves the final
  /// recipient plus the route, never the deposit address, and consumes the
  /// grant at once, right before the runner pays.
  SettlementStepUpHook _settlementStepUp({
    required SensitiveAction action,
    required String asset,
    required String Function(SettlementAuthorizationIntent auth) amountLabel,
    String? account,
    double? amountUsd,
  }) {
    return (auth) async {
      // No quote review sheet. The person already decided on the amount
      // step; the signing prompt below is the confirmation, and a
      // second one before it was a speed bump, not a safeguard (user
      // decision September 2026). A quote that drifts still stops the
      // send through the runner's own drift check.
      if (!mounted) return false;
      final intent = OrchestraGrants.settlement(auth,
          action: action, asset: asset, account: account);
      final sourceFee = auth.sourceFeeBaseUnits;
      final String? sourceFeeReason;
      if (sourceFee != null && auth.sourceFeeAsset == 'USDC') {
        String amount(BigInt units) =>
            '${orchestraAmountToDecimalString(units.toString(), 'USDC', chain: 'hypercore')} USDC';
        sourceFeeReason = context.l10n.stepUpReasonWithdrawWithSourceFee(
          amount(auth.amountIn),
          amount(sourceFee),
          amount(auth.amountIn + sourceFee),
        );
      } else {
        sourceFeeReason = null;
      }
      final grant = await _approveMove(intent,
          amountLabel: amountLabel(auth), amountUsd: amountUsd,
          reasonOverride: sourceFeeReason);
      if (grant == null) {
        return false;
      }
      // Approved: the band takes the step.
      _bandStep(0.55);
      try {
        AuthGrants.consume(grant, intent);
        return true;
      } on AuthGrantException {
        return false;
      }
    };
  }

  /// True when [e] stopped a move before anything moved: the approval was
  /// declined or no longer covers the move.
  static bool _isApprovalStop(Object e) =>
      (e is SettlementStopped && e.reason == SettlementStopReason.declined) ||
      e is AuthGrantException;

  /// Resets the sheet after an approval stop: quiet for a decline or an
  /// expired approval, "Review again" for drift. Returns whether [e] was one.
  bool _stoppedByApproval(Object e, SensitiveAction action) {
    if (!_isApprovalStop(e)) {
      return false;
    }
    _trackMoveFailed(e, stage: 'approval');
    if (!mounted) {
      return true;
    }
    setState(() {
      _processing = false;
      _error = null;
    });
    if (e is AuthGrantException) {
      unawaited(handleGrantFailure(context, e, action: action));
    }
    return true;
  }

  /// Analytics reason for a move that did not go through: a declined
  /// approval is the user's cancel, anything else its fixed category.
  /// Never the raw error text.
  static String _moveFailReason(Object e) =>
      (e is SettlementStopped && e.reason == SettlementStopReason.declined)
          ? 'user_cancelled'
          : TrackingService.errorCategory(e);

  /// The Predictions cash-out. One settlement, two destinations: the
  /// spending account's bitcoin (the default, and the path this method
  /// has always run) or its dollars, picked on the To row. Only the
  /// destination leg of the Orchestra quote changes — same source, same
  /// refund target, same `withdrawUsdc` funding call, same
  /// [SensitiveAction.venueWithdraw] grant, same runner.
  Future<void> _convertUsdToBtc() async {
    var usd = _selectedUsdcFromRatio;
    if (usd < _kMinUsdc || _processing) {
      return;
    }
    final appRead = _appReader;
    // 100% was asked for: resolve "everything" now, from the live
    // balance the withdrawal batch can actually spend, instead of the
    // cached cent-floored figure on screen.
    final drain = _drainArmed && _destWalletId == null;

    // Predictions pays out to the spending account only. A savings
    // destination has no route; the pickers never pair the two, and
    // nothing is sent if a stale state ever does.
    if (_destWalletId != null) {
      setState(() => _error = context.l10n.routeUnavailableNothingSent);
      _moveFailedFeedback();
      return;
    }

    // What the cash-out delivers. Resolved ONCE, here, so every leg
    // below (route, quote, row, fee, overlay) names the same asset and
    // the bitcoin path keeps its exact literals.
    final dollars = _destUsd;
    final destChain = dollars ? kOrchestraUsdChain : 'spark';
    final destAsset = dollars ? kOrchestraUsdAssetCode : 'BTC';

    TrackingService.track('convert_tapped', params: {
      'direction': dollars ? 'usd_to_dollars' : 'usd_to_btc',
      // Exact amount_usd beside the legacy bucket, as on the paired
      // swapInitiated below.
      'amount_bucket': TrackingService.usdBucket(usd),
      ...TrackingService.exactUsd('amount_usd', usd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    TrackingService.swapInitiated(
        fromCoin: 'USDC',
        toCoin: destAsset,
        provider: 'orchestra',
        amountUsd: usd,
        fromAmount: usd,
        fromNetwork: 'polygon',
        toNetwork: destChain,
        venue: 'polymarket');
    TrackingService.polymarketWithdrawInitiated(amountUsdc: usd);

    setState(() {
      _processing = true;
      _error = null;
    });

    // Whether the relayer withdrawal was attempted, for the failure stage.
    var usdcSent = false;
    try {
      // 1. Get Spark self address for BTC settlement.
      final sparkAddress = await ref.read(sparkSelfAddressProvider.future);

      // 2. Create Flashnet quote: polygon native USDC → spark BTC.
      // Refund target = the Polymarket deposit wallet (proxy) the
      // USDC.e actually leaves from in `withdrawUsdc` below — a failed
      // swap refunds to an address the user still controls. Missing
      // proxy → fail HERE, before any funds move.
      // AWAIT the account, never a snapshot of it. `valueOrNull` is null
      // while the provider is loading and after any error, so a cashout
      // attempted before Predictions had finished waking up threw here
      // and reported itself as a move that could not be completed, which
      // said nothing true: nothing had been attempted at all.
      var refundEvm =
          ref.read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress ??
              '';
      if (refundEvm.isEmpty) {
        try {
          refundEvm = await ref
                  .read(polymarketTradingProvider.notifier)
                  .depositAddress() ??
              '';
        } catch (_) {
          // Fall through to the message below: the account could not be
          // read, which is the one thing worth saying.
        }
      }
      if (refundEvm.isEmpty) {
        // Named, because a refund address on the source chain is exactly
        // what is missing and the person can act on it.
        throw context.l10n.homeNavPredictionsWalletNotReadyYet;
      }
      final pm = ref.read(polymarketTradingProvider.notifier);
      final microUsdc =
          drain ? await pm.spendableMicroUsdc() : await pm.payableMicroUsdc(usd);
      if (drain) {
        usd = microUsdc.toDouble() / 1e6;
        if (usd < _kMinUsdc) {
          throw context.l10n.insufficientBalance;
        }
      }
      // The runner persists the settlement record before the relayer call
      // and registers the deposit with a persisted idempotency key.
      // Phase 1b.4: the approval the step-up hook got, handed to
      // `withdrawUsdc` in `fund`, which consumes it right before signing.
      AuthGrant? approved;
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        ref.read,
        flow: dollars
            ? SettlementFlow.movePredictionsToDollars
            : SettlementFlow.moveUsdToBtc,
        route: RouteKey(
            fromChain: 'polygon',
            fromAsset: 'USDC.e',
            toChain: destChain,
            toAsset: destAsset),
        source: SettlementAccountKind.pmHot,
        destination: SettlementAccountKind.sparkHot,
        amountUsd: usd,
        requestQuote: (key) async {
          final quoteRequest = OrchestraQuoteRequest(
            sourceChain: 'polygon',
            sourceAsset: 'USDC.e',
            destinationChain: destChain,
            destinationAsset: destAsset,
            amountBaseUnits: microUsdc,
            recipientAddress: sparkAddress,
            refundAddress: refundEvm,
            recipientKind: RecipientKind.ownSpark,
            ownAddress: await _ownAddressFor(RecipientKind.ownSpark),
            tag: kManualMoveQuoteTag,
          );
          return HotSettlement.quote(ref.read, quoteRequest,
              flow: dollars ? 'move_convert_to_dollars' : 'move_convert_to_btc',
              idempotencyKey: key);
        },
        fund: (verifiedQuote, _) async {
          // 3. Send USDC.e to Orchestra's deposit address. The quote
          //    declared `sourceAsset: 'USDC.e'`, so Flashnet is watching
          //    the bridged contract; native USDC at the same address
          //    would land unseen.
          final grant = approved;
          if (grant == null) {
            throw StateError('Move not approved');
          }
          usdcSent = true;
          final txHash =
              await ref.read(polymarketTradingProvider.notifier).withdrawUsdc(
                    toAddress: verifiedQuote.depositAddress,
                    amount: usd,
                    bridged: true,
                    exactMicroUsdc: verifiedQuote.amountIn,
                    grant: grant,
                  );
          return SettlementFundingProof.relayer(txHash);
        },
        // The relayer withdrawal is on disk once this returns; the
        // deposit is registered behind the overlay.
        registerInBackground: true,
        // Phase 1b.4. Runs once the quote exists, before the margin check
        // and the relayer call. Binds this wallet's Spark address as the
        // final recipient plus the route, the Safe and USDC.e, never the
        // per-quote deposit address.
        stepUp: (auth) async {
          // Straight to the signing prompt; see the note on the other
          // step-up above.
          if (!mounted) return false;
          approved?.revoke();
          approved = null;
          final grant = await _approveMove(
            OrchestraGrants.settlement(
              auth,
              action: SensitiveAction.venueWithdraw,
              asset: 'USDC.e',
              account: refundEvm,
              limits: const {VenueLimit.bridged: true},
            ),
            amountLabel: _usdApprovalLabel(usd),
            amountUsd: usd,
          );
          approved = grant;
          return grant != null;
        },
      ));
      final orchQuote = settled.quote.quote;
      // Register the expected inbound BTC delivery so the Spark receive
      // (Orchestra delivers in about 1 to 3 min) gets hidden from the home
      // Activity feed. The exchange row already tells the story.
      //
      // Bitcoin only: the claim window is matched against an inbound
      // BITCOIN receive, so recording one for a dollar delivery would
      // hide the next unrelated bitcoin that lands instead.
      if (!dollars) {
        PolymarketSparkTxsService.recordExpectedClaimDelivery(
          microUsd: BigInt.from((usd * 1e6).round()),
        );
      }

      // 4. The runner submitted the deposit. Without an order id yet the
      //    reconciler retries registration with the same key.
      final orderId = settled.orderId ?? orchQuote.quoteId;

      // 5. Record exchange for tracking.
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, destAsset,
          chain: destChain);
      final exchange = SwapOrder(
        id: orderId,
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: destAsset,
        networkTo: 'SPARK',
        depositAddress: orchQuote.depositAddress,
        depositAmount: usd.toStringAsFixed(2),
        withdrawalAmount: estOut.toStringAsFixed(dollars ? 2 : 8),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: sparkAddress,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: refundEvm,
        provider: 'Orchestra',
        walletId: ref.read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
      followSettlementRegistration(appRead, settled);
      // Backend provider_events row for revenue attribution
      // (Predictions USDC → spending BTC via Orchestra). Only the REAL
      // order (ord_…); registering the quote id (q_…) creates a second row the
      // ord_… completion can never reconcile with. If the order id isn't back
      // yet, background sync registers it on the q_→ord_ swap.
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'USDC',
          sourceAmount: usd,
          destinationAsset: destAsset,
          destinationAmount: estOut,
        );
      }
      // Push the new exchange into the per-wallet tx cache directly.
      // Without this the home Activity feed only sees the row after
      // the user pulls-to-refresh (which triggers a full sync that
      // re-reads `swapOrdersProvider`). The exchange IS
      // persisted in the swap orders Hive box by
      // `addExchange` above; this just mirrors it into the per-
      // wallet aggregate that the home renders from.
      ref
          .read(walletTransactionCacheProvider.notifier)
          .mergeSwapOrder(exchange);

      BackgroundSyncService().syncNow();

      final feeWalletId = ref.read(settingsProvider).activeWalletId;
      final usdPerBtc = ref.read(selectedCurrencyProvider('usd')).toDouble();
      final sentUsd = usd;
      withSettlementOrderId(settled, (orderId) {
        // Phase 9 — Orchestra spread on this conversion. Compute it in
        // USD: the user paid `usd` USDC, the Orchestra quote promised
        // `estOut` of the destination asset. For bitcoin the "fair"
        // amount at market is `usd / usdPerBtc`, so the shortfall is
        // priced back into dollars; for dollars the leg is at par and the
        // shortfall IS the fee, with no price in it at all.
        try {
          if (dollars || usdPerBtc > 0) {
            final spreadUsd = dollars
                ? sentUsd - estOut
                : (sentUsd / usdPerBtc - estOut) * usdPerBtc;
            if (spreadUsd > 0) {
              FeeHistoryService.log(
                id: 'orch-$orderId',
                kind: FeeKind.orchestraSpread,
                microUsd: (spreadUsd * 1000000).round(),
                nativeAmount: spreadUsd.toStringAsFixed(6),
                nativeUnit: 'usd',
                source: 'Orchestra',
                txId: orderId,
                walletId: feeWalletId,
              );
            }
          }
        } catch (_) {}

        // Submitted, not settled: background sync reports
        // polymarket_withdraw_completed when the order really completes.
        TrackingService.polymarketWithdrawSubmitted(
          orderId: orderId,
          amountUsd: sentUsd,
          destination: dollars ? 'usd' : 'btc',
        );
        // Submit-time (dashboards key off it); settlement is swap_completed.
        TrackingService.track('convert_success', params: {
          'direction': dollars ? 'usd_to_dollars' : 'usd_to_btc',
          // Exact amount_usd beside the legacy bucket.
          'amount_bucket': TrackingService.usdBucket(sentUsd),
          ...TrackingService.exactUsd('amount_usd', sentUsd),
          'order_id': orderId,
          'provider': 'orchestra',
        });
      });
      // NOTE: don't fire swapCompleted here — the deposit has only just
      // been submitted to Orchestra. Real settlement comes through the
      // background-sync polling loop, which fires swapCompleted when
      // the Orchestra status flips to a terminal success state.

      if (!mounted) {
        return;
      }
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final rootNav = Navigator.of(context, rootNavigator: true);
      final btcFormat = ref.read(settingsProvider).btcFormat;
      final outSats = (estOut * 1e8).round();
      final spendingName =
          ref.read(settingsProvider).activeWallet?.name ?? 'Spending';
      final l10n = context.l10n;
      context.pop();
      // Same sent overlay as every other move (user decision: the old
      // "Conversion started" card read small and off-language). It names
      // what landed, so a dollar cash-out reads in dollars.
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: rootNav,
        amount: dollars
            ? '\$${estOut.toStringAsFixed(2)}'
            : '₿${outSats.toFormattedString(btcFormat)}',
        fromWalletName: 'Predictions',
        toWalletName: dollars ? l10n.assetDollars : spendingName,
        assetIconAsset: 'lib/assets/polymarket-logo.svg',
        note: l10n.moveConversionOngoing,
      );
    } catch (e) {
      // Once the USDC left, the order's real outcome comes from the
      // background sync's terminal poll, not from this throw.
      if (!usdcSent) {
        TrackingService.swapFailed(
          fromCoin: 'USDC',
          toCoin: destAsset,
          provider: 'orchestra',
          reason: _moveFailReason(e),
          fromAmount: usd,
          amountUsd: usd,
          fromNetwork: 'polygon',
          toNetwork: destChain,
          venue: 'polymarket',
        );
        _trackMoveFailed(e);
      }
      if (_stoppedByApproval(e, SensitiveAction.venueWithdraw)) {
        return;
      }
      TrackingService.polymarketWithdrawFailed(
        amountUsd: usd,
        provider: 'orchestra',
        reason: _moveFailReason(e),
        stage: usdcSent ? 'post_send' : 'pre_send',
      );
      _trackMoveFailed(e);
      if (!mounted) {
        return;
      }
      final msg = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = msg;
      });
    }
  }

  /// Spending BTC → Predictions. Same Orchestra BTC → USDC.e pipeline
  /// the deposit sheet uses (`_handleConfirmDeposit` in
  /// `polymarket_screen`), then fires a one-shot
  /// `wrapIncomingUsdcEToPusd()` so the proceeds settle as pUSD —
  /// the resting state contract from task #170.
  /// Grosses up a BTC deposit leg so the user's typed USD target actually
  /// ARRIVES after Orchestra's spread, instead of landing a cent or two
  /// short (typed \$2.00, settled \$1.99). Quotes once at [sats]; if the
  /// server's own estimatedOut comes in below the target, scales the sats
  /// by the shortfall ratio plus a 0.3% buffer, clamps to what the source
  /// can cover, and re-quotes once. Uses Orchestra's numbers, never a
  /// guessed fee. [targetUsd] null or 0 (a sats-typed or Max flow with no
  /// USD intent) skips the gross-up entirely.
  /// [refundAddress] is the user's own Spark address (these legs are all
  /// spark-BTC-source) so a failed swap refunds home instead of
  /// stranding at Flashnet. Every quote, including the re-quote, passes
  /// the Orchestra quote gate; [recipient] is the app-resolved own
  /// address for [recipientKind].
  /// The app's own address for [kind], looked up from its source
  /// provider and never from the recipient a flow is about to quote to.
  Future<String?> _ownAddressFor(RecipientKind kind) async {
    switch (kind) {
      case RecipientKind.ownSpark:
        return ref.read(sparkSelfAddressProvider.future);
      case RecipientKind.ownEvm:
        return ref.read(hyperliquidAddressProvider.future);
      case RecipientKind.ownPmWallet:
        return ref
            .read(polymarketTradingProvider)
            .valueOrNull
            ?.proxyWalletAddress;
      case RecipientKind.external:
        return null;
    }
  }

  /// 100% of the spending wallet, resolved when the quote is requested
  /// rather than on the tap: the SDK's cached Spark balance, kept fresh by
  /// the shared sync the sheet starts when it opens. The sheet's
  /// own figure is a cache that can lag a payment (and used to add a
  /// vestigial on-chain balance), and a Spark-to-Spark deposit charges no
  /// fee, so this whole figure is what the quote asks for and what the
  /// SDK then sends.
  Future<int> _sparkDrainSats() async {
    final wrapper = await ref.read(breezSDKProvider.future);
    final sdk = wrapper.instance;
    if (sdk == null) throw StateError('The spending wallet is disconnected.');
    final sats = await sparkDrainBalanceSats(sdk);
    if (sats < _kMinSats) throw context.l10n.insufficientBalance;
    return sats;
  }

  /// A reader that outlives this sheet, for work that ends after it closes
  /// (a deposit registered in the background). Read while mounted.
  T Function<T>(ProviderListenable<T> provider) get _appReader =>
      ProviderScope.containerOf(context, listen: false).read;

  Future<(int, SettlementQuoteResult)> _quoteWithArrivalTarget({
    required int sats,
    required double? targetUsd,
    required String destinationChain,
    required String destinationAsset,
    required String recipient,
    required RecipientKind recipientKind,
    required String refundAddress,
    required String flow,
    required String idempotencyKey,
  }) async {
    final ownAddress = await _ownAddressFor(recipientKind);
    Future<SettlementQuoteResult> quoteFor(int amountSats, String key) {
      final request = OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: destinationChain,
        destinationAsset: destinationAsset,
        amountBaseUnits: BigInt.from(amountSats),
        recipientAddress: recipient,
        refundAddress: refundAddress,
        recipientKind: recipientKind,
        ownAddress: ownAddress,
        tag: kManualMoveQuoteTag,
      );
      return HotSettlement.quote(ref.read, request,
          flow: flow, idempotencyKey: key);
    }

    final target = targetUsd ?? 0;
    // The live balance, not the one held for the screen.
    final maxSats = _maxConvertibleSatsOf(_liveAvailableSats);
    var sendSats = sats;
    if (target > 0) {
      // Gross up the FIRST quote from the estimate the fee block already
      // holds for this exact amount, so the typed figure usually arrives
      // on one quote instead of two.
      // Only an estimate for this quote's own recipient counts (the fee
      // block asks for the same one).
      final estimate = ref
          .read(orchestraFeeEstimateProvider(feeEstimateKey(
            (
              fromChain: 'spark',
              fromAsset: 'BTC',
              toChain: destinationChain,
              toAsset: destinationAsset,
              amount: sats.toString(),
            ),
            recipient: recipient,
          )))
          .valueOrNull;
      if (estimate != null) {
        sendSats = grossUpSatsForTarget(
          sats: sats,
          estimatedOut: orchestraAmountToDouble(
              estimate.estimatedOut, destinationAsset,
              chain: destinationChain),
          targetUsd: target,
          maxSats: maxSats,
        );
      }
    }
    var fetched = await quoteFor(sendSats, idempotencyKey);
    if (target > 0) {
      final estOut = orchestraAmountToDouble(
          fetched.quote.quote.estimatedOut, destinationAsset,
          chain: destinationChain);
      // Asked again only when still short by more than a cent; scaled from
      // the quote's own figure (bounded, see grossUpSatsForTarget).
      if (arrivalTargetShort(estOut, target)) {
        final scaled = grossUpSatsForTarget(
          sats: sendSats,
          estimatedOut: estOut,
          targetUsd: target,
          maxSats: maxSats,
        );
        if (scaled > sendSats) {
          sendSats = scaled;
          // A different request body takes its own idempotency key.
          fetched = await quoteFor(
              sendSats, OrchestraService.generateIdempotencyKey());
        }
      }
    }
    return (sendSats, fetched);
  }

  Future<void> _dispatchBtcToPredictions(int requestedSats) async {
    final appRead = _appReader;
    var sats = requestedSats;
    final drain = _drainArmed;
    final evm = await _evmAddressForDispatch();
    if (!mounted) return;
    if (evm == null || evm.isEmpty) {
      setState(() =>
          _error = context.l10n.homeNavPredictionsWalletNotReadyYet);
      _moveFailedFeedback();
      return;
    }

    final btcRate2 = ref.read(selectedCurrencyProvider('USD')).toDouble();
    final approxUsd2 = (sats / 1e8) * btcRate2;
    TrackingService.track('move_initiated', params: {
      'source_asset': 'btc',
      'dest_asset': 'predictions',
      'amount_bucket': TrackingService.usdBucket(approxUsd2),
      ...TrackingService.exactUsd('amount_usd', approxUsd2),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    TrackingService.polymarketDepositInitiated(
      route: 'btc_spending',
      amountUsd: approxUsd2,
      entrySource: 'move_sheet',
      walletKind: 'hot',
    );
    TrackingService.swapInitiated(
      fromCoin: 'BTC',
      toCoin: 'USDC',
      provider: 'orchestra',
      fromAmount: sats / 1e8,
      amountUsd: approxUsd2,
      fromNetwork: 'spark',
      toNetwork: 'polygon',
      venue: 'polymarket',
    );

    setState(() {
      _processing = true;
      _error = null;
    });

    // Tracks how far the money got, so the catch below can tell "nothing
    // moved" (clean up the pre-persisted row, plain error) apart from
    // "BTC already left" (keep the row, lead with the sent-but framing).
    var sparkSent = false;
    String? pendingQuoteRowId;
    try {
      if (drain) sats = await _sparkDrainSats();
      // 1. Orchestra quote: spark BTC → polygon USDC.e (Safe), grossed
      // up so the typed USD target actually arrives post-spread.
      // Spark-source leg → refund target is the user's own Spark
      // address; resolution failure throws BEFORE anything moves. The
      // runner persists the settlement record before the quote and
      // `broadcasting` before the Spark send (Phase 5 plan B6).
      final sparkRefund = await ref.read(sparkSelfAddressProvider.future);
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        ref.read,
        flow: SettlementFlow.moveBtcToPredictions,
        route: RouteKey(
            fromChain: 'spark',
            fromAsset: 'BTC',
            toChain: 'polygon',
            toAsset: 'USDC.e'),
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.pmHot,
        amountUsd: approxUsd2,
        // Phase 1b.4: approve the final recipient plus the route.
        stepUp: _settlementStepUp(
          action: SensitiveAction.venueDeposit,
          asset: 'BTC',
          amountLabel: (auth) => _btcApprovalLabel(auth.amountIn.toInt()),
          amountUsd: approxUsd2,
        ),
        requestQuote: (key) async {
          final (_, fetched) = await _quoteWithArrivalTarget(
            sats: sats,
            // 100% sends the whole balance as it is; there is no
            // typed outcome to gross the quote up to.
            targetUsd: !drain ? _typedAmountValue : null,
            destinationChain: 'polygon',
            destinationAsset: 'USDC.e',
            recipient: evm,
            recipientKind: RecipientKind.ownPmWallet,
            refundAddress: sparkRefund,
            flow: 'move_predictions',
            idempotencyKey: key,
          );
          return fetched;
        },
        prepareFunding: (verifiedQuote, operationId) async {
          final orchQuote = verifiedQuote.quote;
          final quotedSats = verifiedQuote.amountIn.toInt();
          // A quote refreshed before the send replaces its pending row;
          // nothing was sent against the old one.
          final staleRowId = pendingQuoteRowId;
          if (staleRowId != null && staleRowId != orchQuote.quoteId) {
            await ref
                .read(swapOrdersProvider.notifier)
                .deleteExchange(staleRowId);
          }
          // 1b. Persist the exchange row BEFORE any money moves, linked to
          // the settlement operation. The background sync polls this
          // quote id and swaps it for the real ord_ id.
          final estOutEarly = orchestraAmountToDouble(
              orchQuote.estimatedOut, 'USDC.e',
              chain: 'polygon');
          final preRow = SwapOrder(
            id: orchQuote.quoteId,
            coinFrom: 'BTC',
            networkFrom: 'SPARK',
            coinTo: 'USDC',
            networkTo: 'POLYGON',
            depositAddress: orchQuote.depositAddress,
            depositAmount: (quotedSats / 1e8).toStringAsFixed(8),
            withdrawalAmount: estOutEarly.toStringAsFixed(2),
            status: 'exchanging',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            withdrawalAddress: evm,
            depositMin: '0',
            depositMax: '0',
            rate: '0',
            refundAddress: sparkRefund,
            provider: 'Orchestra',
            walletId: ref.read(settingsProvider).activeWalletId,
            operationId: operationId,
          );
          await ref.read(swapOrdersProvider.notifier).addExchange(preRow);
          pendingQuoteRowId = orchQuote.quoteId;
          return HotSettlement.prepareSpark(ref.read, verifiedQuote);
        },
        registerInBackground: true,
        fund: (verifiedQuote, prepared) async {
          // 2. Send BTC via Spark to the quote's deposit address. From here
          // the BTC may have left, so the row is kept whatever happens.
          sparkSent = true;
          final paymentId = await HotSettlement.sendSpark(ref.read, prepared);
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
      ));
      final orchQuote = settled.quote.quote;
      sats = settled.quote.amountIn.toInt();

      // 3. The runner submitted the deposit with the persisted key. Without
      // an order id the operation stays tracked, the reconciler retries
      // registration and the quote row stays pollable.
      final orderId = settled.orderId ?? orchQuote.quoteId;
      // DO NOT tag this Orchestra order as bet-flow. The home Activity
      // filter (`transactions_builder.dart`'s `betFlowOrderIds` check)
      // HIDES tagged SwapOrderTransactions, and for a Move-to-Predictions
      // deposit this row IS the user-meaningful event.

      // 4. Swap the pre-send quote row for the registered order row
      // (same shape, real ord_ id).
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, 'USDC.e',
          chain: 'polygon');
      final exchange = SwapOrder(
        id: orderId,
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: 'USDC',
        networkTo: 'POLYGON',
        depositAddress: orchQuote.depositAddress,
        depositAmount: (sats / 1e8).toStringAsFixed(8),
        withdrawalAmount: estOut.toStringAsFixed(2),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: evm,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: sparkRefund,
        provider: 'Orchestra',
        walletId: ref.read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      // Add-then-delete, NOT delete-then-add: addExchange is id-keyed,
      // so the transient double row is harmless, while the reverse
      // order has a kill-window with NO row for an in-flight deposit.
      await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
      if (orderId != orchQuote.quoteId) {
        await ref
            .read(swapOrdersProvider.notifier)
            .deleteExchange(orchQuote.quoteId);
      }
      pendingQuoteRowId = null;
      followSettlementRegistration(appRead, settled);
      // Backend provider_events row for revenue attribution
      // (spending BTC → Predictions USDC.e via Orchestra). Only the REAL order
      // (ord_…) — never the quote (q_…), which would duplicate the row.
      // Background sync registers it on the q_→ord_ swap if it's not back yet.
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'BTC',
          sourceAmount: sats / 1e8,
          destinationAsset: 'USDC',
          destinationAmount: estOut,
        );
      }
      ref
          .read(walletTransactionCacheProvider.notifier)
          .mergeSwapOrder(exchange);
      BackgroundSyncService().syncNow();

      // 5. Resting state: Orchestra credits USDC.e to the Safe; the
      // wrap poll watches for that arrival and converts to pUSD per
      // the #170 contract.
      ref.read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();

      // Deposit SUBMITTED — pass the USDC.e estimated-out leg as the
      // analytics amount since it's already USD-equivalent (1 USDC.e
      // = $1 by definition). Background sync reports
      // polymarket_deposit_completed when the order really settles.
      withSettlementOrderId(
          settled,
          (orderId) => TrackingService.polymarketDepositSubmitted(
                orderId: orderId,
                amountUsd: estOut,
                route: 'btc_spending',
                walletKind: 'hot',
              ));

      if (!mounted) {
        return;
      }
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final btcFormat = ref.read(settingsProvider).btcFormat;
      final navigator = Navigator.of(context);
      final settings = ref.read(settingsProvider);
      final fromName = settings.activeWallet?.name ?? 'Spending';
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '₿${sats.toFormattedString(btcFormat)}',
        fromWalletName: fromName,
        toWalletName: 'Predictions',
        assetIconAsset: 'lib/assets/polymarket-logo.svg',
        // Orchestra credits the Safe in 1–3 min, then the wrap → pUSD
        // happens. Surface that to the user so the home tile bumping
        // ~minute later doesn't feel like a surprise.
        note: settled.registered
            ? context.l10n.moveConversionOngoing
            : context.l10n.settlementRegistering,
      );
    } catch (e) {
      // Failure BEFORE the Spark send: nothing moved, so the
      // pre-persisted quote row must not linger as a phantom
      // "Exchanging" Activity row + "$X arriving" hero line.
      final staleRowId = pendingQuoteRowId;
      if (!sparkSent && staleRowId != null) {
        // ignore: unawaited_futures
        ref.read(swapOrdersProvider.notifier).deleteExchange(staleRowId);
      }
      // Once the BTC left, the order's real outcome comes from the
      // background sync's terminal poll, not from this throw.
      if (!sparkSent) {
        TrackingService.swapFailed(
          fromCoin: 'BTC',
          toCoin: 'USDC',
          provider: 'orchestra',
          reason: _moveFailReason(e),
          fromAmount: sats / 1e8,
          amountUsd: approxUsd2,
          fromNetwork: 'spark',
          toNetwork: 'polygon',
          venue: 'polymarket',
        );
        _trackMoveFailed(e);
      }
      if (_stoppedByApproval(e, SensitiveAction.venueDeposit)) {
        return;
      }
      TrackingService.polymarketDepositFailed(
        amountUsd: approxUsd2,
        provider: 'orchestra',
        reason: _moveFailReason(e),
        stage: sparkSent ? 'post_send' : 'pre_send',
      );
      _trackMoveFailed(e);
      if (!mounted) {
        return;
      }
      final msg = _moveFailure(e);
      setState(() {
        _processing = false;
        // The sent-but framing must survive whole; only pre-send
        // errors get trimmed.
        _error = msg;
      });
    }
  }

  /// Spending BTC → the spending account's dollar balance. The same
  /// Orchestra cross-asset leg the venue deposits ride, pointed at the
  /// dollar asset instead of a venue: both ends are the user's own Spark
  /// wallet, so the recipient and the refund are the same self address
  /// and the settlement runner resolves both from the wallet itself.
  ///
  /// Nothing here is user-facing except the overlay, which says Dollars.
  /// The token's own name stays inside the quote, the exchange row and
  /// the analytics, where every other internal identifier lives.
  Future<void> _dispatchBtcToUsd(int requestedSats) async {
    if (_processing) return;
    final appRead = _appReader;
    var sats = requestedSats;
    final drain = _drainArmed;
    final usdPerBtcTap = ref.read(selectedCurrencyProvider('usd')).toDouble();
    final approxUsd = (sats / 1e8) * usdPerBtcTap;
    TrackingService.track('move_initiated', params: {
      'source_asset': 'btc',
      'dest_asset': 'usd',
      'amount_bucket': TrackingService.usdBucket(approxUsd),
      ...TrackingService.exactUsd('amount_usd', approxUsd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    TrackingService.swapInitiated(
        fromCoin: 'BTC',
        toCoin: kOrchestraUsdAssetCode,
        provider: 'orchestra',
        fromAmount: sats / 1e8,
        amountUsd: approxUsd,
        fromNetwork: 'spark',
        toNetwork: kOrchestraUsdChain,
        venue: 'wallet');

    setState(() {
      _processing = true;
      _error = null;
    });

    // Whether the sats were handed to the send, for failure analytics.
    var btcSent = false;
    try {
      if (drain) sats = await _sparkDrainSats();
      // 1. The dollar leg settles on the wallet's own Spark address, and
      // a failed swap refunds to that same address. Resolution failure
      // throws BEFORE anything moves.
      final sparkAddress = await ref.read(sparkSelfAddressProvider.future);
      // 2. The shared Bitcoin → Dollars leg (the slips run the same one
      // under an order's approval): quote, this sheet's own approval,
      // the sats to the quote's deposit address, the Activity row, the
      // registration in the background, the fee and convert analytics.
      // It returns once the sats left: the sheet closes then, and the
      // Activity row follows the conversion from there.
      final seam = debugBitcoinToDollarsSend;
      final sent = seam != null
          ? await seam(approxUsd: approxUsd, onSending: () => btcSent = true)
          : await BitcoinToDollarsLeg.send(
              ref.read,
              appRead: appRead,
              sparkAddress: sparkAddress,
              approxUsd: approxUsd,
              usdPerBtc: usdPerBtcTap,
              stepUp: _settlementStepUp(
                action: SensitiveAction.moveTransfer,
                asset: 'BTC',
                amountLabel: (auth) => _btcApprovalLabel(auth.amountIn.toInt()),
                amountUsd: approxUsd,
              ),
              requestQuote: (key) async {
                final (_, fetched) = await _quoteWithArrivalTarget(
                  sats: sats,
                  // 100% sends the whole balance as it is; there is no
                  // typed outcome to gross the quote up to.
                  targetUsd: !drain ? _typedAmountValue : null,
                  destinationChain: kOrchestraUsdChain,
                  destinationAsset: kOrchestraUsdAssetCode,
                  recipient: sparkAddress,
                  recipientKind: RecipientKind.ownSpark,
                  refundAddress: sparkAddress,
                  flow: 'move_buy_dollars',
                  idempotencyKey: key,
                );
                return fetched;
              },
              onSending: () => btcSent = true,
            );
      final settled = sent.settled;
      sats = sent.sats;
      final estOut = sent.estimatedOutUsd;

      if (!mounted) {
        return;
      }
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final settings = ref.read(settingsProvider);
      final l10n = context.l10n;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '\$${estOut.toStringAsFixed(2)}',
        fromWalletName: settings.activeWallet?.name ?? l10n.spending,
        toWalletName: l10n.assetDollars,
        assetIconAsset: kUsdMarkAsset,
        note: settled.registered
            ? l10n.moveConversionOngoing
            : l10n.settlementRegistering,
      );
    } catch (e) {
      // Once the sats left, the order's real outcome comes from the
      // background sync's terminal poll, not from this throw.
      if (!btcSent) {
        TrackingService.swapFailed(
          fromCoin: 'BTC',
          toCoin: kOrchestraUsdAssetCode,
          provider: 'orchestra',
          reason: _moveFailReason(e),
          fromAmount: sats / 1e8,
          amountUsd: approxUsd,
          fromNetwork: 'spark',
          toNetwork: kOrchestraUsdChain,
          venue: 'wallet',
        );
        _trackMoveFailed(e);
      }
      if (_stoppedByApproval(e, SensitiveAction.moveTransfer) || !mounted) {
        return;
      }
      final message = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = message;
      });
    }
  }

  /// Dollar base units for [usd]. Six decimals, rounded to the cent by
  /// the caller before it gets here, so this never invents sub-cent dust.
  BigInt _usdBaseUnits(double usd) => BigInt.from((usd * 1e6).round());

  /// 100% of the dollar balance, resolved when the move is dispatched:
  /// the token's exact base units from a freshly synced read, not the
  /// cent-floored figure on screen (which left sub-cent dust behind) or a
  /// ledger-sum fallback. A Spark token transfer charges no fee on top.
  Future<BigInt> _usdDrainBaseUnits() async {
    final wrapper = await ref.read(breezSDKProvider.future);
    final sdk = wrapper.instance;
    if (sdk == null) throw StateError('The spending wallet is disconnected.');
    final units = await usdDrainBaseUnits(sdk);
    if (units < BigInt.from((_kMinUsdc * 1e6).round())) {
      throw context.l10n.insufficientBalance;
    }
    return units;
  }

  /// Takes the shortfall of [usd] from venue cash for a purchase of
  /// bitcoin, in the order every action keeps: plan the legs (nothing
  /// moves), ONE approval covering the legs and the purchase, then the
  /// legs at once, then the purchase. Dollars first, then each venue leg
  /// straight to the wallet's own Bitcoin where the venue's rail offers
  /// it (only under that approval, within its caps), home to Dollars
  /// otherwise.
  ///
  /// It never waits for money to land (founder decision 15 October 2026:
  /// "once the order is placed, we should just exit"): it returns once
  /// every leg is SUBMITTED.
  ///  * Dollars already hold what the purchase still takes from them (0
  ///    when the legs bought it all): that amount, for the purchase to go
  ///    on at once under [_purchaseGrant].
  ///  * A leg came home to Dollars and has not landed yet: the purchase
  ///    is handed to the background ([BitcoinPurchaseFinisher], under the
  ///    same approval) and the result says [_VenuePull.queued].
  ///  * Null when it stopped (declined: nothing moved, quietly; otherwise
  ///    the reason is on the caption line, whatever moved stays where it
  ///    went, and the purchase never goes twice: Retry continues the same
  ///    move).
  Future<_VenuePull?> _pullVenueCashForPurchase(double usd) async {
    final puller = ref.read(venueCashPullerProvider);
    // Read while mounted: the purchase may be handed on after the sheet
    // has gone.
    final appRead = _appReader;
    if (_moveUsd != usd) _moveId = null;
    _purchaseGrant?.revoke();
    _purchaseGrant = null;
    _stepsMoveId = null;
    VenueCashPullOutcome? outcome;
    AuthGrant? grant;
    var initialDollarsStopped = false;
    try {
      // What earlier legs of the same move already delivered to Bitcoin
      // is not asked again.
      final earlier =
          _moveId == null ? null : MultiSourceMoveStore.get(_moveId!);
      final needed = math.max(0.0, usd - (earlier?.directDeliveredUsd ?? 0));
      final plan = await puller.plan(
          neededUsd: needed, destination: VenueCashDestination.bitcoin);
      if (!mounted) return null;
      if (!plan.covers) {
        outcome = VenueCashPullOutcome(
            plan: plan,
            legs: const [],
            dollarsCover: false,
            eta: plan.eta,
            destination: VenueCashDestination.bitcoin);
      } else {
        if (plan.pulls.isNotEmpty) {
          grant = await _approvePurchaseWithLegs(usd, plan);
          if (grant == null) {
            // Declined: nothing moved.
            _trackMoveFailed(
                const SettlementStopped(SettlementStopReason.declined),
                stage: 'approval');
            if (mounted) {
              setState(() {
                _processing = false;
                _pullProgress = null;
                _stepsMoveId = null;
                _error = null;
              });
            }
            return null;
          }
          // Approved: the band takes the step.
          _bandStep(0.5);
        }
        if (!mounted) {
          grant?.revoke();
          return null;
        }
        var sent = 0;
        Future<VenueCashPullOutcome> pullNormally() => puller.pullShortfall(
              neededUsd: usd,
              forAction: VenueCashFor.buyBitcoin,
              destination: VenueCashDestination.bitcoin,
              moveId: _moveId,
              approval: grant,
              plan: plan,
              waitFor: Duration.zero,
              onPlanned: (plan) {
                if (!mounted || plan.pulls.isEmpty) return;
                _bandStep(0.6);
                setState(() => _pullProgress = venueCashProgressText(
                    context.l10n, plan,
                    destination: VenueCashDestination.bitcoin,
                    direct: puller.directVenues(
                        plan, VenueCashDestination.bitcoin)));
              },
              // The move's steps take the line from here (its record holds
              // them, live as each leg and the purchase move on).
              onStarted: (id) {
                if (mounted) setState(() => _stepsMoveId = id);
              },
              onLeg: (leg) {
                // Each leg submitted pulls the band a step further.
                sent++;
                final legs = math.max(1, plan.pulls.length);
                _bandStep(0.6 + 0.2 * math.min(sent, legs) / legs);
              },
            );
        if (earlier == null &&
            plan.pulls.length + (plan.dollarsUsd > 0 ? 1 : 0) > 1 &&
            grant != null) {
          final ownSpark = grant.boundIntent.destination!;
          final walletId = grant.walletId;
          final fanout = await appRead(bitcoinPurchaseFanoutProvider).start(
            puller: puller,
            plan: plan,
            approval: grant,
            walletId: walletId,
            ownSpark: ownSpark,
            onPlanned: (selected) {
              if (!mounted) return;
              _bandStep(0.6);
              setState(() => _pullProgress = venueCashProgressText(
                  context.l10n, selected,
                  destination: VenueCashDestination.bitcoin,
                  direct: puller.directVenues(
                      selected, VenueCashDestination.bitcoin)));
            },
            onStarted: (id) {
              _moveId = id;
              _moveUsd = usd;
              if (mounted) setState(() => _stepsMoveId = id);
            },
            onLeg: (leg) {
              sent++;
              _bandStep(0.6 +
                  0.2 *
                      math.min(sent, plan.pulls.length) /
                      math.max(1, plan.pulls.length));
            },
          );
          outcome = fanout.pull;
          grant = fanout.grant;
          initialDollarsStopped =
              fanout.dollarsEnd == ParallelDollarsEnd.notSent ||
                  fanout.dollarsEnd == ParallelDollarsEnd.unknown;
        } else {
          outcome = await pullNormally();
        }
      }
    } catch (_) {
      outcome = null;
    }
    if (outcome?.moveId != null) {
      _moveId = outcome!.moveId;
      _moveUsd = usd;
    }
    if (outcome != null && outcome.plan.covers &&
        outcome.failedLegs.isEmpty && outcome.moveId != null &&
        outcome.dollarsNeededUsd >= 0.01 &&
        DollarsToBitcoinMinimum.belowFloor(
            _usdBaseUnits(outcome.dollarsNeededUsd))) {
      try {
        await appRead(dollarsToBitcoinMinimumProvider).check(
            _usdBaseUnits(outcome.dollarsNeededUsd));
      } on DollarsToBitcoinBelowMinimum {
        BuyBitcoinSteps.record(outcome.moveId,
            (g) => BuyBitcoinSteps.buySkipped(g, at: DateTime.now()));
        PendingBitcoinPurchaseStore.remove(outcome.moveId!);
        grant?.revoke();
        if (!mounted) return null;
        setState(() => _pullProgress = null);
        return _VenuePull(0);
      }
    }
    if (!mounted) {
      // The sheet was closed under the move. Legs that came home to
      // Dollars still finish as Bitcoin, in the background under the
      // same approval; anything else ends here.
      if (outcome != null && grant != null && _queuesPurchase(outcome)) {
        _queuePurchase(appRead, outcome, grant);
      } else {
        grant?.revoke();
      }
      return null;
    }
    if (initialDollarsStopped && outcome != null) {
      // Other sources keep their independently submitted work. A refused
      // Dollars leg gets an explicit retry; an uncertain native send is held.
      if (grant != null && _queuesPurchase(outcome)) {
        _queuePurchase(appRead, outcome, grant);
      } else {
        grant?.revoke();
      }
      setState(() {
        _processing = false;
        _pullProgress = null;
        _error = context.l10n.usdSendFailed;
        _retryPull =
            _parallelPurchase != null && _canRetryParallel(_parallelPurchase!);
      });
      return null;
    }
    if (outcome != null && outcome.dollarsCover) {
      setState(() => _pullProgress = null);
      _purchaseGrant = grant;
      return _VenuePull(outcome.dollarsNeededUsd);
    }
    if (outcome != null && grant != null && _queuesPurchase(outcome)) {
      _queuePurchase(appRead, outcome, grant);
      return _VenuePull(outcome.dollarsNeededUsd, queued: true);
    }
    grant?.revoke();
    final covered = outcome != null && outcome.plan.covers;
    _retryPull = _parallelPurchase != null
        ? _canRetryParallel(_parallelPurchase!)
        : outcome != null && outcome.failedLegs.isNotEmpty;
    _moveOutcome.failed(covered ? 'venue_cash_pending' : 'insufficient_funds',
        stage: 'dispatch');
    _moveFailedFeedback();
    TrackingService.moneyFlowError(
        'move', covered ? 'venue_cash_pending' : 'insufficient_funds');
    setState(() {
      _processing = false;
      _pullProgress = null;
      _stepsMoveId = null;
      _error = (outcome == null
              ? null
              : venueCashStoppedText(context.l10n, outcome)) ??
          (covered
              ? context.l10n.usdSendFailed
              : context.l10n.insufficientBalance);
    });
    return null;
  }

  /// Whether [outcome] is a move whose every leg was submitted and whose
  /// purchase from Dollars only waits on what came home landing: the
  /// purchase can finish in the background.
  static bool _queuesPurchase(VenueCashPullOutcome outcome) =>
      outcome.plan.covers &&
      outcome.legs.isNotEmpty &&
      outcome.failedLegs.isEmpty &&
      outcome.moveId != null &&
      outcome.dollarsNeededUsd >= 0.01;

  /// Hands the purchase that finishes [outcome]'s move to the background
  /// under [grant] (the Buy's one approval): it buys once Dollars hold
  /// what came home, whether or not this sheet is still up.
  static void _queuePurchase(ProviderReader appRead,
      VenueCashPullOutcome outcome, AuthGrant grant) {
    final finisher = appRead(bitcoinPurchaseFinisherProvider);
    unawaited(finisher.start(
      moveId: outcome.moveId!,
      usd: outcome.dollarsNeededUsd,
      grant: grant,
      walletId: appRead(settingsProvider).activeWalletId,
    ));
  }

  /// The purchase's one prompt when [plan] takes venue cash: the Move
  /// approval for the whole [usd] to the wallet's own Bitcoin, binding
  /// the legs that go straight there (a cap per venue, the total). It
  /// lives as long as the background purchase may wait on the legs that
  /// come home ([AuthGrants.autofireTtl], 30 min). Null when declined.
  Future<AuthGrant?> _approvePurchaseWithLegs(
      double usd, VenueCashPlan plan) async {
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null || walletId.isEmpty) return null;
    final String ownSpark = await ref.read(sparkSelfAddressProvider.future);
    if (!mounted || ownSpark.isEmpty) return null;
    final legs = ref
        .read(venueCashPullerProvider)
        .directLegLimit(plan, VenueCashDestination.bitcoin);
    final intent = DirectLegGrants.buyBitcoin(
      walletId: walletId,
      ownSpark: ownSpark,
      route: kDollarsToBtcRoute.label,
      asset: kOrchestraUsdAssetCode,
      totalUsd: usd,
      directLegs: legs,
      ttl: AuthGrants.autofireTtl,
    );
    final seam = debugBuyBitcoinApproval;
    if (seam != null) return seam(intent);
    return _approveMove(intent,
        amountLabel: _usdApprovalLabel(usd), amountUsd: usd);
  }

  /// The purchase is submitted (or nothing was left to buy from Dollars,
  /// or what came home finishes it in the background): the band snaps,
  /// the sheet closes, and the move's one row tells the rest.
  Future<void> _finishVenuePurchase(double usd, {required bool queued}) async {
    _moveId = null;
    if (!queued) _purchaseGrant?.revoke();
    _purchaseGrant = null;
    await _snapBeforeLeaving();
    if (!mounted) {
      _trackMoveCompleted(outcome: queued ? 'purchase_queued' : 'submitted');
      return;
    }
    final navigator = Navigator.of(context);
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    navigator.pop();
    // `move_completed`: every leg was submitted. `purchase_queued`: the
    // purchase from Dollars finishes in the background once what came
    // home lands (`move_purchase_finished` reports it).
    _trackMoveCompleted(outcome: queued ? 'purchase_queued' : 'submitted');
    pushMoveSentOverlay(
      navigator: navigator,
      amount: '\$${usd.toStringAsFixed(2)}',
      fromWalletName: l10n.assetDollars,
      toWalletName: settings.activeWallet?.name ?? l10n.spending,
      assetIconAsset: 'lib/assets/bitcoin-icon.svg',
      note: l10n.moveConversionOngoing,
    );
  }

  /// The spending account's DOLLAR balance → spending BITCOIN. The buy
  /// door paid from a balance the user already holds: `spark:USDB` →
  /// `spark:BTC`, both ends the wallet's own Spark address, so the
  /// recipient and the refund are the same self address.
  ///
  /// [usd] is a dollar figure and becomes the token's own six-decimal
  /// base units once, here. It is a sat count at no point: the sats the
  /// user receives are whatever Orchestra quotes, never a number this
  /// method derives from a price.
  ///
  /// No expected-claim record is written for the inbound bitcoin. That
  /// register drives the "Routing to Bitcoin" banner, which names
  /// Predictions winnings in flight; a purchase is not a claim, so the
  /// delivery lands as an ordinary receive beside the exchange row, the
  /// same way the bitcoin → dollars leg does.
  ///
  /// The sheet closes once the purchase is SENT ([buyBitcoinFromDollars]
  /// returns before the bitcoin lands); with venue cash, once every leg
  /// is submitted ([_pullVenueCashForPurchase]).
  MultiSourceMove? get _parallelPurchase {
    final id = _moveId ?? _stepsMoveId;
    final move = id == null ? null : MultiSourceMoveStore.get(id);
    return move?.isParallelPurchase == true ? move : null;
  }

  bool _canRetryParallel(MultiSourceMove move) =>
      initialDollarsRetryable(move) || move.provenUnsentLegs.isNotEmpty;

  Future<void> _retryParallelPurchase(MultiSourceMove move) async {
    if (_processing || !_canRetryParallel(move)) return;
    if (pickSpendingWallet(ref.read(settingsProvider))?.id != move.walletId) {
      return;
    }
    setState(() => _processing = true);
    AuthGrant? grant;
    try {
      final puller = ref.read(venueCashPullerProvider);
      final initial = initialDollarsRetryable(move);
      final plan = initial
          ? VenueCashPlan(
              neededUsd: move.steps.byId(MoveSteps.initialDollarsId)!.usd,
              dollarsUsd: move.steps.byId(MoveSteps.initialDollarsId)!.usd,
              pulls: const [],
              covers: true,
              eta: Duration.zero,
              uncoveredUsd: 0)
          : await puller.planRetry(move.id);
      if (!mounted || plan == null || !plan.covers) return;
      if (initial) {
        grant = await _approvePurchaseWithLegs(plan.neededUsd, plan);
      } else {
        final intent = DirectLegGrants.retry(
          walletId: move.walletId!,
          destination: move.destination.code,
          totalUsd: plan.pulledUsd,
          directLegs: puller.directLegLimit(plan, move.destination) ?? const {},
        );
        final seam = debugBuyBitcoinApproval;
        grant = seam != null
            ? await seam(intent)
            : await _approveMove(intent,
                amountLabel: _usdApprovalLabel(plan.pulledUsd),
                amountUsd: plan.pulledUsd);
      }
      if (!mounted ||
          grant == null ||
          pickSpendingWallet(ref.read(settingsProvider))?.id != move.walletId) {
        return;
      }
      trackMultiSourceMoveRetry(initial ? plan.neededUsd : plan.pulledUsd);
      if (initial) {
        await retryInitialDollarsPurchase(_appReader,
            moveId: move.id, grant: grant);
      } else {
        await puller.retryMove(move.id, approval: grant, plan: plan);
      }
      final updated = MultiSourceMoveStore.get(move.id);
      if (!mounted || updated == null) return;
      final sources = updated.steps.steps.where(MoveSteps.isVenueLeg).toList();
      final submitted = sources.isNotEmpty && sources.every((step) =>
          step.status == MoneyStepStatus.skipped ||
          (step.ref != null && step.reason != 'outcome_unknown' &&
              step.reason != 'retry_pending' &&
              step.status != MoneyStepStatus.failed));
      if (submitted) {
        setState(() => _error = null);
        await _finishVenuePurchase(updated.spentUsd, queued: false);
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.usdSendFailed);
    } finally {
      grant?.revoke();
      if (mounted) {
        setState(() {
          _processing = false;
          _retryPull = _parallelPurchase != null &&
              _canRetryParallel(_parallelPurchase!);
        });
      }
    }
  }

  Future<void> _dispatchUsdToBtc(double usd) async {
    if (_processing) return;
    final parallel = _parallelPurchase;
    if (parallel != null) {
      await _retryParallelPurchase(parallel);
      return;
    }
    var amountBaseUnits = _usdBaseUnits(usd);
    // 100% of Dollars is the exact drain; an amount past Dollars (venue
    // cash in reach) is sent exactly as chosen.
    final pullsVenueCash = usd > _availableUsd + 0.005;
    final drain = _drainArmed && !pullsVenueCash;
    if (amountBaseUnits <= BigInt.zero) return;

    TrackingService.track('move_initiated', params: {
      'source_asset': 'usd',
      'dest_asset': 'btc',
      'amount_bucket': TrackingService.usdBucket(usd),
      ...TrackingService.exactUsd('amount_usd', usd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    TrackingService.swapInitiated(
      fromCoin: kOrchestraUsdAssetCode,
      toCoin: 'BTC',
      provider: 'orchestra',
      amountUsd: usd,
      fromAmount: usd,
      fromNetwork: kOrchestraUsdChain,
      toNetwork: 'spark',
      venue: 'wallet',
    );

    setState(() {
      _processing = true;
      _error = null;
    });

    // Whether the dollars were handed to the send, for failure analytics.
    var usdSent = false;
    try {
      if (drain) amountBaseUnits = await _usdDrainBaseUnits();
      // Dollars first; the shortfall from venue cash. With venue cash the
      // purchase asks its ONE approval before any leg moves, the legs go
      // under it, and the purchase then pays under the same approval.
      // Nothing is bought until Dollars hold what it takes from them.
      if (_retryPull && _error != null && _moveId != null) {
        trackMultiSourceMoveRetry(
            MultiSourceMoveStore.get(_moveId!)?.remainingUsd ?? 0);
      }
      _retryPull = false;
      _purchaseGrant?.revoke();
      _purchaseGrant = null;
      if (!pullsVenueCash && _moveUsd != usd) _moveId = null;
      if (pullsVenueCash) {
        final pulled = await _pullVenueCashForPurchase(usd);
        if (pulled == null) return;
        if (pulled.queued || pulled.onwardUsd < 0.01) {
          // Every leg is submitted. Either every one went straight to
          // Bitcoin (nothing left to buy from Dollars, no second
          // approval), or what came home finishes as Bitcoin in the
          // background under the same approval.
          final sent = pulled.queued ? usd :
              (_moveId == null ? null : MultiSourceMoveStore.get(_moveId!))?.spentUsd ?? usd;
          await _finishVenuePurchase(sent, queued: pulled.queued);
          return;
        }
        // The purchase takes from Dollars only what the direct legs did
        // not bring.
        if (pulled.onwardUsd + 0.005 < usd) {
          usd = pulled.onwardUsd;
          amountBaseUnits = _usdBaseUnits(pulled.onwardUsd);
        }
      }
      final sent = await buyBitcoinFromDollars(
        _appReader,
        amountBaseUnits: amountBaseUnits,
        usd: usd,
        // Venue cash in the purchase: its one approval was asked before
        // the legs moved and covers this step too.
        stepUp: _purchaseGrant != null
            ? approvedPurchaseStepUp(_purchaseGrant!)
            : _settlementStepUp(
                action: SensitiveAction.moveTransfer,
                asset: kOrchestraUsdAssetCode,
                amountLabel: (auth) =>
                    _usdApprovalLabel(auth.amountIn.toDouble() / 1e6),
                amountUsd: usd,
              ),
        moveId: _moveId,
        onQuoting: () => _bandStep(0.85),
        onFunding: () {
          usdSent = true;
          _bandStep(0.92);
        },
      );
      _moveId = null;

      if (!mounted) return;
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final settings = ref.read(settingsProvider);
      final l10n = context.l10n;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '\$${sent.sentUsd.toStringAsFixed(2)}',
        fromWalletName: l10n.assetDollars,
        toWalletName: settings.activeWallet?.name ?? l10n.spending,
        assetIconAsset: 'lib/assets/bitcoin-icon.svg',
        note: sent.registered
            ? l10n.moveConversionOngoing
            : l10n.settlementRegistering,
      );
    } catch (e) {
      if (!usdSent && e is DollarsToBitcoinBelowMinimum && _moveId != null) {
        final move = MultiSourceMoveStore.get(_moveId!);
        PendingBitcoinPurchaseStore.remove(_moveId!);
        await _finishVenuePurchase(move?.spentUsd ?? 0, queued: false);
        return;
      }
      // The purchase's approval ends with it (a Retry asks again).
      _purchaseGrant?.revoke();
      _purchaseGrant = null;
      // Once the dollars left, the order's real outcome comes from the
      // background sync's terminal poll, not from this throw.
      if (!usdSent) {
        TrackingService.swapFailed(
          fromCoin: kOrchestraUsdAssetCode,
          toCoin: 'BTC',
          provider: 'orchestra',
          reason: _moveFailReason(e),
          fromAmount: usd,
          amountUsd: usd,
          fromNetwork: kOrchestraUsdChain,
          toNetwork: 'spark',
          venue: 'wallet',
        );
        _trackMoveFailed(e);
      }
      if (_stoppedByApproval(e, SensitiveAction.moveTransfer) || !mounted) {
        return;
      }
      final message = e is DollarsToBitcoinBelowMinimum
          ? context.l10n.routeAmountTooSmallGeneric : _moveFailure(e);
      setState(() {
        _processing = false;
        _error = message;
      });
    }
  }

  /// The spending account's DOLLAR balance → Predictions. The same
  /// Orchestra cross-asset leg the bitcoin deposit rides, with the dollar
  /// token as the source asset instead of bitcoin.
  ///
  /// [usd] is a dollar figure. It becomes the token's own six-decimal
  /// base units once, here, and is a sat count at no point in this method.
  /// There is no gross-up: on a dollar source the typed number IS what
  /// leaves, the same as every other same-denomination spend.
  Future<void> _dispatchUsdToPredictions(double usd) async {
    if (_processing) return;
    final appRead = _appReader;
    final evm = await _evmAddressForDispatch();
    if (!mounted) return;
    if (evm == null || evm.isEmpty) {
      setState(() =>
          _error = context.l10n.homeNavPredictionsWalletNotReadyYet);
      _moveFailedFeedback();
      return;
    }
    var amountBaseUnits = _usdBaseUnits(usd);
    final drain = _drainArmed;
    if (amountBaseUnits <= BigInt.zero) return;

    TrackingService.track('move_initiated', params: {
      'source_asset': 'usd',
      'dest_asset': 'predictions',
      'amount_bucket': TrackingService.usdBucket(usd),
      ...TrackingService.exactUsd('amount_usd', usd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    TrackingService.polymarketDepositInitiated(
      route: 'usd',
      amountUsd: usd,
      entrySource: 'move_sheet',
      walletKind: 'hot',
    );
    TrackingService.swapInitiated(
      fromCoin: kOrchestraUsdAssetCode,
      toCoin: 'USDC',
      provider: 'orchestra',
      fromAmount: usd,
      amountUsd: usd,
      fromNetwork: kOrchestraUsdChain,
      toNetwork: 'polygon',
      venue: 'polymarket',
    );

    setState(() {
      _processing = true;
      _error = null;
    });

    var dollarsSent = false;
    String? pendingQuoteRowId;
    try {
      if (drain) amountBaseUnits = await _usdDrainBaseUnits();
      final sparkRefund = await ref.read(sparkSelfAddressProvider.future);
      final ownPm = await _ownAddressFor(RecipientKind.ownPmWallet);
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        ref.read,
        flow: SettlementFlow.moveUsdToPredictions,
        route: RouteKey(
            fromChain: kOrchestraUsdChain,
            fromAsset: kOrchestraUsdAssetCode,
            toChain: 'polygon',
            toAsset: 'USDC.e'),
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.pmHot,
        amountUsd: usd,
        stepUp: _settlementStepUp(
          action: SensitiveAction.venueDeposit,
          asset: kOrchestraUsdAssetCode,
          amountLabel: (auth) =>
              _usdApprovalLabel(auth.amountIn.toDouble() / 1e6),
          amountUsd: usd,
        ),
        requestQuote: (key) => HotSettlement.quote(
          ref.read,
          OrchestraQuoteRequest(
            sourceChain: kOrchestraUsdChain,
            sourceAsset: kOrchestraUsdAssetCode,
            destinationChain: 'polygon',
            destinationAsset: 'USDC.e',
            amountBaseUnits: amountBaseUnits,
            recipientAddress: evm,
            refundAddress: sparkRefund,
            recipientKind: RecipientKind.ownPmWallet,
            ownAddress: ownPm,
            tag: kManualMoveQuoteTag,
          ),
          flow: 'move_predictions_dollars',
          idempotencyKey: key,
        ),
        prepareFunding: (verifiedQuote, operationId) async {
          final orchQuote = verifiedQuote.quote;
          final staleRowId = pendingQuoteRowId;
          if (staleRowId != null && staleRowId != orchQuote.quoteId) {
            await ref
                .read(swapOrdersProvider.notifier)
                .deleteExchange(staleRowId);
          }
          await ref
              .read(swapOrdersProvider.notifier)
              .addExchange(_usdToPredictionsRow(
                id: orchQuote.quoteId,
                quote: verifiedQuote,
                evm: evm,
                sparkRefund: sparkRefund,
                operationId: operationId,
              ));
          pendingQuoteRowId = orchQuote.quoteId;
          return HotSettlement.prepareSpark(ref.read, verifiedQuote);
        },
        registerInBackground: true,
        fund: (verifiedQuote, prepared) async {
          dollarsSent = true;
          final paymentId = await HotSettlement.sendSpark(ref.read, prepared);
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
      ));
      final orchQuote = settled.quote.quote;
      final sentUsd = settled.quote.amountIn.toDouble() / 1e6;
      final orderId = settled.orderId ?? orchQuote.quoteId;
      final exchange = _usdToPredictionsRow(
        id: orderId,
        quote: settled.quote,
        evm: evm,
        sparkRefund: sparkRefund,
        operationId: settled.operation.operationId,
      );
      await ref.read(swapOrdersProvider.notifier).addExchange(exchange);
      if (orderId != orchQuote.quoteId) {
        await ref
            .read(swapOrdersProvider.notifier)
            .deleteExchange(orchQuote.quoteId);
      }
      pendingQuoteRowId = null;
      followSettlementRegistration(appRead, settled);
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, 'USDC.e',
          chain: 'polygon');
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: kOrchestraUsdAssetCode,
          sourceAmount: sentUsd,
          destinationAsset: 'USDC',
          destinationAmount: estOut,
        );
      }
      ref
          .read(walletTransactionCacheProvider.notifier)
          .mergeSwapOrder(exchange);
      BackgroundSyncService().syncNow();
      ref.read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();
      // Submitted, not settled: background sync reports
      // polymarket_deposit_completed when the order really completes.
      withSettlementOrderId(
          settled,
          (orderId) => TrackingService.polymarketDepositSubmitted(
                orderId: orderId,
                amountUsd: estOut,
                route: 'usd',
                walletKind: 'hot',
              ));

      if (!mounted) return;
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final l10n = context.l10n;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '\$${sentUsd.toStringAsFixed(2)}',
        fromWalletName: l10n.assetDollars,
        toWalletName: 'Predictions',
        assetIconAsset: 'lib/assets/polymarket-logo.svg',
        note: settled.registered
            ? l10n.moveConversionOngoing
            : context.l10n.settlementRegistering,
      );
    } catch (e) {
      final staleRowId = pendingQuoteRowId;
      if (!dollarsSent && staleRowId != null) {
        // ignore: unawaited_futures
        ref.read(swapOrdersProvider.notifier).deleteExchange(staleRowId);
      }
      // Once the dollars left, the order's real outcome comes from the
      // background sync's terminal poll, not from this throw.
      if (!dollarsSent) {
        TrackingService.swapFailed(
          fromCoin: kOrchestraUsdAssetCode,
          toCoin: 'USDC',
          provider: 'orchestra',
          reason: _moveFailReason(e),
          fromAmount: usd,
          amountUsd: usd,
          fromNetwork: kOrchestraUsdChain,
          toNetwork: 'polygon',
          venue: 'polymarket',
        );
        _trackMoveFailed(e);
      }
      if (_stoppedByApproval(e, SensitiveAction.venueDeposit)) return;
      TrackingService.polymarketDepositFailed(
        amountUsd: usd,
        provider: 'orchestra',
        reason: _moveFailReason(e),
        stage: dollarsSent ? 'post_send' : 'pre_send',
      );
      _trackMoveFailed(e);
      if (!mounted) return;
      final msg = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = msg;
      });
    }
  }

  /// The Activity row for a dollars → Predictions deposit. The deposit
  /// leg is written in DOLLARS (two decimals), because that is the asset
  /// that left; writing it with the bitcoin divisor is the bug this
  /// helper exists to make impossible.
  SwapOrder _usdToPredictionsRow({
    required String id,
    required VerifiedOrchestraQuote quote,
    required String evm,
    required String sparkRefund,
    required String operationId,
  }) {
    final estOut = orchestraAmountToDouble(quote.quote.estimatedOut, 'USDC.e',
        chain: 'polygon');
    return SwapOrder(
      id: id,
      coinFrom: kOrchestraUsdAssetCode,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: quote.depositAddress,
      depositAmount: (quote.amountIn.toDouble() / 1e6).toStringAsFixed(2),
      withdrawalAmount: estOut.toStringAsFixed(2),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: evm,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: sparkRefund,
      provider: 'Orchestra',
      walletId: ref.read(settingsProvider).activeWalletId,
      operationId: operationId,
    );
  }

  /// The spending account's DOLLAR balance → Investing (HyperCore). Same
  /// shared funding service as the bitcoin deposit, told which balance
  /// pays. [usd] is dollars; it becomes the token's own base units once.
  Future<void> _dispatchUsdToHyperliquid(double usd) async {
    if (_processing) return;
    var amountBaseUnits = _usdBaseUnits(usd);
    final drain = _drainArmed;
    if (amountBaseUnits <= BigInt.zero) return;
    TrackingService.track('move_initiated', params: {
      'source_asset': 'usd',
      'dest_asset': 'trading',
      'amount_bucket': TrackingService.usdBucket(usd),
      ...TrackingService.exactUsd('amount_usd', usd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      if (drain) amountBaseUnits = await _usdDrainBaseUnits();
      final direct = ref.read(sparkHypercoreFundingServiceProvider);
      await direct.ensureAvailable(deposit: true);
      TrackingService.hyperliquidDepositInitiated(
        amountUsd: usd,
        sourceAsset: 'usd',
        walletKind: 'hot',
        route: 'direct',
      );
      final result = await direct.depositFromSpark(
        registerInBackground: true,
        asset: SparkFundingAsset.dollars,
        amountBaseUnits: amountBaseUnits,
        amountUsd: usd,
        stepUp: _settlementStepUp(
          action: SensitiveAction.venueDeposit,
          asset: kOrchestraUsdAssetCode,
          amountLabel: (auth) =>
              _usdApprovalLabel(auth.amountIn.toDouble() / 1e6),
          amountUsd: usd,
        ),
      );
      // Money has landed at the venue, which is the moment a user-signed
      // builder approval will be accepted. Registering it here, once,
      // is the difference between every later order carrying Kute's fee
      // and the first order trying to register it under time pressure
      // on an account that was funded seconds ago. Fire and forget: it
      // must never delay or fail a deposit the person has completed.
      // ignore: discarded_futures
      ref
          .read(hyperliquidTradingProvider.notifier)
          .approveBuilderAfterFunding();
      if (!mounted) return;
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final l10n = context.l10n;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '\$${(result.amountIn.toDouble() / 1e6).toStringAsFixed(2)}',
        fromWalletName: l10n.assetDollars,
        toWalletName: l10n.trading,
        assetIconAsset: 'lib/assets/hyperliquid-logo.svg',
        note: result.registered
            ? l10n.moveConversionOngoing
            : l10n.settlementRegistering,
      );
    } catch (e) {
      if (_stoppedByApproval(e, SensitiveAction.venueDeposit)) {
        return;
      }
      // Fixed category only; completion comes from the settlement
      // reconciler's terminal signal.
      TrackingService.hyperliquidDepositFailed(
        reason: TrackingService.errorCategory(e),
        amountUsd: usd,
        route: 'direct',
        walletKind: 'hot',
      );
      _trackMoveFailed(e);
      if (!mounted) {
        return;
      }
      final message = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = message;
      });
    }
  }

  /// Funding stays on HyperCore. An unavailable route never redirects funds
  /// through an Arbitrum address or the retired gas-paying relayer.
  Future<void> _dispatchBtcToHyperliquid(int requestedSats) async {
    if (_processing) return;
    var sats = requestedSats;
    final drain = _drainArmed;
    final btcRate = ref.read(selectedCurrencyProvider('USD')).toDouble();
    final approxUsd = (sats / 1e8) * btcRate;
    TrackingService.track('move_initiated', params: {
      'source_asset': 'btc',
      'dest_asset': 'trading',
      'amount_bucket': TrackingService.usdBucket(approxUsd),
      ...TrackingService.exactUsd('amount_usd', approxUsd),
      'provider': 'orchestra',
    });
    _trackMoveSubmitted();
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final direct = ref.read(sparkHypercoreFundingServiceProvider);
      await direct.ensureAvailable(deposit: true);
      if (drain) sats = await _sparkDrainSats();
      TrackingService.hyperliquidDepositInitiated(
        amountUsd: approxUsd,
        sourceAsset: 'btc',
        walletKind: 'hot',
        route: 'direct',
      );
      final result = await direct.depositFromSpark(
        registerInBackground: true,
        asset: SparkFundingAsset.bitcoin,
        amountBaseUnits: BigInt.from(sats),
        amountUsd: approxUsd,
        stepUp: _settlementStepUp(
          action: SensitiveAction.venueDeposit,
          asset: 'BTC',
          amountLabel: (auth) => _btcApprovalLabel(auth.amountIn.toInt()),
          amountUsd: approxUsd,
        ),
      );
      // Same as the dollar-funded deposit above: register the builder
      // now that the venue has funds to sign against.
      // ignore: discarded_futures
      ref
          .read(hyperliquidTradingProvider.notifier)
          .approveBuilderAfterFunding();
      if (!mounted) return;
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final settings = ref.read(settingsProvider);
      final l10n = context.l10n;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount:
            '₿${result.amountIn.toInt().toFormattedString(settings.btcFormat)}',
        fromWalletName: settings.activeWallet?.name ?? l10n.spending,
        toWalletName: l10n.trading,
        assetIconAsset: 'lib/assets/hyperliquid-logo.svg',
        note: result.registered
            ? l10n.moveConversionOngoing
            : l10n.settlementRegistering,
      );
    } catch (e) {
      if (_stoppedByApproval(e, SensitiveAction.venueDeposit)) {
        return;
      }
      TrackingService.hyperliquidDepositFailed(
        reason: TrackingService.errorCategory(e),
        amountUsd: approxUsd,
        route: 'direct',
        walletKind: 'hot',
      );
      _trackMoveFailed(e);
      if (!mounted) {
        return;
      }
      final message = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = message;
      });
    }
  }

  /// The Investing cash-out. One dispatch, two destinations: the
  /// spending account's bitcoin (the default and the untouched path) or
  /// its dollars, picked on the To row. Only the Spark asset the
  /// withdrawal is pointed at changes — same HyperCore source, same
  /// [SensitiveAction.venueWithdraw] grant, same runner.
  Future<void> _dispatchHyperliquidToBtc(double usd) async {
    if (_processing) return;
    final dollars = _destUsd;
    final drain = _drainArmed;
    // Every attempt starts on the direct route; `cctp` once it switched
    // to the Circle CCTP fallback. Sent on submitted and failed.
    var route = 'direct';
    final attemptClock = Stopwatch();
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final direct = ref.read(sparkHypercoreFundingServiceProvider);
      await direct.ensureAvailable(deposit: false);
      if (drain) {
        // 100%: everything the account holds now, read fresh, not the
        // cent-floored snapshot on screen: perpetuals, builder-DEX and
        // spot cash together. The withdrawal sends all of it, each pool
        // read exactly and floored only to the six-decimal unit the
        // usdSend and the spot top-up move; a usdSend charges the source
        // nothing on top, so nothing else is held back.
        final fresh = await ref.refresh(hyperliquidAccountProvider.future);
        usd = hypercoreSendableUsdc(fresh.withdrawable, fresh.spotBalances);
        if (!usd.isFinite || usd < _kMinUsdc) {
          throw context.l10n.insufficientBalance;
        }
      }
      final account = await ref.read(hyperliquidAddressProvider.future);
      // Once per attempt: the CCTP fallback below does not send it again.
      TrackingService.hyperliquidWithdrawInitiated(
        amountUsd: usd,
        destination: dollars ? 'usd' : 'btc',
        walletKind: 'hot',
        purpose: 'manual_move',
      );
      attemptClock.start();
      _trackMoveSubmitted();
      SettlementStepUpHook stepUp() => _settlementStepUp(
            action: SensitiveAction.venueWithdraw,
            asset: 'USDC',
            account: account,
            amountLabel: (_) => _usdApprovalLabel(usd),
            amountUsd: usd,
          );
      try {
        await direct.withdrawToSpark(
          registerInBackground: true,
          usd: usd,
          destination:
              dollars ? SparkFundingAsset.dollars : SparkFundingAsset.bitcoin,
          stepUp: stepUp(),
        );
      } catch (e) {
        // Orchestra does not offer the HyperCore route (its catalog lists
        // no destination for it, or the quote refuses it; nothing signed):
        // to Dollars, Circle CCTP brings the cash home instead. A Bitcoin
        // withdrawal keeps the refusal ("isn't available right now").
        if (!dollars || !HyperCoreMoveRail.opensCctpFallback(e)) rethrow;
        route = 'cctp';
        TrackingService.hyperliquidWithdrawStep(
          step: 'cctp_fallback',
          durationMs: attemptClock.elapsedMilliseconds,
          amountUsd: usd,
        );
        await ref.read(hypercoreCctpWithdrawalProvider).withdrawToDollars(
            usd: usd, stepUp: stepUp(), purpose: 'manual_move');
      }
      // Handed to the runner (or the CCTP watcher); the real outcome is
      // reported by the settlement reconciler
      // (hyperliquid_withdraw_completed/failed).
      TrackingService.hyperliquidWithdrawSubmitted(
        amountUsd: usd,
        route: route,
        destination: dollars ? 'usd' : 'btc',
        walletKind: 'hot',
        purpose: 'manual_move',
      );
      if (!mounted) return;
      await _snapBeforeLeaving();
      if (!mounted) {
        _trackMoveCompleted();
        return;
      }
      final navigator = Navigator.of(context);
      final l10n = context.l10n;
      final name =
          ref.read(settingsProvider).activeWallet?.name ?? l10n.spending;
      navigator.pop();
      _trackMoveCompleted();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: '\$${usd.toStringAsFixed(2)}',
        fromWalletName: l10n.trading,
        toWalletName: dollars ? l10n.assetDollars : name,
        assetIconAsset: 'lib/assets/hyperliquid-logo.svg',
        note: l10n.moveConversionOngoing,
      );
    } catch (e) {
      if (_stoppedByApproval(e, SensitiveAction.venueWithdraw)) {
        return;
      }
      // A fixed category, never the error text.
      TrackingService.hyperliquidWithdrawFailed(
        reason: e is CctpUnavailable
            ? e.reason.code
            : TrackingService.errorCategory(e),
        route: route,
        amountUsd: usd,
        destination: dollars ? 'usd' : 'btc',
        walletKind: 'hot',
        purpose: 'manual_move',
      );
      _trackMoveFailed(e);
      if (!mounted) {
        return;
      }
      // The policy withholds `hyperliquid.withdraw` (the CCTP fallback
      // checks it before anything is signed): the shared capability
      // sheet, as the Investing withdraw door shows it.
      if (e is CctpUnavailable && e.decision != null) {
        setState(() => _processing = false);
        unawaited(showCapabilityDecisionSheet(context, e.decision!));
        return;
      }
      setState(() {
        _processing = false;
        _error = _moveFailure(e);
      });
    }
  }

  // ─── Fiat (bank transfer) handoffs ─────────────────────────────────

  String _fiatSymbol(String c) {
    switch (c) {
      case 'USD':
        return '\$';
      case 'CHF':
        return 'Fr';
      default:
        return '€';
    }
  }

  String _fiatFlag(String c) {
    switch (c) {
      case 'USD':
        return '\u{1F1FA}\u{1F1F8}';
      case 'CHF':
        return '\u{1F1E8}\u{1F1ED}';
      default:
        return '\u{1F1EA}\u{1F1FA}';
    }
  }

  /// The typed fiat amount, comma-tolerant. 0 when empty/unparseable.
  double get _typedFiatAmount =>
      double.tryParse(_typedFiatAmountController.text.replaceAll(',', '.')) ??
      0;

  /// Currency picker for the bank rail. Lists [_kBankFiatCurrencies]
  /// (EUR only for now); the pill that opens it is locked while the
  /// list has a single entry, so this only runs once more currencies
  /// return.
  void _showFiatCurrencyPicker() {
    HapticFeedback.selectionClick();
    // Same funnel event the deposit_type bank-transfer step fires — the
    // review flagged this picker as silently untracked.
    TrackingService.buyCurrencyPickerOpened();
    final c = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: _untintedColors(context).surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r))),
      builder: (ctx) => _untinted(
          ctx,
          SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Text(context.l10n.moveSelectCurrency,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w700)),
                ),
                for (final cur in _kBankFiatCurrencies)
                  ListTile(
                    leading:
                        Text(_fiatFlag(cur), style: TextStyle(fontSize: 22.sp)),
                    title: Text(cur,
                        style:
                            TextStyle(color: c.textPrimary, fontSize: 16.sp)),
                    trailing: _fiatCurrency == cur
                        ? Icon(Icons.check, color: c.accent)
                        : null,
                    onTap: () {
                      setState(() => _fiatCurrency = cur);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
          )),
    );
  }

  /// The wallet a fiat deposit would credit: the savings wallet the
  /// Buy bitcoin door was opened for, or null for the spending account.
  /// The destination is the door's own, never picked on the sheet.
  String? get _effectiveFiatDestWalletId => widget.fiatDepositWalletId;

  /// The COLD wallet a fiat buy is pointed at, or null when the buy
  /// credits the Spark spending pool. Cold = hardware, watch-only xpub,
  /// or tracked (external-address) wallet — everything whose funds live
  /// on plain on-chain bitcoin rather than Spark. When non-null:
  ///   * the To chip is pinned to that wallet (no destination switch),
  ///   * the Cash App onramp delivers ON-CHAIN (`destinationChain:
  ///     'bitcoin'`, catalog slug) to [_coldDestAddress] instead of the
  ///     Spark spending address,
  ///   * the pending row is scoped to that wallet's feed.
  /// Signers are excluded — they're air-gapped signing devices with no
  /// receive address.
  WalletConfig? get _fiatDestColdWallet {
    if (_destPredictions || _destHyperliquid || _buyingDollars) return null;
    final id = _effectiveFiatDestWalletId;
    if (id == null) {
      return null;
    }
    for (final w in ref.read(settingsProvider).wallets) {
      if (w.id != id) {
        continue;
      }
      final cold = !w.isSparkWallet && !w.isSigner;
      return cold ? w : null;
    }
    return null;
  }

  /// Resolves (and caches) the on-chain delivery address for the cold
  /// fiat-buy destination. Reuses [walletAddressProvider] — the exact
  /// resolver behind the wallet's own Receive screen: the stored
  /// tracked address for external-address wallets, BDK's idempotent
  /// `nextUnusedAddress` for hardware / watch-only xpub wallets.
  /// Returns null on failure; callers must block dispatch on null
  /// rather than falling back to the Spark spending address.
  Future<String?> _resolveColdDestAddress() async {
    final wallet = _fiatDestColdWallet;
    if (wallet == null) {
      return null;
    }
    if (_coldDestAddressWalletId == wallet.id &&
        (_coldDestAddress?.isNotEmpty ?? false)) {
      return _coldDestAddress;
    }
    if (_coldDestResolving) {
      return null;
    }
    _coldDestResolving = true;
    try {
      final addr = await ref.read(walletAddressProvider(wallet.id).future);
      if (addr.isEmpty) {
        return null;
      }
      if (mounted) {
        setState(() {
          _coldDestAddress = addr;
          _coldDestAddressWalletId = wallet.id;
        });
      } else {
        _coldDestAddress = addr;
        _coldDestAddressWalletId = wallet.id;
      }
      return addr;
    } catch (_) {
      return null;
    } finally {
      _coldDestResolving = false;
    }
  }

  /// True when the CTA should read "Deposit more" instead of Exchange:
  /// the typed amount is real but the source can't cover it. Dispatch
  /// is blocked in that state — the old behavior silently clamped to
  /// Max and converted the whole balance (user report: typed \$5,555
  /// with \$6 available and it drained the wallet).
  bool get _insufficientTyped =>
      !_isFiatMode &&
      _isSupportedSwap &&
      !_loadingRate &&
      !_processing &&
      _sourceBalanceState == null &&
      _typedExceedsAvailable;

  /// "Add funds" opens a buy door. Like every top-level Buy door it is
  /// drawn whatever the policy says about onramps; with none on offer
  /// the tap opens the "Buy unavailable" sheet ([_depositMore]).
  bool get _needsFunding =>
      !_isLedgerMove &&
      (_insufficientTyped ||
          (!_isFiatMode &&
              !_processing &&
              !_loadingRate &&
              _sourceBalanceState == null &&
              !_sourceHasFunds));

  /// Over-typed amount → the user needs outside money. Swap this sheet
  /// for the fiat-buy twin. The lock names the pool they were funding
  /// (analytics keep the intent), but the buy opens on the Cash App
  /// default, which demotes it to the plain "Buy bitcoin" (pools take
  /// funds from the spending wallet only), so the BTC lands in spending
  /// and they deposit onward from there. With no rail on offer it opens
  /// the "Buy unavailable" sheet instead and the move stays as it was.
  Future<void> _depositMore() async {
    HapticFeedback.selectionClick();
    // A refusal is asked again before "Buy unavailable" is shown.
    if (!_anyOnrampVisible &&
        !await confirmAnyOnrampVisible(ref.read(runtimeCapabilitiesProvider))) {
      if (mounted) showBuyUnavailableSheet(context);
      return;
    }
    if (!mounted) return;
    TrackingService.track('move_deposit_more_tapped', params: {
      'dest': _destPredictions
          ? 'predictions'
          : _destHyperliquid
              ? 'trading'
              : _buyingDollars
                  ? 'dollars'
                  : 'spending',
    });
    final lockedSide = _destPredictions
        ? MoveLockedSide.buyToPredictions
        : _destHyperliquid
            ? MoveLockedSide.buyToHyperliquid
            : MoveLockedSide.depositFromFiat;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DepositSheet(lockedSide: lockedSide),
      ),
    );
  }

  /// Compact USD label for the Flashnet band lines ("$1" / "$50,000").
  String _fmtUsdLimit(double v) {
    final whole = v == v.roundToDouble();
    final s = v.toStringAsFixed(whole ? 0 : 2);
    final parts = s.split('.');
    final digits = parts.first;
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buf.write(',');
      }
      buf.write(digits[i]);
    }
    return '\$$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  // ─── Cash App buy (Flashnet Lightning onramp) ─────────────────────
  //
  // Lifted from the retired standalone Cash App sheet so the buy lives
  // INSIDE the fiat buy flow: the sheet's own keypad drives the USD
  // amount, Continue creates the order and IMMEDIATELY launches the
  // Cash App payment link (user decision: no intermediate handoff
  // page). The sheet then shows a quiet waiting state (spinner + stage
  // line + "Open Cash App again"); only when the link cannot launch
  // does the old handoff page (Open Cash App + BOLT11 QR + copy) render
  // as the fallback. The created order is recorded as a pending
  // 'Orchestra' exchange row, marked as a Cash App purchase with the
  // fiat paid, so background sync owns the pending→terminal transition
  // and its analytics and the activity feed renders it as
  // the actual destination; this sheet's 5s poll only drives the
  // on-screen stage. On success the shared success overlay's entrance
  // is the single moneySuccessFeedback choke point — the sheet never
  // fires the haptic itself.

  Future<String> _ledgerCashAppRecipient(
      CashAppDestination destination, String walletId) async {
    final identity = ref.read(ledgerIdentityProvider(walletId));
    if (identity == null || !identity.hasVerifiedEvm) {
      throw StateError('Set up this Ledger account before depositing.');
    }
    final eoa = identity.evmAddress!;
    final String recipient;
    if (destination == CashAppDestination.investing) {
      if (!ref.read(hyperliquidDepositsEnabledProvider)) {
        throw StateError('Investing deposits are temporarily unavailable.');
      }
      recipient = eoa;
    } else if (destination == CashAppDestination.predictions) {
      recipient = await ledgerCashAppPredictionsRecipient(
        eoa: eoa,
        reads: ref.read(ledgerPolymarketReadsProvider),
        deploy: (owner) => PolymarketOnboardingService()
            .deployDepositWallet(eoaAddress: owner),
      );
    } else {
      throw StateError('Choose a Ledger investing or predictions account.');
    }
    if (ref.read(ledgerIdentityProvider(walletId)) != identity) {
      throw StateError('The Ledger account changed. Please try again.');
    }
    return recipient;
  }

  Future<void> _createCashAppOnramp() async {
    final l10n = context.l10n;
    final usd = _typedFiatAmount;
    if (!_cashAppAmountValid || _processing) {
      return;
    }
    setState(() {
      _processing = true;
      _error = null;
      _cashAppUsd = usd;
    });
    // Pinned before any await: a Ledger venue deposit (the caller's venue
    // wallet, or a Ledger move switched to Cash App) delivers only to
    // that Ledger's verified venue account.
    final ledgerVenueWalletId = _cashAppLedgerVenueWalletId;
    if (_isLedgerMove && ledgerVenueWalletId == null) {
      return;
    }
    HapticFeedback.mediumImpact();
    TrackingService.cashAppBuyInitiated(amountUsd: usd);
    TrackingService.moneyFlowSubmitted('buy', props: _buyFlowInputs());
    _trackMoveSubmitted();
    // Once the provider created the order, a later throw (row write,
    // polling, launch) is not a failed purchase: the order is live and
    // background sync reports its real outcome.
    var orderCreated = false;
    try {
      // Capture the destination and durable stores before the request. Closing
      // this sheet must not discard an order the provider already created.
      final settings = ref.read(settingsProvider);
      final orderStore = ref.read(swapOrdersProvider.notifier);
      final transactionCache =
          ref.read(walletTransactionCacheProvider.notifier);
      final destination = _cashAppDestination;
      final ledgerIdentity = ledgerVenueWalletId == null
          ? null
          : ref.read(ledgerIdentityProvider(ledgerVenueWalletId));
      final destinationWalletId = destination.isVenue
          ? ledgerVenueWalletId ?? pickSpendingWallet(settings)?.id
          : _effectiveFiatDestWalletId ?? pickSpendingWallet(settings)?.id;
      final pause = ref.read(routePausePolicyProvider);
      if (ledgerVenueWalletId != null &&
          await pause.isPaused(PausableRoute.ledgerFunding)) {
        throw StateError('Ledger deposits are temporarily unavailable.');
      }
      if (destination == CashAppDestination.investing &&
          await pause.isPaused(PausableRoute.directHypercore)) {
        throw StateError('Investing deposits are temporarily unavailable.');
      }
      // Cold-wallet destination (Purchase from a hardware / watch-only
      // / tracked wallet): deliver ON-CHAIN to that wallet's own
      // address — 'bitcoin' is the catalog chain slug (see
      // orchestra_routes_model nativeChains). Never fall back to the
      // Spark spending address when the address can't be resolved:
      // block with a clear error instead.
      final coldWallet = _fiatDestColdWallet;
      final destinationChain = destination.chain;
      final String recipientAddress;
      if (ledgerVenueWalletId != null) {
        recipientAddress =
            await _ledgerCashAppRecipient(destination, ledgerVenueWalletId);
      } else if (destination == CashAppDestination.investing) {
        if (!ref.read(hyperliquidDepositsEnabledProvider)) {
          throw LocalizedError.from(appL10n(), (l) => l.moveInvestingDepositsUnavailable);
        }
        recipientAddress =
            await ref.read(hyperliquidAddressProvider.future) ?? '';
        if (recipientAddress.isEmpty) throw l10n.investingAccountNotReady;
      } else if (destination == CashAppDestination.predictions) {
        await ref.read(polymarketTradingProvider.future);
        await ref.read(polymarketTradingProvider.notifier).enableTrading();
        recipientAddress = ref
                .read(polymarketTradingProvider)
                .valueOrNull
                ?.proxyWalletAddress ??
            '';
        if (recipientAddress.isEmpty) {
          throw LocalizedError.from(appL10n(), (l) => l.movePredictionsWalletNotReady);
        }
      } else if (coldWallet != null) {
        final addr = await _resolveColdDestAddress();
        if (addr == null || addr.isEmpty) {
          throw l10n.coldWalletAddressUnavailable(coldWallet.name);
        }
        var deliveryAddress = addr;
        // P4.8 (O10): a Ledger destination confirms the delivery address
        // on the device before any order exists. Flag off keeps today's
        // flow byte for byte; other cold wallets never enter this branch.
        if (kLedgerCashAppAddressCheckEnabled && coldWallet.isLedger) {
          final checked = await _checkLedgerCashAppAddress(coldWallet,
              usd: usd, l10n: l10n);
          // Null: the purchase stops here. The sheet is already reset with
          // the typed amount kept, and no order was created.
          if (checked == null) {
            return;
          }
          deliveryAddress = checked;
        }
        recipientAddress = deliveryAddress;
      } else {
        recipientAddress = await ref.read(sparkSelfAddressProvider.future);
      }
      // Every leg that converts (the venues and the dollar balance) is
      // checked against the live catalogue before an order exists. A BTC
      // leg is the Lightning delivery itself and has nothing to convert.
      if (destination.deliversDollars) {
        final availability = await HotSettlement.availability(
            ref.read,
            RouteKey(
              fromChain: 'lightning',
              fromAsset: 'BTC',
              toChain: destination.chain,
              toAsset: destination.asset,
            ));
        if (!availability.isAvailable) {
          throw LocalizedError.from(appL10n(), (l) => l.moveDepositRouteUnavailable);
        }
      }
      if (ledgerVenueWalletId != null &&
          (ledgerIdentity == null ||
              ref.read(ledgerIdentityProvider(ledgerVenueWalletId)) !=
                  ledgerIdentity ||
              (_isLedgerMove && !_ledgerCashAppSourceValid))) {
        throw StateError('The Ledger account changed. Please try again.');
      }
      if (ledgerVenueWalletId == null &&
          destination.isVenue &&
          (destinationWalletId == null ||
              pickSpendingWallet(ref.read(settingsProvider))?.id !=
                  destinationWalletId)) {
        throw StateError('The account changed. Please try again.');
      }
      final fingerprint =
          '$destinationChain|${destination.asset}|$recipientAddress|${usd.toStringAsFixed(2)}';
      if (_cashAppRequestFingerprint != fingerprint) {
        _cashAppRequestFingerprint = fingerprint;
        _cashAppIdempotencyKey = OrchestraService.generateIdempotencyKey();
      }
      final res = await OrchestraService.createOnramp(
        idempotencyKey: _cashAppIdempotencyKey,
        destinationChain: destinationChain,
        destinationAsset: destination.asset,
        recipientAddress: recipientAddress,
        amountFiatUsd: usd.toStringAsFixed(2),
      );
      final created = res.data;
      if (created == null ||
          created.depositAddress.isEmpty ||
          (created.orderId.trim().isEmpty && created.quoteId.trim().isEmpty)) {
        throw res.error ?? l10n.purchaseFailed;
      }
      // The reply is checked before Cash App opens: a well-formed,
      // unexpired mainnet invoice for about the typed dollars, and links
      // that only open Cash App for that invoice. A refused reply leaves
      // the order unpaid to expire, and a retry asks for a fresh one.
      final VerifiedCashAppOnramp verified;
      try {
        verified = verifyCashAppOnramp(
          created,
          requestedUsd: usd,
          usdPerBtc: ref.read(selectedCurrencyProvider('usd')).toDouble(),
          now: DateTime.now(),
        );
      } on WalletGuardException catch (e) {
        _cashAppRequestFingerprint = null;
        _cashAppIdempotencyKey = null;
        TrackingService.orchestraQuoteRejected(
            flow: 'cashapp_buy',
            route: 'cashapp_usd>lightning_btc',
            reason: e.reason.code);
        rethrow;
      }
      final order = verified.order;
      orderCreated = true;
      // The order is live: payment happens in Cash App and background
      // sync reports the purchase even if this sheet closes first.
      _moveOutcome.handedOff('cashapp');
      TrackingService.cashAppPurchaseCreated(
          amountUsd: usd, destination: destination.name);
      TrackingService.moneyFlowStep('buy', 'order_created',
          props: _buyFlowInputs());
      await _recordCashAppPendingRow(order,
          destination: destination,
          fiatUsd: usd,
          deliveryAddress: recipientAddress,
          walletId: coldWallet?.id ?? destinationWalletId,
          orderStore: orderStore,
          transactionCache: transactionCache);
      if (ledgerVenueWalletId == null &&
          destination == CashAppDestination.investing &&
          destinationWalletId != null) {
        await HyperliquidOnboardingService.markEnabled(destinationWalletId);
      }
      _cashAppRequestFingerprint = null;
      _cashAppIdempotencyKey = null;
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingCashAppDestination = destination;
        _pendingCashAppLedgerWalletId = ledgerVenueWalletId;
        _cashAppSession.begin(order);
        _processing = false;
        _cashAppCopied = false;
        _cashAppLinkFallback = false;
      });
      _cashAppPoll?.cancel();
      _cashAppPoll = Timer.periodic(
          const Duration(seconds: 5), (_) => _pollCashAppStatus());
      // Deep link first: hand off to Cash App right away. The poll is
      // already running, so a payment made while the app is in the
      // background still resolves when the user comes back. If the OS
      // cannot open the link, drop to the in-app handoff page.
      final opened = await _launchCashAppLink(auto: true);
      if (!opened && mounted && _cashAppSession.isCurrent(order)) {
        setState(() => _cashAppLinkFallback = true);
      }
    } catch (e) {
      if (!orderCreated) {
        TrackingService.cashAppBuyFailed(
            amountUsd: usd, reason: 'creation_failed');
        TrackingService.moneyFlowError('buy', e);
        _trackMoveFailed(e);
      }
      if (!mounted) {
        return;
      }
      final msg = _moveFailure(e);
      setState(() {
        _processing = false;
        _error = msg;
      });
    }
  }

  /// P4.8 Cash App address check for a Ledger destination (O10, behind
  /// [kLedgerCashAppAddressCheckEnabled]).
  ///
  /// Reads the address and derivation index from [walletReceiveInfoProvider]
  /// (the same pair the Receive screen's device check uses) and returns the
  /// address to hand to `createOnramp`. When that address at that index is
  /// not the one the device last confirmed for this wallet, the Ledger must
  /// show and return exactly the same string first; the pair is then
  /// remembered per wallet.
  ///
  /// Returns null when the purchase must stop. The sheet is already reset
  /// (processing off, typed amount kept) and, for a mismatch or a failed
  /// device check, an error is shown. A cancel shows no error. Never falls
  /// back to an unverified address or to the Spark spending address.
  Future<String?> _checkLedgerCashAppAddress(
    WalletConfig wallet, {
    required double usd,
    required AppLocalizations l10n,
  }) async {
    void stop({String? error, String? failReason}) {
      if (failReason != null) {
        TrackingService.cashAppBuyFailed(amountUsd: usd, reason: failReason);
        TrackingService.moneyFlowError('buy', failReason);
        _trackMoveFailed(failReason, stage: 'address_check');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _processing = false;
        _error = error;
      });
    }

    ({String address, int index}) info;
    try {
      info = await ref.read(walletReceiveInfoProvider(wallet.id).future);
    } catch (_) {
      info = (address: '', index: 0);
    }
    if (!mounted) {
      return null;
    }
    if (info.address.isEmpty) {
      TrackingService.ledgerCashAppAddressCheckResult(result: 'unavailable');
      stop(
          error: l10n.coldWalletAddressUnavailable(wallet.name),
          failReason: 'ledger_address_unverified');
      return null;
    }
    // The address verified below is the one delivered to; keep the cached
    // resolution in step so the order fingerprint matches it.
    if (_coldDestAddress != info.address ||
        _coldDestAddressWalletId != wallet.id) {
      setState(() {
        _coldDestAddress = info.address;
        _coldDestAddressWalletId = wallet.id;
      });
    }

    final store = LedgerVerifiedAddressStore();
    final last = await store.read(wallet.id);
    if (last != null && last.matches(info.address, info.index)) {
      return info.address;
    }
    if (!mounted) {
      return null;
    }

    TrackingService.ledgerCashAppAddressCheckStarted(
        addressChanged: last != null);
    final result = await showLedgerVerifyAddressSheet(
      context,
      wallet: wallet,
      expectedAddress: info.address,
      addressIndex: info.index,
    );
    TrackingService.ledgerCashAppAddressCheckResult(
      result: result.outcome.name,
      failureCode: result.failureCode?.name,
    );
    // The Move sheet closed while the device check was open: create nothing.
    if (!mounted) {
      return null;
    }

    switch (result.outcome) {
      case LedgerAddressCheckOutcome.verified:
        try {
          await store.write(wallet.id,
              address: info.address, index: info.index);
        } catch (_) {
          // Not remembering only means the device is asked again next time.
        }
        if (!mounted) {
          return null;
        }
        return info.address;
      case LedgerAddressCheckOutcome.cancelled:
        // A cancel on the device is not a failure; it still ends the
        // purchase attempt, so the funnel gets its own terminal step.
        TrackingService.track('cashapp_buy_cancelled', params: {
          'venue': 'cashapp',
          'stage': 'ledger_address_check',
          'wallet_kind': 'ledger',
          'amount_bucket': TrackingService.usdBucket(usd),
          ...TrackingService.exactUsd('amount_usd', usd),
        });
        TrackingService.moneyFlowError('buy', 'user_cancelled');
        _trackMoveFailed('user_cancelled', stage: 'address_check');
        stop();
        return null;
      case LedgerAddressCheckOutcome.mismatch:
        stop(
            error: l10n.ledgerVerifyAddressMismatch,
            failReason: 'ledger_address_mismatch');
        return null;
      case LedgerAddressCheckOutcome.failed:
        stop(
            error: l10n.ledgerCashAppAddressNotVerified,
            failReason: 'ledger_address_unverified');
        return null;
    }
  }

  /// Records the order as a pending Orchestra exchange row — the same
  /// pending-deposit line every other Orchestra leg renders — so
  /// background sync's Orchestra poller owns the pending→terminal
  /// transition and Cash App purchase analytics even if the user closes this
  /// sheet. The backend owns provider order storage and actual fee accounting.
  Future<void> _recordCashAppPendingRow(
    OrchestraOnrampResponse order, {
    required double fiatUsd,
    required CashAppDestination destination,
    String? deliveryAddress,
    required String? walletId,
    required SwapOrdersNotifier orderStore,
    required WalletTransactionCacheNotifier transactionCache,
  }) async {
    final exchange = cashAppDepositOrder(
      order: order,
      destination: destination,
      recipient: deliveryAddress ?? '',
      fiatUsd: fiatUsd,
      walletId: walletId,
      createdAt: DateTime.now(),
    );
    await orderStore.addExchange(exchange);
    transactionCache.mergeSwapOrder(exchange);
    reportDiscoveredOrchestraOrder(exchange);
  }

  void _prepareNewCashAppPurchase() {
    if (_processing || !_cashAppSession.prepareNewPurchase()) {
      return;
    }
    TrackingService.cashAppNewPurchaseTapped(source: 'move_sheet');
    _cashAppPoll?.cancel();
    _cashAppPoll = null;
    setState(() {
      _cashAppCopied = false;
      _cashAppLinkFallback = false;
      _cashAppRequestFingerprint = null;
      _cashAppIdempotencyKey = null;
      _error = null;
    });
  }

  /// What the waiting screen shows, so a poll rebuilds only on a change.
  (bool, bool, bool) get _cashAppViewState => (
        _cashAppPaymentSeen,
        _cashAppWindowEnded,
        _cashAppSession.canOfferNewPurchase,
      );

  Future<void> _pollCashAppStatus({bool force = false}) async {
    final order = _cashAppOrder;
    if (order == null) {
      return;
    }
    final shown = _cashAppViewState;
    final data = await _cashAppSession.poll((id) async {
      final response = await OrchestraService.getStatus(id);
      return response.isSuccess ? response.data : null;
    }, force: force);
    if (data == null || !mounted || !_cashAppSession.isCurrent(order)) {
      return;
    }
    final mapped = cashAppExchangeStatus(data.status,
        paymentReceived: data.paymentReceived == true);
    if (!orchestraExchangeStatusIsTerminal(mapped)) {
      // Creating an onramp already sets processing; only confirmed
      // provider evidence proves the invoice was paid.
      if (_cashAppViewState != shown) {
        if (_cashAppPaymentSeen) {
          TrackingService.moneyFlowStep('buy', 'payment_detected',
              props: _buyFlowInputs());
        } else if (_cashAppWindowEnded) {
          TrackingService.moneyFlowStep('buy', 'window_ended',
              props: _buyFlowInputs());
        }
        setState(() {
          if (_cashAppPaymentSeen) {
            _cashAppLinkFallback = false;
          }
        });
      }
      return;
    }
    _cashAppPoll?.cancel();
    if (mapped == 'success') {
      // The recorded exchange row's poller reports cashapp_buy_completed.
      TrackingService.moneyFlowFinished('buy');
      _trackMoveCompleted(outcome: 'paid');
      final l10n = context.l10n;
      final destination = _pendingCashAppDestination ?? _cashAppDestination;
      final received = orchestraAmountToDouble(
          data.amountOut ?? order.estimatedOut, destination.asset,
          chain: destination.chain);
      final ledgerVenueWalletId = _pendingCashAppLedgerWalletId;
      if (ledgerVenueWalletId != null) {
        ref.invalidate(ledgerPmAccountProvider(ledgerVenueWalletId));
        ref.invalidate(ledgerHlAccountProvider(ledgerVenueWalletId));
      } else if (destination == CashAppDestination.predictions) {
        ref.read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();
      } else if (destination == CashAppDestination.investing) {
        ref.invalidate(hyperliquidAccountProvider);
      }
      // This route and the overlay share the root navigator; capture
      // it before popping.
      final nav = Navigator.of(context, rootNavigator: true);
      nav.pop();
      // The overlay's entrance fires moneySuccessFeedback (single
      // choke point). Background sync's poller fires the terminal
      // analytics on the recorded exchange row — nothing to
      // double-fire here.
      pushKuteSuccessOverlay(
        navigator: nav,
        overlay: KuteSuccessOverlay(
          icon: KuteIconSpec(
            assetImage: destination.icon,
            tintDisc: false,
          ),
          headlineLabel: destination.isVenue
              ? 'DEPOSIT RECEIVED'
              : destination == CashAppDestination.dollars
                  ? l10n.cashAppDollarsPurchased.toUpperCase()
                  : l10n.cashAppBitcoinPurchased.toUpperCase(),
          amount: '\$${_cashAppUsd.toStringAsFixed(2)}',
          // On-chain delivery names the cold wallet it went to; the
          // dollar balance and the default both live on the Spending
          // Account, so they share its line.
          subtitle: destination.isVenue
              ? '\$${received.toStringAsFixed(2)} added to ${destination.label}${ledgerVenueWalletId != null ? ' on Ledger' : ''}'
              : destination == CashAppDestination.dollars
                  ? l10n.moveAmountArrived('\$${received.toStringAsFixed(2)}')
                  : _fiatDestColdWallet != null
                      ? l10n.moveAmountSentWallet(
                          _btcApprovalLabel((received * 1e8).round()),
                          _fiatDestColdWallet!.name)
                      : l10n.moveAmountArrived(
                          _btcApprovalLabel((received * 1e8).round())),
          detail: ledgerVenueWalletId != null &&
                  destination == CashAppDestination.predictions
              ? context.l10n.moveLedgerMakeFundsAvailable
              : null,
          onDone: () => nav.pop(),
        ),
      );
    } else {
      // Terminal failure — back to the amount screen with the refund
      // note in the standard error banner. The user can retype and
      // Continue again (a retry creates a fresh order).
      final l10n = context.l10n;
      TrackingService.moneyFlowError('buy', 'settlement');
      _trackMoveFailed('settlement', stage: 'settlement');
      setState(() {
        _cashAppSession.clear();
        _cashAppLinkFallback = false;
        _error = '${l10n.purchaseFailed}. ${l10n.cashAppRefundNote}';
      });
    }
  }

  /// Launches the Cash App payment link in the external app and
  /// reports whether the OS accepted it. Tries the Cash App deep link
  /// first, then the short https link. A `launchUrl` that returns
  /// false or throws is the "cannot launch" signal; it is the reliable
  /// form of the canLaunchUrl check (canLaunchUrl needs manifest query
  /// entries on Android and reports false for links that open fine).
  /// [auto] is true for the launch Continue performs itself, false for
  /// the "Open Cash App again" action.
  Future<bool> _launchCashAppLink({required bool auto}) async {
    final order = _cashAppOrder;
    if (order == null) {
      return false;
    }
    if (_cashAppWindowEnded) {
      return false;
    }
    final link = order.paymentLinks.cashApp;
    final short = order.paymentLinks.shortUrl;
    // Only links verifyCashAppOnramp would keep: https on cash.app and
    // carrying no invoice but this order's.
    final targets = <String>[
      if (link.isNotEmpty) link,
      if (short.isNotEmpty && short != link) short,
    ].where((t) => isAllowedCashAppLink(t, order.depositAddress)).toList();
    var opened = false;
    for (final target in targets) {
      if (!_cashAppSession.isCurrent(order) || _cashAppWindowEnded) {
        return false;
      }
      final uri = Uri.tryParse(target);
      if (uri == null) {
        continue;
      }
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
      if (opened) {
        break;
      }
    }
    TrackingService.cashAppLinkLaunched(auto: auto, opened: opened);
    return opened;
  }

  void _copyCashAppInvoice() {
    if (_cashAppWindowEnded) {
      return;
    }
    final order = _cashAppOrder;
    if (order == null) {
      return;
    }
    final invoice = order.depositAddress;
    if (invoice.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: invoice));
    HapticFeedback.selectionClick();
    setState(() => _cashAppCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _cashAppSession.isCurrent(order)) {
        setState(() => _cashAppCopied = false);
      }
    });
  }

  /// Quiet in-sheet waiting state shown once Continue has launched
  /// Cash App: the amount, a small spinner with the stage line, and one
  /// small text action to relaunch the link. No QR and no copy button
  /// (user decision). A long press on the amount still copies the
  /// BOLT11 invoice for the rare pay-from-another-wallet case.
  Widget _cashAppFeeSummary() {
    final order = _cashAppOrder;
    final destination = _pendingCashAppDestination ?? _cashAppDestination;
    final cost = cashAppQuotedCost(
      destination: destination,
      amountIn: order?.amountIn ?? '',
      estimatedOut: order?.estimatedOut ?? '',
      fiatUsd: _cashAppUsd,
    );
    return MoneyFeeSummary(
        label: 'Estimated conversion cost',
        bitcoinFirst: false,
        sats: cost.sats,
        usd: cost.usd,
        state: cost.sats != null || cost.usd != null ? null : 'Not quoted',
        note: 'Cash App may charge additional fees.');
  }

  Widget _buildCashAppWaitingState() {
    final c = context.colors;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountScreenHeader(title: _sheetTitle),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // The amount leads; what it costs reads on the
                    // summary card below the status line.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _copyCashAppInvoice,
                      child: Text(
                        '\$${_cashAppUsd.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 44.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                        ),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_cashAppWindowEnded)
                          Icon(Icons.schedule_rounded,
                              size: 16.sp, color: c.textSecondary)
                        else
                          SizedBox(
                            width: 14.sp,
                            height: 14.sp,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _cashAppPaymentSeen
                                  ? _kCashAppGreen
                                  : c.textSecondary,
                            ),
                          ),
                        SizedBox(width: 8.w),
                        Flexible(
                          child: Text(
                            _cashAppWindowEnded
                                ? l10n.cashAppPaymentWindowEndedChecking
                                : _cashAppPaymentSeen
                                    ? l10n.purchaseProcessing
                                    : l10n.cashAppWaitingForApp,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_cashAppCopied) ...[
                      SizedBox(height: 6.h),
                      Text(
                        l10n.cashAppInvoiceCopied,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    SizedBox(height: 10.h),
                    TextButton(
                      // A manual relaunch that also fails means the
                      // device has no handler for the link: fall back
                      // to the handoff page so the user can still pay.
                      onPressed: () async {
                        if (_cashAppWindowEnded) {
                          TrackingService.cashAppEndedWindowStatusChecked();
                          await _pollCashAppStatus(force: true);
                          return;
                        }
                        final order = _cashAppOrder;
                        final opened = await _launchCashAppLink(auto: false);
                        if (!opened &&
                            mounted &&
                            order != null &&
                            _cashAppSession.isCurrent(order)) {
                          setState(() => _cashAppLinkFallback = true);
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: c.textSecondary,
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 6.h),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        _cashAppWindowEnded
                            ? l10n.cashAppCheckStatus
                            : l10n.cashAppOpenAgain,
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 20.h),
                    SizedBox(
                      width: double.infinity,
                      child: MoveSummaryCard(children: [_cashAppFeeSummary()]),
                    ),
                    // A payment sent just before the deadline may still be
                    // landing, so keep checking until the session rules it out.
                    if (_cashAppSession.canOfferNewPurchase) ...[
                      SizedBox(height: 12.h),
                      CustomButton(
                        text: l10n.cashAppCreateNewPurchase,
                        primaryColor: _kCashAppGreen,
                        textColor: Colors.white,
                        onPressed: _prepareNewCashAppPurchase,
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        l10n.cashAppPreviousPurchaseTracked,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: c.textSecondary, fontSize: 12.sp),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fallback handoff page, rendered only when the payment link could
  /// not be launched: Open Cash App button, BOLT11 QR for any Lightning
  /// wallet, copy invoice, and the poll's status line.
  Widget _buildCashAppHandoffPage() {
    final c = context.colors;
    final order = _cashAppOrder!;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmountScreenHeader(title: _sheetTitle),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 20.h),
                      Text(
                        '\$${_cashAppUsd.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 44.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      MoveSummaryCard(children: [_cashAppFeeSummary()]),
                      SizedBox(height: 16.h),
                      CustomButton(
                        text: l10n.openCashApp,
                        primaryColor: _kCashAppGreen,
                        textColor: Colors.white,
                        onPressed: () => _launchCashAppLink(auto: false),
                      ),
                      SizedBox(height: 20.h),
                      Text(
                        l10n.cashAppScanInvoice,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Center(
                        child: Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                          child: QrImageView(
                            data: order.depositAddress,
                            size: 168.w,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      Center(
                        child: AppTextButton(
                          text: _cashAppCopied
                              ? l10n.cashAppInvoiceCopied
                              : l10n.cashAppCopyInvoice,
                          onPressed: _copyCashAppInvoice,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14.sp,
                            height: 14.sp,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _cashAppPaymentSeen
                                  ? _kCashAppGreen
                                  : c.textSecondary,
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Flexible(
                            child: Text(
                              _cashAppPaymentSeen
                                  ? l10n.purchaseProcessing
                                  : l10n.cashAppWaitingPayment,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickLedgerDepositSource() async {
    if (_processing) return;
    final fromCashApp = _ledgerCashAppSourceValid;
    if (!fromCashApp && !(_fromBtc && _ledgerContextValid)) return;
    final predictions = _destPredictions;
    final source =
        await showLedgerDepositSourceSheet(context, predictions: predictions);
    if (!mounted || source == null || _processing) return;
    if (fromCashApp) {
      // Back from Cash App to the Ledger's own bitcoin: the device flow
      // takes over again with every one of its checks.
      if (source == LedgerDepositSource.bitcoin && _ledgerCashAppSourceValid) {
        TrackingService.track('move_ledger_funding_source_selected', params: {
          'source': source.name,
        });
        _switchToLedgerBitcoinSource(predictions: predictions);
      }
      return;
    }
    if (!_ledgerContextValid || source == LedgerDepositSource.bitcoin) {
      return;
    }
    TrackingService.track('move_ledger_funding_source_selected', params: {
      'source': source.name,
    });
    // Same sheet, new source. Opening a second Move sheet over this one
    // read as starting again rather than changing where the money comes
    // from.
    _switchToFiatVenueSource(source, predictions: predictions);
  }

  Future<void> _convertLedger() async {
    if (_processing ||
        !_ledgerContextValid ||
        _sourceBalanceState != null ||
        _typedExceedsAvailable) {
      return;
    }
    final walletId = widget.ledgerWalletId!;
    final sats = _selectedSats;
    // The USD keypad accepts cents. Parse those cents as integers so the
    // reviewed amount is exact and cannot follow a later balance refresh.
    final parts = _typedAmount.split('.');
    final whole = BigInt.tryParse(parts.first) ?? BigInt.zero;
    final cents = parts.length == 1
        ? BigInt.zero
        : (BigInt.tryParse(parts[1].padRight(2, '0')) ?? BigInt.zero);
    final decimals = _fromHyperliquid ? kHypercoreUsdcDecimals : 6;
    final units =
        (whole * BigInt.from(100) + cents) * BigInt.from(10).pow(decimals - 2);
    if (_fromBtc ? sats < _kMinSats : _selectedUsdcFromRatio < _kMinUsdc) {
      return;
    }
    setState(() {
      _ledgerMaximumAtReview = _fromBtc ? _ledgerMaximum : null;
      _processing = true;
      _error = null;
    });
    TrackingService.track('move_ledger_review_opened', params: {
      'direction': _fromBtc ? 'deposit' : 'withdraw',
      'venue':
          _destHyperliquid || _fromHyperliquid ? 'investing' : 'predictions',
    });
    TrackingService.moneyFlowStep('move', 'review', props: _moveFlowInputs());
    try {
      if (_destHyperliquid) {
        _moveOutcome.handedOff('ledger');
        final source = await showLedgerFundInvestingSheet(context,
            walletId: walletId,
            initialAmountSats: sats,
            autoStart: true,
            onSubmitted: _trackLedgerMoveSubmitted);
        if (mounted &&
            _ledgerContextValid &&
            source != null &&
            source != LedgerDepositSource.bitcoin) {
          // Back on this sheet with another source: nothing was handed off.
          _moveOutcome.clearHandoff();
          _switchToFiatVenueSource(source, predictions: false);
        }
      } else if (_destPredictions) {
        final account =
            await ref.read(ledgerPmAccountProvider(walletId).future);
        if (!mounted || !_ledgerContextValid) return;
        if (account.account?.kind == null ||
            account.account?.kind == PolymarketAccountKind.uncertain ||
            account.isReadOnly) {
          TrackingService.moneyFlowError('move', 'no_route');
          setState(() => _error = context.l10n.ledgerFundRouteUnavailable);
          _moveFailedFeedback();
          return;
        }
        final decision = await showLedgerPolymarketFundingExplainerSheet(
          context,
          direction: LedgerPmFundingDirection.toPredictions,
          requiresDeploy: account.account?.kind == PolymarketAccountKind.none,
        );
        if (!mounted || !_ledgerContextValid || decision == null) return;
        _moveOutcome.handedOff('ledger');
        await showLedgerFundPredictionsSheet(context,
            walletId: walletId,
            deployConfirmed: decision.deployConfirmed,
            initialAmountSats: sats,
            autoStart: true,
            onSubmitted: _trackLedgerMoveSubmitted);
      } else if (_fromHyperliquid) {
        _moveOutcome.handedOff('ledger');
        await showLedgerWithdrawInvestingSheet(context,
            walletId: walletId,
            initialAmountBaseUnits: units,
            autoStart: true,
            onSubmitted: _trackLedgerMoveSubmitted);
      } else {
        // With withdrawals off the sheet only explains; nothing is handed off.
        if (kLedgerPolymarketWithdrawEnabled) _moveOutcome.handedOff('ledger');
        await showLedgerWithdrawPredictionsSheet(context,
            walletId: walletId,
            amountBaseUnits: units,
            onSubmitted: _trackLedgerMoveSubmitted);
      }
    } catch (e) {
      // The device flow never opened: nothing was handed off.
      _moveOutcome.clearHandoff();
      TrackingService.moneyFlowError('move', e);
      if (mounted) setState(() => _error = context.l10n.ledgerErrorUnknown);
      _moveFailedFeedback();
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _ledgerMaximumAtReview = null;
          _resetTypedAmount();
        });
      }
    }
  }

  Future<void> _convert() async {
    // A fresh tap pulls a fresh band (a Retry after a stop included).
    if (!_processing) {
      _bandProgress = null;
      _bandOutcome = null;
    }
    // A Ledger context never reaches any hot-wallet or legacy dispatcher.
    if (_isLedgerMove) {
      // A Cash App source funds the Ledger's venue account through the
      // onramp; the BTC-source device flow keeps every Ledger check.
      if (_sourceCashApp) {
        if (_ledgerCashAppSourceValid) return _createCashAppOnramp();
        return;
      }
      return _convertLedger();
    }
    // Belt and braces with _insufficientTyped: never dispatch a clamped
    // "everything you have" conversion the user didn't type.
    if (_typedExceedsAvailable) {
      return;
    }
    if (_processing) {
      return;
    }
    // The balance this amount was just judged against, held for the
    // screen while the move spends it (see [_availableSatsAtSubmit]).
    // Only the source's own pool is read, so no other balance is woken;
    // outside money (Cash App, the bank) has no balance to hold.
    _availableSatsAtSubmit =
        !_isFiatMode && _fromBtc ? _liveAvailableSats : null;
    _availableUsdcAtSubmit =
        !_isFiatMode && !_fromBtc ? _liveAvailableUsdc : null;

    // Cash App source — the one LIVE fiat leg. Continue creates the
    // Flashnet onramp and the build swaps to the inline payment
    // handoff. Checked before the bank short-circuit below.
    if (_sourceCashApp) {
      return _createCashAppOnramp();
    }

    // Bank rails are coming soon — nothing executes and the CTA never
    // enables in fiat mode, so this is a defensive short-circuit.
    // Checked FIRST: fiat mode reuses `_fromBtc`/BTC state combos that
    // would otherwise fall into the branches below.
    if (_isFiatMode) {
      return;
    }

    // HyperCore → Bitcoin: send native USDC to Orchestra for Spark delivery.
    // Checked BEFORE the `_convertUsdToBtc` cashout gate below — both are
    // `!_fromBtc` USDC sources, but the HL withdrawable is a different pool
    // from the Predictions balance, so it must not fall through to the
    // Predictions → BTC path.
    if (_fromHyperliquid && _destAsset == 'btc' && _sourceWalletId == null) {
      final usd = _selectedUsdcFromRatio;
      if (usd < _kMinUsdc) {
        return;
      }
      return _dispatchHyperliquidToBtc(usd);
    }

    // Dollars → a venue. Checked BEFORE every `_fromBtc` branch below
    // and before the `!_fromBtc` cashout branches, which have always
    // meant "the Predictions balance". A dollar source is neither, so it
    // is resolved on its own flag and never falls through to a bitcoin
    // path: failing to deposit dollars must never spend bitcoin.
    if (_dollarsAreSource) {
      if (_sourceWalletId != null || _destWalletId != null) return;
      final usd = _selectedUsdcFromRatio;
      if (usd < _kMinUsdc) return;
      if (_destPredictions) return _dispatchUsdToPredictions(usd);
      if (_destHyperliquid) return _dispatchUsdToHyperliquid(usd);
      // Dollars → spending bitcoin, the buy-bitcoin door paid from a
      // balance instead of a card. Guarded on the destination being
      // NOTHING else first: a dollars-to-dollars leg is not a purchase,
      // and a fiat destination is the inert coming-soon screen.
      if (!_destUsd && !_destFiat && _destAsset == 'btc') {
        return _dispatchUsdToBtc(usd);
      }
      // No other destination accepts dollars yet. Stop rather than let
      // the matrix below pick a rail for an amount it would misread.
      return;
    }

    // BTC → Predictions: route via Orchestra (BTC → USDC.e) and fire
    // `wrapIncomingUsdcEToPusd()` so the rest state is pUSD per #170.
    // Only spending BTC supports this — Predictions takes bitcoin from
    // the spending wallet only, so a savings source has no route.
    if (_destPredictions && _fromBtc && _sourceWalletId == null) {
      final sats = _selectedSats;
      if (sats < _kMinSats) {
        return;
      }
      return _dispatchBtcToPredictions(sats);
    }

    // BTC → Dollars: the same Orchestra cross-asset leg, pointed at the
    // dollar asset on the wallet's own Spark address. Spending Bitcoin
    // only — a savings wallet has no PSBT path into this leg, and the
    // From picker never offers one on this door.
    if (_destUsd && _fromBtc && _sourceWalletId == null) {
      final sats = _selectedSats;
      if (sats < _kMinSats) {
        return;
      }
      return _dispatchBtcToUsd(sats);
    }

    // BTC → HyperCore: direct Orchestra deposit from the spending wallet.
    // Ledger funding uses its dedicated device-confirmed flow.
    if (_destHyperliquid && _fromBtc && _sourceWalletId == null) {
      final sats = _selectedSats;
      if (sats < _kMinSats) {
        return;
      }
      return _dispatchBtcToHyperliquid(sats);
    }

    // Predictions → Bitcoin Spending: USDC source + BTC dest + no
    // savings overrides + not a predictions-dest move = the
    // cashout direction. Routes through `_convertUsdToBtc` which
    // calls `withdrawUsdc(bridged: true)` — that helper unwraps pUSD
    // → USDC.e on the Safe internally, then forwards USDC.e to
    // Orchestra's deposit address for BTC delivery via Spark.
    //
    // Before this branch existed the Move button fell through to the
    // BTC → USDC path below (wrong direction) so the user tap did
    // effectively nothing — no unwrap, no send.
    if (!_fromBtc &&
        !_fromHyperliquid &&
        _destAsset == 'btc' &&
        _sourceWalletId == null &&
        _destWalletId == null &&
        !_destPredictions) {
      return _convertUsdToBtc();
    }

    // Every door is matched above. Anything else (a stray wallet id
    // outside a Ledger move, or a source with no destination) has no
    // route: it stops here with nothing sent. The sheet never moves money
    // to or from a savings wallet.
    setState(() => _error = context.l10n.routeUnavailableNothingSent);
    _moveFailedFeedback();
  }

  @override
  Widget build(BuildContext context) {
    // Money in is green, money out is red: the sheet wears the direction
    // of the move (user decision). Buying bitcoin and every deposit read
    // green; every withdrawal and cash-out reads red. The palette goes in
    // as a theme extension so shared children (header, keypad, route and
    // summary cards, fee summary, buttons) follow without being forked.
    // Captured before any tint goes in, so nested pickers can restore it.
    _moveBaseColors = context.colors;
    // Which onramps may show ([_cashAppVisible], [_bankRailAllowed])
    // follows the runtime policy live.
    ref.watch(runtimeCapabilitiesProvider);
    ref.watch(multiSourceMovesProvider);
    // Only the fiat Buy flow wears a colour (user decision); every other
    // move — venue deposits, withdrawals, cash-outs — stays neutral.
    if (!_isBuyFlow) return Builder(builder: _buildSheet);
    final side = sideTintForMoneyIn(true);
    final tinted = sideTintPalette(context.colors, side);
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: ThemeData.estimateBrightnessForColor(side),
        extensions: [
          ...Theme.of(context)
              .extensions
              .values
              .where((e) => e is! AppColorsExtension),
          tinted,
        ],
      ),
      child: Builder(builder: _buildSheet),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final c = context.colors;
    if (_isLedgerMove) {
      ref.watch(ledgerIdentityProvider(widget.ledgerWalletId!));
      ref.watch(walletBalanceCacheProvider);
      if (_fromHyperliquid || _destHyperliquid) {
        ref.watch(ledgerHlAccountProvider(widget.ledgerWalletId!));
      } else {
        ref.watch(ledgerPmAccountProvider(widget.ledgerWalletId!));
      }
      if (_fromBtc && !_processing) {
        ref.watch(ledgerMoveMaxProvider(widget.ledgerWalletId!));
      }
      if (!_ledgerMoveValid) {
        return Scaffold(
            backgroundColor: c.background,
            body: SafeArea(
              child: Padding(
                  padding: EdgeInsets.all(20.w),
                  child: Column(children: [
                    AmountScreenHeader(title: _sheetTitle),
                    SizedBox(height: 24.h),
                    Text(context.l10n.ledgerErrorDetailsChanged),
                  ])),
            ));
      }
    } else if (!_isFiatMode) {
      if (_fromBtc) {
        ref.watch(walletBalanceCacheProvider);
        if (_sourceWalletId == null) ref.watch(sparkBitcoinBalanceProvider);
      } else if (_dollarsAreSource) {
        ref.watch(usdBalanceProvider);
        if (_dollarsReachVenueCash) {
          // The last known figure is on screen at once; the venues are
          // read again in the background and the number follows.
          ref.watch(investmentsSpendableProvider);
          ref.watch(venueCashRefreshProvider);
        }
      } else if (_fromHyperliquid) {
        ref.watch(hyperliquidAccountProvider);
      } else {
        ref.watch(polymarketTradingProvider);
      }
    }
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final btcUnit = btcFormat == 'sats' ? 'sats' : 'BTC';
    // Cash App order in flight. Default: the quiet waiting state (the
    // link was launched straight from Continue). Fallback: the in-app
    // handoff page when the OS could not open the link. Success pops
    // the route and pushes the shared success overlay; failure drops
    // back to the amount screen with the standard error banner.
    if (_cashAppOrder != null) {
      // Rebuild when background sync records a payment for this order and
      // when the grace period ends, even if no poll response arrives.
      ref.watch(swapOrdersProvider.select(_cashAppSession.showsPaymentIn));
      ref.watch(cashAppDeadlinePassedProvider(_cashAppSession.expiresAt));
      ref.watch(
          cashAppDeadlinePassedProvider(_cashAppSession.newPurchaseOfferAt));
      return _cashAppLinkFallback &&
              !_cashAppWindowEnded &&
              !_cashAppPaymentSeen
          ? _buildCashAppHandoffPage()
          : _buildCashAppWaitingState();
    }

    // ── Fiat-mode entry state ───────────────────────────────────────
    // The keypad stays interactive and the live BTC estimate keeps the
    // screen honest, but fiat rails are coming soon: the CTA never
    // enables while a fiat side is selected, so no validity is
    // computed.
    int fiatEstSats = 0;
    if (_isFiatMode) {
      final fiatText = _typedFiatAmountController.text;
      fiatEstSats = _typedFiatAmount > 0
          ? ref.watch(
              inputToSatsProvider((amount: fiatText, currency: _fiatCurrency)))
          : 0;
    }

    // A zero source balance and a below-minimum amount cannot produce a
    // useful quote. Explain the actual state before starting fee requests.
    final String? feeInputState = _isFiatMode
        ? null
        : _sourceBalanceState ??
            (!_sourceHasFunds
                ? 'Add funds to continue'
                : _typedAmountValue <= 0
                    ? 'Enter an amount'
                    : _typedExceedsAvailable
                        ? 'Insufficient balance'
                        : (_fromBtc
                                ? _selectedSats <= 0
                                : _selectedUsdcFromRatio <= 0)
                            ? 'Choose a larger amount'
                            : null);

    // ── Non-fiat conversion + balance lines under the big number ────
    String? conversionLabel;
    // The From row: a state worth naming under the pool's name, and
    // what the source has to move on the right of the card.
    String? sourceState;
    String? availableValue;
    if (!_isFiatMode) {
      final settings = ref.read(settingsProvider);
      String walletName(String id) => settings.wallets
          .firstWhere((w) => w.id == id, orElse: () => settings.wallets.first)
          .name;
      final sourceName = _sourceWalletId != null
          ? walletName(_sourceWalletId!)
          : _dollarsAreSource
              ? context.l10n.assetDollars
              : _fromHyperliquid
                  ? 'Investing'
                  : !_fromBtc
                      ? 'Predictions'
                      : 'Spending';
      final destName = _destWalletId != null
          ? walletName(_destWalletId!)
          : _destHyperliquid
              ? 'Investing'
              : _destPredictions
                  ? 'Predictions'
                  : 'Spending';
      // Over-typed: name the problem (user report: a red "0 available"
      // read like a glitch, not a state).
      sourceState = _sourceBalanceState ??
          (_typedExceedsAvailable ? 'Insufficient balance' : null);
      // The balance itself, in dollars, the unit the amount is typed in
      // (a bitcoin source is valued at the sheet's own rate). Rounded
      // down, so the figure never promises a cent that is not there. A
      // balance that is still loading shows its state instead.
      if (_sourceBalanceState == null) {
        String dollars(double usd) =>
            '\$${((usd * 100).floor() / 100).toStringAsFixed(2)}';
        if (!_fromBtc) {
          // Buying bitcoin from Investments: the Max, what the purchase
          // can actually spend (held while a purchase spends it).
          availableValue = dollars(_availableUsdc);
        } else {
          final sats = _isLedgerMove ? _maxConvertibleSats : _availableSats;
          if (_usdPerBtc > 0) {
            availableValue = dollars((sats / 1e8) * _usdPerBtc);
          } else if (!_loadingRate) {
            // No rate to value it with: the sats are still true.
            availableValue = '${sats.toFormattedString(btcFormat)} $btcUnit';
          }
        }
      }
      if (!_loadingRate && _typedAmountValue > 0) {
        if (_fromBtc) {
          // BTC source aimed at a USD pool — the sats that leave the
          // source wallet. Ratio-derived (so an over-typed amount shows
          // the clamped number that will actually be sent); falls back
          // to a direct rate estimate below the dispatch minimum so the
          // line never reads "0" while the user is mid-typing.
          var sats = _selectedSats;
          if (sats <= 0 && _usdPerBtc > 0) {
            sats = (_typedAmountValue / _usdPerBtc * 1e8).round();
          }
          conversionLabel =
              context.l10n.moveAmountFrom(
                  '${sats.toFormattedString(btcFormat)} $btcUnit', sourceName);
        } else if (_dollarsAreSource || _destUsd) {
          // Dollars at either end: both sides are dollars, so there is
          // no second denomination to show. A sats line here would be a
          // bitcoin figure on a leg where no bitcoin moves.
          conversionLabel = null;
        } else {
          // USD source cashing out — the sats the destination receives.
          var sats = _selectedSatsOutput;
          if (sats <= 0 && _usdPerBtc > 0) {
            sats = (_typedAmountValue / _usdPerBtc * 1e8).round();
          }
          conversionLabel =
              context.l10n.moveAmountTo(
                  '${sats.toFormattedString(btcFormat)} $btcUnit', destName);
        }
      }
    }

    // The route card — where the money comes from (and, on a venue
    // cash-out, what it lands as).
    final routeCard = _DirectionToggle(
      // What the source has to move. Fiat has no in-app
      // balance except on the sell leg, where the spending
      // pool is the source.
      sourceAvailable: _isFiatMode
          ? (_destFiat
              ? '${_availableSats.toFormattedString(btcFormat)} $btcUnit'
              : null)
          : availableValue,
      sourceDetail: _isFiatMode ? null : sourceState,
      sourceDetailIsError: !_isFiatMode && _typedExceedsAvailable,
      // The available balance doubles as Max, so the balance you are
      // looking at is the one thing you have to tap to spend it all.
      onSourceAvailableTap:
          _isFiatMode || _processing || _sourceBalanceState != null
              ? null
              : () => _applyAmountPercent(1),
      // On the Ledger's bitcoin the picker's only other entry is Cash
      // App, so it opens only while the policy offers it.
      ledgerSourcePicker: _isLedgerMove &&
              !_processing &&
              ((_fromBtc && _cashAppVisible) || _sourceCashApp)
          ? _pickLedgerDepositSource
          : null,
      ledgerContext: _isLedgerMove,
      interactionDisabled: _processing,
      venueWalletName: (widget.ledgerWalletId ?? widget.venueWalletId) == null
          ? null
          : ref
              .read(settingsProvider)
              .wallets
              .where((wallet) =>
                  wallet.id == (widget.ledgerWalletId ?? widget.venueWalletId))
              .map((wallet) => wallet.name)
              .firstOrNull,
      fromBtc: _fromBtc,
      sourceWalletId: _sourceWalletId,
      predictionsDest: _destPredictions,
      hyperliquidDest: _destHyperliquid,
      usdDest: _destUsd,
      hyperliquidSource: _fromHyperliquid,
      dollarsSource: _dollarsAreSource,
      dollarsSourceAvailable: _dollarsSourceAllowed,
      fiatSource: _sourceFiat,
      cashAppSource: _sourceCashApp,
      lockedSide: _lockedSide,
      // Receive leads the Investments deposit's From picker: the dock's
      // Receive moved here (owner decision, October 2026). A venue door
      // or a Ledger move has no receive address to show.
      onPickReceive: _lockedSide == MoveLockedSide.depositToUsd &&
              !_isLedgerMove &&
              !_processing
          ? _openReceive
          : null,
      onSwap: () {
        HapticFeedback.selectionClick();
        if (_isLedgerMove) {
          setState(() {
            final investing = _destHyperliquid || _fromHyperliquid;
            _fromBtc = !_fromBtc;
            _fromHyperliquid = investing && !_fromBtc;
            _destHyperliquid = investing && _fromBtc;
            _destPredictions = !investing && _fromBtc;
            _lockedSide = investing
                ? (_fromBtc
                    ? MoveLockedSide.depositToHyperliquid
                    : MoveLockedSide.withdrawFromHyperliquid)
                : (_fromBtc
                    ? MoveLockedSide.depositToPredictions
                    : MoveLockedSide.withdrawFromPredictions);
            _pinLedgerEndpoints();
            _resetTypedAmount();
            _error = null;
          });
          TrackingService.track('move_ledger_direction_changed', params: {
            'direction': _fromBtc ? 'deposit' : 'withdraw',
          });
          return;
        }
        // Locked to Predictions → the swap button inverts the
        // exchange: withdraw (Predictions → BTC) <-> deposit
        // (BTC → Predictions). Re-apply the matching direction and
        // re-quote; the picker-locks follow `_lockedSide`.
        if (_lockedSide == MoveLockedSide.withdrawFromPredictions ||
            _lockedSide == MoveLockedSide.depositToPredictions) {
          setState(() {
            if (_lockedSide == MoveLockedSide.withdrawFromPredictions) {
              _lockedSide = MoveLockedSide.depositToPredictions;
              _fromBtc = true;
              _destPredictions = true;
            } else {
              _lockedSide = MoveLockedSide.withdrawFromPredictions;
              _fromBtc = false;
              _destPredictions = false;
            }
            _sourceWalletId = null;
            _destWalletId = null;
            // The cash-out's dollar destination is not a deposit
            // destination: the flip lands on bitcoin either way.
            _destUsd = false;
            _destAsset = 'btc';
            _resetTypedAmount();
          });
          return;
        }
        // Fiat side on → the flip inverts the exchange between
        // deposit (bank → Bitcoin) and withdraw (Bitcoin → bank),
        // mirroring the Predictions/Trading pairs. Both sides
        // stay the inert coming-soon screen.
        if (_isFiatMode) {
          // Both halves of this flip land on a bank side, so it is
          // dead while the bank rail is hidden.
          if (!_bankRailAllowed) return;
          setState(() {
            if (_sourceFiat || _sourceCashApp) {
              // → Withdraw to bank: From becomes spending BTC,
              // To becomes Bank account · Bank transfer. A Cash
              // App source flips the same way (there is no
              // "sell to Cash App" rail) and drops its pin.
              _lockedSide = MoveLockedSide.withdrawToFiat;
              _sourceFiat = false;
              _sourceCashApp = false;
              _destFiat = true;
              _fromBtc = true;
            } else {
              // → Deposit from bank: From becomes Bank account,
              // To back to the default deposit destination.
              _lockedSide = MoveLockedSide.depositFromFiat;
              _sourceFiat = true;
              _destFiat = false;
              _fromBtc = false;
            }
            // Both halves of the flip are BANK rails (there is
            // no "sell to Cash App"): the typed currency snaps
            // back to the bank default, dropping Cash App's USD
            // lock, and an amount typed in the other currency
            // is cleared with it.
            if (_fiatCurrency != _kBankFiatCurrencies.first) {
              _fiatCurrency = _kBankFiatCurrencies.first;
              _typedFiatAmountController.clear();
            }
            _error = null;
            // The flip shows the other coming-soon side.
            _trackFiatComingSoon();
            // Shared resets — match the initState branches for
            // both fiat locks. A surface/savings destination
            // picked on the deposit side can't carry into the
            // sell (it settles spending → bank only), and
            // flipping back restores the caller-resolved
            // default (fiatDepositWalletId wins again).
            _sourceWalletId = null;
            _destWalletId = null;
            _destAsset = 'btc';
            _destPredictions = false;
            _destHyperliquid = false;
            _fromHyperliquid = false;
            _resetTypedAmount();
          });
          return;
        }
        // Locked to Hyperliquid (Trading) → the swap button inverts
        // the exchange: withdraw (Trading → BTC) <-> deposit (BTC →
        // Trading), staying in this reversed Exchange UI. Mirrors
        // the Predictions withdraw↔deposit flip above; the
        // picker-locks and direction follow `_lockedSide`.
        if (_lockedSide == MoveLockedSide.withdrawFromHyperliquid ||
            _lockedSide == MoveLockedSide.depositToHyperliquid) {
          setState(() {
            if (_lockedSide == MoveLockedSide.withdrawFromHyperliquid) {
              _lockedSide = MoveLockedSide.depositToHyperliquid;
              _fromBtc = true;
              _fromHyperliquid = false;
              _destHyperliquid = true;
            } else {
              _lockedSide = MoveLockedSide.withdrawFromHyperliquid;
              _fromBtc = false;
              _fromHyperliquid = true;
              _destHyperliquid = false;
            }
            _sourceWalletId = null;
            _destWalletId = null;
            // As above: the flip never carries a dollar destination.
            _destUsd = false;
            _destAsset = 'btc';
            _destPredictions = false;
            _resetTypedAmount();
          });
          return;
        }
      },
      onPickSpendingBitcoin: () {
        HapticFeedback.selectionClick();
        setState(() {
          _sourceWalletId = null;
          _fromBtc = true;
          _fromHyperliquid = false;
          _sourceUsd = false;
          _sourceFiat = false;
          _sourceCashApp = false;
          _resetTypedAmount();
        });
        _refreshSelectedFundingRoute();
      },
      onPickCashApp: () {
        // The row is not drawn while the policy withholds Cash App; a
        // stale callback can't pick it either.
        if (!_cashAppVisible) return;
        HapticFeedback.selectionClick();
        TrackingService.addFundsMethodSelected(
            method: 'cashapp', source: 'move_sheet');
        // Cold-wallet buy context (Purchase from a hardware /
        // tracked wallet) KEEPS that destination — the onramp
        // delivers on-chain to it. Computed BEFORE the flags
        // mutate below.
        final coldDest = _fiatDestColdWallet != null;
        _startBuyFlow('move_source_picker');
        setState(() {
          // Payment source changes never replace the chosen destination.
          _sourceCashApp = true;
          _sourceFiat = false;
          _destFiat = false;
          _sourceWalletId = null;
          _fromBtc = false;
          _fromHyperliquid = false;
          _fiatCurrency = 'USD';
          if (!coldDest) _destWalletId = null;
          _destAsset = 'btc';
          _error = null;
          _typedFiatAmountController.clear();
          _resetTypedAmount();
        });
        _fetchCashAppLimits();
        if (coldDest) {
          // ignore: discarded_futures
          _resolveColdDestAddress();
        }
      },
      onPickDollarsSource: () {
        if (!_dollarsSourceAllowed) return;
        HapticFeedback.selectionClick();
        TrackingService.track('move_source_dollars_selected', params: {
          'locked_side': _lockedSide.name,
        });
        setState(() {
          // A dollar source rides with `_fromBtc == false` so the amount
          // is read as USD, and clears every other source outright:
          // `_dollarsAreSource` demands all of this, so a half-set state
          // simply turns the door off rather than paying from the wrong
          // pool.
          _sourceUsd = true;
          _fromBtc = false;
          _fromHyperliquid = false;
          _sourceFiat = false;
          _sourceCashApp = false;
          _sourceWalletId = null;
          _destWalletId = null;
          _destAsset = 'btc';
          _error = null;
          _resetTypedAmount();
        });
      },
      onPickWithdrawDestination: ({required bool dollars}) {
        // Only the two cash-outs draw this row, and only they may set the
        // flag: re-checking the lock here means a stale callback can
        // never point a deposit at the dollar rail.
        if (!_isVenueWithdraw || dollars == _destUsd) return;
        HapticFeedback.selectionClick();
        TrackingService.track('move_withdraw_destination_selected', params: {
          'locked_side': _lockedSide.name,
          'dest_asset': dollars ? 'usd' : 'btc',
        });
        setState(() {
          // The destination asset is the ONE thing this changes. The
          // source stays pinned to the venue, the amount stays typed in
          // dollars either way, and `_destAsset` keeps its own meaning
          // ('btc' | 'usdc') untouched.
          _destUsd = dollars;
          _error = null;
        });
      },
    );

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // X close + operation title. Title tracks the live direction
              // + surface (user decision: "Exchange" told you nothing about
              // where the money was going). See [_sheetTitle] — it reads
              // the lock AND the unlocked From/To flags so a swap into a
              // Predictions withdraw reads "Withdraw from Polymarket",
              // fiat reads "Buy/Sell bitcoin", etc.
              AmountScreenHeader(title: _sheetTitle),
              SizedBox(height: 16.h),
              // ── Middle: the one big typed number ─────────────────────
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isFiatMode)
                          // Typed fiat amount (fiat has no in-app balance,
                          // so the number is what a bank leg would move).
                          // Currency selector rides next to the number;
                          // the live BTC estimate sits beneath.
                          BigAmountDisplay(
                            prefix: _fiatSymbol(_fiatCurrency),
                            amountText: _typedFiatAmountController.text,
                            // The sats estimate only where the purchase
                            // lands in bitcoin: a buy into a venue or the
                            // Dollars arrives in dollars, and its fee
                            // block states what arrives.
                            conversionLabel: !_destHyperliquid &&
                                    !_destPredictions &&
                                    !_destUsd &&
                                    fiatEstSats > 0
                                ? (_destFiat
                                    ? 'Sells ≈ ${fiatEstSats.toFormattedString(btcFormat)} $btcUnit'
                                    : '≈ ${fiatEstSats.toFormattedString(btcFormat)} $btcUnit')
                                : null,
                            // The available balance reads on the From
                            // row of the route card, not twice.
                            trailing: AmountCurrencyPill(
                              flag: _fiatFlag(_fiatCurrency),
                              code: _fiatCurrency,
                              // Cash App settles USD fiat only (the
                              // Flashnet onramp is USD-denominated) —
                              // the currency is locked there. The bank
                              // rail is locked too while it offers a
                              // single currency (EUR for now).
                              onTap: (_processing ||
                                      _sourceCashApp ||
                                      _kBankFiatCurrencies.length < 2)
                                  ? null
                                  : _showFiatCurrencyPicker,
                            ),
                          )
                        else
                          BigAmountDisplay(
                            prefix: '\$',
                            amountText: _typedAmount,
                            loading: _loadingRate,
                            conversionLabel: conversionLabel,
                            // The available balance reads on the From
                            // row of the route card, not twice.
                          ),
                        // One quiet caption line under the big number,
                        // only when there is something to act on: the
                        // Flashnet band edge the typed Cash App amount
                        // broke, or the bank rail's coming-soon line. An
                        // in-band Cash App amount shows no caption (user
                        // decision: no explanatory copy under the amount).
                        if (_isFiatMode)
                          Builder(builder: (context) {
                            final l10n = context.l10n;
                            String? caption;
                            var over = false;
                            if (_sourceCashApp) {
                              final usd = _typedFiatAmount;
                              if (usd > _cashAppMaxFiat) {
                                over = true;
                                caption = l10n.cashAppMaxPerOrder(
                                    _fmtUsdLimit(_cashAppMaxFiat));
                              } else if (usd > 0 && usd < _cashAppMinFiat) {
                                caption = l10n.cashAppMinPerOrder(
                                    _fmtUsdLimit(_cashAppMinFiat));
                              }
                            } else {
                              caption = context.l10n.moveBankComingSoon;
                            }
                            if (caption == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: EdgeInsets.only(top: 10.h),
                              child: Text(
                                caption,
                                style: TextStyle(
                                  color: over
                                      ? AppColors.marketDown
                                      : c.textSecondary,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            );
                          }),
                        // A Buy bitcoin with venue cash: its steps, each
                        // leg on its own line, the purchase, the arrival.
                        if (_stepsMoveId != null && _error == null)
                          Consumer(builder: (context, ref, _) {
                            final move = ref
                                .watch(multiSourceMovesProvider)
                                .where((m) => m.id == _stepsMoveId)
                                .firstOrNull;
                            return move == null
                                ? const SizedBox.shrink()
                                : MoveStepsSection(
                                    move: move, followRows: false);
                          })
                        // Venue cash on its way home for a purchase,
                        // on the same quiet caption line.
                        else if (_pullProgress != null && _error == null)
                          Padding(
                            padding: EdgeInsets.only(top: 10.h),
                            child: Text(
                              _pullProgress!,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                        // A failure reads on the same quiet line as the
                        // fee, in the error ink: no tinted box on this
                        // screen. The button keeps its own state.
                        if (_error != null)
                          Padding(
                            padding: EdgeInsets.only(top: 10.h),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: AppColors.marketDown,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ),
                        // What the move costs, as one caption line under
                        // the amount ("Fee about $0.12"); nothing at all
                        // while there is no fee to speak of. Provider
                        // splits and the estimate caveats stay one tap
                        // inside. No arrival time: the sheet has no
                        // estimate of one to state.
                        MoneyFeeCaption(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                          if (!_isFiatMode &&
                              _isSupportedSwap &&
                              feeInputState != null)
                            MoneyFeeSummary(
                                state: feeInputState,
                                onRetry: (_isLedgerMove
                                        ? _sourceBalanceState != null &&
                                            feeInputState !=
                                                context.l10n.feeUiCalculating
                                        : feeInputState ==
                                            'Balance unavailable')
                                    ? _retrySourceBalance
                                    : null),
                          if (!_isFiatMode &&
                              !_isLedgerMove &&
                              _isSupportedSwap &&
                              feeInputState == null) ...[
                            if (!_fromHyperliquid && !_destHyperliquid)
                              OrchestraFeeSummary(
                                  bitcoinFirst: false,
                                  recipient: _estimateRecipientFor(
                                      _destPredictions
                                          ? 'polygon'
                                          : (_destUsd
                                              ? kOrchestraUsdChain
                                              : 'spark'),
                                      read: ref.watch),
                                  route: (
                                    fromChain: _sourceFeeChain,
                                    fromAsset: _sourceFeeAsset,
                                    toChain: _destHyperliquid
                                        ? 'hypercore'
                                        : (_destPredictions
                                            ? 'polygon'
                                            : (_destUsd
                                                ? kOrchestraUsdChain
                                                : 'spark')),
                                    toAsset: _destHyperliquid
                                        ? 'USDC'
                                        : (_destPredictions
                                            ? 'USDC.e'
                                            : (_destUsd
                                                ? kOrchestraUsdAssetCode
                                                : 'BTC')),
                                    amount: _fromBtc
                                        ? _selectedSats.toString()
                                        : doubleToOrchestraAmount(
                                            _selectedUsdcFromRatio,
                                            _sourceFeeAsset,
                                            chain: _sourceFeeChain),
                                  )),
                            if (_fromHyperliquid || _destHyperliquid)
                              MoveHyperliquidFees(
                                  deposit: _destHyperliquid,
                                  // A dollar-funded Investing deposit pays
                                  // out of the dollar balance, not out of
                                  // spending bitcoin, so the estimate has
                                  // to ask about the leg that will run.
                                  fromDollars: _dollarsAreSource,
                                  // The mirror on the withdraw side: a
                                  // cash-out into dollars prices the leg
                                  // that will run, not the bitcoin one.
                                  toDollars: _destUsd,
                                  sats: _selectedSats,
                                  usd: _selectedUsdcFromRatio,
                                  bitcoinFirst: false),
                          ],
                          // A Cash App purchase that lands in dollars (a
                          // venue or the Dollars): created as an onramp
                          // order, so estimated at the rule that order is
                          // charged, with the Kute fee and what arrives
                          // shown before Continue.
                          if (_sourceCashApp &&
                              _cashAppDestination.deliversDollars)
                            OrchestraFeeSummary(
                                bitcoinFirst: false,
                                onramp: true,
                                showReceive: true,
                                recipient: _estimateRecipientFor(
                                    _cashAppDestination.chain,
                                    read: ref.watch),
                                recipientPending: _estimateRecipientPending(
                                    _cashAppDestination.chain),
                                route: (
                              fromChain: 'lightning',
                              fromAsset: 'BTC',
                              toChain: _cashAppDestination.chain,
                              toAsset: _cashAppDestination.asset,
                              amount: fiatEstSats.toString(),
                            )),
                          if (_sourceCashApp &&
                              !_cashAppDestination.deliversDollars)
                            const MoneyFeeSummary(
                                label: 'Purchase fee',
                                state: 'Shown in Cash App'),
                        ])),
                        SizedBox(height: 18.h),
                        // No percent row and no To row (user decision):
                        // the destination is the sheet's own subject, so
                        // only the source needs picking. That leaves the
                        // amount and one From row, and a lot of space.
                        routeCard,
                      ],
                    ),
                  ),
                ),
              ),
              // ── Bottom, pinned: chips + keypad + CTA ─────
              // On every amount screen, in every state, so the layout
              // never jumps: dimmed while there is nothing to spend.
              AmountQuickChips(
                // Same gate as the available-balance tap: a share of
                // a balance that is still loading, or only a cached
                // fallback, is not a figure to send. Outside money
                // (Cash App, the bank) has no balance to wait for.
                enabled: !_processing &&
                    (_isFiatMode || _sourceBalanceState == null),
                chips: moveQuickAmountChips(
                  // The fiat screens type their own currency and spend
                  // outside money: fixed amounts, no Max.
                  amountIsUsd: true,
                  symbol: _isFiatMode ? _fiatSymbol(_fiatCurrency) : '\$',
                  withMax: !_isFiatMode,
                  maxLabel: context.l10n.max,
                  exceedsAvailable: _chipExceedsAvailable,
                  onDollars:
                      _isFiatMode ? _applyFiatAmountChip : _applyAmountDollars,
                  onPercent: _applyAmountPercent,
                ),
              ),
              SizedBox(height: 12.h),
              AmountKeypad(
                value: _isFiatMode
                    ? _typedFiatAmountController.text
                    : _typedAmount,
                // Dollars and the fiat screens type cents.
                maxDecimals: 2,
                enabled: !_processing,
                onChanged: (v) {
                  if (_isFiatMode) {
                    setState(() => _typedFiatAmountController.text = v);
                    _trackBuyAmountTyped();
                  } else {
                    _onTypedAmountChanged(v);
                  }
                },
              ),
              SizedBox(height: 12.h),
              // The rubber band (founder request, 15 October 2026): the
              // confirm is pulled from the tap until every leg of the move
              // is submitted, jumping forward as each phase arrives
              // (approval, quote, each leg sent), then snaps as the sheet
              // closes. It lets go quietly on a stop: a real failure's
              // soft tap is played once it has ([_moveFailedFeedback]),
              // and a declined approval plays none.
              RubberBandBusy(
                busy: _processing && _bandOn,
                enabled: _bandOn,
                progress: _bandProgress,
                outcome: _bandOutcome,
                expected: const Duration(seconds: 6),
                failureTap: false,
                child: _ConvertButton(
                  // Source-aware enable check. The slider's "amount picked"
                  // depends on which asset is on the From side; the getters
                  // already gate on the per-asset minimum (`_kMinSats` /
                  // `_kMinUsdc`), so we just check that the source-side
                  // amount > 0.
                  //   - BTC source → _selectedSats
                  //   - USDC source → _selectedUsdcFromRatio
                  // Cash App source is the live fiat leg: Continue enables
                  // inside the Flashnet band and creates the onramp. Bank
                  // fiat NEVER enables — bank transfers are coming soon;
                  // the keypad stays interactive but the CTA holds its
                  // disabled style regardless of the typed amount.
                  enabled: _parallelPurchase != null &&
                          !_canRetryParallel(_parallelPurchase!)
                      ? false
                      : _sourceCashApp
                          ? (!_processing && _cashAppAmountValid)
                          : _isFiatMode
                              ? false
                              : _needsFunding ||
                                  (!_insufficientTyped &&
                                      _isSupportedSwap &&
                                      !_processing &&
                                      !_loadingRate &&
                                      (!_isLedgerMove ||
                                          _sourceBalanceState == null) &&
                                      (() {
                                        if (_fromBtc) {
                                          return _selectedSats >= _kMinSats;
                                        }
                                        return _selectedUsdcFromRatio >=
                                            _kMinUsdc;
                                      }())),
                  processing: _processing,
                  // Fiat mode keeps the familiar 'Continue' label in its
                  // permanently disabled state; the quiet line above the
                  // keypad explains why.
                  label: _isFiatMode
                      ? context.l10n.continueLabel
                      : !_isSupportedSwap
                          ? context.l10n.comingSoon2
                          : _retryPull && _error != null
                              ? context.l10n.retry
                          : _needsFunding
                              ? context.l10n.moveAddFunds
                              : (() {
                                  // The label states the action and the
                                  // source-side amount in USD ("Add $50"), so
                                  // the user reads the same "I'm moving $X"
                                  // across every direction.
                                  // Trading source (withdraw): the FROM amount,
                                  // the perp withdrawable is USDC.
                                  if (_fromHyperliquid &&
                                      _selectedUsdcFromRatio > 0) {
                                    return context.l10n.moveActionWithAmount(
                                        _actionVerb,
                                        moveButtonUsd(_selectedUsdcFromRatio));
                                  }
                                  if (_fromBtc && _selectedUsdOutput > 0) {
                                    return context.l10n.moveActionWithAmount(
                                        _actionVerb,
                                        moveButtonUsd(_selectedUsdOutput));
                                  }
                                  if (!_fromBtc && _selectedUsdcFromRatio > 0) {
                                    // Source is Predictions/USDC: the FROM
                                    // amount, whatever the destination.
                                    return context.l10n.moveActionWithAmount(
                                        _actionVerb,
                                        moveButtonUsd(_selectedUsdcFromRatio));
                                  }
                                  return _actionVerb;
                                }()),
                  onTap: _needsFunding ? _depositMore : _convert,
                ),
              ),
              SizedBox(height: 4.h),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a purchase's venue pull decided ([_DepositSheetState._pullVenueCashForPurchase]).
class _VenuePull {
  const _VenuePull(this.onwardUsd, {this.queued = false});

  /// What the purchase still takes from Dollars.
  final double onwardUsd;

  /// The purchase finishes in the background once what came home lands.
  final bool queued;
}

class _ConvertButton extends StatelessWidget {
  final bool enabled;
  final bool processing;
  final String label;
  final VoidCallback onTap;

  const _ConvertButton({
    required this.enabled,
    required this.processing,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: label,
      onPressed: enabled ? onTap : null,
      isLoading: processing,
    );
  }
}

class _DirectionToggle extends ConsumerWidget {
  final String? venueWalletName;
  final bool ledgerContext;
  final VoidCallback? ledgerSourcePicker;
  final bool interactionDisabled;
  final bool fromBtc;
  final String? sourceWalletId;

  /// What the From side has to move ("$124.50", "518 sats"), shown on
  /// the right of the card over the word "available". Null while the
  /// balance is not known.
  final String? sourceAvailable;

  /// A state of the From side worth naming under its name
  /// ("Insufficient balance", "Balance unavailable").
  final String? sourceDetail;

  /// Renders [sourceDetail] in the error color.
  final bool sourceDetailIsError;

  /// Tapping the available balance fills the maximum (owner decision:
  /// the balance IS the max button). Null leaves it as plain text.
  final VoidCallback? onSourceAvailableTap;

  /// Predictions destination flag — when on, the To chip renders the
  /// USDC disc + "Predictions" label and dispatch routes through the
  /// BTC → USDC.e → pUSD pipeline.
  final bool predictionsDest;

  /// Hyperliquid (Trading) destination flag — when on, the To chip
  /// renders the HL logo + "Trading" label and dispatch routes through
  /// the BTC → USDC(Arbitrum) → Hyperliquid onramp.
  final bool hyperliquidDest;

  /// Dollars destination flag. On the locked "Buy dollars" door it names
  /// the Cash App row's purpose. On the two cash-outs, which DO draw
  /// their To row, it is what that row renders and what the two-entry
  /// picker marks as selected.
  final bool usdDest;

  /// Hyperliquid (Trading) SOURCE flag — the reversed twin of
  /// [hyperliquidDest]. When on, the From chip renders the HL logo +
  /// "Trading" / "Balance" (USD) instead of the "Predictions" the plain
  /// `!fromBtc` state would otherwise show.
  final bool hyperliquidSource;

  /// Dollars SOURCE flag — the spending account's dollar balance paying a
  /// venue deposit. It rides with `!fromBtc`, which on its own has always
  /// meant the Predictions pool, so every From-side rendering test reads
  /// this first.
  final bool dollarsSource;

  /// Whether the Dollars tile is on offer in the From picker at all.
  /// True only on the two venue-deposit doors.
  final bool dollarsSourceAvailable;

  /// The bank rail is the source. The From chip renders the
  /// bank-transfer glyph + 'Bank account'. The rail is inert (coming
  /// soon).
  final bool fiatSource;

  /// Cash App is the buy SOURCE (live Flashnet onramp). The From chip
  /// renders the Cash App mark + 'Cash App' with no subtitle and the
  /// source picker keeps offering the bank rail to switch back.
  final bool cashAppSource;

  /// The door the sheet opened on (see [MoveLockedSide]).
  final MoveLockedSide lockedSide;
  final VoidCallback onSwap;

  /// Spending bitcoin picked as the source.
  final VoidCallback onPickSpendingBitcoin;

  /// Cash App picked as the buy source — the parent switches the sheet
  /// in place (USD, live onramp). Source side only, so no side flag.
  final VoidCallback onPickCashApp;

  /// The dollar balance picked as the source of a venue deposit. Source
  /// side only: dollars are a destination through their own door, never
  /// through this picker's To side.
  final VoidCallback onPickDollarsSource;

  /// What a venue cash-out delivers, picked on the To row of the two
  /// withdrawal doors: the spending account's dollars when `dollars` is
  /// true, its bitcoin (the default) when it is false.
  final void Function({required bool dollars}) onPickWithdrawDestination;

  /// Receive picked as the way in: the Dollars receive screen (an
  /// address for whatever coin is being sent, dollars land). Set on the
  /// Investments deposit door only; null draws no row.
  final VoidCallback? onPickReceive;

  const _DirectionToggle({
    this.venueWalletName,
    this.ledgerContext = false,
    this.ledgerSourcePicker,
    this.interactionDisabled = false,
    required this.fromBtc,
    required this.sourceWalletId,
    this.sourceAvailable,
    this.sourceDetail,
    this.sourceDetailIsError = false,
    this.onSourceAvailableTap,
    required this.predictionsDest,
    required this.hyperliquidDest,
    required this.usdDest,
    required this.hyperliquidSource,
    required this.dollarsSource,
    required this.dollarsSourceAvailable,
    required this.fiatSource,
    required this.cashAppSource,
    required this.lockedSide,
    required this.onSwap,
    required this.onPickSpendingBitcoin,
    required this.onPickCashApp,
    required this.onPickDollarsSource,
    required this.onPickWithdrawDestination,
    this.onPickReceive,
  });

  /// The two venue cash-outs. Their lock pins the SOURCE, so the To row
  /// is drawn and pickable here while every other lock hides it.
  bool get _isVenueWithdraw =>
      lockedSide == MoveLockedSide.withdrawFromPredictions ||
      lockedSide == MoveLockedSide.withdrawFromHyperliquid;

  /// True when BOTH ends of the move are pinned and the swap button has
  /// nothing valid to invert to — the buy-to-pool doors (From = Fiat ·
  /// Bank transfer, To = the pool). Every other locked flow either flips
  /// deposit<->withdraw or leaves one side pickable, so the button stays
  /// live there.
  bool get _swapLocked =>
      interactionDisabled ||
      cashAppSource ||
      fiatSource ||
      // A venue cash-out now draws its To row so the destination can be
      // picked. The flip is NOT part of that: inverting a withdrawal
      // into a deposit would walk past the deposit kill-switch the
      // deposit door is gated on, so the circle the row brings with it
      // stays dead.
      _isVenueWithdraw ||
      // Dollars pay a venue in one direction only: there is no
      // "withdraw a venue into dollars" leg to invert into, and a flip
      // that silently reverted the source to bitcoin would be worse
      // than a dead button.
      dollarsSource ||
      // Dollars are bought, not swapped back here: there is no
      // sell-dollars door to invert into.
      lockedSide == MoveLockedSide.depositToUsd ||
      lockedSide == MoveLockedSide.buyToPredictions ||
      lockedSide == MoveLockedSide.buyToHyperliquid;

  /// Whether the dollar balance's own rows wear the USDB coin
  /// ([kUsdMarkAsset]) in place of the Investments arrow: on the
  /// buy-bitcoin door (Dollars → Bitcoin), where the balance is the
  /// money paying, the way the Investments deposit door wears it. The
  /// withdraw and send rows elsewhere keep the arrow.
  bool get _dollarsWearCoin => lockedSide == MoveLockedSide.depositFromFiat;

  /// The From picker, the only side picker left: every door pins its
  /// destination. It opens on the venue deposits, the Dollar deposit and
  /// the buy doors (the withdrawals pin their source, a Ledger move has
  /// its own source sheet).
  void _openSourcePicker(BuildContext context) {
    if (interactionDisabled || ledgerContext) return;
    HapticFeedback.selectionClick();
    // Locked fiat BUY doors (Buy bitcoin / buy-to-pool): the From side
    // is a PAYMENT METHOD choice only — Bank account or Cash App —
    // never a wallet or a surface.
    final paymentMethodsOnly = lockedSide == MoveLockedSide.depositFromFiat ||
        lockedSide == MoveLockedSide.buyToPredictions ||
        lockedSide == MoveLockedSide.buyToHyperliquid;
    // Cash App is the one live fiat rail, listed only while the policy
    // offers it: a withheld onramp is not shown at all (founder decision,
    // October 2026, replacing September's disabled tile). One answer
    // for the hint and the row, read from the open picker's own watch so
    // the list follows the policy live. Every door this picker opens on
    // takes a payment rail as its source.
    bool cashAppOffered(RuntimeCapabilitiesService policy) =>
        onrampVisible(policy, kOnrampCashApp);
    // Hint under the picker title, naming only what this picker really
    // offers.
    String pickerHint(bool cashAppListed) {
      if (paymentMethodsOnly) {
        // No rail on offer: the dollar balance is all this picker lists,
        // so the hint names it rather than promising ways to pay.
        if (!cashAppListed) {
          return dollarsSourceAvailable
              ? context.l10n.moveHintFrom(context.l10n.assetDollars)
              : context.l10n.depositPickHowYouWantToPay;
        }
        // The dollar balance rides in this picker too, so the hint names
        // it rather than promising payment methods and then showing a
        // balance.
        return dollarsSourceAvailable
            ? context.l10n.movePickPayOrDollars
            : context.l10n.depositPickHowYouWantToPay;
      }
      final options = <String>[
        context.l10n.moveHintAWallet,
        if (dollarsSourceAvailable) context.l10n.assetDollars,
        if (cashAppListed) 'Cash App',
      ];
      final list = options.length == 1
          ? options.first
          : options.length == 2
              ? context.l10n.moveHintTwo(options.first, options.last)
              : context.l10n.moveHintMany(
                  options.sublist(0, options.length - 1).join(', '),
                  options.last);
      return context.l10n.moveHintFrom(list);
    }

    // The Investments deposit reads as what it is, adding money to
    // Investments: your own bitcoin first, with what it holds, then a
    // way in from outside (owner decision, October 2026: "Move from" over
    // a "Receive" row read as moving money out of a receive screen).
    final investmentsDeposit =
        lockedSide == MoveLockedSide.depositToUsd && !ledgerContext;
    final spendingSubtitle = investmentsDeposit
        ? (fromBtc && sourceAvailable != null
            ? context.l10n.depositFromSpendingWalletWithBalance(
                sourceAvailable!)
            : context.l10n.depositFromSpendingWallet)
        : context.l10n.spending;
    _showPickerSheet(
      context,
      // Contextual to the action: a fiat buy reads "Buy from", the
      // Investments deposit reads "Add money to Investments", every
      // other door reads "Move from". (User: "it's a Buy not a Move.")
      title: investmentsDeposit
          ? context.l10n.addMoneyToInvestments
          : (fiatSource || cashAppSource)
              ? context.l10n.moveBuyFrom
              : context.l10n.moveMoveFrom,
      // The rows say it all on the Investments deposit: no hint.
      hint: (policy) =>
          investmentsDeposit ? '' : pickerHint(cashAppOffered(policy)),
      rows: (sheetCtx, policy) => [
        // Spending bitcoin: the venue deposits and the Dollar deposit.
        // Their other side is a venue or the dollars, never spending
        // bitcoin itself, so the row is never "in use".
        if (!paymentMethodsOnly)
          MovePickerRow(
            asset: 'lib/assets/bitcoin-icon.svg',
            title: 'Bitcoin',
            subtitle: spendingSubtitle,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onPickSpendingBitcoin();
            },
          ),
        // Another wallet or exchange, under the bitcoin, on the
        // Investments deposit door only: the Dollars receive screen the
        // dock's Receive used to open. It wears the dock's inflow arrow;
        // it is a way in, not a source to pay from, so it never reads
        // "selected".
        if (onPickReceive != null)
          MovePickerRow(
            icon: Icons.south_west_rounded,
            title: context.l10n.depositFromAnotherWallet,
            subtitle: context.l10n.depositFromAnotherWalletSubtitle,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onPickReceive!();
            },
          ),
        // Dollars as a SOURCE. Offered on the two venue-deposit doors
        // and the buy-bitcoin door: the money leaves as the dollar token
        // and Orchestra converts it into what the door is buying, the
        // same leg the Bitcoin tile above rides.
        //
        // It survives `paymentMethodsOnly`, and it is the one row that
        // does. That mode exists to keep wallets and pools out of a BUY,
        // where the question is how you pay; a dollar balance is an
        // answer to that question, and it is the only instant one while
        // the bank rail is dark. `dollarsSourceAvailable` still decides
        // which doors see it, so the buy-to-pool doors (which are the
        // same mode) keep the payment rails only.
        if (dollarsSourceAvailable)
          MovePickerRow(
            // Paying for bitcoin out of the Investments balance (the buy
            // door), the row wears the USDB coin: the money is the coin
            // itself. Everywhere else the dollar balance as a source or
            // destination row wears the Investments arrow (the Home
            // deposit button's icon).
            asset: _dollarsWearCoin ? kUsdMarkAsset : null,
            icon: _dollarsWearCoin ? null : kInvestmentsIcon,
            title: context.l10n.assetDollars,
            subtitle: context.l10n.moveSourceDollarsSubtitle,
            // Already the chosen source: SELECTED, not dead.
            disabled: dollarsSource,
            disabledLabel: context.l10n.moveSelectedBadge,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onPickDollarsSource();
            },
          ),
        // The bank row is not drawn. It was a permanently disabled
        // "Coming soon" entry, which is a row that takes up space in a
        // picker and answers no to every tap. Restoring it is a row
        // behind `onrampVisible(policy, kOnrampBank)` like the Cash App
        // row, plus a pick handler that seeds `_sourceFiat`.
        // Cash App is a payment source for Bitcoin, the venue
        // deposits and the dollar balance ([CashAppDestination.dollars]
        // delivers the dollar asset itself). Withheld by the policy, it
        // is not drawn at all ([cashAppOffered]).
        if (cashAppOffered(policy))
          MovePickerRow(
            asset: 'lib/assets/cashapp-logo.svg',
            title: 'Cash App',
            subtitle: (predictionsDest || hyperliquidDest)
                ? context.l10n.deposit
                : usdDest
                    ? context.l10n.dollarDeposit
                    : context.l10n.moveBuyBitcoin,
            // The method already in use is SELECTED, not
            // disabled. On the buy flow it is usually the
            // only live rail, and marking it "IN USE" left a
            // chooser where every row was dead and nothing
            // explained why.
            disabled: cashAppSource,
            disabledLabel: context.l10n.moveSelectedBadge,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              onPickCashApp();
            },
          ),
      ],
    );
  }

  /// What a venue cash-out delivers: the spending account's bitcoin or
  /// its dollars. Two entries, because the choice is between two
  /// balances of one account — the wallets, pools and rails the full
  /// side picker offers have no part in a withdrawal's destination.
  void _openWithdrawDestinationPicker(BuildContext context) {
    if (interactionDisabled || ledgerContext) return;
    HapticFeedback.selectionClick();
    _showPickerSheet(
      context,
      title: context.l10n.moveMoveTo,
      hint: (_) => context.l10n.moveWithdrawDestinationHint,
      rows: (sheetCtx, _) => [
        MovePickerRow(
          asset: 'lib/assets/bitcoin-icon.svg',
          title: 'Bitcoin',
          subtitle: context.l10n.spending,
          // The one already chosen reads SELECTED, not dead — the same
          // treatment the Dollars source row wears.
          disabled: !usdDest,
          disabledLabel: context.l10n.moveSelectedBadge,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            onPickWithdrawDestination(dollars: false);
          },
        ),
        MovePickerRow(
          // The Investments arrow, as on every row the dollar balance
          // is a source or destination of.
          icon: kInvestmentsIcon,
          title: context.l10n.assetDollars,
          subtitle: context.l10n.moveDestDollarsSubtitle,
          disabled: usdDest,
          disabledLabel: context.l10n.moveSelectedBadge,
          onTap: () {
            Navigator.of(sheetCtx).pop();
            onPickWithdrawDestination(dollars: true);
          },
        ),
      ],
    );
  }

  /// The chrome every picker in this sheet wears: the untinted surface,
  /// the handle, a [title] with its [hint], then [rows]. Shared so a
  /// picker with two entries reads exactly like the one with ten.
  void _showPickerSheet(
    BuildContext context, {
    required String title,
    required String Function(RuntimeCapabilitiesService policy) hint,
    required List<Widget> Function(
            BuildContext sheetCtx, RuntimeCapabilitiesService policy)
        rows,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // The runtime policy is watched here so an open picker follows it
      // live: an onramp withdrawn while it is open leaves the list.
      builder: (_) => Consumer(builder: (sheetCtx, sheetRef, _) {
        final policy = sheetRef.watch(runtimeCapabilitiesProvider);
        // Every colour in this sheet must come from the UNTINTED palette.
        // The body was already untinted, but the title, the hint and the
        // handle were reading `c`, captured from the tinted sheet that
        // opened this one. On a green sheet that ink is white, so the
        // title rendered white on the white picker and disappeared.
        final pc = _untintedColors(sheetCtx);
        return _untinted(
          sheetCtx,
          Container(
            decoration: BoxDecoration(
              color: pc.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            padding: EdgeInsets.fromLTRB(0, 16.h, 0, 16.h),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: pc.dragHandle,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: pc.textPrimary,
                            fontSize: 28.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (hint(policy).isNotEmpty) ...[
                          SizedBox(height: 6.h),
                          Text(
                            hint(policy),
                            style: TextStyle(
                              color: pc.textTertiary,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                  ...rows(sheetCtx, policy),
                  SizedBox(height: 8.h),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  /// Whether [w] is a bitcoin account that can send besides the spending
  /// wallet (hardware, signing watch-only and hot on-chain wallets; never
  /// a tracked address or a pure watch-only). With one, the From row
  /// names the account its bitcoin leaves ("Spending").
  static bool _isOtherSendingBitcoinAccount(WalletConfig w) {
    if (w.isExternalAddress) {
      return false;
    }
    if (!(w.isHardware || w.isWatchOnly || w.isBitcoinSoftware)) {
      return false;
    }
    if (w.isWatchOnly && !w.isHardware && !w.isSigner) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The source wallet's name and brand when it is not the spending
    // account (a Ledger's own bitcoin in a Ledger move).
    String? sourceWalletName;
    if (sourceWalletId != null) {
      final settings = ref.watch(settingsProvider);
      sourceWalletName = settings.wallets
          .firstWhere(
            (w) => w.id == sourceWalletId,
            orElse: () => settings.wallets.first,
          )
          .name;
    }
    String? sourceBrandAsset;
    Color? sourceBrandColor;
    if (sourceWalletId != null) {
      final settings = ref.read(settingsProvider);
      final w = settings.wallets.firstWhere(
        (w) => w.id == sourceWalletId,
        orElse: () => settings.wallets.first,
      );
      final visual = WalletVisual.fromWallet(
        walletType: w.walletType,
        isHardware: w.isHardware,
        isWatchOnly: w.isWatchOnly,
        isSigner: w.isSigner,
        isDark: Theme.of(context).brightness == Brightness.dark,
      );
      sourceBrandAsset = visual.svgAsset;
      sourceBrandColor = visual.color;
    }
    // Source-side rendering: a Trading source (`hyperliquidSource`) reads
    // the HL logo + "Trading / Balance"; a plain USDC source (`!fromBtc`
    // on the spending pool) is the Predictions cashout direction.
    final sourceIsHyperliquid = hyperliquidSource && sourceWalletId == null;
    // The dollar source is checked BEFORE this: `!fromBtc` alone has
    // always spelled "the Predictions balance" here.
    final sourceIsUsdc = !fromBtc &&
        !hyperliquidSource &&
        !dollarsSource &&
        sourceWalletId == null;
    // The account label under a name ("Spending", "Savings") is there
    // to tell two accounts of one asset apart. With a single bitcoin
    // account it says nothing, so it is dropped; a Ledger move keeps
    // its labels, which name the device's own accounts.
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
    final btcSourceLabelled =
        ledgerContext || wallets.any(_isOtherSendingBitcoinAccount);
    return MoveRouteCard(
      // A cash-out states where the money LANDS and nothing else. The
      // venue it leaves is the sheet's own subject, named in the title,
      // so a From row there restated the obvious and turned the one real
      // choice into half a route (owner decision).
      // Ledger withdrawals have no destination picker, so retain their
      // source row instead of creating a route card with no endpoints.
      from: _isVenueWithdraw && !ledgerContext
          ? null
          : MoveRouteEndpoint(
              name: cashAppSource
                  ? 'Cash App'
                  : fiatSource
                      ? context.l10n.homeNavBankAccount
                      : dollarsSource
                          ? context.l10n.assetDollars
                          : sourceIsHyperliquid
                              ? context.l10n.trading
                              : sourceIsUsdc
                                  ? context.l10n.predictions
                                  : (sourceWalletName ?? 'Bitcoin'),
              asset: cashAppSource
                  ? 'lib/assets/cashapp-logo.svg'
                  : fiatSource
                      ? 'lib/assets/bank-transfer-logo.svg'
                      : dollarsSource && _dollarsWearCoin
                          ? kUsdMarkAsset
                          : sourceIsHyperliquid
                              ? 'lib/assets/hyperliquid-logo.svg'
                              : sourceIsUsdc
                                  ? 'lib/assets/polymarket-logo.svg'
                                  : (sourceBrandAsset ??
                                      'lib/assets/bitcoin-icon.svg'),
              assetTint: sourceBrandAsset != null ? sourceBrandColor : null,
              // The dollar balance as a source wears the Investments
              // arrow (`asset` is ignored while `iconData` is set),
              // except on the buy-bitcoin door, where it wears the USDB
              // coin above ([_dollarsWearCoin]).
              iconData:
                  dollarsSource && !_dollarsWearCoin ? kInvestmentsIcon : null,
              // Bank on the FROM side is money coming in, so the second
              // line names the action ('Deposit') rather than repeating
              // the rail ('Bank transfer'), which said nothing the title
              // above it had not already said. Cash App carries no second
              // line at all (user decision): the title is the whole story.
              origin: cashAppSource
                  ? null
                  : fiatSource
                      ? 'Deposit'
                      // One dollar balance, one balance per venue: only
                      // a Ledger's venue account has a name to show.
                      : dollarsSource
                          ? null
                          : (sourceIsHyperliquid || sourceIsUsdc)
                              ? venueWalletName
                              : (!btcSourceLabelled && sourceWalletName == null)
                                  ? null
                                  : (sourceWalletName != null
                                      ? 'Savings'
                                      : 'Spending'),
              // What the source has to move, on the right of the card.
              available: sourceAvailable,
              onAvailableTap: onSourceAvailableTap,
              detail: sourceDetail == null
                  ? null
                  : feeCopy(context, sourceDetail!),
              detailIsError: sourceDetailIsError,
              // Deposits keep their source dropdown; withdrawals pin the venue.
              onTap: interactionDisabled
                  ? null
                  : ledgerContext
                      ? ledgerSourcePicker
                      : (lockedSide == MoveLockedSide.withdrawFromPredictions ||
                              lockedSide ==
                                  MoveLockedSide.withdrawFromHyperliquid ||
                              lockedSide == MoveLockedSide.withdrawToFiat)
                          ? null
                          : () => _openSourcePicker(context),
            ),
      // A locked side usually means the destination is the sheet's own
      // subject, so the From row stands alone (user decision). The two
      // cash-outs are the exception: their lock pins the SOURCE, and
      // what the money turns into on the way out is exactly the thing
      // worth choosing. A Ledger cash-out still settles on the device's
      // own wallet, so it keeps the single row.
      to: _isVenueWithdraw && !ledgerContext
          ? MoveRouteEndpoint(
              name: usdDest ? context.l10n.assetDollars : 'Bitcoin',
              asset: 'lib/assets/bitcoin-icon.svg',
              // The dollar balance as a destination wears the
              // Investments arrow (`asset` is ignored while set).
              iconData: usdDest ? kInvestmentsIcon : null,
              // A cash-out lands in the spending account and nowhere
              // else, so there is no second account to tell apart.
              // The venue's spendable balance rides this row. A
              // cash-out draws no From row, and that is where the figure
              // and the tap that fills it used to live, so the one row
              // the sheet does draw carries both.
              available: sourceAvailable,
              onAvailableTap: onSourceAvailableTap,
              detail: sourceDetail == null
                  ? null
                  : feeCopy(context, sourceDetail!),
              detailIsError: sourceDetailIsError,
              onTap: interactionDisabled
                  ? null
                  : () => _openWithdrawDestinationPicker(context),
            )
          : null,
      // A venue exchange is invertible: the parent's onSwap flips it
      // between withdraw and deposit. (onSwap fires the haptic itself.) The
      // buy-to-pool locks pin BOTH ends (From = Fiat, To = the pool),
      // so there is nothing to invert — a flip would land on an
      // unrelated "Sell bitcoin" state. Disable + dim it there.
      onSwap: _swapLocked ? null : onSwap,
    );
  }
}

/// One row of the Move sheet's pickers: a mark, a title over a subtitle,
/// and a chevron (or a badge while [disabled]). Public so the Investments
/// receive screen can carry its "From your Bitcoin" row in the very same
/// shape.
class MovePickerRow extends StatelessWidget {
  /// Brand SVG for the mark. Exactly one of [asset] and [icon] is set.
  final String? asset;

  /// Glyph mark, drawn the way the route card draws its glyph
  /// endpoints: the Investments arrow on the dollar balance's row.
  final IconData? icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool disabled;

  /// Pill text rendered in the trailing position when [disabled] is
  /// true. Defaults to `SOON` (used by the Fiat row); the Move-side
  /// reuse passes `IN USE` to flag a tile already chosen on the
  /// opposite side.
  final String disabledLabel;

  /// The row's side inset. Null keeps the sheet's own 20 (design units);
  /// a page that already insets its content passes zero.
  final double? horizontalPadding;

  const MovePickerRow({
    super.key,
    this.asset,
    this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
    this.disabledLabel = 'SOON',
    this.horizontalPadding,
  }) : assert((asset == null) != (icon == null),
            'A picker row wears one mark: an SVG asset or a glyph');

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mark = icon != null
        ? Container(
            width: 36.sp,
            height: 36.sp,
            decoration: BoxDecoration(
              color: c.textPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11.r),
            ),
            child: Icon(icon, color: c.textPrimary, size: 20.sp),
          )
        : SvgPicture.asset(asset!, width: 36.sp, height: 36.sp);
    // Custom Row instead of ListTile to control the exact left
    // padding. ListTile applied an implicit `_minLeadingWidth`
    // gap that left a visible empty band between the screen edge
    // and the icon on the Move-from picker.
    return Opacity(
      opacity: disabled ? 0.6 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding ?? 20.w, vertical: 12.h),
            child: Row(
              children: [
                mark,
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2)),
                      SizedBox(height: 3.h),
                      Text(subtitle,
                          style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1)),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                if (disabled)
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: c.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(disabledLabel,
                        style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4)),
                  )
                else
                  Icon(Icons.chevron_right_rounded,
                      color: c.textTertiary, size: 22.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
