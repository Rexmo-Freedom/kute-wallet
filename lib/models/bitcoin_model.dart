import 'dart:convert';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/onchain/esplora_fallback.dart';
import 'package:kute/services/bitcoin/bitcoin_fee_estimate_service.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// Dart holds data only. SQLite, sync, signing and transaction construction
/// execute on the platform's serial native BDK executor.
class BitcoinModel {
  final Bitcoin config;
  BitcoinModel(this.config);

  Future<void> sync() => _withFallback(() => config.session.sync());
  Future<void> fullScan() =>
      _withFallback(() => config.session.sync(fullScan: true));

  /// A sync that cannot reach its Esplora host closes this session and
  /// records the failure, so the providers rebuild the wallet against the
  /// alternate host and the next sync goes through. The failure is still
  /// thrown to this caller; the retry is the next scheduled sync.
  Future<void> _withFallback(Future<void> Function() run) async {
    try {
      await run();
    } on OnchainException catch (e) {
      final url = config.electrumUrl;
      if (url == null ||
          !EsploraFallback.isNetworkFailure(e.code) ||
          EsploraFallback.alternate(url) == null ||
          EsploraFallback.instance.effectiveUrl(url) != url) {
        rethrow;
      }
      try {
        await config.session.close();
      } catch (_) {
        // The session may already be gone; the rebuild opens a fresh one.
      }
      EsploraFallback.instance.markNetworkFailure(url);
      rethrow;
    }
  }

  Future<AddressInfo> _address(String mode, [int? index]) async =>
      AddressInfo.fromMap(await config.session.call('address', {
        'mode': mode,
        'keychain': 'external',
        if (index != null) 'index': index,
      }));
  Future<AddressInfo> getNextUnusedAddress() => _address('nextUnused');
  Future<int> getAddress() async => (await _address('revealNext')).index;
  Future<String> getAddressString() async =>
      (await _address('revealNext')).address.toString();
  Future<String> getCurrentAddress(int index) async =>
      (await _address('peek', index)).address.toString();
  Future<AddressInfo> getAddressInfo(int index) => _address('peek', index);

  List<TxDetails> getTransactions() => config.session.snapshot.transactions;
  Balance getBalance() => config.session.snapshot.balance;
  List<LocalOutput> listUnspent() => config.session.snapshot.utxos;

  Future<Psbt> signBitcoinTransaction(Psbt psbt) async {
    LedgerOperationScope.assertHotAllowed(HotSigningAction.bdkSoftwareSign);
    return Psbt.fromMap(
        await config.session.call('sign', {'psbt': psbt.serialize()}));
  }

  /// Recommended fee rates. Timeout, retries and the last known good
  /// fallback live in [BitcoinFeeEstimateService]; a wallet is not needed.
  Future<BitcoinFeeModel> estimateFeeRate() =>
      BitcoinFeeEstimateService.instance.fetch();

  /// Native refuses a blank or unparsable address, a non-positive fee rate
  /// and — outside a drain — a non-positive amount, and reports all three
  /// as one generic code. The send flow could then only word that as a
  /// single "check what you entered" sentence on its fee row, naming
  /// nothing the user could correct. Each argument is checked here instead,
  /// with a code that says WHICH input is wrong. The reviewed amount, fee,
  /// inputs, outputs, network and wallet still come from the native build.
  static void _assertBuildable(TransactionBuilder transaction,
      {required bool drain}) {
    final address = transaction.outAddress.trim();
    // A `bitcoin:` URI or a BIP21 query reaching here means a caller
    // skipped `stripBitcoinAddress`; native reads it as a bad address.
    if (address.isEmpty ||
        address.contains(':') ||
        address.contains('?') ||
        address.contains(RegExp(r'\s'))) {
      throw const OnchainException('invalid_address');
    }
    if (!transaction.fee.isFinite || transaction.fee <= 0) {
      throw const OnchainException('invalid_fee_rate');
    }
    if (transaction.amount < 0 || (!drain && transaction.amount <= 0)) {
      throw const OnchainException('invalid_amount');
    }
  }

