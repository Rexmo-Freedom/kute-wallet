import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/continuous_haptics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with the test seam', () {
    late List<ContinuousHapticsCall> log;
    setUp(() {
      ContinuousHaptics.debugReset();
      log = ContinuousHaptics.debugLog = [];
    });
    tearDown(() => ContinuousHaptics.debugLog = null);

    test('updates are throttled to about 30 Hz', () {
      final owner = Object();
      ContinuousHaptics.start(0.3, 0.1, owner: owner);
      for (var ms = 0; ms <= 1000; ms += 4) {
        ContinuousHaptics.update(0.3 + ms / 2000, 0.2,
            owner: owner, at: Duration(milliseconds: ms));
      }
      final updates = log.where((c) => c.method == 'update').toList();
      expect(updates.length, inInclusiveRange(28, 32));
      expect(updates.last.intensity, greaterThan(updates.first.intensity!));
    });

    test('a rumble belongs to its owner', () {
      final a = Object();
      final b = Object();
      ContinuousHaptics.start(0.3, 0.1, owner: a);
      ContinuousHaptics.update(0.5, 0.2, owner: b, at: Duration.zero);
      ContinuousHaptics.stop(owner: b);
      expect(log.map((c) => c.method), ['start']);
      ContinuousHaptics.stop(owner: a);
      ContinuousHaptics.update(0.5, 0.2, owner: a, at: Duration.zero);
      expect(log.map((c) => c.method), ['start', 'stop']);
    });

    test('several bands: one rumble at the strongest level, one ratchet, '
        'and a snap leaves the others rumbling', () {
      final a = Object();
      final b = Object();
      ContinuousHaptics.start(0.3, 0.1, owner: a);
      ContinuousHaptics.start(0.6, 0.3, owner: b);
      expect(log.map((c) => c.method), ['start', 'update']);
      expect(log.last.intensity, 0.6);
      // Only the leader's updates and clicks reach the phone.
      ContinuousHaptics.update(0.4, 0.1, owner: a, at: Duration.zero);
      ContinuousHaptics.tick(0.5, 0.5, owner: a);
      expect(log, hasLength(2));
      ContinuousHaptics.tick(0.8, 0.8, owner: b);
      expect(log.last.method, 'tick');
      // b lands: the snap, then a's rumble again.
      ContinuousHaptics.stop(owner: b);
      expect(log.last.method, 'update');
      expect(log.last.intensity, 0.4);
      ContinuousHaptics.snap(owner: b);
      expect(log.map((c) => c.method).skip(4), ['snap', 'start']);
      expect(ContinuousHaptics.isRunning(a), isTrue);
      ContinuousHaptics.stop(owner: a);
      expect(log.last.method, 'stop');
      expect(ContinuousHaptics.isRunning(), isFalse);
    });

    test('values are clamped to 0..1', () {
      ContinuousHaptics.start(3, double.nan);
      expect(log.single.intensity, 1);
      expect(log.single.sharpness, 0);
    });
  });

  test('without the bridge nothing throws, and the snap falls back to the '
      'system heavy impact', () async {
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = null;
    final system = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      system.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    ContinuousHaptics.start(0.3, 0.1);
    ContinuousHaptics.update(0.4, 0.2);
    ContinuousHaptics.tick(0.5, 0.5);
    ContinuousHaptics.pulse(0.5);
    ContinuousHaptics.stop();
    await pumpEventQueue();
    ContinuousHaptics.snap();
    await pumpEventQueue();
    expect(
        system.where((c) =>
            c.method == 'HapticFeedback.vibrate' &&
            c.arguments == 'HapticFeedbackType.heavyImpact'),
        hasLength(1));
  });
}
