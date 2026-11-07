// The Dollars Send, a sheet over the current screen (the Dollars tab's
// Send; it was the Investments Withdraw, the Deposit's sheet turned
// around).
//
// THE SAME WHO STEP AS THE BITCOIN SEND (founder, 7 November 2026, the
// approved Send: "ok do it, just make sure that people realise they can
// send to different cryptos also"; send_recipient_step.dart): Who, then
// What, then Review. Only the home differs: here the money leaves from
// Dollars unless the person or the address says otherwise.
//
//   * the title "Send dollars" and the same search field, "Name, phone or
//     any crypto address", Paste and Scan inside;
//   * while it is empty, the crypto hint under it: the coins stacked and
//     "Send to Bitcoin, USDC, USDT, ETH and 18 more" from the very coins the
//     dollar send offers under the policy; a tap opens the coin sheet as a
//     browse list, and a coin picked turns the field into that coin's
//     address field ("USDC on Base address", the coin with Change under
//     it). With no coin offered the hint is not there and the unavailable
//     line says why;
//   * THE INPUT DECIDES THE RAIL: an address the dollar send takes on one
//     network resolves as the recipient card (the coin on its network) and
//     Continue opens the dollar send straight on its amount; one several
//     networks take asks which in the coin sheet, filtered to it; a
//     destination only bitcoin pays (a Lightning invoice or address, a
//     Spark address, a bitcoin address no dollar route takes) is handed to
//     the Bitcoin Send, preset, on its amount ("From your Bitcoin" says so
//     on the card). A paste or a scan goes straight on, a typed address
//     waits for Continue;
//   * an own account's name typed ("bitcoin", "my dollars") offers "Move
//     to your Bitcoin" / "Move to your Dollars", Move money straight on the
//     amount (showOwnMoneyMove): the escape hatch, never a chip;
//   * "Frequent" (the recent dollar recipients, paid directly: the send
//     opens on that coin and address, on its amount) and All contacts A-Z
//     (send_contacts_list.dart). A contact, or a typed number no contact
//     has, is a person: What first (send_what_step.dart: this Send's
//     Dollars, or a gift), then the existing flow: the claim link in
//     dollars (a Kute address takes none), or a prediction or investment
//     from the search in send mode.
//
// No chips any more (founder, 7 November 2026: one verb per intent): no
// "To your Bitcoin" (the Bitcoin Receive's "From your Dollars" fills it),
// no "Crypto address", no "Prediction or investment".
//
// The bar is the default "Search or Manage with AI", Continue while the
// field holds a destination. A send that went out, or a link created,
// closes this sheet. Nothing here moves money: every door is an existing
// flow, unchanged.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/helpers/scanned_address.dart'
    show bareRecipientAddress, evmPaymentChainId;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/providers/asset_icon_provider.dart' show kBitcoinMarkAsset;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/scanner/scanner_sheet.dart' show showScannerSheet;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/screens/share/send_pick_market_sheet.dart'
    show sendPickOffered, showSendPickMarketSheet;
import 'package:kute/screens/share/send_to_anyone_sheet.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show MoneyMovementAccount, showOwnMoneyMove;
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/send/send_contacts_list.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart';
import 'package:kute/screens/shared/send/send_sheet.dart' show showSendSheet;
import 'package:kute/screens/shared/send/send_what_step.dart';
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

/// The Move sheet's `entry_source` when this sheet's search finds an own
/// account ("Move to your Bitcoin", send_recipient_step.dart).
const String kUsdWithdrawSearchSource = 'usd_withdraw_search';

/// The dollar send's `entry_source` when a destination on this sheet opens
/// it (and the Bitcoin Send's, for one only bitcoin pays).
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

/// What the field holds, read against what the dollar send offers: the
/// dollar [destination] it settles by itself, the bare [address], the
/// [candidates] it could land on (several: the network question), whether
/// only bitcoin pays it ([bitcoinRail]: the Bitcoin Send takes it), and
/// what is wrong with it ([error], said under the field).
typedef _UsdWho = ({
  UsdSendDestination? destination,
  String address,
  List<UsdSendDestination> candidates,
  bool bitcoinRail,
  String? error,
});

