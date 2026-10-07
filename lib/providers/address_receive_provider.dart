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

final inputCurrencyProvider = StateProvider.autoDispose<String>((ref) => ref.watch(defaultDropdownValueProvider));
final inputAmountProvider = StateProvider<String>((ref) => '0.0');
