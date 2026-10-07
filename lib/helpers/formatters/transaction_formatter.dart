import 'package:kute/models/onchain_types.dart' as bdk;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';

String transactionAmountInFiat(bdk.TxDetails transaction, WidgetRef ref) {
  final currency = ref.watch(settingsProvider).currency;

  int satsAmount;
  if (transaction.received.toSat() == 0 && transaction.sent.toSat() > 0) {
    satsAmount = transaction.sent.toSat();
  } else if (transaction.received.toSat() > 0 && transaction.sent.toSat() == 0) {
    satsAmount = transaction.received.toSat();
  } else {
    satsAmount = (transaction.received.toSat() - transaction.sent.toSat()).abs();
  }

  final formattedFiat = ref.watch(conversionToFiatProvider(satsAmount));

  return '$formattedFiat $currency';
}

String transactionAmount(bdk.TxDetails transaction, WidgetRef ref) {
  int total;
  if (transaction.received.toSat() == 0 && transaction.sent.toSat() > 0) {
    total = transaction.sent.toSat();
  } else if (transaction.received.toSat() > 0 && transaction.sent.toSat() == 0) {
    total = transaction.received.toSat();
  } else {
    total = (transaction.received.toSat() - transaction.sent.toSat()).abs();
  }

  return ref.watch(conversionProvider(total));
}
