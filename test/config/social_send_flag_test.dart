// The local social-send flag (lib/config/feature_flags.dart; founder, 24
// November 2026: "for now with a local feature flag disable: 1 - access to
// contacts, only allow to send normal bitcoins. sending dont allow to send
// a prediction or investment"). Pinned off, then on, through the test seam:
//
//   * the contacts: the platform is never asked (no status read, no prompt,
//     no book, no Settings) off; on, it is, as before;
//   * the doors to a person: Send to anyone, the gift search, the What step
//     and the contacts picker refuse off, nothing on screen;
//   * the gift card and row are gone off;
//   * the getkute.com line ends a share's text off, once; on, the text is
//     as it was;
//   * the line and the Who step's placeholder are translated in every
//     language, "getkute.com" untouched.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/config/feature_flags.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/share_link_model.dart' show ShareLinkKind;
import 'package:kute/screens/share/cards/share_card_copy.dart'
    show withGetKuteLine;
import 'package:kute/screens/share/send_pick_market_sheet.dart'
    show sendGiftShown, showSendPickMarketSheet;
import 'package:kute/screens/share/send_to_anyone_sheet.dart'
    show SendToAnyoneSheet, showSendToAnyoneSheet;
import 'package:kute/screens/shared/send/send_recipient_step.dart'
    show showSendContactsPicker;
import 'package:kute/screens/shared/send/send_what_step.dart'
    show SendWhatSheet, sendToPerson;
import 'package:kute/services/contacts/send_contacts_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/runtime_policy_fixture.dart';
import '../mocks/fake_send_contacts_gateway.dart';

/// The fake book, counting every call the notifier makes to the platform.
class _CountingGateway extends FakeSendContactsGateway {
  _CountingGateway()
      : super(
            permission: SendContactsPermission.granted,
            contacts: fakeContacts());

  int statusReads = 0;
  int loads = 0;

  @override
  Future<SendContactsPermission> status() async {
    statusReads++;
    return super.status();
  }

  @override
  Future<List<SendContact>> load() async {
    loads++;
    return super.load();
  }
}

/// A screen with one button running [onTap] with its context.
Future<void> _pumpButton(
    WidgetTester tester, Future<void> Function(BuildContext) onTap) async {
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => onTap(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  tearDown(() => debugSocialSendEnabled = null);

  test('the build ships it off', () {
    expect(kSocialSendEnabled, isFalse);
    expect(socialSendEnabled, isFalse);
  });

  group('the phone\'s contacts', () {
    Future<(_CountingGateway, ProviderContainer)> open() async {
      final gateway = _CountingGateway();
      final container = ProviderContainer(overrides: [
        sendContactsGatewayProvider.overrideWithValue(gateway),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(sendContactsProvider.notifier);
      await notifier.refresh();
      await notifier.request();
      await notifier.openSettings();
      return (gateway, container);
    }

    test('off: never asked, never read', () async {
      debugSocialSendEnabled = false;
      final (gateway, container) = await open();
      expect(gateway.statusReads, 0);
      expect(gateway.prompts, 0);
      expect(gateway.loads, 0);
      expect(gateway.settingsOpened, 0);
      final state = container.read(sendContactsProvider);
      expect(state.permission, SendContactsPermission.unknown);
      expect(state.contacts, isEmpty);
    });

    test('on: read as before', () async {
      debugSocialSendEnabled = true;
      final (gateway, container) = await open();
      expect(gateway.statusReads, 1);
      expect(gateway.prompts, 1);
      expect(gateway.loads, greaterThan(0));
      expect(gateway.settingsOpened, 1);
      expect(container.read(sendContactsProvider).contacts, hasLength(3));
    });
  });

  group('the doors to a person, off', () {
    setUp(() => debugSocialSendEnabled = false);

    testWidgets('Send to anyone refuses, nothing on screen', (tester) async {
      bool? created = true;
      await _pumpButton(tester, (context) async {
        created = await showSendToAnyoneSheet(context,
            kind: ShareLinkKind.bitcoin, entrySource: 'test');
      });
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SendToAnyoneSheet), findsNothing);
      expect(created, isNull);
    });

    testWidgets('the gift search refuses', (tester) async {
      bool? sent = true;
      await _pumpButton(tester, (context) async {
        sent = await showSendPickMarketSheet(context, entrySource: 'test');
      });
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(sent, isFalse);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a person asks no What and opens nothing', (tester) async {
      var opened = 0;
      bool? created = true;
      await _pumpButton(tester, (context) async {
        created = await sendToPerson(
          context,
          phone: '+351912345678',
          openLink: () async {
            opened++;
            return true;
          },
          openGift: () async {
            opened++;
            return true;
          },
        );
      });
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(SendWhatSheet), findsNothing);
      expect(opened, 0);
      expect(created, isFalse);
    });

    testWidgets('the contacts picker does not open', (tester) async {
      await _pumpButton(tester, (context) async {
        await showSendContactsPicker(context,
            onPick: (_) {}, onSomeoneElse: () {});
      });
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  test('the gift card and row: gone off, there on', () async {
    final policy = runtimePolicyFixture(
        also: const {'polymarket.browse', 'hyperliquid.browse'});
    await policy.refresh();
    debugSocialSendEnabled = false;
    expect(sendGiftShown(policy), isFalse);
    debugSocialSendEnabled = true;
    expect(sendGiftShown(policy), isTrue);
  });

  group('the getkute.com line', () {
    final en = lookupAppLocalizations(const Locale('en'));

    test('off: the last line, once', () {
      debugSocialSendEnabled = false;
      expect(en.shareGetKuteLine, 'Get in on the action at getkute.com');
      final text = withGetKuteLine(en, 'Bitcoin on Kute https://x/m/1\n');
      expect(text,
          'Bitcoin on Kute https://x/m/1\nGet in on the action at getkute.com');
      expect(withGetKuteLine(en, text), text);
      expect(withGetKuteLine(en, ''), en.shareGetKuteLine);
    });

    test('on: the text as it was', () {
      debugSocialSendEnabled = true;
      expect(withGetKuteLine(en, 'Bitcoin on Kute'), 'Bitcoin on Kute');
    });

    test('every language says it, getkute.com untouched', () {
      final english = en.shareGetKuteLine;
      final hint = en.sendRecipientSearchHintNoPhone;
      final cut = <String>[];
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        final line = l10n.shareGetKuteLine;
        if (!line.contains('getkute.com')) cut.add('$locale: $line');
        if (line.contains('\n')) cut.add('$locale: two lines');
        if (locale.languageCode != 'en') {
          if (line == english) cut.add('$locale: untranslated line');
          if (l10n.sendRecipientSearchHintNoPhone == hint) {
            cut.add('$locale: untranslated placeholder');
          }
        }
      }
      expect(cut, isEmpty, reason: cut.join('\n'));
    });
  });
}
