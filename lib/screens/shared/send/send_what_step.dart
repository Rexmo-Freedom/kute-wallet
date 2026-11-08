// lib/screens/shared/send/send_what_step.dart
//
// WHO, THEN WHAT, THEN REVIEW (founder, 7 November 2026, the approved
// Send: "ok do it, just make sure that people realise they can send to
// different cryptos also"). Both Sends, the Bitcoin one (confirm_send.dart)
// and the Dollars one (usd/usd_withdraw_screen.dart), share their Who step
// (send_recipient_step.dart); this What step is the Dollars Send's alone.
// Each keeps its own amount and its own Review.
//
// An ADDRESS needs no What: the input decides the rail and the send goes
// on to its amount. On the BITCOIN SEND a person needs none either (founder,
// 8 November 2026: "just assume that it is bitcoin, so this picker is not
// necessary"): confirm_send.dart sends them bitcoin straight on, no sheet and
// no gift, so a gift starts only from the Dollars Send. On the DOLLARS SEND a
// PERSON (a phone contact, a typed number no contact has) is asked What, in
// one small sheet over the Send ([showSendWhatSheet]), on the app's big cards
// (kute_action_cards.dart):
//
//   Send to Maria
//   What are you sending?
//   [$                ] [Sal              ]   the money, this Send's Dollars;
//   [Dollars          ] [A prediction or  ]   the gift, whatever is held
//   [$12.00 available ] [investment       ]   (see THE GIFT IS ALWAYS THERE)
//   [                 ] [They claim it... ]
//   ( Sal  Back )                             the floating bar
//
// THE SEND ALREADY SAYS WHOSE MONEY (founder, 7 November 2026, over the
// Money card with its From toggle: "here we should have a sal button,
// this is still confusing here"; then "choosing bitcoin or dollars should
// [not need to] be decided from here, because we already know from the
// button we click"). No toggle and no Bitcoin / Dollars choice: the money
// card is this Send's Dollars (the mark, "Dollars", "$12.00 available"). A
// figure not known yet prints no line.
//
// THE SQUARES (founder, 7 November 2026, of the two full-width rows the
// cards were: "here should be the squares"). The grid lays the two out as
// two equal squares side by side, whatever the language: "A prediction or
// investment" wraps to the lines it needs at half a phone's width and the
// money card grows with it (the grid's square rules,
// kute_action_cards.dart). The money card alone, full width and compact,
// only where the policy withholds the gift (the grid's lone card).
//
// THE GIFT IS ALWAYS THERE, ON THIS SHEET (founder, 8 November 2026: "we need
// to have it as an option always"). It never reads positions, a venue's cash
// or any balance: the link moves nothing when it is created
// (models/share_link_model.dart). A refused trade never stops it here
// (founder, 8 November 2026: "only on the last screen, the bet slip, show
// this error, not in this part"): the market's slip says why and sends
// nothing (slip_share.dart). Only the backend's policy decides, read live
// while the sheet is up (send_pick_market_sheet.dart): a venue's browse open
// opens the search; neither open for a region (or no policy read yet) keeps
// the card, as it looks, and its tap asks again, then says why on the shared
// Unavailable sheet with "Check connection", the sheet staying under it;
// only a browse refusal of another kind on both venues (a switch off, a
// platform or version rule, coming soon) takes the card away.
//
// SAL IS THE GIFT (founder, 7 November 2026, of its grey-boxed gift glyph:
// "a prediction or investment should be like the icon much better, maybe
// sal"): the gift wears Sal's `share` face ([SendSalShareGlyph], the face
// the send mode's bar and the link rows wear), no box, in the same 40 box
// as the money's round mark. He is drawn at his face's own cell, 48
// ([kSendWhatSalSize]): the cell keeps a margin round him, so at 48 his
// drawing, ear to scarf, is as wide and as tall as the Dollars disc beside
// him (at 40 he read a size smaller), in light and dark; never the
// predictions' gauge (its half ring read as a stuck spinner).
//
// THE BAR IS ITS BACK (the PIN sheet's Cancel, pin_gate_sheet.dart): the
// sheet is the Send's second step over its first, so while it is up the
// floating Sal bar is its one button, Back ([KuteBarContext.primary],
// beating the short sheet's hidden context), Sal's face on it and the
// Sal sheet a long press away; a tap closes the sheet, the Who step
// under it as it was: no answer, no event.
//
// [sendToPerson] then runs the existing flow, nothing new moves money:
//
//   * Money: the claim link, Send to anyone in dollars (a Kute address takes
//     no dollars; send_to_anyone_sheet.dart), the first name and the number
//     kept in the local row;
//   * A prediction or investment: the search sheet in send mode with the
//     person prefilled (send_pick_market_sheet.dart, SendPickSession): a
//     market, its slip's "Send $X · side", then Send to anyone's "Who is it
//     for?" with the name already there. A gift is always a link: the
//     claim screen places it.
//
// `send_what_picked {what, from, home}` once per answer (the From only for
// money; both always "dollars" now, kept for the events already counted: the
// Bitcoin Send asks nothing and counts nothing); never the person, the number
// or an address.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/screens/share/send_pick_market_sheet.dart'
    show sendGiftShown, sendGiftStoppedByBrowse;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendSalShareGlyph;
import 'package:kute/services/contacts/send_contacts_service.dart'
    show SendContact;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/services/tracking_service.dart';

/// What a person is sent: money, or a prediction or investment as a gift.
enum SendWhatKind { money, gift }

/// The What sheet's route name, for the route observers; also the bar's
/// `search_opened` source while it is up.
const String kSendWhatRouteName = 'send_what';

