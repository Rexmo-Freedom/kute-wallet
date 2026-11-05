// lib/screens/share/receipt_share.dart
//
// EVERY RECEIPT SHARES (founder, 5 November 2026: "All these
// transactions, next to View on the blockchain, should have the share and
// a special share card"). A transaction's receipt (transactions_builder
// .dart, hyperliquid_fill_activity.dart) hands its bar a [ReceiptShare]
// (ReceiptBarAction.share, receipt_parts.dart): the round Sal button
// beside the bar's primary (View on the blockchain, View market, Track
// this exchange, Claim now; Done where the receipt has no action of its
// own) opens [openReceiptShare]:
//
//   * a won prediction with its cost known ([ReceiptShare.won]): the won
//     brag card ("CALLED IT", brag_card.dart), as the receipt's "Brag
//     about it" card does;
//   * anything else: the card preview (share_card_preview.dart) with the
//     receipt's own card ([ReceiptCardData], cards/receipt_card.dart),
//     built live from the providers while the preview is up, the bar
//     "Share" sending the PNG.
//
// THE BUILDERS ([moneyReceiptShare], [predictionReceiptShare],
// [tradeReceiptShare]) take the receipt's own figures (sats, dollars, the
// market's title and picture) and format them as the brag cards do: money
// in the person's currency (bragMoney), bitcoin as the app writes it
// (conversionProvider), its value only once the price is known. Never an
// address, a transaction id or an order id.
//
// THE MESSAGE ([receiptShareText]): a market's card carries "{title} on
// Kute {link}" with the sharer's code on the link (the brag cards' text);
// a money card the app's invite with the sharer's code ("I'm using Kute.
// Join with my link"), nothing without a code.
//
// Analytics: `receipt_card_shared {card, result}` once the OS share sheet
// answered: `card` the card's kind (`receipt_sent`, `receipt_predicted`,
// …), `result` its status (success | dismissed | unavailable | error). No
// figure, no market, no id. The won card reports `brag_shared` (card:
// won), as from any other door.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionProvider, conversionToFiatProvider, currentBtcUsdProvider;
import 'package:kute/screens/share/brag/brag_data.dart'
    show BragWin, bragMoney, bragSignedMoney, kBragCentUsd;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart'
    show showBragPreviewSheet;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart'
    show showShareCardPreviewSheet;
import 'package:kute/screens/share/cards/share_card_sources.dart'
    show ShareCardWatch;
import 'package:kute/screens/share/share_market_sheet.dart'
    show shareLinkWithReferral;
import 'package:kute/screens/shared/kute_share_actions.dart'
    show kMarketLinkInvesting, kMarketLinkPredictions, marketShareLink;
import 'package:kute/services/appsflyer_service.dart' show AppsFlyerService;
import 'package:kute/services/tracking_service.dart';

/// The preview's route name, for the route observers.
const String kReceiptCardPreviewRoute = 'receipt_card_preview';

/// What a receipt's round Sal button shares (see the file header).
class ReceiptShare {
  const ReceiptShare(this.card, {this.won});

  /// The receipt's card, built from the providers (live in the preview).
  final ReceiptCardData Function(ShareCardWatch watch) card;

  /// A won prediction's brag card, read when the button is tapped: when it
  /// gives one, that card opens instead of [card].
  final BragWin? Function(ShareCardWatch watch)? won;
}

/// Opens [share]'s card from a receipt (see the file header).
Future<void> openReceiptShare(BuildContext context, ReceiptShare share) {
  final container = ProviderScope.containerOf(context, listen: false);
  T read<T>(ProviderListenable<T> p) => container.read(p);
  final won = share.won?.call(read);
  if (won != null) return showBragPreviewSheet(context, won);
  final l10n = context.l10n;
  return showShareCardPreviewSheet(
    context,
    title: l10n.shareCardReadyTitle,
    shareLabel: l10n.share,
    routeName: kReceiptCardPreviewRoute,
    source: 'receipt_card',
    build: share.card,
    text: (context) => receiptShareText(context.l10n, share.card(read)),
    onShared: (result) => TrackingService.track('receipt_card_shared',
        params: {'card': share.card(read).kind, 'result': result}),
  );
}

/// The message under a receipt's card (see the file header).
String receiptShareText(AppLocalizations l10n, ReceiptCardData d) {
  final code = d.referralCode?.trim() ?? '';
  final link = d.link;
  final title = d.title?.trim() ?? '';
  if (link != null && title.isNotEmpty) {
    return l10n.bragShareText(title, shareLinkWithReferral(link, code: code));
  }
  if (code.isEmpty) return '';
  String? invite;
  try {
    invite = AppsFlyerService.shareLink(code);
  } catch (_) {
    // The link template is not loaded (a test, an early start): the code.
  }
  return invite != null
      ? l10n.walletsShareTextWithLinkNoDiscount(invite)
      : l10n.walletsShareTextWithCodeNoDiscount(code);
}

