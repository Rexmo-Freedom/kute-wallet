// lib/services/onchain/web/web_onchain_plugin.dart
//
// The web build's answer to the com.kutewallet.app/onchain channel. iOS
// and Android answer it with native BDK (ios/Runner/NativeBdkPlugin.swift,
// android/.../OnchainPlugin.kt); a browser has neither, so
// NativeOnchainService calls [WebOnchainPlugin.invoke] here instead of the
// MethodChannel (picked by the conditional export in onchain_transport.dart).
//
// It follows NativeBdkPlugin.swift method by method: the same arguments,
// the same checks, the same return maps and the same error codes, so no
// other part of the app can tell the platforms apart. BDK itself is the
// official WebAssembly build, bdk-wasm (web/bdk_wallet_web/, bindings in
// bdk_wasm.dart), which runs the same Rust BDK as the native bindings.
// What bdk-wasm does not expose (BIP39, the account xpub) is pure Dart in
// web_bitcoin_keys.dart.
//
// Differences a browser forces, each kept to the smallest change:
//  * Persistence: no SQLite. The wallet's BDK changeset is kept as JSON in
//    the browser (OnchainWebStore, keyed by the dbPath the app passes), so
//    a reload loads the wallet instead of rescanning it.
//  * Electrum is TCP, which a browser cannot open. Only Esplora is served;
//    OnchainEndpoint.fromStored already turns a stored Electrum node into
//    the default Esplora host on the web.
//  * One JavaScript thread: there are no owner queues. Requests on one
//    wallet are already serialised by NativeOnchainService; a scan awaits
//    the network without holding the wallet, so other wallets keep going.
//
// Extension types (dart:js_interop) need language 3.3; the package floor
// is older.
// @dart=3.3

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:kute/services/onchain/native_onchain_service.dart'
    show OnchainTransport;
import 'package:kute/services/onchain/onchain_web_store.dart';
import 'package:kute/services/onchain/web/bdk_wasm.dart';
import 'package:kute/services/onchain/web/web_bitcoin_keys.dart';

/// On the web the channel is answered in Dart; see the file comment.
OnchainTransport platformOnchainTransport(MethodChannel channel) =>
    WebOnchainPlugin.instance.invoke;

@JS('kuteBdkReady')
external JSPromise<JSAny?>? get _kuteBdkReady;

@JS('kuteBdk')
external JSAny? get _kuteBdk;

@JS('Number')
external JSNumber _jsNumber(JSAny? value);

@JS('BigInt')
external JSBigInt _jsBigInt(JSNumber value);

/// One of the fixed error codes NativeOnchainService accepts.
class _Failure implements Exception {
  final String code;
  const _Failure(this.code);
  static const invalidRequest = _Failure('invalid_request');
  static const mismatch = _Failure('wallet_mismatch');
  static const network = _Failure('network');
  static const invalidAddress = _Failure('invalid_address');
  static const invalidTransaction = _Failure('invalid_transaction');
  static const timeout = _Failure('timeout');
  static const unsupported = _Failure('unsupported');
  static const internal = _Failure('internal');
}

/// The same fixed messages the native plugins send. BDK's own messages
/// can contain descriptors, addresses or amounts and never cross.
const _messages = {
  'invalid_request': 'The Bitcoin request is invalid.',
  'wallet_open_failed': 'The Bitcoin wallet could not be opened.',
  'wallet_mismatch': 'The Bitcoin wallet session does not match.',
  'network': 'The Bitcoin server request failed.',
  'insufficient_funds': 'The Bitcoin wallet has insufficient funds.',
  'invalid_address': 'The Bitcoin address is invalid for this network.',
  'invalid_amount': 'The amount is below the Bitcoin network minimum.',
  'invalid_fee_rate': 'The fee rate is not usable for this transaction.',
  'invalid_transaction': 'The Bitcoin transaction could not be processed.',
  'timeout': 'The Bitcoin request expired before it could start.',
  'busy': 'Bitcoin requests are still completing. Please try again later.',
  'unsupported': 'The Bitcoin operation is not supported.',
  'internal': 'The Bitcoin operation failed.',
};

