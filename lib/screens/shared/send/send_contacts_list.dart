// lib/screens/shared/send/send_contacts_list.dart
//
// CONTACTS LIKE REVOLUT (founder, 1 November 2026), on the Bitcoin send
// and the Dollars send alike: no separate "Send to a friend" row. Under
// the search field, ONE "Contacts" list merging
//
//   1. the recent recipients (the flow's own: Lightning and Spark
//      addresses on Bitcoin, coin addresses on Dollars), newest first;
//   2. the phone's contacts (services/contacts/send_contacts_service.dart),
//      alphabetical, once the permission is granted. Until then the ask
//      row ("See your contacts") leads the list; tapping it prompts (or,
//      refused for good, opens Settings).
//
// THE LOOK (founder, 1 November 2026: "these contacts must look better,
// this page does not look fintech at all"):
//
//   * "Frequent" on top: a horizontal row of big avatar circles (56, the
//     name under in 12 sp, at most 8): the recent recipients, newest
//     first, a contact standing in for its own address (its name and
//     photo). Hidden while typing and while a recipient is chosen.
//     FREQUENT STAYS ON TOP (founder, 2 November 2026): on both Sends it
//     sits directly under the search field, ABOVE the "Send to" card;
//     the flows place [SendFrequentSection] there and mount
//     [SendContactsSection] with `showFrequent: false` under the card.
//   * "All contacts": an A–Z list with sticky letter headers (12 sp,
//     textSecondary), each letter's rows in the soft card, 60 tall: the
//     avatar at 44 (the photo, else the initials in one of six muted
//     chart tints derived from the name, [sendAvatarTint]), the name
//     16 w500, the address or number 13 textSecondary, no chevrons, the
//     hairlines inset to the text. What is typed filters it.
//
// Every avatar wears a BADGE on its corner ([SendPersonBadge]): Sal's face
// when the recipient is a Kute user (founder: "Kute is actually my Sal";
// a `@paykute.com` Lightning address, from a recent or a contact's
// email), ⚡ when it is any other Lightning address (or an LNURL); none
// for a plain phone contact or a coin address.
//
// [SendContactsSection] is a SLIVER: the flows put it in their one
// CustomScrollView under the field and the cards, so the list flows under
// the floating bar with the bar's clearance at the scroll's end (the
// Dollars Send reference), never in a clipped box of its own.
//
// A tap hands the entry to the flow ([SendContactsSection.onPerson]): an
// entry with an address is paid directly (as a recent always was); a
// plain contact starts the claim link (Send to anyone with the first name
// and the number kept in the local row). What is typed in the field
// filters the list by name, number or address, and a typed phone number
// no contact has offers "Send a link to +351…" ([onPhoneLink]).
//
// THE FIELD KEEPS EVERYTHING IT DOES (founder): this list is added UNDER
// it and never stands in for address entry.
//
// ONE RECIPIENT CARD (founder, 1 November 2026: the resolved state "must
// be more fintech", Revolut-style). Once the field resolves to a
// destination the flows show [SendRecipientCard], "Sending to": the
// person's avatar with its badge (the rail's mark when nobody known), the
// name (the contact's, else the recent's label, else the shortened
// address, [sendRecipientName]), the full address under it and the rail
// as a chip; "Change" clears it. The person is never listed twice: the
// list below drops them ([SendContactsSection.excludeAddress]) and, with
// anyone left, reads "Other contacts".
//
// Until the contacts are granted, "All contacts" holds the ask row (and,
// while typing, the matching recents). Everything is local: numbers never
// leave the phone.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart';
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The badge on an entry's avatar.
enum SendPersonBadge { none, kute, lightning }

/// The badge rule (see the file header): Kute for a `@paykute.com`
/// Lightning address (or [kuteRecipient]), ⚡ for any other Lightning
/// address or LNURL, none otherwise.
SendPersonBadge sendBadgeFor(String? address, {bool kuteRecipient = false}) {
  if (kuteRecipient || isKuteLightningAddress(address)) {
    return SendPersonBadge.kute;
  }
  final a = address?.trim().toLowerCase() ?? '';
  if (a.isEmpty) return SendPersonBadge.none;
  final lnAddress = RegExp(r'^[a-z0-9._+\-]+@[a-z0-9\-]+(\.[a-z0-9\-]+)+$');
  if (lnAddress.hasMatch(a) ||
      a.startsWith('lnurl') ||
      a.startsWith('lightning:')) {
    return SendPersonBadge.lightning;
  }
  return SendPersonBadge.none;
}

