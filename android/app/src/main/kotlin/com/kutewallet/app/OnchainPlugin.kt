package com.kutewallet.app

import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.bitcoindevkit.*
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Only plain codec values cross this channel. All BDK handles stay on the owner thread. */
class OnchainPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var delivery = AtomicBoolean(false)
    private lateinit var dataRoot: File

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        dataRoot = File(binding.applicationContext.applicationInfo.dataDir)
        delivery = AtomicBoolean(true)
        channel = MethodChannel(binding.binaryMessenger, "com.kutewallet.app/onchain")
            .also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        delivery.set(false)
        channel?.setMethodCallHandler(null)
        channel = null
        // Engine/activity replacement must not unlock a database while native work is running.
        // Explicit close is ordered behind earlier work on the process-owned executor.
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("invalid_request", "The wallet request is invalid.", null)
            return
        }
        val currentDelivery = delivery
        val root = dataRoot
        try {
            OnchainOwner.execute(call.method) {
                val reply = try {
                    NativeReply(OnchainOwner.handle(call.method, args, root), null)
                } catch (error: OnchainFailure) {
                    NativeReply(null, error.category)
                } catch (_: LinkageError) {
                    NativeReply(null, "unsupported")
                } catch (_: Exception) {
                    // SDK exceptions can contain keys, addresses and values. Never forward them.
                    NativeReply(null, "internal")
                }
                // MethodChannel.Result supports any thread. Encoding large history snapshots
                // here also keeps that work off the Android platform/UI thread.
                if (currentDelivery.get()) {
                    if (reply.error == null) result.success(reply.value)
                    else result.error(reply.error, OnchainFailure.message(reply.error), null)
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("busy", "The wallet is busy. Try again shortly.", null)
        }
    }
}

private data class NativeReply(val value: Any?, val error: String?)

private class OnchainFailure(val category: String) : Exception() {
    companion object {
        fun message(category: String): String = when (category) {
            "invalid_request" -> "The wallet request is invalid."
            "wallet_open_failed" -> "The wallet could not be opened. Its data was preserved."
            "wallet_mismatch" -> "The wallet session does not match this request."
            "network" -> "The Bitcoin server request did not complete."
            "insufficient_funds" -> "There are insufficient funds for this transaction."
            "invalid_address" -> "The Bitcoin address is invalid for this network."
            "invalid_amount" -> "The amount is below the Bitcoin network minimum."
            "invalid_fee_rate" -> "The fee rate is not usable for this transaction."
            "invalid_transaction" -> "The Bitcoin transaction could not be processed."
            "busy" -> "The wallet is busy. Try again shortly."
            "timeout" -> "The wallet request expired before it started."
            "unsupported" -> "This wallet operation is unavailable on this device."
            else -> "The wallet operation could not be completed."
        }
    }
}

/**
 * Process lifetime ownership also covers recovery wallets and engine reattachment. A caller
 * deadline never interrupts Rust, replaces this executor or releases an in-use SQLite handle.
 * The bounded queue prevents requests from accumulating during a stalled server connection.
 */
private object OnchainOwner {
    private val executor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(64),
        { work -> Thread(work, "kute-onchain").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    // Local key operations must remain available while a wallet waits for a server.
    // These tasks create and dispose their own handles without accessing any session.
    private val statelessExecutor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(32),
        { work -> Thread(work, "kute-onchain-keys").apply { isDaemon = true } },
        ThreadPoolExecutor.AbortPolicy(),
    )
    private val sessions = mutableMapOf<String, WalletSession>()

    fun execute(method: String, work: () -> Unit) =
        (if (method in setOf("mnemonic", "derive", "inspectPsbt")) statelessExecutor else executor)
            .execute(work)

    fun handle(method: String, args: Map<*, *>, dataRoot: File): Any? {
        if (args.integer("deadlineMs") <= System.currentTimeMillis()) fail("timeout")
        when (method) {
            "mnemonic" -> return mnemonic(args)
            "derive" -> return derive(args)
            "inspectPsbt" -> return transactionCall {
                Psbt(args.text("psbt")).owned { psbtResult(it) }
            }
        }
        val walletId = args.text("walletId")
        if (method == "open") return open(walletId, args, dataRoot)
        val sessionId = args.text("sessionId")
        val session = sessions[walletId]
        if (session == null && method == "close") return null
        if (session == null || session.id != sessionId) fail("wallet_mismatch")
        return when (method) {
            "sync" -> sync(session, args)
            "snapshot" -> snapshot(session.wallet)
            "address" -> address(session, args)
            "build" -> build(session, args)
            "bump" -> bump(session, args)
            "sign" -> sign(session, args)
            "broadcast" -> broadcast(session, args)
            "close" -> close(walletId, session, args)
            else -> fail("unsupported")
        }
    }