class WebOnchainPlugin {
  static final instance = WebOnchainPlugin();

  final _sessions = <String, _Session>{};
  final _openingPaths = <String>{};
  final _openingWallets = <String>{};
  Future<void>? _loading;

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    try {
      return await _dispatch(method, _Request(arguments));
    } catch (error) {
      final code = _classify(error, method);
      throw PlatformException(code: code, message: _messages[code]);
    }
  }

  Future<void> _load() {
    final loading = _loading ??= () async {
      if (_kuteBdk != null) return;
      final ready = _kuteBdkReady;
      if (ready == null) throw _Failure.unsupported;
      try {
        await ready.toDart;
      } catch (_) {
        throw _Failure.unsupported;
      }
    }();
    return loading.catchError((Object error) {
      _loading = null;
      throw error;
    });
  }

  Future<Object?> _dispatch(String method, _Request request) async {
    switch (method) {
      case 'mnemonic':
        request.checkDeadline();
        return _mnemonic(request);
      case 'derive':
        await _load();
        request.checkDeadline();
        return _derive(request);
      case 'inspectPsbt':
        await _load();
        request.checkDeadline();
        return _psbtResult(BdkPsbt.fromString(request.string('psbt')),
            unsignedOnly: true);
    }
    await _load();
    final walletId = request.string('walletId');
    request.checkDeadline();
    if (method == 'open') return _open(walletId, request);
    final sessionId = request.string('sessionId');
    final session = _sessions[walletId];
    if (session == null) {
      if (method == 'close') return null;
      throw _Failure.mismatch;
    }
    if (session.id != sessionId) throw _Failure.mismatch;
    if (method == 'close') return _close(walletId, session, request);

    final wallet = session.wallet;
    if (wallet == null) throw _Failure.mismatch;
    switch (method) {
      case 'snapshot':
        return _snapshot(wallet);
      case 'sync':
        final fullScan = request.boolean('fullScan');
        final update = await session.scan(fullScan: fullScan);
        wallet.applyUpdate(update);
        await session.persist();
        return {'fullScan': fullScan, 'snapshot': _snapshot(wallet)};
      case 'address':
        final keychain = request.keychain();
        final BdkAddressInfo address;
        switch (request.string('mode')) {
          case 'nextUnused':
            address = wallet.nextUnusedAddress(keychain);
            await session.persist();
          case 'revealNext':
            address = wallet.revealNextAddress(keychain);
            await session.persist();
          case 'peek':
            address = wallet.peekAddress(keychain, request.uint32('index'));
          default:
            throw _Failure.invalidRequest;
        }
        return {'address': address.address.asString(), 'index': address.index};
      case 'build':
        return _build(session, wallet, request);
      case 'bump':
        final txid = BdkTxid.fromString(request.string('txid'));
        final psbt = wallet
            .buildFeeBump(txid)
            .feeRate(request.feeRate())
            .finish();
        await session.persist();
        return _psbtResult(psbt);
      case 'sign':
        final psbt = BdkPsbt.fromString(request.string('psbt'));
        final signed = wallet.sign(psbt, BdkSignOptions());
        return {..._psbtResult(psbt), 'signed': signed};
      case 'broadcast':
        final payload = request.string('payload');
        final BdkTransaction transaction;
        switch (request.string('format')) {
          case 'psbt':
            final psbt = BdkPsbt.fromString(payload);
            var finalized = wallet.sign(psbt, BdkSignOptions());
            if (!finalized) {
              finalized = wallet.finalizePsbt(psbt, BdkSignOptions());
            }
            if (!finalized) throw _Failure.invalidTransaction;
            transaction = psbt.extractTx();
          case 'hex':
            transaction = BdkTransaction.fromBytes(_decodeHex(payload).toJS);
          default:
            throw _Failure.invalidRequest;
        }
        final txid = transaction.computeTxid().asString();
        // One submission only. An uncertain response is reconciled by the
        // caller.
        await session.broadcast(transaction);
        return {'txid': txid};
      default:
        throw _Failure.unsupported;
    }
  }

  // ---- Stateless key work -------------------------------------------------

  Object _mnemonic(_Request request) {
    switch (request.string('action')) {
      case 'generate':
        if (request.values['wordCount'] != null &&
            request.integer('wordCount') != 12) {
          throw _Failure.invalidRequest;
        }
        return WebBitcoinKeys.generateMnemonic();
      case 'validate':
        final phrase = request.values['mnemonic'];
        if (phrase is! String) throw _Failure.invalidRequest;
        return WebBitcoinKeys.validateMnemonic(phrase);
      case 'fromEntropy':
        final entropy = request.values['entropy'];
        if (entropy is! Uint8List ||
            !WebBitcoinKeys.entropyLengths.contains(entropy.length)) {
          throw _Failure.invalidRequest;
        }
        return WebBitcoinKeys.mnemonicFromEntropy(entropy);
      default:
        throw _Failure.invalidRequest;
    }
  }

  Map<String, String> _derive(_Request request) {
    final network = request.network();
    final mainnet = network == 'bitcoin';
    final purpose = const {
      'bip44': 44,
      'bip49': 49,
      'bip84': 84,
      'bip86': 86
    }[request.string('scriptType')];
    if (purpose == null) throw _Failure.invalidRequest;
    // The address type bdk-wasm names BDK's Bip44/49/84/86 templates by.
    final addressType = const {
      44: 'p2pkh',
      49: 'p2sh',
      84: 'p2wpkh',
      86: 'p2tr'
    }[purpose]!;
    final fingerprint = request.string('masterFingerprint');
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(fingerprint)) {
      throw _Failure.invalidRequest;
    }
    final phrase = request.values['mnemonic'];
    final xpub = request.values['xpub'];
    if ((phrase is String) == (xpub is String)) throw _Failure.invalidRequest;
    if (phrase is String) {
      // As native: BDK's Bip-template private descriptors on the BIP39
      // master key (no passphrase), and the account key's xpub.
      final seed = WebBitcoinKeys.seed(phrase);
      final pair = seedToDescriptor(seed.toJS, network, addressType);
      return {
        'external': pair.externalDescriptor,
        'internal': pair.internalDescriptor,
        'accountXpub': WebBitcoinKeys.accountXpub(seed,
            purpose: purpose, mainnet: mainnet),
      };
    }
    xpub as String;
    final pair = xpubToDescriptor(xpub, fingerprint, network, addressType);
    return {
      'external': pair.externalDescriptor,
      'internal': pair.internalDescriptor,
      'accountXpub': xpub,
    };
  }

  // ---- Wallet sessions ----------------------------------------------------

  Future<Map<String, Object?>> _open(String walletId, _Request request) async {
    final path = request.string('dbPath');
    final identity = _Identity(
      path: path,
      descriptor: request.string('descriptor'),
      changeDescriptor: request.string('changeDescriptor'),
      network: request.network(),
      backendKind: request.string('backendKind'),
      backendUrl: request.string('backendUrl'),
      temporary: request.boolean('temporary', fallback: false),
    );
    identity.validateBackend();
    if (identity.temporary) _validateTemporaryPath(path);
    final existing = _sessions[walletId];
    if (existing != null) {
      final wallet = existing.wallet;
      if (existing.identity != identity || wallet == null) {
        throw _Failure.mismatch;
      }
      return {
        'sessionId': existing.id,
        'isNewWallet': existing.isNewWallet,
        'snapshot': _snapshot(wallet),
      };
    }
    // Different wallet IDs must not acquire independent writers to the same
    // stored wallet, nor one wallet two sessions.
    if (_openingWallets.contains(walletId) ||
        _openingPaths.contains(path) ||
        _sessions.values.any((session) => session.identity.path == path)) {
      throw _Failure.mismatch;
    }
    _openingWallets.add(walletId);
    _openingPaths.add(path);
    try {
      final stored = await OnchainWebStore.read(path);
      final session = _Session(identity, isNewWallet: stored == null);
      try {
        await session.openWallet(stored);
        final snapshot = _snapshot(session.requireWallet());
        _sessions[walletId] = session;
        return {
          'sessionId': session.id,
          'isNewWallet': session.isNewWallet,
          'snapshot': snapshot,
        };
      } catch (_) {
        session.release();
        // A recovery wallet that never opened leaves nothing behind.
        if (identity.temporary && stored == null) {
          try {
            await OnchainWebStore.delete(path);
          } catch (_) {}
        }
        rethrow;
      }
    } finally {
      _openingWallets.remove(walletId);
      _openingPaths.remove(path);
    }
  }

  Future<Object?> _close(
      String walletId, _Session session, _Request request) async {
    final deleteTemporary = request.boolean('deleteTemporary', fallback: false);
    if (deleteTemporary && !session.identity.temporary) {
      throw _Failure.invalidRequest;
    }
    final path = session.identity.path;
    if (deleteTemporary) _validateTemporaryPath(path);
    if (session.wallet != null) await session.persist();
    session.release();
    _sessions.remove(walletId);
    if (deleteTemporary) await OnchainWebStore.delete(path);
    return null;
  }

  static void _validateTemporaryPath(String path) {
    final name = path.split('/').last;
    if (!const ['bdk_temp_', 'bdk_sweep_', 'bdk_xpub_check_']
        .any(name.startsWith)) {
      throw _Failure.invalidRequest;
    }
  }

  Future<Map<String, Object?>> _build(
      _Session session, BdkWallet wallet, _Request request) async {
    final BdkAddress address;
    try {
      address = BdkAddress.fromString(request.string('address'), wallet.network);
    } catch (_) {
      throw _Failure.invalidAddress;
    }
    final amount = request.integer('amountSats');
    final drain = request.boolean('drain');
    if (amount > 2100000000000000 || (!drain && amount <= 0)) {
      throw _Failure.invalidRequest;
    }
    var builder = wallet
        .buildTx()
        .feeRate(request.feeRate())
        .setExactSequence(0xFFFFFFFD);
    if (drain) {
      builder = builder.drainWallet().drainTo(address.scriptPubkey);
    } else {
      builder = builder.addRecipient(BdkRecipient(
          address.scriptPubkey, BdkAmount.fromSat(_bigInt(amount))));
    }
    final values = request.values['selectedUtxos'];
    if (values != null) {
      if (values is! List || values.isEmpty) throw _Failure.invalidRequest;
      final selected = <BdkOutPoint>[];
      for (final value in values) {
        if (value is! Map || value.keys.any((key) => key is! String)) {
          throw _Failure.invalidRequest;
        }
        final outpoint = _Request(Map<String, Object?>.from(value));
        selected.add(BdkOutPoint(BdkTxid.fromString(outpoint.string('txid')),
            outpoint.uint32('vout')));
      }
      builder = builder.addUtxos(selected.toJS).onlySpendFrom();
    }
    final psbt = builder.finish();
    await session.persist();
    return _psbtResult(psbt);
  }

  // ---- Values -------------------------------------------------------------

  Map<String, Object?> _snapshot(BdkWallet wallet) {
    final balance = wallet.balance;
    final transactions = [
      for (final canonical in wallet.transactions().toDart)
        _transaction(wallet, canonical),
    ];
    final outputs = [
      for (final output in wallet.listUnspent().toDart) _output(wallet, output),
    ];
    return {
      'balance': {
        'confirmed': _sats(balance.confirmed),
        'trustedPending': _sats(balance.trustedPending),
        'untrustedPending': _sats(balance.untrustedPending),
        'immature': _sats(balance.immature),
        'total': _sats(balance.total),
        'spendable': _sats(balance.trustedSpendable),
      },
      'transactions': transactions,
      'utxos': outputs,
    };
  }

  Map<String, Object?> _transaction(BdkWallet wallet, BdkWalletTx canonical) {
    final details = wallet.txDetails(canonical.txid);
    if (details == null) throw _Failure.internal;
    final fee = details.fee;
    final feeRate = details.feeRate;
    return {
      'txid': details.txid.asString(),
      'sent': _sats(details.sent),
      'received': _sats(details.received),
      'fee': fee == null ? null : _sats(fee),
      'feeRate': feeRate == null ? null : _int(feeRate.toSatPerKwu()) / 250.0,
      'balanceDelta': _int(details.balanceDelta),
      'chainPosition': _position(details.chainPosition),
      'tx': _summary(details.tx),
    };
  }

  Map<String, Object?> _output(BdkWallet wallet, BdkLocalOutput output) {
    final outpoint = output.outpoint;
    final txout = output.txout;
    // bdk-wasm's LocalOutput has no chain position; it is the creating
    // transaction's, which is what BDK puts there.
    final creating = wallet.getTx(outpoint.txid);
    if (creating == null) throw _Failure.internal;
    return {
      'outpoint': {'txid': outpoint.txid.asString(), 'vout': outpoint.vout},
      'txout': {
        'value': _sats(txout.value),
        'scriptPubkey': txout.scriptPubkey.toHexString(),
      },
      'keychain': output.keychain == 'external' ? 'external' : 'internal',
      // Only unspent outputs are listed.
      'isSpent': false,
      'derivationIndex': output.derivationIndex,
      'chainPosition': _position(creating.chainPosition),
    };
  }

  static Map<String, Object?> _position(BdkChainPosition position) {
    if (position.isConfirmed) {
      final anchor = position.anchor;
      if (anchor == null) throw _Failure.internal;
      final block = anchor.blockId;
      return {
        'height': block.height,
        'confirmationTime': _int(anchor.confirmationTime),
        'blockHash': block.hash,
        'lastSeen': null,
      };
    }
    final lastSeen = position.lastSeen;
    return {
      'height': null,
      'confirmationTime': null,
      'blockHash': null,
      'lastSeen': lastSeen == null ? null : _int(lastSeen),
    };
  }

  static Map<String, Object?> _summary(BdkTransaction transaction) {
    final bytes = transaction.toBytes().toDart;
    final inputs = [
      for (final input in transaction.input.toDart)
        {
          'previousOutput': {
            'txid': input.previousOutput.txid.asString(),
            'vout': input.previousOutput.vout,
          },
          'sequence': input.sequence,
        },
    ];
    final outputs = [
      for (final output in transaction.output.toDart)
        {
          'value': _sats(output.value),
          'scriptPubkey': output.scriptPubkey.toHexString(),
        },
    ];
    return {
      'txid': transaction.computeTxid().asString(),
      'vsize': transaction.vsize,
      // The consensus encoding starts with the signed 32-bit version.
      'version': ByteData.sublistView(bytes).getInt32(0, Endian.little),
      'inputCount': inputs.length,
      'outputCount': outputs.length,
      'inputs': inputs,
      'outputs': outputs,
      'rawHex': _hex(bytes),
    };
  }

  static Map<String, Object?> _psbtResult(BdkPsbt psbt,
      {bool unsignedOnly = false}) {
    // extract_tx fills available signatures without finalizing or mutating
    // the PSBT (it consumes its handle, hence the clone). A fee-rate or
    // missing-UTXO extraction failure falls back to the unsigned
    // transaction, as native does.
    BdkTransaction? transaction;
    if (!unsignedOnly) {
      try {
        transaction = psbt.clone().extractTx();
      } catch (_) {}
    }
    transaction ??= psbt.unsignedTx;
    BdkAmount? fee;
    try {
      fee = psbt.fee();
    } catch (_) {}
    return {
      'psbt': psbt.asString(),
      'feeSats': fee == null ? null : _sats(fee),
      'tx': _summary(transaction),
    };
  }

  // ---- Errors -------------------------------------------------------------

  static String _classify(Object error, String operation) {
    if (error is _Failure) return error.code;
    if (operation == 'open') return 'wallet_open_failed';
    // BDK names why a transaction could not be built; only the code steers
    // the choice, as native's CreateTxError case names do.
    final code = _bdkErrorCode(error);
    if (code != null && code <= 22) {
      switch (code) {
        case 11: // InsufficientFunds
          return 'insufficient_funds';
        case 10: // OutputBelowDustLimit
          return 'invalid_amount';
        case 7: // FeeTooLow
        case 8: // FeeRateTooLow
        case 21: // FeeRateUnavailable
          return 'invalid_fee_rate';
        case 2: // SpendingPolicyRequired
        case 9: // NoUtxosSelected
        case 15: // UnknownUtxo
        case 16: // MissingNonWitnessUtxo
          return 'invalid_request';
        default:
          return 'invalid_transaction';
      }
    }
    if (const {'build', 'bump', 'sign', 'broadcast', 'inspectPsbt'}
        .contains(operation)) {
      return 'invalid_transaction';
    }
    if (const {'mnemonic', 'derive'}.contains(operation)) {
      return 'invalid_request';
    }
    return 'internal';
  }

  /// The [BdkErrorCode] of a BdkError thrown by bdk-wasm, else null.
  static int? _bdkErrorCode(Object error) {
    try {
      final value = error as JSAny;
      if (!value.instanceof(bdkErrorClass)) return null;
      return (value as BdkErrorValue).code;
    } catch (_) {
      return null;
    }
  }
}

