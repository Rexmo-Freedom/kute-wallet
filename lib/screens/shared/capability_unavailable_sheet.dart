// lib/screens/shared/capability_unavailable_sheet.dart
//
// The one sheet Kute shows when a tap reaches something the runtime policy
// withholds: a Bet, an order, a Deposit or Add money on Predictions or
// Investing, Ledger included. Controls that can say why they are shut do
// so in place with [CapabilityBlockNote]; this sheet is for the taps that
// only learn it at the tap (a dock button, a policy that changed while a
// ticket was open, a door into a gated account).
//
// Built like every other Kute sheet (the Ledger funding explainer, the
// fee and speed pickers): [showAppBottomSheet], drag handle, the shared
// 28sp title, the body as its subtitle, one primary "Got it" button, and
// the container's own safe-area and home-indicator handling. No artwork,
// no reason codes.
//
// Title: for a region block whose regions the backend names (founder
// decision, 27 October 2026: region blocks live only in the backend
// policy), "Not available in the European Union, the UK and Switzerland"
// over the one VPN sentence allowed ("If this isn't where you are, check
// your VPN settings."); "Not available in your region" over the
// connection sentence for one it does not name; the caller's title (or
// the generic "Unavailable") for anything else. A block a capability
// inherits (`blockedBy`) reads the same.
//
// An allow list is not a region block (founder, 7 November 2026: "not
// avaliable in usa? my vpn is in lisbon. please just say not avaliable
// right now"). A policy denial because the person is outside the places a
// feature is offered (`country_not_allowed`,
// [CapabilityDecision.notOfferedHere]; Cash App is US-only) reads just
// "Not available right now": no region (the backend's list is where it IS
// offered), no VPN sentence, no body, the plain "Got it", and nothing
// counted as `capability_region_blocked`, whatever the caller passed.
//
// A region block's one button is "Check connection" instead of "Got it"
// (founder decision, October 2026; lib/services/region_freshness.dart):
// it asks both venues and Kute's policy again, the button busy
// meanwhile. Allowed now: the sheet closes, answering
// true when what it was opened for is allowed, so a door can go on into
// its action. Still restricted: it stays, with a soft failure tap, and
// the button can be tapped again after the VPN changes. The sheet closes
// by dragging it down or tapping outside, like every sheet.
//
// THE BAR IS THE BUTTON (founder, 31 October 2026; kute_bar_context.dart):
// the sheet draws no button of its own. "Got it" or "Check connection" is
// the floating Sal bar's primary action ([KuteBarContext.primary]), busy
// with the bar's progress ring while the re-check runs (the rubber band
// the drawn button wore went with it), and the sheet keeps the room under
// its header clear for the bar ([kuteBarScrollClearance]). The bar's long
// press asks Sal scoped to the venue the block came from, when the sheet
// knows one ([_category]).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/success_feedback.dart'
    show moneyFailureFeedbackAfterBand;
import 'package:kute/services/tracking_service.dart';

class CapabilityUnavailableSheet extends StatefulWidget {
  const CapabilityUnavailableSheet({
    super.key,
    required this.message,
    this.regionRestricted = false,
    this.title,
    this.regionTitle,
    this.capabilities,
    this.venues = const [],
  });

  /// The sentence that says why: [CapabilityDecision.messageIn] (or the
  /// provider's own region sentence). Empty for none: the title alone
  /// (an allow list's "Not available right now").
  final String message;

  /// A region block: the title names the region, whatever [title] says,
  /// and the button is "Check connection".
  final bool regionRestricted;

  /// Title for a block that is not about the region. Defaults to the
  /// generic "Unavailable".
  final String? title;

  /// A region block's title when the backend named its regions
  /// ([CapabilityDecision.regionTitleIn]); the generic "Not available in
  /// your region" otherwise.
  final String? regionTitle;

  /// What a region block was opened for, read again after "Check
  /// connection": the policy capabilities (and the venues gating them).
  /// Null reads every region denial the policy holds.
  final Iterable<String>? capabilities;

  /// The venues whose own region answer opened the sheet.
  final Iterable<InvestmentProvider> venues;

  @override
  State<CapabilityUnavailableSheet> createState() =>
      _CapabilityUnavailableSheetState();
}

