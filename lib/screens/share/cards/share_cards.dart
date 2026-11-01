// lib/screens/share/cards/share_cards.dart
//
// THE SHARE CARD FAMILY (founder, 1 November 2026: "sending bitcoin or
// dollars or predictions should be like this. Sending a stock should show
// the actual stock with a nice design, this is important"). One widget,
// [ShareCard], drawing [ShareCardData] (share_card_data.dart) in the brag
// card's frame (share_card_frame.dart), 4:5, captured at 1080 × 1350:
//
//   * MONEY: "{Name}, I sent you" over the big amount ("₿12,000" with
//     "$9.40" in a pill, or "$10.00"), Sal smug with his line, "Claim on
//     Kute". Bitcoin orange for bitcoin, Kute green for dollars.
//   * PREDICTION: the market's picture and question (two lines), the
//     headline (the market's odds by topic, share_card_copy.dart), the
//     pick as a big pill ("Yes · 47%") and "$10 on it" when sent as a
//     pick, the chance over the week when loaded, Sal in his shades
//     ("Trust me on this one."), "Place it on Kute"; shared without a pick
//     the leading outcome's odds, "What do you think?", "Make your call on
//     Kute". Polymarket blue.
//   * INVESTMENT: THE ACTUAL STOCK: its real logo (HlCoinIcon), display
//     name and ticker, the headline ("Tesla is $242.10, up 3.4% today"),
//     today's change in a coloured pill, the side ("Long") and amount when
//     sent as a pick, the last 30 days' closes as a smooth line full
//     width, "Trade it on Kute". Deep navy with the change's colour as the
//     glow.
//
// The RECIPIENT's version ([ShareCardAudience.recipient]) is the claim
// screen's hero: "{Name}, a friend sent you", "It's yours. Tap claim."
// and Sal's warm lines; no chip (the claim button is the bar).
//
// Real data only: what is null is left out. The card never reads a
// provider or the screen's scale: the preview is exactly the image.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart';
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart';

/// The gradients.
const List<Color> kShareBitcoinGradient = [Color(0xFFF9A23B), Color(0xFFB0500A)];
const List<Color> kShareDollarsGradient = [Color(0xFF15B866), Color(0xFF05532C)];
const List<Color> kSharePredictionGradient = [
  Color(0xFF3B7BFF),
  Color(0xFF0A2A80)
];
const List<Color> kShareInvestmentGradient = [
  Color(0xFF1B2238),
  Color(0xFF05070D)
];

/// Today's change: up, down.
const Color kShareUp = Color(0xFF22C97A);
const Color kShareDown = Color(0xFFFF5468);

/// Sal on the cards with more to show: a little smaller than the brag
/// card's.
const double kShareSalSmall = 140;

/// The still Sal wears on [data]'s card.
String shareCardSalAsset(ShareCardData data) {
  if (data.audience == ShareCardAudience.recipient) return kShareSalSmug;
  return switch (data) {
    MoneyCardData() => kShareSalSmug,
    PredictionCardData(picked: true) => kShareSalShades,
    PredictionCardData() => kShareSalSmug,
    InvestmentCardData(:final change) =>
      (change ?? 0) > 0 ? kShareSalShades : kShareSalSmug,
  };
}

class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.data, this.sal, this.lineSeed = 0});

  final ShareCardData data;

  /// The decoded still ([shareCardSalAsset], ShareCardSal); null: no Sal.
  final ui.Image? sal;

  /// Picks Sal's line in the card's pool (shareCardLine).
  final int lineSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final line = shareCardLine(l10n, data, lineSeed);
    final recipient = data.audience == ShareCardAudience.recipient;
    final cta = data is MoneyCardData || recipient
        ? l10n.shareCardJoinMeOnKute
        : l10n.bragBeatMeOnKute;
    final code = recipient ? null : data.referralCode;
    final salKey = ValueKey(
        'share-card-sal-${shareCardSalAsset(data).split('/').last.split('.').first}');
    switch (data) {
      case final MoneyCardData d:
        return ShareCardFrame(
          key: ValueKey('share-card-${d.kind}'),
          colors: d.bitcoin ? kShareBitcoinGradient : kShareDollarsGradient,
          wordmarkDot: d.bitcoin ? kShareCardDark : null,
          cta: cta,
          code: code,
          sal: sal,
          salKey: salKey,
          body: _MoneyBody(data: d, line: line),
        );
      case final PredictionCardData d:
        return ShareCardFrame(
          key: ValueKey('share-card-${d.kind}'),
          colors: kSharePredictionGradient,
          cta: cta,
          code: code,
          sal: sal,
          salKey: salKey,
          salHeight: kShareSalSmall,
          body: _PredictionBody(data: d, line: line),
        );
      case final InvestmentCardData d:
        final change = d.change;
        final accent = change == null || change.abs() < 0.0005
            ? null
            : change > 0
                ? kShareUp
                : kShareDown;
        return ShareCardFrame(
          key: ValueKey('share-card-${d.kind}'),
          colors: kShareInvestmentGradient,
          glow: accent,
          background: accent == null
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.9, -0.85),
                      radius: 1.1,
                      colors: [
                        accent.withValues(alpha: 0.26),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
          cta: cta,
          code: code,
          sal: sal,
          salKey: salKey,
          salHeight: kShareSalSmall,
          body: _InvestmentBody(data: d, line: line, accent: accent),
        );
    }
  }
}

