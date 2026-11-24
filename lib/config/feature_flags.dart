// lib/config/feature_flags.dart
//
// LOCAL, COMPILE-TIME FEATURE FLAGS. Plain consts baked into the build:
// no backend, no remote config, no PostHog flags (PostHog is collection
// only).

import 'package:flutter/foundation.dart' show visibleForTesting;

/// THE SOCIAL SEND (founder, 24 November 2026: "for now with a local
/// feature flag disable: 1 - access to contacts, only allow to send normal
/// bitcoins. sending dont allow to send a prediction or investment").
///
/// Off (false), the app:
///
///   * never asks for or reads the phone's contacts: no permission prompt,
///     no "See your contacts" row, no contacts list or picker on Send
///     (services/contacts/send_contacts_service.dart answers without the
///     platform);
///   * sends to an address only: no claim link to a person (Send to
///     anyone, a contact or a typed phone number, the Dollars Send's "To a
///     friend" card), no What step and no gift of a prediction or an
///     investment (the search and the slips in send mode); each opener
///     refuses when reached anyway;
///   * ends the text of every prediction, win, P&L, position, level and
///     receipt share with one line inviting people to the app at
///     getkute.com ([withGetKuteLine], share_card_copy.dart).
///
/// True restores the behaviour before the flag exactly. The code reads it
/// through [socialSendEnabled], which tests can pin either way.
const bool kSocialSendEnabled = false;

/// Test seam: pins [socialSendEnabled] (null: [kSocialSendEnabled]).
@visibleForTesting
bool? debugSocialSendEnabled;

/// Whether the social send is on: [kSocialSendEnabled], unless a test
/// pinned it.
bool get socialSendEnabled => debugSocialSendEnabled ?? kSocialSendEnabled;
