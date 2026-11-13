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
// The edgy line comes from a pool of 10 to 15 per kind (founder, 5
// November 2026: "add many more variations"; [receiptCardEdges]), a sale
// or a close by its result's sign, a prediction placed by its odds.
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
      // The coin on her head, never the briefcase and glasses (founder,
      // 5 November 2026).
      ReceiptCardKind.sent => ShareCardPose.claim,
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

/// The edgy lines that may go on a receipt's card (see the file header):
/// 10 to 15 per kind, a sale or a close by its result's sign (an unknown
/// result only lines that claim none), a prediction placed by the chance
/// it was placed at (the favourite "Went with the odds. Shocking.", the
/// underdog "41% says I'm early, not wrong.", "The crowd is 59%
/// wrong."). A figure in a line is the card's own.
List<String> receiptCardEdges(AppLocalizations l10n, ReceiptCardData d) {
  final loc = l10n.localeName;
  String? text(String? s) => s?.trim().isNotEmpty == true ? s!.trim() : null;
  final money = text(d.amount);
  // The card's big number on a money receipt.
  final figure = money ?? text(d.bitcoin);
  final result = text(d.result);
  final price = text(d.price);
  final side = text(d.side) == null ? null : shareCardOutcome(l10n, d.side!);
  List<String> exit() => switch (d.pnl == null ? null : _sign(d.pnl)) {
        // No result known: nothing that names one.
        null => [
            l10n.receiptEdgeInAndOut,
            l10n.receiptEdgeUpWhenToLeave,
            l10n.receiptEdgeDownExits,
            l10n.receiptEdgeSoldLeftDrama,
            l10n.receiptEdgeSoldCashPosition,
            l10n.receiptEdgeSoldDeliberately,
          ],
        1 => [
            l10n.receiptEdgeTookWin,
            l10n.receiptEdgeUpInUpOut,
            l10n.receiptEdgeUpEgo,
            l10n.receiptEdgeUpWhileGreen,
            l10n.receiptEdgeUpWhenToLeave,
            if (result != null) l10n.receiptEdgeUpDoneHere(result),
            l10n.receiptEdgeUpBooked,
            l10n.receiptEdgeUpNoEncore,
            l10n.receiptEdgeUpGreed,
            l10n.receiptEdgeUpDiscipline,
            l10n.receiptEdgeUpWinIsWin,
            l10n.bragEdgeWonNoNotes,
          ],
        -1 => [
            l10n.receiptEdgeCutIt,
            l10n.receiptEdgeDownDignity,
            l10n.receiptEdgeDownExits,
            l10n.receiptEdgeDownQuick,
            l10n.receiptEdgeDownLessonKept,
            l10n.receiptEdgeDownStubborn,
            l10n.receiptEdgeDownTookL,
            l10n.receiptEdgeDownNotMyDay,
            l10n.receiptEdgeDownZeroTears,
            l10n.receiptEdgeDownHalfSkill,
            if (result != null) l10n.receiptEdgeDownTuition(result),
            l10n.shareEdgeBragNotOut,
          ],
        _ => [
            l10n.receiptEdgeInAndOut,
            l10n.receiptEdgeFlatRoundTrip,
            l10n.receiptEdgeFlatWiser,
            l10n.receiptEdgeFlatZeroStress,
            l10n.receiptEdgeFlatNoHarm,
            l10n.receiptEdgeFlatShrugged,
            l10n.receiptEdgeFlatStory,
            l10n.shareEdgeBragUndefeated,
            l10n.shareEdgeBragNetCalm,
            l10n.shareEdgeBragSteadyHands,
            l10n.shareEdgeBragDidntPanic,
            l10n.shareEdgeBragBalanced,
          ],
      };
  switch (d.type) {
    case ReceiptCardKind.sent:
      return [
        l10n.receiptEdgeNoBank,
        l10n.receiptEdgeSentNext,
        l10n.receiptEdgeSentNoHold,
        l10n.receiptEdgeSentBeforeBank,
        l10n.receiptEdgeSentDrama,
        l10n.receiptEdgeSentBusinessDays,
        l10n.receiptEdgeSentThankLater,
        l10n.receiptEdgeSentEfficient,
        l10n.receiptEdgeSentOneTap,
        l10n.receiptEdgeSentPaidUp,
        l10n.receiptEdgeSentAdult,
        if (figure != null) l10n.receiptEdgeSentGone(figure),
        l10n.receiptEdgeSentSaga,
      ];
    case ReceiptCardKind.received:
      return [
        l10n.receiptEdgeLanded,
        l10n.shareEdgeMoneyFlex,
        l10n.receiptEdgeReceivedCasual,
        l10n.receiptEdgeReceivedNoted,
        if (figure != null) l10n.receiptEdgeReceivedRicher(figure),
        l10n.receiptEdgeReceivedThankYou,
        l10n.receiptEdgeReceivedMoodUp,
        l10n.receiptEdgeReceivedGrace,
        l10n.receiptEdgeReceivedAskTwice,
        l10n.receiptEdgeReceivedUnscheduled,
        l10n.receiptEdgeReceivedNoMiddle,
        l10n.receiptEdgeReceivedCompliments,
      ];
    case ReceiptCardKind.incoming:
      return [
        l10n.receiptEdgeIncoming,
        l10n.receiptEdgeIncomingAlmost,
        l10n.receiptEdgeIncomingLoading,
        l10n.receiptEdgeIncomingRefreshing,
        l10n.receiptEdgeIncomingNotChecking,
        l10n.receiptEdgeIncomingPending,
        l10n.receiptEdgeIncomingPatienceMode,
        l10n.receiptEdgeIncomingSnacks,
        l10n.receiptEdgeIncomingMinute,
        l10n.receiptEdgeIncomingMotion,
        l10n.receiptEdgeIncomingWatched,
      ];
    case ReceiptCardKind.moved:
      return [
        l10n.receiptEdgeMoved,
        l10n.receiptEdgeMovedFurniture,
        l10n.receiptEdgeMovedDidntLose,
        l10n.receiptEdgeMovedPockets,
        l10n.receiptEdgeMovedRelocated,
        l10n.receiptEdgeMovedNewRoom,
        l10n.receiptEdgeMovedHousekeeping,
        l10n.receiptEdgeMovedShuffle,
        l10n.receiptEdgeMovedGrownUp,
        l10n.receiptEdgeMovedOrganised,
        l10n.receiptEdgeMovedTidying,
        l10n.receiptEdgeMovedAllocating,
      ];
    case ReceiptCardKind.bought:
      return [
        l10n.receiptEdgeStacked,
        l10n.receiptEdgeBoughtOverthink,
        l10n.receiptEdgeBoughtPile,
        l10n.receiptEdgeBoughtAccumulation,
        l10n.receiptEdgeBoughtToldNoOne,
        l10n.receiptEdgeBoughtNotTiming,
        if (figure != null) l10n.receiptEdgeBoughtConviction(figure),
        l10n.receiptEdgeBoughtPatience,
        l10n.receiptEdgeBoughtNoise,
        l10n.receiptEdgeBoughtBackToDay,
        l10n.receiptEdgeBoughtShoes,
      ];
    case ReceiptCardKind.sold:
      return [
        l10n.receiptEdgeTookSome,
        l10n.receiptEdgeSoldKeptCool,
        l10n.receiptEdgeSoldNoRegrets,
        l10n.receiptEdgeSoldDidntCheck,
        l10n.receiptEdgeSoldLiquidity,
        l10n.receiptEdgeSoldLeftDrama,
        l10n.receiptEdgeSoldSleeping,
        l10n.receiptEdgeSoldCashPosition,
        l10n.receiptEdgeSoldDeliberately,
        l10n.receiptEdgeSoldPressed,
        l10n.receiptEdgeSoldLittleCash,
      ];
    case ReceiptCardKind.predicted:
      // By the whole percent the speedometer shows.
      final c = d.chance;
      final shown = c != null && c > 0 && c < 1 ? (c * 100).round() : null;
      return [
        l10n.receiptEdgeLockedIn,
        l10n.receiptEdgeOnRecord,
        l10n.receiptEdgePredictedCommitted,
        l10n.receiptEdgePredictedHardPart,
        l10n.receiptEdgePredictedSkin,
        l10n.receiptEdgePredictedNails,
        l10n.receiptEdgePredictedTookSide,
        l10n.receiptEdgePredictedJustMySide,
        l10n.receiptEdgePredictedResolution,
        if (money != null && side != null)
          l10n.receiptEdgePredictedThatsThePost(money, side),
        if (shown != null && shown >= 50) ...[
          l10n.shareEdgePickWithOdds,
          l10n.shareEdgePickSafePick,
        ],
        // "41% says I'm early", "The crowd is 59% wrong": only for the
        // underdog.
        if (shown != null && shown < 50) ...[
          l10n.shareEdgePredictionEarly(shareCardChance(loc, c! * 100)),
          l10n.shareEdgePredictionCrowd(shareCardChance(loc, 100.0 - shown)),
          l10n.shareEdgePickLongShot,
          l10n.shareEdgePickContrarian,
        ],
      ];
    case ReceiptCardKind.cashedOut:
    case ReceiptCardKind.closed:
      return exit();
    case ReceiptCardKind.lost:
      return [
        l10n.receiptEdgeWrongToday,
        l10n.receiptEdgeLesson,
        l10n.receiptEdgeLostNextQuestion,
        l10n.receiptEdgeLostRudely,
        l10n.receiptEdgeLostHumour,
        l10n.receiptEdgeLostCompany,
        l10n.receiptEdgeLostOnMe,
        l10n.receiptEdgeLostConfidence,
        l10n.receiptEdgeLostWrongly,
        l10n.receiptEdgeLostGraceful,
        l10n.receiptEdgeLostOddsWereOdds,
        l10n.receiptEdgeLostAlreadyMoved,
        l10n.receiptEdgeLostUpLesson,
        l10n.receiptEdgeDownTookL,
      ];
    case ReceiptCardKind.paidOut:
      return [
        l10n.receiptEdgeCollected,
        l10n.receiptEdgePaidResolved,
        l10n.receiptEdgePaidNormal,
        if (money != null) l10n.receiptEdgePaidInFull(money),
        l10n.receiptEdgePaidCourtesy,
        l10n.bragEdgeWonReceipts,
        l10n.bragEdgeWonPaysSometimes,
        l10n.bragEdgeWonAgreed,
        l10n.bragEdgeWonNoNotes,
        l10n.bragEdgeWonCollecting,
        l10n.bragEdgeWonThenPayout,
        l10n.bragEdgeWonMySide,
      ];
    case ReceiptCardKind.opened:
      return [
        l10n.receiptEdgeOpened,
        l10n.receiptEdgeOnRecord,
        if (!d.spot) l10n.receiptEdgeOpenedPulse,
        l10n.receiptEdgeOpenedCalmly,
        if (price != null) l10n.receiptEdgeOpenedInAt(price),
        l10n.receiptEdgeOpenedNotRefreshing,
        l10n.receiptEdgeOpenedSized,
        l10n.receiptEdgeOpenedJustMine,
        l10n.receiptEdgeOpenedUnderstanding,
        l10n.receiptEdgeOpenedMyProblem,
        l10n.receiptEdgeOpenedEither,
        l10n.shareEdgeStockFeelings,
      ];
  }
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

    ShareCardIdentity? identity(
            {bool investing = false, String? meta, String? held}) =>
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
                side: held,
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
          identity: identity(held: side),
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
