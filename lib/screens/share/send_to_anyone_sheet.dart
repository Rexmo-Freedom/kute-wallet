// lib/screens/share/send_to_anyone_sheet.dart
//
// SEND TO ANYONE. The recipient option on Send (bitcoin: the Send to step
// of confirm_send.dart; dollars: the Withdraw sheet) for someone who has
// no address to paste: a link they claim with Kute. Three steps in one
// sheet, each built from the send flows' own pieces:
//
//   1. Amount: the send hero (SendTypedAmountHero, the unit pill) over the
//      app keypad (AmountKeypad). Dollars are typed as dollars; bitcoin is
//      typed in the user's currency and converted to sats by the bitcoin
//      send's own conversion (inputToSatsProvider), with the sats shown
//      under the figure.
//   2. Who is it for? One text field, the first name, optional. Create
//      link posts to the backend (nothing moves: a share link is a pending
//      send, see models/share_link_model.dart) and opens the OS share
//      sheet with "{name}, I sent you {amount} with Kute. Claim it here:
//      {url}".
//   3. The receipt: the pending row (pending_share_links.dart), Share
//      again and Done.
//
// Launched from a market page's bar or the market share sheet
// (kute_share_actions.dart, share_market_sheet.dart) the sheet carries THE
// PICK on the link: the market slug and title, the venue, the outcome
// ("Yes", a candidate, "Long"), its index and the side. The pick reads
// above the amount ("Yes on Gemini Carbon"), goes to the backend with the
// link, and the share text says "I sent you a prediction on Kute: Yes on
// Gemini Carbon, $12.00". There is no market picker here in phase 1.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionProvider, inputToSatsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart' show AmountKeypad;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_text_field.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendAmountUnitPill, SendToListCard, SendTypedAmountHero;
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_link_events.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The sheet's route name, for the route observers.
const String kSendToAnyoneRouteName = 'send_to_anyone';

/// Opens Send to anyone for [kind] over the current screen. Resolves to
/// true when a link was created. The pick ([marketTitle], [venue],
/// [outcome], [outcomeIndex], [side]) is optional; see the file header.
Future<bool?> showSendToAnyoneSheet(
  BuildContext context, {
  required ShareLinkKind kind,
  String? marketSlug,
  String? marketTitle,
  String? venue,
  String? outcome,
  int? outcomeIndex,
  String? side,
  required String entrySource,
}) {
  TrackingService.markEntrySource('share_link', entrySource);
  return showAppBottomSheet<bool>(
    context: context,
    routeSettings: const RouteSettings(name: kSendToAnyoneRouteName),
    builder: (_) => SendToAnyoneSheet(
      kind: kind,
      marketSlug: marketSlug,
      marketTitle: marketTitle,
      venue: venue,
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: side,
    ),
  );
}

class SendToAnyoneSheet extends ConsumerStatefulWidget {
  const SendToAnyoneSheet({
    super.key,
    required this.kind,
    this.marketSlug,
    this.marketTitle,
    this.venue,
    this.outcome,
    this.outcomeIndex,
    this.side,
  });

  final ShareLinkKind kind;
  final String? marketSlug;

  /// The pick (see the file header); all null for a plain send.
  final String? marketTitle;
  final String? venue;
  final String? outcome;
  final int? outcomeIndex;
  final String? side;

  /// Whether the link carries a pick.
  bool get hasPick =>
      (outcome?.trim().isNotEmpty ?? false) &&
      (marketTitle?.trim().isNotEmpty ?? false);

  /// Test seam: what Create link hands the OS. Null opens the share sheet.
  @visibleForTesting
  static Future<String> Function(String text)? debugSharer;

  @override
  ConsumerState<SendToAnyoneSheet> createState() => _SendToAnyoneSheetState();
}

enum _Step { amount, name, done }

class _SendToAnyoneSheetState extends ConsumerState<SendToAnyoneSheet> {
  _Step _step = _Step.amount;
  String _typed = '';
  final TextEditingController _name = TextEditingController();
  bool _creating = false;
  String? _error;
  PendingShareLink? _created;

  ShareLinkKind get kind => widget.kind;
  bool get _dollars => kind == ShareLinkKind.dollars;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The typed figure as the link's minor units: cents, or sats through
  /// the bitcoin send's conversion. Zero while nothing usable is typed.
  int _amountMinor() {
    final value = double.tryParse(_typed) ?? 0;
    if (value <= 0) return 0;
    if (_dollars) return (value * 100).round();
    try {
      final currency = ref.read(settingsProvider).currency;
      return ref
          .read(inputToSatsProvider((amount: _typed, currency: currency)));
    } catch (_) {
      return 0;
    }
  }