/// The Dollars Send's first step (see the file header).
class UsdWithdrawScreen extends ConsumerStatefulWidget {
  const UsdWithdrawScreen({super.key});

  /// Test seam: what a destination opens (a coin's address, a resolved
  /// address, a recent). Null opens the dollar send over this sheet, on
  /// its amount when the address is known; the answer is whether the send
  /// went out.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context,
      UsdSendDestination destination, String? recipient)? debugSendOpener;

  /// Test seam: what the What step's "A prediction or investment" opens,
  /// with the person picked. Null opens the market search in send mode;
  /// the answer is whether a link was created.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context,
      {String? senderLabel, String? recipientPhone})? debugPickOpener;

  /// Test seam: the claim link in [kind]'s money for a contact or a typed
  /// number. Null opens Send to anyone, with the contact's name or the
  /// number.
  @visibleForTesting
  static Future<bool?> Function(BuildContext context,
      {required ShareLinkKind kind,
      SendContact? contact,
      String? phone})? debugLinkOpener;

  /// Test seam: the Bitcoin Send for an address (a destination only
  /// bitcoin pays, or a Kute contact paid from Bitcoin). Null closes this
  /// sheet and opens the Bitcoin Send, the address preset, on its amount.
  @visibleForTesting
  static void Function(BuildContext context, String address)?
      debugBitcoinSendOpener;

  @override
  ConsumerState<UsdWithdrawScreen> createState() => _UsdWithdrawScreenState();
}

class _UsdWithdrawScreenState extends ConsumerState<UsdWithdrawScreen> {
  final TextEditingController _search = TextEditingController();

  /// The coin picked from the crypto hint's browse list: the field is its
  /// address field until Change drops it.
  UsdSendDestination? _coin;

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

  /// "Move to your Bitcoin" / "Move to your Dollars" (the search's escape
  /// hatch): Move money straight on the amount into that account, pinned
  /// (showOwnMoneyMove). Dollars to Bitcoin spends all the dollar money
  /// (Dollars, then venue cash) as the Bitcoin Receive's "From your
  /// Dollars" does.
  void _openOwnMove(SendOwnAccount into) {
    HapticFeedback.selectionClick();
    unawaited(showOwnMoneyMove(context,
        from: into == SendOwnAccount.bitcoin
            ? MoneyMovementAccount.dollars
            : MoneyMovementAccount.bitcoin,
        entrySource: kUsdWithdrawSearchSource));
  }

  /// A person (a contact, or a typed number no contact has), asked What
  /// (send_what_step.dart: this Send's Dollars, or a gift), then the
  /// existing flow. A link created closes this sheet, as a send that went
  /// out does.
  Future<void> _sendToPerson({SendContact? contact, String? phone}) async {
    trackSendRecipientPicked(contact != null ? 'contact' : 'phone');
    final label = contact?.firstName;
    final number = contact?.phone ?? phone;
    final created = await sendToPerson(
      context,
      contact: contact,
      phone: phone,
      home: SendFrom.dollars,
      giftOffered: sendPickOffered(ref.read(runtimeCapabilitiesProvider)),
      openLink: (kind) {
        final open = UsdWithdrawScreen.debugLinkOpener;
        return open != null
            ? open(context, kind: kind, contact: contact, phone: phone)
            : showSendToAnyoneSheet(
                context,
                kind: kind,
                senderLabel: label,
                recipientPhone: number,
                entrySource: kUsdWithdrawContactSource,
              );
      },
      openGift: () {
        final open = UsdWithdrawScreen.debugPickOpener;
        return open != null
            ? open(context, senderLabel: label, recipientPhone: number)
            : showSendPickMarketSheet(context,
                entrySource: kUsdWithdrawSheetSource,
                senderLabel: label,
                recipientPhone: number);
      },
      payDirect: _openBitcoinSend,
    );
    if (created && mounted) _closeSelf();
  }

