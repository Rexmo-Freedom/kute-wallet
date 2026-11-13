// lib/services/contacts/send_contacts_service.dart
//
// THE PHONE'S CONTACTS ON THE SEND SCREEN (founder, 31 October 2026):
// a send can go to a phone number through a Send to anyone link, so the
// Send to step offers the person's contacts as recipients. Everything
// stays on the phone: names and numbers are read through
// `flutter_contacts`, filtered in memory and never sent to the backend or
// to analytics (the only event is `send_contacts_permission {granted}`).
// A picked contact starts the Send to anyone flow with the first name as
// the link's label and the number kept in the local pending-link row
// (models/share_link_model.dart, `recipientPhone`) for "Send again via
// WhatsApp / SMS".
//
// The permission is asked ON TAP of the "See your contacts" row at the
// top of the Contacts list (send_contacts_list.dart), never on screen
// open; the status is read on open so the row can say "Allow contacts in
// Settings" once the person refused. Each contact also carries its photo
// thumbnail (the avatar) and, when one of its emails is a Kute Lightning
// address (`name@paykute.com`), that address: the list badges it as a
// Kute user and a tap pays it directly. Both stay on the phone too. The platform is behind
// [SendContactsGateway] so widget tests drive every state with a fake.

import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/services/tracking_service.dart';

/// Where the person stands on the contacts permission.
enum SendContactsPermission {
  /// Never asked.
  unknown,
  granted,

  /// Refused in a way the system lets us ask again.
  denied,

  /// Refused for good (iOS after one refusal, Android "Don't ask again",
  /// a restricted profile): only Settings can turn it on.
  blocked,
}

/// One contact as the Send screen shows it: a name and ONE number (the
/// primary, else the first).
@immutable
class SendContact {
  const SendContact({
    required this.id,
    required this.displayName,
    required this.firstName,
    required this.phone,
    this.lightningAddress,
    this.photo,
  });

  final String id;
  final String displayName;

  /// The given name, else the first word of the display name. The label
  /// the share link carries.
  final String firstName;

  /// The number as the phone book has it.
  final String phone;

  /// A Kute Lightning address among the contact's emails
  /// ([kKuteLightningDomain]), else null.
  final String? lightningAddress;

  /// The photo thumbnail, when the book has one.
  final Uint8List? photo;

  /// "MA" for Maria Alves, "M" for Maria.
  String get initials => sendContactInitials(displayName);

  /// Whether [query] (a name fragment or digits) matches this contact.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (displayName.toLowerCase().contains(q)) return true;
    if (lightningAddress?.toLowerCase().contains(q) ?? false) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty ||
        digits.length != q.replaceAll(RegExp(r'[\s+()\-.]'), '').length) {
      return false;
    }
    return phone.replaceAll(RegExp(r'\D'), '').contains(digits);
  }
}

/// The Lightning address domain of every Kute wallet.
const String kKuteLightningDomain = 'paykute.com';

/// Whether [address] is a Kute Lightning address (`name@paykute.com`).
bool isKuteLightningAddress(String? address) {
  final a = address?.trim().toLowerCase() ?? '';
  final at = a.lastIndexOf('@');
  return at > 0 && a.substring(at + 1) == kKuteLightningDomain;
}

/// "MA" for Maria Alves, "M" for Maria, "" for nothing.
String sendContactInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  String first(String s) => String.fromCharCodes(s.runes.take(1)).toUpperCase();
  if (parts.length == 1) return first(parts.first);
  return first(parts.first) + first(parts.last);
}

/// The platform behind the contacts section.
abstract class SendContactsGateway {
  Future<SendContactsPermission> status();
  Future<SendContactsPermission> request();
  Future<List<SendContact>> load();
  Future<void> openSettings();
}

/// `flutter_contacts`.
class FlutterContactsGateway implements SendContactsGateway {
  const FlutterContactsGateway();

  SendContactsPermission _map(fc.PermissionStatus s) => switch (s) {
        fc.PermissionStatus.granted ||
        fc.PermissionStatus.limited =>
          SendContactsPermission.granted,
        fc.PermissionStatus.denied => SendContactsPermission.denied,
        fc.PermissionStatus.permanentlyDenied ||
        fc.PermissionStatus.restricted =>
          SendContactsPermission.blocked,
        _ => SendContactsPermission.unknown,
      };

