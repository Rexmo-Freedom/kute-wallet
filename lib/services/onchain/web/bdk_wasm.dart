// lib/services/onchain/web/bdk_wasm.dart
//
// dart:js_interop bindings for the parts of bdk-wasm
// (@bitcoindevkit/bdk-wallet-web 0.4.0, vendored in web/bdk_wallet_web/)
// the web channel implementation uses. Every name resolves under
// globalThis.kuteBdk, which web/index.html sets once the wasm module has
// loaded; callers await [kuteBdkReady] first. See bitcoindevkit.d.ts there
// for the full API.
//
// bdk-wasm consumes Rust values passed by value: a builder method returns
// a new builder and the old handle is spent, and a SignOptions, Recipient
// or ChangeSet handed to a call cannot be used again.
//
// Extension types (dart:js_interop) need language 3.3; the package floor
// is older.
// @dart=3.3
@JS('kuteBdk')
library;

import 'dart:js_interop';

@JS('BdkError')
external JSFunction get bdkErrorClass;

@JS('seed_to_descriptor')
external BdkDescriptorPair seedToDescriptor(
    JSUint8Array seed, String network, String addressType);

@JS('xpub_to_descriptor')
external BdkDescriptorPair xpubToDescriptor(
    String xpub, String fingerprint, String network, String addressType);

extension type BdkDescriptorPair._(JSObject _) implements JSObject {
  @JS('external')
  external String get externalDescriptor;
  @JS('internal')
  external String get internalDescriptor;
}

@JS('Wallet')
extension type BdkWallet._(JSObject _) implements JSObject {
  external static BdkWallet create(
      String network, String externalDescriptor, String internalDescriptor);
  external static BdkWallet load(BdkChangeSet changeset,
      String? externalDescriptor, String? internalDescriptor);

  external String get network;
  external BdkBalance get balance;

  @JS('next_unused_address')
  external BdkAddressInfo nextUnusedAddress(String keychain);
  @JS('reveal_next_address')
  external BdkAddressInfo revealNextAddress(String keychain);
  @JS('peek_address')
  external BdkAddressInfo peekAddress(String keychain, int index);

  external JSArray<BdkWalletTx> transactions();
  @JS('get_tx')
  external BdkWalletTx? getTx(BdkTxid txid);
  @JS('tx_details')
  external BdkTxDetails? txDetails(BdkTxid txid);
  @JS('list_unspent')
  external JSArray<BdkLocalOutput> listUnspent();

  @JS('start_full_scan')
  external BdkFullScanRequest startFullScan();
  @JS('start_sync_with_revealed_spks')
  external BdkSyncRequest startSyncWithRevealedSpks();
  @JS('apply_update')
  external void applyUpdate(BdkUpdate update);
  @JS('take_staged')
  external BdkChangeSet? takeStaged();

  @JS('build_tx')
  external BdkTxBuilder buildTx();
  @JS('build_fee_bump')
  external BdkTxBuilder buildFeeBump(BdkTxid txid);
  external bool sign(BdkPsbt psbt, BdkSignOptions options);
  @JS('finalize_psbt')
  external bool finalizePsbt(BdkPsbt psbt, BdkSignOptions options);
}

@JS('ChangeSet')
extension type BdkChangeSet._(JSObject _) implements JSObject {
  @JS('from_json')
  external static BdkChangeSet fromJson(String json);
  @JS('to_json')
  external String toJson();
  @JS('is_empty')
  external bool isEmpty();
  external void merge(BdkChangeSet other);
}

@JS('EsploraClient')
extension type BdkEsploraClient._(JSObject _) implements JSObject {
  external BdkEsploraClient(String url, int maxRetries);
  @JS('full_scan')
  external JSPromise<BdkUpdate> fullScan(
      BdkFullScanRequest request, int stopGap, int parallelRequests);
  external JSPromise<BdkUpdate> sync(
      BdkSyncRequest request, int parallelRequests);
  external JSPromise<JSAny?> broadcast(BdkTransaction transaction);
}

extension type BdkFullScanRequest._(JSObject _) implements JSObject {}

extension type BdkSyncRequest._(JSObject _) implements JSObject {}

extension type BdkUpdate._(JSObject _) implements JSObject {}

extension type BdkBalance._(JSObject _) implements JSObject {
  external BdkAmount get confirmed;
  @JS('trusted_pending')
  external BdkAmount get trustedPending;
  @JS('untrusted_pending')
  external BdkAmount get untrustedPending;
  external BdkAmount get immature;
  external BdkAmount get total;
  @JS('trusted_spendable')
  external BdkAmount get trustedSpendable;
}

@JS('Amount')
extension type BdkAmount._(JSObject _) implements JSObject {
  @JS('from_sat')
  external static BdkAmount fromSat(JSBigInt sats);
  @JS('to_sat')
  external JSBigInt toSat();
}

@JS('FeeRate')
extension type BdkFeeRate._(JSObject _) implements JSObject {
  external BdkFeeRate(JSBigInt satPerVb);
  @JS('to_sat_per_kwu')
  external JSBigInt toSatPerKwu();
}

