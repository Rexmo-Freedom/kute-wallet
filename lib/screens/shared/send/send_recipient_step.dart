// lib/screens/shared/send/send_recipient_step.dart
//
// THE RECIPIENT-FIRST SEND STEP (founder, 31 October 2026: the old step
// "looked very 2019 fintech"). Both sends, bitcoin (confirm_send.dart)
// and dollars (usd/usd_send_screen.dart), open on the same shape:
//
//   * a search-style field at the top ("Name, address, Lightning or
//     @user"), a magnifier at its left and Paste and Scan inside at its
//     right ([SendRecipientSearchField]);
//   * a pasted or typed destination the flow recognises as one resolved
//     row under it: the rail's mark, the shortened address, the rail in
//     words ([SendResolvedRow]); the bar's Continue acts on it;
//   * "Frequent" under it (founder, 2 November 2026: "Frequent stays on
//     top"): the recents as circles, hidden while typing and once a
//     recipient is chosen (send_contacts_list.dart, SendFrequentSection);
//   * ONE QUESTION PER LEVEL, PEOPLE FIRST (founder, 6 November 2026,
//     the approved Send hierarchy, on the Bitcoin and the Dollars Send):
//
//       [ 🔍 Name, phone, address or @user   📋 ⌗ ]
//       Frequent                 (P) (J) (A)          ← level 1: people
//       More ways to send
//       [₿ To your Bitcoin] [⛓ Crypto address] [📈 Prediction or
//        investment]                                 ← level 2
//       All contacts             A Anna Haro …        ← level 3
//
//     Level 2 is ONE row of small, equal chips ([SendWaysRow] of
//     [SendWayChip]: the big cards' surface, smaller; the icon at the
//     top left, a short label under it), clearly under the people above
//     it. They share the row's width evenly (founder, 7 November 2026:
//     two chips, Prediction hidden, take half each, no empty third slot);
//     a label wraps to two lines and the chips of the row stay equally
//     tall. Three fit across a 375 pt phone in every shipped language; a
//     label that cannot fit (a very large text) turns the row into a
//     horizontal scroll, never a cut word. No big "Send to" card grid any
//     more;
//   * All contacts A–Z under the chips (founder, 1 November 2026,
//     Revolut's one list: send_contacts_list.dart): the recents and the
//     phone's contacts, filtered by what is typed, badged Kute or ⚡, the
//     resolved destination always first above it.
//
// There is no "Send to a friend" row on the Bitcoin or Dollars Send any
// more: a plain contact in the list IS the friend link. [SendToFriendRow],
// [SendContactMatches] and the contacts picker stay for the dollar send's
// own coin step (usd_send_screen.dart, reached from a deep link).
//
// No step bar: the sheet's title says where the person is. The floating
// Sal bar is the step's Continue (kute_bar_context.dart; the plain
// primary context, no style of its own).
//
// Presentation only, with one exception: the friend row and the picker
// drive `sendContactsProvider` (the permission prompt, the book) because
// every send mounts them the same way. No money call here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/coin_asset_grid.dart'
    show CoinAssetGroup;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Whether what is typed has the shape of a destination (an address, an
/// invoice, a payment request, a Lightning address) rather than a name to
/// search the recents and the contacts with. A short word with no scheme,
/// no `@domain` and no address length is a search.
bool sendTextLooksLikeAddress(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains(' ')) return false;
  if (t.contains(':')) return true;
  if (t.contains('@') && t.contains('.')) return true;
  return t.length >= 20;
}

/// The centred title of a send step's app bar ("Send", "Send dollars",
/// "Send USDC").
class SendStepTitle extends StatelessWidget {
  const SendStepTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 17.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      );
}