  Future<Psbt> _build(TransactionBuilder transaction,
      {required bool drain}) async {
    _assertBuildable(transaction, drain: drain);
    return Psbt.fromMap(await config.session.call('build', {
      'address': transaction.outAddress.trim(),
      'amountSats': transaction.amount,
      'feeRateSatVb': transaction.fee.ceil(),
      'drain': drain,
      if (transaction.selectedUtxos?.isNotEmpty == true)
        'selectedUtxos': transaction.selectedUtxos!
            .map((point) => {
                  'txid': point.txid.toString(),
                  'vout': point.vout,
                })
            .toList(),
    }));
  }

  Future<Psbt> buildBitcoinTransaction(TransactionBuilder transaction) =>
      _build(transaction, drain: false);
  Future<Psbt> drainWalletBitcoinTransaction(TransactionBuilder transaction) =>
      _build(transaction, drain: true);
  Future<Psbt> bumpFeeTransaction(BumpFeeTransactionBuilder transaction) async {
    if (!transaction.fee.isFinite || transaction.fee <= 0) {
      throw const OnchainException('invalid_fee_rate');
    }
    return Psbt.fromMap(await config.session.call('bump', {
      'txid': transaction.txid,
      'feeRateSatVb': transaction.fee.ceil(),
    }));
  }

  Future<String> _broadcast(String payload, String format) async {
    final result = await config.session.call('broadcast', {
      'payload': payload,
      'format': format,
    });
    return (result! as Map)['txid'] as String;
  }

  Future<String> broadcastBitcoinTransaction(Psbt signedPsbt) =>
      _broadcast(signedPsbt.serialize(), 'psbt');

  /// Hardware signers may return hex or base64, either raw tx or PSBT.
  Future<String> broadcastSignedTransaction(String input) {
    final clean = input.trim().replaceAll(RegExp(r'\s+'), '');
    List<int> bytes;
    if (clean.isNotEmpty &&
        clean.length.isEven &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
      bytes = [
        for (var i = 0; i < clean.length; i += 2)
          int.parse(clean.substring(i, i + 2), radix: 16)
      ];
    } else {
      try {
        bytes = base64Decode(clean);
      } catch (_) {
        throw const FormatException('Input is neither valid Hex nor Base64');
      }
    }
    if (bytes.isEmpty) throw const FormatException('Empty transaction');
    final isPsbt = bytes.length >= 5 &&
        bytes[0] == 0x70 &&
        bytes[1] == 0x73 &&
        bytes[2] == 0x62 &&
        bytes[3] == 0x74 &&
        bytes[4] == 0xff;
    return isPsbt
        ? _broadcast(base64Encode(bytes), 'psbt')
        : _broadcast(
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
            'hex');
  }
}

class Bitcoin {
  final NativeWalletSession session;
  final Network network;
  bool needsFullScan;

  /// The Esplora host this session was opened on, for the fallback.
  final String? electrumUrl;
  String get walletId => session.walletId;
  Bitcoin(this.session, this.network,
      {this.needsFullScan = false, this.electrumUrl});
}

class TransactionBuilder {
  final int amount;
  final String outAddress;
  final double fee;
  final List<OutPoint>? selectedUtxos;

  TransactionBuilder(this.amount, this.outAddress, this.fee,
      {this.selectedUtxos});
}

class BumpFeeTransactionBuilder {
  final String txid;
  final double fee;

  BumpFeeTransactionBuilder({required this.txid, required this.fee});
}

class BitcoinFeeModel {
  final double fastestFee;
  final double halfHourFee;
  final double hourFee;
  final double economyFee;
  final double minimumFee;

  /// True when these are the last known good rates served because the
  /// live estimate failed; the UI says so instead of presenting them as live.
  final bool isStale;

  BitcoinFeeModel(this.fastestFee, this.halfHourFee, this.hourFee,
      this.economyFee, this.minimumFee,
      {this.isStale = false});
}