/// The left column beside the big Sal: the card's width less the margins
/// and Sal, a little under him.
const double _kMoneyColumn = 360 - 44 - 184 * kShareCardSalAspect + 18;

/// The column beside the smaller Sal.
const double _kSmallColumn = 360 - 44 - kShareSalSmall * kShareCardSalAspect + 14;

/// The band at the bottom of the body beside the smaller Sal: the bubble
/// over the chip.
const double _kSalBand = 100;

Widget _topLine(String text, {double size = 14}) => Text(
      text,
      key: const ValueKey('share-card-top'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: shareCardText(size, FontWeight.w700,
          kShareCardInk.withValues(alpha: 0.92),
          spacing: -0.3, height: 1.2),
    );

/// The headline's size: 26 with room (a market shared, no pick row),
/// else 23, a step down for a long one (a German sentence).
double _headlineSize(String text, {required bool roomy}) {
  final base = roomy ? 26.0 : 23.0;
  return text.length > 44 ? base - 3 : base;
}

Widget _chip(String label) => ShareCardChip(
      key: const ValueKey('share-card-chip'),
      label: label,
    );

/// The bubble over the chip, beside the smaller Sal.
class _SalBand extends StatelessWidget {
  const _SalBand({required this.line, this.chip});

  final String line;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kSalBand),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          width: _kSmallColumn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: ShareCardBubble(text: line, maxLines: 2),
              ),
              const SizedBox(height: 12),
              if (chip != null) _chip(chip!),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Money ───────────────────────────────────────────────────────────

class _MoneyBody extends StatelessWidget {
  const _MoneyBody({required this.data, required this.line});

  final MoneyCardData data;
  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recipient = data.audience == ShareCardAudience.recipient;
    final top = shareCardTopLine(l10n, data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top != null) _topLine(top, size: 17),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            data.amount,
            key: const ValueKey('share-card-amount'),
            maxLines: 1,
            style: shareCardText(64, FontWeight.w800, kShareCardInk,
                spacing: -2.6, height: 1.05, tabular: true),
          ),
        ),
        if (data.amountSub != null) ...[
          const SizedBox(height: 8),
          ShareCardPill(
            key: const ValueKey('share-card-amount-sub'),
            text: data.amountSub!,
            size: 16,
          ),
        ],
        if (recipient) ...[
          const SizedBox(height: 12),
          Text(
            l10n.claimCardTapClaim,
            key: const ValueKey('share-card-tap-claim'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: shareCardText(16, FontWeight.w700,
                kShareCardInk.withValues(alpha: 0.9),
                spacing: -0.2),
          ),
        ],
        const SizedBox(height: 18),
        Expanded(
          child: SizedBox(
            width: _kMoneyColumn,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: ShareCardBubble(text: line),
                ),
                const Spacer(),
                if (!recipient) _chip(l10n.shareCardClaimChip),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Prediction ──────────────────────────────────────────────────────

class _PredictionBody extends StatelessWidget {
  const _PredictionBody({required this.data, required this.line});

  final PredictionCardData data;
  final String line;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loc = l10n.localeName;
    final recipient = data.audience == ShareCardAudience.recipient;
    final top = shareCardTopLine(l10n, data);
    final headline = predictionHeadline(l10n, data);
    final outcome = shareCardOutcome(l10n, data.outcome);
    final chance = data.chance;
    final pickText = chance == null
        ? outcome
        : recipient
            ? l10n.claimCardPickChance(outcome, shareCardChance(loc, chance))
            : '$outcome · ${shareCardChance(loc, chance)}';
    final series = data.series;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top != null) ...[_topLine(top), const SizedBox(height: 8)],
        Row(
          children: [
            ShareCardLogo(
              key: const ValueKey('share-card-logo'),
              size: 40,
              title: data.question,
              investing: false,
              imageUrl: data.imageUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.question,
                key: const ValueKey('share-card-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: shareCardText(15, FontWeight.w800,
                    kShareCardInk.withValues(alpha: 0.95),
                    spacing: -0.3, height: 1.2),
              ),
            ),
          ],
        ),
        if (headline != null) ...[
          const SizedBox(height: 10),
          ShareCardHeadline(
            key: const ValueKey('share-card-headline'),
            text: headline.text,
            emphasis: headline.emphasis,
            size: _headlineSize(headline.text, roomy: !data.picked),
            maxLines: 3,
          ),
        ],
        if (data.picked) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShareCardPill(
                key: const ValueKey('share-card-pick'),
                text: pickText,
                size: 17,
              ),
              if (data.amount != null)
                Text(
                  l10n.shareCardAmountOnIt(data.amount!),
                  key: const ValueKey('share-card-amount'),
                  maxLines: 1,
                  style: shareCardText(17, FontWeight.w800, kShareCardInk,
                      spacing: -0.3, tabular: true),
                ),
            ],
          ),
        ],
        Expanded(
          child: series != null && series.length >= 2
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: SizedBox(
                    key: const ValueKey('share-card-chart'),
                    width: double.infinity,
                    child: CustomPaint(
                        painter: ShareCardLinePainter(points: series)),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        _SalBand(
          line: line,
          chip: recipient
              ? null
              : data.picked
                  ? l10n.shareCardPlaceChip
                  : l10n.shareCardCallChip,
        ),
      ],
    );
  }
}

