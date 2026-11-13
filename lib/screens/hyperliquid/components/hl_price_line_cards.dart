// lib/screens/hyperliquid/components/hl_price_line_cards.dart
//
// The Chart sheet's PRICE LINES section, in its square cards: a card to set
// a new line and one per line, its price and where it stands, with a round
// button in the place of an indicator's tune button. Also what setting and
// removing a line do, shared by the chart and the sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hl_price_line.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hl_price_lines_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Sets a line on [market] at [level]. Says why when it cannot be set, and
/// returns whether it was.
bool hlPlacePriceLine(
  BuildContext context,
  WidgetRef ref, {
  required HlMarket market,
  required String marketKey,
  required double level,
  required double? reference,
}) {
  final refusal = ref.read(hlPriceLinesProvider.notifier).add(
        market: market,
        marketKey: marketKey,
        level: level,
        reference: reference,
      );
  if (refusal != null) {
    final l10n = context.l10n;
    showMessageSnackBarInfo(
      context: context,
      message: switch (refusal) {
        HlPriceLineRefusal.limit => l10n.chartPriceLineLimit(kHlPriceLineLimit),
        HlPriceLineRefusal.atPrice => l10n.chartPriceLineAtPrice,
        HlPriceLineRefusal.tooFar => l10n.chartPriceLineTooFar,
      },
    );
    return false;
  }
  TrackingService.track('price_alert_created', params: {
    'market_kind': market.kind.name,
    'direction': level > reference! ? 'above' : 'below',
  });
  return true;
}

/// Removes [line]. [via] is `chart` or `list`.
void hlRemovePriceLine(WidgetRef ref, HlPriceLine line, {required String via}) {
  ref.read(hlPriceLinesProvider.notifier).remove(line.id);
  TrackingService.track('price_alert_deleted', params: {
    'market_kind': line.kind.name,
    'direction': line.direction.name,
    'reached': line.isReached,
    'via': via,
  });
}

/// A tap on a line on the chart: asks first, since a tap on the plot is easy
/// to make by accident and there is no undo for a line.
Future<void> hlConfirmRemovePriceLine(
  BuildContext context,
  WidgetRef ref,
  HlPriceLine line, {
  int? decimalCap,
}) async {
  final l10n = context.l10n;
  final confirmed = await showAppBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.chartPriceLineRemoveTitle,
            subtitle: l10n.chartPriceLineRemoveBody(
              line.coin,
              formatHlPrice(line.level, decimalCap: decimalCap),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
            child: AppBottomSheetButton(
              key: const ValueKey('hl-price-line-remove-confirm'),
              text: l10n.chartPriceLineRemoveCta,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ),
          AppBottomSheetTextButton(
            text: l10n.cancel,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    ),
  );
  if (confirmed == true) hlRemovePriceLine(ref, line, via: 'chart');
}

/// The sheet's card to set a new line.
class HlPriceLineNewCard extends StatelessWidget {
  const HlPriceLineNewCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey('hl-chart-price-line-new'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: _CardBody(
          reached: false,
          trailing: _RoundIcon(icon: Icons.add_rounded, color: c.textPrimary),
          title: l10n.chartPriceLineNew,
          note: l10n.chartPriceLineNewNote,
        ),
      ),
    );
  }
}

/// One line in the sheet: its price, where it stands, and its remove button.
class HlPriceLineCard extends StatelessWidget {
  const HlPriceLineCard({
    super.key,
    required this.line,
    required this.onRemove,
    this.decimalCap,
  });

  final HlPriceLine line;
  final VoidCallback onRemove;
  final int? decimalCap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final reachedAt = line.reachedAtMs;
    return Semantics(
      container: true,
      child: _CardBody(
        reached: line.isReached,
        trailing: Semantics(
          button: true,
          label: l10n.chartPriceLineRemoveTitle,
          excludeSemantics: true,
          child: GestureDetector(
            key: ValueKey('hl-chart-price-line-remove-${line.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onRemove();
            },
            child: _RoundIcon(icon: Icons.close_rounded, color: c.textPrimary),
          ),
        ),
        title: formatHlPrice(line.level, decimalCap: decimalCap),
        note: reachedAt != null
            ? l10n.chartPriceLineReachedOn(DateFormat('d MMM, HH:mm')
                .format(DateTime.fromMillisecondsSinceEpoch(reachedAt)))
            : line.direction == HlPriceLineDirection.above
                ? l10n.chartPriceLineAbove
                : l10n.chartPriceLineBelow,
      ),
    );
  }
}

/// An indicator card's layout: the small picture with a round button beside
/// it, the name, the note.
class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.reached,
    required this.trailing,
    required this.title,
    required this.note,
  });

  final bool reached;
  final Widget trailing;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return HlSquareBox(
      picked: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 30,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _MiniLinePainter(
                      color: reached ? c.textTertiary : c.textSecondary,
                      reached: reached,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                trailing,
              ],
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// The indicator card's round tune button, with another icon.
class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 30,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      );
}

/// A tiny price line: the mark and the dashes, as on the chart.
class _MiniLinePainter extends CustomPainter {
  _MiniLinePainter({required this.color, required this.reached});

  final Color color;
  final bool reached;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final stroke = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const mark = 16.0;
    for (var x = mark + 4; x < size.width; x += 10) {
      final end = x + 6 < size.width ? x + 6 : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), stroke);
    }
    hlPaintPriceLineMark(canvas, Offset(mark / 2, y), mark,
        color: color, reached: reached);
  }

  @override
  bool shouldRepaint(covariant _MiniLinePainter old) =>
      old.color != color || old.reached != reached;
}
