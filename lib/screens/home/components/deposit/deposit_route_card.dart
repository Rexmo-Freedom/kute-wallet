// lib/screens/home/components/deposit/deposit_route_card.dart
//
// The Move sheet's route, as one card instead of two side-by-side
// chips: a From row and a To row stacked on a single neutral surface,
// each with the pool or wallet's mark, its name, where it sits and —
// on the right of the row that carries it — what is available to move.
// The flip affordance is the one circle riding the hairline between
// the rows.
//
// Purely presentational: every tap is a callback the Move sheet owns,
// exactly the ones the two chips carried before.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

/// One end of a move: the pool or wallet the money leaves, or the one
/// it lands in.
class MoveRouteEndpoint {
  const MoveRouteEndpoint({
    required this.name,
    required this.asset,
    this.assetTint,
    this.iconData,
    this.iconColor,
    this.origin,
    this.available,
    this.onAvailableTap,
    this.detail,
    this.detailIsError = false,
    this.onTap,
  });

  /// Pool or wallet name shown on the first line ("Bitcoin",
  /// "Investing", "Predictions", a savings wallet's own name).
  final String name;

  /// Brand SVG for the mark. Ignored when [iconData] is set.
  final String asset;

  /// `ColorFilter.srcIn` tint for [asset] — hardware brand marks ship
  /// with a single-color fill that vanishes on light surfaces.
  final Color? assetTint;

  /// Glyph fallback for wallets with no brand SVG (tracked address,
  /// watch-only, generic hardware).
  final IconData? iconData;
  final Color? iconColor;

  /// Which account the money sits in: "Spending", "Savings", a Ledger's
  /// name. Null when there is only one account it could be.
  final String? origin;

  /// What this end has to move ("$124.50"), shown on the right of the
  /// row over the word "available". Null draws nothing there.
  final String? available;

  /// Tapping the available balance fills the maximum. Only the balance
  /// itself carries it, so the rest of the row still opens the picker.
  final VoidCallback? onAvailableTap;

  /// A state on the line under the name, after the origin: an
  /// over-typed amount, a balance that is loading or unavailable.
  final String? detail;

  /// Renders [detail] in the error color.
  final bool detailIsError;

  /// Null makes the row inert — a pinned endpoint shows no chevron.
  final VoidCallback? onTap;
}

/// The route on one card. With both ends it is From over To with the
/// flip circle between them. With one end it is that row alone, no
/// divider and no flip: the other side is the sheet's own subject and
/// there is nothing to choose about it. A deposit states where the
/// money comes from, a cash-out states where it lands.
class MoveRouteCard extends StatelessWidget {
  const MoveRouteCard({
    super.key,
    this.from,
    this.to,
    this.onSwap,
  }) : assert(from != null || to != null, 'a route needs at least one end');

  /// Null renders the To row alone.
  final MoveRouteEndpoint? from;

  /// Null renders the From row alone.
  final MoveRouteEndpoint? to;

  /// Null disables the flip (both ends pinned, or the sheet is busy).
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: to == null
          ? _MoveRouteRow(label: context.l10n.from, endpoint: from!)
          : from == null
              ? _MoveRouteRow(label: context.l10n.to, endpoint: to!)
              : Stack(
              alignment: Alignment.centerRight,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MoveRouteRow(
                        label: context.l10n.from,
                        endpoint: from!,
                        reserveFlip: true),
                    Padding(
                      padding: EdgeInsets.only(left: 62.w),
                      child: Divider(
                          height: 1, thickness: 0.5, color: c.borderSubtle),
                    ),
                    _MoveRouteRow(
                        label: context.l10n.to,
                        endpoint: to!,
                        reserveFlip: true),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(right: 14.w),
                  child: Material(
                    color: c.background,
                    shape: CircleBorder(
                      side: BorderSide(color: c.borderSubtle, width: 0.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onSwap,
                      child: SizedBox(
                        width: 38.sp,
                        height: 38.sp,
                        child: Icon(
                          Icons.swap_vert_rounded,
                          color:
                              onSwap == null ? c.textTertiary : c.textPrimary,
                          size: 20.sp,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MoveRouteRow extends StatelessWidget {
  const _MoveRouteRow({
    required this.label,
    required this.endpoint,
    this.reserveFlip = false,
  });

  final String label;
  final MoveRouteEndpoint endpoint;

  /// Keeps the right edge clear of the flip circle riding the hairline
  /// of a two-row card. A single row has no circle to avoid.
  final bool reserveFlip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final origin = endpoint.origin;
    final detail = endpoint.detail;
    final available = endpoint.available;
    final body = Padding(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
      child: Row(
        children: [
          SizedBox(
            width: 34.sp,
            height: 34.sp,
            child: Center(
              child: endpoint.iconData != null
                  ? Container(
                      width: 32.sp,
                      height: 32.sp,
                      decoration: BoxDecoration(
                        color: (endpoint.iconColor ?? c.textPrimary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Icon(endpoint.iconData,
                          color: endpoint.iconColor ?? c.textPrimary,
                          size: 18.sp),
                    )
                  : SvgPicture.asset(
                      endpoint.asset,
                      width: 32.sp,
                      height: 32.sp,
                      colorFilter: endpoint.assetTint != null
                          ? ColorFilter.mode(
                              endpoint.assetTint!, BlendMode.srcIn)
                          : null,
                    ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        endpoint.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (endpoint.onTap != null)
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: c.textTertiary, size: 18.sp),
                  ],
                ),
                if (origin != null || detail != null) ...[
                  SizedBox(height: 2.h),
                  Text.rich(
                    TextSpan(children: [
                      if (origin != null) TextSpan(text: origin),
                      if (origin != null && detail != null)
                        const TextSpan(text: ' · '),
                      if (detail != null)
                        TextSpan(
                          text: detail,
                          style: TextStyle(
                            color: endpoint.detailIsError
                                ? AppColors.error
                                : c.textSecondary,
                          ),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (available != null) ...[
            SizedBox(width: 10.w),
            _AvailableBalance(
                value: available, onTap: endpoint.onAvailableTap),
          ],
          // Keeps the row clear of the flip circle riding the hairline.
          if (reserveFlip) SizedBox(width: 44.w),
        ],
      ),
    );
    if (endpoint.onTap == null) {
      return body;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: endpoint.onTap, child: body),
    );
  }
}

/// The balance on the right of a route row: the figure over the word
/// "available", in the row's own name and caption styles.
class _AvailableBalance extends StatelessWidget {
  const _AvailableBalance({required this.value, required this.onTap});

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          context.l10n.moveAvailableCaption,
          maxLines: 1,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
    if (onTap == null) {
      return column;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
          child: column,
        ),
      ),
    );
  }
}
