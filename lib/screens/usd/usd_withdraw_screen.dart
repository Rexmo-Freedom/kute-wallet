// The Dollars Send, a sheet over the current screen (the Dollars tab's
// Send; it was the Investments Withdraw, the Deposit's sheet turned
// around).
//
// THE BITCOIN SEND'S LAYOUT (founder, 1 November 2026: "Send on Dollars
// does three main things and it must be clear"; the first step reads like
// the Bitcoin send's Send to step, confirm_send.dart):
//
//   * the title "Send dollars" and the same search field, "Name, address
//     or phone", Paste and Scan inside. A typed or pasted address the
//     dollar send recognises shows its resolved row first (the coin on its
//     network) and the bar's Continue opens the dollar send on it; one
//     that could land on several networks asks which in the coin sheet;
//   * "Frequent" directly under the field (founder, 2 November 2026:
//     "Frequent stays on top"), the recent recipients as circles, hidden
//     while typing and once a recipient is chosen;
//   * THE FOUR WAYS AS SQUARES (founder, 4 November 2026: "too many
//     options and buttons, make it more clear"; 5 November 2026: "I think
//     these should be cards like squares, also in Bitcoin"): under one
//     "Send to" label, a 2 x 2 grid of the app's big square cards
//     (kute_action_cards.dart): on top, where the money goes that is yours
//     or an address, "To your Bitcoin" (the Move money sheet, Dollars to
//     Bitcoin) and "To a crypto address" (the coins it can land as, in the
//     coin sheet, exactly as the Bitcoin send's card opens its own); under
//     them, a friend: "Send to anyone" (a link they claim with Kute, no
//     contact needed) and "Send a prediction" ("Or an investment", the
//     market search, send_pick_market_sheet.dart: a market's page, its
//     slip sends; the card goes where neither venue is open to this
//     person, sendPickOffered);
//   * All contacts A–Z under them, the friends themselves
//     (send_contacts_list.dart; founder: a growing list never hides the
//     cards): the recent dollar recipients (paid directly: the send opens
//     on that coin and address) and the phone's contacts (a claim link for
//     dollars to their number), filtered by the text, "Send a link to
//     +351…" for a typed number.
//
// No big Bitcoin card and no inline coin grid any more. The bar is the default
// "Search or Manage with AI" (the rows are the actions), Continue while the
// field holds a destination. A send that went out, or a link created, closes
// this sheet. Nothing here moves money: every door is an existing flow,
// unchanged.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/asset_icon_provider.dart' show kBitcoinMarkAsset;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/scanner/scanner_sheet.dart' show showScannerSheet;
import 'package:kute/screens/search/components/search_rows.dart'
    show SearchChanceGauge;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/screens/share/send_pick_market_sheet.dart'
    show sendPickOffered, showSendPickMarketSheet;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show MoneyMovementAccount, showMoneyMovementSheet;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart';
import 'package:kute/screens/shared/send/send_sheet.dart' show showSendSheet;
import 'package:kute/screens/usd/usd_receive_screen.dart'
    show watchSpendingBitcoinUsd;
import 'package:kute/screens/usd/usd_send_screen.dart';
import 'package:kute/services/contacts/send_contacts_service.dart'
    show SendContact, sendContactsProvider;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/orchestra_usd_send_routes.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The route name the Withdraw sheet carries.
const String kUsdWithdrawRouteName = 'withdrawDollars';

/// The Move sheet's `entry_source` when the Bitcoin card ("To your
/// wallet") at the top of this sheet opens it.
const String kUsdWithdrawBitcoinRowSource = 'usd_withdraw_bitcoin_row';

/// The dollar send's `entry_source` when a coin on this sheet opens it.
const String kUsdWithdrawSheetSource = 'usd_withdraw_sheet';

/// Send to anyone's `entry_source` for a contact or a typed number on
/// this sheet.
const String kUsdWithdrawContactSource = 'usd_withdraw_contact';