    private fun mnemonic(args: Map<*, *>): Any = when (args.text("action")) {
        "generate" -> {
            if (args.containsKey("wordCount") && args.integer("wordCount") != 12L) fail("invalid_request")
            Mnemonic(WordCount.WORDS12).owned { it.toString() }
        }
        "validate" -> {
            val phrase = args["mnemonic"] as? String ?: fail("invalid_request")
            try { Mnemonic.fromString(phrase).owned { true } }
            catch (_: Bip39Exception) { false }
        }
        "fromEntropy" -> {
            val entropy = args["entropy"] as? ByteArray ?: fail("invalid_request")
            try { Mnemonic.fromEntropy(entropy).owned { it.toString() } }
            catch (_: Bip39Exception) { fail("invalid_request") }
        }
        else -> fail("invalid_request")
    }

    private fun derive(args: Map<*, *>): Map<String, String> {
        val network = network(args.text("network"))
        val kind = if (network == Network.BITCOIN) NetworkKind.MAIN else NetworkKind.TEST
        val fingerprint = args.text("masterFingerprint")
        if (!Regex("[0-9a-fA-F]{8}").matches(fingerprint)) fail("invalid_request")
        val scriptType = args.text("scriptType")
        val purpose = when (scriptType) {
            "bip44" -> 44
            "bip49" -> 49
            "bip84" -> 84
            "bip86" -> 86
            else -> fail("invalid_request")
        }
        val phrase = args["mnemonic"] as? String
        val xpub = args["xpub"] as? String
        if ((phrase == null) == (xpub == null)) fail("invalid_request")
        return try {
            if (phrase != null) {
                Mnemonic.fromString(phrase).owned { mnemonic ->
                    DescriptorSecretKey(kind, mnemonic, null).owned { secret ->
                        val external = privateDescriptor(scriptType, secret, KeychainKind.EXTERNAL, kind)
                            .owned { it.toStringWithSecret() }
                        val internal = privateDescriptor(scriptType, secret, KeychainKind.INTERNAL, kind)
                            .owned { it.toStringWithSecret() }
                        val coin = if (network == Network.BITCOIN) 0 else 1
                        val accountXpub = DerivationPath("m/${purpose}h/${coin}h/0h").owned { path ->
                            secret.derive(path).owned { account ->
                                account.asPublic().owned { public ->
                                    val bare = Regex("(?:xpub|tpub)[1-9A-HJ-NP-Za-km-z]+")
                                        .find(public.toString())?.value ?: fail("internal")
                                    if (bare.length != 111) fail("internal")
                                    bare
                                }
                            }
                        }
                        mapOf("external" to external, "internal" to internal, "accountXpub" to accountXpub)
                    }
                }
            } else {
                val bare = xpub ?: fail("invalid_request")
                val prefix = if (network == Network.BITCOIN) "xpub" else "tpub"
                if (!Regex("${prefix}[1-9A-HJ-NP-Za-km-z]{107}").matches(bare)) fail("invalid_request")
                DescriptorPublicKey.fromString(bare).owned { public ->
                    val external = publicDescriptor(scriptType, public, fingerprint, KeychainKind.EXTERNAL, kind)
                        .owned { it.toStringWithSecret() }
                    val internal = publicDescriptor(scriptType, public, fingerprint, KeychainKind.INTERNAL, kind)
                        .owned { it.toStringWithSecret() }
                    mapOf("external" to external, "internal" to internal, "accountXpub" to bare)
                }
            }
        } catch (error: OnchainFailure) {
            throw error
        } catch (_: Exception) {
            fail("invalid_request")
        }
    }

    private fun privateDescriptor(type: String, key: DescriptorSecretKey,
        keychain: KeychainKind, network: NetworkKind): Descriptor = when (type) {
        "bip44" -> Descriptor.newBip44(key, keychain, network)
        "bip49" -> Descriptor.newBip49(key, keychain, network)
        "bip84" -> Descriptor.newBip84(key, keychain, network)
        "bip86" -> Descriptor.newBip86(key, keychain, network)
        else -> fail("invalid_request")
    }