/// The recipient field as a search field: a magnifier at the left, the
/// text, and two 32 px buttons inside at the right (Paste and Scan while
/// empty, a clear once there is text).
class SendRecipientSearchField extends StatelessWidget {
  const SendRecipientSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onPaste,
    required this.onScan,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;
  final VoidCallback onScan;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = controller.text.isEmpty;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Container(
      key: const ValueKey('send-recipient-search'),
      constraints: BoxConstraints(minHeight: 52.h),
      padding: EdgeInsets.fromLTRB(14.w, 2.h, 8.w, 2.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: c.textSecondary, size: 22.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
              cursorColor: c.accent,
              cursorWidth: 2.0,
              maxLines: 2,
              minLines: 1,
              // An address, a name or an invoice, never prose: nothing
              // that rewrites what is typed or pasted.
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              scrollPadding: EdgeInsets.only(bottom: 120.h),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: hintText,
                hintMaxLines: 1,
                hintStyle: TextStyle(
                  color: c.textSecondary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                isDense: true,
              ),
            ),
          ),
          SizedBox(width: 4.w),
          AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
            child: empty
                ? Row(
                    key: const ValueKey('send-field-empty'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SendSearchFieldButton(
                        key: const ValueKey('send-field-paste'),
                        icon: Icons.content_paste_rounded,
                        tooltip: context.l10n.paste,
                        onTap: onPaste,
                      ),
                      SizedBox(width: 4.w),
                      SendSearchFieldButton(
                        key: const ValueKey('send-field-scan'),
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: context.l10n.scan,
                        onTap: onScan,
                      ),
                    ],
                  )
                : SendSearchFieldButton(
                    key: const ValueKey('send-field-clear'),
                    icon: Icons.cancel_rounded,
                    tooltip: context.l10n.close,
                    onTap: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A 32 px icon button inside the search field.
class SendSearchFieldButton extends StatelessWidget {
  const SendSearchFieldButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 32.sp,
            height: 32.sp,
            child: Icon(icon, color: c.textPrimary, size: 17.sp),
          ),
        ),
      ),
    );
  }
}

/// The destination the field holds, recognised: the rail's mark, the
/// shortened address over the rail in words ("Bitcoin · on-chain",
/// "Lightning", "USDT on Base"). One row in a soft card; the bar's
/// Continue acts on it.
class SendResolvedRow extends StatelessWidget {
  const SendResolvedRow({
    super.key,
    required this.leading,
    required this.address,
    required this.rail,
    this.onTap,
  });

  final Widget leading;
  final String address;
  final String rail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SendToListCard(
      key: const ValueKey('send-resolved-row'),
      colors: c,
      rows: [
        SendToListRow(
          colors: c,
          leading: leading,
          title: sendShortAddress(address),
          subtitle: rail,
          trailing: Container(
            width: 24.sp,
            height: 24.sp,
            decoration: BoxDecoration(color: c.success, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, color: Colors.white, size: 16.sp),
          ),
          onTap: onTap ?? () {},
        ),
      ],
    );
  }
}

/// One line of text under the field that says what is wrong with it
/// ("Not an Arbitrum address").
class SendInlineError extends StatelessWidget {
  const SendInlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 6.w),
        child: Text(
          message,
          key: const ValueKey('send-inline-error'),
          style: TextStyle(
            color: AppColors.error,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      );
}

