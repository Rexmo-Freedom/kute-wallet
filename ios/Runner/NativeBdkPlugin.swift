import Foundation
import CoreFoundation
import Flutter
import BitcoinDevKit

/// The channel carries values only. Wallet handles stay on their owner queue;
/// stateless key work uses its own queue. Dart timeouts never cancel native work.
final class NativeBdkPlugin: NSObject, FlutterPlugin {
  private let owner = NativeBdkOwner.shared

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.kutewallet.app/onchain", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeBdkPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(NativeBdkFailure.invalidRequest.flutterError)
      return
    }
    if NativeBdkStateless.supports(call.method) {
      NativeBdkStateless.shared.submit(call.method, arguments: arguments, result: result)
      return
    }
    owner.queue.async {
      let response: Any?
      do {
        response = try self.owner.execute(call.method, arguments: arguments)
      } catch {
        response = NativeBdkFailure.classify(error, operation: call.method).flutterError
      }
      DispatchQueue.main.async { result(response) }
    }
  }
}

private enum NativeBdkFailure: String, Error {
  case invalidRequest = "invalid_request"
  case openFailed = "wallet_open_failed"
  case mismatch = "wallet_mismatch"
  case network
  case insufficientFunds = "insufficient_funds"
  case invalidAddress = "invalid_address"
  case invalidAmount = "invalid_amount"
  case invalidFeeRate = "invalid_fee_rate"
  case invalidTransaction = "invalid_transaction"
  case timeout
  case busy
  case unsupported
  case internalFailure = "internal"

  var flutterError: FlutterError {
    // SDK errors can contain descriptors, addresses or transaction values.
    // Only these fixed messages may cross the channel or reach diagnostics.
    let message: String
    switch self {
    case .invalidRequest: message = "The Bitcoin request is invalid."
    case .openFailed: message = "The Bitcoin wallet could not be opened."
    case .mismatch: message = "The Bitcoin wallet session does not match."
    case .network: message = "The Bitcoin server request failed."
    case .insufficientFunds: message = "The Bitcoin wallet has insufficient funds."
    case .invalidAddress: message = "The Bitcoin address is invalid for this network."
    case .invalidAmount: message = "The amount is below the Bitcoin network minimum."
    case .invalidFeeRate: message = "The fee rate is not usable for this transaction."
    case .invalidTransaction: message = "The Bitcoin transaction could not be processed."
    case .timeout: message = "The Bitcoin request expired before it could start."
    case .busy: message = "Bitcoin requests are still completing. Please try again later."
    case .unsupported: message = "The Bitcoin operation is not supported."
    case .internalFailure: message = "The Bitcoin operation failed."
    }
    return FlutterError(code: rawValue, message: message, details: nil)
  }

  static func classify(_ error: Error, operation: String) -> NativeBdkFailure {
    if let failure = error as? NativeBdkFailure { return failure }
    if operation == "open" { return .openFailed }
    if error is EsploraError || error is ElectrumError { return .network }
    if let createError = error as? CreateTxError,
       case .InsufficientFunds = createError { return .insufficientFunds }
    // BDK names the reason a transaction could not be built, and reporting
    // every failure that is not InsufficientFunds as one generic code
    // destroyed it: the send flow could then only word a dust amount, an
    // unusable fee rate and a coin that is no longer there as the same
    // "check the amount and address" sentence. Only the case NAME steers the
    // choice; the message that crosses the channel stays one of the fixed
    // strings above, so no descriptor, address or value is ever forwarded.
    if error is CreateTxError {
      let name = String(describing: error)
      if name.contains("Dust") { return .invalidAmount }
      if name.contains("FeeRate") || name.contains("FeeTooLow")
          || name.contains("FeeTooHigh") { return .invalidFeeRate }
      if name.contains("Utxo") || name.contains("OutPoint")
          || name.contains("SpendingPolicy") { return .invalidRequest }
      if name.contains("Address") || name.contains("Script") { return .invalidAddress }
      return .invalidTransaction
    }
    if ["build", "bump", "sign", "broadcast", "inspectPsbt"].contains(operation) {
      return .invalidTransaction
    }
    if ["mnemonic", "derive"].contains(operation) { return .invalidRequest }
    return .internalFailure
  }
}