    private fun publicDescriptor(type: String, key: DescriptorPublicKey, fingerprint: String,
        keychain: KeychainKind, network: NetworkKind): Descriptor = when (type) {
        "bip44" -> Descriptor.newBip44Public(key, fingerprint, keychain, network)
        "bip49" -> Descriptor.newBip49Public(key, fingerprint, keychain, network)
        "bip84" -> Descriptor.newBip84Public(key, fingerprint, keychain, network)
        "bip86" -> Descriptor.newBip86Public(key, fingerprint, keychain, network)
        else -> fail("invalid_request")
    }

    private fun open(walletId: String, args: Map<*, *>, dataRoot: File): Map<String, Any?> {
        val path = File(args.text("dbPath")).canonicalFile
        val root = dataRoot.canonicalFile
        if (!path.path.startsWith(root.path + File.separator)) fail("invalid_request")
        val descriptor = args.text("descriptor")
        val changeDescriptor = args["changeDescriptor"] as? String
        val network = network(args.text("network"))
        val backendKind = args.text("backendKind")
        val backendUrl = args.text("backendUrl")
        validateBackend(backendKind, backendUrl)
        val temporary = args.flag("temporary", false)
        if (temporary && !temporaryName(path)) fail("invalid_request")
        val identity = identity(path.path, descriptor, changeDescriptor ?: "", network.name,
            backendKind, backendUrl, temporary.toString())
        sessions[walletId]?.let {
            if (it.identity != identity) fail("wallet_mismatch")
            return mapOf("sessionId" to it.id, "isNewWallet" to it.isNewWallet,
                "snapshot" to snapshot(it.wallet))
        }
        if (sessions.values.any { it.path == path }) fail("wallet_mismatch")

        val existed = path.exists()
        if (existed && !path.isFile) fail("wallet_open_failed")
        var persister: Persister? = null
        var wallet: Wallet? = null
        try {
            val kind = if (network == Network.BITCOIN) NetworkKind.MAIN else NetworkKind.TEST
            persister = Persister.newSqlite(path.path)
            val store = persister
            wallet = Descriptor(descriptor, kind).owned { external ->
                if (changeDescriptor == null) {
                    if (existed) Wallet.loadSingle(external, store, 25u)
                    else Wallet.createSingle(external, network, store, 25u)
                } else {
                    Descriptor(changeDescriptor, kind).owned { internal ->
                        if (existed) Wallet.load(external, internal, store, 25u)
                        else Wallet(external, internal, network, store, 25u)
                    }
                }
            }
            if (wallet.network() != network) fail("wallet_open_failed")
            val value = snapshot(wallet)
            val session = WalletSession(UUID.randomUUID().toString(), identity, path,
                temporary, !existed, network, backendKind, backendUrl, wallet, store)
            sessions[walletId] = session
            return mapOf("sessionId" to session.id, "isNewWallet" to session.isNewWallet,
                "snapshot" to value)
        } catch (_: Exception) {
            var disposed = true
            try { wallet?.destroy() } catch (_: Exception) { disposed = false }
            try { persister?.destroy() } catch (_: Exception) { disposed = false }
            // A failed recovery scan must not leave its newly created database behind.
            // Never unlink an existing file or a handle whose release failed.
            if (disposed && temporary && !existed && temporaryName(path)) {
                for (suffix in listOf("-wal", "-shm", "-journal", "")) {
                    try {
                        val file = File(path.path + suffix)
                        if (file.exists()) file.delete()
                    } catch (_: Exception) {
                        // Keep the original sanitized open failure, including cleanup errors.
                    }
                }
            }
            // Existing database failures must never become an empty replacement wallet.
            fail("wallet_open_failed")
        }
    }

