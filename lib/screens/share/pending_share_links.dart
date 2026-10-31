// lib/screens/share/pending_share_links.dart
//
// The sender's receipt for a share link: "$12.00 · Ana" over "Link sent ·
// waiting for Ana to claim", in the Send to list-row style
// (SendToListRow in SendToListCard), so it reads like the recents it sits
// near. [PendingShareLinkRow] is one row (the Send to anyone sheet shows
// it as the receipt); [PendingShareLinksCard] is the list under a "Links
// you sent" header, hidden when there is nothing pending (the Activity
// screen mounts it above the transactions).
//
// Tapping a row opens its detail: Share again (the same OS share sheet,
// while the link is open and this device has its URL) and Cancel link
// (`POST /cancel`; the row turns Cancelled). Nothing here moves money.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendToListCard, SendToListRow, SendToSectionHeader;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/theme/app_theme.dart';

/// One link this wallet sent, as a Send to list row.
class PendingShareLinkRow extends ConsumerWidget {
  const PendingShareLinkRow({super.key, required this.row, this.onTap});

  final PendingShareLink row;

  /// Null opens the row's detail sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final amount =
        shareLinkAmountLabel(context, ref, row.kind, row.amountMinor);
    final name = row.label?.trim() ?? '';
    final done = row.status == ShareLinkStatus.paid ||
        row.status == ShareLinkStatus.cancelled ||
        row.status == ShareLinkStatus.expired;
    return SendToListRow(
      colors: c,
      leading: Icon(
        done ? Icons.check_rounded : Icons.ios_share_rounded,
        color: done ? c.textTertiary : c.textPrimary,
        size: 20.sp,
      ),
      title: name.isEmpty ? amount : '$amount · $name',
      subtitle: shareLinkStatusLabel(context, row),
      onTap: onTap ?? () => showPendingShareLinkDetail(context, row),
    );
  }
}

/// "Links you sent" over the pending rows. Empty when there are none.
class PendingShareLinksCard extends ConsumerWidget {
  const PendingShareLinksCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(pendingShareLinksProvider);
    if (rows.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendToSectionHeader(title: context.l10n.sharePendingLinksTitle),
          SendToListCard(
            colors: c,
            rows: [for (final row in rows) PendingShareLinkRow(row: row)],
          ),
        ],
      ),
    );
  }
}

/// The row's detail: the receipt again, Share again and Cancel link.
Future<void> showPendingShareLinkDetail(
        BuildContext context, PendingShareLink row) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: 'share_link_detail'),
      builder: (_) => _PendingShareLinkDetail(id: row.id),
    );

class _PendingShareLinkDetail extends ConsumerStatefulWidget {
  const _PendingShareLinkDetail({required this.id});
  final String id;

  @override
  ConsumerState<_PendingShareLinkDetail> createState() =>
      _PendingShareLinkDetailState();
}

class _PendingShareLinkDetailState
    extends ConsumerState<_PendingShareLinkDetail> {
  bool _cancelling = false;
  String? _error;

  Future<void> _shareAgain(PendingShareLink row) async {
    final amount =
        shareLinkAmountLabel(context, ref, row.kind, row.amountMinor);
    final text = shareLinkMessage(context,
        name: row.label,
        amount: amount,
        url: row.url,
        outcome: row.outcome,
        title: row.marketTitle,
        venue: row.venue);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? (box.localToGlobal(ui.Offset.zero) & box.size)
        : (ui.Offset.zero & const ui.Size(1, 1));
    try {
      final r = await SharePlus.instance
          .share(ShareParams(text: text, sharePositionOrigin: origin));
      ShareLinkEvents.shared(row.kind, result: r.status.name);
    } catch (_) {
      ShareLinkEvents.shared(row.kind, result: 'error');
    }
  }

  Future<void> _cancel(PendingShareLink row) async {
    if (_cancelling) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await ref.read(shareLinksApiProvider).cancel(row.id);
      ShareLinksStore.setStatus(row.id, ShareLinkStatus.cancelled);
      ShareLinkEvents.cancelled(row.kind);
      if (mounted) Navigator.of(context).maybePop();
    } on ShareLinkApiException catch (e) {
      // Already claimed or paid: the backend refuses; the row follows.
      if (e.conflict) {
        ShareLinksStore.setStatus(row.id, ShareLinkStatus.claimed);
      }
      if (mounted) {
        setState(() => _error = context.l10n.shareLinkCancelFailed);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.shareLinkCancelFailed);
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(pendingShareLinksProvider);
    final row = ShareLinksStore.byId(widget.id);
    final l10n = context.l10n;
    final c = context.colors;
    if (row == null) return const SizedBox.shrink();
    final open = row.status == ShareLinkStatus.open;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.shareSendToAnyone,
            icon: Icons.ios_share_rounded,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SendToListCard(
                  colors: c,
                  rows: [PendingShareLinkRow(row: row, onTap: () {})],
                ),
                if (_error != null) ...[
                  SizedBox(height: 10.h),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (open) ...[
                  SizedBox(height: 20.h),
                  if (row.url.isNotEmpty)
                    AppButton(
                      key: const ValueKey('share-link-share-again'),
                      text: l10n.shareLinkShareAgain,
                      onPressed: () => unawaited(_shareAgain(row)),
                    ),
                  SizedBox(height: 8.h),
                  AppTextButton(
                    key: const ValueKey('share-link-cancel'),
                    text: _cancelling ? '…' : l10n.shareLinkCancel,
                    onPressed:
                        _cancelling ? null : () => unawaited(_cancel(row)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
