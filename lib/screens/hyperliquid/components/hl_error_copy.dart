import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/hyperliquid_error_message.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/slip_form_body.dart';
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

/// An order the venue refused, told on the ticket. The raw venue text
/// (when the app has no words of its own for it) is one tap away in a
/// bottom sheet; a ticket short of room shows the notice as one line whose
/// tap opens it all there too. Nothing opens in place.
class HlTradeErrorNotice extends StatelessWidget {
  const HlTradeErrorNotice({super.key, required this.message, this.error});

  final String message;
  final Object? error;

  Widget _details(AppColorsExtension c, String details) => SelectableText(
      details,
      style: TextStyle(color: c.textSecondary, fontSize: 12.sp, height: 1.4));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = hlTradeRejectionDetails(error);
    final decoration = BoxDecoration(
      color: c.surface,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: c.border),
    );
    // A ticket short of room says it in one line; a tap reads it all.
    final lines = SlipDensity.noticeLines(context);
    if (lines != null) {
      return SlipNoticeLine(
        maxLines: lines,
        icon: Icons.info_outline_rounded,
        message: message,
        decoration: decoration,
        onOpen: () => showSlipDetailSheet(context,
            title: context.l10n.details,
            children: [
              Text(message,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 15.sp, height: 1.4)),
              if (details != null) ...[
                SizedBox(height: 12.h),
                _details(c, details),
              ],
            ]),
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: decoration,
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
          // One tap away, in a sheet: the raw venue text is the fallback
          // for a rejection the app has no words for.
          if (details != null)
            Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showSlipDetailSheet(context,
                      title: context.l10n.details,
                      children: [_details(c, details)]),
                  child: Row(children: [
                    Text(context.l10n.details,
                        style:
                            TextStyle(color: c.textSecondary, fontSize: 13.sp)),
                    Icon(Icons.chevron_right_rounded,
                        size: 18.sp, color: c.textSecondary),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
