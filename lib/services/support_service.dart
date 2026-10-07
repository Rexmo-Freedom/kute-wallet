// lib/services/support_service.dart
//
// Tiny reusable wrapper around the Crisp live-support chat. Extracted
// from `home.dart`'s inline `_openSupportChat` so the same "summon Sal"
// affordance can be triggered from anywhere (the Home mascot gesture,
// the unified search "Contact support" result, etc.) without each
// callsite re-reading dotenv and re-constructing the Crisp config.

import 'package:crisp_chat/crisp_chat.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Opens the live support chat (Crisp). Reads the website id from
/// `CRISP_ID` in dotenv and no-ops when it's missing/empty so a
/// misconfigured build never throws into the caller. Crisp init can
/// also throw if the id is malformed at build time — swallowed here for
/// the same reason: surfacing the error buys nothing, the user would
/// just tap again.
Future<void> openSupportChat() async {
  try {
    final websiteId = dotenv.env['CRISP_ID'];
    if (websiteId == null || websiteId.isEmpty) return;
    await FlutterCrispChat.openCrispChat(
      config: CrispConfig(websiteID: websiteId),
    );
  } catch (_) {
    // Crisp init can throw if the env id is misconfigured at build
    // time; surfacing the error to the user buys nothing — they'd
    // just tap again. Swallow and let the next tap retry.
  }
}
