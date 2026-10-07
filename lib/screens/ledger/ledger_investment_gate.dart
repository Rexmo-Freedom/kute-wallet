import 'package:flutter/material.dart';
import 'package:kute/constants/feature_flags.dart'
    show kLedgerInvestingEnabled;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

const ledgerInvestingCapability = 'ledger.hyperliquid';
const ledgerPredictionsCapability = 'ledger.polymarket';

/// Whether a Ledger's own venue for [capability] (`ledger.polymarket` or
/// `ledger.hyperliquid`) is on: the runtime policy alone (founder
/// decision, October 2026; there is no build switch). A denied capability
/// and a policy Kute cannot read both read as off, since neither id is in
/// the offline table. When false the venue is not shown anywhere on a
/// Ledger: no tab, no header or pill, no logo, no badge, no Settings
/// address, no setup prompt, no unavailable sheet. When true the surfaces
/// appear and the setup is asked the first time that venue is opened.
/// [policy] is the live policy by default; pass the watched one in a
/// build so the surface follows an admin switch.
bool ledgerInvestmentAllowed(String capability,
        {RuntimeCapabilitiesService? policy}) =>
    (policy ?? RuntimeCapabilitiesService.instance).allows(capability);

/// True when either Ledger venue is on (see [ledgerInvestmentAllowed]).
/// Decides the venue-wide surfaces: the post-connect setup step, the Add
/// Wallet venue badges and the Settings venue addresses of a Ledger.
bool ledgerAnyVenueAllowed({RuntimeCapabilitiesService? policy}) =>
    ledgerInvestmentAllowed(ledgerPredictionsCapability, policy: policy) ||
    ledgerInvestmentAllowed(ledgerInvestingCapability, policy: policy);

/// The Ledger an import continues with to the "Invest with your Ledger"
/// setup step, or null to land on Home. Only a Ledger, and only while a
/// Ledger venue is on ([ledgerAnyVenueAllowed]); otherwise the Ledger is
/// connected as a bitcoin hardware wallet, exactly as if "Keep Bitcoin
/// only" had been tapped, with no prompt.
String? ledgerVenueSetupAfterImport({
  required String? importedWalletId,
  required String? importedWalletType,
  RuntimeCapabilitiesService? policy,
}) =>
    kLedgerInvestingEnabled &&
            importedWalletType == 'ledger' &&
            ledgerAnyVenueAllowed(policy: policy)
        ? importedWalletId
        : null;

/// Why a Ledger can't reach Investing or Predictions, in the shared
/// unavailable sheet every other blocked action uses. Only for a door
/// that was already open (a market page reached another way); entry
/// points themselves are hidden instead.
Future<void> showLedgerInvestmentUnavailable(
        BuildContext context, String capability) =>
    showCapabilityUnavailableSheet(
      context,
      message: capability == ledgerInvestingCapability
          ? context.l10n.ledgerInvestingUnavailable
          : context.l10n.ledgerPredictionsUnavailable,
    );

/// The Ledger capability a Move into a Ledger's own venue account needs,
/// or null when the move puts no new money into Predictions or Investing.
/// [ledgerWalletId] is the Ledger the move is pinned to (a Ledger device
/// move, or the Ledger venue account a Cash App purchase funds). Every
/// direction out of a venue (withdrawals) is an exit and needs none.
String? ledgerVenueEntryCapability({
  required String? ledgerWalletId,
  required bool toPredictions,
  required bool toInvesting,
}) {
  if (ledgerWalletId == null) return null;
  if (toPredictions) return ledgerPredictionsCapability;
  if (toInvesting) return ledgerInvestingCapability;
  return null;
}