    private fun sync(session: WalletSession, args: Map<*, *>): Map<String, Any?> {
        val fullScan = args.flag("fullScan")
        val update = networkCall {
            if (fullScan) {
                session.wallet.startFullScan().owned { builder ->
                    builder.build().owned { request ->
                        if (session.backendKind == "esplora") {
                            session.esplora().fullScan(request, 20uL, 2uL)
                        } else {
                            session.electrum().fullScan(request, 20uL, 50uL, false)
                        }
                    }
                }
            } else {
                session.wallet.startSyncWithRevealedSpks().owned { builder ->
                    builder.build().owned { request ->
                        if (session.backendKind == "esplora") {
                            session.esplora().sync(request, 2uL)
                        } else {
                            session.electrum().sync(request, 50uL, false)
                        }
                    }
                }
            }
        }
        update.owned { session.wallet.applyUpdate(it) }
        session.wallet.persist(session.persister)
        return mapOf("fullScan" to fullScan, "snapshot" to snapshot(session.wallet))
    }

    private fun address(session: WalletSession, args: Map<*, *>): Map<String, Any> {
        val keychain = keychain(args.text("keychain"))
        val mode = args.text("mode")
        val result = when (mode) {
            "nextUnused" -> session.wallet.nextUnusedAddress(keychain)
            "revealNext" -> session.wallet.revealNextAddress(keychain)
            "peek" -> {
                val index = args.uint("index")
                if (index > 0x7FFFFFFFu) fail("invalid_request")
                session.wallet.peekAddress(keychain, index)
            }
            else -> fail("invalid_request")
        }
        return result.owned {
            if (mode != "peek") session.wallet.persist(session.persister)
            mapOf("address" to it.address.toString(), "index" to it.index.toLong())
        }
    }

    private fun build(session: WalletSession, args: Map<*, *>): Map<String, Any?> {
        val destination = try { Address(args.text("address"), session.network) }
            catch (_: Exception) { fail("invalid_address") }
        return destination.owned { address ->
            address.scriptPubkey().owned { script ->
                FeeRate.fromSatPerVb(args.positive("feeRateSatVb").toULong()).owned { rate ->
                    val builders = mutableListOf<TxBuilder>()
                    fun keep(builder: TxBuilder): TxBuilder = builder.also { builders.add(it) }
                    try {
                        var builder = keep(TxBuilder())
                        builder = keep(builder.feeRate(rate))
                        builder = keep(builder.setExactSequence(0xFFFFFFFDu))
                        if (args.flag("drain")) {
                            builder = keep(builder.drainWallet())
                            builder = keep(builder.drainTo(script))
                        } else {
                            Amount.fromSat(args.positive("amountSats").toULong()).owned { amount ->
                                builder = keep(builder.addRecipient(script, amount))
                            }
                        }
                        val selected = args["selectedUtxos"]
                        if (selected != null) {
                            val list = selected as? List<*> ?: fail("invalid_request")
                            if (list.isEmpty() || list.size > 10000) fail("invalid_request")
                            val outpoints = mutableListOf<OutPoint>()
                            try {
                                for (item in list) {
                                    val output = item as? Map<*, *> ?: fail("invalid_request")
                                    val vout = output.uint("vout")
                                    outpoints.add(OutPoint(Txid.fromString(output.text("txid")), vout))
                                }
                                builder = keep(builder.addUtxos(outpoints))
                                builder = keep(builder.manuallySelectedOnly())
                            } finally {
                                outpoints.forEach { it.destroy() }
                            }
                        }
                        transactionCall {
                            builder.finish(session.wallet).owned { psbt ->
                                session.wallet.persist(session.persister)
                                psbtResult(psbt)
                            }
                        }
                    } finally {
                        builders.asReversed().forEach { it.destroy() }
                    }
                }
            }
        }
    }

    private fun bump(session: WalletSession, args: Map<*, *>): Map<String, Any?> = transactionCall {
        Txid.fromString(args.text("txid")).owned { txid ->
            FeeRate.fromSatPerVb(args.positive("feeRateSatVb").toULong()).owned { rate ->
                BumpFeeTxBuilder(txid, rate).owned { builder ->
                    builder.setExactSequence(0xFFFFFFFDu).owned { configured ->
                        configured.finish(session.wallet).owned { psbt ->
                            session.wallet.persist(session.persister)
                            psbtResult(psbt)
                        }
                    }
                }
            }
        }
    }

    private fun sign(session: WalletSession, args: Map<*, *>): Map<String, Any?> = transactionCall {
        Psbt(args.text("psbt")).owned { psbt ->
            val signed = session.wallet.sign(psbt, null)
            psbtResult(psbt) + ("signed" to signed)
        }
    }