/// The phone number [query] spells, when it is one (digits with the
/// usual separators, at least 6 digits); null for anything else.
String? sendTypedPhone(String query) {
  final q = query.trim();
  if (!RegExp(r'^\+?[\d\s()\-.]+$').hasMatch(q)) return null;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 6 || digits.length > 15) return null;
  return q.startsWith('+') ? '+$digits' : digits;
}

/// One entry of the Contacts list.
@immutable
class SendPerson {
  const SendPerson({
    required this.id,
    required this.name,
    this.secondary,
    this.initials = '',
    this.photo,
    this.mark,
    this.icon,
    this.badge = SendPersonBadge.none,
    this.address,
    this.contact,
  });

  /// A recent recipient (paid directly).
  factory SendPerson.recent({
    required String address,
    required String name,
    String? secondary,
    Widget? mark,
    IconData? icon,
    bool kuteRecipient = false,
  }) =>
      SendPerson(
        id: 'recent:${address.toLowerCase()}',
        name: name,
        secondary: secondary,
        initials: mark == null && icon == null ? sendContactInitials(name) : '',
        mark: mark,
        icon: icon,
        badge: sendBadgeFor(address, kuteRecipient: kuteRecipient),
        address: address,
      );

  /// A phone contact: paid directly at its Kute address when it has one,
  /// else a claim link to its number.
  factory SendPerson.contact(SendContact contact) => SendPerson(
        id: 'contact:${contact.id}',
        name: contact.displayName,
        secondary: contact.lightningAddress ?? contact.phone,
        initials: contact.initials,
        photo: contact.photo,
        badge: sendBadgeFor(contact.lightningAddress),
        address: contact.lightningAddress,
        contact: contact,
      );

  final String id;
  final String name;
  final String? secondary;
  final String initials;
  final Uint8List? photo;

  /// A coin mark in the circle (a dollar recent's coin on its network).
  final Widget? mark;

  /// An icon in the circle (an address with no name).
  final IconData? icon;
  final SendPersonBadge badge;

  /// The destination a tap pays directly; null for a plain contact.
  final String? address;

  /// The phone contact behind the entry, if any.
  final SendContact? contact;

  /// Paid directly (an address), rather than by a claim link.
  bool get direct => address != null && address!.isNotEmpty;

  /// Whether [query] matches the name, the number or the address.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (address?.toLowerCase().contains(q) ?? false) return true;
    if (secondary?.toLowerCase().contains(q) ?? false) return true;
    return contact?.matches(query) ?? false;
  }
}

/// Recents first (newest first), then the contacts not already listed as
/// a recent (by their Kute address), alphabetical.
List<SendPerson> sendPeople({
  required List<SendPerson> recents,
  required List<SendContact> contacts,
}) {
  final listed = {
    for (final r in recents)
      if (r.address != null) r.address!.toLowerCase()
  };
  return [
    ...recents,
    for (final c in contacts)
      if (!listed.contains(c.lightningAddress?.toLowerCase()))
        SendPerson.contact(c),
  ];
}

/// An address as the recipient match compares it: trimmed, lowercased,
/// without a `lightning:` scheme.
String sendAddressKey(String? address) {
  var a = address?.trim().toLowerCase() ?? '';
  if (a.startsWith('lightning:')) a = a.substring('lightning:'.length);
  return a;
}

/// Who a resolved destination belongs to: a phone contact with that
/// address first (its name and photo), else a recent recipient; null when
/// nobody known has it.
SendPerson? sendMatchingPerson(
  String address, {
  required List<SendPerson> recents,
  required List<SendContact> contacts,
}) {
  final key = sendAddressKey(address);
  if (key.isEmpty) return null;
  for (final ct in contacts) {
    if (sendAddressKey(ct.lightningAddress) == key) {
      return SendPerson.contact(ct);
    }
  }
  for (final r in recents) {
    if (sendAddressKey(r.address) == key) return r;
  }
  return null;
}

