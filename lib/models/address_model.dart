import 'package:kute/models/send_tx_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';



class AddressAndAmount {
  final String address;
  final int? amount;
  final PaymentType type;
  final String? assetId;

  AddressAndAmount(this.address, this.amount, this.assetId, {this.type = PaymentType.Unknown});
}

class Address {
  final int bitcoinAddressIndex;
  final String bitcoinAddress;
  final String? lightningAddress; // Added field

  Address({
    required this.bitcoinAddressIndex,
    required this.bitcoinAddress,
    this.lightningAddress,
  });

  // Helper for state updates
  Address copyWith({
    int? bitcoinAddressIndex,
    String? bitcoinAddress,
    String? lightningAddress,
  }) {
    return Address(
      bitcoinAddressIndex: bitcoinAddressIndex ?? this.bitcoinAddressIndex,
      bitcoinAddress: bitcoinAddress ?? this.bitcoinAddress,
      lightningAddress: lightningAddress ?? this.lightningAddress,
    );
  }
}

class AddressModel extends StateNotifier<Address> {
  final String? walletId;

  // Pass walletId to the notifier
  AddressModel(super.state, this.walletId);

  Future<void> setBitcoinAddress(int index, String address) async {
    if (walletId == null) return;

    final box = await Hive.openBox('addresses');

    if (!mounted) return;

    // Use wallet-specific keys
    box.put('bitcoinIndex_$walletId', index);
    box.put('bitcoinAddress_$walletId', address);

    state = Address(
      bitcoinAddressIndex: index,
      bitcoinAddress: address,
    );
  }
}