// ─── Investment ──────────────────────────────────────────────────────

class _InvestmentBody extends StatelessWidget {
  const _InvestmentBody(
      {required this.data, required this.line, required this.accent});

  final InvestmentCardData data;
  final String line;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loc = l10n.localeName;
    final recipient = data.audience == ShareCardAudience.recipient;
    final top = shareCardTopLine(l10n, data);
    final headline = investmentHeadline(l10n, data);
    final change = data.change;
    final series = data.series;
    final side = data.side;
    final ticker = data.ticker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top != null) ...[_topLine(top), const SizedBox(height: 8)],
        Row(
          children: [
            ShareCardLogo(
              key: const ValueKey('share-card-logo'),
              size: 42,
              round: true,
              title: data.title,
              investing: true,
              coin: data.coin,
              wireCoin: data.wireCoin,
              iconUrl: data.iconUrl,
              category: data.category,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.title,
                    key: const ValueKey('share-card-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shareCardText(20, FontWeight.w800, kShareCardInk,
                        spacing: -0.5, height: 1.1),
                  ),
                  if (ticker != null && ticker != data.title) ...[
                    const SizedBox(height: 2),
                    Text(
                      ticker,
                      key: const ValueKey('share-card-ticker'),
                      maxLines: 1,
                      style: shareCardText(12, FontWeight.w700,
                          kShareCardInk.withValues(alpha: 0.6),
                          spacing: 0.8),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (headline != null) ...[
          const SizedBox(height: 10),
          ShareCardHeadline(
            key: const ValueKey('share-card-headline'),
            text: headline.text,
            emphasis: headline.emphasis,
            size: _headlineSize(headline.text, roomy: !data.picked),
            maxLines: 3,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (change != null && accent != null)
              ShareCardPill(
                key: const ValueKey('share-card-change'),
                text: l10n.shareCardToday(shareCardChangeSigned(loc, change)),
                size: 13,
                fill: accent,
                color: kShareCardInk,
              ),
            if (side != null)
              ShareCardPill(
                key: const ValueKey('share-card-side'),
                text: side == 'short' ? l10n.shortLabel : l10n.longLabel,
                size: 13,
              ),
            if (data.amount != null)
              Text(
                l10n.shareCardAmountOnIt(data.amount!),
                key: const ValueKey('share-card-amount'),
                maxLines: 1,
                style: shareCardText(15, FontWeight.w800, kShareCardInk,
                    spacing: -0.3, tabular: true),
              ),
          ],
        ),
        Expanded(
          child: series != null && series.length >= 2
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: SizedBox(
                    key: const ValueKey('share-card-chart'),
                    width: double.infinity,
                    child: CustomPaint(
                      painter: ShareCardLinePainter(
                          points: series, color: accent ?? kShareCardInk),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        _SalBand(line: line, chip: recipient ? null : l10n.shareCardTradeChip),
      ],
    );
  }
}