/// The recipient card's name: the contact's, else the recent's label,
/// else the shortened address.
String sendRecipientName(SendPerson? match, String address) {
  final name = match?.name.trim() ?? '';
  return name.isNotEmpty ? name : sendShortAddress(address.trim());
}

/// The most entries the Frequent row shows.
const int kSendFrequentMax = 8;

/// The Frequent row (see the file header): the recents, newest first,
/// each standing as the contact that has its address when there is one,
/// at most [kSendFrequentMax].
List<SendPerson> sendFrequent({
  required List<SendPerson> recents,
  required List<SendContact> contacts,
}) {
  final byAddress = {
    for (final ct in contacts)
      if (sendAddressKey(ct.lightningAddress).isNotEmpty)
        sendAddressKey(ct.lightningAddress): ct
  };
  final out = <SendPerson>[];
  final seen = <String>{};
  for (final r in recents) {
    final key = sendAddressKey(r.address);
    if (key.isEmpty || !seen.add(key)) continue;
    final ct = byAddress[key];
    out.add(ct != null ? SendPerson.contact(ct) : r);
    if (out.length == kSendFrequentMax) break;
  }
  return out;
}

/// The Frequent row as a step shows it: nothing while typing ([query])
/// or once a recipient is chosen ([excludeAddress]), else [sendFrequent].
List<SendPerson> sendFrequentShown({
  required String query,
  String? excludeAddress,
  required List<SendPerson> recents,
  required List<SendContact> contacts,
}) {
  if (sendAddressKey(excludeAddress).isNotEmpty || query.trim().isNotEmpty) {
    return const <SendPerson>[];
  }
  return sendFrequent(recents: recents, contacts: contacts);
}

/// The letter an entry files under in the A–Z list: its name's first
/// letter, upper case (accents folded for the Latin letters), else "#".
String sendIndexLetter(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  var ch = t.substring(0, 1).toUpperCase();
  const folds = {
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'Å': 'A',
    'Ç': 'C', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'Ñ': 'N',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', 'Ø': 'O',
    'Š': 'S', 'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ý': 'Y', 'Ž': 'Z',
  };
  ch = folds[ch] ?? ch;
  return RegExp(r'^[A-Z]$').hasMatch(ch) ? ch : '#';
}

/// [people] filed A–Z by [sendIndexLetter], each letter's entries by
/// name, "#" last.
List<(String, List<SendPerson>)> sendAlphabetical(List<SendPerson> people) {
  final groups = <String, List<SendPerson>>{};
  for (final p in people) {
    groups.putIfAbsent(sendIndexLetter(p.name), () => []).add(p);
  }
  final letters = groups.keys.toList()
    ..sort((a, b) {
      if (a == '#') return b == '#' ? 0 : 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });
  return [
    for (final l in letters)
      (
        l,
        groups[l]!
          ..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ),
  ];
}

/// The muted tint an initials avatar wears for [name]: one of the chart
/// palette's six, picked by a hash of the name that never changes from
/// one run to the next (String.hashCode may).
int sendAvatarTintIndex(String name, {int tints = 6}) {
  var h = 0;
  for (final u in name.trim().toLowerCase().codeUnits) {
    h = (h * 31 + u) & 0x3fffffff;
  }
  return h % tints;
}

/// The tint itself, from [c]'s chart palette.
Color sendAvatarTint(AppColorsExtension c, String name) {
  final palette = c.chartCategorical;
  final n = palette.length < 6 ? palette.length : 6;
  return palette[sendAvatarTintIndex(name, tints: n)];
}

/// The Contacts under a send's search field, as SLIVERS for the flow's
/// one CustomScrollView (see the file header).
class SendContactsSection extends ConsumerWidget {
  const SendContactsSection({
    super.key,
    required this.query,
    required this.recents,
    required this.onPerson,
    required this.onPhoneLink,
    this.excludeAddress,
    this.background,
    this.showFrequent = true,
  });

  /// What the field holds (filters the list).
  final String query;
  final List<SendPerson> recents;
  final ValueChanged<SendPerson> onPerson;