/// Authentication and descriptor work must not wait behind a network scan.
/// Admission is bounded even when callers stop awaiting their visible Future.
private final class NativeBdkStateless {
  static let shared = NativeBdkStateless()
  private let queue = DispatchQueue(label: "com.kutewallet.app.onchain.keys", qos: .userInitiated)
  private let admission = NSLock()
  private var pending = 0
  private let limit = 16

  static func supports(_ method: String) -> Bool {
    ["mnemonic", "derive", "inspectPsbt"].contains(method)
  }

  func submit(_ method: String, arguments: [String: Any], result: @escaping FlutterResult) {
    admission.lock()
    guard pending < limit else {
      admission.unlock()
      result(NativeBdkFailure.busy.flutterError)
      return
    }
    pending += 1
    admission.unlock()
    queue.async {
      defer {
        self.admission.lock()
        self.pending -= 1
        self.admission.unlock()
      }
      let response: Any?
      do {
        response = try self.execute(method, request: NativeBdkRequest(arguments))
      } catch {
        response = NativeBdkFailure.classify(error, operation: method).flutterError
      }
      DispatchQueue.main.async { result(response) }
    }
  }

  private func execute(_ method: String, request: NativeBdkRequest) throws -> Any {
    dispatchPrecondition(condition: .onQueue(queue))
    guard try request.integer("deadlineMs") > Int64(Date().timeIntervalSince1970 * 1_000) else {
      throw NativeBdkFailure.timeout
    }
    switch method {
    case "mnemonic":
      switch try request.string("action") {
      case "generate":
        if request.values["wordCount"] != nil {
          guard try request.integer("wordCount") == 12 else { throw NativeBdkFailure.invalidRequest }
        }
        return Mnemonic(wordCount: .words12).description
      case "validate":
        guard let phrase = request.values["mnemonic"] as? String else {
          throw NativeBdkFailure.invalidRequest
        }
        return (try? Mnemonic.fromString(mnemonic: phrase)) != nil
      case "fromEntropy":
        guard let entropy = request.values["entropy"] as? FlutterStandardTypedData,
              entropy.elementSize == 1, [16, 20, 24, 28, 32].contains(entropy.data.count) else {
          throw NativeBdkFailure.invalidRequest
        }
        return try Mnemonic.fromEntropy(entropy: entropy.data).description
      default: throw NativeBdkFailure.invalidRequest
      }
    case "derive":
      return try derive(request)
    case "inspectPsbt":
      let psbt = try Psbt(psbtBase64: request.string("psbt"))
      return try NativeBdkCodec.psbtResult(psbt, unsignedOnly: true)
    default: throw NativeBdkFailure.unsupported
    }
  }

  private func derive(_ request: NativeBdkRequest) throws -> [String: String] {
    let network = try request.network()
    let kind: NetworkKind = network == .bitcoin ? .main : .test
    let script = try request.string("scriptType")
    guard let purpose = ["bip44": 44, "bip49": 49, "bip84": 84, "bip86": 86][script] else {
      throw NativeBdkFailure.invalidRequest
    }
    let fingerprint = try request.string("masterFingerprint")
    guard fingerprint.range(of: "^[0-9a-fA-F]{8}$", options: .regularExpression) != nil else {
      throw NativeBdkFailure.invalidRequest
    }
    let phrase = request.values["mnemonic"] as? String
    let xpub = request.values["xpub"] as? String
    guard (phrase != nil) != (xpub != nil) else { throw NativeBdkFailure.invalidRequest }
    let external: Descriptor
    let change: Descriptor
    let accountXpub: String
    if let phrase = phrase {
      let mnemonic = try Mnemonic.fromString(mnemonic: phrase)
      let key = DescriptorSecretKey(networkKind: kind, mnemonic: mnemonic, password: nil)
      external = secretDescriptor(key, keychain: .external, kind: kind, purpose: purpose)
      change = secretDescriptor(key, keychain: .internal, kind: kind, purpose: purpose)
      let coin = network == .bitcoin ? 0 : 1
      let path = try DerivationPath(path: "m/\(purpose)h/\(coin)h/0h")
      let publicKey = try key.derive(path: path).asPublic().description
      guard let range = publicKey.range(of: "(?:xpub|tpub)[1-9A-HJ-NP-Za-km-z]+", options: .regularExpression) else {
        throw NativeBdkFailure.internalFailure
      }
      accountXpub = String(publicKey[range])
    } else if let xpub = xpub {
      let key = try DescriptorPublicKey.fromString(publicKey: xpub)
      external = try publicDescriptor(key, fingerprint: fingerprint, keychain: .external,
                                      kind: kind, purpose: purpose)
      change = try publicDescriptor(key, fingerprint: fingerprint, keychain: .internal,
                                    kind: kind, purpose: purpose)
      accountXpub = xpub
    } else { throw NativeBdkFailure.invalidRequest }
    return ["external": external.toStringWithSecret(), "internal": change.toStringWithSecret(),
            "accountXpub": accountXpub]
  }