  Future<void> _create() async {
    if (_creating) return;
    final amountMinor = _amountMinor();
    if (amountMinor <= 0) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    final label = _name.text.trim();
    try {
      final pick = widget.hasPick;
      final created = await ref.read(shareLinksApiProvider).create(
            kind: kind,
            amountMinor: amountMinor,
            marketSlug: widget.marketSlug,
            senderLabel: label.isEmpty ? null : label,
            venue: pick ? widget.venue : null,
            outcome: pick ? widget.outcome!.trim() : null,
            outcomeIndex: pick ? widget.outcomeIndex : null,
            side: pick ? widget.side : null,
          );
      final row = PendingShareLink(
        id: created.id,
        kind: kind,
        amountMinor: amountMinor,
        label: label.isEmpty ? null : label,
        marketSlug: widget.marketSlug,
        marketTitle: pick ? widget.marketTitle!.trim() : null,
        venue: pick ? widget.venue : null,
        outcome: pick ? widget.outcome!.trim() : null,
        url: created.url,
        createdAt: DateTime.now(),
        status: ShareLinkStatus.open,
      );
      ShareLinksStore.put(row);
      ShareLinkEvents.created(kind, amountMinor,
          marketSlug: widget.marketSlug, outcome: row.outcome);
      if (!mounted) return;
      setState(() {
        _created = row;
        _step = _Step.done;
        _creating = false;
      });
      await _share(row);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = context.l10n.shareCreateFailed;
      });
    }
  }

  Future<void> _share(PendingShareLink row) async {
    final amount =
        shareLinkAmountLabel(context, ref, row.kind, row.amountMinor);
    final text = shareLinkMessage(context,
        name: row.label,
        amount: amount,
        url: row.url,
        outcome: row.outcome,
        title: row.marketTitle,
        venue: row.venue);
    final debug = SendToAnyoneSheet.debugSharer;
    try {
      final String result;
      if (debug != null) {
        result = await debug(text);
      } else {
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null
            ? (box.localToGlobal(ui.Offset.zero) & box.size)
            : (ui.Offset.zero & const ui.Size(1, 1));
        final r = await SharePlus.instance
            .share(ShareParams(text: text, sharePositionOrigin: origin));
        result = r.status.name;
      }
      ShareLinkEvents.shared(row.kind, result: result);
    } catch (_) {
      ShareLinkEvents.shared(row.kind, result: 'error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      followKeyboard: _step == _Step.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: _step == _Step.name
                ? l10n.shareWhoIsItFor
                : widget.hasPick
                    ? (widget.venue == 'hyperliquid'
                        ? l10n.sendThisInvestment
                        : l10n.sendThisPrediction)
                    : l10n.shareSendToAnyone,
            subtitle: _step == _Step.amount
                ? (widget.hasPick
                    ? l10n.sendThisPickSub
                    : l10n.shareSendToAnyoneSubtitle)
                : null,
            icon: Icons.ios_share_rounded,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
            child: switch (_step) {
              _Step.amount => _amountStep(),
              _Step.name => _nameStep(),
              _Step.done => _doneStep(),
            },
          ),
        ],
      ),
    );
  }

  Widget _amountStep() {
    final c = context.colors;
    final l10n = context.l10n;
    final amountMinor = _amountMinor();
    final settings = ref.watch(settingsProvider);
    // Dollars type as dollars; bitcoin types in the user's currency with
    // the sats it comes to under the figure.
    final unit = _dollars ? 'USD' : settings.currency;
    String? under;
    if (!_dollars && amountMinor > 0) {
      try {
        under = '≈ ${ref.watch(conversionProvider(amountMinor))}';
      } catch (_) {
        under = null;
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.hasPick) ...[
          // The pick, above the amount: "Yes on Gemini Carbon".
          Text(
            sharePickLine(context,
                outcome: widget.outcome!.trim(),
                title: widget.marketTitle!.trim()),
            key: const ValueKey('share-pick-line'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              height: 1.3,
            ),
          ),
          SizedBox(height: 10.h),
        ],
        SizedBox(height: 6.h),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SendTypedAmountHero(prefix: '\$', typed: _typed),
              ),
            ),
            SizedBox(width: 10.w),
            SendAmountUnitPill(
              code: unit,
              icon: SvgPicture.asset(
                _dollars ? kUsdMarkAsset : kBitcoinMarkAsset,
                width: 20.sp,
                height: 20.sp,
              ),
            ),
          ],
        ),
        if (under != null) ...[
          SizedBox(height: 8.h),
          Text(
            under,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        SizedBox(height: 16.h),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: AmountKeypad(
            value: _typed,
            maxDecimals: 2,
            onChanged: (v) => setState(() => _typed = v),
          ),
        ),
        SizedBox(height: 16.h),
        AppButton(
          key: const ValueKey('share-amount-continue'),
          text: l10n.continueLabel,
          onPressed:
              amountMinor > 0 ? () => setState(() => _step = _Step.name) : null,
        ),
      ],
    );
  }

  Widget _nameStep() {
    final l10n = context.l10n;
    final c = context.colors;
    final amount = shareLinkAmountLabel(context, ref, kind, _amountMinor());
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          amount,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 15.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        SizedBox(height: 14.h),
        AppTextField(
          key: const ValueKey('share-name-field'),
          controller: _name,
          hintText: l10n.shareFirstNameHint,
          autofocus: true,
          maxLength: 40,
          keyboardType: TextInputType.name,
          onChanged: (_) => setState(() {}),
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
        SizedBox(height: 20.h),
        AppButton(
          key: const ValueKey('share-create-link'),
          text: l10n.shareCreateLink,
          isLoading: _creating,
          loadingLabel: l10n.shareCreatingLink,
          onPressed: _creating ? null : () => unawaited(_create()),
        ),
      ],
    );
  }

  Widget _doneStep() {
    final l10n = context.l10n;
    final c = context.colors;
    final row = _created;
    if (row == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SendToListCard(
          colors: c,
          rows: [PendingShareLinkRow(row: row, onTap: () {})],
        ),
        SizedBox(height: 20.h),
        AppButton(
          key: const ValueKey('share-done'),
          text: l10n.done,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        SizedBox(height: 8.h),
        AppTextButton(
          key: const ValueKey('share-again'),
          text: l10n.shareLinkShareAgain,
          onPressed: () => unawaited(_share(row)),
        ),
      ],
    );
  }
}
