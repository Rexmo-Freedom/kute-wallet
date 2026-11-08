// lib/screens/share/send_pick_session.dart
//
// SEND MODE (founder, 7 November 2026: "This share here should only be
// for sharing the market. Don't have the share on the slip, only in Send
// should it be to send to someone"; then "just get rid of the button to
// share the actual prediction on the buy, just keep it on the send"). A
// prediction or an investment is sent ONLY from Send: a person picked on
// either Send, then the What step's "A prediction or investment"
// (send_what_step.dart), opens the search sheet in send mode
// (send_pick_market_sheet.dart, unified_search_screen.dart), a result
// opens its market page in send mode, and that page's slip runs in send
// mode: its primary is the send itself ("Send $50 · Short AMD"), which
// opens Send to anyone's "Who is it for?" step with the pick and the
// amount (slip_share.dart). Nothing is ever placed from a slip in send
// mode.
//
// [SendPickSession] is that one send: who it is for (the contact picked
// on the Send screen, if any), where it started (analytics), and the
// search sheet's route, so a gift that went out closes the market pages,
// the slip and the sheet in one go and the Send screen closes as a send
// that went out ([SendPickSession.finish]). It travels as a parameter
// into the market pages and the slips (they are separate routes), and
// down the search sheet's own tree through [SendPickScope].
//
// THE SEARCH SHEET SAYS IT ONCE, BIG (founder, 8 November 2026, on the
// small chip it wore: "i still think for anna should be more clear and
// better"): the first steps' own heading (SheetTitleHeader), "Pick a gift
// for Ana", "Pick a gift" with no contact ([sendPickSheetTitle]), so the
// person arriving there sees what they are doing and for whom.
//
// Past it, [SendPickChip] carries that on, at the top of the market page
// and the slip: "For Ana", "Sending to a friend", with the gift glyph.
// Founder, 7 November 2026 ("the sending to a friend should be more
// clear"): the search sheet's scope chip shape in the app's primary ink
// (the primary button's own fill and contrast), so it reads as the state
// the page is in, not as one more grey control; its "For Ana" is the
// sender's ([sendPickChipForNamed]), never the card's "Ana, for you".
//
// A MARKET PAGE IN SEND MODE NEVER OFFERS THE LOOK-ONLY LINK (founder, 7
// November 2026: "the link to look at it should say you are buying this
// for your friend as an info"; "same here"). The page's bar says what is
// happening instead of "Send to a friend · They get a link to look at
// it":
//
//   * an event of several outcomes (a game's board too):
//     [sendPickInfoBar], the Sal pill reading "Pick an outcome · You're
//     buying it for Ana" ("... for your friend" with no contact); a tap
//     brings the outcomes into view, and nothing on it sends anything;
//   * one Yes / No market, or an Investing market: the trade row stays
//     the bar, in its green and red, each pill saying it sends
//     ([sendPickTradeLabel]: "Send Yes 18.5%", "Send Long", "Send
//     Short"), and the round Sal share button is away. Each pill opens the
//     slip in send mode, whose primary is the send (slip_share.dart).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService;
import 'package:kute/theme/app_theme.dart';

/// Send to anyone's entry source for a pick sent from a slip in send
/// mode (analytics; it was `bet_slip` / `order_slip` while the slips had
/// their own share button).
const String kSendModeSlipSource = 'send_mode_slip';

/// The market pages' `source` for a market opened from the search sheet
/// in send mode (analytics, as `search` is for the plain sheet).
const String kSendPickMarketSource = 'send_pick';

/// The venues the gift search lists: those whose BROWSE is open, the same
/// answer the plain search reads in that policy state. A refused trade
/// never takes a venue off this list (founder, 8 November 2026: "only on
/// the last screen, the bet slip, show this error"): the market's slip
/// says so and stops the send (slip_share.dart).
({bool predictions, bool investing}) sendPickVenues(
        RuntimeCapabilitiesService policy) =>
    (
      predictions: policy.allows('polymarket.browse'),
      investing: policy.allows('hyperliquid.browse'),
    );

/// One send of a prediction or an investment (see the file header).
class SendPickSession {
  SendPickSession({
    required this.entrySource,
    String? recipientName,
    String? recipientPhone,
  })  : recipientName = _clean(recipientName),
        recipientPhone = _clean(recipientPhone);

  /// Where the send started (`dollar_send`, `bitcoin_send`, …).
  final String entrySource;

  /// The first name of the contact picked on the Send screen; null:
  /// nobody yet (the "Who is it for?" step asks).
  final String? recipientName;

  /// That contact's number, kept in the local row only (never posted,
  /// never tracked).
  final String? recipientPhone;

  /// Whether the gift went out (a link was created).
  bool get sent => _sent;
  bool _sent = false;

  Route<dynamic>? _sheetRoute;