  private func secretDescriptor(_ key: DescriptorSecretKey, keychain: KeychainKind,
                                kind: NetworkKind, purpose: Int) -> Descriptor {
    switch purpose {
    case 44: return Descriptor.newBip44(secretKey: key, keychainKind: keychain, networkKind: kind)
    case 49: return Descriptor.newBip49(secretKey: key, keychainKind: keychain, networkKind: kind)
    case 84: return Descriptor.newBip84(secretKey: key, keychainKind: keychain, networkKind: kind)
    default: return Descriptor.newBip86(secretKey: key, keychainKind: keychain, networkKind: kind)
    }
  }

  private func publicDescriptor(_ key: DescriptorPublicKey, fingerprint: String,
                                keychain: KeychainKind, kind: NetworkKind, purpose: Int) throws -> Descriptor {
    switch purpose {
    case 44: return try Descriptor.newBip44Public(publicKey: key, fingerprint: fingerprint,
                                                keychainKind: keychain, networkKind: kind)
    case 49: return try Descriptor.newBip49Public(publicKey: key, fingerprint: fingerprint,
                                                keychainKind: keychain, networkKind: kind)
    case 84: return try Descriptor.newBip84Public(publicKey: key, fingerprint: fingerprint,
                                                keychainKind: keychain, networkKind: kind)
    default: return try Descriptor.newBip86Public(publicKey: key, fingerprint: fingerprint,
                                                 keychainKind: keychain, networkKind: kind)
    }
  }
}

private final class NativeBdkOwner {
  static let shared = NativeBdkOwner()
  let queue = DispatchQueue(label: "com.kutewallet.app.onchain.owner", qos: .utility)
  private var sessions: [String: NativeBdkSession] = [:]