  @override
  Future<SendContactsPermission> status() async {
    try {
      return _map(
          await fc.FlutterContacts.permissions.check(fc.PermissionType.read));
    } catch (_) {
      return SendContactsPermission.unknown;
    }
  }

  @override
  Future<SendContactsPermission> request() async {
    try {
      return _map(
          await fc.FlutterContacts.permissions.request(fc.PermissionType.read));
    } catch (_) {
      return SendContactsPermission.denied;
    }
  }

  @override
  Future<List<SendContact>> load() async {
    final rows = await fc.FlutterContacts.getAll(
      properties: {
        fc.ContactProperty.name,
        fc.ContactProperty.phone,
        fc.ContactProperty.email,
        fc.ContactProperty.photoThumbnail,
      },
    );
    final out = <SendContact>[];
    for (final c in rows) {
      final id = c.id;
      if (id == null || c.phones.isEmpty) continue;
      final primary = c.phones.where((p) => p.isPrimary == true).firstOrNull;
      final phone = (primary ?? c.phones.first).number.trim();
      if (phone.isEmpty) continue;
      final display = (c.displayName ?? '').trim();
      final given = (c.name?.first ?? '').trim();
      final name = display.isNotEmpty
          ? display
          : given.isNotEmpty
              ? given
              : phone;
      final kute = c.emails
          .map((e) => e.address.trim())
          .where(isKuteLightningAddress)
          .firstOrNull;
      final thumb = c.photo?.thumbnail;
      out.add(SendContact(
        id: id,
        displayName: name,
        firstName: given.isNotEmpty ? given : name.split(' ').first,
        phone: phone,
        lightningAddress: kute,
        photo: thumb != null && thumb.isNotEmpty ? thumb : null,
      ));
    }
    out.sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  @override
  Future<void> openSettings() => fc.FlutterContacts.permissions.openSettings();
}

/// Test seam and the real thing: override in a ProviderScope.
final sendContactsGatewayProvider =
    Provider<SendContactsGateway>((_) => const FlutterContactsGateway());

@immutable
class SendContactsState {
  const SendContactsState({
    this.permission = SendContactsPermission.unknown,
    this.contacts = const [],
    this.loading = false,
  });

  final SendContactsPermission permission;

  /// Alphabetical, every contact with a number. Empty until granted.
  final List<SendContact> contacts;
  final bool loading;

  bool get granted => permission == SendContactsPermission.granted;

  SendContactsState copyWith({
    SendContactsPermission? permission,
    List<SendContact>? contacts,
    bool? loading,
  }) =>
      SendContactsState(
        permission: permission ?? this.permission,
        contacts: contacts ?? this.contacts,
        loading: loading ?? this.loading,
      );

  /// The contacts matching [query], up to [limit].
  List<SendContact> matching(String query, {int? limit}) {
    final out = [
      for (final c in contacts)
        if (c.matches(query)) c
    ];
    return limit == null ? out : out.take(limit).toList();
  }
}

class SendContactsNotifier extends Notifier<SendContactsState> {
  @override
  SendContactsState build() => const SendContactsState();

  SendContactsGateway get _gateway => ref.read(sendContactsGatewayProvider);

  /// On the Send to step's open: the status only, never a prompt. Loads
  /// the book when it was granted before.
  Future<void> refresh() async {
    final permission = await _gateway.status();
    state = state.copyWith(permission: permission);
    if (permission == SendContactsPermission.granted &&
        state.contacts.isEmpty) {
      await _load();
    }
  }

  /// The "Send to a friend" row tapped: the system prompt, then the book.
  Future<SendContactsPermission> request() async {
    final permission = await _gateway.request();
    TrackingService.track('send_contacts_permission', params: {
      'granted': permission == SendContactsPermission.granted,
    });
    state = state.copyWith(permission: permission);
    if (permission == SendContactsPermission.granted) await _load();
    return permission;
  }

  Future<void> openSettings() => _gateway.openSettings();

  Future<void> _load() async {
    state = state.copyWith(loading: true);
    try {
      final rows = await _gateway.load();
      state = state.copyWith(contacts: rows, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }
}

final sendContactsProvider =
    NotifierProvider<SendContactsNotifier, SendContactsState>(
        SendContactsNotifier.new);
