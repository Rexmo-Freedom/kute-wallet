// lib/screens/share/cards/share_card_versus.dart
//
// BOTH SIDES ON A CHALLENGE CARD (founder, 4 November 2026: "I think
// Bitcoin will win, wanna fight me?"). A prediction sent as a dare draws
// the market's two sides side by side instead of the speedometer: the
// sender's side MARKED (filled in the card's ink, the card's own colour
// for its words: "MY SIDE", "Yes", "62%") and the other side open
// (outlined, "YOUR SIDE?", "No", "38%"), a small "VS" between them. A
// side's chance is the market's own, left out when not read; a named
// market's other side is its strongest rival, "?" when the market has not
// been read yet (never a made-up name).
//
// The card's colours only, no provider, no screen scale: the preview is
// exactly the image.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:kute/screens/share/cards/share_card_frame.dart';

/// One side of the dare.
@immutable
class ShareCardVersusSide {
  const ShareCardVersusSide({
    required this.tag,
    required this.name,
    this.chance,
    this.imageUrl,
  });

  /// The caps tag over it ("My side", "Your side?"), drawn uppercase.
  final String tag;

  /// The outcome ("Yes", "Gen.G"); "?" when unknown.
  final String name;

  /// Its chance as the card writes it ("62%"); null: not read.
  final String? chance;

  /// Its own picture (a team's crest); null: none.
  final String? imageUrl;
}

/// The tallest the blocks are drawn.
const double kShareVersusMaxHeight = 190;

/// The gap between the blocks, the VS badge sitting over it.
const double kShareVersusGap = 14;

/// The VS badge's side.
const double kShareVersusBadge = 34;

class ShareCardVersus extends StatelessWidget {
  const ShareCardVersus({
    super.key,
    required this.palette,
    required this.mine,
    required this.theirs,
    this.keyPrefix = 'share-card',
  });

  final ShareCardPalette palette;

  /// The sender's side (marked) and the side the friend is dared to take.
  final ShareCardVersusSide mine;
  final ShareCardVersusSide theirs;

  /// The keys: `{prefix}-versus`, `{prefix}-versus-mine`,
  /// `{prefix}-versus-theirs` and their `-tag`, `-name`, `-chance`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight.isFinite
          ? math.min(box.maxHeight, kShareVersusMaxHeight)
          : kShareVersusMaxHeight;
      return Center(
        child: SizedBox(
          key: ValueKey('$keyPrefix-versus'),
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Side(
                      key: ValueKey('$keyPrefix-versus-mine'),
                      side: mine,
                      marked: true,
                      palette: p,
                      keyPrefix: '$keyPrefix-versus-mine',
                    ),
                  ),
                  const SizedBox(width: kShareVersusGap),
                  Expanded(
                    child: _Side(
                      key: ValueKey('$keyPrefix-versus-theirs'),
                      side: theirs,
                      marked: false,
                      palette: p,
                      keyPrefix: '$keyPrefix-versus-theirs',
                    ),
                  ),
                ],
              ),
              Container(
                key: ValueKey('$keyPrefix-versus-badge'),
                width: kShareVersusBadge,
                height: kShareVersusBadge,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.ink, width: 1.5),
                ),
                child: Text(
                  'VS',
                  maxLines: 1,
                  style: shareCardText(11, FontWeight.w800, p.ink,
                      spacing: 0.6, height: 1),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Side extends StatelessWidget {
  const _Side({
    super.key,
    required this.side,
    required this.marked,
    required this.palette,
    required this.keyPrefix,
  });

  final ShareCardVersusSide side;
  final bool marked;
  final ShareCardPalette palette;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    // Marked: the ink's block, the card's colour for its words.
    final words = marked ? p.background : p.ink;
    final image = side.imageUrl;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: marked ? p.ink : null,
        borderRadius: BorderRadius.circular(20),
        border: marked ? null : Border.all(color: p.muted, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Smaller rather than cut.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              side.tag.toUpperCase(),
              key: ValueKey('$keyPrefix-tag'),
              maxLines: 1,
              style: shareCardText(11, FontWeight.w700,
                  marked ? words.withValues(alpha: 0.8) : p.muted,
                  spacing: 1.1, height: 1.2),
            ),
          ),
          const Spacer(),
          if (image != null && image.isNotEmpty) ...[
            ShareCardLogo(
              size: 28,
              title: side.name,
              investing: false,
              palette: p,
              imageUrl: image,
            ),
            const SizedBox(height: 8),
          ],
          // The name whole where it can be: two lines, smaller rather
          // than cut.
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  side.name,
                  key: ValueKey('$keyPrefix-name'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: shareCardText(22, FontWeight.w700, words,
                      spacing: -0.4, height: 1.1),
                ),
              ),
            ),
          ),
          if (side.chance != null) ...[
            const SizedBox(height: 4),
            Text(
              side.chance!,
              key: ValueKey('$keyPrefix-chance'),
              maxLines: 1,
              style: shareCardText(34, FontWeight.w600, words,
                  spacing: -0.8, height: 1.05, tabular: true),
            ),
          ],
        ],
      ),
    );
  }
}