    private fun broadcast(session: WalletSession, args: Map<*, *>): Map<String, Any> {
        val payload = args.text("payload")
        val transaction = transactionCall {
            when (args.text("format")) {
                "hex" -> Transaction(decodeHex(payload))
                "psbt" -> Psbt(payload).owned { psbt ->
                    session.wallet.sign(psbt, null)
                    if (!session.wallet.finalizePsbt(psbt, null)) fail("invalid_transaction")
                    psbt.extractTx()
                }
                else -> fail("invalid_request")
            }
        }
        return transaction.owned { tx ->
            val txid = tx.computeTxid().owned { it.toString() }
            // A broadcast is attempted once. A network failure can mean the server accepted it.
            networkCall {
                if (session.backendKind == "esplora") session.esplora().broadcast(tx)
                else session.electrum().transactionBroadcast(tx).destroy()
            }
            mapOf("txid" to txid)
        }
    }

    private fun close(walletId: String, session: WalletSession, args: Map<*, *>): Any? {
        val delete = args.flag("deleteTemporary", false)
        if (delete && (!session.temporary || !temporaryName(session.path))) fail("invalid_request")
        // Flush staged address/change state before releasing the sole database owner.
        session.wallet.persist(session.persister)
        session.dispose()
        sessions.remove(walletId)
        if (delete) {
            for (suffix in listOf("-wal", "-shm", "")) {
                val file = File(session.path.path + suffix)
                if (file.exists() && !file.delete()) fail("internal")
            }
        }
        return null
    }

    private fun snapshot(wallet: Wallet): Map<String, Any?> {
        val balance = wallet.balance().owned {
            mapOf("confirmed" to it.confirmed.toSat().toLong(),
                "trustedPending" to it.trustedPending.toSat().toLong(),
                "untrustedPending" to it.untrustedPending.toSat().toLong(),
                "immature" to it.immature.toSat().toLong(),
                "total" to it.total.toSat().toLong(),
                "spendable" to it.trustedSpendable.toSat().toLong())
        }
        val transactions = wallet.transactions().ownedList { transactions ->
            transactions.map { canonical ->
                canonical.transaction.computeTxid().owned { txid ->
                    val details = wallet.txDetails(txid) ?: fail("internal")
                    details.owned {
                        mapOf("txid" to it.txid.toString(), "sent" to it.sent.toSat().toLong(),
                            "received" to it.received.toSat().toLong(),
                            "fee" to it.fee?.toSat()?.toLong(),
                            "feeRate" to it.feeRate?.toSatPerKwu()?.toDouble()?.div(250.0),
                            "balanceDelta" to it.balanceDelta, "chainPosition" to position(it.chainPosition),
                            "tx" to txSummary(it.tx))
                    }
                }
            }
        }
        val utxos = wallet.listUnspent().ownedList { outputs ->
            outputs.map {
                mapOf("outpoint" to outpoint(it.outpoint), "txout" to txout(it.txout),
                    "keychain" to if (it.keychain == KeychainKind.EXTERNAL) "external" else "internal",
                    "isSpent" to it.isSpent, "derivationIndex" to it.derivationIndex.toLong(),
                    "chainPosition" to position(it.chainPosition))
            }
        }
        return mapOf("balance" to balance, "transactions" to transactions, "utxos" to utxos)
    }

    private fun position(position: ChainPosition): Map<String, Any?> = when (position) {
        is ChainPosition.Confirmed -> mapOf(
            "height" to position.confirmationBlockTime.blockId.height.toLong(),
            "confirmationTime" to position.confirmationBlockTime.confirmationTime.toLong(),
            "blockHash" to position.confirmationBlockTime.blockId.hash.toString(), "lastSeen" to null)
        is ChainPosition.Unconfirmed -> mapOf("height" to null, "confirmationTime" to null,
            "blockHash" to null, "lastSeen" to position.timestamp?.toLong())
    }

    private fun outpoint(outpoint: OutPoint): Map<String, Any> =
        mapOf("txid" to outpoint.txid.toString(), "vout" to outpoint.vout.toLong())

    private fun txout(output: TxOut): Map<String, Any> =
        mapOf("value" to output.value.toSat().toLong(), "scriptPubkey" to hex(output.scriptPubkey.toBytes()))