  func execute(_ method: String, arguments: [String: Any]) throws -> Any? {
    dispatchPrecondition(condition: .onQueue(queue))
    let request = NativeBdkRequest(arguments)
    let walletId = try request.string("walletId")
    let deadline = try request.integer("deadlineMs")
    guard deadline > Int64(Date().timeIntervalSince1970 * 1_000) else {
      throw NativeBdkFailure.timeout
    }
    if method == "open" { return try open(walletId: walletId, request: request) }
    let sessionId = try request.string("sessionId")
    guard let session = sessions[walletId] else {
      if method == "close" { return nil }
      throw NativeBdkFailure.mismatch
    }
    guard session.id == sessionId else { throw NativeBdkFailure.mismatch }

    if method == "close" {
      let deleteTemporary = try request.boolean("deleteTemporary", fallback: false)
      guard !deleteTemporary || session.identity.temporary else {
        throw NativeBdkFailure.invalidRequest
      }
      let path = session.identity.path
      if deleteTemporary { try validateTemporaryPath(path) }
      if let wallet = session.wallet, let persister = session.persister {
        _ = try wallet.persist(persister: persister)
      }
      // Clearing all strong handle references here releases the SQLite owner
      // after any preceding scan/sign/broadcast has actually returned.
      session.release()
      sessions.removeValue(forKey: walletId)
      if deleteTemporary {
        for suffix in ["", "-wal", "-shm"] {
          let file = path + suffix
          if FileManager.default.fileExists(atPath: file) {
            try FileManager.default.removeItem(atPath: file)
          }
        }
      }
      return nil
    }

    guard let wallet = session.wallet, let persister = session.persister else {
      throw NativeBdkFailure.mismatch
    }
    switch method {
    case "snapshot":
      return try snapshot(wallet)
    case "sync":
      let fullScan = try request.boolean("fullScan")
      let update = try session.sync(fullScan: fullScan)
      try wallet.applyUpdate(update: update)
      _ = try wallet.persist(persister: persister)
      return ["fullScan": fullScan, "snapshot": try snapshot(wallet)]
    case "address":
      let keychain = try request.keychain()
      let address: AddressInfo
      switch try request.string("mode") {
      case "nextUnused":
        address = wallet.nextUnusedAddress(keychain: keychain)
        _ = try wallet.persist(persister: persister)
      case "revealNext":
        address = wallet.revealNextAddress(keychain: keychain)
        _ = try wallet.persist(persister: persister)
      case "peek":
        address = wallet.peekAddress(keychain: keychain, index: try request.uint32("index"))
      default: throw NativeBdkFailure.invalidRequest
      }
      return ["address": address.address.description, "index": Int64(address.index)]
    case "build":
      let address: Address
      do {
        address = try Address(address: request.string("address"), network: wallet.network())
      } catch { throw NativeBdkFailure.invalidAddress }
      let amount = try request.uint64("amountSats")
      let drain = try request.boolean("drain")
      guard amount <= 2_100_000_000_000_000, drain || amount > 0 else {
        throw NativeBdkFailure.invalidRequest
      }
      var builder = TxBuilder()
        .feeRate(feeRate: try request.feeRate())
        .setExactSequence(nsequence: 0xFFFFFFFD)
      if drain {
        builder = builder.drainWallet().drainTo(script: address.scriptPubkey())
      } else {
        builder = builder.addRecipient(script: address.scriptPubkey(), amount: Amount.fromSat(satoshi: amount))
      }
      if let values = request.values["selectedUtxos"], !(values is NSNull) {
        guard let outpoints = values as? [[String: Any]], !outpoints.isEmpty else {
          throw NativeBdkFailure.invalidRequest
        }
        let selected = try outpoints.map { value -> OutPoint in
          let outpoint = NativeBdkRequest(value)
          return OutPoint(txid: try Txid.fromString(hex: outpoint.string("txid")),
                          vout: try outpoint.uint32("vout"))
        }
        builder = builder.addUtxos(outpoints: selected).manuallySelectedOnly()
      }
      let psbt = try builder.finish(wallet: wallet)
      _ = try wallet.persist(persister: persister)
      return try NativeBdkCodec.psbtResult(psbt)
    case "bump":
      let builder = BumpFeeTxBuilder(txid: try Txid.fromString(hex: request.string("txid")),
                                     feeRate: try request.feeRate())
        .setExactSequence(nsequence: 0xFFFFFFFD)
      let psbt = try builder.finish(wallet: wallet)
      _ = try wallet.persist(persister: persister)
      return try NativeBdkCodec.psbtResult(psbt)
    case "sign":
      let psbt = try Psbt(psbtBase64: request.string("psbt"))
      let signed = try wallet.sign(psbt: psbt, signOptions: nil)
      var result = try NativeBdkCodec.psbtResult(psbt)
      result["signed"] = signed
      return result
    case "broadcast":
      let payload = try request.string("payload")
      let transaction: BitcoinDevKit.Transaction
      switch try request.string("format") {
      case "psbt":
        let psbt = try Psbt(psbtBase64: payload)
        let signed = try wallet.sign(psbt: psbt, signOptions: nil)
        var finalized = signed
        if !finalized { finalized = try wallet.finalizePsbt(psbt: psbt, signOptions: nil) }
        guard finalized else { throw NativeBdkFailure.invalidTransaction }
        transaction = try psbt.extractTx()
      case "hex":
        transaction = try BitcoinDevKit.Transaction(transactionBytes: NativeBdkCodec.decodeHex(payload))
      default: throw NativeBdkFailure.invalidRequest
      }
      // One submission only. An uncertain response is reconciled by the caller.
      try session.broadcast(transaction)
      return ["txid": transaction.computeTxid().description]
    default:
      throw NativeBdkFailure.unsupported
    }
  }