class _Identity {
  final String path;
  final String descriptor;
  final String changeDescriptor;
  final String network;
  final String backendKind;
  final String backendUrl;
  final bool temporary;
  const _Identity({
    required this.path,
    required this.descriptor,
    required this.changeDescriptor,
    required this.network,
    required this.backendKind,
    required this.backendUrl,
    required this.temporary,
  });

  void validateBackend() {
    final url = Uri.tryParse(backendUrl);
    if (url == null ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !url.hasScheme) {
      throw _Failure.invalidRequest;
    }
    final scheme = url.scheme.toLowerCase();
    switch (backendKind) {
      case 'esplora':
        final local = const {'localhost', '127.0.0.1', '::1'}.contains(url.host);
        if (scheme != 'https' &&
            !(scheme == 'http' && (network == 'regtest' || local))) {
          throw _Failure.invalidRequest;
        }
      case 'electrum':
        // A browser cannot open Electrum's TCP connection.
        throw _Failure.unsupported;
      default:
        throw _Failure.invalidRequest;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _Identity &&
      other.path == path &&
      other.descriptor == descriptor &&
      other.changeDescriptor == changeDescriptor &&
      other.network == network &&
      other.backendKind == backendKind &&
      other.backendUrl == backendUrl &&
      other.temporary == temporary;

  @override
  int get hashCode => Object.hash(path, descriptor, changeDescriptor, network,
      backendKind, backendUrl, temporary);
}

class _Session {
  final String id = _sessionId();
  final _Identity identity;
  final bool isNewWallet;
  BdkWallet? wallet;

  /// Everything persisted for this wallet so far: every staged change is
  /// merged in and the whole set written back, as BDK's SQLite store keeps
  /// the sum of its changesets.
  BdkChangeSet? _stored;
  BdkEsploraClient? _client;

  _Session(this.identity, {required this.isNewWallet});

  static String _sessionId() {
    final random = Random.secure();
    final hex = [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> openWallet(String? storedJson) async {
    if (storedJson == null) {
      // Native creates and persists in one step (lookahead 25, BDK's
      // default here too).
      final created = BdkWallet.create(
          identity.network, identity.descriptor, identity.changeDescriptor);
      wallet = created;
      final initial = created.takeStaged();
      if (initial == null) throw _Failure.internal;
      _stored = initial;
      await OnchainWebStore.write(identity.path, initial.toJson());
    } else {
      // Never turn a load error into an empty replacement wallet. Loading
      // with the descriptors checks they match the stored ones and keeps
      // the private keys for signing.
      wallet = BdkWallet.load(BdkChangeSet.fromJson(storedJson),
          identity.descriptor, identity.changeDescriptor);
      _stored = BdkChangeSet.fromJson(storedJson);
      await persist();
    }
    if (requireWallet().network != identity.network) throw _Failure.mismatch;
  }

  BdkWallet requireWallet() => wallet ?? (throw _Failure.mismatch);

  Future<void> persist() async {
    final staged = requireWallet().takeStaged();
    if (staged == null || staged.isEmpty()) return;
    final stored = _stored;
    if (stored == null) throw _Failure.internal;
    stored.merge(staged);
    await OnchainWebStore.write(identity.path, stored.toJson());
  }

  BdkEsploraClient _esplora() =>
      // Six retries, esplora-client's default, as native's client.
      _client ??= BdkEsploraClient(identity.backendUrl, 6);

  Future<BdkUpdate> scan({required bool fullScan}) async {
    final wallet = requireWallet();
    final client = _esplora();
    try {
      if (fullScan) {
        return await client.fullScan(wallet.startFullScan(), 20, 2).toDart;
      }
      return await client.sync(wallet.startSyncWithRevealedSpks(), 2).toDart;
    } catch (_) {
      throw _Failure.network;
    }
  }

  Future<void> broadcast(BdkTransaction transaction) async {
    try {
      await _esplora().broadcast(transaction).toDart;
    } catch (_) {
      throw _Failure.network;
    }
  }

  void release() {
    _client = null;
    wallet = null;
    _stored = null;
  }
}

/// The request map, read with the native plugins' rules.
class _Request {
  final Map<String, Object?> values;
  const _Request(this.values);

  String string(String key) {
    final value = values[key];
    if (value is! String || value.isEmpty) throw _Failure.invalidRequest;
    return value;
  }

  int integer(String key) {
    final value = values[key];
    if (value is! int || value < 0) throw _Failure.invalidRequest;
    return value;
  }

  int uint32(String key) {
    final value = integer(key);
    if (value > 0xFFFFFFFF) throw _Failure.invalidRequest;
    return value;
  }

  bool boolean(String key, {bool? fallback}) {
    if (!values.containsKey(key) && fallback != null) return fallback;
    final value = values[key];
    if (value is! bool) throw _Failure.invalidRequest;
    return value;
  }

  void checkDeadline() {
    if (integer('deadlineMs') <= DateTime.now().millisecondsSinceEpoch) {
      throw _Failure.timeout;
    }
  }

  String network() {
    final value = string('network');
    if (!const {'bitcoin', 'testnet', 'testnet4', 'signet', 'regtest'}
        .contains(value)) {
      throw _Failure.invalidRequest;
    }
    return value;
  }

  String keychain() {
    final value = string('keychain');
    if (value != 'external' && value != 'internal') {
      throw _Failure.invalidRequest;
    }
    return value;
  }

  BdkFeeRate feeRate() {
    final value = integer('feeRateSatVb');
    if (value <= 0) throw _Failure.invalidRequest;
    return BdkFeeRate(_bigInt(value));
  }
}

// ---- Number and byte conversions -------------------------------------------

JSBigInt _bigInt(int value) => _jsBigInt(value.toJS);

/// A BDK u64/i64 as an exact Dart int, refused beyond 2^53 where a
/// JavaScript number stops being exact (native refuses beyond Int64).
int _int(JSBigInt value) {
  final number = _jsNumber(value).toDartDouble;
  if (!number.isFinite || number.abs() > 9007199254740991) {
    throw _Failure.invalidTransaction;
  }
  return number.toInt();
}

int _sats(BdkAmount amount) => _int(amount.toSat());

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _decodeHex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw _Failure.invalidTransaction;
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
