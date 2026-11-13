// BackgroundGrace: a no-op where unsupported, hold/release pairs on iOS and
// Android over the channel, a native expiry kills the token, and the
// watchdog releases a hold nobody gave back.

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/platform/background_grace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;

  setUp(() {
    BackgroundGrace.debugReset();
    calls = [];
    messenger.setMockMethodCallHandler(BackgroundGrace.channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(BackgroundGrace.channel, null);
    BackgroundGrace.debugReset();
  });

  /// The native side's `expired(id)` call into Dart.
  Future<void> nativeExpiry(int id) async {
    ServicesBinding.instance.channelBuffers.push(
      BackgroundGrace.channel.name,
      BackgroundGrace.channel.codec
          .encodeMethodCall(MethodCall('expired', {'id': id})),
      (_) {},
    );
    await pumpEventQueue();
  }

  group('where unsupported', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);

    test('hands out tokens, pairs them, and never touches the channel',
        () async {
      expect(BackgroundGrace.isSupported, isFalse);
      final token = BackgroundGrace.hold('order');
      expect(BackgroundGrace.isHeld(token), isTrue);
      expect(BackgroundGrace.activeCount, 1);
      BackgroundGrace.release(token);
      expect(BackgroundGrace.isHeld(token), isFalse);
      expect(BackgroundGrace.activeCount, 0);
      await pumpEventQueue();
      expect(calls, isEmpty);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group(platform.name, () {
      setUp(() => debugDefaultTargetPlatformOverride = platform);

      test('hold and release reach the channel as a pair on one id',
          () async {
        final token = BackgroundGrace.hold('order');
        expect(BackgroundGrace.isSupported, isTrue);
        BackgroundGrace.release(token);
        await pumpEventQueue();
        expect(calls.map((c) => c.method), ['hold', 'release']);
        expect(calls[0].arguments, {'id': token.id, 'reason': 'order'});
        expect(calls[1].arguments, {'id': token.id});
      });

      test('a second release of the same token sends nothing', () async {
        final token = BackgroundGrace.hold('order');
        BackgroundGrace.release(token);
        BackgroundGrace.release(token);
        await pumpEventQueue();
        expect(calls.map((c) => c.method), ['hold', 'release']);
      });

      test('two holds are two tasks, released independently', () async {
        final a = BackgroundGrace.hold('order');
        final b = BackgroundGrace.hold('order');
        expect(a.id, isNot(b.id));
        BackgroundGrace.release(a);
        expect(BackgroundGrace.isHeld(b), isTrue);
        expect(BackgroundGrace.activeCount, 1);
        BackgroundGrace.release(b);
        await pumpEventQueue();
        expect(calls.map((c) => c.arguments['id']), [a.id, b.id, a.id, b.id]);
      });
    });
  }

  group('iOS expiry', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('a native expiry kills the token; its release sends nothing',
        () async {
      final token = BackgroundGrace.hold('order');
      await pumpEventQueue();
      await nativeExpiry(token.id);
      expect(BackgroundGrace.isHeld(token), isFalse);
      expect(BackgroundGrace.expiredCount.value, 1);
      BackgroundGrace.release(token);
      await pumpEventQueue();
      expect(calls.map((c) => c.method), ['hold']);
    });

    test('an expiry for an unknown id is ignored', () async {
      final token = BackgroundGrace.hold('order');
      await nativeExpiry(token.id + 40);
      expect(BackgroundGrace.isHeld(token), isTrue);
      expect(BackgroundGrace.expiredCount.value, 0);
    });
  });

  group('watchdog', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('releases a hold nobody gave back, once, and counts it', () {
      fakeAsync((async) {
        final token = BackgroundGrace.hold('order');
        async.elapse(BackgroundGrace.watchdog - const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(BackgroundGrace.isHeld(token), isTrue);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(BackgroundGrace.isHeld(token), isFalse);
        expect(BackgroundGrace.watchdogCount.value, 1);
        expect(calls.map((c) => c.method), ['hold', 'release']);
        // Nothing left to fire.
        async.elapse(BackgroundGrace.watchdog * 2);
        async.flushMicrotasks();
        expect(calls.map((c) => c.method), ['hold', 'release']);
        expect(BackgroundGrace.watchdogCount.value, 1);
      });
    });

    test('a released hold never fires its watchdog', () {
      fakeAsync((async) {
        final token = BackgroundGrace.hold('order');
        BackgroundGrace.release(token);
        async.elapse(BackgroundGrace.watchdog * 2);
        async.flushMicrotasks();
        expect(BackgroundGrace.watchdogCount.value, 0);
        expect(calls.map((c) => c.method), ['hold', 'release']);
      });
    });
  });
}
