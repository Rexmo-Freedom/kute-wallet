// lib/screens/share/cards/receipt_card.dart
//
// THE RECEIPT CARDS (founder, 5 November 2026: "All these transactions,
// next to View on the blockchain, should have the share and a special
// share card"). Every receipt's round Sal button opens one of these
// (screens/share/receipt_share.dart), drawn in the family's one frame
// (share_card_frame.dart): one solid colour, one big number, Sal in a
// pose, the edgy line, the wordmark and the sharer's code. Per kind
// ([ReceiptCardKind]):
//
//   * SENT / RECEIVED / ON ITS WAY: the money huge. Bitcoin on the app's
//     ink with the amount in orange (the bitcoin send's own card, founder,
//     2 November 2026), its value in the person's currency and "in
//     bitcoin · ₿12,000" under it; dollars on the green. Sal hands it
//     over (the briefcase) on a send, lounges with the coin on a receive.
//     "No bank was harmed in this payment."
//   * MOVED: between the person's own accounts, "Dollars → Bitcoin" under
//     the money, in the colour of where it went; Sal's side-eye. "Same
//     money. Better spot."
//   * BOUGHT · BITCOIN / SOLD · BITCOIN: what was paid (or got), the
//     bitcoin under it. "Stacked a little more."
//   * I'M ON YES (a prediction placed, blue): the market's picture and
//     question, the speedometer at the chance it was placed at ("Chance
//     when I got in"), "$10 on Yes"; Sal squinting at the odds. "Locked
//     in. Now we wait."
//   * CASHED OUT (a prediction sold): the result huge in green or red by
//     its sign, "Sold for $14.20" under it, the side as the meta; blue
//     when the receipt has no result.
//   * NOT THIS TIME (a prediction lost, only when the person shares it):
//     the stake lost, red, Sal's flop with one eye open; dry and classy,
//     never sad: "Wrong today. Back tomorrow.", "Lesson paid in full."
//   * PAID OUT (a payout the won card cannot measure: no cost known):
//     green, the payout huge. A payout with its cost opens the won brag
//     card instead (brag_card.dart, "CALLED IT").
//   * OPENED POSITION · LONG / BOUGHT (an Investing trade, navy): the
//     market's real logo, name and ticker, the entry price huge, "2.5 TSLA
//     · $250.00" under it. CLOSED POSITION · LONG / SOLD: the result huge
//     in its colour, "Exit price · $3,576.10", the size.
//
// Never an address, a transaction id or any identifier: only what the
// receipt's hero and tiles already show. PG, never "bet", never a promise
// of profit; a loss is shown only when the person chose to share it.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardChance, shareCardOutcome;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';
import 'package:kute/screens/share/cards/share_card_speedometer.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalClip;

/// Under this a result is nothing: no sign, no colour.
const double kReceiptCardCent = 0.005;

/// The logo's side in the identity row.
const double _kLogo = 36;

/// A result's sign: 1 up, −1 down, 0 flat or unknown.
int _sign(double? pnl) => pnl == null
    ? 0
    : pnl >= kReceiptCardCent
        ? 1
        : pnl <= -kReceiptCardCent
            ? -1
            : 0;

/// The card's colour (see the file header): a result by its sign, a
/// prediction blue, a trade navy, money by its asset (bitcoin on the
/// app's ink with the amount in orange).
ShareCardPalette receiptCardPalette(ReceiptCardData d) {
  switch (d.type) {
    case ReceiptCardKind.lost:
      return ShareCardPalette.loss;
    case ReceiptCardKind.paidOut:
      return ShareCardPalette.win;
    case ReceiptCardKind.cashedOut:
    case ReceiptCardKind.closed:
      return switch (_sign(d.pnl)) {
        1 => ShareCardPalette.win,
        -1 => ShareCardPalette.loss,
        _ => d.type == ReceiptCardKind.cashedOut
            ? ShareCardPalette.prediction
            : ShareCardPalette.investment,
      };
    case ReceiptCardKind.predicted:
      return ShareCardPalette.prediction;
    case ReceiptCardKind.opened:
      return ShareCardPalette.investment;
    case ReceiptCardKind.sent:
    case ReceiptCardKind.received:
    case ReceiptCardKind.incoming:
    case ReceiptCardKind.moved:
    case ReceiptCardKind.bought:
    case ReceiptCardKind.sold:
      return switch (d.asset) {
        ReceiptCardAsset.bitcoin => ShareCardPalette.bitcoinClaim,
        ReceiptCardAsset.dollars => ShareCardPalette.dollars,
        ReceiptCardAsset.predictions => ShareCardPalette.prediction,
        ReceiptCardAsset.investing => ShareCardPalette.investment,
      };
  }
}

