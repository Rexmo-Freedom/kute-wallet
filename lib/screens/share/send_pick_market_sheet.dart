// lib/screens/share/send_pick_market_sheet.dart
//
// SEND A PREDICTION OR AN INVESTMENT FROM SEND (founder, 31 October 2026:
// people must be able to send a pick from the Send screen, not only from
// a market page). Both Sends' What step opens it: a person picked, then
// "A prediction or investment" (send_what_step.dart; founder, 7 November
// 2026: a gift is a What, never a chip).
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
// and the results are markets only. A venue where this person cannot place a
// prediction (an investment) is left out (sendPickVenues): its slip could
// only send the market's card.
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
// THE WHAT STEP'S GIFT IS ALWAYS THERE, ITS TAP SAYS WHY (founder, 8
// November 2026, over the lone Bitcoin card: "we need to have it as an
// option always"). It reads no holdings and no balance: only the policy,
// live, the region rule of the coin pickers (founder decision, 27 October
// 2026; coin_asset_grid.dart): neither venue open for a region
// ([sendPickRegionBlock]) or no policy read yet keeps the card, and its tap
// asks again and then shows the shared Unavailable sheet, "Check connection"
// going on into the search when it finds a venue open
// ([sendGiftStoppedByPolicy]). Only a refusal that is no region's on both
// venues (a switch off, a platform or version rule, coming soon) takes the
// card away ([sendGiftShown]).
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

/// Whether a prediction or an investment can be composed to send here:
/// either venue offered and open to this person (see the file header).
bool sendPickOffered(RuntimeCapabilitiesService policy) {
  final venues = sendPickVenues(policy);
  return venues.predictions || venues.investing;
}

/// The gates of each venue a pick can be sent from ([sendPickVenues]).
const _kSendPickVenueGates = [
  ['polymarket.browse', 'polymarket.trade'],
  ['hyperliquid.browse', 'hyperliquid.trade'],
];

/// What stands in front of the gift while it cannot be composed and a
/// region or a policy not read yet is why (see the file header): the first
/// refusal, of a venue with no other kind of refusal. Null while a venue is
/// open, and while a refusal of another kind shuts both venues.
CapabilityRegionBlock? sendPickRegionBlock(RuntimeCapabilitiesService policy) {
  if (sendPickOffered(policy)) return null;
  for (final gates in _kSendPickVenueGates) {
    CapabilityRegionBlock? first;
    var kept = true;
    for (final id in gates) {
      final decision = policy.decision(id);
      if (decision.allowed && !decision.comingSoon) continue;
      if (decision.comingSoon ||
          !(decision.regionRestricted ||
              decision.reason == 'policy_unavailable')) {
        kept = false;
        break;
      }
      first ??= (capability: id, decision: decision);
    }
    if (kept && first != null) return first;
  }
  return null;
}

/// Whether the What step shows the gift (see the file header).
bool sendGiftShown(RuntimeCapabilitiesService policy) =>
    sendPickOffered(policy) || sendPickRegionBlock(policy) != null;

/// The tap on the What step's gift: true when the policy stands in front of
/// it, so the caller must not open the search. As a coin's tap
/// (coinPickStoppedByRegion, coin_asset_grid.dart): the refusal is asked
/// again first (a stale answer never shuts it), then the shared Unavailable
/// sheet says why; a "Check connection" that finds a venue open answers
/// false and the gift goes on.
Future<bool> sendGiftStoppedByPolicy(
    BuildContext context, RuntimeCapabilitiesService policy) async {
  final first = sendPickRegionBlock(policy);
  if (first == null) return !sendPickOffered(policy);
  await confirmCapability(policy, first.capability);
  if (!context.mounted) return true;
  if (sendPickOffered(policy)) return false;
  final standing = sendPickRegionBlock(policy);
  // Withheld meanwhile: the card leaves with the policy's change.
  if (standing == null) return true;
  final open = await showCapabilityDecisionSheet(context, standing.decision,
      capability: standing.capability, surface: kSendWhatGiftSurface);
  return !open || !sendPickOffered(policy);
}

/// The Unavailable sheet's `surface` when the What step's gift is refused.
const String kSendWhatGiftSurface = 'send_what_gift';

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
