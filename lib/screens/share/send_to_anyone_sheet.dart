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
//   2. Who is it for? One text field, the first name, optional, under THE
//      SHARE CARD live at about 60% (founder, 1 November 2026: "the card
//      makes it feel like a gift"; cards/share_cards.dart): "{Name}, I
//      sent you" over the amount as they type, or the pick's card (the
//      prediction's odds, the actual stock). Create link posts to the
//      backend (nothing moves: a share link is a pending send, see
//      models/share_link_model.dart).
//   3. The card in full ("Your card is ready") over the pending row
//      (pending_share_links.dart), the bar "Share": the card as a PNG in
//      the OS share sheet with "{name}, I sent you {amount} with Kute.
//      Claim it here: {url}". Sharing always shows the card first; Done
//      is a text button.
//
// Launched from a market page's bar, the market share sheet or the
// market search (kute_share_actions.dart, share_market_sheet.dart,
// send_pick_market_sheet.dart) the sheet carries THE PICK on the link: the
// market slug and title, the venue, the outcome ("Yes", a candidate,
// "Long"), its index and the side. The pick reads above the amount, the
// market's picture beside it ("Yes on Gemini Carbon", "64% chance"), goes
// to the backend with the link, and the share text says "I sent you a
// prediction on Kute: Yes on Gemini Carbon, $12.00".
//
// NO SIDE IS EVER CHOSEN FOR THE PERSON (founder, 4 November 2026: "it
// auto-selects No"). Handed a market ([SendToAnyoneSheet.market],
// send_pick.dart) whose side is not picked yet, the sheet opens on a step
// before the amount: what is sent (the market's picture and name) over
// every side it can send, the two sides of a Yes/No market as the market
// page's own pair, equal, nothing selected, or one row per outcome; a tap
// is the choice and the amount follows, the pick over it with "Change"
// back to the sides. Each step says what it asks: the side, how much, who
// it is for.
//
// A PREDICTION pick can go as a DARE (share_challenge.dart): the
// "Challenge them" switch under the name, off by default, turns the live
// card into the challenge card (both sides, the sender's marked) and the
// link into a challenge (`challenge: true` to the backend, `?challenge=1`
// on the URL kept in the pending row, so every resend carries it). It is
// offered once the side is chosen (never a side chosen for the person).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/providers/currency_conversions_provider.dart'
    show conversionProvider, conversionToFiatProvider, inputToSatsProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show shareCardMessage;
import 'package:kute/screens/share/cards/share_card_data.dart';
import 'package:kute/screens/share/cards/share_card_preview.dart';
import 'package:kute/screens/share/cards/share_card_sources.dart';
import 'package:kute/screens/share/pending_share_links.dart';
import 'package:kute/screens/share/send_pick.dart';
import 'package:kute/screens/share/share_challenge.dart';
import 'package:kute/screens/share/share_link_copy.dart';
import 'package:kute/screens/share/share_link_resend.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart' show AmountKeypad;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_text_field.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show SendAmountUnitPill, SendToListCard, SendTypedAmountHero;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show SendChangeButton;
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
/// [market] is a market whose side the person picks first (or whose side
/// was picked already, a position's); it stands in for the pick fields.
Future<bool?> showSendToAnyoneSheet(
  BuildContext context, {
  required ShareLinkKind kind,
  SendPickMarket? market,
  String? marketSlug,
  String? marketTitle,
  String? venue,
  String? outcome,
  int? outcomeIndex,
  String? side,
  String? senderLabel,
  String? recipientPhone,
  required String entrySource,
}) {
  TrackingService.markEntrySource('share_link', entrySource);
  return showAppBottomSheet<bool>(
    context: context,
    routeSettings: const RouteSettings(name: kSendToAnyoneRouteName),
    builder: (_) => SendToAnyoneSheet(
      kind: kind,
      market: market,
      marketSlug: marketSlug,
      marketTitle: marketTitle,
      venue: venue,
      outcome: outcome,
      outcomeIndex: outcomeIndex,
      side: side,
      senderLabel: senderLabel,
      recipientPhone: recipientPhone,
    ),
  );
}

class SendToAnyoneSheet extends ConsumerStatefulWidget {
  const SendToAnyoneSheet({
    super.key,
    required this.kind,
    this.market,
    this.marketSlug,
    this.marketTitle,
    this.venue,
    this.outcome,
    this.outcomeIndex,
    this.side,
    this.senderLabel,
    this.recipientPhone,
  });

  final ShareLinkKind kind;

  /// A market whose side is picked on the sheet's first step (see the
  /// file header); with one, the pick fields below are left out.
  final SendPickMarket? market;
  final String? marketSlug;

  /// The name field prefilled (a contact picked on the Send screen, its
  /// first name). The person can still change it.
  final String? senderLabel;