  private func open(walletId: String, request: NativeBdkRequest) throws -> [String: Any] {
    let suppliedPath = try request.string("dbPath")
    guard suppliedPath.hasPrefix("/") else { throw NativeBdkFailure.invalidRequest }
    let path = URL(fileURLWithPath: suppliedPath).standardizedFileURL.resolvingSymlinksInPath().path
    let appRoot = URL(fileURLWithPath: NSHomeDirectory())
      .standardizedFileURL.resolvingSymlinksInPath().path
    guard path.hasPrefix(appRoot + "/") else { throw NativeBdkFailure.invalidRequest }
    let identity = NativeBdkIdentity(
      path: path,
      descriptor: try request.string("descriptor"),
      changeDescriptor: try request.string("changeDescriptor"),
      network: try request.network(),
      backendKind: try request.string("backendKind"),
      backendUrl: try request.string("backendUrl"),
      temporary: try request.boolean("temporary", fallback: false))
    try identity.validateBackend()
    if identity.temporary { try validateTemporaryPath(path) }
    if let existing = sessions[walletId] {
      guard existing.identity == identity, let wallet = existing.wallet else {
        throw NativeBdkFailure.mismatch
      }
      return ["sessionId": existing.id, "isNewWallet": existing.isNewWallet,
              "snapshot": try snapshot(wallet)]
    }
    // Different wallet IDs must not acquire independent writers to the same DB.
    guard !sessions.values.contains(where: { $0.identity.path == path }) else {
      throw NativeBdkFailure.mismatch
    }
    let existed = FileManager.default.fileExists(atPath: path)
    let session = NativeBdkSession(identity: identity, isNewWallet: !existed)
    do {
      try session.openWallet()
      let initialSnapshot = try snapshot(session.requireWallet())
      sessions[walletId] = session
      return ["sessionId": session.id, "isNewWallet": session.isNewWallet, "snapshot": initialSnapshot]
    } catch {
      // openWallet has unwound its local handles. Drop the retained SQLite
      // owner before cleaning an unsuccessful, newly created recovery DB.
      session.release()
      if identity.temporary && !existed && session.attemptedPersistenceOpen {
        try validateTemporaryPath(path)
        for suffix in ["", "-wal", "-shm"] {
          let file = path + suffix
          if FileManager.default.fileExists(atPath: file) {
            try? FileManager.default.removeItem(atPath: file)
          }
        }
      }
      throw error
    }
  }

  private func validateTemporaryPath(_ path: String) throws {
    let name = URL(fileURLWithPath: path).lastPathComponent
    guard ["bdk_temp_", "bdk_sweep_", "bdk_xpub_check_"].contains(where: name.hasPrefix) else {
      throw NativeBdkFailure.invalidRequest
    }
  }