/// The Dollars tab's Send: this sheet over the current screen.
Future<void> showUsdWithdrawSheet(BuildContext context) =>
    showAppBottomSheet<void>(
      context: context,
      routeSettings: const RouteSettings(name: kUsdWithdrawRouteName),
      builder: (_) => const UsdWithdrawScreen(),
    );

/// The Dollars Send's first step (see the file header).
class UsdWithdrawScreen extends ConsumerStatefulWidget {
  const UsdWithdrawScreen({super.key});

  /// Test seam: what "To your Bitcoin" opens. Null opens the real Move
  /// money sheet, Dollars to Bitcoin.
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugMoveSheetOpener;

  /// Test seam: what a destination opens (a coin from the sheet, a
  /// resolved address, a recent). Null opens the dollar send over this
  /// sheet; the answer is whether the send went out.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context,
      UsdSendDestination destination, String? recipient)? debugSendOpener;

  /// Test seam: what "Send a prediction" opens. Null opens
  /// the market search; the answer is whether a link was created.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context)? debugPickOpener;

  /// Test seam: the claim link for a contact, a typed number or anyone
  /// ("Send to anyone", neither). Null opens Send to anyone for dollars.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context,
      {SendContact? contact, String? phone})? debugLinkOpener;

  @override
  ConsumerState<UsdWithdrawScreen> createState() => _UsdWithdrawScreenState();
}

