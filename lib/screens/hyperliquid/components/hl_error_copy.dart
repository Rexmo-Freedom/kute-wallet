import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/hyperliquid_error_message.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/theme/app_theme.dart';

export 'package:kute/helpers/hyperliquid_error_message.dart';

/// Only a bounded exchange rejection is suitable for optional user details.
/// HTTP bodies and arbitrary exceptions can contain request or account data.
/// Details are the fallback for a rejection the app has no words for; the
/// minimum's own line ("Minimum is $X.") needs none.
String? hlTradeRejectionDetails(Object? error) {
  if (error is! HyperliquidRejectedException) return null;
  if (hlIsMinNotionalError(error)) return null;
  final reason =
      error.reason.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (reason.isEmpty) return null;
  return reason.length > 800 ? '${reason.substring(0, 800)}…' : reason;
}

class HlTradeErrorNotice extends StatelessWidget {
  const HlTradeErrorNotice({super.key, required this.message, this.error});

  final String message;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = hlTradeRejectionDetails(error);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded,
                color: c.textSecondary, size: 20.sp),
            SizedBox(width: 10.w),
            Expanded(
                child: Text(message,
                    style: TextStyle(
                        color: c.textPrimary, fontSize: 14.sp, height: 1.4))),
          ]),
          // Collapsed until asked for: the raw venue text is the fallback
          // for a rejection the app has no words for. Its own transparent
          // Material, so the tile's ink is not hidden by the card's fill.
          if (details != null)
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.only(bottom: 12.h),
                  title: Text(context.l10n.details,
                      style:
                          TextStyle(color: c.textSecondary, fontSize: 13.sp)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(details,
                          style: TextStyle(
                              color: c.textSecondary, fontSize: 12.sp)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