  private func snapshot(_ wallet: Wallet) throws -> [String: Any] {
    let balance = wallet.balance()
    let transactions = try wallet.transactions().map { canonical -> [String: Any] in
      guard let details = wallet.txDetails(txid: canonical.transaction.computeTxid()) else {
        throw NativeBdkFailure.internalFailure
      }
      return [
        "txid": details.txid.description,
        "sent": try NativeBdkCodec.codecInteger(details.sent.toSat()), "received": try NativeBdkCodec.codecInteger(details.received.toSat()),
        "fee": NativeBdkCodec.nullable(try details.fee.map { try NativeBdkCodec.codecInteger($0.toSat()) }),
        "feeRate": NativeBdkCodec.nullable(details.feeRate.map { Double($0.toSatPerKwu()) / 250.0 }),
        "balanceDelta": details.balanceDelta,
        "chainPosition": try NativeBdkCodec.position(details.chainPosition), "tx": try NativeBdkCodec.transactionSummary(details.tx),
      ]
    }
    let outputs: [[String: Any]] = try wallet.listUnspent().map { output in
      ["outpoint": ["txid": output.outpoint.txid.description, "vout": Int64(output.outpoint.vout)],
       "txout": ["value": try NativeBdkCodec.codecInteger(output.txout.value.toSat()), "scriptPubkey": NativeBdkCodec.hex(output.txout.scriptPubkey.toBytes())],
       "keychain": output.keychain == .external ? "external" : "internal",
       "isSpent": output.isSpent, "derivationIndex": Int64(output.derivationIndex),
       "chainPosition": try NativeBdkCodec.position(output.chainPosition)]
    }
    return [
      "balance": ["confirmed": try NativeBdkCodec.codecInteger(balance.confirmed.toSat()),
                  "trustedPending": try NativeBdkCodec.codecInteger(balance.trustedPending.toSat()),
                  "untrustedPending": try NativeBdkCodec.codecInteger(balance.untrustedPending.toSat()),
                  "immature": try NativeBdkCodec.codecInteger(balance.immature.toSat()), "total": try NativeBdkCodec.codecInteger(balance.total.toSat()),
                  "spendable": try NativeBdkCodec.codecInteger(balance.trustedSpendable.toSat())],
      "transactions": transactions, "utxos": outputs,
    ]
  }
}

/// Pure value conversion. Callers retain and destroy their own BDK handles on
/// their respective queue; this type stores no handles or mutable state.
private enum NativeBdkCodec {
  static func position(_ value: ChainPosition) throws -> [String: Any] {
    switch value {
    case .confirmed(let confirmation, _):
      return ["height": Int64(confirmation.blockId.height),
              "confirmationTime": try codecInteger(confirmation.confirmationTime),
              "blockHash": confirmation.blockId.hash.description, "lastSeen": NSNull()]
    case .unconfirmed(let timestamp):
      return ["height": NSNull(), "confirmationTime": NSNull(), "blockHash": NSNull(),
              "lastSeen": nullable(try timestamp.map { try codecInteger($0) })]
    }
  }

  static func transactionSummary(_ transaction: BitcoinDevKit.Transaction) throws -> [String: Any] {
    let inputs: [[String: Any]] = transaction.input().map { input in
      ["previousOutput": ["txid": input.previousOutput.txid.description,
                          "vout": Int64(input.previousOutput.vout)],
       "sequence": Int64(input.sequence)]
    }
    let outputs: [[String: Any]] = try transaction.output().map { output in
      ["value": try codecInteger(output.value.toSat()), "scriptPubkey": hex(output.scriptPubkey.toBytes())]
    }
    return ["txid": transaction.computeTxid().description, "vsize": Int64(transaction.vsize()),
            "version": Int64(transaction.version()),
            "inputCount": inputs.count, "outputCount": outputs.count,
            "inputs": inputs, "outputs": outputs, "rawHex": hex(transaction.serialize())]
  }

  static func psbtResult(_ psbt: Psbt, unsignedOnly: Bool = false) throws -> [String: Any] {
    // extractTx fills available signatures without finalizing or mutating the
    // PSBT. High-fee/missing-UTXO extraction failures retain the original PSBT.
    let extracted = unsignedOnly ? unsignedTransaction(psbt) :
      ((try? psbt.extractTx()) ?? unsignedTransaction(psbt))
    guard let transaction = extracted else {
      throw NativeBdkFailure.invalidTransaction
    }
    let summary = try transactionSummary(transaction)
    return ["psbt": psbt.serialize(), "feeSats": nullable(try (try? psbt.fee()).map { try codecInteger($0) }),
            "tx": summary]
  }