  /// Whether Frequent leads this section. The Sends pass false: their
  /// Frequent sits above the Send to card ([SendFrequentSection]).
  final bool showFrequent;

  /// A typed number no contact has: the claim link to it.
  final ValueChanged<String> onPhoneLink;

  /// The chosen recipient's address, while the field holds a resolved
  /// destination: that person is left out (the recipient card shows
  /// them), the field no longer filters (it holds an address, not a
  /// search), Frequent hides and the list reads "Other contacts".
  final String? excludeAddress;

  /// What the sticky letter headers are painted with: the sheet's own
  /// colour, so rows scroll under them cleanly. Defaults to the page
  /// background.
  final Color? background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final state = ref.watch(sendContactsProvider);
    final contacts = state.granted ? state.contacts : const <SendContact>[];
    final chosenKey = sendAddressKey(excludeAddress);
    final chosen = chosenKey.isNotEmpty;
    // A recipient is chosen: the field holds its address, not a search.
    final query = chosen ? '' : this.query.trim();
    final typing = query.isNotEmpty;
    bool kept(SendPerson p) =>
        !chosen ||
        (sendAddressKey(p.address) != chosenKey &&
            sendAddressKey(p.contact?.lightningAddress) != chosenKey);

    final phone = chosen ? null : sendTypedPhone(query);
    final phoneDigits = phone?.replaceAll(RegExp(r'\D'), '');
    final phoneKnown = phoneDigits != null &&
        contacts.any((ct) {
          final d = ct.phone.replaceAll(RegExp(r'\D'), '');
          return d.endsWith(phoneDigits) || phoneDigits.endsWith(d);
        });
    final Widget? phoneRow = phone != null && !phoneKnown
        ? SendToListRow(
            key: const ValueKey('send-phone-link-row'),
            colors: c,
            leading: const SendSalShareGlyph(),
            title: l10n.sendLinkToPhone(phone),
            subtitle: l10n.sendToAFriendSub,
            onTap: () => onPhoneLink(phone),
          )
        : null;
    final Widget? askRow = state.granted || chosen || typing
        ? null
        : SendToListRow(
            key: const ValueKey('send-contacts-ask-row'),
            colors: c,
            leading:
                Icon(Icons.contacts_rounded, color: c.textPrimary, size: 24.sp),
            title: state.permission == SendContactsPermission.blocked
                ? l10n.sendAllowContactsInSettings
                : l10n.sendContactsSeeYours,
            subtitle: state.permission == SendContactsPermission.blocked
                ? l10n.sendAllowContactsInSettingsSub
                : l10n.sendContactsSeeYoursSub,
            onTap: () {
              final notifier = ref.read(sendContactsProvider.notifier);
              unawaited(state.permission == SendContactsPermission.blocked
                  ? notifier.openSettings()
                  : notifier.request());
            },
          );

    final frequent = showFrequent
        ? sendFrequentShown(
            query: query,
            excludeAddress: excludeAddress,
            recents: recents,
            contacts: contacts)
        : const <SendPerson>[];
    // The A–Z list: everyone (recents and contacts, once each) with a
    // book; without one, only while typing (the recents already sit in
    // Frequent) or as the others beside a chosen recipient.
    final listed = contacts.isNotEmpty || typing || chosen
        ? [
            for (final p in sendPeople(recents: recents, contacts: contacts))
              if (p.matches(query) && kept(p)) p
          ]
        : const <SendPerson>[];
    final groups = sendAlphabetical(listed);

    if (frequent.isEmpty &&
        groups.isEmpty &&
        phoneRow == null &&
        askRow == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final headerColor = background ?? c.background;
    return SliverMainAxisGroup(
      key: const ValueKey('send-contacts-section'),
      slivers: [
        if (frequent.isNotEmpty)
          SliverToBoxAdapter(
            child: _SendFrequentBlock(people: frequent, onPerson: onPerson),
          ),
        if (phoneRow != null || askRow != null || groups.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 20.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SendSectionLabel(
                      chosen ? l10n.sendOtherContacts : l10n.sendAllContacts),
                  if (phoneRow != null || askRow != null)
                    SendToListCard(colors: c, rows: [
                      if (phoneRow != null) phoneRow,
                      if (askRow != null) askRow,
                    ]),
                ],
              ),
            ),
          ),
        if (groups.isNotEmpty)
          SliverMainAxisGroup(
            key: const ValueKey('send-contacts-list'),
            slivers: [
              for (final (letter, people) in groups)
                SliverMainAxisGroup(slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _SendLetterHeader(
                        letter: letter, color: headerColor, ink: c.textSecondary),
                  ),
                  SliverToBoxAdapter(
                    child: _SendContactCard(
                      people: people,
                      onPerson: onPerson,
                    ),
                  ),
                ]),
            ],
          ),
      ],
    );
  }
}