  /// Test seam: what a result tapped in the send-mode search opens (a
  /// PolymarketEvent or an HlMarket) instead of its page.
  @visibleForTesting
  static void Function(Object market)? debugOpenMarket;

  /// Hands [market] to [debugOpenMarket] when a test set it: true when it
  /// did (the page is then not opened).
  static bool debugOpened(Object market) {
    final open = debugOpenMarket;
    if (open == null) return false;
    open(market);
    return true;
  }

  static String? _clean(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// The search sheet's route, recorded as it builds.
  void attach(Route<dynamic>? route) {
    if (route != null) _sheetRoute = route;
  }

  /// The gift went out: closes everything stacked over the search sheet
  /// (the slip, the market pages) and the sheet itself, so the Send screen
  /// reads the send as done ([sent]).
  void finish(NavigatorState navigator) {
    _sent = true;
    final route = _sheetRoute;
    if (route == null || !route.isActive) return;
    navigator.popUntil((r) => r == route || r.isFirst);
    if (route.isCurrent) navigator.pop();
  }
}

/// The send-mode session for the search sheet's own tree (its rows open
/// their markets in send mode).
class SendPickScope extends InheritedWidget {
  const SendPickScope({super.key, required this.session, required super.child});

  final SendPickSession session;

  /// The session over [context]; null outside send mode. A sheet's
  /// session never changes, so this registers no dependency (it is read
  /// from taps too).
  static SendPickSession? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SendPickScope>()?.session;

  @override
  bool updateShouldNotify(SendPickScope old) => old.session != session;
}

/// The search sheet's big title in send mode (see the file header): "Pick
/// a gift for Ana" when a contact was picked, else "Pick a gift".
String sendPickSheetTitle(AppLocalizations l10n, SendPickSession session) {
  final name = session.recipientName;
  return name == null
      ? l10n.sendPickSheetTitle
      : l10n.sendPickSheetTitleNamed(name);
}

/// The small chip at the top of a market page and a slip in send mode:
/// "For Ana" when a contact was picked, else "Sending to a friend" (see
/// the file header).
/// The search sheet's scope chip shape (28 high, 13 sp), in the primary
/// button's ink: its fill, the words and the gift glyph in its contrast,
/// w600.
class SendPickChip extends StatelessWidget {
  const SendPickChip({super.key, required this.session});

  final SendPickSession session;

  /// The chip's words for [session].
  static String label(BuildContext context, SendPickSession session) {
    final name = session.recipientName;
    return name == null
        ? context.l10n.sendPickChipFriend
        : context.l10n.sendPickChipForNamed(name);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = label(context, session);
    final fill = c.textPrimary;
    final ink = contrastingOnColor(fill);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('send-pick-chip'),
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_giftcard_rounded,
                key: const ValueKey('send-pick-chip-gift'),
                size: 15,
                color: ink),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bar's words under "Pick an outcome" in send mode: who the pick is
/// bought for, by the contact's name when Send had one.
String sendPickBuyingFor(AppLocalizations l10n, SendPickSession session) {
  final name = session.recipientName;
  return name == null
      ? l10n.sendPickBarBuyingForFriend
      : l10n.sendPickBarBuyingFor(name);
}

/// A trade pill's words in send mode (see the file header): "Send Yes",
/// "Send Short"; [side] is the pill's own word.
String sendPickTradeLabel(AppLocalizations l10n, String side) =>
    l10n.sendPickTradeSide(side);

/// The bar of a market page in send mode with no Yes / No pair (see the
/// file header): "Pick an outcome · You're buying it for Ana". [onTap]
/// is all a tap does (the page brings its outcomes into view): never the
/// Sal sheet, never a link. The `share` clip keeps the market page's
/// movement (the pill folds while the page scrolls down).
KuteBarContext sendPickInfoBar(
  BuildContext context,
  SendPickSession session, {
  required VoidCallback onTap,
  required SearchCategory category,
  String? searchHint,
  required String source,
}) =>
    _SendPickInfoBar(
      label: context.l10n.sendPickBarPickOutcome,
      sublabel: sendPickBuyingFor(context.l10n, session),
      category: category,
      searchHint: searchHint,
      source: source,
      onTap: onTap,
    );

class _SendPickInfoBar extends KuteBarContext {
  const _SendPickInfoBar({
    required super.label,
    required super.sublabel,
    required super.category,
    required super.searchHint,
    required super.source,
    required this.onTap,
    super.route,
  }) : super(clip: 'share');

  final VoidCallback onTap;

  @override
  VoidCallback? get directAction => onTap;

  @override
  KuteBarContext boundTo(Route<dynamic>? route) => _SendPickInfoBar(
        label: label,
        sublabel: sublabel,
        category: category,
        searchHint: searchHint,
        source: source,
        onTap: onTap,
        route: route,
      );
}
