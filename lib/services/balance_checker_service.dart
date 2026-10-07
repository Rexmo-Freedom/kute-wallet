import 'dart:async';
import 'dart:typed_data';

import 'package:kute/models/onchain_types.dart' show Network;
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a single derivation path's balance check result.
class DerivationBalance {
  final String label;
  final String derivationPath;
  final String addressType; // 'legacy', 'nested_segwit', 'native_segwit'
  final int balanceSats;
  final String? sampleAddress;

  /// Bare account-level extended public key for this path (e.g.
  /// `xpub6...`). Derived from the descriptor's secret key during the
  /// scan so callers can register the funded path as a watch-only
  /// wallet without re-touching the mnemonic. Empty when derivation
  /// failed. An incomplete scan never reports that path as empty.
  final String xpub;

  /// App scriptType slug matching the xpub-import / `BitcoinConfig`
  /// flow: `'bip44'` (legacy), `'bip49'` (nested segwit), `'bip84'`
  /// (native segwit). Mirrors `_scriptTypeString` in the xpub-import
  /// screen so a watch-only wallet built from this record derives the
  /// SAME addresses the funds actually live at.
  final String scriptType;

  const DerivationBalance({
    required this.label,
    required this.derivationPath,
    required this.addressType,
    required this.balanceSats,
    this.sampleAddress,
    this.xpub = '',
    this.scriptType = '',
  });

  bool get hasBalance => balanceSats > 0;
}

/// Maps the scanner's `addressType` to the app's scriptType slug used
/// everywhere else (xpub-import `_scriptTypeString`, `WalletConfig.scriptType`,
/// `BitcoinConfigModel`): legacy→bip44, nested_segwit→bip49,
/// native_segwit→bip84. Defaults to bip84 for any unknown type.
String scriptTypeForAddressType(String addressType) {
  switch (addressType) {
    case 'legacy':
      return 'bip44';
    case 'nested_segwit':
      return 'bip49';
    case 'native_segwit':
    default:
      return 'bip84';
  }
}

/// Overall result of a multi-path balance check.
class BalanceCheckResult {
  final List<DerivationBalance> paths;
  final bool isComplete;
  final String? error;

  const BalanceCheckResult({
    this.paths = const [],
    this.isComplete = false,
    this.error,
  });

  int get totalBalance => paths.fold(0, (sum, p) => sum + p.balanceSats);
  bool get hasAnyBalance => paths.any((p) => p.hasBalance);
  List<DerivationBalance> get pathsWithBalance =>
      paths.where((p) => p.hasBalance).toList();
}

/// State for the balance checking process.
class BalanceCheckState {
  final bool isChecking;
  final int checkedPaths;
  final int totalPaths;
  final BalanceCheckResult? result;

  const BalanceCheckState({
    this.isChecking = false,
    this.checkedPaths = 0,
    this.totalPaths = 3,
    this.result,
  });

  double get progress => totalPaths > 0 ? checkedPaths / totalPaths : 0;

  BalanceCheckState copyWith({
    bool? isChecking,
    int? checkedPaths,
    int? totalPaths,
    BalanceCheckResult? result,
  }) {
    return BalanceCheckState(
      isChecking: isChecking ?? this.isChecking,
      checkedPaths: checkedPaths ?? this.checkedPaths,
      totalPaths: totalPaths ?? this.totalPaths,
      result: result ?? this.result,
    );
  }
}

/// Serialized descriptors cross the platform boundary; BDK handles never do.
typedef RecoveryDescriptors = ({
  String external,
  String internal,
  String xpub,
});

typedef RecoveryDescriptorBuilder = FutureOr<RecoveryDescriptors> Function(
  String mnemonic,
  String addressType,
);
typedef RecoveryXpubDescriptorBuilder = FutureOr<RecoveryDescriptors> Function(
  String xpub,
  String scriptType,
);

/// Checks existing on-chain balances during wallet recovery. Native BDK owns
/// each temporary database until scanning, signing and cleanup have finished.
class BalanceCheckerService extends StateNotifier<BalanceCheckState> {
  final String electrumUrl;
  final NativeOnchainService _nativeService;
  final Future<String> Function() _directoryPath;
  final RecoveryDescriptorBuilder? _descriptorBuilder;
  final RecoveryXpubDescriptorBuilder? _xpubDescriptorBuilder;
  static int _temporarySequence = 0;
  static const _incompleteMessage =
      'Could not check all Bitcoin addresses. Please try again.';

