import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:money2/money2.dart';

enum PaymentType {
  Bitcoin,
  Lightning,
  Spark,
  Unknown,
  NonNative
}

class SendTxModel extends StateNotifier<SendTx> {
  SendTxModel(super.state);

  void updateAddress(String address) {
    state = state.copyWith(address: address);
  }

  void resetToDefault() {
    state = SendTx(address: '', amount: 0, type: PaymentType.Unknown, drain: false, networkHint: null);
  }

  void updateAmount(int amount) {
    state = state.copyWith(amount: amount);
  }

  void updatePaymentType(PaymentType type) {
    state = state.copyWith(type: type);
  }

  void updateDrain(bool drain) {
    state = state.copyWith(drain: drain);
  }

  void updateNetworkHint(String? hint) {
    state = SendTx(
      address: state.address,
      amount: state.amount,
      type: state.type,
      drain: state.drain,
      networkHint: hint,
    );
  }
  void updateAmountFromInput(String value, String denomination) {
    if (value.isEmpty) {
      state = state.copyWith(amount: 0);
      return;
    }

    // Handle potential comma inputs (e.g. European format)
    final cleanValue = value.replaceAll(',', '.');
    final double? amountNum = double.tryParse(cleanValue);

    if (amountNum == null || amountNum == 0) {
      state = state.copyWith(amount: 0);
      return;
    }

    int amountSats;

    switch (denomination) {
      case 'sats':
      // Direct integer conversion
        amountSats = amountNum.toInt();
        break;
      case 'BTC':
      // Use Money2 to safely convert BTC (Major) -> Sats (Minor)
      // This avoids floating point errors (e.g. 0.1 + 0.2 != 0.3)
      // Note: Ensure 'BTC' is registered in your app initialization or use a fallback
        try {
          final btcMoney = Money.fromNum(amountNum, isoCode: 'BTC');
          amountSats = btcMoney.minorUnits.toInt();
        } catch (e) {
          // Fallback: use string parsing to avoid floating-point precision errors
          final parts = amountNum.toStringAsFixed(8).split('.');
          amountSats = int.parse(parts[0]) * 100000000 + int.parse(parts[1]);
        }
        break;
      default:
        amountSats = 0;
    }

    state = state.copyWith(amount: amountSats);
  }
}

class SendTx {
  final String address;
  final int amount;
  final PaymentType type;
  final bool drain;
  final String? networkHint;

  SendTx({
    required this.address,
    required this.amount,
    required this.type,
    required this.drain,
    this.networkHint,
  });

  SendTx copyWith({
    String? address,
    int? amount,
    PaymentType? type,
    bool? drain,
    String? networkHint,
  }) {
    return SendTx(
      address: address ?? this.address,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      drain: drain ?? this.drain,
      networkHint: networkHint ?? this.networkHint,
    );
  }
}