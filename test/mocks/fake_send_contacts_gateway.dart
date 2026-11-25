// The phone book behind the Send screen's Contacts section, in a test:
// the permission as the test sets it, the contacts it holds, and a record
// of the prompt and of Settings being opened.

import 'package:kute/services/contacts/send_contacts_service.dart';

class FakeSendContactsGateway implements SendContactsGateway {
  FakeSendContactsGateway({
    this.permission = SendContactsPermission.unknown,
    this.contacts = const [],
    this.answer = SendContactsPermission.granted,
  });

  /// What the system says before any prompt.
  SendContactsPermission permission;

  /// What the prompt answers.
  SendContactsPermission answer;
  List<SendContact> contacts;
  int prompts = 0;
  int settingsOpened = 0;

  @override
  Future<SendContactsPermission> status() async => permission;

  @override
  Future<SendContactsPermission> request() async {
    prompts++;
    permission = answer;
    return permission;
  }

  @override
  Future<List<SendContact>> load() async => contacts;

  @override
  Future<void> openSettings() async => settingsOpened++;
}

/// Three friends with numbers.
List<SendContact> fakeContacts() => const [
      SendContact(
          id: 'c1',
          displayName: 'Ana Costa',
          firstName: 'Ana',
          phone: '+351 911 111 111'),
      SendContact(
          id: 'c2',
          displayName: 'Maria Alves',
          firstName: 'Maria',
          phone: '+351 912 345 678'),
      SendContact(
          id: 'c3',
          displayName: 'Rui Santos',
          firstName: 'Rui',
          phone: '+351 913 333 333'),
    ];