    private fun txSummary(tx: Transaction): Map<String, Any> {
        val inputs = tx.input().ownedList { inputs ->
            inputs.map { mapOf("previousOutput" to outpoint(it.previousOutput), "sequence" to it.sequence.toLong()) }
        }
        val outputs = tx.output().ownedList { outputs -> outputs.map { txout(it) } }
        return mapOf("txid" to tx.computeTxid().owned { it.toString() },
            "vsize" to tx.vsize().toLong(), "inputCount" to inputs.size.toLong(),
            "outputCount" to outputs.size.toLong(), "rawHex" to hex(tx.serialize()),
            "version" to tx.version().toLong(), "inputs" to inputs, "outputs" to outputs)
    }

    private fun psbtResult(psbt: Psbt): Map<String, Any?> {
        val encoded = psbt.serialize()
        val fee = try { psbt.fee().toLong() } catch (_: Exception) { null }
        val tx = try { psbt.extractTx() } catch (_: Exception) {
            // BDK's fee checks can reject extraction when a hardware PSBT lacks UTXOs.
            // Read the v0 global unsigned transaction without changing any PSBT metadata.
            Transaction(unsignedTransaction(encoded))
        }
        return tx.owned { mapOf("psbt" to encoded, "feeSats" to fee, "tx" to txSummary(it)) }
    }

    private fun unsignedTransaction(psbt: String): ByteArray {
        val bytes = Base64.decode(psbt, Base64.DEFAULT)
        if (bytes.size < 6 || !bytes.copyOfRange(0, 5).contentEquals(byteArrayOf(0x70, 0x73, 0x62, 0x74, 0xff.toByte()))) {
            fail("invalid_transaction")
        }
        var index = 5
        fun size(): Int {
            if (index >= bytes.size) fail("invalid_transaction")
            val first = bytes[index++].toInt() and 255
            if (first < 253) return first
            val width = when (first) { 253 -> 2; 254 -> 4; else -> 8 }
            if (index + width > bytes.size) fail("invalid_transaction")
            var value = 0uL
            for (offset in 0 until width) value = value or ((bytes[index++].toULong() and 255uL) shl (offset * 8))
            if (value > bytes.size.toULong()) fail("invalid_transaction")
            return value.toInt()
        }
        while (index < bytes.size) {
            val keySize = size()
            if (keySize == 0) break
            if (keySize > bytes.size - index) fail("invalid_transaction")
            val unsigned = keySize == 1 && bytes[index] == 0.toByte()
            index += keySize
            val valueSize = size()
            if (valueSize > bytes.size - index) fail("invalid_transaction")
            if (unsigned) return bytes.copyOfRange(index, index + valueSize)
            index += valueSize
        }
        fail("invalid_transaction")
    }

    private fun validateBackend(kind: String, url: String) {
        val uri = try { URI(url) } catch (_: Exception) { fail("invalid_request") }
        if (uri.host.isNullOrEmpty() || uri.userInfo != null || uri.fragment != null) fail("invalid_request")
        when (kind) {
            "esplora" -> if (uri.scheme != "https" && uri.scheme != "http") fail("invalid_request")
            "electrum" -> if (uri.scheme != "ssl" && uri.scheme != "tcp") fail("invalid_request")
            else -> fail("unsupported")
        }
    }

    private fun network(value: String): Network = when (value) {
        "bitcoin" -> Network.BITCOIN
        "testnet" -> Network.TESTNET
        "testnet4" -> Network.TESTNET4
        "signet" -> Network.SIGNET
        "regtest" -> Network.REGTEST
        else -> fail("invalid_request")
    }

    private fun keychain(value: String): KeychainKind = when (value) {
        "external" -> KeychainKind.EXTERNAL
        "internal" -> KeychainKind.INTERNAL
        else -> fail("invalid_request")
    }

    private fun temporaryName(path: File): Boolean = listOf("bdk_temp_", "bdk_sweep_", "bdk_xpub_check_")
        .any { path.name.startsWith(it) }

    private fun identity(vararg fields: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        fields.forEach { field ->
            val bytes = field.toByteArray(Charsets.UTF_8)
            digest.update(bytes.size.toString().toByteArray(Charsets.US_ASCII))
            digest.update(0.toByte())
            digest.update(bytes)
        }
        return hex(digest.digest())
    }

    private inline fun <T> networkCall(block: () -> T): T = try { block() }
        catch (error: OnchainFailure) { throw error }
        catch (_: Exception) { fail("network") }