/// The sharer's own referral code for the footer; null without one.
String? receiptReferralCode() {
  final code = AffiliateService.affiliateCode?.trim() ?? '';
  return code.isEmpty ? null : code;
}

/// [sats] as the app writes bitcoin ("₿12,000"), and its value in the
/// person's currency once the price is known.
({String? bitcoin, String? fiat}) _bitcoin(ShareCardWatch watch, int sats) {
  if (sats <= 0) return (bitcoin: null, fiat: null);
  try {
    final btc = watch(conversionProvider(sats));
    final priced = watch(currentBtcUsdProvider) > 0;
    return (
      bitcoin: btc,
      fiat: priced ? watch(conversionToFiatProvider(sats)) : null,
    );
  } catch (_) {
    return (bitcoin: null, fiat: null);
  }
}

/// A money receipt's card (sent, received, on its way, moved, bought,
/// sold): [amount] as the receipt wrote it (a bank order's own currency),
/// else [usd] in the person's currency when the receipt counts in
/// dollars, else [sats]' value; [sats] as the bitcoin under it. [asset]
/// is the card's colour (where the money went, on a move); [from] and
/// [to] a move's accounts, [what] what was bought or sold.
ReceiptShare moneyReceiptShare({
  required ReceiptCardKind type,
  required ReceiptCardAsset asset,
  String? amount,
  double? usd,
  int? sats,
  String? from,
  String? to,
  String? what,
}) =>
    ReceiptShare((watch) {
      final b = sats == null ? null : _bitcoin(watch, sats);
      final money = amount ??
          (usd != null && usd.isFinite && usd > 0
              ? bragMoney(watch, usd)
              : b?.fiat);
      return ReceiptCardData(
        type: type,
        asset: asset,
        amount: money,
        bitcoin: b?.bitcoin,
        from: from,
        to: to,
        what: what,
        referralCode: receiptReferralCode(),
      );
    });

/// A prediction's receipt card: placed ([chance] the price paid, [usd]
/// the stake), sold ([usd] the proceeds, [pnlUsd] the result when the
/// receipt knows it), lost ([usd] the stake), paid out ([usd] the
/// payout). [won] tries the won brag card first.
ReceiptShare predictionReceiptShare({
  required ReceiptCardKind type,
  required String title,
  String? side,
  String? imageUrl,
  String? eventSlug,
  double? chance,
  double? usd,
  double? pnlUsd,
  BragWin? Function(ShareCardWatch watch)? won,
}) =>
    ReceiptShare((watch) {
      final money =
          usd != null && usd.isFinite && usd > 0 ? bragMoney(watch, usd) : null;
      final double? pnl = switch (type) {
        ReceiptCardKind.lost => usd == null ? null : -usd,
        ReceiptCardKind.paidOut => usd,
        _ => pnlUsd,
      };
      final result = pnl == null || !pnl.isFinite
          ? null
          : type == ReceiptCardKind.cashedOut && pnl.abs() < kBragCentUsd
              ? null
              : bragSignedMoney(watch, pnl);
      final slug = eventSlug?.trim() ?? '';
      final image = imageUrl?.trim() ?? '';
      return ReceiptCardData(
        type: type,
        asset: ReceiptCardAsset.predictions,
        amount: money,
        result: type == ReceiptCardKind.predicted ? null : result,
        pnl: pnl,
        title: title.trim(),
        side: side?.trim(),
        imageUrl: image.isEmpty ? null : image,
        chance: chance != null && chance > 0 && chance < 1 ? chance : null,
        link: marketShareLink(
            venue: kMarketLinkPredictions, slug: slug.isEmpty ? null : slug),
        referralCode: receiptReferralCode(),
      );
    }, won: won);

/// An Investing trade's receipt card: opened ([price] the entry) or
/// closed ([price] the exit, [pnlUsd] what closing realised); [size] in
/// the market's units ("2.5 TSLA"), [usd] the trade's value; [spot] a
/// token bought or sold.
ReceiptShare tradeReceiptShare({
  required ReceiptCardKind type,
  required String title,
  String? ticker,
  String? coin,
  String? wireCoin,
  String? iconUrl,
  String? category,
  String? side,
  bool spot = false,
  String? price,
  String? size,
  double? usd,
  double? pnlUsd,
}) =>
    ReceiptShare((watch) {
      final pnl =
          pnlUsd != null && pnlUsd.isFinite && pnlUsd != 0 ? pnlUsd : null;
      return ReceiptCardData(
        type: type,
        asset: ReceiptCardAsset.investing,
        amount: usd != null && usd.isFinite && usd > 0
            ? bragMoney(watch, usd)
            : null,
        result: pnl == null ? null : bragSignedMoney(watch, pnl),
        pnl: pnl,
        title: title,
        ticker: ticker,
        coin: coin,
        wireCoin: wireCoin,
        iconUrl: iconUrl,
        category: category,
        side: side,
        spot: spot,
        price: price,
        size: size,
        link: marketShareLink(venue: kMarketLinkInvesting, slug: coin),
        referralCode: receiptReferralCode(),
      );
    });
