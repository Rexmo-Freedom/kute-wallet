import 'package:hive_ce/hive.dart';

part 'balance_model.g.dart';

@HiveType(typeId: 26)
class WalletBalance {
  @HiveField(0)
  final int onChainBtcBalance;

  @HiveField(1)
  final int sparkBitcoinbalance;

  /// Deprecated: the Flashnet USDB Earn product was removed and nothing
  /// writes this any more, so it is always 0 going forward. Retained so
  /// the Hive field numbering and the JSON cache shape stay stable
  /// without a build_runner pass; never reuse field index 2.
  @HiveField(2)
  final int usdbBalance; // USDB base units (6 decimals)

  bool get isEmpty {
    return onChainBtcBalance == 0 && sparkBitcoinbalance == 0;
  }

  WalletBalance({
    required this.onChainBtcBalance,
    required this.sparkBitcoinbalance,
    this.usdbBalance = 0,
  });

  WalletBalance copyWith({
    int? onChainBtcBalance,
    int? sparkBitcoinbalance,
    int? usdbBalance,
  }) {
    return WalletBalance(
      onChainBtcBalance: onChainBtcBalance ?? this.onChainBtcBalance,
      sparkBitcoinbalance: sparkBitcoinbalance ?? this.sparkBitcoinbalance,
      usdbBalance: usdbBalance ?? this.usdbBalance,
    );
  }

  factory WalletBalance.empty() {
    return WalletBalance(
      onChainBtcBalance: 0,
      sparkBitcoinbalance: 0,
      usdbBalance: 0,
    );
  }

  // Value-equality so StateNotifier setters can short-circuit
  // notification when sync produces an identical balance — the
  // every-5-seconds refresh on a wallet that hasn't moved otherwise
  // cascades a rebuild into every Consumer of the active wallet's
  // balance, every tick, for nothing.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletBalance &&
          other.onChainBtcBalance == onChainBtcBalance &&
          other.sparkBitcoinbalance == sparkBitcoinbalance &&
          other.usdbBalance == usdbBalance);

  @override
  int get hashCode =>
      Object.hash(onChainBtcBalance, sparkBitcoinbalance, usdbBalance);
}

class BalanceChange {
  final String asset;
  final int amount;

  BalanceChange({required this.asset, required this.amount});
}