/// Sal's pose (see the file header).
ShareCardPose receiptCardPose(ReceiptCardData d) => switch (d.type) {
      ReceiptCardKind.sent => ShareCardPose.send,
      ReceiptCardKind.received ||
      ReceiptCardKind.incoming ||
      ReceiptCardKind.bought =>
        d.asset == ReceiptCardAsset.bitcoin
            ? ShareCardPose.claim
            : ShareCardPose.win,
      ReceiptCardKind.moved || ReceiptCardKind.sold => ShareCardPose.flat,
      ReceiptCardKind.predicted ||
      ReceiptCardKind.opened =>
        ShareCardPose.predict,
      ReceiptCardKind.cashedOut || ReceiptCardKind.closed => switch (
            _sign(d.pnl)) {
          1 => ShareCardPose.win,
          -1 => ShareCardPose.loss,
          _ => ShareCardPose.flat,
        },
      ReceiptCardKind.lost => ShareCardPose.loss,
      ReceiptCardKind.paidOut => ShareCardPose.win,
    };

/// An Investing trade's side in the app's language ("Long", "Short").
String _sideLabel(AppLocalizations l10n, String? side) =>
    side == 'short' ? l10n.shortLabel : l10n.longLabel;

/// The caps line at the top of a receipt's card (see the file header).
String receiptCardTopLine(AppLocalizations l10n, ReceiptCardData d) {
  final what =
      d.what?.trim().isNotEmpty == true ? d.what!.trim() : l10n.bitcoin;
  return switch (d.type) {
    ReceiptCardKind.sent => l10n.sent,
    ReceiptCardKind.received => l10n.received,
    ReceiptCardKind.incoming => l10n.activityOnItsWay,
    ReceiptCardKind.moved => l10n.receiptCardMoved,
    ReceiptCardKind.bought => l10n.activityRowBought(what),
    ReceiptCardKind.sold => l10n.activityRowSold(what),
    ReceiptCardKind.predicted =>
      l10n.receiptCardOnSide(shareCardOutcome(l10n, d.side ?? '')),
    ReceiptCardKind.cashedOut => l10n.receiptCardCashedOut,
    ReceiptCardKind.lost => l10n.receiptCardNotThisTime,
    ReceiptCardKind.paidOut => l10n.receiptCardPaidOut,
    ReceiptCardKind.opened => d.spot
        ? l10n.investingBought
        : '${l10n.hlFillOpened} · ${_sideLabel(l10n, d.side)}',
    ReceiptCardKind.closed => d.spot
        ? l10n.investingSold
        : '${l10n.hlFillClosed} · ${_sideLabel(l10n, d.side)}',
  };
}

/// The edgy lines that may go on a receipt's card (see the file header).
List<String> receiptCardEdges(AppLocalizations l10n, ReceiptCardData d) {
  List<String> result() => switch (_sign(d.pnl)) {
        1 => [l10n.receiptEdgeTookWin],
        -1 => [l10n.receiptEdgeCutIt],
        _ => [l10n.receiptEdgeInAndOut],
      };
  return switch (d.type) {
    ReceiptCardKind.sent => [l10n.receiptEdgeNoBank, l10n.receiptEdgeSentNext],
    ReceiptCardKind.received => [
        l10n.receiptEdgeLanded,
        l10n.shareEdgeMoneyFlex
      ],
    ReceiptCardKind.incoming => [l10n.receiptEdgeIncoming],
    ReceiptCardKind.moved => [l10n.receiptEdgeMoved],
    ReceiptCardKind.bought => [l10n.receiptEdgeStacked],
    ReceiptCardKind.sold => [l10n.receiptEdgeTookSome],
    ReceiptCardKind.predicted => [
        l10n.receiptEdgeLockedIn,
        l10n.receiptEdgeOnRecord,
        // "41% says I'm early": only for the underdog.
        if (d.chance case final c? when c > 0 && c < 0.5)
          l10n.shareEdgePredictionEarly(
              shareCardChance(l10n.localeName, c * 100)),
      ],
    ReceiptCardKind.cashedOut || ReceiptCardKind.closed => result(),
    ReceiptCardKind.lost => [
        l10n.receiptEdgeWrongToday,
        l10n.receiptEdgeLesson
      ],
    ReceiptCardKind.paidOut => [l10n.receiptEdgeCollected],
    ReceiptCardKind.opened => [
        l10n.receiptEdgeOpened,
        l10n.receiptEdgeOnRecord
      ],
  };
}

/// One receipt's card in the family's frame (see the file header).
class ReceiptShareCard extends StatelessWidget {
  const ReceiptShareCard({
    super.key,
    required this.data,
    required this.caps,
    required this.line,
    this.mark,
  });

  final ReceiptCardData data;

  /// The caps line and the edgy line (share_card_copy.dart picks them).
  final String caps;
  final String line;