/// The quiet "Change" text button a section header carries on the right
/// (the recipient card, a coin chosen on the Send to card): 13 w600
/// textSecondary, a generous hit area.
class SendChangeButton extends StatelessWidget {
  const SendChangeButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(left: 12.w),
          child: Text(
            context.l10n.sendRecipientChange,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The 12 sp section header ("Recent", "Send to").
class SendSectionLabel extends StatelessWidget {
  const SendSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: 4.w, right: 4.w, bottom: 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One recent recipient as the circles row shows it: [initials] in the
/// circle (a person), else [icon] (the rail); [label] under it.
@immutable
class SendRecentItem {
  const SendRecentItem({
    required this.id,
    required this.label,
    this.initials,
    this.icon,
    this.mark,
    required this.onTap,
  });

  final String id;

  /// The name, or the short address. Labels only: never the full address.
  final String label;
  final String? initials;
  final IconData? icon;

  /// A coin mark in place of [icon] (the dollar send's coin on its
  /// network).
  final Widget? mark;
  final VoidCallback onTap;

  /// Whether [query] matches this row's label.
  bool matches(String query) =>
      query.trim().isEmpty ||
      label.toLowerCase().contains(query.trim().toLowerCase());
}

/// "Recent": the recipients as 56 px circles in a horizontal row, the
/// name or short address under each (11 sp). Tapping one is the flow's
/// own commit.
class SendRecentCircles extends StatelessWidget {
  const SendRecentCircles({super.key, required this.items});

  final List<SendRecentItem> items;

  static const double circle = 56;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('send-recent-circles'),
      height: (circle + 6 + 30).h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 2.w),
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 14.w),
        itemBuilder: (context, i) {
          final item = items[i];
          return Semantics(
            button: true,
            label: item.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () {
                HapticFeedback.selectionClick();
                item.onTap();
              },
              child: SizedBox(
                width: 68.w,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: circle.sp,
                      height: circle.sp,
                      decoration: BoxDecoration(
                        color: c.surfaceLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.borderSubtle, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: item.mark ??
                          (item.initials != null && item.initials!.isNotEmpty
                              ? Text(
                                  item.initials!,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                )
                              : Icon(item.icon ?? Icons.person_rounded,
                                  color: c.textPrimary, size: 24.sp)),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      item.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A 32 px initials circle (a contact in a list).
class SendInitialsCircle extends StatelessWidget {
  const SendInitialsCircle(this.initials, {super.key, this.size = 32});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size.sp,
      height: size.sp,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      alignment: Alignment.center,
      child: initials.isEmpty
          ? Icon(Icons.person_rounded, color: c.textPrimary, size: (size * 0.55).sp)
          : Text(
              initials,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: (size * 0.38).sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
    );
  }
}

/// Sal's `share` face at 32, the glyph of the link rows (Send to a friend,
/// Send a prediction or investment).
class SendSalShareGlyph extends StatelessWidget {
  const SendSalShareGlyph({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SalSprite(
        clip: 'share',
        size: size.sp,
        fallback: Icon(Icons.ios_share_rounded,
            color: context.colors.textPrimary, size: (size * 0.65).sp),
      );
}

/// The phone book's matches for what is typed, inline under the field:
/// up to [maxRows] rows and no header. Nothing while the field is empty,
/// while the book is not granted, or when nothing matches; the book
/// itself opens from the "Send to a friend" row ([SendToFriendRow]).
/// [onPick] starts the flow's Send to anyone with the contact.
class SendContactMatches extends ConsumerWidget {
  const SendContactMatches({
    super.key,
    required this.query,
    required this.onPick,
  });

  final String query;
  final ValueChanged<SendContact> onPick;

  static const int maxRows = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();
    final state = ref.watch(sendContactsProvider);
    if (!state.granted) return const SizedBox.shrink();
    final matches = state.matching(query, limit: maxRows);
    if (matches.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: SendToListCard(
        key: const ValueKey('send-contact-matches'),
        colors: c,
        rows: [
          for (final contact in matches)
            SendToListRow(
              key: ValueKey('send-contact-${contact.id}'),
              colors: c,
              leading: SendInitialsCircle(contact.initials),
              title: contact.displayName,
              subtitle: contact.phone,
              onTap: () => onPick(contact),
            ),
        ],
      ),
    );
  }
}

/// The contacts picker: "Someone else" at the top (a plain link with a
/// typed name, [onSomeoneElse]), then the book, alphabetical, under a
/// search field; with the permission refused for good, the Settings row
/// instead, and with a refusal the system can ask again, a row that asks
/// again. Closes on a pick and hands it to [onPick].
Future<void> showSendContactsPicker(
  BuildContext context, {
  String initialQuery = '',
  required ValueChanged<SendContact> onPick,
  required VoidCallback onSomeoneElse,
}) =>
    showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => _SendContactsPickerSheet(
        initialQuery: initialQuery,
        onPick: (contact) {
          Navigator.of(sheetCtx).pop();
          onPick(contact);
        },
        onSomeoneElse: () {
          Navigator.of(sheetCtx).pop();
          onSomeoneElse();
        },
      ),
    );

class _SendContactsPickerSheet extends ConsumerStatefulWidget {
  const _SendContactsPickerSheet({
    required this.initialQuery,
    required this.onPick,
    required this.onSomeoneElse,
  });

  final String initialQuery;
  final ValueChanged<SendContact> onPick;
  final VoidCallback onSomeoneElse;

  @override
  ConsumerState<_SendContactsPickerSheet> createState() =>
      _SendContactsPickerSheetState();
}

class _SendContactsPickerSheetState
    extends ConsumerState<_SendContactsPickerSheet> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final state = ref.watch(sendContactsProvider);
    final notifier = ref.read(sendContactsProvider.notifier);
    final granted = state.granted;
    final matches = granted ? state.matching(_query.text) : const <SendContact>[];
    // "Someone else" first, then the book (or what stands in for it).
    final rows = <Widget>[
      SendToListRow(
        key: const ValueKey('send-contacts-someone-else'),
        colors: c,
        leading: const SendInitialsCircle(''),
        title: l10n.sendSomeoneElse,
        onTap: widget.onSomeoneElse,
      ),
      if (state.permission == SendContactsPermission.blocked)
        SendToListRow(
          key: const ValueKey('send-contacts-settings'),
          colors: c,
          leading: Icon(Icons.contacts_rounded,
              color: c.textSecondary, size: 24.sp),
          title: l10n.sendAllowContactsInSettings,
          subtitle: l10n.sendAllowContactsInSettingsSub,
          onTap: () => unawaited(notifier.openSettings()),
        )
      else if (!granted)
        SendToListRow(
          key: const ValueKey('send-contacts-ask'),
          colors: c,
          leading: Icon(Icons.contacts_rounded,
              color: c.textPrimary, size: 24.sp),
          title: l10n.sendContacts,
          subtitle: l10n.sendAllowContactsInSettingsSub,
          onTap: () => unawaited(notifier.request()),
        )
      else
        for (final contact in matches)
          SendToListRow(
            key: ValueKey('send-contact-pick-${contact.id}'),
            colors: c,
            leading: SendInitialsCircle(contact.initials),
            title: contact.displayName,
            subtitle: contact.phone,
            onTap: () => widget.onPick(contact),
          ),
    ];
    return AppBottomSheetContainer(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      followKeyboard: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendToAFriend,
            icon: Icons.contacts_rounded,
          ),
          if (granted)
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: c.borderSubtle, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        color: c.textSecondary, size: 20.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('send-contacts-picker-search'),
                        controller: _query,
                        autofocus: widget.initialQuery.isEmpty,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n.sendContactsSearchHint,
                          hintStyle: TextStyle(
                            color: c.textSecondary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 32.h),
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(
                height: 0.5,
                thickness: 0.5,
                color: c.borderSubtle,
                indent: 52.w,
              ),
              itemBuilder: (context, i) => rows[i],
            ),
          ),
          if (granted && matches.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 32.h),
              child: Text(
                l10n.sendNoContactsMatch,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The analytics of a recipient picked on the step: `contact`, `recent`
/// or `address` (typed, pasted or scanned). Never the recipient itself.
void trackSendRecipientPicked(String kind) =>
    TrackingService.track('send_recipient_picked', params: {'kind': kind});

/// "Send to a friend", the one link row of the Send to card (see the
/// file header): Sal's `share` face, "They claim it with Kute, no wallet
/// needed". The tap asks the contacts permission the first time (and
/// again after a refusal the system allows to ask again), then opens the
/// contacts picker with "Someone else" at its top: a contact picked goes
/// to [onPick], "Someone else" to [onSomeoneElse] (the flow's plain Send
/// to anyone sheet). Refused for good, the picker offers Settings.
class SendToFriendRow extends ConsumerWidget {
  const SendToFriendRow({
    super.key,
    required this.onPick,
    required this.onSomeoneElse,
    this.title,
  });

  final ValueChanged<SendContact> onPick;
  final VoidCallback onSomeoneElse;

  /// The row's words; null reads "Send to a friend". The Dollars send says
  /// "Send dollars to a friend" (founder, 1 November 2026).
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return SendToListRow(
      key: const ValueKey('send-to-friend-row'),
      colors: context.colors,
      leading: const SendSalShareGlyph(),
      title: title ?? l10n.sendToAFriend,
      subtitle: l10n.sendToAFriendSub,
      onTap: () => unawaited(_open(context, ref)),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final permission = ref.read(sendContactsProvider).permission;
    if (permission == SendContactsPermission.unknown ||
        permission == SendContactsPermission.denied) {
      await ref.read(sendContactsProvider.notifier).request();
    }
    if (!context.mounted) return;
    await showSendContactsPicker(context,
        onPick: onPick, onSomeoneElse: onSomeoneElse);
  }
}

/// The dollar send's "Send a prediction or investment" row.
class SendPickMarketRow extends StatelessWidget {
  const SendPickMarketRow({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SendToListRow(
      key: const ValueKey('send-pick-market-row'),
      colors: context.colors,
      leading: const SendSalShareGlyph(),
      title: l10n.sendPickMarket,
      subtitle: l10n.sendPickMarketSub,
      onTap: onTap,
    );
  }
}

/// "USDC, USDT, ETH +18": [sendAlsoSendsToSummary] for a card's short
/// line (the Receive sheets' "Another wallet").
String sendCoinsShortSummary(
    AppLocalizations l10n, List<CoinAssetGroup> groups) {
  final shown = groups.take(SendCoinStack.stack).toList();
  final rest = groups.length - shown.length;
  final names = [for (final g in shown) g.displaySymbol].join(', ');
  if (names.isEmpty) return '';
  return rest > 0 ? l10n.coinsSummaryShort(names, rest) : names;
}

/// "USDC, USDT, ETH and 16 more": the first [SendCoinStack.stack] coins of
/// [groups] by symbol and how many more (the Also sends to row's and
/// card's line); empty with no coins.
String sendAlsoSendsToSummary(
    AppLocalizations l10n, List<CoinAssetGroup> groups) {
  final shown = groups.take(SendCoinStack.stack).toList();
  final rest = groups.length - shown.length;
  final names = [for (final g in shown) g.displaySymbol];
  if (names.isEmpty) return '';
  if (rest > 0) return l10n.sendAlsoSendsToMore(names.join(', '), rest);
  if (names.length == 1) return names.first;
  return l10n.sendAlsoSendsToList(
      names.sublist(0, names.length - 1).join(', '), names.last);
}

/// The first [stack] coin marks of [groups], [mark] each, overlapping by
/// a little over half: the Also sends to row's leading glyph and card's
/// visual.
class SendCoinStack extends StatelessWidget {
  const SendCoinStack({super.key, required this.groups, this.mark = 22});

  final List<CoinAssetGroup> groups;

  /// One mark's side (scaled by sp).
  final double mark;

  /// How many marks it shows.
  static const int stack = 3;

  /// The ring each mark wears, in the card's colour, so the overlap reads.
  static const double ring = 1.5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = groups.take(stack).toList();
    final step = mark * 9 / 22;
    // The box holds every mark with its ring (founder, 7 November 2026:
    // the last coin was cut at the right): a mark is [mark] plus the ring
    // on both sides.
    return SizedBox(
      width: (mark + (shown.length - 1) * step).sp + 2 * ring,
      height: mark.sp + 2 * ring,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: (i * step).sp,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surfaceLight,
                  border: Border.all(color: c.surfaceLight, width: ring),
                ),
                child: AssetIcon(assetCode: shown[i].assetCode, size: mark.sp),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Also sends to": the coin marks stacked, "USDC, USDT, ETH and 16
/// more" and the chevron, opening the rails sheet.
class SendAlsoSendsToRow extends StatelessWidget {
  const SendAlsoSendsToRow({
    super.key,
    required this.groups,
    required this.onTap,
    this.title,
  });

  final List<CoinAssetGroup> groups;
  final VoidCallback onTap;

  /// The row's words; null reads "Also sends to" (the Dollars Add says
  /// "From another wallet or exchange").
  final String? title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Three marks overlapping by half, in the row's 40 px leading slot.
    return SendToListRow(
      key: const ValueKey('send-also-sends-to-row'),
      colors: context.colors,
      leading: SendCoinStack(groups: groups),
      title: title ?? l10n.sendToCryptoAddress,
      subtitle: sendAlsoSendsToSummary(l10n, groups),
      onTap: onTap,
    );
  }
}

/// The coin marks' side on a big square card ([sendAlsoSendsToCard]).
const double kSendCoinStackCardMark = 30;

/// "Also sends to" (or [title]: "To a crypto address") as the app's big
/// square card (kute_action_cards.dart; founder, 5 November 2026: the
/// Send recipient options "should be cards like squares"): the coin marks
/// stacked at the top left, the title, "USDC, USDT, ETH and 16 more"
/// under it; keyed `send-also-sends-to-row` as the row was, unless [key]
/// names it (the Dollars Add's "From another wallet or exchange").
KuteActionCard sendAlsoSendsToCard(
  AppLocalizations l10n, {
  required List<CoinAssetGroup> groups,
  required VoidCallback onTap,
  String? title,
  String? subtitle,
  Key? key,
}) =>
    KuteActionCard(
      key: key ?? const ValueKey('send-also-sends-to-row'),
      visual: SendCoinStack(groups: groups, mark: kSendCoinStackCardMark),
      title: title ?? l10n.sendToCryptoAddress,
      subtitle: subtitle ?? sendAlsoSendsToSummary(l10n, groups),
      onTap: onTap,
    );

/// The Receive sheets' "Another wallet" card (founder, 7 November 2026:
/// one-line titles, "Or an exchange · USDC, USDT, ETH +18" under it), the
/// coins stacked, keyed [key].
KuteActionCard receiveAnotherWalletCard(
  AppLocalizations l10n, {
  required List<CoinAssetGroup> groups,
  required VoidCallback onTap,
  required Key key,
}) =>
    sendAlsoSendsToCard(
      l10n,
      key: key,
      groups: groups,
      title: l10n.receiveAnotherWallet,
      subtitle:
          l10n.receiveOrAnExchangeLine(sendCoinsShortSummary(l10n, groups)),
      onTap: onTap,
    );

/// The space between the chips of a [SendWaysRow] (design units, scaled
/// by width).
const double kSendWayChipGap = 8;

/// A chip's inner padding (design units).
const double kSendWayChipPadding = 12;

/// The height of a chip's icon box (scaled by sp); a 20 to 24 mark sits
/// in it, centred on its left edge.
const double kSendWayChipIconSlot = 24;

/// The coin marks' side in the Crypto address chip's stack.
const double kSendWayChipCoinMark = 20;

/// One way to send on the level-2 row (see the file header): the big
/// cards' surface (kute_action_cards.dart), smaller. [icon] at the top
/// left in its 24 box, [label] under it (13, w600, up to two lines,
/// never a word cut: [SendWaysRow] measures). [semanticsLabel] says what
/// the short label stands for ("Send an investment or prediction").
class SendWayChip extends StatelessWidget {
  const SendWayChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final String? semanticsLabel;

  /// The label's style (shared with the row's fit measurement).
  static TextStyle labelStyle(AppColorsExtension c) => TextStyle(
        color: c.textPrimary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.2,
      );

  /// The lines a label may take.
  static const int maxLines = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: kSendWayChipPadding.w,
                vertical: kSendWayChipPadding.h),
            // The big cards' surface: surface-1 (the dark surface in dark
            // mode) and the hairline, a smaller radius.
            decoration: BoxDecoration(
              color: isLight ? c.surfaceLight : c.surface,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                  color: isLight ? c.border : c.borderSubtle, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: kSendWayChipIconSlot.sp,
                  child: Align(alignment: Alignment.centerLeft, child: icon),
                ),
                SizedBox(height: 8.h),
                Text(
                  label,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle(c),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Level 2 of the Send step (see the file header): ONE row of [chips]
/// sharing the width evenly (three a third each, two half each: never an
/// empty slot), equally tall. When a label cannot fit its share (a very
/// large text) the row scrolls sideways, the chips as wide as the longest
/// label needs, all alike.
class SendWaysRow extends StatelessWidget {
  const SendWaysRow({super.key, required this.chips});

  final List<SendWayChip> chips;

  /// The text a chip [chipWidth] wide has for its label.
  static double _inner(double chipWidth) =>
      chipWidth - 2 * kSendWayChipPadding.w - 2;

  /// Whether every chip's label fits a chip [chipWidth] wide: no word
  /// wider than the chip (it would break mid-word) and no more than
  /// [SendWayChip.maxLines] lines. A word may break after its hyphen
  /// ("Krypto-Adresse") or its slash ("Forudsigelse/investering");
  /// Japanese breaks between characters, so only its lines count.
  static bool labelsFit(
      BuildContext context, List<SendWayChip> chips, double chipWidth) {
    final inner = _inner(chipWidth);
    if (inner <= 0) return false;
    final style =
        DefaultTextStyle.of(context).style.merge(SendWayChip.labelStyle(context.colors));
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final cjk = RegExp(r'[　-鿿＀-￯]');
    double width(String text) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    for (final chip in chips) {
      for (final word in chip.label.split(RegExp(r'\s+'))) {
        if (word.isEmpty || cjk.hasMatch(word)) continue;
        for (final part in word.split(RegExp(r'(?<=[-‐/])'))) {
          if (width(part) > inner) return false;
        }
      }
      final p = TextPainter(
        text: TextSpan(text: chip.label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: SendWayChip.maxLines,
      )..layout(maxWidth: inner);
      final over = p.didExceedMaxLines;
      p.dispose();
      if (over) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final g = kSendWayChipGap.w;
      final slots = chips.length;
      final total = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      final third = (total - g * (slots - 1)) / slots;
      Widget row(double chipWidth) => IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) SizedBox(width: g),
                  SizedBox(width: chipWidth, child: chips[i]),
                ],
              ],
            ),
          );
      if (labelsFit(context, chips, third)) {
        return Align(alignment: Alignment.centerLeft, child: row(third));
      }
      // Wider chips, all alike, scrolling sideways: never a cut word.
      var wide = third;
      while (wide < total && !labelsFit(context, chips, wide)) {
        wide += 8;
      }
      return SingleChildScrollView(
        key: const ValueKey('send-ways-scroll'),
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: row(wide),
      );
    });
  }
}
