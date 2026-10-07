import 'package:kute/models/address_model.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

final initialAddressesProvider = FutureProvider<Address>((ref) async {
  final settings = ref.watch(settingsProvider);
  final activeWallet = settings.activeWallet;

  if (activeWallet == null) {
    return Address(bitcoinAddressIndex: 0, bitcoinAddress: '');
  }

  if (activeWallet.isExternalAddress) {
    final externalAddress = await AuthModel().getExternalAddress(activeWallet.id);
    return Address(
      bitcoinAddressIndex: 0,
      bitcoinAddress: externalAddress ?? '',
    );
  }

  final box = await Hive.openBox('addresses');
  final bitcoinAddressIndex =
      box.get('bitcoinIndex_${activeWallet.id}', defaultValue: 0);
  final cached =
      box.get('bitcoinAddress_${activeWallet.id}', defaultValue: '') as String;

  String bitcoinAddress = cached;

  // Spark wallets: read the cached deposit address. The provider is
  // wired with `newAddress: true` on its first run, so the very
  // first read after a cold start (or after the push pipeline
  // invalidates it on a `claimedDeposits` event) lands a guaranteed
  // fresh address. Subsequent reads return the SAME address — what
  // the user wants when they share an address and reopen the
  // receive screen a minute later. We deliberately do NOT
  // `ref.refresh` here: a refresh on every `initialAddressesProvider`
  // rebuild (which fires on any settings mutation) would burn
  // through fresh addresses for no benefit and confuse a sender.
  //
  // BDK wallets: `lastUsedAddressProviderString` is autoDispose and
  // calls `revealNextAddress` + `persist` under the hood, which
  // after a full-scan correctly returns the next address past every
  // scriptPubKey BDK has seen used. Plain `ref.read` is enough —
  // each fresh listener pass re-runs the autoDispose body.
  try {
    if (activeWallet.sparkEnabled) {
      bitcoinAddress = await ref.read(getSparkBitcoinAddressProvider.future);
    } else {
      bitcoinAddress = await ref.read(lastUsedAddressProviderString.future);
    }
    if (bitcoinAddress.isNotEmpty) {
      box.put('bitcoinAddress_${activeWallet.id}', bitcoinAddress);
    }
  } catch (_) {
    // Fall through with whatever cached value we have. UI shows
    // either the previous address or empty; next sync retries.
  }

  final breezPrefs = ref.read(breezPreferencesProvider);
  final lightningAddress = await breezPrefs.getLnAddress(activeWallet.id);

  return Address(
    bitcoinAddressIndex: bitcoinAddressIndex,
    bitcoinAddress: bitcoinAddress,
    lightningAddress: lightningAddress,
  );
});

final addressProvider = StateNotifierProvider<AddressModel, Address>((ref) {
  final initialSettings = ref.watch(initialAddressesProvider);
  final activeWalletId = ref.watch(settingsProvider).activeWalletId;

  return AddressModel(
    initialSettings.when(
      data: (addresses) => addresses,
      loading: () => Address(
        bitcoinAddressIndex: 0,
        bitcoinAddress: '',
      ),
      error: (Object error, StackTrace stackTrace) {
        return Address(
          bitcoinAddressIndex: 0,
          bitcoinAddress: '',
        );
      },
    ),
    activeWalletId,
    ref,
  );
});

class AddressModel extends StateNotifier<Address> {
  final String? walletId;
  final Ref ref;

  AddressModel(super.state, this.walletId, this.ref);

  Future<void> setBitcoinAddress(int index, String address) async {
    if (walletId == null) return;

    final box = await Hive.openBox('addresses');
    if (!mounted) return;

    box.put('bitcoinIndex_$walletId', index);
    box.put('bitcoinAddress_$walletId', address);

    state = state.copyWith(
      bitcoinAddressIndex: index,
      bitcoinAddress: address,
    );
  }

  Future<void> updateLightningAddress(String? address) async {
    if (walletId == null || !mounted) return;

    final breezPrefs = ref.read(breezPreferencesProvider);
    await breezPrefs.setLnAddress(walletId!, address);

    state = state.copyWith(lightningAddress: address);
  }
}