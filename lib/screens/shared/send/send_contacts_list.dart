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
// Each entry: an avatar circle (the photo, the initials, or the coin's
// mark), the name and a quiet line; a BADGE on the avatar's corner
// ([SendPersonBadge]): the Kute mark when the recipient is a Kute user
// (a `@paykute.com` Lightning address, from a recent or a contact's
// email), ⚡ when it is any other Lightning address (or an LNURL); none
// for a plain phone contact or a coin address.
//
// A tap hands the entry to the flow ([SendContactsSection.onPerson]): an
// entry with an address is paid directly (as a recent always was); a
// plain contact starts the claim link (Send to anyone with the first name
// and the number kept in the local row). What is typed in the field
// filters the list by name, number or address, and a typed phone number
// no contact has offers "Send a link to +351…" ([onPhoneLink]).
//
// THE FIELD KEEPS EVERYTHING IT DOES (founder): this list is added UNDER
// it and never stands in for address entry; the flows show their resolved
// destination row first and the list under it.
//
// With no contacts (not granted, or an empty book) the recents keep their
// circles row ([SendRecentCircles]); with contacts everything is the one
// list. Everything is local: numbers never leave the phone.

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

/// The Contacts section under a send's search field (see the file
/// header).
class SendContactsSection extends ConsumerWidget {
  const SendContactsSection({
    super.key,
    required this.query,
    required this.recents,
    required this.onPerson,
    required this.onPhoneLink,
  });

  /// What the field holds (filters the list).
  final String query;
  final List<SendPerson> recents;
  final ValueChanged<SendPerson> onPerson;

  /// A typed number no contact has: the claim link to it.
  final ValueChanged<String> onPhoneLink;

  /// The most entries listed at once (type to find the rest).
  static const int maxRows = 60;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final state = ref.watch(sendContactsProvider);
    final contacts = state.granted ? state.contacts : const <SendContact>[];
    final phone = sendTypedPhone(query);
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
    final Widget? askRow = state.granted
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

    // No book: the ask row, the recents' circles, the phone link.
    if (contacts.isEmpty) {
      final shown = [
        for (final r in recents)
          if (r.matches(query)) r
      ];
      final rows = [
        if (phoneRow != null) phoneRow,
        if (askRow != null && query.trim().isEmpty) askRow,
      ];
      if (rows.isEmpty && shown.isEmpty) return const SizedBox.shrink();
      return Padding(
        key: const ValueKey('send-contacts-section'),
        padding: EdgeInsets.only(top: 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isNotEmpty) ...[
              SendSectionLabel(l10n.sendContacts),
              SendToListCard(colors: c, rows: rows),
            ],
            if (shown.isNotEmpty) ...[
              if (rows.isNotEmpty) SizedBox(height: 20.h),
              SendSectionLabel(l10n.sendRecentRecipients),
              SendRecentCircles(items: [
                for (final p in shown)
                  SendRecentItem(
                    id: p.id,
                    label: p.name,
                    initials: p.initials.isEmpty ? null : p.initials,
                    icon: p.icon,
                    mark: p.mark,
                    onTap: () => onPerson(p),
                  ),
              ]),
            ],
          ],
        ),
      );
    }

    final people = [
      for (final p in sendPeople(recents: recents, contacts: contacts))
        if (p.matches(query)) p
    ];
    final rows = <Widget>[
      if (phoneRow != null) phoneRow,
      for (final p in people.take(maxRows))
        SendToListRow(
          key: ValueKey('send-person-${p.id}'),
          colors: c,
          leading: SendPersonAvatar(person: p),
          title: p.name,
          subtitle: p.secondary,
          onTap: () => onPerson(p),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('send-contacts-section'),
      padding: EdgeInsets.only(top: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendSectionLabel(l10n.sendContacts),
          SendToListCard(
              key: const ValueKey('send-contacts-list'), colors: c, rows: rows),
        ],
      ),
    );
  }
}

/// An entry's 40 px avatar with its badge on the lower right corner.
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
            color: c.textPrimary,
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
    final badge = d * 0.42;
    return SizedBox.square(
      dimension: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
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

/// The badge itself: the Kute mark (a "k" on the ink circle) or ⚡ (a bolt
/// on amber), ringed in the card's surface.
class SendPersonBadgeDot extends StatelessWidget {
  const SendPersonBadgeDot(
      {super.key, required this.badge, required this.size});

  final SendPersonBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
          color: kute ? c.textPrimary : const Color(0xFFFFB300),
          shape: BoxShape.circle,
          border: Border.all(color: c.surfaceLight, width: 1.5),
        ),
        child: kute
            ? Text(
                'k',
                style: TextStyle(
                  color: c.surfaceLight,
                  fontSize: size * 0.62,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              )
            : Icon(Icons.bolt_rounded, color: Colors.white, size: size * 0.78),
      ),
    );
  }
}