  /// Sal's decoded face (ShareCardSal).
  final SalClip? mark;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = data;
    final p = receiptCardPalette(d);
    final pose = receiptCardPose(d);
    final key = ValueKey('share-card-${d.kind}');
    final code = d.referralCode;
    final money = d.amount?.trim().isNotEmpty == true ? d.amount!.trim() : null;
    final btc = d.bitcoin?.trim().isNotEmpty == true ? d.bitcoin!.trim() : null;
    final result =
        d.result?.trim().isNotEmpty == true ? d.result!.trim() : null;
    final sign = _sign(d.pnl);
    final resultColor = sign > 0
        ? p.up
        : sign < 0
            ? p.down
            : null;
    final side = d.side?.trim().isNotEmpty == true
        ? shareCardOutcome(l10n, d.side!)
        : null;
    final title = d.title?.trim() ?? '';

    ShareCardIdentity? identity({bool investing = false, String? meta}) =>
        title.isEmpty
            ? null
            : ShareCardIdentity(
                palette: p,
                logo: ShareCardLogo(
                  key: const ValueKey('share-card-logo'),
                  size: _kLogo,
                  title: title,
                  investing: investing,
                  palette: p,
                  imageUrl: d.imageUrl,
                  coin: d.coin,
                  wireCoin: d.wireCoin,
                  iconUrl: d.iconUrl,
                  category: d.category,
                ),
                name: title,
                meta: meta,
              );

    switch (d.type) {
      case ReceiptCardKind.sent:
      case ReceiptCardKind.received:
      case ReceiptCardKind.incoming:
      case ReceiptCardKind.moved:
      case ReceiptCardKind.bought:
      case ReceiptCardKind.sold:
        final path = d.type == ReceiptCardKind.moved &&
                (d.from?.isNotEmpty ?? false) &&
                (d.to?.isNotEmpty ?? false)
            ? '${d.from} → ${d.to}'
            : null;
        final inBitcoin =
            btc != null && money != null ? l10n.shareCardInBitcoin(btc) : null;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          // The money in the person's currency, the bitcoin under it;
          // without the money, the bitcoin alone.
          number: money ?? btc ?? '—',
          numberBase: kShareCardMoneyHeroMax,
          // A move: the bitcoin under the money, then its path.
          fact: inBitcoin ?? path,
          plain: inBitcoin != null ? path : null,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
      case ReceiptCardKind.predicted:
        final chance = d.chance;
        final has = chance != null && chance > 0 && chance < 1;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: identity(),
          // The chance it was placed at on the open-position screen's
          // speedometer; without one, the stake alone.
          number: has ? null : (money ?? side),
          numberMax: kShareCardHeroMax,
          graphic: has
              ? ShareCardSpeedometer(
                  key: const ValueKey('share-card-odds'),
                  palette: p,
                  fraction: chance,
                  figure: shareCardChance(l10n.localeName, chance * 100),
                  caption: l10n.receiptCardEntryChance,
                )
              : null,
          graphicFills: has,
          plain: has && money != null && side != null
              ? l10n.shareCardAmountOn(money, side)
              : null,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
      case ReceiptCardKind.cashedOut:
      case ReceiptCardKind.lost:
      case ReceiptCardKind.paidOut:
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: identity(meta: side),
          number: result ?? money ?? '—',
          numberMax: kShareCardHeroMax,
          fact: d.type == ReceiptCardKind.cashedOut &&
                  result != null &&
                  money != null
              ? l10n.receiptCardSoldFor(money)
              : null,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
      case ReceiptCardKind.opened:
      case ReceiptCardKind.closed:
        final price =
            d.price?.trim().isNotEmpty == true ? d.price!.trim() : null;
        final ticker = d.ticker?.trim();
        final size = [
          if (d.size?.trim().isNotEmpty == true) d.size!.trim(),
          if (money != null) money,
        ].join(' · ');
        final closed = d.type == ReceiptCardKind.closed;
        final hero = closed ? (result ?? price ?? money) : (price ?? money);
        // A position's entry or exit; a token's price.
        final priceLabel = d.spot
            ? l10n.price2
            : closed
                ? l10n.investingExitPrice
                : l10n.hlChartEntry;
        final String? fact = price == null
            ? null
            : closed && result != null
                ? '$priceLabel · $price'
                : priceLabel;
        return ShareCardFrame(
          key: key,
          palette: p,
          caps: caps,
          identity: identity(
              investing: true,
              meta: ticker != null && ticker.isNotEmpty && ticker != title
                  ? ticker
                  : null),
          number: hero ?? '—',
          numberMax: kShareCardHeroMax,
          fact: fact,
          factColor: closed && result != null ? resultColor : null,
          plain: size.isEmpty ? null : size,
          line: line,
          code: code,
          mark: mark,
          pose: pose,
        );
    }
  }
}