/// Frequent on its own (FREQUENT STAYS ON TOP, see the file header): a
/// box for the Sends' column, directly under the search field and above
/// the Send to card, with the same hide rules as [SendContactsSection]
/// (nothing while typing or once a recipient is chosen). Its own 20 h
/// gap on top; nothing at all when there are no recents.
class SendFrequentSection extends ConsumerWidget {
  const SendFrequentSection({
    super.key,
    required this.query,
    required this.recents,
    required this.onPerson,
    this.excludeAddress,
  });

  /// What the field holds (any text hides the row).
  final String query;
  final List<SendPerson> recents;
  final ValueChanged<SendPerson> onPerson;

  /// The chosen recipient's address: the row hides.
  final String? excludeAddress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendContactsProvider);
    final frequent = sendFrequentShown(
      query: query,
      excludeAddress: excludeAddress,
      recents: recents,
      contacts: state.granted ? state.contacts : const <SendContact>[],
    );
    if (frequent.isEmpty) return const SizedBox.shrink();
    return _SendFrequentBlock(
      key: const ValueKey('send-frequent-section'),
      people: frequent,
      onPerson: onPerson,
    );
  }
}

/// The "Frequent" label over the row of circles, 20 h above it.
class _SendFrequentBlock extends StatelessWidget {
  const _SendFrequentBlock(
      {super.key, required this.people, required this.onPerson});

  final List<SendPerson> people;
  final ValueChanged<SendPerson> onPerson;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SendSectionLabel(context.l10n.sendFrequent),
            SendFrequentRow(people: people, onPerson: onPerson),
          ],
        ),
      );
}

/// The height of a sticky letter header (design units).
const double kSendLetterHeaderHeight = 30;

/// A letter's sticky header: the letter in 12 sp textSecondary, on the
/// sheet's own colour so rows pass under it cleanly.
class _SendLetterHeader extends SliverPersistentHeaderDelegate {
  _SendLetterHeader(
      {required this.letter, required this.color, required this.ink});

  final String letter;
  final Color color;
  final Color ink;

  // Whole pixels: a fractional extent trips the pinned header's
  // layout-versus-paint check once the group sums its children.
  double get _h => kSendLetterHeaderHeight.h.roundToDouble();

  @override
  double get minExtent => _h;

  @override
  double get maxExtent => _h;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        key: ValueKey('send-letter-$letter'),
        color: color,
        alignment: Alignment.bottomLeft,
        padding: EdgeInsets.only(left: 4.w, bottom: 6.h),
        child: Text(
          letter,
          style: TextStyle(
            color: ink,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      );

  @override
  bool shouldRebuild(_SendLetterHeader old) =>
      old.letter != letter || old.color != color || old.ink != ink;
}

/// One letter's rows in the soft card, hairlines inset to the text.
class _SendContactCard extends StatelessWidget {
  const _SendContactCard({required this.people, required this.onPerson});

