// lib/screens/share/send_pick_market_sheet.dart
//
// SEND A PREDICTION OR AN INVESTMENT FROM SEND (founder, 31 October 2026:
// people must be able to send a pick from the Send screen, not only from
// a market page). The Dollars Send's What step opens it: a person picked,
// then "A prediction or investment" (send_what_step.dart; founder, 7 November
// 2026: a gift is a What, never a chip; 8 November 2026: the Bitcoin Send just
// sends bitcoin).
//
// IT IS THE SEARCH SHEET, IN SEND MODE (founder, 7 November 2026: "too
// much text here, and this is still not the search one just adapted to
// sending, should be basically the same"). [showSendPickMarketSheet]
// opens the Sal bar's own search sheet (unified_search_screen.dart,
// showKuteSearch) with a [SendPickSession] (send_pick_session.dart): the
// same composer with Sal ("Search predictions and investments"), the same
// Recent, Moving now and Trending predictions with their gauges, the same
// results; only the heading says what it is for and for whom ("Pick a
// gift for Ana", "Pick a gift"), the Connect your own AI card stays out,
// and the results are markets only, of any venue whose browse is open
// (sendPickVenues), as the plain search lists them.
//
// A TAP OPENS THE MARKET IN SEND MODE, AND ITS SLIP SENDS (founder, 7
// November 2026: the slips have no share button any more, "only in Send
// should it be to send to someone"; screens/share/slip_share.dart). The
// person picks the side on the page as always (Yes | No, Invest | Short,
// an outcome's row: nothing chosen for them) and types the amount on the
// slip, whose primary is the send ("Send $50 · Short AMD"); it opens Send
// to anyone's "Who is it for?" with the pick, the contact picked on Send
// prefilled. A link created closes the slip, the pages and this sheet,
// and the future resolves to true: the Send screen closes as a send that
// went out.
//
// THE SLIP IS THE GATE, NOT THIS STEP (founder, 8 November 2026, over the
// Unavailable sheet on the What step's gift: "only on the last screen, the
// bet slip, show this error, not in this part, because someone can send
// investment"). A person may be refused on one venue, or one market, and
// not on another, so a refused trade never stops the gift here: the card
// shows and its tap opens the search whenever a venue's browse is open
// ([sendPickOffered]), and the slip of a refused market says why, with its
// own "Check connection", and sends nothing (slip_share.dart).
//
// ONLY NOTHING TO LIST STOPS IT. Neither venue's browse open: for a region,
// or no policy read yet, the card stays and its tap asks again, then shows
// the shared Unavailable sheet, "Check connection" going on into the search
// when it finds a browse open ([sendGiftStoppedByBrowse]); a refusal of
// another kind on both (a switch off, a platform or version rule, coming
// soon) takes the card away ([sendGiftShown]). It reads no holdings and no
// balance: only the policy, live. The Dollars coin step's row follows the
// same rule (usd_send_screen.dart).
//
// `send_pick_market_opened {source: send}` once per open,
// `send_pick_market_picked {venue, searched}` per market opened.

import 'package:flutter/widgets.dart';

import 'package:kute/screens/search/unified_search_screen.dart'
    show showKuteSearch;
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show showCapabilityDecisionSheet;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show CapabilityRegionBlock;
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService, confirmCapability;
import 'package:kute/services/tracking_service.dart';

/// Whether the gift search has anything to list: either venue's browse
/// open (see the file header). A refused trade does not change this.
bool sendPickOffered(RuntimeCapabilitiesService policy) {
  final venues = sendPickVenues(policy);
  return venues.predictions || venues.investing;
}

/// What stands in front of the gift when nothing can be listed and a region
/// or a policy not read yet is why (see the file header): the first such
/// browse refusal. Null while a browse is open, and while refusals of
/// another kind shut both.
CapabilityRegionBlock? sendGiftBrowseBlock(RuntimeCapabilitiesService policy) {
  if (sendPickOffered(policy)) return null;
  for (final id in const ['polymarket.browse', 'hyperliquid.browse']) {
    final decision = policy.decision(id);
    if (decision.allowed || decision.comingSoon) continue;
    if (decision.regionRestricted || decision.reason == 'policy_unavailable') {
      return (capability: id, decision: decision);
    }
  }
  return null;
}

/// Whether the What step shows the gift, and the coin step its row (see the
/// file header).
bool sendGiftShown(RuntimeCapabilitiesService policy) =>
    sendPickOffered(policy) || sendGiftBrowseBlock(policy) != null;

/// The tap on the gift: true when nothing can be listed, so the caller must
/// not open the search. False at once with a browse open, whatever the
/// trade gates say. With none open the refusal is asked again first (a
/// stale answer never shuts it), then the shared Unavailable sheet says why;
/// a "Check connection" that finds a browse open answers false and the gift
/// goes on.
Future<bool> sendGiftStoppedByBrowse(
    BuildContext context, RuntimeCapabilitiesService policy) async {
  final first = sendGiftBrowseBlock(policy);
  if (first == null) return !sendPickOffered(policy);
  await confirmCapability(policy, first.capability);
  if (!context.mounted) return true;
  if (sendPickOffered(policy)) return false;
  final standing = sendGiftBrowseBlock(policy);
  // Withheld meanwhile: the card leaves with the policy's change.
  if (standing == null) return true;
  final open = await showCapabilityDecisionSheet(context, standing.decision,
      capability: standing.capability, surface: 'send_what_gift');
  return !open || !sendPickOffered(policy);
}

/// Opens the search sheet in send mode over the send (see the file
/// header). [senderLabel] and [recipientPhone] are the contact picked
/// before the row, if any: the heading names them and Send to anyone
/// opens with them. Resolves to true when a link was created.
Future<bool?> showSendPickMarketSheet(
  BuildContext context, {
  required String entrySource,
  String? senderLabel,
  String? recipientPhone,
}) async {
  TrackingService.track('send_pick_market_opened', params: {'source': 'send'});
  final session = SendPickSession(
    entrySource: entrySource,
    recipientName: senderLabel,
    recipientPhone: recipientPhone,
  );
  await showKuteSearch(
    context,
    source: kSendPickMarketSource,
    sendPick: session,
  );
  return session.sent;
}