class _CapabilityUnavailableSheetState
    extends State<CapabilityUnavailableSheet> {
  bool _checking = false;

  /// The venue the block came from, for the bar's long press (asking Sal
  /// scoped to Predictions or Perpetuals): the venues whose own answer
  /// opened the sheet, else the policy capabilities' prefix
  /// (`polymarket.deposit`, `hyperliquid.deposit`); everything otherwise.
  SearchCategory get _category {
    final venues = widget.venues.toSet();
    final ids = widget.capabilities?.toList() ?? const <String>[];
    final predictions = venues.contains(InvestmentProvider.polymarket) ||
        ids.any((id) => id.startsWith('polymarket.'));
    final perpetuals = venues.contains(InvestmentProvider.hyperliquid) ||
        ids.any((id) => id.startsWith('hyperliquid.'));
    if (predictions && !perpetuals) return SearchCategory.predictions;
    if (perpetuals && !predictions) return SearchCategory.perpetuals;
    return SearchCategory.all;
  }

  /// "Check connection": a fresh region round, then what stands. Allowed
  /// now closes the sheet (true when what it was opened for is allowed);
  /// still restricted keeps it, with the soft failure tap.
  Future<void> _checkConnection() async {
    if (_checking) return;
    setState(() => _checking = true);
    await RegionFreshness.checkConnection();
    if (!mounted) return;
    if (!RegionFreshness.regionRefused(
        capabilities: widget.capabilities, venues: widget.venues)) {
      final policy = RuntimeCapabilitiesService.instance;
      final allowed = widget.capabilities?.every((id) {
            final decision = policy.decision(id);
            return decision.allowed && !decision.comingSoon;
          }) ??
          true;
      Navigator.of(context).pop(allowed);
      return;
    }
    setState(() => _checking = false);
    moneyFailureFeedbackAfterBand(() => mounted && _checking);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final region = widget.regionRestricted;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: region
                ? (widget.regionTitle ?? l10n.capabilityRegionTitle)
                : (widget.title ?? l10n.gateUnavailableTitle),
            subtitle: widget.message.isEmpty ? null : widget.message,
          ),
          SizedBox(height: 8.h),
          // THE BAR IS THE BUTTON (founder, 31 October 2026; kute_bar_context
          // .dart): "Check connection" (busy with the bar's progress ring
          // while the re-check runs, so it takes no second tap) or "Got
          // it" is the floating Sal bar's primary action, with the handler
          // the drawn button had; the sheet keeps the room under its
          // header for the bar.
          KuteBarContextScope(
            barContext: region
                ? KuteBarContext.primary(
                    label: l10n.checkConnection,
                    busy: _checking,
                    busyLabel: l10n.checkConnection,
                    onPrimary: _checkConnection,
                    category: _category,
                    source: 'capability_unavailable',
                    disabledLabel: null,
                  )
                : KuteBarContext.primary(
                    label: l10n.gotIt,
                    onPrimary: () => Navigator.of(context).pop(false),
                    category: _category,
                    source: 'capability_unavailable',
                    disabledLabel: null,
                  ),
            child: SizedBox(height: kuteBarScrollClearance.h),
          ),
        ],
      ),
    );
  }
}

/// The sheet's own context while one is up, so a second tap (or a tap
/// racing a place-time re-check) never stacks another one on top. Read
/// through `mounted`, so a sheet torn down with its navigator never leaves
/// the guard stuck. [_opening] covers the frame between the call and the
/// sheet's first build.
BuildContext? _openSheet;
bool _opening = false;

