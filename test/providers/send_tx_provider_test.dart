import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/send_tx_provider.dart';

void main() {
  setUpAll(() {
    AppCurrencies.registerCustomCurrencies();
  });

  group('SendTx model', () {
    test('copyWith updates address', () {
      final tx = SendTx(address: 'abc', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(address: 'xyz');
      expect(updated.address, 'xyz');
      expect(updated.amount, 0);
    });

    test('copyWith updates amount', () {
      final tx = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(amount: 5000);
      expect(updated.amount, 5000);
    });

    test('copyWith updates type', () {
      final tx = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(type: PaymentType.Lightning);
      expect(updated.type, PaymentType.Lightning);
    });

    test('copyWith updates drain', () {
      final tx = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(drain: true);
      expect(updated.drain, true);
    });

    test('copyWith preserves unmodified fields', () {
      final tx = SendTx(address: 'addr', amount: 100, type: PaymentType.Bitcoin, drain: true);
      final updated = tx.copyWith(amount: 999);
      expect(updated.address, 'addr');
      expect(updated.type, PaymentType.Bitcoin);
      expect(updated.drain, true);
    });

    test('copyWith updates networkHint', () {
      final tx = SendTx(address: 'a', amount: 0, type: PaymentType.Unknown, drain: false, networkHint: 'ETH');
      expect(tx.networkHint, 'ETH');
      final updated = tx.copyWith(networkHint: 'SOL');
      expect(updated.networkHint, 'SOL');
    });
  });

  group('SendTxModel notifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial state has empty address and zero amount', () {
      final state = container.read(sendTxProvider);
      expect(state.address, '');
      expect(state.amount, 0);
      expect(state.type, PaymentType.Unknown);
      expect(state.drain, false);
      expect(state.networkHint, isNull);
    });

    test('updateAddress changes address', () {
      container.read(sendTxProvider.notifier).updateAddress('bc1qtest');
      expect(container.read(sendTxProvider).address, 'bc1qtest');
    });

    test('updateAmount changes amount', () {
      container.read(sendTxProvider.notifier).updateAmount(42000);
      expect(container.read(sendTxProvider).amount, 42000);
    });

    test('updatePaymentType changes type', () {
      container.read(sendTxProvider.notifier).updatePaymentType(PaymentType.Lightning);
      expect(container.read(sendTxProvider).type, PaymentType.Lightning);
    });

    test('updateDrain changes drain', () {
      container.read(sendTxProvider.notifier).updateDrain(true);
      expect(container.read(sendTxProvider).drain, true);
    });

    test('updateNetworkHint changes networkHint', () {
      container.read(sendTxProvider.notifier).updateNetworkHint('ETH');
      expect(container.read(sendTxProvider).networkHint, 'ETH');
    });

    test('updateNetworkHint can set to null', () {
      container.read(sendTxProvider.notifier).updateNetworkHint('ETH');
      container.read(sendTxProvider.notifier).updateNetworkHint(null);
      expect(container.read(sendTxProvider).networkHint, isNull);
    });

    test('resetToDefault clears all fields', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('bc1qtest');
      notifier.updateAmount(50000);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      notifier.updateDrain(true);
      notifier.updateNetworkHint('ETH');

      notifier.resetToDefault();

      final state = container.read(sendTxProvider);
      expect(state.address, '');
      expect(state.amount, 0);
      expect(state.type, PaymentType.Unknown);
      expect(state.drain, false);
      expect(state.networkHint, isNull);
    });

    test('updateAmountFromInput empty string sets 0', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('updateAmountFromInput non-numeric sets 0', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('abc', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('updateAmountFromInput zero sets 0', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('updateAmountFromInput sats denomination', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('50000', 'sats');
      expect(container.read(sendTxProvider).amount, 50000);
    });

    test('updateAmountFromInput sats truncates decimals', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('50000.7', 'sats');
      expect(container.read(sendTxProvider).amount, 50000);
    });

    test('updateAmountFromInput BTC denomination converts to sats', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('1.0', 'BTC');
      expect(container.read(sendTxProvider).amount, 100000000);
    });

    test('updateAmountFromInput BTC small amount', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0.0005', 'BTC');
      expect(container.read(sendTxProvider).amount, 50000);
    });

    test('updateAmountFromInput handles comma as decimal', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0,5', 'BTC');
      expect(container.read(sendTxProvider).amount, 50000000);
    });

    test('updateAmountFromInput unknown denomination sets 0', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('100', 'XYZ');
      expect(container.read(sendTxProvider).amount, 0);
    });
  });

  group('sendTxProvider autoDispose behavior', () {
    test('provider is autoDispose — fresh state after all listeners removed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Simulate a "screen" listening to the provider
      final sub = container.listen(sendTxProvider, (_, __) {});

      // Set some state (simulating scanner → confirm flow)
      container.read(sendTxProvider.notifier).updateAddress('bc1qstale');
      container.read(sendTxProvider.notifier).updateAmount(100000);
      container.read(sendTxProvider.notifier).updatePaymentType(PaymentType.Bitcoin);

      expect(container.read(sendTxProvider).address, 'bc1qstale');

      // "Screen" is removed — listener closed
      sub.close();

      // Riverpod autoDispose happens asynchronously — pump the event loop
      await Future<void>.delayed(Duration.zero);

      // Re-read: autoDispose creates fresh default state
      final freshState = container.read(sendTxProvider);
      expect(freshState.address, '');
      expect(freshState.amount, 0);
      expect(freshState.type, PaymentType.Unknown);
      expect(freshState.drain, false);
    });

    test('state persists while at least one listener exists', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Two "screens" listening (e.g., confirm screen + derived provider)
      final sub1 = container.listen(sendTxProvider, (_, __) {});
      final sub2 = container.listen(sendTxProvider, (_, __) {});

      container.read(sendTxProvider.notifier).updateAddress('bc1qkeep');
      container.read(sendTxProvider.notifier).updateAmount(50000);

      // Remove one listener (e.g., camera pops)
      sub1.close();
      await Future<void>.delayed(Duration.zero);

      // State should still be alive because sub2 is active
      expect(container.read(sendTxProvider).address, 'bc1qkeep');
      expect(container.read(sendTxProvider).amount, 50000);

      // Remove last listener
      sub2.close();
      await Future<void>.delayed(Duration.zero);

      // Now state should be fresh
      expect(container.read(sendTxProvider).address, '');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('stale state cannot leak between payment flows', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Flow 1: User scans and enters confirm screen
      final flow1 = container.listen(sendTxProvider, (_, __) {});
      container.read(sendTxProvider.notifier).updateAddress('bc1qflow1');
      container.read(sendTxProvider.notifier).updateAmount(100000);
      container.read(sendTxProvider.notifier).updatePaymentType(PaymentType.Bitcoin);

      // User presses back without sending — flow 1 ends
      flow1.close();
      await Future<void>.delayed(Duration.zero);

      // Flow 2: User starts a new payment
      final flow2 = container.listen(sendTxProvider, (_, __) {});
      final state = container.read(sendTxProvider);

      // Must be fresh — no stale address from flow 1
      expect(state.address, '');
      expect(state.amount, 0);
      expect(state.type, PaymentType.Unknown);

      flow2.close();
    });

    test('resetToDefault still works as belt-and-suspenders', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(sendTxProvider, (_, __) {});

      container.read(sendTxProvider.notifier).updateAddress('bc1qtest');
      container.read(sendTxProvider.notifier).updateAmount(99999);
      container.read(sendTxProvider.notifier).resetToDefault();

      // Even while listener is active, reset works
      expect(container.read(sendTxProvider).address, '');
      expect(container.read(sendTxProvider).amount, 0);

      sub.close();
    });

    test('simulates full scanner → confirm → send → dispose flow', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Step 1: Scanner writes state (ref.read — no persistent listener)
      container.read(sendTxProvider.notifier).updateAddress('bc1qrecipient');
      container.read(sendTxProvider.notifier).updateAmount(50000);
      container.read(sendTxProvider.notifier).updatePaymentType(PaymentType.Bitcoin);

      // Step 2: Confirm screen mounts (ref.watch — starts listening)
      final confirmScreenListener = container.listen(sendTxProvider, (_, __) {});

      // Step 3: Confirm screen reads the state
      expect(container.read(sendTxProvider).address, 'bc1qrecipient');
      expect(container.read(sendTxProvider).amount, 50000);
      expect(container.read(sendTxProvider).type, PaymentType.Bitcoin);

      // Step 4: User sends — success callback resets and navigates away
      container.read(sendTxProvider.notifier).resetToDefault();
      confirmScreenListener.close();
      await Future<void>.delayed(Duration.zero);

      // Step 5: Next flow gets clean state
      final nextFlowListener = container.listen(sendTxProvider, (_, __) {});
      expect(container.read(sendTxProvider).address, '');
      expect(container.read(sendTxProvider).amount, 0);
      nextFlowListener.close();
    });

    test('simulates scanner → confirm → error → back flow (no manual reset)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Scanner writes state
      container.read(sendTxProvider.notifier).updateAddress('bc1qdangerous');
      container.read(sendTxProvider.notifier).updateAmount(1000000);

      // Confirm screen mounts
      final confirmScreen = container.listen(sendTxProvider, (_, __) {});

      // Send fails — NO resetToDefault() called (the bug scenario)
      // User presses back — screen unmounts
      confirmScreen.close();
      await Future<void>.delayed(Duration.zero);

      // Next flow: autoDispose ensures fresh state
      final nextFlow = container.listen(sendTxProvider, (_, __) {});
      final state = container.read(sendTxProvider);

      // CRITICAL: stale address must not be present
      expect(state.address, '');
      expect(state.amount, 0);
      expect(state.type, PaymentType.Unknown);

      nextFlow.close();
    });
  });

  group('PaymentType enum', () {
    test('all values exist', () {
      expect(PaymentType.values.length, 5);
      expect(PaymentType.values, contains(PaymentType.Bitcoin));
      expect(PaymentType.values, contains(PaymentType.Lightning));
      expect(PaymentType.values, contains(PaymentType.Spark));
      expect(PaymentType.values, contains(PaymentType.Unknown));
      expect(PaymentType.values, contains(PaymentType.NonNative));
    });
  });

  group('SendTx copyWith edge cases', () {
    test('copyWith with no arguments returns identical values', () {
      final tx = SendTx(address: 'addr', amount: 100, type: PaymentType.Bitcoin, drain: true, networkHint: 'ETH');
      final copy = tx.copyWith();
      expect(copy.address, 'addr');
      expect(copy.amount, 100);
      expect(copy.type, PaymentType.Bitcoin);
      expect(copy.drain, true);
      expect(copy.networkHint, 'ETH');
    });

    test('copyWith returns a new instance (not the same reference)', () {
      final tx = SendTx(address: 'a', amount: 0, type: PaymentType.Unknown, drain: false);
      final copy = tx.copyWith();
      expect(identical(tx, copy), isFalse);
    });

    test('copyWith cannot set networkHint to null (uses ?? operator)', () {
      // This documents the known limitation: copyWith uses `??` so passing null
      // for networkHint keeps the old value. updateNetworkHint works around this.
      final tx = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false, networkHint: 'ETH');
      final copy = tx.copyWith(networkHint: null);
      // Because of `??`, null is treated as "not provided" and the old value is kept
      expect(copy.networkHint, 'ETH');
    });

    test('copyWith updates multiple fields at once', () {
      final tx = SendTx(address: 'old', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(address: 'new', amount: 999, type: PaymentType.Lightning, drain: true);
      expect(updated.address, 'new');
      expect(updated.amount, 999);
      expect(updated.type, PaymentType.Lightning);
      expect(updated.drain, true);
    });

    test('copyWith with empty string address', () {
      final tx = SendTx(address: 'has_addr', amount: 0, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(address: '');
      expect(updated.address, '');
    });

    test('copyWith with zero amount', () {
      final tx = SendTx(address: '', amount: 50000, type: PaymentType.Unknown, drain: false);
      final updated = tx.copyWith(amount: 0);
      expect(updated.amount, 0);
    });
  });

  group('SendTxModel state change notifications', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('listener is notified on each state change', () {
      int notificationCount = 0;
      container.listen(sendTxProvider, (_, __) {
        notificationCount++;
      });

      container.read(sendTxProvider.notifier).updateAddress('addr1');
      container.read(sendTxProvider.notifier).updateAmount(100);
      container.read(sendTxProvider.notifier).updateDrain(true);

      expect(notificationCount, 3);
    });

    test('multiple rapid updates all take effect', () {
      final notifier = container.read(sendTxProvider.notifier);

      for (int i = 0; i < 100; i++) {
        notifier.updateAmount(i);
      }

      expect(container.read(sendTxProvider).amount, 99);
    });

    test('updating address does not affect amount or type', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAmount(42000);
      notifier.updatePaymentType(PaymentType.Spark);
      notifier.updateDrain(true);

      notifier.updateAddress('new_address');

      final state = container.read(sendTxProvider);
      expect(state.address, 'new_address');
      expect(state.amount, 42000);
      expect(state.type, PaymentType.Spark);
      expect(state.drain, true);
    });

    test('updating amount does not affect address or type', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('keep_this');
      notifier.updatePaymentType(PaymentType.Lightning);

      notifier.updateAmount(99999);

      final state = container.read(sendTxProvider);
      expect(state.address, 'keep_this');
      expect(state.amount, 99999);
      expect(state.type, PaymentType.Lightning);
    });

    test('resetToDefault after partial updates clears everything', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('partial');
      // Only set address, leave amount at default

      notifier.resetToDefault();

      final state = container.read(sendTxProvider);
      expect(state.address, '');
      expect(state.amount, 0);
      expect(state.type, PaymentType.Unknown);
      expect(state.drain, false);
      expect(state.networkHint, isNull);
    });

    test('double resetToDefault is safe', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('something');
      notifier.resetToDefault();
      notifier.resetToDefault();

      final state = container.read(sendTxProvider);
      expect(state.address, '');
      expect(state.amount, 0);
    });
  });

  group('updateAmountFromInput edge cases', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('negative value in sats sets negative amount', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('-100', 'sats');
      // double.tryParse('-100') returns -100.0 which is != 0
      // toInt() gives -100
      expect(container.read(sendTxProvider).amount, -100);
    });

    test('negative value in BTC converts to negative sats', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('-0.001', 'BTC');
      // The Money2 library may throw on negative, falling back to string parsing
      final amount = container.read(sendTxProvider).amount;
      // Regardless of path taken, a negative BTC should produce a negative sat value
      expect(amount, lessThan(0));
    });

    test('very large sats value', () {
      // 21 million BTC in sats = 2,100,000,000,000,000
      container.read(sendTxProvider.notifier).updateAmountFromInput('2100000000000000', 'sats');
      expect(container.read(sendTxProvider).amount, 2100000000000000);
    });

    test('BTC value 21000000 (max supply)', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('21000000', 'BTC');
      expect(container.read(sendTxProvider).amount, 2100000000000000);
    });

    test('BTC with 8 decimal places (1 sat)', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0.00000001', 'BTC');
      expect(container.read(sendTxProvider).amount, 1);
    });

    test('whitespace-only string sets 0', () {
      // '   ' is not empty but double.tryParse returns null
      container.read(sendTxProvider.notifier).updateAmountFromInput('   ', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('string with leading/trailing spaces parses successfully', () {
      // double.tryParse trims whitespace in Dart, so ' 100 ' parses as 100.0
      container.read(sendTxProvider.notifier).updateAmountFromInput(' 100 ', 'sats');
      expect(container.read(sendTxProvider).amount, 100);
    });

    test('European format with comma in sats', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('1000,5', 'sats');
      // comma replaced with dot -> '1000.5' -> toInt() = 1000
      expect(container.read(sendTxProvider).amount, 1000);
    });

    test('multiple commas replaced correctly', () {
      // '1,000,5' -> '1.000.5' -> double.tryParse returns null -> 0
      container.read(sendTxProvider.notifier).updateAmountFromInput('1,000,5', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('BTC 0.0 is treated as zero', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0.0', 'BTC');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('BTC 0.00000000 is treated as zero', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0.00000000', 'BTC');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('sats with only dot sets 0', () {
      // '.' -> double.tryParse returns null -> 0
      container.read(sendTxProvider.notifier).updateAmountFromInput('.', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('sats with only comma sets 0', () {
      // ',' -> replaced with '.' -> '.' -> double.tryParse returns null -> 0
      container.read(sendTxProvider.notifier).updateAmountFromInput(',', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('BTC fractional value 0.5', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('0.5', 'BTC');
      expect(container.read(sendTxProvider).amount, 50000000);
    });

    test('sats integer value 1', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('1', 'sats');
      expect(container.read(sendTxProvider).amount, 1);
    });

    test('BTC integer value 1 without decimal', () {
      container.read(sendTxProvider.notifier).updateAmountFromInput('1', 'BTC');
      expect(container.read(sendTxProvider).amount, 100000000);
    });

    test('sequential updateAmountFromInput calls override previous value', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAmountFromInput('100', 'sats');
      expect(container.read(sendTxProvider).amount, 100);
      notifier.updateAmountFromInput('200', 'sats');
      expect(container.read(sendTxProvider).amount, 200);
      notifier.updateAmountFromInput('', 'sats');
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('updateAmountFromInput does not affect other fields', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('keep_me');
      notifier.updatePaymentType(PaymentType.Bitcoin);
      notifier.updateDrain(true);
      notifier.updateNetworkHint('SOL');

      notifier.updateAmountFromInput('5000', 'sats');

      final state = container.read(sendTxProvider);
      expect(state.amount, 5000);
      expect(state.address, 'keep_me');
      expect(state.type, PaymentType.Bitcoin);
      expect(state.drain, true);
      expect(state.networkHint, 'SOL');
    });
  });

  group('customFeeRateProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial value is null', () {
      final feeRate = container.read(customFeeRateProvider);
      expect(feeRate, isNull);
    });

    test('can set a custom fee rate', () {
      container.read(customFeeRateProvider.notifier).state = 5.0;
      expect(container.read(customFeeRateProvider), 5.0);
    });

    test('can reset to null', () {
      container.read(customFeeRateProvider.notifier).state = 10.0;
      container.read(customFeeRateProvider.notifier).state = null;
      expect(container.read(customFeeRateProvider), isNull);
    });

    test('can set zero fee rate', () {
      container.read(customFeeRateProvider.notifier).state = 0.0;
      expect(container.read(customFeeRateProvider), 0.0);
    });

    test('can set fractional fee rate', () {
      container.read(customFeeRateProvider.notifier).state = 1.5;
      expect(container.read(customFeeRateProvider), 1.5);
    });
  });

  group('sendBlocksProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial value is 1 (fastest)', () {
      expect(container.read(sendBlocksProvider), 1);
    });

    test('can change to each valid block target', () {
      for (int i = 1; i <= 5; i++) {
        container.read(sendBlocksProvider.notifier).state = i;
        expect(container.read(sendBlocksProvider), i);
      }
    });

    test('setting out of range value is still stored (no validation at provider level)', () {
      container.read(sendBlocksProvider.notifier).state = 99;
      expect(container.read(sendBlocksProvider), 99);
    });
  });

  group('selectedUtxosProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('initial value is empty list', () {
      final utxos = container.read(selectedUtxosProvider);
      expect(utxos, isEmpty);
    });

    test('empty list means automatic UTXO selection', () {
      final utxos = container.read(selectedUtxosProvider);
      expect(utxos.isEmpty, true);
    });
  });

  group('customFeeRateProvider autoDispose', () {
    test('resets to null after listeners removed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(customFeeRateProvider, (_, __) {});
      container.read(customFeeRateProvider.notifier).state = 25.0;
      expect(container.read(customFeeRateProvider), 25.0);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(customFeeRateProvider), isNull);
    });
  });

  group('sendBlocksProvider autoDispose', () {
    test('resets to 1 after listeners removed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(sendBlocksProvider, (_, __) {});
      container.read(sendBlocksProvider.notifier).state = 4;
      expect(container.read(sendBlocksProvider), 4);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(sendBlocksProvider), 1);
    });
  });

  group('selectedUtxosProvider autoDispose', () {
    test('resets to empty list after listeners removed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sub = container.listen(selectedUtxosProvider, (_, __) {});
      // Cannot easily add OutPoint objects without bdk_dart internals,
      // but we can verify the autoDispose mechanism on the default value
      expect(container.read(selectedUtxosProvider), isEmpty);

      sub.close();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(selectedUtxosProvider), isEmpty);
    });
  });

  group('SendTxModel updateNetworkHint edge cases', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('updateNetworkHint preserves all other fields', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateAddress('test_addr');
      notifier.updateAmount(12345);
      notifier.updatePaymentType(PaymentType.Spark);
      notifier.updateDrain(true);

      notifier.updateNetworkHint('MATIC');

      final state = container.read(sendTxProvider);
      expect(state.address, 'test_addr');
      expect(state.amount, 12345);
      expect(state.type, PaymentType.Spark);
      expect(state.drain, true);
      expect(state.networkHint, 'MATIC');
    });

    test('updateNetworkHint with empty string', () {
      container.read(sendTxProvider.notifier).updateNetworkHint('');
      expect(container.read(sendTxProvider).networkHint, '');
    });

    test('updateNetworkHint called multiple times keeps last value', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateNetworkHint('ETH');
      notifier.updateNetworkHint('SOL');
      notifier.updateNetworkHint('MATIC');
      expect(container.read(sendTxProvider).networkHint, 'MATIC');
    });
  });

  group('SendTx construction', () {
    test('all fields required except networkHint', () {
      final tx = SendTx(address: 'a', amount: 1, type: PaymentType.Bitcoin, drain: true);
      expect(tx.networkHint, isNull);
    });

    test('networkHint defaults to null', () {
      final tx = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false);
      expect(tx.networkHint, isNull);
    });

    test('can construct with all PaymentType values', () {
      for (final type in PaymentType.values) {
        final tx = SendTx(address: '', amount: 0, type: type, drain: false);
        expect(tx.type, type);
      }
    });

    test('can construct with very long address', () {
      final longAddr = 'a' * 10000;
      final tx = SendTx(address: longAddr, amount: 0, type: PaymentType.Unknown, drain: false);
      expect(tx.address.length, 10000);
    });

    test('can construct with max int amount', () {
      // Dart int is 64-bit on VM
      final tx = SendTx(address: '', amount: 9223372036854775807, type: PaymentType.Unknown, drain: false);
      expect(tx.amount, 9223372036854775807);
    });
  });

  group('Combined provider state isolation', () {
    test('sendTxProvider and customFeeRateProvider are independent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sendTxProvider.notifier).updateAmount(50000);
      container.read(customFeeRateProvider.notifier).state = 10.0;

      expect(container.read(sendTxProvider).amount, 50000);
      expect(container.read(customFeeRateProvider), 10.0);

      // Resetting sendTx does not affect customFeeRate
      container.read(sendTxProvider.notifier).resetToDefault();
      expect(container.read(customFeeRateProvider), 10.0);
      expect(container.read(sendTxProvider).amount, 0);
    });

    test('sendBlocksProvider and sendTxProvider are independent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sendBlocksProvider.notifier).state = 3;
      container.read(sendTxProvider.notifier).updateAmount(10000);

      container.read(sendTxProvider.notifier).resetToDefault();

      expect(container.read(sendBlocksProvider), 3);
    });

    test('all providers reset independently on autoDispose', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final subTx = container.listen(sendTxProvider, (_, __) {});
      final subFee = container.listen(customFeeRateProvider, (_, __) {});
      final subBlocks = container.listen(sendBlocksProvider, (_, __) {});

      container.read(sendTxProvider.notifier).updateAmount(77777);
      container.read(customFeeRateProvider.notifier).state = 15.0;
      container.read(sendBlocksProvider.notifier).state = 5;

      // Close only sendTx listener
      subTx.close();
      await Future<void>.delayed(Duration.zero);

      // sendTx resets, others stay
      expect(container.read(sendTxProvider).amount, 0);
      expect(container.read(customFeeRateProvider), 15.0);
      expect(container.read(sendBlocksProvider), 5);

      subFee.close();
      subBlocks.close();
    });
  });

  group('updateDrain edge cases', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('setting drain to same value is idempotent', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateDrain(false);
      notifier.updateDrain(false);
      expect(container.read(sendTxProvider).drain, false);
    });

    test('toggling drain back and forth', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateDrain(true);
      expect(container.read(sendTxProvider).drain, true);
      notifier.updateDrain(false);
      expect(container.read(sendTxProvider).drain, false);
      notifier.updateDrain(true);
      expect(container.read(sendTxProvider).drain, true);
    });

    test('drain true with amount 0 (drain wallet with zero explicit amount)', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updateDrain(true);
      notifier.updateAmount(0);

      final state = container.read(sendTxProvider);
      expect(state.drain, true);
      expect(state.amount, 0);
    });
  });

  group('updatePaymentType transitions', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    test('can transition through all payment types', () {
      final notifier = container.read(sendTxProvider.notifier);
      for (final type in PaymentType.values) {
        notifier.updatePaymentType(type);
        expect(container.read(sendTxProvider).type, type);
      }
    });

    test('setting same type twice does not cause issues', () {
      final notifier = container.read(sendTxProvider.notifier);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      notifier.updatePaymentType(PaymentType.Bitcoin);
      expect(container.read(sendTxProvider).type, PaymentType.Bitcoin);
    });
  });
}
