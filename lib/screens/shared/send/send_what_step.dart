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
// has) is asked What, in one small sheet over the Send ([showSendWhatSheet]),
// on the app's big cards (kute_action_cards.dart):
//
//   Send to Maria
//   What are you sending?
//   [₿  Bitcoin                          ›]   the money, of the Send it
//   [   328,686 sats available · $248.82  ]   was opened on
//   [🎁 A prediction or investment        ›]   only where a slip can send
//   [   They claim it with Kute, no wallet ]   one (sendPickOffered)
//   ( Sal  Back )                             the floating bar
//
// THE SEND ALREADY SAYS WHOSE MONEY (founder, 7 November 2026, over the
// Money card with its From toggle: "here we should have a sal button,
// this is still confusing here"; then "choosing bitcoin or dollars should
// [not need to] be decided from here, because we already know from the
// button we click"). No toggle and no Bitcoin / Dollars choice: the money
// card is the Send's own account, the Bitcoin Send's Bitcoin (the mark,
// "Bitcoin", the line the link's amount step prints: "328,686 sats
// available · $248.82", the spending wallet's bitcoin that pays the link)
// or the Dollars Send's Dollars (the mark, "Dollars", "$12.00
// available"). A figure not known yet prints no line. The gift wears the
// gift glyph the send mode's chip wears on the search sheet it opens
// (send_pick_session.dart), never the predictions' gauge (its half ring
// read as a stuck spinner). The grid lays the two out (oneLineTitles):
// two squares where both titles read on one line at half the width, else
// two compact full-width cards, as on a phone; the money card alone, full
// width and compact, where no gift can be offered.
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
// for money, the home's account); never the person, the number or an
// address.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionToFiatProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdBalanceUnknownProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/contacts/send_contacts_service.dart'
    show SendContact;
import 'package:kute/services/tracking_service.dart';

/// The account money leaves from.
enum SendFrom { bitcoin, dollars }

/// What a person is sent: money, or a prediction or investment as a gift.
enum SendWhatKind { money, gift }

/// The What step's answer: [what], and for money the account it leaves
/// [from].
typedef SendWhat = ({SendWhatKind what, SendFrom from});

/// The What sheet's route name, for the route observers; also the bar's
/// `search_opened` source while it is up.
const String kSendWhatRouteName = 'send_what';

/// The What sheet's cards: the money, and the gift.
const ValueKey<String> kSendWhatMoneyKey = ValueKey('send-what-money');
const ValueKey<String> kSendWhatGiftKey = ValueKey('send-what-gift');

/// Asks What for [name] (see the file header): the money of [from] (the
/// Send it was opened on), or a prediction or investment where
/// [giftOffered]. Null when the sheet is closed.
Future<SendWhat?> showSendWhatSheet(
  BuildContext context, {
  required String name,
  required SendFrom from,
  required bool giftOffered,
}) =>
    showAppBottomSheet<SendWhat>(
      context: context,
      routeSettings: const RouteSettings(name: kSendWhatRouteName),
      builder: (_) => SendWhatSheet(
        name: name,
        from: from,
        giftOffered: giftOffered,
      ),
    );

/// What the Bitcoin card says is there: the spending wallet's bitcoin
/// (the pool the link pays from, as Send to anyone reads it) in the
/// Bitcoin unit from Settings with its fiat, the link's amount step's own
/// line ("328,686 sats available · $248.82"); "328,686 sats available"
/// while no fiat figure can be read (no rate yet); null while the balance
/// is unknown.
String? watchSendWhatBitcoinAvailable(WidgetRef ref, AppLocalizations l10n) {
  try {
    final settings = ref.watch(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) return null;
    final sats =
        ref.watch(walletBalanceCacheProvider)[spending.id]?.sparkBitcoinbalance;
    if (sats == null) return null;
    final unit = settings.btcFormat;
    final amount = sats.toFormattedString(unit);
    String fiat;
    try {
      fiat = ref.watch(conversionToFiatProvider(sats));
    } catch (_) {
      fiat = '';
    }
    // No rate yet reads as zero: a balance is never "· $0.00".
    if (sats > 0 && !RegExp('[1-9]').hasMatch(fiat)) fiat = '';
    return fiat.isEmpty
        ? l10n.hlYieldAvailableLine('$amount $unit')
        : l10n.sendAmountUnitAvailableWithFiat(amount, unit, fiat);
  } catch (_) {
    return null;
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
  const SendWhatSheet({
    super.key,
    required this.name,
    required this.from,
    required this.giftOffered,
  });

  final String name;

  /// The account the money leaves from: the Send's own.
  final SendFrom from;
  final bool giftOffered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final who = name.trim();
    final bitcoin = from == SendFrom.bitcoin;
    final mark = kKuteActionCardVisualSize.sp;
    void pick(SendWhatKind what) =>
        Navigator.of(context).pop<SendWhat>((what: what, from: from));
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
              // Squares only where both titles read on one line, else two
              // compact full-width cards (see the file header).
              oneLineTitles: true,
              cards: [
                KuteActionCard(
                  key: kSendWhatMoneyKey,
                  visual: SvgPicture.asset(
                      bitcoin ? kBitcoinMarkAsset : kUsdMarkAsset,
                      width: mark,
                      height: mark),
                  title: bitcoin ? l10n.bitcoin : l10n.portfolioBalanceDollars,
                  subtitle: bitcoin
                      ? watchSendWhatBitcoinAvailable(ref, l10n)
                      : watchSendWhatDollarsAvailable(ref, l10n),
                  onTap: () => pick(SendWhatKind.money),
                ),
                if (giftOffered)
                  KuteActionCard(
                    key: kSendWhatGiftKey,
                    // The send mode chip's gift (send_pick_session.dart).
                    visual: const KuteActionCardIcon(
                        Icons.card_giftcard_rounded),
                    title: l10n.sendWhatGift,
                    subtitle: l10n.sendToAFriendSub,
                    onTap: () => pick(SendWhatKind.gift),
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

/// A person picked on a Send's Who step: [contact] (a phone contact) or
/// [phone] (a typed number no contact has). Asks What ([showSendWhatSheet],
/// the money of [home], the Send it was opened on) and runs the existing
/// flow for the answer (see the file header): [payDirect] with the Kute
/// address for money from Bitcoin to someone on Kute, [openLink] with the
/// link's money otherwise, [openGift] for a prediction or investment.
/// Resolves to true when a link was created: the Send closes, as after a
/// send that went out.
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
      name: name, from: home, giftOffered: giftOffered);
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
