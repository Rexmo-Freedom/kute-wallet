// lib/screens/shared/send/send_what_step.dart
//
// WHO, THEN WHAT, THEN REVIEW (founder, 7 November 2026, the approved
// Send: "ok do it, just make sure that people realise they can send to
// different cryptos also"). Both Sends, the Bitcoin one (confirm_send.dart)
// and the Dollars one (usd/usd_withdraw_screen.dart), share their Who step
// (send_recipient_step.dart) and this What step; each keeps its own amount
// and its own Review.
//
// An ADDRESS needs no What: the input decides the rail and the send goes
// on to its amount. A PERSON (a phone contact, a typed number no contact
// has) is asked What, in one small sheet over the Send ([showSendWhatSheet]):
//
//   Send to Maria
//   What are you sending?
//   [₿  Money                         ›]
//   [   From  ( Bitcoin | Dollars )    ]   the From toggle, the home's
//                                          account first
//   [◔  A prediction or investment    ›]   only where a slip can send one
//                                          (sendPickOffered)
//
// [sendToPerson] then runs the existing flow, nothing new moves money:
//
//   * Money from Bitcoin to someone on Kute (a contact with a Kute
//     Lightning address): paid directly at that address, the Bitcoin
//     Send's own amount and Review;
//   * Money to anyone else, or from Dollars (a Kute address takes no
//     dollars): the claim link, Send to anyone in that account's money
//     (send_to_anyone_sheet.dart), the first name and the number kept in
//     the local row;
//   * A prediction or investment: the search sheet in send mode with the
//     person prefilled (send_pick_market_sheet.dart, SendPickSession): a
//     market, its slip's "Send $X · side", then Send to anyone's "Who is it
//     for?" with the name already there. A gift is always a link: the
//     claim screen places it.
//
// `send_what_picked {what, from, home}` once per answer (the From only
// for money); never the person, the number or an address.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/screens/search/components/search_rows.dart'
    show SearchChanceGauge;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/services/contacts/send_contacts_service.dart'
    show SendContact;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The account money leaves from.
enum SendFrom { bitcoin, dollars }

/// What a person is sent: money, or a prediction or investment as a gift.
enum SendWhatKind { money, gift }

/// The What step's answer: [what], and for money the account it leaves
/// [from].
typedef SendWhat = ({SendWhatKind what, SendFrom from});

/// The What sheet's route name, for the route observers.
const String kSendWhatRouteName = 'send_what';

/// The What sheet's rows and its From toggle.
const ValueKey<String> kSendWhatMoneyKey = ValueKey('send-what-money');
const ValueKey<String> kSendWhatGiftKey = ValueKey('send-what-gift');
const ValueKey<String> kSendWhatFromKey = ValueKey('send-what-from');

/// Asks What for [name] (see the file header): Money with the From toggle
/// on [initialFrom] (the home the Send was opened from), or a prediction
/// or investment where [giftOffered]. Null when the sheet is closed.
Future<SendWhat?> showSendWhatSheet(
  BuildContext context, {
  required String name,
  required SendFrom initialFrom,
  required bool giftOffered,
}) =>
    showAppBottomSheet<SendWhat>(
      context: context,
      routeSettings: const RouteSettings(name: kSendWhatRouteName),
      builder: (_) => SendWhatSheet(
        name: name,
        initialFrom: initialFrom,
        giftOffered: giftOffered,
      ),
    );

/// The What step's sheet (see the file header).
class SendWhatSheet extends StatefulWidget {
  const SendWhatSheet({
    super.key,
    required this.name,
    required this.initialFrom,
    required this.giftOffered,
  });

  final String name;
  final SendFrom initialFrom;
  final bool giftOffered;

  @override
  State<SendWhatSheet> createState() => _SendWhatSheetState();
}

class _SendWhatSheetState extends State<SendWhatSheet> {
  late SendFrom _from = widget.initialFrom;