  final List<SendPerson> people;
  final ValueChanged<SendPerson> onPerson;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < people.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: c.borderSubtle,
                indent: (kSendContactRowInset + 44 + 12).w,
              ),
            SendContactRow(
              key: ValueKey('send-person-${people[i].id}'),
              person: people[i],
              onTap: () => onPerson(people[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// A row's side inset inside its card.
const double kSendContactRowInset = 14;

/// One A–Z row (see the file header): 60 tall, the avatar at 44, the name
/// 16 w500 over the address or number 13 textSecondary, no chevron.
class SendContactRow extends StatelessWidget {
  const SendContactRow({super.key, required this.person, required this.onTap});

  final SendPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary = person.secondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 60.h),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: kSendContactRowInset.w, vertical: 8.h),
            child: Row(
              children: [
                SendPersonAvatar(person: person, size: 44),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (secondary != null && secondary.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Frequent": big avatar circles (56) in one horizontal row, the name
/// under each in 12 sp; a tap pays as the list does.
class SendFrequentRow extends StatelessWidget {
  const SendFrequentRow(
      {super.key, required this.people, required this.onPerson});

  final List<SendPerson> people;
  final ValueChanged<SendPerson> onPerson;

  static const double avatar = 56;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // As tall as a circle and one name line at the reader's text size.
    final nameLine = MediaQuery.textScalerOf(context).scale(12.sp) * 1.4;
    return SizedBox(
      key: const ValueKey('send-frequent-row'),
      height: avatar.sp + 8.h + nameLine + 4,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        itemCount: people.length,
        separatorBuilder: (_, __) => SizedBox(width: 12.w),
        itemBuilder: (context, i) {
          final p = people[i];
          return Semantics(
            button: true,
            label: p.name,
            excludeSemantics: true,
            child: GestureDetector(
              key: ValueKey('send-frequent-${p.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPerson(p),
              child: SizedBox(
                width: avatar.sp + 10.w,
                child: Column(
                  children: [
                    SendPersonAvatar(person: p, size: avatar),
                    SizedBox(height: 8.h),
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// An entry's avatar (40 by default) with its badge on the lower right
/// corner: the photo, a coin mark, or the initials on their name's tint.
class SendPersonAvatar extends StatelessWidget {
  const SendPersonAvatar({super.key, required this.person, this.size = 40});

  final SendPerson person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = size.sp;
    final Widget inner;
    if (person.photo != null) {
      inner = ClipOval(
        child: Image.memory(person.photo!,
            width: d, height: d, fit: BoxFit.cover, gaplessPlayback: true),
      );
    } else if (person.mark != null) {
      inner = Center(child: person.mark);
    } else if (person.initials.isNotEmpty) {
      inner = Center(
        child: Text(
          person.initials,
          style: TextStyle(
            color: sendAvatarTint(c, person.name),
            fontSize: (size * 0.36).sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      );
    } else {
      inner = Icon(person.icon ?? Icons.person_rounded,
          color: c.textPrimary, size: (size * 0.5).sp);
    }
    final tinted = person.photo == null &&
        person.mark == null &&
        person.initials.isNotEmpty;
    final badge = d * 0.42;
    return SizedBox.square(
      dimension: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            key: const ValueKey('send-avatar-circle'),
            width: d,
            height: d,
            decoration: tinted
                // Initials on a soft colour derived from the name.
                ? BoxDecoration(
                    color: sendAvatarTint(c, person.name)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  )
                : BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.borderSubtle, width: 0.5),
                  ),
            child: inner,
          ),
          if (person.badge != SendPersonBadge.none)
            Positioned(
              right: -badge * 0.18,
              bottom: -badge * 0.18,
              child: SendPersonBadgeDot(badge: person.badge, size: badge),
            ),
        ],
      ),
    );
  }
}

/// The badge itself: Sal's face for a Kute user (founder: "Kute is
/// actually my Sal"; the idle clip's first frame, still) or ⚡ (a bolt on
/// amber), in a small white-ringed circle.
class SendPersonBadgeDot extends StatelessWidget {
  const SendPersonBadgeDot(
      {super.key, required this.badge, required this.size});

  final SendPersonBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kute = badge == SendPersonBadge.kute;
    return Semantics(
      label:
          kute ? context.l10n.sendBadgeKute : context.l10n.sendBadgeLightning,
      child: Container(
        key: ValueKey(kute ? 'send-badge-kute' : 'send-badge-lightning'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kute ? Colors.white : const Color(0xFFFFB300),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: kute
            ? ClipOval(child: SendSalFaceStill(size: size - 3))
            : Icon(Icons.bolt_rounded, color: Colors.white, size: size * 0.78),
      ),
    );
  }
}

/// Sal's face, still: the first frame of the `idle` sprite sheet (its
/// framing is the face), cropped from the sheet without the sprite
/// player, so a badge never animates or waits on the clip cache.
class SendSalFaceStill extends StatelessWidget {
  const SendSalFaceStill({super.key, required this.size});

  final double size;

  /// The sheet: 8 columns by 6 rows of the idle clip.
  static const String asset = 'lib/assets/sal/idle@2x.webp';
  static const int columns = 8;
  static const int rows = 6;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return SizedBox.square(
      key: const ValueKey('send-sal-face'),
      dimension: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: size * columns,
          maxWidth: size * columns,
          minHeight: size * rows,
          maxHeight: size * rows,
          child: Image.asset(
            asset,
            width: size * columns,
            height: size * rows,
            fit: BoxFit.fill,
            cacheWidth: (size * columns * dpr).ceil(),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// "Sending to": the one recipient card a resolved destination shows (see
/// the file header). [railMark] stands in for the avatar when nobody known
/// has the address; [rail] reads on the chip ("Lightning", "Bitcoin ·
/// on-chain"); [onChange] clears the field. [onTap] is the bar's Continue.
class SendRecipientCard extends ConsumerWidget {
  const SendRecipientCard({
    super.key,
    required this.address,
    required this.rail,
    required this.railMark,
    required this.recents,
    required this.onChange,
    this.onTap,
  });

  final String address;
  final String rail;
  final Widget railMark;
  final List<SendPerson> recents;
  final VoidCallback onChange;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final state = ref.watch(sendContactsProvider);
    final contacts = state.granted ? state.contacts : const <SendContact>[];
    final match =
        sendMatchingPerson(address, recents: recents, contacts: contacts);
    final name = sendRecipientName(match, address);
    // The person's own avatar when it has a face (a photo, initials, a
    // coin mark); otherwise the rail's mark, with the badge either way.
    final hasFace = match != null &&
        (match.photo != null || match.initials.isNotEmpty || match.mark != null);
    final avatar = hasFace
        ? match
        : SendPerson(
            id: 'recipient',
            name: name,
            mark: railMark,
            badge: match?.badge ?? sendBadgeFor(address),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SendSectionLabel(
          l10n.sendRecipientSendingTo,
          trailing: SendChangeButton(
            key: const ValueKey('send-recipient-change'),
            onTap: onChange,
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16.r),
            onTap: onTap,
            child: Container(
              key: const ValueKey('send-recipient-card'),
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Row(
                children: [
                  SendPersonAvatar(person: avatar, size: 44),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          key: const ValueKey('send-recipient-name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        SendMiddleEllipsisText(
                          address.trim(),
                          key: const ValueKey('send-recipient-address'),
                          maxLines: 2,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 120.w),
                    child: Container(
                      key: const ValueKey('send-recipient-rail'),
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: c.textPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        rail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [text] whole when it fits [maxLines] at the width; otherwise its head
/// and tail around an ellipsis ("bc1qar0s…f5mdq"), never cut at the end:
/// an address is checked by both its ends.
class SendMiddleEllipsisText extends StatelessWidget {
  const SendMiddleEllipsisText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines = 2,
  });

  final String text;
  final TextStyle style;
  final int maxLines;

  /// The longest middle-ellipsised form of [text] that fits [maxLines] at
  /// [maxWidth] (the text itself when it fits).
  static String fit(
    String text, {
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
    required TextScaler textScaler,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    bool fits(String t) {
      final p = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final over = p.didExceedMaxLines;
      p.dispose();
      return !over;
    }

    if (fits(text)) return text;
    String cut(int keep) {
      final head = (keep + 1) ~/ 2;
      final tail = keep ~/ 2;
      return '${text.substring(0, head)}\u2026'
          '${text.substring(text.length - tail)}';
    }

    var lo = 0;
    var hi = text.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (fits(cut(mid))) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return cut(lo);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final shown = constraints.hasBoundedWidth
              ? fit(
                  text,
                  style: DefaultTextStyle.of(context).style.merge(style),
                  maxWidth: constraints.maxWidth,
                  maxLines: maxLines,
                  textScaler: MediaQuery.textScalerOf(context),
                  textDirection: Directionality.of(context),
                )
              : text;
          return Text(shown,
              maxLines: maxLines, overflow: TextOverflow.clip, style: style);
        },
      );
}
