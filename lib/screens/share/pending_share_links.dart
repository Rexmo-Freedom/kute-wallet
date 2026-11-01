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
// Tapping a row opens its detail: Share again (while the link is open and
// this device has its URL: the link's share card first, the same card
// Send to anyone made, cards/share_card_preview.dart, then the OS share
// sheet with the PNG and the text) and Cancel link (`POST /cancel`; the
// row turns Cancelled). Nothing here moves money.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionProvider, conversionToFiatProvider;
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/share/share_link_resend.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/receipt_parts.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetScrollView;
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

  /// Share again: the link's card first (see the file header).
  Future<void> _shareAgain(PendingShareLink row) {
    final l10n = context.l10n;
    return showShareCardPreviewSheet(
      context,
      title: l10n.shareCardReadyTitle,
      shareLabel: l10n.share,
      routeName: 'share_link_card',
      source: 'share_link_again',
      build: (watch) {
        String? btc;
        String? fiat;
        if (row.kind == ShareLinkKind.bitcoin) {
          try {
            btc = watch(conversionProvider(row.amountMinor));
            fiat = watch(conversionToFiatProvider(row.amountMinor));
          } catch (_) {}
        }
        return shareCardForLink(
          watch,
          locale: l10n.localeName,
          kind: row.kind,
          amountMinor: row.amountMinor,
          recipient: row.label,
          marketSlug: row.marketSlug,
          marketTitle: row.marketTitle,
          venue: row.venue,
          outcome: row.outcome,
          bitcoinAmount: btc,
          bitcoinFiat: fiat,
          referralCode: AffiliateService.affiliateCode,
        );
      },
      text: (context) => shareLinkMessage(context,
          name: row.label,
          amount: shareLinkAmountLabel(context, ref, row.kind, row.amountMinor),
          url: row.url,
          outcome: row.outcome,
          title: row.marketTitle,
          venue: row.venue),
      onShared: (result) => ShareLinkEvents.shared(row.kind, result: result),
    );
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
    final done = row.status == ShareLinkStatus.paid ||
        row.status == ShareLinkStatus.cancelled ||
        row.status == ShareLinkStatus.expired;
    final name = row.label?.trim() ?? '';
    final pick = [
      if (row.outcome?.trim().isNotEmpty == true) row.outcome!.trim(),
      if (row.marketTitle?.trim().isNotEmpty == true) row.marketTitle!.trim(),
    ].join(' · ');
    String date(DateTime at) {
      try {
        return DateFormat('d MMM yyyy, HH:mm', l10n.localeName).format(at);
      } catch (_) {
        return DateFormat('d MMM yyyy, HH:mm').format(at);
      }
    }

    // The receipt's one structure (receipt_parts.dart): the hero, the
    // facts as tiles, the pick on its own row, Share again as the bar.
    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: SheetScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReceiptHero(
              leading: Container(
                width: 56.sp,
                height: 56.sp,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  done ? Icons.check_rounded : Icons.ios_share_rounded,
                  color: done ? c.textTertiary : c.textPrimary,
                  size: 26.sp,
                ),
              ),
              title: Text(
                l10n.shareSendToAnyone,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              amount: Text(
                shareLinkAmountLabel(context, ref, row.kind, row.amountMinor),
                style: receiptAmountStyle(c),
              ),
              result: shareLinkStatusLabel(context, row),
              resultColor: c.textSecondary,
            ),
            ReceiptFactTiles(facts: [
              if (name.isNotEmpty) ReceiptFact(label: l10n.to, value: name),
              ReceiptFact(label: l10n.date, value: date(row.createdAt)),
            ]),
            if (pick.isNotEmpty)
              ReceiptLongRow(label: l10n.betMarketCategory, value: pick),
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
              SizedBox(height: 12.h),
              // A contact's number (kept on the phone only), prefilled in
              // WhatsApp or the SMS composer. These and Cancel link stay on
              // the sheet as text buttons above the bar.
              if (row.url.isNotEmpty && row.recipientPhone != null) ...[
                AppTextButton(
                  key: const ValueKey('share-link-whatsapp'),
                  text: l10n.shareSendAgainWhatsApp,
                  onPressed: () => unawaited(resendShareLinkVia(
                      context, ref, row, ShareLinkResendChannel.whatsapp)),
                ),
                AppTextButton(
                  key: const ValueKey('share-link-sms'),
                  text: l10n.shareSendAgainSms,
                  onPressed: () => unawaited(resendShareLinkVia(
                      context, ref, row, ShareLinkResendChannel.sms)),
                ),
              ],
              SizedBox(height: 8.h),
              AppTextButton(
                key: const ValueKey('share-link-cancel'),
                text: _cancelling ? '…' : l10n.shareLinkCancel,
                onPressed: _cancelling ? null : () => unawaited(_cancel(row)),
              ),
            ],
            // THE BAR IS THE BUTTON (kute_bar_context.dart): Share again is
            // the floating Sal bar's primary action while the link is open
            // and this device has its URL; the sheet keeps clear of it.
            if (open && row.url.isNotEmpty)
              ReceiptBarAction(
                label: l10n.shareLinkShareAgain,
                onPrimary: () => unawaited(_shareAgain(row)),
              )
            else
              const ReceiptBarAction.none(),
          ],
        ),
      ),
    );
  }
}