  void _pick(SendWhatKind what) =>
      Navigator.of(context).pop<SendWhat>((what: what, from: _from));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final name = widget.name.trim();
    final bitcoin = _from == SendFrom.bitcoin;
    final mark = 28.sp;
    // The Send to card's surface (SendToListCard), the Money row and its
    // From toggle in one card: the toggle is Money's, never the gift's.
    final card = BoxDecoration(
      color: c.surfaceLight,
      borderRadius: BorderRadius.circular(16.r),
      border: Border.all(color: c.borderSubtle, width: 0.5),
    );
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: name.isEmpty ? l10n.sendTo : l10n.sendWhatTitle(name),
            subtitle: l10n.sendWhatSubtitle,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SendToListRow(
                        key: kSendWhatMoneyKey,
                        colors: c,
                        leading: SvgPicture.asset(
                            bitcoin ? kBitcoinMarkAsset : kUsdMarkAsset,
                            width: mark,
                            height: mark),
                        // The account's mark says where it leaves from;
                        // the toggle under it says it in words.
                        title: l10n.sendWhatMoney,
                        onTap: () => _pick(SendWhatKind.money),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
                        child: Row(
                          children: [
                            Text(
                              l10n.sendWhatFrom,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.1,
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: KutePillTabs(
                                key: kSendWhatFromKey,
                                horizontalPadding: 0,
                                size: KutePillSize.regular,
                                items: [
                                  KutePillItem(
                                    key: const ValueKey(
                                        'send-what-from-bitcoin'),
                                    label: l10n.bitcoin,
                                  ),
                                  KutePillItem(
                                    key: const ValueKey(
                                        'send-what-from-dollars'),
                                    label: l10n.portfolioBalanceDollars,
                                  ),
                                ],
                                selectedIndex: bitcoin ? 0 : 1,
                                onTap: (i) => setState(() => _from = i == 0
                                    ? SendFrom.bitcoin
                                    : SendFrom.dollars),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.giftOffered) ...[
                  SizedBox(height: 12.h),
                  SendToListCard(
                    colors: c,
                    rows: [
                      SendToListRow(
                        key: kSendWhatGiftKey,
                        colors: c,
                        // The predictions' own gauge (the search rows' half
                        // ring), as the old Send chip wore it.
                        leading: const SearchChanceGauge(chance: 0.64),
                        title: l10n.sendWhatGift,
                        subtitle: l10n.sendToAFriendSub,
                        onTap: () => _pick(SendWhatKind.gift),
                      ),
                    ],
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

/// A person picked on a Send's Who step: [contact] (a phone contact) or
/// [phone] (a typed number no contact has). Asks What ([showSendWhatSheet],
/// the From toggle on [home]) and runs the existing flow for the answer
/// (see the file header): [payDirect] with the Kute address for money from
/// Bitcoin to someone on Kute, [openLink] with the link's money otherwise,
/// [openGift] for a prediction or investment. Resolves to true when a link
/// was created: the Send closes, as after a send that went out.
Future<bool> sendToPerson(
  BuildContext context, {
  SendContact? contact,
  String? phone,
  required SendFrom home,
  required bool giftOffered,
  required Future<bool?> Function(ShareLinkKind kind) openLink,
  required Future<bool?> Function() openGift,
  required void Function(String address) payDirect,
}) async {
  final name = contact?.displayName.trim().isNotEmpty == true
      ? contact!.displayName
      : (phone ?? contact?.phone ?? '');
  final what = await showSendWhatSheet(context,
      name: name, initialFrom: home, giftOffered: giftOffered);
  if (what == null || !context.mounted) return false;
  TrackingService.track('send_what_picked', params: {
    'what': what.what.name,
    'home': home.name,
    if (what.what == SendWhatKind.money) 'from': what.from.name,
  });
  switch (what.what) {
    case SendWhatKind.gift:
      return await openGift() == true;
    case SendWhatKind.money:
      final kute = contact?.lightningAddress?.trim() ?? '';
      if (what.from == SendFrom.bitcoin && kute.isNotEmpty) {
        payDirect(kute);
        return false;
      }
      return await openLink(what.from == SendFrom.bitcoin
              ? ShareLinkKind.bitcoin
              : ShareLinkKind.dollars) ==
          true;
  }
}
