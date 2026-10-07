import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlMarketDirectory;

/// Trade notifications are stored with fixed English titles and row labels:
/// they are records, and the store matches on some of those words (for
/// example `rows.containsKey('Net profit')`). They are put in the app
/// language here, when shown. Anything not listed (market titles, amounts,
/// wallet names) passes through unchanged.
String tradeNotificationCopy(AppLocalizations l10n, String text) =>
    switch (text) {
      'Prediction won' => l10n.tnPredictionWon,
      'Prediction lost' => l10n.tnPredictionLost,
      'Prediction settled' => l10n.tnPredictionSettled,
      'Prediction bought' => l10n.tnPredictionBought,
      'Prediction sold' => l10n.tnPredictionSold,
      'Prediction' => l10n.tnPrediction,
      'Trade closed in profit' => l10n.tnTradeClosedProfit,
      'Trade closed' => l10n.tnTradeClosed,
      'Closing fill' => l10n.tnClosingFill,
      'Settlement payout' => l10n.tnSettlementPayout,
      'Position cost basis' => l10n.tnPositionCostBasis,
      'Return less cost basis' => l10n.tnReturnLessCost,
      'Profit details' => l10n.tnProfitDetails,
      'Additional fees may affect net profit' => l10n.tnFeesMayAffect,
      'Result' => l10n.tnResult,
      'Open Positions to check claim status' => l10n.tnCheckClaimStatus,
      'No payout' => l10n.betNoPayout,
      'Net profit' => l10n.tnNetProfit,
      'Trading P&L' => l10n.tnTradingPnl,
      'All trading fees' => l10n.tnAllTradingFees,
      'Funding received / paid' => l10n.tnFunding,
      'Includes' => l10n.tnIncludes,
      'Opening, partial closes and final close' => l10n.tnIncludesAllCloses,
      'Closed P&L (exchange)' => l10n.tnClosedPnlExchange,
      'Fill fee' => l10n.tnFillFee,
      'Filled size' => l10n.tnFilledSize,
      'Fill price' => l10n.tnFillPrice,
      'Accounting' => l10n.tnAccounting,
      'See trade history for all fees and funding' => l10n.tnSeeTradeHistory,
      'Claim credited' => l10n.tnClaimCredited,
      'Destination' => l10n.ledgerSummaryDestination,
      'Predictions balance' => l10n.homeNavPredictionsBalance,
      'Bought' => l10n.investingBought,
      'Sold' => l10n.investingSold,
      'Wallet' => l10n.accountWallet,
      'Shares' => l10n.betShares,
      'Average fill price' => l10n.tnAverageFillPrice,
      'Status' => l10n.status,
      'Filled' => l10n.ledgerOrderFilled,
      'Transaction' => l10n.tnTransaction,
      // What a Hyperliquid fill did (hlFillAction, stored in English).
      'Position liquidated' => l10n.hlFillLiquidated,
      'Bought asset' => l10n.hlFillBoughtAsset,
      'Sold asset' => l10n.hlFillSoldAsset,
      'Opened position' => l10n.hlFillOpened,
      'Closed position' => l10n.hlFillClosed,
      'Reversed position' => l10n.hlFillReversed,
      'Added to position' => l10n.hlFillAdded,
      'Reduced position' => l10n.hlFillReduced,
      'Trade filled' => l10n.hlFillTradeFilled,
      // Earlier receipts stored the venue's own direction words.
      'Buy' => l10n.buy,
      'Sell' => l10n.sell,
      'Close Long' || 'Close Short' => l10n.hlFillReduced,
      'Open Long' || 'Open Short' => l10n.hlFillAdded,
      _ => text,
    };

/// A stored subtitle in the app language: each ` · `-separated part is
/// passed through [tradeNotificationCopy], so `BTC · Full position` reads
/// in the app language while market names stay as they are.
///
/// Earlier Hyperliquid receipts stored the wire coin ('@142', 'xyz:TSLA');
/// those read as the market's name ('TSLA').
String tradeNotificationSubtitle(AppLocalizations l10n, String subtitle) =>
    subtitle
        .split(' · ')
        .map((part) => part == 'Full position'
            ? l10n.tnFullPosition
            : _isHlWireCoin(part)
                ? HlMarketDirectory.displayName(part)
                : tradeNotificationCopy(l10n, part))
        .join(' · ');

bool _isHlWireCoin(String part) =>
    RegExp(r'^@\d+$').hasMatch(part) ||
    RegExp(r'^[a-z]{1,8}:[A-Za-z0-9]+$').hasMatch(part);
