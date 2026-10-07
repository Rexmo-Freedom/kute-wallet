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
// Title: "Not available in your region" for a region block, whose body is
// the network / VPN sentence; the caller's title (or the generic
// "Unavailable") for anything else.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

class CapabilityUnavailableSheet extends StatelessWidget {
  const CapabilityUnavailableSheet({
    super.key,
    required this.message,
    this.regionRestricted = false,
    this.title,
  });

  /// The sentence that says why: [CapabilityDecision.messageIn] (or the
  /// provider's own region sentence).
  final String message;

  /// A region block: the title names the region, whatever [title] says.
  final bool regionRestricted;

  /// Title for a block that is not about the region. Defaults to the
  /// generic "Unavailable".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: regionRestricted
                ? l10n.capabilityRegionTitle
                : (title ?? l10n.gateUnavailableTitle),
            subtitle: message,
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: AppButton(
              key: const ValueKey('capability-unavailable-got-it'),
              text: l10n.gotIt,
              onPressed: () => Navigator.of(context).pop(),
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

/// Shows the shared unavailable sheet. Resolves when it is dismissed; does
/// nothing while one is already showing.
Future<void> showCapabilityUnavailableSheet(
  BuildContext context, {
  required String message,
  bool regionRestricted = false,
  String? title,
}) async {
  if (_opening || _openSheet?.mounted == true || !context.mounted) return;
  _opening = true;
  try {
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        _openSheet = sheetContext;
        _opening = false;
        return CapabilityUnavailableSheet(
          message: message,
          regionRestricted: regionRestricted,
          title: title,
        );
      },
    );
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

/// The shared sheet for a policy [decision] that denies.
Future<void> showCapabilityDecisionSheet(
  BuildContext context,
  CapabilityDecision decision, {
  String? title,
}) =>
    showCapabilityUnavailableSheet(
      context,
      message: decision.messageIn(context.l10n),
      regionRestricted: decision.regionRestricted,
      title: title,
    );

/// The shared sheet for whatever [error] a capability check threw: the
/// policy's denial or the venue's own region answer. Returns false (and
/// shows nothing) for any other error, so the caller can handle it.
Future<bool> showCapabilityErrorSheet(
  BuildContext context,
  Object error, {
  String? title,
}) async {
  if (error is CapabilityUnavailableException) {
    await showCapabilityDecisionSheet(context, error.decision, title: title);
    return true;
  }
  if (error is ProviderAvailabilityException) {
    await showCapabilityUnavailableSheet(
      context,
      message: error.availability.messageIn(context.l10n),
      regionRestricted:
          error.availability.status == ProviderAvailabilityStatus.restricted,
      title: title,
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
  showCapabilityDecisionSheet(context, decision);
  return false;
}
