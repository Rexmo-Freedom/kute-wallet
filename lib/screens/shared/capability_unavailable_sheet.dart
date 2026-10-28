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
// A region block's one button is "Check connection" instead of "Got it"
// (founder decision, October 2026; lib/services/region_freshness.dart):
// it asks both venues and Kute's policy again, the button busy with the
// shared rubber band meanwhile. Allowed now: the sheet closes, answering
// true when what it was opened for is allowed, so a door can go on into
// its action. Still restricted: it stays, with a soft failure tap, and
// the button can be tapped again after the VPN changes. The sheet closes
// by dragging it down or tapping outside, like every sheet.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
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
  /// provider's own region sentence).
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
            subtitle: widget.message,
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: region
                ? RubberBandBusy(
                    busy: _checking,
                    expected: const Duration(seconds: 2),
                    child: AppButton(
                      key: const ValueKey(
                          'capability-unavailable-check-connection'),
                      text: l10n.checkConnection,
                      isLoading: _checking,
                      onPressed: _checking ? null : _checkConnection,
                    ),
                  )
                : AppButton(
                    key: const ValueKey('capability-unavailable-got-it'),
                    text: l10n.gotIt,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
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
/// `capability_region_blocked` on [surface].
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
  if (denial != null && denial.decision.regionRestricted) {
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
/// the backend's regions in the title, over the VPN sentence.
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
      regionRestricted: decision.regionRestricted,
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