  BalanceCheckerService({
    required this.electrumUrl,
    NativeOnchainService? nativeService,
    Future<String> Function()? directoryPath,
    RecoveryDescriptorBuilder? descriptorBuilder,
    RecoveryXpubDescriptorBuilder? xpubDescriptorBuilder,
  })  : _nativeService = nativeService ?? NativeOnchainService.instance,
        _directoryPath = directoryPath ?? _documentsPath,
        _descriptorBuilder = descriptorBuilder,
        _xpubDescriptorBuilder = xpubDescriptorBuilder,
        super(const BalanceCheckState());

  static Future<String> _documentsPath() async =>
      (await getApplicationDocumentsDirectory()).path;

  /// A failed path is unknown, never a successful zero-balance result.
  Future<BalanceCheckResult> checkAllPaths(String mnemonic) async {
    if (state.isChecking) throw const OnchainException('busy');
    state = const BalanceCheckState(isChecking: true);
    final results = <DerivationBalance>[];
    const paths = [
      (
        label: 'Legacy (P2PKH)',
        path: "m/44'/0'/0'",
        type: 'legacy',
      ),
      (
        label: 'Nested SegWit (P2SH)',
        path: "m/49'/0'/0'",
        type: 'nested_segwit',
      ),
      (
        label: 'Native SegWit (P2WPKH)',
        path: "m/84'/0'/0'",
        type: 'native_segwit',
      ),
    ];
    try {
      for (final path in paths) {
        state = state.copyWith(checkedPaths: results.length);
        results.add(await _checkPath(mnemonic,
            label: path.label,
            derivationPath: path.path,
            addressType: path.type));
      }
      final result = BalanceCheckResult(
          paths: List.unmodifiable(results), isComplete: true);
      state = state.copyWith(
          isChecking: false,
          checkedPaths: results.length,
          result: result);
      return result;
    } catch (_) {
      final result = BalanceCheckResult(
          paths: List.unmodifiable(results),
          isComplete: false,
          error: _incompleteMessage);
      if (mounted) {
        state = state.copyWith(
            isChecking: false,
            checkedPaths: results.length,
            result: result);
      }
      return result;
    }
  }

  Future<DerivationBalance> _checkPath(
    String mnemonic, {
    required String label,
    required String derivationPath,
    required String addressType,
  }) async {
    final descriptors =
        await (_descriptorBuilder ?? _mnemonicDescriptors)(mnemonic, addressType);
    if (descriptors.xpub.isEmpty) {
      throw const OnchainException('invalid_request');
    }
    return _withTemporaryWallet('bdk_temp_check', descriptors, (model) async {
      await model.fullScan();
      final totalSats = model.getBalance().total.toSat();
      final sampleAddress =
          totalSats > 0 ? await model.getCurrentAddress(0) : null;
      return DerivationBalance(
          label: label,
          derivationPath: derivationPath,
          addressType: addressType,
          balanceSats: totalSats,
          sampleAddress: sampleAddress,
          xpub: descriptors.xpub,
          scriptType: scriptTypeForAddressType(addressType));
    });
  }

