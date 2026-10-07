import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_alert_haptics.dart';
import 'package:kute/services/kute_haptics.dart';

void main() {
  late List<KuteHaptic> played;
  late DateTime now;
  var foreground = true;

  setUp(() {
    KuteHaptics.debugReset();
    played = [];
    now = DateTime(2026, 10, 4, 12);
    foreground = true;
    KuteHaptics.debugOverride = (p) async => played.add(p);
    KuteHaptics.debugNow = () => now;
    KuteHaptics.debugForeground = () => foreground;
  });
  tearDown(KuteHaptics.debugReset);

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  test('nothing plays in the background', () async {
    foreground = false;
    for (final p in KuteHaptic.values) {
      expect(await KuteHaptics.play(p), isFalse);
    }
    expect(played, isEmpty);
  });

  test('each pattern keeps its minimum gap', () async {
    for (final p in KuteHaptic.values) {
      KuteHaptics.debugReset();
      played = [];
      KuteHaptics.debugOverride = (x) async => played.add(x);
      KuteHaptics.debugNow = () => now;
      KuteHaptics.debugForeground = () => true;
      expect(await KuteHaptics.play(p), isTrue);
      advance(p.minGapMs - 1);
      expect(await KuteHaptics.play(p), isFalse, reason: p.name);
      advance(1);
      expect(await KuteHaptics.play(p), isTrue, reason: p.name);
      expect(played, [p, p]);
    }
  });

  test('odds ticks and heartbeats can never buzz continuously', () async {
    // Asked every 50 ms for 10 seconds.
    for (var i = 0; i < 200; i++) {
      await KuteHaptics.play(KuteHaptic.oddsTick);
      advance(50);
    }
    expect(played.length, 10);
    expect(KuteHaptic.heartbeat.minGapMs, greaterThanOrEqualTo(900));
  });

  test('a pattern asked for while another plays is dropped', () async {
    final results = <Future<bool>>[];
    KuteHaptics.debugOverride = (p) async {
      played.add(p);
      // Asked for mid-pattern.
      results.add(KuteHaptics.play(KuteHaptic.fill));
      await Future<void>.delayed(Duration.zero);
    };
    expect(await KuteHaptics.play(KuteHaptic.warning), isTrue);
    expect(await results.single, isFalse);
    expect(played, [KuteHaptic.warning]);
  });

  test('money arriving stays quiet right after a money-success beat',
      () async {
    expect(KuteHaptics.claimMoneySuccess(), isTrue);
    advance(2000);
    expect(await KuteHaptics.play(KuteHaptic.moneyIn), isFalse);
    advance(KuteHaptics.moneyInAfterSuccess.inMilliseconds);
    expect(await KuteHaptics.play(KuteHaptic.moneyIn), isTrue);
  });

  test('the money-success beat stays quiet right after money arriving',
      () async {
    expect(await KuteHaptics.play(KuteHaptic.moneyIn), isTrue);
    advance(1000);
    expect(KuteHaptics.claimMoneySuccess(), isFalse);
    advance(KuteHaptics.successAfterMoneyIn.inMilliseconds);
    expect(KuteHaptics.claimMoneySuccess(), isTrue);
  });

  test('Investing warnings never share a pattern with fills', () {
    for (final t in HlTradeAlertType.values) {
      expect(hlAlertHaptic(t) == KuteHaptic.warning, t.isWarning,
          reason: t.name);
    }
    expect(hlAlertHaptic(HlTradeAlertType.filled), KuteHaptic.fill);
    expect(hlAlertHaptic(HlTradeAlertType.takeProfit), KuteHaptic.fill);
    expect(hlAlertHaptic(HlTradeAlertType.stopLoss), KuteHaptic.notice);
  });
}
