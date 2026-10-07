import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';

/// The venue mark the venue's top button leads with: the same Hyperliquid
/// and Polymarket marks the nav strip draws for the two tabs.
String venueMarkAsset(InvestmentsProduct product) =>
    product == InvestmentsProduct.predictions
        ? 'lib/assets/polymarket-logo.svg'
        : 'lib/assets/hyperliquid-logo.svg';

/// The venue's deposit label: "Investing deposit" / "Predictions deposit",
/// named the way the Dollars screen names its "Dollar deposit".
String venueDepositLabel(BuildContext context, InvestmentsProduct product) =>
    product == InvestmentsProduct.predictions
        ? context.l10n.predictionsDeposit
        : context.l10n.investingDeposit;

/// The venue's top button: Deposit for that venue (owner decision: the
/// primary button above the balance funds the venue, and Portfolio moved
/// into the dock). Drawn exactly as the Bitcoin and Dollars top buttons
/// are (Purchase Bitcoin, Dollar deposit): the default AppButton with the
/// balance's own mark leading the label, here the venue's mark and its
/// "Investing deposit" / "Predictions deposit" name, so the four read as
/// one control pointed at four balances.
/// A null [onTap] renders it disabled, the way the dock's Deposit did when
/// the venue could not take a deposit yet. [source] is the host's screen
/// key for the `quick_action_tapped` event the dock used to send, which
/// also carries the `venue`.
class VenueDepositButton extends StatelessWidget {
  final InvestmentsProduct product;
  final String source;
  final VoidCallback? onTap;

  const VenueDepositButton({
    super.key,
    required this.product,
    required this.source,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = venueDepositLabel(context, product);
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        excludeSemantics: true,
        child: AppButton(
          text: label,
          svgAsset: venueMarkAsset(product),
          onPressed: onTap == null
              ? null
              : () {
                  TrackingService.quickAction('deposit',
                      source: source,
                      venue: product == InvestmentsProduct.predictions
                          ? 'polymarket'
                          : 'hyperliquid');
                  onTap!();
                },
        ),
      ),
    );
  }
}