  /// The picked contact's number, kept in the local row only (see
  /// PendingShareLink.recipientPhone); offers WhatsApp and SMS on the
  /// receipt with it prefilled. Never posted, never tracked.
  final String? recipientPhone;

  /// The pick (see the file header); all null for a plain send.
  final String? marketTitle;
  final String? venue;
  final String? outcome;
  final int? outcomeIndex;
  final String? side;

  /// Whether the link carries a pick handed over as it is (a market to
  /// pick the side on counts once the side is picked; see the state).
  bool get hasPick =>
      market != null ||
      ((outcome?.trim().isNotEmpty ?? false) &&
          (marketTitle?.trim().isNotEmpty ?? false));

  @override
  ConsumerState<SendToAnyoneSheet> createState() => _SendToAnyoneSheetState();
}

enum _Step { side, amount, name, done }

class _SendToAnyoneSheetState extends ConsumerState<SendToAnyoneSheet> {
  /// The market with the side picked so far (see the file header).
  late SendPickMarket? _market = widget.market;
  late _Step _step =
      widget.market?.needsSide ?? false ? _Step.side : _Step.amount;
  String _typed = '';
  late final TextEditingController _name =
      TextEditingController(text: widget.senderLabel?.trim() ?? '');
  bool _creating = false;
  bool _sharing = false;

  /// "Challenge them" (share_challenge.dart), a prediction pick only.
  bool _challenge = false;
  bool get _canChallenge =>
      shareChallengeOffered(hasPick: _hasPick, venue: _pickVenue);
  String? _error;
  PendingShareLink? _created;

  /// The card's capture (the last step) and Sal's line, picked once.
  final GlobalKey _boundary = GlobalKey();
  final GlobalKey _liveBoundary = GlobalKey();
  final int _seed = ShareCardShare.seed();

  ShareLinkKind get kind => widget.kind;
  bool get _dollars => kind == ShareLinkKind.dollars;

  /// The pick the link carries: the market's picked side, else the pick
  /// fields as handed over.
  SendPickSide? get _side => _market?.settled;
  String? get _pickSlug => _market?.slug ?? widget.marketSlug;
  String? get _pickTitle => _market?.title ?? widget.marketTitle;
  String? get _pickVenue => _market?.venue ?? widget.venue;
  String? get _pickOutcome =>
      _market != null ? _side?.label : widget.outcome;
  int? get _pickIndex => _market != null ? _side?.index : widget.outcomeIndex;
  String? get _pickSide => _market != null ? _side?.side : widget.side;
  bool get _investing => _pickVenue == 'hyperliquid';

  /// Whether the link carries a pick (a market's side picked).
  bool get _hasPick =>
      (_pickOutcome?.trim().isNotEmpty ?? false) &&
      (_pickTitle?.trim().isNotEmpty ?? false);

