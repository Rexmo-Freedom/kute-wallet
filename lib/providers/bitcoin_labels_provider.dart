import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/providers/wallet_scope_provider.dart';

/// Labels are local wallet metadata, never sent to analytics or explorers.
/// Use the existing settings box so complete app wipe removes them too.
final bitcoinLabelsWalletIdProvider = Provider<String?>((ref) {
  final wallet = scopedOperationalWallet(ref);
  return wallet != null && (wallet.usesBdk || wallet.isExternalAddress)
      ? wallet.id
      : null;
});

final bitcoinLabelsProvider =
    StateNotifierProvider.family<BitcoinLabels, Map<String, String>, String>(
        (ref, walletId) => BitcoinLabels(walletId));

class BitcoinLabels extends StateNotifier<Map<String, String>> {
  BitcoinLabels(this.walletId) : super(_read(walletId));
  final String walletId;
  static String _key(String walletId) => 'bitcoin_labels_v1:$walletId';
  static Map<String, String> _read(String walletId) {
    final value = Hive.box('settings').get(_key(walletId));
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String
    };
  }

  Future<void> setLabel(String key, String label) async {
    final text = label.trim();
    if (text.length > 100) throw ArgumentError('Label exceeds 100 characters');
    final updated = {...state};
    if (text.isEmpty) {
      updated.remove(key);
    } else {
      updated[key] = text;
    }
    await Hive.box('settings').put(_key(walletId), updated);
    if (mounted) state = updated;
  }
}

String bitcoinTransactionLabelKey(String txid) => 'tx:$txid';
String bitcoinCoinLabelKey(OutPoint outpoint) =>
    'coin:${outpoint.txid}:${outpoint.vout}';

/// An explicit coin label wins. Otherwise the creating transaction's label
/// applies dynamically, including change outputs from an outgoing payment.
/// Relabelling a transaction therefore updates inherited labels, even for coins
/// discovered by a later sync, without overwriting an intentional coin label.
String? bitcoinCoinLabel(Map<String, String> labels, OutPoint outpoint) =>
    labels[bitcoinCoinLabelKey(outpoint)] ??
    labels[bitcoinTransactionLabelKey(outpoint.txid.toString())];