    private inline fun <T> transactionCall(block: () -> T): T = try { block() }
        catch (error: OnchainFailure) { throw error }
        catch (_: CreateTxException.InsufficientFunds) { fail("insufficient_funds") }
        catch (error: Exception) { fail(transactionFailureCode(error)) }
}

private class WalletSession(
    val id: String,
    val identity: String,
    val path: File,
    val temporary: Boolean,
    val isNewWallet: Boolean,
    val network: Network,
    val backendKind: String,
    private val backendUrl: String,
    val wallet: Wallet,
    val persister: Persister,
) {
    private var esploraClient: EsploraClient? = null
    private var electrumClient: ElectrumClient? = null

    fun esplora(): EsploraClient = esploraClient ?: EsploraClient(backendUrl, null)
        .also { esploraClient = it }

    fun electrum(): ElectrumClient = electrumClient ?: ElectrumClient(
        backendUrl, socks5 = null, timeout = 10u.toUByte(), retry = 0u.toUByte(), validateDomain = true,
    ).also { electrumClient = it }

    fun dispose() {
        esploraClient?.destroy()
        electrumClient?.destroy()
        wallet.destroy()
        persister.destroy()
    }
}

private fun fail(category: String): Nothing = throw OnchainFailure(category)

/**
 * BDK names the reason a transaction could not be built, and reporting every
 * failure that is not InsufficientFunds as one generic category destroyed it:
 * the send flow could then only word a dust amount, an unusable fee rate and a
 * coin that is no longer there as the same "check the amount and address"
 * sentence. Only the exception's CLASS NAME is read here — never its message,
 * which can carry descriptors, addresses or amounts — and it is mapped to a
 * fixed category from the channel's allowed set.
 */
private fun transactionFailureCode(error: Throwable): String {
    val names = generateSequence(error) { it.cause }
        .take(8)
        .joinToString(" ") { it.javaClass.simpleName }
    return when {
        names.contains("InsufficientFunds", true) -> "insufficient_funds"
        names.contains("Dust", true) -> "invalid_amount"
        names.contains("FeeRate", true) || names.contains("FeeTooLow", true) ||
            names.contains("FeeTooHigh", true) -> "invalid_fee_rate"
        names.contains("Utxo", true) || names.contains("OutPoint", true) ||
            names.contains("SpendingPolicy", true) -> "invalid_request"
        names.contains("Address", true) || names.contains("Script", true) -> "invalid_address"
        else -> "invalid_transaction"
    }
}

private fun Map<*, *>.text(name: String): String =
    (this[name] as? String)?.takeIf { it.isNotBlank() } ?: fail("invalid_request")

private fun Map<*, *>.integer(name: String): Long = when (val value = this[name]) {
    is Long -> value
    is Int -> value.toLong()
    else -> fail("invalid_request")
}

private fun Map<*, *>.positive(name: String): Long = integer(name).also { if (it <= 0) fail("invalid_request") }

private fun Map<*, *>.uint(name: String): UInt = integer(name).also {
    if (it < 0 || it > UInt.MAX_VALUE.toLong()) fail("invalid_request")
}.toUInt()

private fun Map<*, *>.flag(name: String, default: Boolean? = null): Boolean =
    if (containsKey(name)) this[name] as? Boolean ?: fail("invalid_request")
    else default ?: fail("invalid_request")

private inline fun <T : Disposable, R> T.owned(block: (T) -> R): R = try { block(this) }
    finally { destroy() }

private inline fun <T : Disposable, R> List<T>.ownedList(block: (List<T>) -> R): R = try { block(this) }
    finally { forEach { it.destroy() } }

private fun hex(bytes: ByteArray): String {
    val chars = "0123456789abcdef"
    return buildString(bytes.size * 2) {
        bytes.forEach { byte ->
            val value = byte.toInt() and 255
            append(chars[value ushr 4])
            append(chars[value and 15])
        }
    }
}

private fun decodeHex(value: String): ByteArray {
    if (value.isEmpty() || value.length % 2 != 0 || value.length > 8_000_000) fail("invalid_transaction")
    return ByteArray(value.length / 2) { index ->
        val high = value[index * 2].digitToIntOrNull(16) ?: fail("invalid_transaction")
        val low = value[index * 2 + 1].digitToIntOrNull(16) ?: fail("invalid_transaction")
        ((high shl 4) or low).toByte()
    }
}