/// The What sheet's cards: the money, and the gift.
const ValueKey<String> kSendWhatMoneyKey = ValueKey('send-what-money');
const ValueKey<String> kSendWhatGiftKey = ValueKey('send-what-gift');

/// Asks What for [name] (see the file header): this Send's Dollars, or a
/// prediction or investment. Null when the sheet is closed.
Future<SendWhatKind?> showSendWhatSheet(
  BuildContext context, {
  required String name,
}) =>
    showAppBottomSheet<SendWhatKind>(
      context: context,
      routeSettings: const RouteSettings(name: kSendWhatRouteName),
      builder: (_) => SendWhatSheet(name: name),
    );

/// The size Sal's face is drawn at on the gift card: his face's own cell
/// (see the file header).
const double kSendWhatSalSize = 48;

/// The gift card's visual (see the file header): Sal's `share` face at
/// [kSendWhatSalSize] in the card's 40 visual box, standing on its foot,
/// so his drawing covers the box as the money's round mark covers its own.
class SendWhatSal extends StatelessWidget {
  const SendWhatSal({super.key});

  @override
  Widget build(BuildContext context) {
    final sal = kSendWhatSalSize.sp;
    return SizedBox.square(
      dimension: kKuteActionCardVisualSize.sp,
      child: OverflowBox(
        minWidth: 0,
        maxWidth: sal,
        minHeight: 0,
        maxHeight: sal,
        alignment: Alignment.bottomCenter,
        child: const SendSalShareGlyph(size: kSendWhatSalSize),
      ),
    );
  }
}

/// What the Dollars card says is there: the Dollars balance floored to
/// the cent, as Send to anyone's dollar amount step prints it ("$12.00
/// available"); null while the SDK has not answered.
String? watchSendWhatDollarsAvailable(WidgetRef ref, AppLocalizations l10n) {
  try {
    if (ref.watch(usdBalanceUnknownProvider)) return null;
    final cents = (ref.watch(usdBalanceProvider) * 100).floor();
    return l10n.hlYieldAvailableLine('\$${(cents / 100).toStringAsFixed(2)}');
  } catch (_) {
    return null;
  }
}

/// The What step's sheet (see the file header).
class SendWhatSheet extends ConsumerWidget {
  const SendWhatSheet({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final who = name.trim();
    final mark = kKuteActionCardVisualSize.sp;
    void pick(SendWhatKind what) =>
        Navigator.of(context).pop<SendWhatKind>(what);
    // Live: the policy, never what is held (see the file header).
    final policy = ref.watch(runtimeCapabilitiesProvider);
    Future<void> pickGift() async {
      if (await sendGiftStoppedByBrowse(context, policy)) return;
      if (context.mounted) pick(SendWhatKind.gift);
    }

    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: who.isEmpty ? l10n.sendTo : l10n.sendWhatTitle(who),
            subtitle: l10n.sendWhatSubtitle,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: KuteActionCardGrid(
              key: const ValueKey('send-what-cards'),
              // Two squares, the gift's title on two lines where it needs
              // them; the money card alone only where the policy withholds
              // the gift (see the file header).
              cards: [
                KuteActionCard(
                  key: kSendWhatMoneyKey,
                  visual: SvgPicture.asset(kUsdMarkAsset,
                      width: mark, height: mark),
                  title: l10n.portfolioBalanceDollars,
                  subtitle: watchSendWhatDollarsAvailable(ref, l10n),
                  onTap: () => pick(SendWhatKind.money),
                ),
                if (sendGiftShown(policy))
                  KuteActionCard(
                    key: kSendWhatGiftKey,
                    // Sal's share face, as big as the money's mark, no
                    // box (see the file header).
                    visual: const SendWhatSal(),
                    title: l10n.sendWhatGift,
                    subtitle: l10n.sendToAFriendSub,
                    onTap: pickGift,
                  ),
              ],
            ),
          ),
          // THE BAR IS ITS BACK (see the file header): the sheet keeps
          // the bar's room under its cards.
          KuteBarContextScope(
            barContext: KuteBarContext.primary(
              label: l10n.back,
              onPrimary: () {
                if (context.mounted) Navigator.of(context).pop();
              },
              source: kSendWhatRouteName,
              // Never waits on input.
              disabledLabel: null,
            ),
            child: SizedBox(height: kuteBarScrollClearance.h),
          ),
        ],
      ),
    );
  }
}

/// A person picked on the Dollars Send's Who step: [contact] (a phone contact)
/// or [phone] (a typed number no contact has). Asks What ([showSendWhatSheet])
/// and runs the existing flow for the answer (see the file header): [openLink]
/// for this Send's Dollars, [openGift] for a prediction or investment. Resolves
/// to true when a link was created: the Send closes, as after a send that went
/// out.
Future<bool> sendToPerson(
  BuildContext context, {
  SendContact? contact,
  String? phone,
  required Future<bool?> Function() openLink,
  required Future<bool?> Function() openGift,
}) async {
  final name = contact?.displayName.trim().isNotEmpty == true
      ? contact!.displayName
      : (phone ?? contact?.phone ?? '');
  final what = await showSendWhatSheet(context, name: name);
  if (what == null || !context.mounted) return false;
  TrackingService.track('send_what_picked', params: {
    'what': what.name,
    'home': 'dollars',
    if (what == SendWhatKind.money) 'from': 'dollars',
  });
  switch (what) {
    case SendWhatKind.gift:
      return await openGift() == true;
    case SendWhatKind.money:
      return await openLink() == true;
  }
}
