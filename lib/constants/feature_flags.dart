// lib/constants/feature_flags.dart
//
// Release feature flags. Hidden, not deleted: flipping a flag restores
// the feature with its routes and screens intact.

/// Bank tab visibility for this release (user decision September 2026:
/// ships in a later version). Gates the nav pill chip AND the shell
/// pager page so neither taps nor swipes can reach '/bank'; the route
/// and BankScreen stay wired underneath.
///
/// The strip slot it used to hold now belongs to the USD tab (the
/// spending account's dollars, '/usd'). Flipping this back on puts Bank
/// back in the pager ahead of USD; nothing about USD depends on it.
const bool showBankTab = false;

/// "Share usage analytics" switch in Settings → Security. Hidden until it
/// ships: while false the row is not built and nothing links to it. The
/// opt-out itself (TrackingService.disableTracking) works either way.
const bool showAnalyticsOptOut = false;

// Cash App availability is published by backend runtime capabilities. Payment
// rails that have not shipped (Bank/DEPIX) remain Coming soon in their picker.

// These Ledger actions are blind-signed: the device shows a code, not the
// details (like Phantom with a Ledger). They ship enabled by decision
// (September 2026); a build can still turn them off with the dart-defines.

/// Ledger account screen, Add Wallet venue icons and setup step.
const bool kLedgerInvestingEnabled = true;

// Ledger Predictions and Ledger Investing (a Ledger's own Polymarket and
// Hyperliquid accounts) have no build switch: they answer to the runtime
// capabilities `ledger.polymarket` / `ledger.hyperliquid` alone, see
// `ledgerInvestmentAllowed` in lib/screens/ledger/ledger_investment_gate.dart.

/// O1: Hyperliquid orders, cancels, leverage and TWAP signed by a
/// Ledger. The device shows a code, not the details, so these payloads
/// are opaque and blocked while this is off.
const bool kLedgerHyperliquidOpaqueActionsEnabled = bool.fromEnvironment(
  'KUTE_LEDGER_HYPERLIQUID_OPAQUE_ACCEPTED',
  defaultValue: true,
);

/// O3: Polymarket withdrawal out of a Ledger deposit wallet. The
/// destination sits inside batch calldata the device cannot display.
const bool kLedgerPolymarketWithdrawEnabled = bool.fromEnvironment(
  'KUTE_LEDGER_POLYMARKET_WITHDRAW_ACCEPTED',
  defaultValue: true,
);

/// Native Spark to and from HyperCore funding. When disabled, funding stops.
const bool kDirectHypercoreFundingEnabled = true;

/// O16: USB transport choice in the Ledger device picker (Android only).
const bool kLedgerUsbTransportEnabled = true;

/// O10: on-device address check before a Cash App purchase into a
/// Ledger address.
const bool kLedgerCashAppAddressCheckEnabled = true;

// ── Compromise tools (Wallet hardening Phase 5 plan B18, F14) ──────────