  /// A side picked on the side step: on to the amount.
  void _pickSideNow(SendPickSide side) {
    final market = _market;
    if (market == null) return;
    TrackingService.track('send_pick_side_picked', params: {
      'venue': market.venue,
      'side': side.side,
      'sides': market.sides.length,
    });
    setState(() {
      _market = market.choose(side);
      _step = _Step.amount;
    });
  }

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
      final pick = _hasPick;
      final challenge = _challenge && _canChallenge;
      final created = await ref.read(shareLinksApiProvider).create(
            kind: kind,
            amountMinor: amountMinor,
            marketSlug: _pickSlug,
            senderLabel: label.isEmpty ? null : label,
            venue: pick ? _pickVenue : null,
            outcome: pick ? _pickOutcome!.trim() : null,
            outcomeIndex: pick ? _pickIndex : null,
            side: pick ? _pickSide : null,
            challenge: challenge,
          );
      final row = PendingShareLink(
        id: created.id,
        kind: kind,
        amountMinor: amountMinor,
        label: label.isEmpty ? null : label,
        marketSlug: _pickSlug,
        marketTitle: pick ? _pickTitle!.trim() : null,
        venue: pick ? _pickVenue : null,
        outcome: pick ? _pickOutcome!.trim() : null,
        url: challenge ? shareChallengeUrl(created.url) : created.url,
        challenge: challenge,
        createdAt: DateTime.now(),
        status: ShareLinkStatus.open,
        recipientPhone: widget.recipientPhone?.trim().isEmpty ?? true
            ? null
            : widget.recipientPhone!.trim(),
      );
      ShareLinksStore.put(row);
      ShareLinkEvents.created(kind, amountMinor,
          marketSlug: _pickSlug,
          outcome: row.outcome,
          challenge: challenge);
      if (!mounted) return;
      // The card first (founder, 1 November 2026): Share is the bar.
      setState(() {
        _created = row;
        _step = _Step.done;
        _creating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = context.l10n.shareCreateFailed;
      });
    }
  }

  /// The card for [amountMinor] to [label]: the pick's card when the
  /// link carries one (the dare with [challenge]), else the money card
  /// (cards/share_card_sources.dart).
  ShareCardData _card(int amountMinor, String? label,
      {bool challenge = false}) {
    String? btc;
    String? fiat;
    if (!_dollars && amountMinor > 0) {
      try {
        btc = ref.watch(conversionProvider(amountMinor));
        fiat = ref.watch(conversionToFiatProvider(amountMinor));
      } catch (_) {
        btc = null;
        fiat = null;
      }
    }
    final pick = _hasPick;
    return shareCardForLink(
      <T>(p) => ref.watch(p),
      locale: context.l10n.localeName,
      kind: kind,
      amountMinor: amountMinor,
      recipient: label,
      marketSlug: pick ? _pickSlug : null,
      marketTitle: pick ? _pickTitle : null,
      venue: pick ? _pickVenue : null,
      outcome: pick ? _pickOutcome : null,
      side: pick ? _pickSide : null,
      bitcoinAmount: btc,
      bitcoinFiat: fiat,
      referralCode: AffiliateService.affiliateCode,
      challenge: pick && challenge,
    );
  }

  Future<void> _share(PendingShareLink row, ShareCardData card) async {
    if (_sharing) return;
    final amount =
        shareLinkAmountLabel(context, ref, row.kind, row.amountMinor);
    final text = shareCardMessage(
        context.l10n,
        card,
        shareLinkMessage(context,
            name: row.label,
            amount: amount,
            url: row.url,
            outcome: row.outcome,
            title: row.marketTitle,
            venue: row.venue,
            challenge: row.challenge));
    setState(() => _sharing = true);
    final result =
        await shareCardImage(context, _boundary, text: text, name: card.kind);
    ShareLinkEvents.shared(row.kind, result: result);
    if (mounted) setState(() => _sharing = false);
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
          // Each step says what it asks (see the file header): the side,
          // how much, who it is for.
          AppBottomSheetHeader(
            title: switch (_step) {
              _Step.name => l10n.shareWhoIsItFor,
              _Step.done => l10n.shareCardReadyTitle,
              // "a" while the side is picked here, "this" for a side
              // handed over (a position's).
              _ when widget.market?.needsSide ?? false =>
                _investing ? l10n.sendAnInvestment : l10n.sendAPrediction,
              _ when widget.hasPick =>
                _investing ? l10n.sendThisInvestment : l10n.sendThisPrediction,
              _ => l10n.shareSendToAnyone,
            },
            subtitle: switch (_step) {
              _Step.side => (_market?.isPair ?? true)
                  ? l10n.sendPickSideSub
                  : l10n.sendPickOutcomeSub,
              _Step.amount => widget.hasPick
                  ? l10n.sendPickAmountSub
                  : l10n.shareSendToAnyoneSubtitle,
              _ => null,
            },
            icon: Icons.ios_share_rounded,
          ),
          if (_step == _Step.side)
            // The outcomes of a big event can run long: they scroll.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                child: _sideStep(),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
              child: switch (_step) {
                _Step.side => const SizedBox.shrink(),
                _Step.amount => _amountStep(),
                _Step.name => _nameStep(),
                _Step.done => _doneStep(),
              },
            ),
        ],
      ),
    );
  }

  /// The side step: what is sent over every side it can send, none
  /// chosen (send_pick.dart). A tap is the choice.
  Widget _sideStep() {
    final market = _market;
    if (market == null) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('send-pick-side-step'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SendPickMarketHeader(market: market),
        SizedBox(height: 20.h),
        SendPickSideChooser(market: market, onPicked: _pickSideNow),
        // A long list of outcomes scrolls clear of the floating bar.
        if (!market.isPair) SizedBox(height: kuteBarScrollClearance.h),
      ],
    );
  }

  /// The pick over the amount: the market's picture (when the sheet has
  /// the market), "Yes on {market}" and the side's chance or the price
  /// under it, and "Change" back to the sides when there was a choice.
  Widget _pickSummary(AppColorsExtension c) {
    final l10n = context.l10n;
    final market = _market;
    final side = _side;
    final outcome = side != null
        ? sendPickSideLabel(l10n, side)
        : _pickOutcome!.trim();
    final String? under;
    if (side?.chance != null) {
      under = sendPickChanceLine(l10n, side!);
    } else if (market != null && market.investing) {
      under = market.price;
    } else {
      under = null;
    }
    final line = Text(
      sharePickLine(context, outcome: outcome, title: _pickTitle!.trim()),
      key: const ValueKey('share-pick-line'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: c.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        height: 1.3,
      ),
    );
    if (market == null) return line;
    final canChange = widget.market?.needsSide ?? false;
    return Row(
      key: const ValueKey('share-pick-summary'),
      children: [
        sendPickLogo(context, market),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line,
              if (under != null && under.isNotEmpty) ...[
                SizedBox(height: 2.h),
                Text(
                  under,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (canChange)
          SendChangeButton(
            key: const ValueKey('share-pick-change'),
            onTap: () => setState(() {
              _market = _market?.choose(null);
              _step = _Step.side;
            }),
          ),
      ],
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
        if (_hasPick) ...[
          // The pick, above the amount: "Yes on Gemini Carbon".
          _pickSummary(c),
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
        // THE BAR IS THE BUTTON (kute_bar_context.dart): Continue is the
        // floating Sal bar's primary action; the keypad keeps clear of it.
        KuteBarContextScope(
          barContext: KuteBarContext.primary(
            label: l10n.continueLabel,
            onPrimary: () => setState(() => _step = _Step.name),
            enabled: amountMinor > 0,
            source: 'share_amount',
            disabledLabel: l10n.barNeedAmount,
          ),
          child: SizedBox(height: kuteBarScrollClearance.h),
        ),
      ],
    );
  }

  Widget _nameStep() {
    final l10n = context.l10n;
    final label = _name.text.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The card, live as the name is typed (see the file header).
        ShareCardPreviewBox(
          key: const ValueKey('share-live-card'),
          data: _card(_amountMinor(), label.isEmpty ? null : label,
              challenge: _challenge && _canChallenge),
          boundaryKey: _liveBoundary,
          widthFraction: 0.6,
          heightFraction: 0.34,
          lineSeed: _seed,
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
          // The bar is Create link and hides under the keyboard: the
          // return key creates the link too.
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_creating) unawaited(_create());
          },
        ),
        // A prediction can go as a dare (share_challenge.dart).
        if (_canChallenge) ...[
          SizedBox(height: 8.h),
          ShareChallengeToggle(
            value: _challenge,
            onChanged: (v) => setState(() => _challenge = v),
          ),
        ],
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
        // Create link is the bar (kute_bar_context.dart), busy while the
        // link is posted. The bar hides under the keyboard, so the field's
        // return key creates the link too.
        KuteBarContextScope(
          barContext: KuteBarContext.primary(
            label: l10n.shareCreateLink,
            onPrimary: () => unawaited(_create()),
            enabled: !_creating,
            busy: _creating,
            busyLabel: l10n.shareCreatingLink,
            source: 'share_name',
            disabledLabel: null,
          ),
          child: SizedBox(height: kuteBarScrollClearance.h),
        ),
      ],
    );
  }

  Widget _doneStep() {
    final l10n = context.l10n;
    final c = context.colors;
    final row = _created;
    if (row == null) return const SizedBox.shrink();
    final card = _card(row.amountMinor, row.label, challenge: row.challenge);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The card is a button too: a tap shares it, as the bar does.
        Semantics(
          button: true,
          label: l10n.share,
          child: GestureDetector(
            key: const ValueKey('share-done-card-tap'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_share(row, card)),
            child: ShareCardPreviewBox(
              data: card,
              boundaryKey: _boundary,
              heightFraction: row.recipientPhone != null ? 0.34 : 0.42,
              lineSeed: _seed,
            ),
          ),
        ),
        SizedBox(height: 12.h),
        SendToListCard(
          colors: c,
          rows: [PendingShareLinkRow(row: row, onTap: () {})],
        ),
        SizedBox(height: 12.h),
        // The contact's number, kept on the phone, prefilled in WhatsApp
        // and the SMS composer (share_link_resend.dart).
        if (row.recipientPhone != null) ...[
          AppTextButton(
            key: const ValueKey('share-again-whatsapp'),
            text: l10n.shareSendAgainWhatsApp,
            onPressed: () => unawaited(resendShareLinkVia(
                context, ref, row, ShareLinkResendChannel.whatsapp)),
          ),
          AppTextButton(
            key: const ValueKey('share-again-sms'),
            text: l10n.shareSendAgainSms,
            onPressed: () => unawaited(resendShareLinkVia(
                context, ref, row, ShareLinkResendChannel.sms)),
          ),
        ],
        AppTextButton(
          key: const ValueKey('share-done'),
          text: l10n.done,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        // Share is the bar (kute_bar_context.dart): the card with the
        // link; Done sits above it.
        KuteBarContextScope(
          barContext: KuteBarContext.primary(
            label: l10n.share,
            onPrimary: () => unawaited(_share(row, card)),
            busy: _sharing,
            source: 'share_done',
            disabledLabel: null,
          ),
          child: SizedBox(height: kuteBarScrollClearance.h),
        ),
      ],
    );
  }
}