  Future<T> _withTemporaryWallet<T>(
      String prefix,
      RecoveryDescriptors descriptors,
      Future<T> Function(BitcoinModel) operation) async {
    final directory = await _directoryPath();
    final id =
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_temporarySequence++}';
    final session = await _nativeService.open(
        walletId: id,
        dbPath: '$directory/$id.sqlite',
        descriptor: descriptors.external,
        changeDescriptor: descriptors.internal,
        network: 'bitcoin',
        endpoint: OnchainEndpoint.fromStored(electrumUrl),
        temporary: true);
    try {
      final result =
          await operation(BitcoinModel(Bitcoin(session, Network.bitcoin)));
      await _closeTemporary(session);
      return result;
    } catch (_) {
      // A visible timeout does not cancel native work. Close waits for the real
      // native reply before disposing handles and deleting the temporary DB.
      unawaited(_closeTemporary(session));
      rethrow;
    }
  }

  Future<void> _closeTemporary(NativeWalletSession session) async {
    try {
      await session.close(deleteTemporary: true);
    } catch (_) {
      // Native retains ownership on failure. Never delete or reopen this DB in
      // Dart; a cleanup failure must not erase a completed balance result.
    }
  }

  Future<RecoveryDescriptors> _mnemonicDescriptors(
      String mnemonic, String addressType) async {
    final pair = await NativeBitcoinPrimitives(service: _nativeService).derive(
        network: Network.bitcoin, mnemonic: mnemonic,
        scriptType: scriptTypeForAddressType(addressType));
    return (external: pair.external, internal: pair.internal, xpub: pair.accountXpub);
  }

  /// Called only after the user approves migration to the target address.
  Future<String?> sweepPath(
      {required String mnemonic,
      required String addressType,
      required String targetAddress,
      required double feeRate}) async {
    try {
      final descriptors =
          await (_descriptorBuilder ?? _mnemonicDescriptors)(mnemonic, addressType);
      return await _withTemporaryWallet('bdk_sweep', descriptors,
          (model) async {
        await model.fullScan();
        final unsigned = await model.drainWalletBitcoinTransaction(
            TransactionBuilder(0, targetAddress, feeRate));
        final signed = await model.signBitcoinTransaction(unsigned);
        if (signed.signed != true) {
          throw const OnchainException('invalid_transaction');
        }
        return model.broadcastBitcoinTransaction(signed);
      });
    } catch (_) {
      return null;
    }
  }

  void reset() {
    state = const BalanceCheckState();
  }

  /// Failed discovery propagates to the caller so it cannot look like no funds.
  Future<int> checkXpubBalance(
      {required String xpub, required String scriptType}) async {
    try {
      final descriptors =
          await (_xpubDescriptorBuilder ?? _publicDescriptors)(xpub, scriptType);
      return await _withTemporaryWallet('bdk_xpub_check', descriptors,
          (model) async {
        await model.fullScan();
        return model.getBalance().total.toSat();
      });
    } on OnchainException {
      rethrow;
    } catch (_) {
      throw const OnchainException('invalid_request');
    }
  }

  Future<RecoveryDescriptors> _publicDescriptors(String xpub, String scriptType) async {
    final pair = await NativeBitcoinPrimitives(service: _nativeService).derive(
        network: Network.bitcoin, xpub: _convertKeyToStandard(xpub),
        scriptType: const ['bip44', 'bip49', 'bip86'].contains(scriptType) ? scriptType : 'bip84');
    return (external: pair.external, internal: pair.internal, xpub: pair.accountXpub);
  }

  /// Convert SLIP-132 keys (zpub, ypub) to standard xpub for BDK
  String _convertKeyToStandard(String key) {
    if (key.startsWith('xpub') || key.startsWith('tpub')) return key;

    final rawBytes = _base58DecodeCheck(key);
    final targetVersion = [0x04, 0x88, 0xB2, 0x1E]; // mainnet xpub

    for (int i = 0; i < 4; i++) {
      rawBytes[i] = targetVersion[i];
    }
    return _base58EncodeCheck(rawBytes);
  }

  static const String _b58Alphabet =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

  Uint8List _base58DecodeCheck(String input) {
    BigInt value = BigInt.zero;
    for (int i = 0; i < input.length; i++) {
      final charIndex = _b58Alphabet.indexOf(input[i]);
      if (charIndex < 0) throw FormatException('Invalid base58 char');
      value = value * BigInt.from(58) + BigInt.from(charIndex);
    }
    final hex = value.toRadixString(16).padLeft(164, '0'); // 82 bytes = 164 hex
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    // Strip the 4-byte checksum
    return Uint8List.fromList(bytes.sublist(0, bytes.length - 4));
  }

  String _base58EncodeCheck(Uint8List payload) {
    final hash1 = sha256.convert(payload).bytes;
    final hash2 = sha256.convert(hash1).bytes;
    final checksum = hash2.sublist(0, 4);

    final data = [...payload, ...checksum];
    BigInt value = BigInt.zero;
    for (final byte in data) {
      value = (value << 8) | BigInt.from(byte);
    }

    final sb = StringBuffer();
    while (value > BigInt.zero) {
      final remainder = (value % BigInt.from(58)).toInt();
      value = value ~/ BigInt.from(58);
      sb.write(_b58Alphabet[remainder]);
    }
    for (final byte in data) {
      if (byte == 0) {
        sb.write('1');
      } else {
        break;
      }
    }
    return sb.toString().split('').reversed.join();
  }
}
