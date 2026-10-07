import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Label left in `textSecondary`, value right in `textPrimary`: the detail
/// row vocabulary of the transaction sheet, recreated here so coin surfaces
/// share it without reaching into the transaction builder's private helpers.
///
/// [copiable] rows copy the full [value] on tap and confirm with the app's
/// toast plus a haptic. [onTap] with a [trailingIcon] turns the row into a
/// generic affordance (the label rows use an edit glyph).
class SheetDetailRow extends StatelessWidget {
  const SheetDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.copiable = false,
    this.truncate = false,
    this.onCopied,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool copiable;

  /// Middle-ellipsis for long hex strings (8 + 8 characters). The copied
  /// text is always the full [value].
  final bool truncate;

  /// Runs after a successful copy; callers hook tracking here.
  final VoidCallback? onCopied;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final display = truncate && value.length > 16
        ? '${value.substring(0, 8)}...${value.substring(value.length - 8)}'
        : value;
    final icon = trailingIcon ?? (copiable ? Icons.copy_rounded : null);
    final tap = onTap ?? (copiable ? () => _copy(context) : null);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              )),
          SizedBox(width: 12.w),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(display,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: valueColor ?? c.textPrimary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                  if (icon != null) ...[
                    SizedBox(width: 6.w),
                    Icon(icon, color: c.accent, size: 12.sp),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copy(BuildContext context) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: value));
    showMessageSnackBarInfo(
        context: context, message: context.l10n.copiedToClipboard);
    onCopied?.call();
  }
}

/// Grows or shrinks with its child instead of snapping to the new height.
/// The detail sheets wrap their content in one so the modal itself glides
/// when a disclosure opens or a graph finishes loading, and the disclosures
/// use one too (the outer one then follows the inner frame by frame).
/// Content stays pinned to the top while the height changes, and the OS
/// reduced motion setting turns the glide into an instant resize.
class SheetAnimatedSize extends StatelessWidget {
  const SheetAnimatedSize({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSize(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// The scroll body of a detail sheet: a [SingleChildScrollView] whose
/// content sits in a [SheetAnimatedSize], so the modal glides to its new
/// height when a disclosure opens or a graph finishes loading, and scrolls
/// as usual once the content passes the sheet's maximum height.
class SheetScrollView extends StatelessWidget {
  const SheetScrollView({super.key, this.padding, required this.child});
  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      padding: padding, child: SheetAnimatedSize(child: child));
}

/// Collapsed technical block: the transaction sheet's "Nerd data" pattern.
/// Closed by default so ids and heights stay one tap away without crowding
/// the human rows above.
///
/// [title] names the block (default "Nerd data"); [expandedTitle], when
/// set, replaces it while open ("Show 3 more" / "Show less"). [onToggle]
/// hears each open and close, for the callers that count opens.
class SheetNerdDataSection extends StatefulWidget {
  const SheetNerdDataSection({
    super.key,
    required this.children,
    this.title,
    this.expandedTitle,
    this.onToggle,
  });
  final List<Widget> children;
  final String? title;
  final String? expandedTitle;
  final ValueChanged<bool>? onToggle;

  @override
  State<SheetNerdDataSection> createState() => _SheetNerdDataSectionState();
}

class _SheetNerdDataSectionState extends State<SheetNerdDataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 8.h),
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
            widget.onToggle?.call(_expanded);
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18.sp,
                  color: c.textTertiary,
                ),
                SizedBox(width: 4.w),
                Flexible(
                  child: Text(
                    (_expanded ? widget.expandedTitle : null) ??
                        widget.title ??
                        context.l10n.activityNerdData,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The rows grow into place instead of snapping open.
        SheetAnimatedSize(
          child: _expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 4.h),
                    ...widget.children,
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Full-width outlined explorer link, the transaction sheet's "View in
/// Mempool" chrome. Opens in the in-app browser and falls back to the
/// external browser where the platform cannot host one.
class SheetLinkButton extends StatelessWidget {
  const SheetLinkButton({
    super.key,
    required this.label,
    required this.uri,
    this.onPressed,
  });

  final String label;
  final Uri uri;

  /// Runs before the launch (the sheets close themselves first).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      height: 48.h,
      child: OutlinedButton.icon(
        onPressed: () async {
          onPressed?.call();
          if (!await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        icon: Icon(Icons.open_in_new_rounded, size: 18.sp),
        label: Text(label,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonBorder),
        ),
      ),
    );
  }
}