/// Shows the shared unavailable sheet. Resolves when it is dismissed:
/// true only when "Check connection" found [capabilities] allowed now
/// (a region block; [capabilities] and [venues] as on
/// [CapabilityUnavailableSheet]), so the caller may go on into the
/// action. Does nothing (false) while one is already showing.
///
/// [denial] is Kute's policy refusal behind the sheet, when there is one
/// (the capability and its decision): a region block names its regions in
/// the title when the backend did, and is counted once as
/// `capability_region_blocked` on [surface]. A denial by an allow list
/// ([CapabilityDecision.notOfferedHere]) is not one: whatever [title],
/// [message] and [regionRestricted] say, the sheet reads just "Not
/// available right now" over "Got it", and nothing is counted, as for any
/// refusal that is not about the region.
Future<bool> showCapabilityUnavailableSheet(
  BuildContext context, {
  required String message,
  bool regionRestricted = false,
  String? title,
  String? regionTitle,
  Iterable<String>? capabilities,
  Iterable<InvestmentProvider> venues = const [],
  ({String capability, CapabilityDecision decision})? denial,
  String surface = 'unavailable_sheet',
}) async {
  if (_opening || _openSheet?.mounted == true || !context.mounted) {
    return false;
  }
  if (denial != null && denial.decision.notOfferedHere) {
    title = context.l10n.capabilityNotAvailableNow;
    message = '';
    regionRestricted = false;
    regionTitle = null;
  } else if (denial != null && denial.decision.regionBlocked) {
    regionTitle ??= denial.decision.regionTitleIn(context.l10n);
    TrackingService.capabilityRegionBlocked(denial.capability,
        blockedBy: denial.decision.blockedBy, surface: surface);
  }
  _opening = true;
  try {
    final allowed = await showAppBottomSheet<bool>(
      context: context,
      builder: (sheetContext) {
        _openSheet = sheetContext;
        _opening = false;
        return CapabilityUnavailableSheet(
          message: message,
          regionRestricted: regionRestricted,
          title: title,
          regionTitle: regionTitle,
          capabilities: capabilities,
          venues: venues,
        );
      },
    );
    return allowed ?? false;
  } finally {
    _opening = false;
  }
}

/// The shared sheet for a Buy door tapped while no onramp is on offer
/// (see `anyOnrampVisible`): "Buy unavailable", no purchase providers.
Future<void> showBuyUnavailableSheet(BuildContext context) {
  return showCapabilityUnavailableSheet(
    context,
    title: context.l10n.buyUnavailableTitle,
    message: context.l10n.buyUnavailableBody,
  );
}

/// The shared sheet for a policy [decision] that denies [capability]
/// (when the caller knows it: "Check connection" reads it again). True
/// when "Check connection" found it allowed now. A region block names
/// the backend's regions in the title, over the VPN sentence; an allow
/// list's refusal reads "Not available right now".
Future<bool> showCapabilityDecisionSheet(
  BuildContext context,
  CapabilityDecision decision, {
  String? title,
  String? capability,
  String surface = 'unavailable_sheet',
}) =>
    showCapabilityUnavailableSheet(
      context,
      message: decision.bodyIn(context.l10n),
      regionRestricted: decision.regionBlocked,
      title: title,
      capabilities: capability == null ? null : [capability],
      denial: (capability: capability ?? 'unknown', decision: decision),
      surface: surface,
    );

/// The shared sheet for whatever [error] a capability check threw: the
/// policy's denial or the venue's own region answer. Returns false (and
/// shows nothing) for any other error, so the caller can handle it.
Future<bool> showCapabilityErrorSheet(
  BuildContext context,
  Object error, {
  String? title,
  String surface = 'unavailable_sheet',
}) async {
  if (error is CapabilityUnavailableException) {
    await showCapabilityDecisionSheet(context, error.decision,
        title: title, capability: error.capability, surface: surface);
    return true;
  }
  if (error is ProviderAvailabilityException) {
    await showCapabilityUnavailableSheet(
      context,
      message: error.availability.messageIn(context.l10n),
      regionRestricted:
          error.availability.status == ProviderAvailabilityStatus.restricted,
      title: title,
      venues: [error.availability.provider],
    );
    return true;
  }
  return false;
}

/// The capability behind every "Advanced" entry on a trade ticket: limit,
/// trigger, TWAP and trailing orders, leverage and custom slippage.
const kTradingAdvancedCapability = 'trading.advanced';

/// The tap on an "Advanced" entry (the bet slip, the order ticket, the
/// close and sell sheets, Ledger included). True when the Advanced page
/// may open. While the policy withholds `trading.advanced`, or Kute cannot
/// read a policy (it is not in the offline table), nothing opens: the
/// shared sheet says why instead, with the policy's own reason. The entry
/// itself stays visible, and placing still re-checks as the backstop.
bool advancedTradingOffered(
    BuildContext context, RuntimeCapabilitiesService policy) {
  final decision = policy.decision(kTradingAdvancedCapability);
  if (decision.allowed && !decision.comingSoon) return true;
  showCapabilityDecisionSheet(context, decision,
      capability: kTradingAdvancedCapability);
  return false;
}
