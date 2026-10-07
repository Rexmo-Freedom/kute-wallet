import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_notification_copy.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/trade_notification_store.dart';

/// The market art of a results-inbox receipt: the prediction's crest or
/// the Investing coin.
class TradeNotificationArtwork extends StatelessWidget {
  const TradeNotificationArtwork({super.key, required this.item});
  final TradeNotification item;

  @override
  Widget build(BuildContext context) {
    if (item.product == 'predictions') {
      return PolyReceiptArtwork(url: item.imageUrl);
    }
    // Earlier receipts already saved the wire coin before the separator.
    final coin = item.assetCode ?? item.subtitle.split(' · ').first;
    return HlCoinIcon(coin: hlBaseCoin(coin), wireCoin: coin, size: 44);
  }
}

/// The receipt card for a stored result. Stored rows are English records
/// (trade_notification_copy); here they become what a person reads: the
/// amount first, shares and the average price at the precision the
/// Activity sheets use, the status in plain words, the date, the wallet
/// only when there is more than one, and the transaction hash as a short
/// copyable value with a block-explorer link instead of a 66-character row.
TradeReceipt tradeNotificationReceipt(
    AppLocalizations l10n, TradeNotification item,
    {required bool showWallet}) {
  final predictions = item.product == 'predictions';
  // Prediction subtitles are 'Market title · Outcome': the outcome goes in
  // the chip, the title wraps on its own.
  final cut = predictions ? item.subtitle.lastIndexOf(' · ') : -1;
  final title = cut > 0
      ? item.subtitle.substring(0, cut)
      : tradeNotificationSubtitle(l10n, item.subtitle);
  final outcome = cut > 0 ? item.subtitle.substring(cut + 3) : null;
  final hash = item.rows['Transaction'];
  final rows = <String, String>{};
  for (final e in item.rows.entries) {
    switch (e.key) {
      case 'Transaction' || 'Wallet':
        break; // The hash gets its own row; the wallet is added below.
      case 'Shares':
        final shares = double.tryParse(e.value);
        rows[l10n.betShares] = shares?.toStringAsFixed(2) ?? e.value;
      case 'Average fill price':
        final cents = double.tryParse(e.value.replaceAll('¢', ''));
        rows[l10n.tnAverageFillPrice] =
            cents == null ? e.value : '${cents.toStringAsFixed(1)}¢';
      case 'Status' when e.value == 'Filled':
        rows[l10n.status] = l10n.completed;
      default:
        rows[tradeNotificationCopy(l10n, e.key)] =
            tradeNotificationCopy(l10n, e.value);
    }
  }
  rows[l10n.date] = DateFormat('d MMM yyyy, HH:mm', l10n.localeName)
      .format(DateTime.fromMillisecondsSinceEpoch(item.time));
  if (showWallet && item.walletName?.isNotEmpty == true) {
    rows[l10n.accountWallet] = item.walletName!;
  }
  return TradeReceipt(
    leading: TradeNotificationArtwork(item: item),
    title: title,
    subtitle: outcome,
    rows: rows,
    transaction: predictions
        ? TradeReceiptTransaction.polygon(hash)
        : TradeReceiptTransaction.hyperliquid(hash),
  );
}

/// The outcome token a Predictions receipt is about, read from its id
/// (`pm-fill:<account>:<tx>:<asset>:…` or `pm:<account>:<asset>:<payout>`).
String? tradeNotificationAsset(TradeNotification item) {
  final parts = item.id.split(':');
  if (parts.first == 'pm-fill' && parts.length > 3) return parts[3];
  if (parts.first == 'pm' && parts.length > 2) return parts[2];
  return null;
}

/// The results-inbox receipt screen: the result as the heading at the top,
/// then the receipt card. "View prediction" leads when the position is
/// still open in the spending wallet; the list the receipt belongs to
/// (Activity for fills, Positions otherwise) is then the second button.
KuteConfirmation tradeNotificationConfirmation(
  AppLocalizations l10n,
  TradeNotification item, {
  required bool showWallet,
  required VoidCallback onList,
  VoidCallback? onViewPrediction,
}) {
  final listLabel = item.id.startsWith('pm-fill:')
      ? l10n.activity
      : l10n.ledgerPositionsTitle;
  return KuteConfirmation(
    message: tradeNotificationCopy(l10n, item.title),
    messageAboveReceipt: true,
    success: item.positive && !item.read,
    celebrate: item.positive && !item.read,
    showCloseButton: true,
    buttonText: onViewPrediction == null ? listLabel : l10n.betViewPrediction,
    onDone: onViewPrediction ?? onList,
    secondaryButtonText: onViewPrediction == null ? null : listLabel,
    onSecondary: onViewPrediction == null ? null : onList,
    receipt: tradeNotificationReceipt(l10n, item, showWallet: showWallet),
  );
}

/// Opens [item]'s receipt over the results inbox (already popped).
void openTradeNotificationReceipt({
  required NavigatorState navigator,
  required ProviderContainer container,
  required AppLocalizations l10n,
  required TradeNotification item,
}) {
  final settings = container.read(settingsProvider);
  final wallet =
      settings.wallets.where((w) => w.id == item.walletId).firstOrNull;
  final spending =
      wallet != null && pickSpendingWallet(settings)?.id == wallet.id;
  PolymarketPosition? position;
  final asset = tradeNotificationAsset(item);
  final pm = container.read(polymarketTradingProvider).valueOrNull;
  if (spending &&
      asset != null &&
      pm?.proxyWalletAddress?.toLowerCase() == item.account.toLowerCase()) {
    position = container
        .read(polymarketActivePositionsProvider)
        .where((p) => p.tokenId == asset && p.size > 0)
        .firstOrNull;
  }
  final product = item.product == 'predictions'
      ? InvestmentsProduct.predictions
      : InvestmentsProduct.trading;
  final tab = item.id.startsWith('pm-fill:') ? 2 : 0;
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: tradeNotificationConfirmation(
      l10n,
      item,
      showWallet: settings.wallets.length > 1,
      onViewPrediction: position == null
          ? null
          : () {
              navigator.pop();
              PositionDetailSheet.show(navigator.context, position: position!);
            },
      onList: () {
        navigator.pop();
        if (wallet == null) return;
        if (wallet.isLedger) {
          navigator.push(MaterialPageRoute(
              builder: (_) => LedgerPortfolioScreen(
                  walletId: wallet.id, product: product, initialTab: tab)));
        } else if (spending) {
          navigator.push(MaterialPageRoute(
              builder: (_) =>
                  OpenInvestmentsScreen(product: product, initialTab: tab)));
        }
      },
    ),
  );
}