  private static func unsignedTransaction(_ psbt: Psbt) -> BitcoinDevKit.Transaction? {
    // BIP174 v0 stores the unsigned transaction under global key 0x00. Ledger
    // inspection needs this transaction, and it also supports summaries when
    // extractTx lacks UTXO data. Hardware-wallet metadata stays untouched.
    guard let data = Data(base64Encoded: psbt.serialize()), data.count >= 5,
          data.count <= 16 * 1_024 * 1_024,
          Array(data.prefix(5)) == [0x70, 0x73, 0x62, 0x74, 0xff] else { return nil }
    let bytes = Array(data)
    var offset = 5
    func compactSize() -> UInt64? {
      guard offset < bytes.count else { return nil }
      let first = bytes[offset]
      offset += 1
      if first < 253 { return UInt64(first) }
      let width = first == 253 ? 2 : (first == 254 ? 4 : 8)
      guard width <= bytes.count - offset else { return nil }
      var value: UInt64 = 0
      for index in 0..<width { value |= UInt64(bytes[offset + index]) << (8 * index) }
      offset += width
      return value
    }
    while offset < bytes.count {
      guard let keyLength = compactSize(), keyLength > 0,
            keyLength <= UInt64(bytes.count - offset) else { return nil }
      let keyStart = offset
      offset += Int(keyLength)
      guard let valueLength = compactSize(), valueLength <= UInt64(bytes.count - offset) else { return nil }
      if keyLength == 1 && bytes[keyStart] == 0 {
        return try? BitcoinDevKit.Transaction(
          transactionBytes: Data(bytes[offset..<(offset + Int(valueLength))]))
      }
      offset += Int(valueLength)
    }
    return nil
  }

  static func decodeHex(_ value: String) throws -> Data {
    let bytes = Array(value.utf8)
    guard !bytes.isEmpty, bytes.count.isMultiple(of: 2) else { throw NativeBdkFailure.invalidTransaction }
    var result = Data(capacity: bytes.count / 2)
    func digit(_ byte: UInt8) -> UInt8? {
      switch byte {
      case 48...57: return byte - 48
      case 65...70: return byte - 55
      case 97...102: return byte - 87
      default: return nil
      }
    }
    for index in stride(from: 0, to: bytes.count, by: 2) {
      guard let high = digit(bytes[index]), let low = digit(bytes[index + 1]) else {
        throw NativeBdkFailure.invalidTransaction
      }
      result.append(high * 16 + low)
    }
    return result
  }

  static func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  static func nullable<Value>(_ value: Value?) -> Any {
    if let value = value { return value }
    return NSNull()
  }

  static func codecInteger(_ value: UInt64) throws -> Int64 {
    guard let result = Int64(exactly: value) else { throw NativeBdkFailure.invalidTransaction }
    return result
  }
}

private struct NativeBdkIdentity: Equatable {
  let path: String
  let descriptor: String
  let changeDescriptor: String
  let network: Network
  let backendKind: String
  let backendUrl: String
  let temporary: Bool

  func validateBackend() throws {
    guard let url = URLComponents(string: backendUrl), let scheme = url.scheme?.lowercased(),
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
      throw NativeBdkFailure.invalidRequest
    }
    switch backendKind {
    case "esplora":
      guard scheme == "https" || (scheme == "http" &&
        (network == .regtest || ["localhost", "127.0.0.1", "::1"].contains(host))) else {
        throw NativeBdkFailure.invalidRequest
      }
    case "electrum":
      guard ["ssl", "tcp"].contains(scheme), let port = url.port, port > 0 else {
        throw NativeBdkFailure.invalidRequest
      }
    default: throw NativeBdkFailure.invalidRequest
    }
  }
}

private final class NativeBdkSession {
  let id = UUID().uuidString
  let identity: NativeBdkIdentity
  let isNewWallet: Bool
  var wallet: Wallet?
  var persister: Persister?
  private(set) var attemptedPersistenceOpen = false
  private var esplora: EsploraClient?
  private var electrum: ElectrumClient?

  init(identity: NativeBdkIdentity, isNewWallet: Bool) {
    self.identity = identity
    self.isNewWallet = isNewWallet
  }

