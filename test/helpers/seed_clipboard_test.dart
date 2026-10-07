import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/seed_clipboard.dart';
import 'package:kute/services/secure/keychain_local.dart';

const phrase = 'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

class FakeClipboard implements ClipboardAccess {
  FakeClipboard({this.withCounter = false});

  final bool withCounter;
  String? text;
  int counter = 0;
  int reads = 0;
  final writes = <String>[];
  final sensitiveWrites = <String>[];

  @override
  Future<void> write(String value) async {
    text = value;
    writes.add(value);
    counter++;
  }

  @override
  Future<void> writeSensitive(String value) async {
    sensitiveWrites.add(value);
    await write(value);
  }

  @override
  Future<String?> read() async {
    reads++;
    return text;
  }

  @override
  Future<int?> changeCount() async => withCounter ? counter : null;

  void userCopies(String value) {
    text = value;
    counter++;
  }
}

class DelayedClipboard extends FakeClipboard {
  DelayedClipboard({this.delayCounter = false}) : super(withCounter: true);
  final bool delayCounter;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> write(String value) async {
    if (!delayCounter && value.isNotEmpty) {
      entered.complete();
      await release.future;
    }
    await super.write(value);
  }

  @override
  Future<int?> changeCount() async {
    if (delayCounter && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.changeCount();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SeedClipboard', () {
    testWidgets('clears after 60 s when the clipboard still holds the phrase',
        (tester) async {
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      expect(fake.text, phrase);

      await tester.pump(const Duration(seconds: 59));
      expect(fake.text, phrase);
      await tester.pump(const Duration(seconds: 1));
      expect(fake.text, '');
      expect(fake.writes, [phrase, '']);
      // The phrase goes out marked sensitive; the clear is a plain write.
      expect(fake.sensitiveWrites, [phrase]);
      expect(clipboard.hasPendingCopy, isFalse);
    });

    testWidgets('something copied later is never cleared', (tester) async {
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      fake.userCopies('an address the user copied');

      await tester.pump(const Duration(seconds: 60));
      expect(fake.text, 'an address the user copied');
      expect(fake.writes, [phrase]);
    });

    testWidgets('with a change counter the content is never read',
        (tester) async {
      final fake = FakeClipboard(withCounter: true);
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      await tester.pump(const Duration(seconds: 60));
      expect(fake.text, '');

      await clipboard.copy(phrase);
      fake.userCopies('later copy');
      await tester.pump(const Duration(seconds: 60));
      expect(fake.text, 'later copy');
      expect(fake.reads, 0);
    });

    testWidgets('dispose clears a pending copy still on the clipboard',
        (tester) async {
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      clipboard.dispose();
      await tester.pump();
      expect(fake.text, '');

      await tester.pump(const Duration(seconds: 60));
      expect(fake.writes, [phrase, '']);
    });

    testWidgets('dispose keeps something copied later', (tester) async {
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      fake.userCopies('later copy');
      clipboard.dispose();
      await tester.pump();
      expect(fake.text, 'later copy');
    });

    testWidgets('dispose without a copy never touches the clipboard',
        (tester) async {
      final fake = FakeClipboard()..text = 'user text';
      SeedClipboard(access: fake).dispose();
      await tester.pump(const Duration(seconds: 61));
      expect(fake.reads, 0);
      expect(fake.writes, isEmpty);
      expect(fake.text, 'user text');
    });

    for (final delayCounter in [false, true]) {
      testWidgets('dispose during ${delayCounter ? 'counter read' : 'write'} clears the late copy',
          (tester) async {
        final fake = DelayedClipboard(delayCounter: delayCounter);
        final clipboard = SeedClipboard(access: fake);
        final copying = clipboard.copy(phrase);
        await fake.entered.future;
        clipboard.dispose();
        fake.release.complete();
        await copying;
        await tester.pump();
        expect(fake.text, '');
        expect(fake.writes, [phrase, '']);
        expect(clipboard.hasPendingCopy, isFalse);
        await tester.pump(const Duration(seconds: 61));
        expect(fake.writes, [phrase, '']);
      });
    }

    testWidgets('dispose prevents a queued copy from writing another seed',
        (tester) async {
      final fake = DelayedClipboard();
      final clipboard = SeedClipboard(access: fake);
      final first = clipboard.copy(phrase);
      await fake.entered.future;
      final second = clipboard.copy('another fixture');
      clipboard.dispose();
      fake.release.complete();
      await Future.wait([first, second]);
      await tester.pump();
      await clipboard.copy('after disposal');
      expect(fake.writes, [phrase, '']);
      expect(fake.text, '');
    });

    group('takePaste', () {
      testWidgets('reads once and clears a phrase still on the clipboard',
          (tester) async {
        final fake = FakeClipboard(withCounter: true)..userCopies(phrase);
        final clipboard = SeedClipboard(access: fake);
        expect(await clipboard.takePaste(), phrase);
        expect(fake.reads, 1);
        expect(await clipboard.clearIfUnchanged(), isTrue);
        expect(fake.text, '');
        // The counter guards the clear, so the content is read only once.
        expect(fake.reads, 1);
      });

      testWidgets('keeps something copied after the paste', (tester) async {
        final fake = FakeClipboard(withCounter: true)..userCopies(phrase);
        final clipboard = SeedClipboard(access: fake);
        await clipboard.takePaste();
        fake.userCopies('a later copy');
        expect(await clipboard.clearIfUnchanged(), isFalse);
        expect(fake.text, 'a later copy');
      });

      testWidgets('without a counter compares the content before clearing',
          (tester) async {
        final fake = FakeClipboard()..userCopies(phrase);
        final clipboard = SeedClipboard(access: fake);
        await clipboard.takePaste();
        expect(await clipboard.clearIfUnchanged(), isTrue);
        expect(fake.text, '');
      });

      testWidgets('forget leaves the clipboard alone, even on dispose',
          (tester) async {
        final fake = FakeClipboard()..userCopies('not a phrase');
        final clipboard = SeedClipboard(access: fake);
        expect(await clipboard.takePaste(), 'not a phrase');
        clipboard.forget();
        clipboard.dispose();
        await tester.pump(const Duration(seconds: 61));
        expect(fake.text, 'not a phrase');
        expect(fake.writes, isEmpty);
      });

      testWidgets('an empty clipboard returns null and holds nothing',
          (tester) async {
        final fake = FakeClipboard();
        final clipboard = SeedClipboard(access: fake);
        expect(await clipboard.takePaste(), isNull);
        expect(clipboard.hasPendingCopy, isFalse);
      });
    });

    testWidgets('a new copy restarts the 60 s window', (tester) async {
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);
      await tester.pump(const Duration(seconds: 30));
      await clipboard.copy(phrase);
      await tester.pump(const Duration(seconds: 30));
      expect(fake.text, phrase);
      await tester.pump(const Duration(seconds: 30));
      expect(fake.text, '');
    });

    testWidgets('in the background the check waits for resume', (tester) async {
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      final fake = FakeClipboard();
      final clipboard = SeedClipboard(access: fake);
      await clipboard.copy(phrase);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 90));
      expect(fake.text, phrase);
      expect(fake.reads, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.text, '');
    });
  });

  group('SystemClipboardAccess', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
        calls.add(call);
        return 7;
      });
    });

    tearDown(
        () => messenger.setMockMethodCallHandler(KeychainLocal.channel, null));

    test('iOS reads UIPasteboard.changeCount over the security channel',
        () async {
      final count = await const SystemClipboardAccess(
        platform: TargetPlatform.iOS,
      ).changeCount();
      expect(count, 7);
      expect(calls.single.method, 'pasteboardChangeCount');
      expect(calls.single.arguments, isNull);
    });

    test('Android has no change counter', () async {
      final count = await const SystemClipboardAccess(
        platform: TargetPlatform.android,
      ).changeCount();
      expect(count, isNull);
      expect(calls, isEmpty);
    });

    test('iOS and Android copy a secret as sensitive over the channel',
        () async {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        calls.clear();
        await SystemClipboardAccess(platform: platform).writeSensitive(phrase);
        expect(calls.single.method, 'copySensitive', reason: '$platform');
        expect(calls.single.arguments, {'text': phrase, 'expirySeconds': 60});
      }
    });

    test('a failed sensitive copy falls back to the plain clipboard',
        () async {
      String? plain;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          plain = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      messenger.setMockMethodCallHandler(KeychainLocal.channel, (call) async {
        calls.add(call);
        throw PlatformException(code: 'UNAVAILABLE');
      });
      await const SystemClipboardAccess(platform: TargetPlatform.iOS)
          .writeSensitive(phrase);
      expect(calls.single.method, 'copySensitive');
      expect(plain, phrase);

      // No native handler at all (an older build): plain copy too.
      plain = null;
      messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
      await const SystemClipboardAccess(platform: TargetPlatform.android)
          .writeSensitive(phrase);
      expect(plain, phrase);
    });

    test('other platforms copy the plain way', () async {
      String? plain;
      messenger.setMockMethodCallHandler(SystemChannels.platform,
          (call) async {
        if (call.method == 'Clipboard.setData') {
          plain = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await const SystemClipboardAccess(platform: TargetPlatform.macOS)
          .writeSensitive(phrase);
      expect(calls, isEmpty);
      expect(plain, phrase);
    });

    test('a missing native method falls back to a content compare', () async {
      messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
      final count = await const SystemClipboardAccess(
        platform: TargetPlatform.iOS,
      ).changeCount();
      expect(count, isNull);
    });
  });

  test('seed screens copy only through SeedClipboard', () {
    for (final path in [
      'lib/screens/settings/components/seed_words.dart',
      'lib/screens/settings/components/backup_wallet.dart',
      'lib/screens/creation/recover_wallet.dart',
      'lib/screens/recovery/restore_secrets_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('SeedClipboard()'), reason: path);
      expect(source, isNot(contains('Clipboard.setData')), reason: path);
    }
  });
}
