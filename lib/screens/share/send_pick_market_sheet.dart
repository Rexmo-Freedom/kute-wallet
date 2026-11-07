// lib/screens/share/send_pick_market_sheet.dart
//
// SEND A PREDICTION OR AN INVESTMENT FROM SEND (founder, 31 October 2026:
// people must be able to send a pick from the Send screen, not only from
// a market page). The Dollars Send's "Send a prediction or investment"
// row (and the Bitcoin Send's, and the Withdraw sheet's) opens it.
//
// IT IS THE SEARCH SHEET, IN SEND MODE (founder, 7 November 2026: "too
// much text here, and this is still not the search one just adapted to
// sending, should be basically the same"). [showSendPickMarketSheet]
// opens the Sal bar's own search sheet (unified_search_screen.dart,
// showKuteSearch) with a [SendPickSession] (send_pick_session.dart): the
// same composer with Sal ("Search a market to send"), the same Recent,
// Moving now and Trending predictions with their gauges, the same
// results; only a small chip at the top says who it is for ("For Ana",
// "Sending to a friend"), the Connect your own AI card stays out, and the
// results are markets only. A venue where this person cannot place a
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
// went out. The Send screen hides its row when neither venue is open
// (sendPickOffered).
//
// `send_pick_market_opened {source: send}` once per open,
// `send_pick_market_picked {venue, searched}` per market opened.

import 'package:flutter/widgets.dart';

import 'package:kute/screens/search/unified_search_screen.dart'
    show showKuteSearch;
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show RuntimeCapabilitiesService;
import 'package:kute/services/tracking_service.dart';

/// Whether a prediction or an investment can be composed to send here:
/// either venue offered and open to this person (see the file header).
bool sendPickOffered(RuntimeCapabilitiesService policy) {
  final venues = sendPickVenues(policy);
  return venues.predictions || venues.investing;
}

/// Opens the search sheet in send mode over the send (see the file
/// header). [senderLabel] and [recipientPhone] are the contact picked
/// before the row, if any: the chip names them and Send to anyone opens
/// with them. Resolves to true when a link was created.
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
