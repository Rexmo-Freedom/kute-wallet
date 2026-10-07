import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';

/// A fee rate in basis points as a percentage in the app locale, e.g. 0.50%.
String feeRateText(int bps) =>
    NumberFormat.decimalPercentPattern(decimalDigits: 2).format(bps / 10000);

/// A discount as a share of a fee, e.g. 40 → 40%. Used in referral copy
/// and the fee summaries' friend-discount notes.
String discountShareText(int pct) =>
    NumberFormat.decimalPercentPattern(decimalDigits: 0)
        .format(pct.clamp(0, 100) / 100);

/// A commission rate given in percent (5 → 5%, 7.5 → 7.5%), as the
/// backend's affiliate terms publish it.
String commissionRateText(num pct) {
  final value = pct.clamp(0, 100).toDouble();
  final whole = value == value.roundToDouble();
  return NumberFormat.decimalPercentPattern(decimalDigits: whole ? 0 : 1)
      .format(value / 100);
}

/// The share of a fee a discount took off it, as a whole percentage: the
/// discount over the fee as it was listed (paid + discount). 100 when the
/// discount took the whole fee; 0 when nothing came off.
int discountShareOf({required num paid, required num discount}) {
  if (discount <= 0 || paid < 0) return 0;
  final listed = paid + discount;
  if (listed <= 0) return 0;
  return (discount * 100 / listed).round().clamp(0, 100);
}

/// Shared fee copy used by hot-wallet and Ledger sheets.
String feeCopy(BuildContext context, String text) => switch (text) {
      "Estimated fee" => context.l10n.feeUiEstimatedFee,
      "Fees" => context.l10n.fees,
      "Total fees" => context.l10n.totalFees,
      "Estimated fees" => context.l10n.feeUiEstimatedFees,
      "Network activation" => context.l10n.feeUiNetworkActivation,
      "Network activation (up to)" => context.l10n.feeUiNetworkActivationUpTo,
      "Fee settings unavailable" => context.l10n.feeUiFeeSettingsUnavailable,
      "Estimated conversion cost" => context.l10n.moveEstimatedConversionCost,
      "Not quoted" => context.l10n.moveNotQuoted,
      "Cash App may charge additional fees." => context.l10n.moveCashAppMayCharge,
      "Shown before signing" => context.l10n.moveShownBeforeSigning,
      "Purchase fee" => context.l10n.movePurchaseFee,
      "Provider fee" => context.l10n.providerFee,
      "You send" => context.l10n.youSend,
      "You receive" => context.l10n.youReceive,
      "You receive at least" => context.l10n.feeUiYouReceiveAtLeast,
      "Shown before you confirm" => context.l10n.feeUiShownBeforeYouConfirm,
      "Included in the amount you receive" =>
        context.l10n.feeUiIncludedInTheAmountYouReceive,
      "Estimate. The exact fees are shown before you confirm." =>
        context.l10n.feeUiEstimateExactFeesShownBeforeYouConfirm,
      "Taken from the amount you send." =>
        context.l10n.feeUiTakenFromTheAmountYouSend,
      "Unavailable" => context.l10n.feeUiUnavailable,
      "Enter an amount" => context.l10n.feeUiEnterAnAmount,
      "Calculating…" => context.l10n.feeUiCalculating,
      "Unavailable · Retry" => context.l10n.feeUiUnavailableRetry,
      "Total unavailable" => context.l10n.feeUiTotalUnavailable,
      "Exchange fee estimate" => context.l10n.feeUiExchangeFeeEstimate,
      "Kute fee" => context.l10n.feeUiKuteFee,
      "Polymarket fee" => context.l10n.feeUiPolymarketFee,
      "Estimated proceeds after fees" =>
        context.l10n.feeUiEstimatedProceedsAfterFees,
      "Conversion fee estimate" => context.l10n.feeUiConversionFeeEstimate,
      "Bridge withdrawal fee" => context.l10n.feeUiBridgeWithdrawalFee,
      "Network fee" => context.l10n.feeUiNetworkFee,
      "Bitcoin network fee" => context.l10n.feeUiBitcoinNetworkFee,
      "Shown on Ledger before signing" =>
        context.l10n.feeUiShownOnLedgerBeforeSigning,
      "Covered by relayer" => context.l10n.feeUiCoveredByRelayer,
      "Paid fee" => context.l10n.feeUiPaidFee,
      "Fee rebate" => context.l10n.feeUiFeeRebate,
      "Paid trading fee" => context.l10n.feeUiPaidTradingFee,
      "Not reported in activity" => context.l10n.feeUiNotReportedInActivity,
      "Provider quote" => context.l10n.feeUiProviderQuote,
      "Entry history unavailable" => context.l10n.feeUiEntryHistoryUnavailable,
      "Entry capital unavailable" => context.l10n.feeUiEntryCapitalUnavailable,
      "Available after selling" => context.l10n.feeUiAvailableAfterSelling,
      "vs holding Bitcoin" => context.l10n.feeUiVsHoldingBitcoin,
      "Position vs holding Bitcoin" =>
        context.l10n.feeUiPositionVsHoldingBitcoin,
      "Estimated · daily Bitcoin prices · before fees" =>
        context.l10n.feeUiEstimatedDailyBitcoinPricesBeforeFees,
      "Current position · daily entry Bitcoin prices · before fees" =>
        context.l10n.feeUiCurrentPositionDailyEntryBitcoinPricesBeforeFees,
      "Ahead of holding Bitcoin." => context.l10n.feeUiAheadOfHoldingBitcoin,
      "Behind holding Bitcoin." => context.l10n.feeUiBehindHoldingBitcoin,
      "Included in the conversion. Network fees and exchange-rate spread may also apply." =>
        context.l10n
            .feeUiIncludedInTheConversionNetworkFeesAndExchangeRateSpreadMayAlsoApply,
      "If filled as a taker. Maker fees may be lower." =>
        context.l10n.feeUiIfFilledAsATakerMakerFeesMayBeLower,
      "Final fee depends on the fill price." =>
        context.l10n.feeUiFinalFeeDependsOnTheFillPrice,
      "On filled trade value. Final fees may vary; rebates are not deducted." =>
        context
            .l10n.feeUiOnFilledTradeValueFinalFeesMayVaryRebatesAreNotDeducted,
      "Venue fee varies by market. Kute fee shown below." =>
        context.l10n.feeUiVenueFeeVariesByMarketKuteFeeShownBelow,
      "Includes any Kute builder fee." =>
        context.l10n.feeUiIncludesAnyKuteBuilderFee,
      "Transfer fee" => context.l10n.feeUiTransferFee,
      "Not quoted by venue" => context.l10n.feeUiNotQuotedByVenue,
      "Add funds to continue" => context.l10n.feeUiAddFundsToContinue,
      "Price unavailable" => context.l10n.feeUiPriceUnavailable,
      "Estimate unavailable" => context.l10n.feeUiEstimateUnavailable,
      "Varies by market" => context.l10n.feeUiVariesByMarket,
      "Available after account setup" =>
        context.l10n.feeUiAvailableAfterAccountSetup,
      "Choose a larger amount" => context.l10n.feeUiChooseALargerAmount,
      "Shown in Cash App" => context.l10n.feeUiShownInCashApp,
      "Insufficient balance" => context.l10n.feeUiInsufficientBalance,
      "Updating balance" => context.l10n.feeUiUpdatingBalance,
      "Balance unavailable" => context.l10n.feeUiBalanceUnavailable,
      _ => text,
    };