class _UsdWithdrawScreenState extends ConsumerState<UsdWithdrawScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    TrackingService.screenView('usd_withdraw');
    // The offering is live-catalogue only, so nudge it rather than
    // waiting for the 6 h cadence.
    // ignore: discarded_futures
    ref.read(orchestraSupportedRoutesProvider.notifier).refresh();
    // The contacts' status only (never a prompt), the book if granted.
    // ignore: discarded_futures
    ref.read(sendContactsProvider.notifier).refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// "To your Bitcoin": the Move money sheet from Dollars to Bitcoin.
  void _openToBitcoin() {
    final open = UsdWithdrawScreen.debugMoveSheetOpener;
    if (open != null) {
      TrackingService.markEntrySource('move', kUsdWithdrawBitcoinRowSource);
      unawaited(open(context));
      return;
    }
    // Pinned: Investments to Bitcoin, nothing to pick, as Purchase Bitcoin
    // pins its ends (founder, 1 November 2026).
    unawaited(showMoneyMovementSheet(
      context,
      initialSource: MoneyMovementAccount.dollars,
      initialDestination: MoneyMovementAccount.bitcoin,
      entrySource: kUsdWithdrawBitcoinRowSource,
      pinned: true,
    ));
  }

  /// "Send a prediction": the market search, a pick on a
  /// link.
  Future<void> _openPick() {
    final open = UsdWithdrawScreen.debugPickOpener;
    return _afterLink(open != null
        ? open(context)
        : showSendPickMarketSheet(context,
            entrySource: kUsdWithdrawSheetSource));
  }

  /// The claim link for dollars: to a contact (its first name, its number
  /// kept in the local row), to a typed number, or to anyone (neither).
  Future<void> _openLink({SendContact? contact, String? phone}) {
    trackSendRecipientPicked(
        contact != null ? 'contact' : (phone != null ? 'phone' : 'link'));
    final open = UsdWithdrawScreen.debugLinkOpener;
    return _afterLink(open != null
        ? open(context, contact: contact, phone: phone)
        : showSendToAnyoneSheet(
            context,
            kind: ShareLinkKind.dollars,
            senderLabel: contact?.firstName,
            recipientPhone: contact?.phone ?? phone,
            entrySource: kUsdWithdrawContactSource,
          ));
  }

  /// A link created closes this sheet, as a send that went out does.
  Future<void> _afterLink(Future<bool?> created) async {
    final done = await created;
    if (done == true && mounted) _closeSelf();
  }

  void _closeSelf() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty) return;
      _setText(raw);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  Future<void> _scan() async {
    final scanned = await showScannerSheet(context);
    if (!mounted || scanned == null) return;
    _setText(scanned.trim());
  }

  void _setText(String text) {
    _search.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final text = _search.text.trim();
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offeredResult = usdSendOfferedDestinations(catalog);
    final offered = offeredResult.offered;
    final match = text.isEmpty ? null : matchUsdRecipient(text, offered);
    // A destination: the field holds an address the dollar send takes,
    // on a network it settles by itself ([UsdRecipientMatch.autoPick])
    // or one the person picks in the coin sheet.
    final auto = match == null
        ? null
        : usdSendPaymentRequestDestination(text, offered) ?? match.autoPick;
    final recognised = match != null && match.recognised;
    final looksLikeAddress = recognised || sendTextLooksLikeAddress(text);
    String? error;
    if (looksLikeAddress && (match?.candidates.isEmpty ?? true)) {
      error = recognised
          ? offeredResult.hiddenReason ?? l10n.usdSendAddressUnsupported
          : l10n.sendAddressNotIdentified;
    }
    final resolved = auto != null ? match!.address : null;
    final recents = _recentPeople(offered);

    final bar = auto != null
        ? KuteBarContext.primary(
            label: l10n.continueLabel,
            onPrimary: () => unawaited(_openSend(auto, recipient: resolved)),
            // Only built once a destination is resolved: never off.
            disabledLabel: null,
            category: SearchCategory.all,
            source: kUsdWithdrawSheetSource,
          )
        : KuteBarContext(
            label: l10n.searchOrManageAi,
            source: kUsdWithdrawSheetSource,
          );
    return KuteBarContextScope(
      barContext: bar,
      child: ReceiveSheetFrame(
        leading:
            KuteCloseButton(onPressed: () => Navigator.of(context).maybePop()),
        title: SendStepTitle(l10n.sendDollarsTitle),
        semanticTitle: l10n.sendDollarsTitle,
        // ONE scroll: the field and the cards, then the Contacts as
        // slivers (sticky letter headers), the bar's clearance at the end.
        child: CustomScrollView(
          key: const ValueKey('usd-withdraw-scroll'),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SendRecipientSearchField(
                controller: _search,
                hintText: l10n.usdSendSearchHint,
                onChanged: (_) => setState(() {}),
                onPaste: () => unawaited(_paste()),
                onScan: () => unawaited(_scan()),
              ),
              // One recipient card (founder: "more fintech"), the person
              // never listed again below.
              if (auto != null) ...[
                SizedBox(height: 20.h),
                SendRecipientCard(
                  railMark: usdSendDestinationMark(auto, size: 28),
                  address: resolved!,
                  rail: l10n.usdSendResolvedRail(
                      auto.chainDisplayName, auto.displaySymbol),
                  recents: recents,
                  onChange: _clearRecipient,
                  onTap: () => unawaited(_openSend(auto, recipient: resolved)),
                ),
              ] else if (match != null && match.candidates.length > 1) ...[
                // An address several networks take: which one.
                SizedBox(height: 12.h),
                SendToListCard(
                  colors: c,
                  emphasized: true,
                  rows: [
                    SendToListRow(
                      key: const ValueKey('usd-withdraw-pick-network'),
                      colors: c,
                      leading: Icon(Icons.swap_horiz_rounded,
                          color: c.textSecondary, size: 20.sp),
                      title: l10n.sendWhichNetworkIsThisAddressOn,
                      subtitle: l10n.sendTapToChoose,
                      onTap: () => _openCoinPicker(
                          only: match.candidates, recipient: match.address),
                    ),
                  ],
                ),
              ] else if (error != null) ...[
                SizedBox(height: 10.h),
                SendInlineError(message: error),
              ],
              // Frequent stays on top (founder, 2 November 2026):
              // directly under the field, above the Send to card. Hidden
              // while typing and once a recipient is chosen.
              SendFrequentSection(
                query: text,
                excludeAddress: resolved,
                recents: recents,
                onPerson: (p) => _onPerson(p, offered),
              ),
              // The two cards before Contacts (founder): a growing list
              // never pushes them out of sight; Contacts scroll on to the
              // bar's clearance. Hidden while a recipient is chosen: the
              // card above is the choice.
              if (auto == null) ...[
                SizedBox(height: 20.h),
                SendSectionLabel(l10n.sendToLabel),
                _optionsGrid(offered),
              ],
            ],
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              sliver: SendContactsSection(
                query: text,
                excludeAddress: resolved,
                recents: recents,
                // Frequent sits above the Send to card.
                showFrequent: false,
                onPerson: (p) => _onPerson(p, offered),
                onPhoneLink: (phone) => unawaited(_openLink(phone: phone)),
                // The sheet's own white (its dark surface in dark mode).
                background: context.isDark ? c.surface : Colors.white,
              ),
            ),
            SliverToBoxAdapter(
                child: SizedBox(height: kuteBarScrollClearance.h)),
          ],
        ),
      ),
    );
  }

  /// "Change" on the recipient card: the field empties and the Send to
  /// card and the whole Contacts list come back.
  void _clearRecipient() {
    HapticFeedback.selectionClick();
    _search.clear();
    setState(() {});
  }

  /// The recent dollar recipients as Contacts entries: the short address
  /// over the coin on its network, the coin's mark in the circle.
  List<SendPerson> _recentPeople(List<UsdSendDestination> offered) => [
        for (final r in usdSendRecentRecipients(ref, offered))
          SendPerson.recent(
            address: r.address,
            name: sendShortAddress(r.address),
            secondary: context.l10n.usdSendResolvedRail(
                r.destination.chainDisplayName, r.destination.displaySymbol),
            mark: usdSendDestinationMark(r.destination, size: 28),
          ),
      ];

  /// A Contacts entry tapped: a recent opens the send on its coin and
  /// address; a contact gets a claim link for dollars (a Kute Lightning
  /// address cannot take dollars directly).
  void _onPerson(SendPerson person, List<UsdSendDestination> offered) {
    final contact = person.contact;
    if (contact != null) {
      unawaited(_openLink(contact: contact));
      return;
    }
    final address = person.address;
    if (address == null) return;
    final recent = usdSendRecentRecipients(ref, offered, limit: 50)
        .where((r) => r.address.toLowerCase() == address.toLowerCase())
        .firstOrNull;
    if (recent == null) return;
    trackSendRecipientPicked('recent');
    unawaited(_openSend(recent.destination, recipient: recent.address));
  }

  /// THE FOUR WAYS AS SQUARES (founder, 5 November 2026: "I think these
  /// should be cards like squares"): one 2 x 2 grid of the app's big
  /// square cards (kute_action_cards.dart) under the one "Send to" label.
  /// Yours or an address on top, "To your Bitcoin" (the Move money
  /// sheet) and "To a crypto address" (the coin sheet); a friend under
  /// them, "Send to anyone" (a link, no contact needed) and "Send a
  /// prediction" (or an investment: the market search). With no coin
  /// offered the address card goes and the unavailable line sits under
  /// the three.
  Widget _optionsGrid(List<UsdSendDestination> offered) {
    final l10n = context.l10n;
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = coinGroupsOfferedUnderPolicy(
      groupCoinsByAsset([for (final d in offered) usdSendDestinationOption(d)]),
      otherLegAsset: kOrchestraUsdAssetCode,
    ).groups;
    final balance = watchSpendingBitcoinUsd(ref);
    // A prediction (an investment) is composed on a slip that can send it:
    // with both venues closed to this person the card goes
    // (send_pick_market_sheet.dart; founder, 5 November 2026).
    final pickOffered = sendPickOffered(ref.watch(runtimeCapabilitiesProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KuteActionCardGrid(
          key: const ValueKey('usd-withdraw-options'),
          cards: [
            KuteActionCard(
              key: const ValueKey('usd-withdraw-to-bitcoin'),
              visual: SvgPicture.asset(kBitcoinMarkAsset,
                  width: kKuteActionCardVisualSize.sp,
                  height: kKuteActionCardVisualSize.sp),
              title: l10n.usdSendToYourBitcoin,
              subtitle:
                  balance == null ? null : l10n.usdBitcoinBalanceLine(balance),
              onTap: _openToBitcoin,
            ),
            if (groups.isNotEmpty)
              sendAlsoSendsToCard(l10n,
                  groups: groups,
                  title: l10n.sendToCryptoAddress,
                  onTap: _openCoinPicker),
            KuteActionCard(
              key: const ValueKey('usd-withdraw-anyone'),
              visual: const SendSalShareGlyph(size: kKuteActionCardVisualSize),
              title: l10n.shareSendToAnyone,
              subtitle: l10n.shareSendToAnyoneSubtitle,
              onTap: () => unawaited(_openLink()),
            ),
            if (pickOffered)
              KuteActionCard(
              key: const ValueKey('usd-withdraw-pick'),
              // The predictions' own gauge (the search rows' half ring).
              visual: const SearchChanceGauge(chance: 0.64),
              title: l10n.sendAPrediction,
              subtitle: l10n.sendPickCardSub,
              onTap: () => unawaited(_openPick()),
            ),
          ],
        ),
        if (groups.isEmpty) ...[
          SizedBox(height: 12.h),
          ReceiveCaption(
            text: loading
                ? l10n.usdSendRoutesUnavailable
                : l10n.usdSendDestinationsUnavailable,
          ),
        ],
      ],
    );
  }

  /// The coin sheet the dollar send opens (every offered coin, or only
  /// [only] for an address several networks take); a pick opens the send
  /// on it, with [recipient] when the field held one.
  void _openCoinPicker({List<UsdSendDestination>? only, String? recipient}) {
    TrackingService.track('usd_withdraw_coin_sheet_opened');
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          final all = usdSendOfferedDestinations(catalog).offered;
          final ids = only?.map((d) => d.id).toSet();
          final choices = [
            for (final d in all)
              if (ids == null || ids.contains(d.id)) d
          ];
          return CoinAssetPickerSheet(
            otherLegAsset: kOrchestraUsdAssetCode,
            groups: groupCoinsByAsset(
                [for (final d in choices) usdSendDestinationOption(d)]),
            title: ctx.l10n.usdFlowStepCoin,
            subtitle: ctx.l10n.usdSendPickCoin,
            emptyLabel: loading
                ? ctx.l10n.usdSendRoutesUnavailable
                : ctx.l10n.usdSendDestinationsUnavailable,
            flow: 'usd_withdraw',
            onPicked: (row) {
              final picked = choices
                  .where((d) => d.id == '${row.chain}:${row.assetCode}')
                  .firstOrNull;
              if (picked == null) return;
              Navigator.of(sheetCtx).pop();
              unawaited(_openSend(picked, recipient: recipient));
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// The dollar send over this sheet, the coin already picked (and the
  /// address, when there is one). A send that went out closes this sheet
  /// behind its success screen.
  Future<void> _openSend(UsdSendDestination destination,
      {String? recipient}) async {
    TrackingService.markEntrySource('usd_send', kUsdWithdrawSheetSource);
    final open = UsdWithdrawScreen.debugSendOpener;
    final sent = open != null
        ? await open(context, destination, recipient)
        : await showSendSheet<bool>(
            context,
            builder: (_) => UsdSendScreen(
                initialDestination: destination, initialRecipient: recipient),
          );
    if (sent != true || !mounted) return;
    _closeSelf();
  }
}
