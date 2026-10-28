import 'package:hive_ce/hive.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final isBitcoinInputProvider = StateProvider.autoDispose<bool>((ref) => true);

const kReceiveUnitPrefKey = 'receive_input_currency';

/// Remembers the last unit the user PICKED on the Receive amount field
/// (settings Hive box). autoDispose used to forget a fiat pick the
/// moment the screen closed — every open reset to BTC/Sats.
String? _rememberedReceiveUnit() {
  try {
    if (Hive.isBoxOpen('settings')) {
      final v = Hive.box('settings').get(kReceiveUnitPrefKey);
      if (v is String && v.isNotEmpty) return v;
    }
  } catch (_) {}
  return null;
}

final defaultDropdownValueProvider = StateProvider.autoDispose<String>((ref) {
  final remembered = _rememberedReceiveUnit();
  if (remembered != null) return remembered;
  final format = ref.watch(settingsProvider).btcFormat;
  switch (format) {
    case 'BTC':
      return 'BTC';
    case 'sats':
      return 'Sats';
    default:
      return 'BTC';
  }
});

/// The Bitcoin unit an amount entry opens in: BTC when Settings →
/// Bitcoin unit is BTC, sats otherwise.
String bitcoinEntryUnit(String btcFormat) =>
    btcFormat == 'BTC' ? 'BTC' : 'Sats';

/// Entry unit on the Send amount step. Every open starts in the Bitcoin
/// unit from Settings — never fiat, never the unit remembered on Receive,
/// never the unit flipped to on a previous send (autoDispose forgets it
/// when the send closes). The user can still pick fiat within the flow.
final inputCurrencyProvider = StateProvider.autoDispose<String>((ref) =>
    bitcoinEntryUnit(ref.watch(settingsProvider.select((s) => s.btcFormat))));

/// Entry unit on the Receive amount field: the last unit picked there
/// (see [kReceiveUnitPrefKey]), else the Bitcoin unit from Settings.
final receiveInputCurrencyProvider = StateProvider.autoDispose<String>(
    (ref) => ref.watch(defaultDropdownValueProvider));
final inputAmountProvider = StateProvider<String>((ref) => '0.0');