  /// The Bitcoin Send for [address], preset: it opens on its amount (a
  /// native rail answers its Send to step). This sheet closes under it.
  void _openBitcoinSend(String address) {
    TrackingService.markEntrySource('send', kUsdWithdrawSheetSource);
    final open = UsdWithdrawScreen.debugBitcoinSendOpener;
    if (open != null) {
      open(context, address);
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    // Kept alive until the Bitcoin Send reads it (the provider disposes
    // with no listener): this sheet's subscription closes with it.
    ref.listenManual(sendTxProvider, (_, __) {});
    final notifier = ref.read(sendTxProvider.notifier);
    notifier.resetToDefault();
    notifier.updateAddress(address);
    unawaited(router.pushNamed('pay_send'));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _closeSelf();
    });
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
      _setText(raw, goOn: true);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  Future<void> _scan() async {
    final scanned = await showScannerSheet(context);
    if (!mounted || scanned == null) return;
    _setText(scanned.trim(), goOn: true);
  }

  /// [text] into the field; a paste or a scan ([goOn]) goes straight on:
  /// a destination to its amount, an address several networks take to the
  /// network question, one only bitcoin pays to the Bitcoin Send.
  void _setText(String text, {bool goOn = false}) {
    _search.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {});
    if (!goOn) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _search.text != text) return;
      final offered =
          usdSendOfferedDestinations(ref.read(orchestraSupportedRoutesProvider))
              .offered;
      final who = _who(text.trim(), offered, context.l10n);
      final destination = who.destination;
      if (destination != null) {
        trackSendRecipientPicked('address');
        unawaited(_openSend(destination, recipient: who.address));
      } else if (who.bitcoinRail) {
        trackSendRecipientPicked('address');
        _openBitcoinSend(text.trim());
      } else if (who.candidates.length > 1) {
        _openCoinPicker(only: who.candidates, recipient: who.address);
      }
    });
  }

  /// What [text] means here (see the file header): with a coin picked from
  /// the hint, an address for that coin's network only; otherwise the
  /// dollar destinations it can land on, or bitcoin's own rails.
  _UsdWho _who(String text, List<UsdSendDestination> offered,
      AppLocalizations l10n,
      {String? hiddenReason}) {
    final coin = _pickedCoin(offered);
    if (text.isEmpty) {
      return (
        destination: null,
        address: '',
        candidates: const <UsdSendDestination>[],
        bitcoinRail: false,
        error: null,
      );
    }
    if (coin != null) {
      final address = bareRecipientAddress(text);
      final accepted = usdSendDestinationAccepts(coin, address,
          chainId: evmPaymentChainId(text));
      final looksLikeAddress = usdSendAddressFamily(address) != 'unknown' ||
          sendTextLooksLikeAddress(text);
      return (
        destination: accepted ? coin : null,
        address: address,
        candidates: accepted ? [coin] : const <UsdSendDestination>[],
        bitcoinRail: false,
        error: !accepted && looksLikeAddress
            ? l10n.usdSendNotNetworkAddress(coin.chainDisplayName)
            : null,
      );
    }
    final match = matchUsdRecipient(text, offered);
    // A destination: an address the dollar send takes, on a network it
    // settles by itself ([UsdRecipientMatch.autoPick]).
    final auto =
        usdSendPaymentRequestDestination(text, offered) ?? match.autoPick;
    final bitcoinRail = match.candidates.isEmpty && sendIsBitcoinRail(text);
    final looksLikeAddress =
        match.recognised || sendTextLooksLikeAddress(text);
    String? error;
    if (!bitcoinRail && looksLikeAddress && match.candidates.isEmpty) {
      error = match.recognised
          ? hiddenReason ?? l10n.usdSendAddressUnsupported
          : l10n.sendAddressNotIdentified;
    }
    return (
      destination: auto,
      address: match.address,
      candidates: match.candidates,
      bitcoinRail: bitcoinRail,
      error: error,
    );
  }

  /// The picked coin while the dollar send still offers it.
  UsdSendDestination? _pickedCoin(List<UsdSendDestination> offered) {
    final coin = _coin;
    if (coin == null) return null;
    return offered.where((d) => d.id == coin.id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final text = _search.text.trim();
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    ref.watch(runtimeCapabilitiesProvider);
    final offeredResult = usdSendOfferedDestinations(catalog);
    final offered = offeredResult.offered;
    final coin = _pickedCoin(offered);
    final who =
        _who(text, offered, l10n, hiddenReason: offeredResult.hiddenReason);
    final auto = who.destination;
    // A recipient chosen: a dollar destination, or one only bitcoin pays.
    final chosen = auto != null || who.bitcoinRail;
    final resolved = auto != null ? who.address : null;
    final recents = _recentPeople(offered);
    final background = context.isDark ? c.surface : Colors.white;
    // The coins the hint names and its browse list offers: the dollar
    // send's own destinations, less what the policy withdraws.
    final loading = ref.watch(orchestraRoutesReadyProvider).isLoading;
    final groups = coinGroupsOfferedUnderPolicy(
      groupCoinsByAsset([for (final d in offered) usdSendDestinationOption(d)]),
      otherLegAsset: kOrchestraUsdAssetCode,
    ).groups;
    final atRest = text.isEmpty && coin == null;

    final bar = chosen
        ? KuteBarContext.primary(
            label: l10n.continueLabel,
            onPrimary: _continue,
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
        // ONE scroll: the field and its results, then the Contacts as
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
                      hintText: coin != null
                          ? l10n.sendAssetOnNetworkAddressHint(
                              coin.displaySymbol, coin.chainDisplayName)
                          : l10n.sendRecipientSearchHint,
                      onChanged: (_) => setState(() {}),
                      onPaste: () => unawaited(_paste()),
                      onScan: () => unawaited(_scan()),
                    ),
                    if (auto != null) ...[
                      // One recipient card, the person never listed again.
                      SizedBox(height: 20.h),
                      SendRecipientCard(
                        railMark: usdSendDestinationMark(auto, size: 28),
                        address: resolved!,
                        rail: l10n.usdSendResolvedRail(
                            auto.chainDisplayName, auto.displaySymbol),
                        recents: recents,
                        onChange: _clearRecipient,
                        onTap: _continue,
                      ),
                    ] else if (who.bitcoinRail) ...[
                      // Only bitcoin pays it: the card says the money
                      // leaves from Bitcoin (the Bitcoin Send takes it).
                      SizedBox(height: 20.h),
                      SendRecipientCard(
                        railMark: SvgPicture.asset(kBitcoinMarkAsset,
                            width: 28.sp, height: 28.sp),
                        address: text,
                        rail: l10n.usdReceiveFromYourBitcoin,
                        recents: recents,
                        onChange: _clearRecipient,
                        onTap: _continue,
                      ),
                    ] else if (coin == null && who.candidates.length > 1) ...[
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
                                only: who.candidates, recipient: who.address),
                          ),
                        ],
                      ),
                    ],
                    // The coin picked from the hint, Change at its right:
                    // back to the plain field.
                    if (coin != null && auto == null) ...[
                      SizedBox(height: 12.h),
                      SendToListCard(
                        key: const ValueKey('usd-withdraw-coin-card'),
                        colors: c,
                        rows: [
                          SendToListRow(
                            colors: c,
                            leading: usdSendDestinationMark(coin, size: 28),
                            title: '${coin.displaySymbol} · '
                                '${coin.chainDisplayName}',
                            trailing: SendChangeButton(
                              key: const ValueKey('usd-withdraw-coin-change'),
                              onTap: _clearCoin,
                            ),
                            onTap: () => _openCoinPicker(browse: true),
                          ),
                        ],
                      ),
                    ],
                    if (who.error != null) ...[
                      SizedBox(height: 10.h),
                      SendInlineError(message: who.error!),
                    ],
                    // What else the field takes, under it while empty; with
                    // no coin offered, the line that says why instead.
                    if (atRest)
                      groups.isNotEmpty
                          ? SendCryptoHint(
                              groups: groups,
                              background: background,
                              onTap: _openCryptoHint,
                            )
                          : Padding(
                              padding: EdgeInsets.only(top: 12.h),
                              child: ReceiveCaption(
                                text: loading
                                    ? l10n.usdSendRoutesUnavailable
                                    : l10n.usdSendDestinationsUnavailable,
                              ),
                            ),
                    // An own account's name typed: the move into it.
                    if (coin == null && !chosen && who.candidates.isEmpty)
                      SendMoveToOwnRows(query: text, onMove: _openOwnMove),
                    // The people: Frequent directly under the field, hidden
                    // while typing and once a recipient is chosen.
                    if (coin == null)
                      SendFrequentSection(
                        query: text,
                        excludeAddress: resolved,
                        recents: recents,
                        onPerson: (p) => _onPerson(p, offered),
                      ),
                  ],
                ),
              ),
            ),
            if (coin == null && !who.bitcoinRail)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                sliver: SendContactsSection(
                  query: text,
                  excludeAddress: resolved,
                  recents: recents,
                  // Frequent sits above, under the field.
                  showFrequent: false,
                  onPerson: (p) => _onPerson(p, offered),
                  onPhoneLink: (phone) =>
                      unawaited(_sendToPerson(phone: phone)),
                  // The sheet's own white (its dark surface in dark mode).
                  background: background,
                ),
              ),
            SliverToBoxAdapter(
                child: SizedBox(height: kuteBarScrollClearance.h)),
          ],
        ),
      ),
    );
  }

  /// The bar's Continue (and a tap on the recipient card): the dollar send
  /// on the destination, on its amount, or the Bitcoin Send for one only
  /// bitcoin pays.
  void _continue() {
    final offered =
        usdSendOfferedDestinations(ref.read(orchestraSupportedRoutesProvider))
            .offered;
    final text = _search.text.trim();
    final who = _who(text, offered, context.l10n);
    final destination = who.destination;
    if (destination != null) {
      trackSendRecipientPicked('address');
      unawaited(_openSend(destination, recipient: who.address));
    } else if (who.bitcoinRail) {
      trackSendRecipientPicked('address');
      _openBitcoinSend(text);
    }
  }

  /// The crypto hint: the coin sheet as a browse list; a coin picked turns
  /// the field into its address field.
  void _openCryptoHint() {
    TrackingService.track('usd_withdraw_coin_sheet_opened',
        params: {'source': 'crypto_hint'});
    _openCoinPicker(browse: true, tracked: true);
  }

  /// "Change" on the recipient card: the field empties and the hint and
  /// the whole Contacts list come back.
  void _clearRecipient() {
    HapticFeedback.selectionClick();
    _search.clear();
    setState(() {});
  }

  /// "Change" beside the coin picked from the hint: back to the plain
  /// field, the Contacts with it.
  void _clearCoin() {
    HapticFeedback.selectionClick();
    setState(() => _coin = null);
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
  /// address, on its amount; a contact is a person, asked What first.
  void _onPerson(SendPerson person, List<UsdSendDestination> offered) {
    final contact = person.contact;
    if (contact != null) {
      unawaited(_sendToPerson(contact: contact));
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

  /// The coin sheet of the dollar send: every offered coin ([browse], the
  /// crypto hint's list: a pick becomes the field's coin), or only [only]
  /// for an address several networks take (a pick opens the send on it
  /// with [recipient]).
  void _openCoinPicker(
      {List<UsdSendDestination>? only,
      String? recipient,
      bool browse = false,
      bool tracked = false}) {
    if (!tracked) TrackingService.track('usd_withdraw_coin_sheet_opened');
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
            selectedOptionId: browse ? _coin?.id : null,
            onPicked: (row) {
              final picked = choices
                  .where((d) => d.id == '${row.chain}:${row.assetCode}')
                  .firstOrNull;
              if (picked == null) return;
              Navigator.of(sheetCtx).pop();
              if (browse) {
                setState(() => _coin = picked);
                return;
              }
              unawaited(_openSend(picked, recipient: recipient));
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// The dollar send over this sheet, the coin already picked and, with
  /// [recipient], on its amount (the Who step answered here). A send that
  /// went out closes this sheet behind its success screen.
  Future<void> _openSend(UsdSendDestination destination,
      {String? recipient}) async {
    TrackingService.markEntrySource('usd_send', kUsdWithdrawSheetSource);
    final open = UsdWithdrawScreen.debugSendOpener;
    final sent = open != null
        ? await open(context, destination, recipient)
        : await showSendSheet<bool>(
            context,
            builder: (_) => UsdSendScreen(
              initialDestination: destination,
              initialRecipient: recipient,
              startOnAmount: recipient != null,
            ),
          );
    if (sent != true || !mounted) return;
    _closeSelf();
  }
}