extension type BdkAddressInfo._(JSObject _) implements JSObject {
  external BdkAddress get address;
  external int get index;
}

@JS('Address')
extension type BdkAddress._(JSObject _) implements JSObject {
  @JS('from_string')
  external static BdkAddress fromString(String address, String network);
  @JS('script_pubkey')
  external BdkScriptBuf get scriptPubkey;
  @JS('toString')
  external String asString();
}

extension type BdkScriptBuf._(JSObject _) implements JSObject {
  @JS('to_hex_string')
  external String toHexString();
}

@JS('Txid')
extension type BdkTxid._(JSObject _) implements JSObject {
  @JS('from_string')
  external static BdkTxid fromString(String txid);
  @JS('toString')
  external String asString();
}

@JS('OutPoint')
extension type BdkOutPoint._(JSObject _) implements JSObject {
  external BdkOutPoint(BdkTxid txid, int vout);
  external BdkTxid get txid;
  external int get vout;
}

extension type BdkTxOut._(JSObject _) implements JSObject {
  external BdkAmount get value;
  @JS('script_pubkey')
  external BdkScriptBuf get scriptPubkey;
}

extension type BdkTxIn._(JSObject _) implements JSObject {
  @JS('previous_output')
  external BdkOutPoint get previousOutput;
  external int get sequence;
}

@JS('Transaction')
extension type BdkTransaction._(JSObject _) implements JSObject {
  @JS('from_bytes')
  external static BdkTransaction fromBytes(JSUint8Array bytes);
  @JS('compute_txid')
  external BdkTxid computeTxid();
  external int get vsize;
  external JSArray<BdkTxIn> get input;
  external JSArray<BdkTxOut> get output;
  @JS('to_bytes')
  external JSUint8Array toBytes();
}

extension type BdkConfirmationBlockTime._(JSObject _) implements JSObject {
  @JS('block_id')
  external BdkBlockId get blockId;
  @JS('confirmation_time')
  external JSBigInt get confirmationTime;
}

extension type BdkBlockId._(JSObject _) implements JSObject {
  external int get height;
  external String get hash;
}

extension type BdkChainPosition._(JSObject _) implements JSObject {
  @JS('is_confirmed')
  external bool get isConfirmed;
  external BdkConfirmationBlockTime? get anchor;
  @JS('last_seen')
  external JSBigInt? get lastSeen;
}

extension type BdkWalletTx._(JSObject _) implements JSObject {
  external BdkTxid get txid;
  @JS('chain_position')
  external BdkChainPosition get chainPosition;
}

extension type BdkTxDetails._(JSObject _) implements JSObject {
  external BdkTxid get txid;
  external BdkAmount get sent;
  external BdkAmount get received;
  external BdkAmount? get fee;
  @JS('fee_rate')
  external BdkFeeRate? get feeRate;
  @JS('balance_delta_sat')
  external JSBigInt get balanceDelta;
  @JS('chain_position')
  external BdkChainPosition get chainPosition;
  external BdkTransaction get tx;
}

extension type BdkLocalOutput._(JSObject _) implements JSObject {
  external BdkOutPoint get outpoint;
  external BdkTxOut get txout;
  external String get keychain;
  @JS('derivation_index')
  external int get derivationIndex;
}

@JS('Recipient')
extension type BdkRecipient._(JSObject _) implements JSObject {
  external BdkRecipient(BdkScriptBuf scriptPubkey, BdkAmount amount);
}

extension type BdkTxBuilder._(JSObject _) implements JSObject {
  @JS('fee_rate')
  external BdkTxBuilder feeRate(BdkFeeRate rate);
  @JS('set_exact_sequence')
  external BdkTxBuilder setExactSequence(int sequence);
  @JS('add_recipient')
  external BdkTxBuilder addRecipient(BdkRecipient recipient);
  @JS('drain_wallet')
  external BdkTxBuilder drainWallet();
  @JS('drain_to')
  external BdkTxBuilder drainTo(BdkScriptBuf scriptPubkey);
  @JS('add_utxos')
  external BdkTxBuilder addUtxos(JSArray<BdkOutPoint> outpoints);
  @JS('only_spend_from')
  external BdkTxBuilder onlySpendFrom();
  external BdkPsbt finish();
}

@JS('Psbt')
extension type BdkPsbt._(JSObject _) implements JSObject {
  @JS('from_string')
  external static BdkPsbt fromString(String base64);
  @JS('toString')
  external String asString();
  external BdkPsbt clone();
  @JS('extract_tx')
  external BdkTransaction extractTx();
  external BdkAmount fee();
  @JS('unsigned_tx')
  external BdkTransaction get unsignedTx;
}

@JS('SignOptions')
extension type BdkSignOptions._(JSObject _) implements JSObject {
  external BdkSignOptions();
}

extension type BdkErrorValue._(JSObject _) implements JSObject {
  external int get code;
}