  func openWallet() throws {
    let networkKind: NetworkKind = identity.network == .bitcoin ? .main : .test
    let descriptor = try Descriptor(descriptor: identity.descriptor, networkKind: networkKind)
    let changeDescriptor = try Descriptor(descriptor: identity.changeDescriptor, networkKind: networkKind)
    attemptedPersistenceOpen = true
    let store = try Persister.newSqlite(path: identity.path)
    persister = store
    if isNewWallet {
      wallet = try Wallet(descriptor: descriptor, changeDescriptor: changeDescriptor,
                           network: identity.network, persister: store, lookahead: 25)
    } else {
      // Never turn a load error into an empty replacement wallet.
      wallet = try Wallet.load(descriptor: descriptor, changeDescriptor: changeDescriptor,
                                persister: store, lookahead: 25)
    }
    guard try requireWallet().network() == identity.network else { throw NativeBdkFailure.mismatch }
  }

  func requireWallet() throws -> Wallet {
    guard let wallet = wallet else { throw NativeBdkFailure.mismatch }
    return wallet
  }

  private func ensureClient() throws {
    if identity.backendKind == "esplora" {
      if esplora == nil { esplora = EsploraClient(url: identity.backendUrl, proxy: nil) }
    } else if electrum == nil {
      electrum = try ElectrumClient(url: identity.backendUrl, socks5: nil,
                                     timeout: 10, retry: 0, validateDomain: true)
    }
  }

  func sync(fullScan: Bool) throws -> Update {
    guard let wallet = wallet else { throw NativeBdkFailure.mismatch }
    try ensureClient()
    if fullScan {
      let request = try wallet.startFullScan().build()
      if let client = esplora {
        return try client.fullScan(request: request, stopGap: 20, parallelRequests: 2)
      }
      if let client = electrum {
        return try client.fullScan(request: request, stopGap: 20, batchSize: 50, fetchPrevTxouts: false)
      }
    } else {
      let request = try wallet.startSyncWithRevealedSpks().build()
      if let client = esplora { return try client.sync(request: request, parallelRequests: 2) }
      if let client = electrum {
        return try client.sync(request: request, batchSize: 50, fetchPrevTxouts: false)
      }
    }
    throw NativeBdkFailure.internalFailure
  }

  func broadcast(_ transaction: BitcoinDevKit.Transaction) throws {
    try ensureClient()
    if let client = esplora { try client.broadcast(transaction: transaction) }
    else if let client = electrum { _ = try client.transactionBroadcast(tx: transaction) }
    else { throw NativeBdkFailure.internalFailure }
  }

  func release() {
    esplora = nil
    electrum = nil
    wallet = nil
    persister = nil
  }
}

private struct NativeBdkRequest {
  let values: [String: Any]
  init(_ values: [String: Any]) { self.values = values }

  func string(_ key: String) throws -> String {
    guard let value = values[key] as? String, !value.isEmpty else { throw NativeBdkFailure.invalidRequest }
    return value
  }

  func integer(_ key: String) throws -> Int64 {
    guard let value = values[key] as? NSNumber,
          CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
          value.doubleValue >= 0, value.doubleValue < Double(Int64.max),
          NSNumber(value: value.int64Value) == value else { throw NativeBdkFailure.invalidRequest }
    return value.int64Value
  }

  func uint64(_ key: String) throws -> UInt64 { UInt64(try integer(key)) }

  func uint32(_ key: String) throws -> UInt32 {
    guard let value = UInt32(exactly: try integer(key)) else { throw NativeBdkFailure.invalidRequest }
    return value
  }

  func boolean(_ key: String, fallback: Bool? = nil) throws -> Bool {
    if values[key] == nil, let fallback = fallback { return fallback }
    guard let value = values[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
      throw NativeBdkFailure.invalidRequest
    }
    return value.boolValue
  }

  func network() throws -> Network {
    switch try string("network") {
    case "bitcoin": return .bitcoin
    case "testnet": return .testnet
    case "testnet4": return .testnet4
    case "signet": return .signet
    case "regtest": return .regtest
    default: throw NativeBdkFailure.invalidRequest
    }
  }

  func keychain() throws -> KeychainKind {
    switch try string("keychain") {
    case "external": return .external
    case "internal": return .internal
    default: throw NativeBdkFailure.invalidRequest
    }
  }

  func feeRate() throws -> FeeRate {
    let value = try uint64("feeRateSatVb")
    guard value > 0 else { throw NativeBdkFailure.invalidRequest }
    return try FeeRate.fromSatPerVb(satVb: value)
  }
}
