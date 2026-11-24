/**
 * A Bitcoin address.
 */
export class Address {
    static __wrap(ptr) {
        const obj = Object.create(Address.prototype);
        obj.__wbg_ptr = ptr;
        AddressFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        AddressFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_address_free(ptr, 0);
    }
    /**
     * @returns {Address}
     */
    clone() {
        const ret = wasm.address_clone(this.__wbg_ptr);
        return Address.__wrap(ret);
    }
    /**
     * Constructs an [`Address`] from an output script (`scriptPubkey`).
     * @param {ScriptBuf} script_buf
     * @param {Network} network
     * @returns {Address}
     */
    static from_script(script_buf, network) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(script_buf, ScriptBuf);
            var ptr0 = script_buf.__destroy_into_raw();
            wasm.address_from_script(retptr, ptr0, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Address.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {string} address_str
     * @param {Network} network
     * @returns {Address}
     */
    static from_string(address_str, network) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(address_str, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.address_from_string(retptr, ptr0, len0, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Address.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {ScriptBuf}
     */
    get script_pubkey() {
        const ret = wasm.address_script_pubkey(this.__wbg_ptr);
        return ScriptBuf.__wrap(ret);
    }
    /**
     * @returns {string}
     */
    toString() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.address_toString(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) Address.prototype[Symbol.dispose] = Address.prototype.free;

/**
 * A derived address and the index it was found at.
 */
export class AddressInfo {
    static __wrap(ptr) {
        const obj = Object.create(AddressInfo.prototype);
        obj.__wbg_ptr = ptr;
        AddressInfoFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        AddressInfoFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_addressinfo_free(ptr, 0);
    }
    /**
     * Address
     * @returns {Address}
     */
    get address() {
        const ret = wasm.addressinfo_address(this.__wbg_ptr);
        return Address.__wrap(ret);
    }
    /**
     * Gets the address type of the address.
     *
     * # Returns
     *
     * None if unknown, non-standard or related to the future witness version.
     * @returns {AddressType | undefined}
     */
    get address_type() {
        const ret = wasm.addressinfo_address_type(this.__wbg_ptr);
        return __wbindgen_enum_AddressType[ret];
    }
    /**
     * @returns {AddressInfo}
     */
    clone() {
        const ret = wasm.addressinfo_clone(this.__wbg_ptr);
        return AddressInfo.__wrap(ret);
    }
    /**
     * Child index of this address
     * @returns {number}
     */
    get index() {
        const ret = wasm.addressinfo_index(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Type of keychain
     * @returns {KeychainKind}
     */
    get keychain() {
        const ret = wasm.addressinfo_keychain(this.__wbg_ptr);
        return __wbindgen_enum_KeychainKind[ret];
    }
}
if (Symbol.dispose) AddressInfo.prototype[Symbol.dispose] = AddressInfo.prototype.free;

/**
 * Amount
 *
 * The [Amount] type can be used to express Bitcoin amounts that support
 * arithmetic and conversion to various denominations.
 */
export class Amount {
    static __wrap(ptr) {
        const obj = Object.create(Amount.prototype);
        obj.__wbg_ptr = ptr;
        AmountFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        AmountFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_amount_free(ptr, 0);
    }
    /**
     * @param {number} btc
     * @returns {Amount}
     */
    static from_btc(btc) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.amount_from_btc(retptr, btc);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Amount.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {bigint} satoshi
     * @returns {Amount}
     */
    static from_sat(satoshi) {
        const ret = wasm.amount_from_sat(satoshi);
        return Amount.__wrap(ret);
    }
    /**
     * Check whether or not a value is below dust limit
     * for a given script
     * @param {ScriptBuf} script
     * @returns {boolean}
     */
    is_dust(script) {
        _assertClass(script, ScriptBuf);
        var ptr0 = script.__destroy_into_raw();
        const ret = wasm.amount_is_dust(this.__wbg_ptr, ptr0);
        return ret !== 0;
    }
    /**
     * Express this [`Amount`] as a floating-point value in Bitcoin.
     *
     * Please be aware of the risk of using floating-point numbers.
     * @returns {number}
     */
    to_btc() {
        const ret = wasm.amount_to_btc(this.__wbg_ptr);
        return ret;
    }
    /**
     * Express this [Amount] as a floating-point value in the given denomination.
     *
     * Please be aware of the risk of using floating-point numbers.
     * @param {Denomination} denom
     * @returns {number}
     */
    to_float_in(denom) {
        const ret = wasm.amount_to_float_in(this.__wbg_ptr, (__wbindgen_enum_Denomination.indexOf(denom) + 1 || 10) - 1);
        return ret;
    }
    /**
     * Gets the number of satoshis in this [`Amount`].
     * @returns {bigint}
     */
    to_sat() {
        const ret = wasm.amount_to_sat(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
}
if (Symbol.dispose) Amount.prototype[Symbol.dispose] = Amount.prototype.free;

/**
 * Balance, differentiated into various categories.
 */
export class Balance {
    static __wrap(ptr) {
        const obj = Object.create(Balance.prototype);
        obj.__wbg_ptr = ptr;
        BalanceFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        BalanceFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_balance_free(ptr, 0);
    }
    /**
     * Confirmed and immediately spendable balance
     * @returns {Amount}
     */
    get confirmed() {
        const ret = wasm.balance_confirmed(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * All coinbase outputs not yet matured
     * @returns {Amount}
     */
    get immature() {
        const ret = wasm.balance_immature(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Get the whole balance visible to the wallet.
     * @returns {Amount}
     */
    get total() {
        const ret = wasm.balance_total(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Unconfirmed UTXOs generated by a wallet tx
     * @returns {Amount}
     */
    get trusted_pending() {
        const ret = wasm.balance_trusted_pending(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Get sum of trusted_pending and confirmed coins.
     *
     * This is the balance you can spend right now that shouldn't get cancelled via another party
     * double spending it.
     * @returns {Amount}
     */
    get trusted_spendable() {
        const ret = wasm.balance_trusted_spendable(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Unconfirmed UTXOs received from an external wallet
     * @returns {Amount}
     */
    get untrusted_pending() {
        const ret = wasm.balance_untrusted_pending(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
}
if (Symbol.dispose) Balance.prototype[Symbol.dispose] = Balance.prototype.free;

export class BdkError {
    static __wrap(ptr) {
        const obj = Object.create(BdkError.prototype);
        obj.__wbg_ptr = ptr;
        BdkErrorFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        BdkErrorFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_bdkerror_free(ptr, 0);
    }
    /**
     * @returns {BdkErrorCode}
     */
    get code() {
        const ret = wasm.bdkerror_code(this.__wbg_ptr);
        return ret;
    }
    /**
     * @returns {any}
     */
    get data() {
        const ret = wasm.bdkerror_data(this.__wbg_ptr);
        return takeObject(ret);
    }
    /**
     * @returns {string}
     */
    get message() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.bdkerror_message(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) BdkError.prototype[Symbol.dispose] = BdkError.prototype.free;

/**
 * @enum {0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39}
 */
export const BdkErrorCode = Object.freeze({
    /**
     * ------- Transaction creation errors -------
     * There was a problem with the descriptors passed in
     */
    Descriptor: 0, "0": "Descriptor",
    /**
     * There was a problem while extracting and manipulating policies
     */
    Policy: 1, "1": "Policy",
    /**
     * Spending policy is not compatible with this [`KeychainKind`]
     */
    SpendingPolicyRequired: 2, "2": "SpendingPolicyRequired",
    /**
     * Requested invalid transaction version '0'
     */
    Version0: 3, "3": "Version0",
    /**
     * Requested transaction version `1`, but at least `2` is needed to use OP_CSV
     */
    Version1Csv: 4, "4": "Version1Csv",
    /**
     * Requested `LockTime` is less than is required to spend from this script
     */
    LockTime: 5, "5": "LockTime",
    /**
     * Cannot enable RBF with `Sequence` given a required OP_CSV
     */
    RbfSequenceCsv: 6, "6": "RbfSequenceCsv",
    /**
     * When bumping a tx the absolute fee requested is lower than replaced tx absolute fee
     */
    FeeTooLow: 7, "7": "FeeTooLow",
    /**
     * When bumping a tx the fee rate requested is lower than required
     */
    FeeRateTooLow: 8, "8": "FeeRateTooLow",
    /**
     * `manually_selected_only` option is selected but no utxo has been passed
     */
    NoUtxosSelected: 9, "9": "NoUtxosSelected",
    /**
     * Output created is under the dust limit, 546 satoshis
     */
    OutputBelowDustLimit: 10, "10": "OutputBelowDustLimit",
    /**
     * Wallet's UTXO set is not enough to cover recipient's requested plus fee.
     */
    InsufficientFunds: 11, "11": "InsufficientFunds",
    /**
     * Cannot build a tx without recipients
     */
    NoRecipients: 12, "12": "NoRecipients",
    /**
     * Partially signed bitcoin transaction error
     */
    Psbt: 13, "13": "Psbt",
    /**
     * In order to use the [`TxBuilder::add_global_xpubs`] option every extended
     * key in the descriptor must either be a master key itself (having depth = 0) or have an
     * explicit origin provided
     *
     * [`TxBuilder::add_global_xpubs`]: crate::wallet::tx_builder::TxBuilder::add_global_xpubs
     */
    MissingKeyOrigin: 14, "14": "MissingKeyOrigin",
    /**
     * Happens when trying to spend an UTXO that is not in the internal database
     */
    UnknownUtxo: 15, "15": "UnknownUtxo",
    /**
     * Missing non_witness_utxo on foreign utxo for given `OutPoint`
     */
    MissingNonWitnessUtxo: 16, "16": "MissingNonWitnessUtxo",
    /**
     * Miniscript PSBT error
     */
    MiniscriptPsbt: 17, "17": "MiniscriptPsbt",
    /**
     * ------- Fee bump errors -------
     * Transaction not found in the internal database
     */
    TransactionNotFound: 18, "18": "TransactionNotFound",
    /**
     * Transaction is already confirmed, cannot fee-bump
     */
    TransactionConfirmed: 19, "19": "TransactionConfirmed",
    /**
     * Transaction does not signal RBF (sequence >= 0xFFFFFFFE)
     */
    IrreplaceableTransaction: 20, "20": "IrreplaceableTransaction",
    /**
     * Fee rate data is unavailable
     */
    FeeRateUnavailable: 21, "21": "FeeRateUnavailable",
    /**
     * Input references an invalid output index
     */
    InvalidOutputIndex: 22, "22": "InvalidOutputIndex",
    /**
     * ------- Address errors -------
     * Base58 error.
     */
    Base58: 23, "23": "Base58",
    /**
     * Bech32 segwit decoding error.
     */
    Bech32: 24, "24": "Bech32",
    /**
     * A witness version conversion/parsing error.
     */
    WitnessVersion: 25, "25": "WitnessVersion",
    /**
     * A witness program error.
     */
    WitnessProgram: 26, "26": "WitnessProgram",
    /**
     * Tried to parse an unknown HRP.
     */
    UnknownHrp: 27, "27": "UnknownHrp",
    /**
     * Legacy address is too long.
     */
    LegacyAddressTooLong: 28, "28": "LegacyAddressTooLong",
    /**
     * Invalid base58 payload data length for legacy address.
     */
    InvalidBase58PayloadLength: 29, "29": "InvalidBase58PayloadLength",
    /**
     * Invalid legacy address prefix in base58 data payload.
     */
    InvalidLegacyPrefix: 30, "30": "InvalidLegacyPrefix",
    /**
     * Address's network differs from required one.
     */
    NetworkValidation: 31, "31": "NetworkValidation",
    /**
     * ------- Amount errors -------
     * The amount is too big or too small.
     */
    OutOfRange: 32, "32": "OutOfRange",
    /**
     * Amount has higher precision than supported by the type.
     */
    TooPrecise: 33, "33": "TooPrecise",
    /**
     * A digit was expected but not found.
     */
    MissingDigits: 34, "34": "MissingDigits",
    /**
     * Input string was too large.
     */
    InputTooLarge: 35, "35": "InputTooLarge",
    /**
     * Invalid character in input.
     */
    InvalidCharacter: 36, "36": "InvalidCharacter",
    /**
     * ------- Block application errors -------
     * Cannot connect block to the existing chain
     */
    CannotConnect: 37, "37": "CannotConnect",
    /**
     * Connected-to hash does not match the expected hash
     */
    UnexpectedConnectedToHash: 38, "38": "UnexpectedConnectedToHash",
    /**
     * ------- Other errors -------
     * Unexpected error, should never happen
     */
    Unexpected: 39, "39": "Unexpected",
});

/**
 * A full Bitcoin block (header + transactions).
 *
 * Construct from consensus-encoded bytes using `Block.from_bytes()`.
 */
export class Block {
    static __wrap(ptr) {
        const obj = Object.create(Block.prototype);
        obj.__wbg_ptr = ptr;
        BlockFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        BlockFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_block_free(ptr, 0);
    }
    /**
     * Returns the block hash.
     * @returns {string}
     */
    get block_hash() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.block_block_hash(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Deserialize a block from consensus-encoded bytes.
     *
     * Accepts a `Uint8Array` of raw block bytes as produced by Bitcoin Core
     * or any standard Bitcoin serializer.
     * @param {Uint8Array} bytes
     * @returns {Block}
     */
    static from_bytes(bytes) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passArray8ToWasm0(bytes, wasm.__wbindgen_export);
            const len0 = WASM_VECTOR_LEN;
            wasm.block_from_bytes(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Block.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns the previous block hash from the header.
     * @returns {string}
     */
    get prev_blockhash() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.block_prev_blockhash(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Returns the block header timestamp.
     * @returns {number}
     */
    get time() {
        const ret = wasm.block_time(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Returns the number of transactions in the block.
     * @returns {number}
     */
    get tx_count() {
        const ret = wasm.block_tx_count(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Returns the list of transactions in the block.
     * @returns {Transaction[]}
     */
    get txdata() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.block_txdata(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
}
if (Symbol.dispose) Block.prototype[Symbol.dispose] = Block.prototype.free;

/**
 * A reference to a block in the canonical chain.
 */
export class BlockId {
    static __wrap(ptr) {
        const obj = Object.create(BlockId.prototype);
        obj.__wbg_ptr = ptr;
        BlockIdFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        BlockIdFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_blockid_free(ptr, 0);
    }
    /**
     * The hash of the block.
     * @returns {string}
     */
    get hash() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.blockid_hash(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * The height of the block.
     * @returns {number}
     */
    get height() {
        const ret = wasm.blockid_height(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Create a new `BlockId` from a height and block hash string.
     * @param {number} height
     * @param {string} hash
     */
    constructor(height, hash) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(hash, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.blockid_new(retptr, height, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            this.__wbg_ptr = r0;
            BlockIdFinalization.register(this, this.__wbg_ptr, this);
            return this;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
}
if (Symbol.dispose) BlockId.prototype[Symbol.dispose] = BlockId.prototype.free;

/**
 * Represents the observed position of some chain data.
 */
export class ChainPosition {
    static __wrap(ptr) {
        const obj = Object.create(ChainPosition.prototype);
        obj.__wbg_ptr = ptr;
        ChainPositionFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ChainPositionFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_chainposition_free(ptr, 0);
    }
    /**
     * The [`Anchor`].
     * @returns {ConfirmationBlockTime | undefined}
     */
    get anchor() {
        const ret = wasm.chainposition_anchor(this.__wbg_ptr);
        return ret === 0 ? undefined : ConfirmationBlockTime.__wrap(ret);
    }
    /**
     * Determines the upper bound of the confirmation height.
     * @returns {number | undefined}
     */
    get confirmation_height_upper_bound() {
        const ret = wasm.chainposition_confirmation_height_upper_bound(this.__wbg_ptr);
        return ret === Number.MAX_SAFE_INTEGER ? undefined : ret;
    }
    /**
     * When the chain data was first seen in the mempool.
     *
     * This value will be `None` if the chain data was never seen in the mempool.
     * @returns {bigint | undefined}
     */
    get first_seen() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.chainposition_first_seen(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r2 = getDataViewMemory0().getBigInt64(retptr + 8 * 1, true);
            return r0 === 0 ? undefined : BigInt.asUintN(64, r2);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns whether [`ChainPosition`] is confirmed or not.
     * @returns {boolean}
     */
    get is_confirmed() {
        const ret = wasm.chainposition_is_confirmed(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * When the chain data is last seen in the mempool.
     *
     * This value will be `None` if the chain data was never seen in the mempool and only seen
     * in a conflicting chain.
     * @returns {bigint | undefined}
     */
    get last_seen() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.chainposition_last_seen(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r2 = getDataViewMemory0().getBigInt64(retptr + 8 * 1, true);
            return r0 === 0 ? undefined : BigInt.asUintN(64, r2);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Whether the chain data is anchored transitively by a child transaction.
     *
     * If the value is `Some`, it means we have incomplete data. We can only deduce that the
     * chain data is confirmed at a block equal to or lower than the block referenced by `A`.
     * @returns {Txid | undefined}
     */
    get transitively() {
        const ret = wasm.chainposition_transitively(this.__wbg_ptr);
        return ret === 0 ? undefined : Txid.__wrap(ret);
    }
}
if (Symbol.dispose) ChainPosition.prototype[Symbol.dispose] = ChainPosition.prototype.free;

/**
 * A changeset for [`Wallet`].
 */
export class ChangeSet {
    static __wrap(ptr) {
        const obj = Object.create(ChangeSet.prototype);
        obj.__wbg_ptr = ptr;
        ChangeSetFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ChangeSetFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_changeset_free(ptr, 0);
    }
    /**
     * Create a new `ChangeSet` from a JSON string.
     * @param {string} val
     * @returns {ChangeSet}
     */
    static from_json(val) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(val, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.changeset_from_json(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return ChangeSet.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {boolean}
     */
    is_empty() {
        const ret = wasm.changeset_is_empty(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * Merge another [`ChangeSet`] into itself.
     *
     * Conflicting non-empty descriptors or networks return an error without modifying
     * the destination. Missing identity fields are allowed in incremental changesets;
     * callers remain responsible for ensuring those changes belong to the same wallet.
     * @param {ChangeSet} other
     */
    merge(other) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(other, ChangeSet);
            var ptr0 = other.__destroy_into_raw();
            wasm.changeset_merge(retptr, this.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            if (r1) {
                throw takeObject(r0);
            }
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Serialize `ChangeSet` to JSON.
     * @returns {string}
     */
    to_json() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.changeset_to_json(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) ChangeSet.prototype[Symbol.dispose] = ChangeSet.prototype.free;

/**
 * Policy regarding the use of change outputs when creating a transaction.
 * @enum {0 | 1 | 2}
 */
export const ChangeSpendPolicy = Object.freeze({
    /**
     * Use both change and non-change outputs (default)
     */
    ChangeAllowed: 0, "0": "ChangeAllowed",
    /**
     * Only use change outputs
     */
    OnlyChange: 1, "1": "OnlyChange",
    /**
     * Do not use any change outputs
     */
    ChangeForbidden: 2, "2": "ChangeForbidden",
});

/**
 * A checkpoint is a node of a reference-counted linked list of [`BlockId`]s.
 *
 * Checkpoints are cheaply cloneable and are useful to find the agreement point between two sparse
 * block chains.
 */
export class CheckPoint {
    static __wrap(ptr) {
        const obj = Object.create(CheckPoint.prototype);
        obj.__wbg_ptr = ptr;
        CheckPointFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        CheckPointFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_checkpoint_free(ptr, 0);
    }
    /**
     * Get the [`BlockId`] of the checkpoint.
     * @returns {BlockId}
     */
    get block_id() {
        const ret = wasm.checkpoint_block_id(this.__wbg_ptr);
        return BlockId.__wrap(ret);
    }
    /**
     * Get checkpoint at `height`.
     *
     * Returns `None` if checkpoint at `height` does not exist.
     * @param {number} height
     * @returns {CheckPoint | undefined}
     */
    get(height) {
        const ret = wasm.checkpoint_get(this.__wbg_ptr, height);
        return ret === 0 ? undefined : CheckPoint.__wrap(ret);
    }
    /**
     * Get the block hash of the checkpoint.
     * @returns {string}
     */
    get hash() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.checkpoint_hash(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Get the height of the checkpoint.
     * @returns {number}
     */
    get height() {
        const ret = wasm.checkpoint_height(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Get the previous checkpoint in the chain
     * @returns {CheckPoint | undefined}
     */
    get prev() {
        const ret = wasm.checkpoint_prev(this.__wbg_ptr);
        return ret === 0 ? undefined : CheckPoint.__wrap(ret);
    }
}
if (Symbol.dispose) CheckPoint.prototype[Symbol.dispose] = CheckPoint.prototype.free;

/**
 * CSV / CLTV requirements for transaction construction.
 *
 * Prefer `Policy.get_condition()` when selecting a descriptor spending path.
 */
export class Condition {
    static __wrap(ptr) {
        const obj = Object.create(Condition.prototype);
        obj.__wbg_ptr = ptr;
        ConditionFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ConditionFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_condition_free(ptr, 0);
    }
    /**
     * Optional consensus nSequence requirement.
     * @returns {number | undefined}
     */
    get csv() {
        const ret = wasm.condition_csv(this.__wbg_ptr);
        return ret === Number.MAX_SAFE_INTEGER ? undefined : ret;
    }
    /**
     * Combine requirements from every keychain whose inputs may be selected.
     *
     * Returns a new condition with the stricter requirements; neither input is
     * changed or consumed. Mixing height and time units returns an error.
     * @param {Condition} other
     * @returns {Condition}
     */
    merge(other) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(other, Condition);
            wasm.condition_merge(retptr, this.__wbg_ptr, other.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Condition.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Construct known requirements directly, or omit both for an immediate path.
     *
     * `csv` is a consensus nSequence value: blocks, or bit 22 plus units of 512
     * seconds. The disable flag is rejected and unused BIP68 bits are cleared.
     * `timelock` is consensus nLockTime:
     * heights below 500,000,000, Unix seconds otherwise. Both must be unsigned
     * 32-bit integers. These values are not checked against a descriptor.
     * @param {number | null} [csv]
     * @param {number | null} [timelock]
     */
    constructor(csv, timelock) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.condition_new(retptr, !isLikeNone(csv), isLikeNone(csv) ? 0 : csv, !isLikeNone(timelock), isLikeNone(timelock) ? 0 : timelock);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            this.__wbg_ptr = r0;
            ConditionFinalization.register(this, this.__wbg_ptr, this);
            return this;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Optional consensus nLockTime requirement.
     * @returns {number | undefined}
     */
    get timelock() {
        const ret = wasm.condition_timelock(this.__wbg_ptr);
        return ret === Number.MAX_SAFE_INTEGER ? undefined : ret;
    }
}
if (Symbol.dispose) Condition.prototype[Symbol.dispose] = Condition.prototype.free;

/**
 * Represents the observed position of some chain data.
 */
export class ConfirmationBlockTime {
    static __wrap(ptr) {
        const obj = Object.create(ConfirmationBlockTime.prototype);
        obj.__wbg_ptr = ptr;
        ConfirmationBlockTimeFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ConfirmationBlockTimeFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_confirmationblocktime_free(ptr, 0);
    }
    /**
     * The anchor block.
     * @returns {BlockId}
     */
    get block_id() {
        const ret = wasm.confirmationblocktime_block_id(this.__wbg_ptr);
        return BlockId.__wrap(ret);
    }
    /**
     * The confirmation time of the transaction being anchored.
     * @returns {bigint}
     */
    get confirmation_time() {
        const ret = wasm.confirmationblocktime_confirmation_time(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
}
if (Symbol.dispose) ConfirmationBlockTime.prototype[Symbol.dispose] = ConfirmationBlockTime.prototype.free;

/**
 * Pair of descriptors for external and internal keychains
 */
export class DescriptorPair {
    static __wrap(ptr) {
        const obj = Object.create(DescriptorPair.prototype);
        obj.__wbg_ptr = ptr;
        DescriptorPairFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        DescriptorPairFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_descriptorpair_free(ptr, 0);
    }
    /**
     * @returns {string}
     */
    get external() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.descriptorpair_external(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    get internal() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.descriptorpair_internal(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @param {string} external
     * @param {string} internal
     */
    constructor(external, internal) {
        const ptr0 = passStringToWasm0(external, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(internal, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len1 = WASM_VECTOR_LEN;
        const ret = wasm.descriptorpair_new(ptr0, len0, ptr1, len1);
        this.__wbg_ptr = ret;
        DescriptorPairFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
}
if (Symbol.dispose) DescriptorPair.prototype[Symbol.dispose] = DescriptorPair.prototype.free;

export class EsploraClient {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        EsploraClientFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_esploraclient_free(ptr, 0);
    }
    /**
     * @param {Transaction} transaction
     * @returns {Promise<void>}
     */
    broadcast(transaction) {
        _assertClass(transaction, Transaction);
        const ret = wasm.esploraclient_broadcast(this.__wbg_ptr, transaction.__wbg_ptr);
        return takeObject(ret);
    }
    /**
     * @param {FullScanRequest} request
     * @param {number} stop_gap
     * @param {number} parallel_requests
     * @returns {Promise<Update>}
     */
    full_scan(request, stop_gap, parallel_requests) {
        _assertClass(request, FullScanRequest);
        var ptr0 = request.__destroy_into_raw();
        const ret = wasm.esploraclient_full_scan(this.__wbg_ptr, ptr0, stop_gap, parallel_requests);
        return takeObject(ret);
    }
    /**
     * @returns {Promise<FeeEstimates>}
     */
    get_fee_estimates() {
        const ret = wasm.esploraclient_get_fee_estimates(this.__wbg_ptr);
        return takeObject(ret);
    }
    /**
     * @param {Txid} txid
     * @returns {Promise<Transaction | undefined>}
     */
    get_tx(txid) {
        _assertClass(txid, Txid);
        var ptr0 = txid.__destroy_into_raw();
        const ret = wasm.esploraclient_get_tx(this.__wbg_ptr, ptr0);
        return takeObject(ret);
    }
    /**
     * @param {string} url
     * @param {number} max_retries
     */
    constructor(url, max_retries) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(url, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.esploraclient_new(retptr, ptr0, len0, max_retries);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            this.__wbg_ptr = r0;
            EsploraClientFinalization.register(this, this.__wbg_ptr, this);
            return this;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {SyncRequest} request
     * @param {number} parallel_requests
     * @returns {Promise<Update>}
     */
    sync(request, parallel_requests) {
        _assertClass(request, SyncRequest);
        var ptr0 = request.__destroy_into_raw();
        const ret = wasm.esploraclient_sync(this.__wbg_ptr, ptr0, parallel_requests);
        return takeObject(ret);
    }
}
if (Symbol.dispose) EsploraClient.prototype[Symbol.dispose] = EsploraClient.prototype.free;

/**
 * A transaction ID paired with an eviction timestamp.
 *
 * Used with `Wallet::apply_evicted_txs` to mark unconfirmed transactions
 * as evicted from the mempool.
 */
export class EvictedTx {
    static __unwrap(jsValue) {
        if (!(jsValue instanceof EvictedTx)) {
            return 0;
        }
        return jsValue.__destroy_into_raw();
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        EvictedTxFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_evictedtx_free(ptr, 0);
    }
    /**
     * Create a new `EvictedTx`.
     *
     * - `txid`: The transaction ID to evict
     * - `evicted_at`: Unix timestamp of when the transaction was evicted
     * @param {Txid} txid
     * @param {bigint} evicted_at
     */
    constructor(txid, evicted_at) {
        _assertClass(txid, Txid);
        var ptr0 = txid.__destroy_into_raw();
        const ret = wasm.evictedtx_new(ptr0, evicted_at);
        this.__wbg_ptr = ret;
        EvictedTxFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
}
if (Symbol.dispose) EvictedTx.prototype[Symbol.dispose] = EvictedTx.prototype.free;

/**
 * Map where the key is the confirmation target (in number of blocks) and the value is the estimated feerate (in sat/vB).
 */
export class FeeEstimates {
    static __wrap(ptr) {
        const obj = Object.create(FeeEstimates.prototype);
        obj.__wbg_ptr = ptr;
        FeeEstimatesFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        FeeEstimatesFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_feeestimates_free(ptr, 0);
    }
    /**
     * Returns the feerate (in sat/vB) or undefined.
     * Available confirmation targets are 1-25, 144, 504 and 1008 blocks.
     * @param {number} k
     * @returns {number | undefined}
     */
    get(k) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.feeestimates_get(retptr, this.__wbg_ptr, k);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r2 = getDataViewMemory0().getFloat64(retptr + 8 * 1, true);
            return r0 === 0 ? undefined : r2;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
}
if (Symbol.dispose) FeeEstimates.prototype[Symbol.dispose] = FeeEstimates.prototype.free;

/**
 * Represents fee rate.
 *
 * This is an integer newtype representing fee rate in `sat/kwu`. It provides protection against mixing
 * up the types as well as basic formatting features.
 */
export class FeeRate {
    static __wrap(ptr) {
        const obj = Object.create(FeeRate.prototype);
        obj.__wbg_ptr = ptr;
        FeeRateFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        FeeRateFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_feerate_free(ptr, 0);
    }
    /**
     * Create a fee rate in sat/vB, rejecting values that overflow sat/kwu.
     * @param {bigint} sat_vb
     */
    constructor(sat_vb) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.feerate_new(retptr, sat_vb);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            this.__wbg_ptr = r0;
            FeeRateFinalization.register(this, this.__wbg_ptr, this);
            return this;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns raw fee rate.
     * @returns {bigint}
     */
    to_sat_per_kwu() {
        const ret = wasm.feerate_to_sat_per_kwu(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
    /**
     * Converts to sat/vB rounding up.
     * @returns {bigint}
     */
    to_sat_per_vb_ceil() {
        const ret = wasm.feerate_to_sat_per_vb_ceil(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
    /**
     * Converts to sat/vB rounding down.
     * @returns {bigint}
     */
    to_sat_per_vb_floor() {
        const ret = wasm.feerate_to_sat_per_vb_floor(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
}
if (Symbol.dispose) FeeRate.prototype[Symbol.dispose] = FeeRate.prototype.free;

/**
 * Data required to perform a spk-based blockchain client full scan.
 *
 * A client full scan iterates through all the scripts for the given keychains, fetching relevant
 * data until some stop gap number of scripts is found that have no data. This operation is
 * generally only used when importing or restoring previously used keychains in which the list of
 * used scripts is not known.
 */
export class FullScanRequest {
    static __wrap(ptr) {
        const obj = Object.create(FullScanRequest.prototype);
        obj.__wbg_ptr = ptr;
        FullScanRequestFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        FullScanRequestFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_fullscanrequest_free(ptr, 0);
    }
}
if (Symbol.dispose) FullScanRequest.prototype[Symbol.dispose] = FullScanRequest.prototype.free;

/**
 * Wallet's UTXO set is not enough to cover recipient's requested plus fee.
 */
export class InsufficientFunds {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        InsufficientFundsFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_insufficientfunds_free(ptr, 0);
    }
    /**
     * Amount available for spending
     * @returns {Amount}
     */
    get available() {
        const ret = wasm.__wbg_get_insufficientfunds_available(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Amount needed for the transaction
     * @returns {Amount}
     */
    get needed() {
        const ret = wasm.__wbg_get_insufficientfunds_needed(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Amount available for spending
     * @param {Amount} arg0
     */
    set available(arg0) {
        _assertClass(arg0, Amount);
        var ptr0 = arg0.__destroy_into_raw();
        wasm.__wbg_set_insufficientfunds_available(this.__wbg_ptr, ptr0);
    }
    /**
     * Amount needed for the transaction
     * @param {Amount} arg0
     */
    set needed(arg0) {
        _assertClass(arg0, Amount);
        var ptr0 = arg0.__destroy_into_raw();
        wasm.__wbg_set_insufficientfunds_needed(this.__wbg_ptr, ptr0);
    }
}
if (Symbol.dispose) InsufficientFunds.prototype[Symbol.dispose] = InsufficientFunds.prototype.free;

/**
 * A reference to a transaction output.
 */
export class LocalOutput {
    static __wrap(ptr) {
        const obj = Object.create(LocalOutput.prototype);
        obj.__wbg_ptr = ptr;
        LocalOutputFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        LocalOutputFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_localoutput_free(ptr, 0);
    }
    /**
     * The derivation index for the script pubkey in the wallet
     * @returns {number}
     */
    get derivation_index() {
        const ret = wasm.localoutput_derivation_index(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Type of keychain
     * @returns {KeychainKind}
     */
    get keychain() {
        const ret = wasm.localoutput_keychain(this.__wbg_ptr);
        return __wbindgen_enum_KeychainKind[ret];
    }
    /**
     * Reference to a transaction output
     * @returns {OutPoint}
     */
    get outpoint() {
        const ret = wasm.localoutput_outpoint(this.__wbg_ptr);
        return OutPoint.__wrap(ret);
    }
    /**
     * Transaction output
     * @returns {TxOut}
     */
    get txout() {
        const ret = wasm.localoutput_txout(this.__wbg_ptr);
        return TxOut.__wrap(ret);
    }
}
if (Symbol.dispose) LocalOutput.prototype[Symbol.dispose] = LocalOutput.prototype.free;

/**
 * A reference to a transaction output.
 */
export class OutPoint {
    static __wrap(ptr) {
        const obj = Object.create(OutPoint.prototype);
        obj.__wbg_ptr = ptr;
        OutPointFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    static __unwrap(jsValue) {
        if (!(jsValue instanceof OutPoint)) {
            return 0;
        }
        return jsValue.__destroy_into_raw();
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        OutPointFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_outpoint_free(ptr, 0);
    }
    /**
     * @param {string} outpoint_str
     * @returns {OutPoint}
     */
    static from_string(outpoint_str) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(outpoint_str, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.outpoint_from_string(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return OutPoint.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {Txid} txid
     * @param {number} vout
     */
    constructor(txid, vout) {
        _assertClass(txid, Txid);
        var ptr0 = txid.__destroy_into_raw();
        const ret = wasm.outpoint_new(ptr0, vout);
        this.__wbg_ptr = ret;
        OutPointFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
    /**
     * @returns {string}
     */
    toString() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.outpoint_toString(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * The referenced transaction's txid.
     * @returns {Txid}
     */
    get txid() {
        const ret = wasm.outpoint_txid(this.__wbg_ptr);
        return Txid.__wrap(ret);
    }
    /**
     * The index of the referenced output in its transaction's vout.
     * @returns {number}
     */
    get vout() {
        const ret = wasm.outpoint_vout(this.__wbg_ptr);
        return ret >>> 0;
    }
}
if (Symbol.dispose) OutPoint.prototype[Symbol.dispose] = OutPoint.prototype.free;

/**
 * Caller-owned spending policy extracted from a public descriptor.
 *
 * This describes spending requirements, not the caller's available signatures.
 */
export class Policy {
    static __wrap(ptr) {
        const obj = Object.create(Policy.prototype);
        obj.__wbg_ptr = ptr;
        PolicyFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        PolicyFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_policy_free(ptr, 0);
    }
    /**
     * Extract a policy without wallet-owned signers or PSBT satisfaction state.
     *
     * Pass `wallet.public_descriptor(keychain)` to inspect a resolved receive or
     * change descriptor. Private keys are not accepted. Returns undefined if the
     * descriptor has no spending policy.
     * @param {string} descriptor
     * @returns {Policy | undefined}
     */
    static from_descriptor(descriptor) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.policy_from_descriptor(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return r0 === 0 ? undefined : Policy.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Derive CSV / CLTV requirements using BDK's policy selection rules.
     *
     * `path` maps policy node IDs to selected child indexes. An empty object is
     * sufficient when `requires_path()` is false. Missing required selections,
     * out-of-range indexes and incompatible timelock units return an error.
     * This does not select signing keys or force a particular final witness.
     * @param {Record<string, number[]>} path
     * @returns {Condition}
     */
    get_condition(path) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.policy_get_condition(retptr, this.__wbg_ptr, addHeapObject(path));
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Condition.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * The root policy node ID. Obtain child IDs from `to_json()`.
     * @returns {string}
     */
    get id() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.policy_id(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Whether choosing a path is necessary to determine the timelock requirements.
     * @returns {boolean}
     */
    requires_path() {
        const ret = wasm.policy_requires_path(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * Serialize BDK's policy tree, including node IDs, types, items and thresholds.
     *
     * Inspect this tree to select child indexes; do not hardcode IDs from another
     * descriptor or a policy extracted with different signers. Contribution and
     * satisfaction fields do not indicate which keys the caller actually holds.
     * @returns {string}
     */
    to_json() {
        let deferred2_0;
        let deferred2_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.policy_to_json(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
            var ptr1 = r0;
            var len1 = r1;
            if (r3) {
                ptr1 = 0; len1 = 0;
                throw takeObject(r2);
            }
            deferred2_0 = ptr1;
            deferred2_1 = len1;
            return getStringFromWasm0(ptr1, len1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred2_0, deferred2_1, 1);
        }
    }
}
if (Symbol.dispose) Policy.prototype[Symbol.dispose] = Policy.prototype.free;

/**
 * A Partially Signed Transaction.
 */
export class Psbt {
    static __wrap(ptr) {
        const obj = Object.create(Psbt.prototype);
        obj.__wbg_ptr = ptr;
        PsbtFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        PsbtFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_psbt_free(ptr, 0);
    }
    /**
     * @returns {Psbt}
     */
    clone() {
        const ret = wasm.psbt_clone(this.__wbg_ptr);
        return Psbt.__wrap(ret);
    }
    /**
     * Combines this [`Psbt`] with `other` PSBT as described by BIP 174. In-place.
     *
     * In accordance with BIP 174 this function is commutative i.e., `A.combine(B) == B.combine(A)`
     * @param {Psbt} other
     */
    combine(other) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(other, Psbt);
            var ptr0 = other.__destroy_into_raw();
            wasm.psbt_combine(retptr, this.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            if (r1) {
                throw takeObject(r0);
            }
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * An alias for [`extract_tx_fee_rate_limit`].
     * @returns {Transaction}
     */
    extract_tx() {
        try {
            const ptr = this.__destroy_into_raw();
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.psbt_extract_tx(retptr, ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Transaction.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Extracts the [`Transaction`] from a [`Psbt`] by filling in the available signature information.
     *
     * ## Errors
     *
     * [`ExtractTxError`] variants will contain either the [`Psbt`] itself or the [`Transaction`]
     * that was extracted. These can be extracted from the Errors in order to recover.
     * See the error documentation for info on the variants. In general, it covers large fees.
     * @returns {Transaction}
     */
    extract_tx_fee_rate_limit() {
        try {
            const ptr = this.__destroy_into_raw();
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.psbt_extract_tx_fee_rate_limit(retptr, ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Transaction.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Extracts the [`Transaction`] from a [`Psbt`] by filling in the available signature information.
     * @param {FeeRate} max_fee_rate
     * @returns {Transaction}
     */
    extract_tx_with_fee_rate_limit(max_fee_rate) {
        try {
            const ptr = this.__destroy_into_raw();
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(max_fee_rate, FeeRate);
            var ptr0 = max_fee_rate.__destroy_into_raw();
            wasm.psbt_extract_tx_with_fee_rate_limit(retptr, ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Transaction.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {Amount}
     */
    fee() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.psbt_fee(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Amount.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * The total transaction fee amount, sum of input amounts minus sum of output amounts, in sats.
     * If the PSBT is missing a TxOut for an input returns None.
     * @returns {Amount | undefined}
     */
    fee_amount() {
        const ret = wasm.psbt_fee_amount(this.__wbg_ptr);
        return ret === 0 ? undefined : Amount.__wrap(ret);
    }
    /**
     * The transaction's fee rate. This value will only be accurate if calculated AFTER the
     * `Psbt` is finalized and all witness/signature data is added to the transaction.
     * If the PSBT is missing a TxOut for an input returns None.
     * @returns {FeeRate | undefined}
     */
    fee_rate() {
        const ret = wasm.psbt_fee_rate(this.__wbg_ptr);
        return ret === 0 ? undefined : FeeRate.__wrap(ret);
    }
    /**
     * Create a PSBT from a base64 string
     * @param {string} val
     * @returns {Psbt}
     */
    static from_string(val) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(val, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.psbt_from_string(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Psbt.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Serialize the PSBT to a string in base64 format
     * @returns {string}
     */
    toString() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.psbt_toString(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Serialize `Psbt` to JSON.
     * @returns {string}
     */
    to_json() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.psbt_to_json(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * The unsigned transaction, scriptSigs and witnesses for each input must be empty.
     * @returns {Transaction}
     */
    get unsigned_tx() {
        const ret = wasm.psbt_unsigned_tx(this.__wbg_ptr);
        return Transaction.__wrap(ret);
    }
    /**
     * The version number of this PSBT. If omitted, the version number is 0.
     * @returns {number}
     */
    get version() {
        const ret = wasm.psbt_version(this.__wbg_ptr);
        return ret >>> 0;
    }
}
if (Symbol.dispose) Psbt.prototype[Symbol.dispose] = Psbt.prototype.free;

/**
 * A Transaction recipient
 */
export class Recipient {
    static __wrap(ptr) {
        const obj = Object.create(Recipient.prototype);
        obj.__wbg_ptr = ptr;
        RecipientFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    static __unwrap(jsValue) {
        if (!(jsValue instanceof Recipient)) {
            return 0;
        }
        return jsValue.__destroy_into_raw();
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        RecipientFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_recipient_free(ptr, 0);
    }
    /**
     * @returns {Amount}
     */
    get amount() {
        const ret = wasm.recipient_amount(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * @param {Address} address
     * @param {Amount} amount
     * @returns {Recipient}
     */
    static from_address(address, amount) {
        _assertClass(address, Address);
        var ptr0 = address.__destroy_into_raw();
        _assertClass(amount, Amount);
        var ptr1 = amount.__destroy_into_raw();
        const ret = wasm.recipient_from_address(ptr0, ptr1);
        return Recipient.__wrap(ret);
    }
    /**
     * @param {ScriptBuf} script_pubkey
     * @param {Amount} amount
     */
    constructor(script_pubkey, amount) {
        _assertClass(script_pubkey, ScriptBuf);
        var ptr0 = script_pubkey.__destroy_into_raw();
        _assertClass(amount, Amount);
        var ptr1 = amount.__destroy_into_raw();
        const ret = wasm.recipient_new(ptr0, ptr1);
        this.__wbg_ptr = ret;
        RecipientFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
    /**
     * @returns {ScriptBuf}
     */
    get script_pubkey() {
        const ret = wasm.recipient_script_pubkey(this.__wbg_ptr);
        return ScriptBuf.__wrap(ret);
    }
}
if (Symbol.dispose) Recipient.prototype[Symbol.dispose] = Recipient.prototype.free;

/**
 * An owned, growable script.
 *
 * `ScriptBuf` is the most common script type that has the ownership over the contents of the
 * script. It has a close relationship with its borrowed counterpart, [`Script`].
 */
export class ScriptBuf {
    static __wrap(ptr) {
        const obj = Object.create(ScriptBuf.prototype);
        obj.__wbg_ptr = ptr;
        ScriptBufFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        ScriptBufFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_scriptbuf_free(ptr, 0);
    }
    /**
     * @returns {Uint8Array}
     */
    as_bytes() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.scriptbuf_as_bytes(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU8FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export5(r0, r1 * 1, 1);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {ScriptBuf}
     */
    clone() {
        const ret = wasm.scriptbuf_clone(this.__wbg_ptr);
        return ScriptBuf.__wrap(ret);
    }
    /**
     * @param {Uint8Array} bytes
     * @returns {ScriptBuf}
     */
    static from_bytes(bytes) {
        const ptr0 = passArray8ToWasm0(bytes, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.scriptbuf_from_bytes(ptr0, len0);
        return ScriptBuf.__wrap(ret);
    }
    /**
     * @param {string} s
     * @returns {ScriptBuf}
     */
    static from_hex(s) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(s, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.scriptbuf_from_hex(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return ScriptBuf.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {boolean}
     */
    is_op_return() {
        const ret = wasm.scriptbuf_is_op_return(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * Returns the minimum value an output with this script should have in order to be
     * broadcastable on today's Bitcoin network.
     * @returns {Amount}
     */
    minimal_non_dust() {
        const ret = wasm.scriptbuf_minimal_non_dust(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * Returns the minimum value an output with this script should have in order to be
     * broadcastable on today's Bitcoin network.
     * @param {FeeRate} dust_relay_fee
     * @returns {Amount}
     */
    minimal_non_dust_custom(dust_relay_fee) {
        _assertClass(dust_relay_fee, FeeRate);
        var ptr0 = dust_relay_fee.__destroy_into_raw();
        const ret = wasm.scriptbuf_minimal_non_dust_custom(this.__wbg_ptr, ptr0);
        return Amount.__wrap(ret);
    }
    /**
     * @returns {string}
     */
    toString() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.scriptbuf_toString(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    to_asm_string() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.scriptbuf_to_asm_string(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @returns {string}
     */
    to_hex_string() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.scriptbuf_to_hex_string(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) ScriptBuf.prototype[Symbol.dispose] = ScriptBuf.prototype.free;

export class SentAndReceived {
    static __wrap(ptr) {
        const obj = Object.create(SentAndReceived.prototype);
        obj.__wbg_ptr = ptr;
        SentAndReceivedFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SentAndReceivedFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_sentandreceived_free(ptr, 0);
    }
    /**
     * @returns {Amount}
     */
    get 0() {
        const ret = wasm.__wbg_get_sentandreceived_0(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * @returns {Amount}
     */
    get 1() {
        const ret = wasm.__wbg_get_sentandreceived_1(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * @param {Amount} arg0
     */
    set 0(arg0) {
        _assertClass(arg0, Amount);
        var ptr0 = arg0.__destroy_into_raw();
        wasm.__wbg_set_sentandreceived_0(this.__wbg_ptr, ptr0);
    }
    /**
     * @param {Amount} arg0
     */
    set 1(arg0) {
        _assertClass(arg0, Amount);
        var ptr0 = arg0.__destroy_into_raw();
        wasm.__wbg_set_sentandreceived_1(this.__wbg_ptr, ptr0);
    }
}
if (Symbol.dispose) SentAndReceived.prototype[Symbol.dispose] = SentAndReceived.prototype.free;

/**
 * Options for signing a PSBT.
 *
 * BDK 3.2 retains `SignOptions` for `Wallet::sign_with_signers`. This wrapper
 * preserves the descriptor-based JavaScript signing API while caller-owned
 * signer support is developed.
 */
export class SignOptions {
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SignOptionsFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_signoptions_free(ptr, 0);
    }
    /**
     * @returns {boolean}
     */
    get allow_all_sighashes() {
        const ret = wasm.signoptions_allow_all_sighashes(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * @returns {boolean}
     */
    get allow_grinding() {
        const ret = wasm.signoptions_allow_grinding(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * @returns {number | undefined}
     */
    get assume_height() {
        const ret = wasm.signoptions_assume_height(this.__wbg_ptr);
        return ret === Number.MAX_SAFE_INTEGER ? undefined : ret;
    }
    constructor() {
        const ret = wasm.signoptions_new();
        this.__wbg_ptr = ret;
        SignOptionsFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
    /**
     * @param {boolean} value
     */
    set allow_all_sighashes(value) {
        wasm.signoptions_set_allow_all_sighashes(this.__wbg_ptr, value);
    }
    /**
     * @param {boolean} value
     */
    set allow_grinding(value) {
        wasm.signoptions_set_allow_grinding(this.__wbg_ptr, value);
    }
    /**
     * @param {number | null} [value]
     */
    set assume_height(value) {
        wasm.signoptions_set_assume_height(this.__wbg_ptr, isLikeNone(value) ? Number.MAX_SAFE_INTEGER : (value) >>> 0);
    }
    /**
     * @param {boolean} value
     */
    set sign_with_tap_internal_key(value) {
        wasm.signoptions_set_sign_with_tap_internal_key(this.__wbg_ptr, value);
    }
    /**
     * @param {boolean} value
     */
    set trust_witness_utxo(value) {
        wasm.signoptions_set_trust_witness_utxo(this.__wbg_ptr, value);
    }
    /**
     * @param {boolean} value
     */
    set try_finalize(value) {
        wasm.signoptions_set_try_finalize(this.__wbg_ptr, value);
    }
    /**
     * @returns {boolean}
     */
    get sign_with_tap_internal_key() {
        const ret = wasm.signoptions_sign_with_tap_internal_key(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * @returns {boolean}
     */
    get trust_witness_utxo() {
        const ret = wasm.signoptions_trust_witness_utxo(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * @returns {boolean}
     */
    get try_finalize() {
        const ret = wasm.signoptions_try_finalize(this.__wbg_ptr);
        return ret !== 0;
    }
}
if (Symbol.dispose) SignOptions.prototype[Symbol.dispose] = SignOptions.prototype.free;

export class SpkIndexed {
    static __wrap(ptr) {
        const obj = Object.create(SpkIndexed.prototype);
        obj.__wbg_ptr = ptr;
        SpkIndexedFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SpkIndexedFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_spkindexed_free(ptr, 0);
    }
    /**
     * @returns {KeychainKind}
     */
    get 0() {
        const ret = wasm.__wbg_get_spkindexed_0(this.__wbg_ptr);
        return __wbindgen_enum_KeychainKind[ret];
    }
    /**
     * @returns {number}
     */
    get 1() {
        const ret = wasm.__wbg_get_spkindexed_1(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * @param {KeychainKind} arg0
     */
    set 0(arg0) {
        wasm.__wbg_set_spkindexed_0(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(arg0) + 1 || 3) - 1);
    }
    /**
     * @param {number} arg0
     */
    set 1(arg0) {
        wasm.__wbg_set_spkindexed_1(this.__wbg_ptr, arg0);
    }
}
if (Symbol.dispose) SpkIndexed.prototype[Symbol.dispose] = SpkIndexed.prototype.free;

/**
 * Data required to perform a spk-based blockchain client sync.
 *
 * A client sync fetches relevant chain data for a known list of scripts, transaction ids and
 * outpoints.
 */
export class SyncRequest {
    static __wrap(ptr) {
        const obj = Object.create(SyncRequest.prototype);
        obj.__wbg_ptr = ptr;
        SyncRequestFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        SyncRequestFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_syncrequest_free(ptr, 0);
    }
}
if (Symbol.dispose) SyncRequest.prototype[Symbol.dispose] = SyncRequest.prototype.free;

/**
 * Bitcoin transaction.
 *
 * An authenticated movement of coins.
 */
export class Transaction {
    static __wrap(ptr) {
        const obj = Object.create(Transaction.prototype);
        obj.__wbg_ptr = ptr;
        TransactionFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TransactionFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_transaction_free(ptr, 0);
    }
    /**
     * Returns the base transaction size.
     *
     * > Base transaction size is the size of the transaction serialised with the witness data stripped.
     * @returns {number}
     */
    get base_size() {
        const ret = wasm.transaction_base_size(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * @returns {Transaction}
     */
    clone() {
        const ret = wasm.transaction_clone(this.__wbg_ptr);
        return Transaction.__wrap(ret);
    }
    /**
     * Computes the [`Txid`].
     *
     * Hashes the transaction **excluding** the segwit data (i.e. the marker, flag bytes, and the
     * witness fields themselves). For non-segwit transactions which do not have any segwit data,
     * this will be equal to [`Transaction::compute_wtxid()`].
     * @returns {Txid}
     */
    compute_txid() {
        const ret = wasm.transaction_compute_txid(this.__wbg_ptr);
        return Txid.__wrap(ret);
    }
    /**
     * Deserialize a transaction from consensus-encoded bytes.
     *
     * Accepts a `Uint8Array` of raw transaction bytes (as produced by `to_bytes()`
     * or any standard Bitcoin serializer).
     * @param {Uint8Array} bytes
     * @returns {Transaction}
     */
    static from_bytes(bytes) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passArray8ToWasm0(bytes, wasm.__wbindgen_export);
            const len0 = WASM_VECTOR_LEN;
            wasm.transaction_from_bytes(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Transaction.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * List of transaction inputs.
     * @returns {TxIn[]}
     */
    get input() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.transaction_input(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Checks if this is a coinbase transaction.
     *
     * The first transaction in the block distributes the mining reward and is called the coinbase
     * transaction. It is impossible to check if the transaction is first in the block, so this
     * function checks the structure of the transaction instead - the previous output must be
     * all-zeros (creates satoshis "out of thin air").
     * @returns {boolean}
     */
    get is_coinbase() {
        const ret = wasm.transaction_is_coinbase(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * Returns `true` if the transaction itself opted in to be BIP-125-replaceable (RBF).
     *
     * # Warning
     *
     * **Incorrectly relying on RBF may lead to monetary loss!**
     *
     * This **does not** cover the case where a transaction becomes replaceable due to ancestors
     * being RBF. Please note that transactions **may be replaced** even if they **do not** include
     * the RBF signal: <https://bitcoinops.org/en/newsletters/2022/10/19/#transaction-replacement-option>.
     * @returns {boolean}
     */
    get is_explicitly_rbf() {
        const ret = wasm.transaction_is_explicitly_rbf(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * Returns `true` if this transactions nLockTime is enabled ([BIP-65]).
     * @returns {boolean}
     */
    get is_lock_time_enabled() {
        const ret = wasm.transaction_is_lock_time_enabled(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * List of transaction outputs.
     * @returns {TxOut[]}
     */
    get output() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.transaction_output(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Serialize the transaction to consensus-encoded bytes (BIP144 format).
     *
     * Returns the raw transaction as a `Uint8Array` suitable for broadcasting,
     * passing to other WASM modules (e.g. LDK), or storing in IndexedDB.
     * @returns {Uint8Array}
     */
    to_bytes() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.transaction_to_bytes(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayU8FromWasm0(r0, r1).slice();
            wasm.__wbindgen_export5(r0, r1 * 1, 1);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns the total transaction size.
     *
     * > Total transaction size is the transaction size in bytes serialized as described in BIP144,
     * > including base data and witness data.
     * @returns {number}
     */
    get total_size() {
        const ret = wasm.transaction_total_size(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Returns the input at `input_index` if it exists.
     * @param {number} input_index
     * @returns {TxIn}
     */
    tx_in(input_index) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.transaction_tx_in(retptr, this.__wbg_ptr, input_index);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return TxIn.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns the output at `output_index` if it exists.
     * @param {number} output_index
     * @returns {TxOut}
     */
    tx_out(output_index) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.transaction_tx_out(retptr, this.__wbg_ptr, output_index);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return TxOut.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Returns the "virtual size" (vsize) of this transaction.
     *
     * Will be `ceil(weight / 4.0)`. Note this implements the virtual size as per [`BIP141`], which
     * is different to what is implemented in Bitcoin Core. The computation should be the same for
     * any remotely sane transaction, and a standardness-rule-correct version is available in the
     * [`policy`] module.
     *
     * > Virtual transaction size is defined as Transaction weight / 4 (rounded up to the next integer).
     * @returns {number}
     */
    get vsize() {
        const ret = wasm.transaction_vsize(this.__wbg_ptr);
        return ret >>> 0;
    }
}
if (Symbol.dispose) Transaction.prototype[Symbol.dispose] = Transaction.prototype.free;

/**
 * A transaction builder.
 *
 * A `TxBuilder` is created by calling [`build_tx`] or [`build_fee_bump`] on a wallet. After
 * assigning it, you set options on it until finally calling [`finish`] to consume the builder and
 * generate the transaction.
 *
 * Each option setting method on `TxBuilder` takes and returns a new builder so you can chain calls
 *
 * Fee-bump builders support fee policy, ordering, dust allowance, witness-only UTXOs,
 * global xpub metadata, and spending conditions. Other settings are rejected by `finish()`.
 */
export class TxBuilder {
    static __wrap(ptr) {
        const obj = Object.create(TxBuilder.prototype);
        obj.__wbg_ptr = ptr;
        TxBuilderFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TxBuilderFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_txbuilder_free(ptr, 0);
    }
    /**
     * Add an OP_RETURN output with arbitrary data to the transaction.
     *
     * The data is embedded in an `OP_RETURN` output with a zero-value amount.
     * This is commonly used for timestamping, anchoring data on-chain, or
     * protocol-specific metadata (e.g. Omni, OpenTimestamps).
     *
     * The data must be at most 80 bytes (the standard OP_RETURN limit).
     * If the data exceeds 80 bytes, the error will occur when calling `finish()`.
     * @param {Uint8Array} data
     * @returns {TxBuilder}
     */
    add_data(data) {
        const ptr = this.__destroy_into_raw();
        const ptr0 = passArray8ToWasm0(data, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.txbuilder_add_data(ptr, ptr0, len0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Fill in the `PSBT_GLOBAL_XPUB` field with extended keys from both the external
     * and internal descriptors.
     *
     * This is useful for offline signers that participate in multisig. Some hardware
     * wallets like BitBox and ColdCard require this.
     * @returns {TxBuilder}
     */
    add_global_xpubs() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_add_global_xpubs(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Add a recipient to the internal list
     * @param {Recipient} recipient
     * @returns {TxBuilder}
     */
    add_recipient(recipient) {
        const ptr = this.__destroy_into_raw();
        _assertClass(recipient, Recipient);
        var ptr0 = recipient.__destroy_into_raw();
        const ret = wasm.txbuilder_add_recipient(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Add a utxo to the internal list of unspendable utxos
     * @param {OutPoint} outpoint
     * @returns {TxBuilder}
     */
    add_unspendable(outpoint) {
        const ptr = this.__destroy_into_raw();
        _assertClass(outpoint, OutPoint);
        var ptr0 = outpoint.__destroy_into_raw();
        const ret = wasm.txbuilder_add_unspendable(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Add a UTXO to the internal list of UTXOs that **must** be spent.
     *
     * These have priority over the "unspendable" UTXOs, meaning that if a UTXO is present both
     * in the "UTXOs" and the "unspendable" list, it will be spent.
     * @param {OutPoint} outpoint
     * @returns {TxBuilder}
     */
    add_utxo(outpoint) {
        const ptr = this.__destroy_into_raw();
        _assertClass(outpoint, OutPoint);
        var ptr0 = outpoint.__destroy_into_raw();
        const ret = wasm.txbuilder_add_utxo(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Add a list of UTXOs to the internal list of UTXOs that **must** be spent.
     * @param {OutPoint[]} outpoints
     * @returns {TxBuilder}
     */
    add_utxos(outpoints) {
        const ptr = this.__destroy_into_raw();
        const ptr0 = passArrayJsValueToWasm0(outpoints, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.txbuilder_add_utxos(ptr, ptr0, len0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set whether or not the dust limit is checked.
     *
     * **Note**: by avoiding a dust limit check you may end up with a transaction that is non-standard.
     * @param {boolean} allow_dust
     * @returns {TxBuilder}
     */
    allow_dust(allow_dust) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_allow_dust(ptr, allow_dust);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set the change spending policy.
     *
     * Controls whether change outputs from previous transactions can be spent.
     * @param {ChangeSpendPolicy} change_policy
     * @returns {TxBuilder}
     */
    change_policy(change_policy) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_change_policy(ptr, change_policy);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set the current blockchain height.
     *
     * This will be used to:
     * 1. Set the nLockTime for preventing fee sniping.
     *    **Note**: This will be ignored if you manually specify a locktime using [`nlocktime`](Self::nlocktime).
     * 2. Decide whether coinbase outputs are mature or not. If the coinbase outputs are not
     *    mature at spending height (`current_height + 1`), they are ignored in coin selection.
     *    To spend immature coinbase inputs, manually add them using [`add_utxo`](Self::add_utxo).
     *
     * If not provided, the last sync height is used.
     * @param {number} height
     * @returns {TxBuilder}
     */
    current_height(height) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_current_height(ptr, height);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Shorthand to set the change policy to [`ChangeSpendPolicy::ChangeForbidden`].
     *
     * This effectively forbids the wallet from spending change outputs.
     * @returns {TxBuilder}
     */
    do_not_spend_change() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_do_not_spend_change(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Sets the address to *drain* excess coins to.
     *
     * Usually, when there are excess coins they are sent to a change address generated by the
     * wallet. This option replaces the usual change address with an arbitrary `script_pubkey` of
     * your choosing. Just as with a change output, if the drain output is not needed (the excess
     * coins are too small) it will not be included in the resulting transaction. The only
     * difference is that it is valid to use `drain_to` without setting any ordinary recipients
     * with [`add_recipient`] (but it is perfectly fine to add recipients as well).
     *
     * If you choose not to set any recipients, you should provide the utxos that the
     * transaction should spend via [`add_utxos`].
     * @param {ScriptBuf} script_pubkey
     * @returns {TxBuilder}
     */
    drain_to(script_pubkey) {
        const ptr = this.__destroy_into_raw();
        _assertClass(script_pubkey, ScriptBuf);
        var ptr0 = script_pubkey.__destroy_into_raw();
        const ret = wasm.txbuilder_drain_to(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Spend all the available inputs. This respects filters like [`TxBuilder::unspendable`] and the change policy.
     * @returns {TxBuilder}
     */
    drain_wallet() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_drain_wallet(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Enable Replace-By-Fee (BIP 125) signaling.
     *
     * **Note:** RBF is enabled by default in BDK (nSequence = `0xFFFFFFFD`).
     * This method is kept for API compatibility but is effectively a no-op.
     * @returns {TxBuilder}
     */
    enable_rbf() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_enable_rbf(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Enable Replace-By-Fee (BIP 125) with a specific nSequence value.
     *
     * **Note:** RBF is enabled by default in BDK. Custom nSequence values
     * are not currently supported through this builder. This method is kept for
     * API compatibility but is effectively a no-op.
     * @param {number} _nsequence
     * @returns {TxBuilder}
     */
    enable_rbf_with_sequence(_nsequence) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_enable_rbf_with_sequence(ptr, _nsequence);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Exclude outpoints whose enclosing transaction has fewer than `min_confirms`
     * confirmations.
     *
     * - Passing `0` will include all transactions (no filtering).
     * - Passing `1` will exclude all unconfirmed transactions (equivalent to
     *   [`exclude_unconfirmed`]).
     * - Passing `6` will only allow outpoints from transactions with at least 6 confirmations.
     * @param {number} min_confirms
     * @returns {TxBuilder}
     */
    exclude_below_confirmations(min_confirms) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_exclude_below_confirmations(ptr, min_confirms);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Exclude outpoints whose enclosing transaction is unconfirmed.
     *
     * This is a shorthand for [`exclude_below_confirmations(1)`](Self::exclude_below_confirmations).
     * @returns {TxBuilder}
     */
    exclude_unconfirmed() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_exclude_unconfirmed(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set an absolute fee.
     *
     * The `fee_absolute` method refers to the absolute transaction fee in satoshis.
     * If both `fee_absolute` and `fee_rate` are set, whichever is called last takes precedence.
     *
     * Note that this is really a minimum absolute fee -- it's possible to
     * overshoot it slightly since adding a change output to drain the remaining
     * excess might not be viable.
     * @param {Amount} fee
     * @returns {TxBuilder}
     */
    fee_absolute(fee) {
        const ptr = this.__destroy_into_raw();
        _assertClass(fee, Amount);
        var ptr0 = fee.__destroy_into_raw();
        const ret = wasm.txbuilder_fee_absolute(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set a custom fee rate.
     *
     * This method sets the mining fee paid by the transaction as a rate on its size.
     * This means that the total fee paid is equal to `fee_rate` times the size
     * of the transaction. Default is 1 sat/vB in accordance with Bitcoin Core's default
     * relay policy.
     *
     * Note that this is really a minimum feerate -- it's possible to
     * overshoot it slightly since adding a change output to drain the remaining
     * excess might not be viable.
     * @param {FeeRate} fee_rate
     * @returns {TxBuilder}
     */
    fee_rate(fee_rate) {
        const ptr = this.__destroy_into_raw();
        _assertClass(fee_rate, FeeRate);
        var ptr0 = fee_rate.__destroy_into_raw();
        const ret = wasm.txbuilder_fee_rate(ptr, ptr0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Finish building the transaction.
     *
     * Returns a new [`Psbt`] per [`BIP174`].
     * @returns {Psbt}
     */
    finish() {
        try {
            const ptr = this.__destroy_into_raw();
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.txbuilder_finish(retptr, ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Psbt.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Fill in the `redeem_script` and `witness_script` fields of PSBT outputs.
     *
     * This is useful for signers that always require these fields, such as ColdCard
     * and BitBox hardware wallets.
     * BDK 3 always includes these fields; retained for JavaScript compatibility.
     * @returns {TxBuilder}
     */
    include_output_redeem_witness_script() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_include_output_redeem_witness_script(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set an absolute locktime for the transaction.
     *
     * This is used to set a specific block height or timestamp before which
     * the transaction cannot be mined.
     * @param {number} locktime
     * @returns {TxBuilder}
     */
    nlocktime(locktime) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_nlocktime(ptr, locktime);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Shorthand to set the change policy to [`ChangeSpendPolicy::OnlyChange`].
     *
     * This effectively only allows the wallet to spend change outputs.
     * @returns {TxBuilder}
     */
    only_spend_change() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_only_spend_change(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Only spend UTXOs added by [`add_utxo`](Self::add_utxo).
     *
     * The wallet will **not** add additional UTXOs to the transaction even if they are needed
     * to make the transaction valid.
     * @returns {TxBuilder}
     */
    only_spend_from() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_only_spend_from(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Only fill in the `witness_utxo` field in PSBT inputs, and remove the `non_witness_utxo`.
     *
     * This reduces the PSBT size and is acceptable for segwit-only wallets. Some hardware
     * wallets may prefer or require this.
     * @returns {TxBuilder}
     */
    only_witness_utxo() {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_only_witness_utxo(ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Choose the ordering for inputs and outputs of the transaction
     * @param {TxOrdering} ordering
     * @returns {TxBuilder}
     */
    ordering(ordering) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_ordering(ptr, ordering);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set the CSV / CLTV requirements for the intended spending path.
     *
     * Obtain this from `Policy.get_condition()`, or construct a `Condition` when
     * the requirements are known. Merge the conditions of all keychains whose
     * inputs may be selected. Repeated calls replace the previous condition.
     *
     * This overrides BDK's automatic policy inference for the entire transaction,
     * including fee bumps. It sets timelocks, not signing keys or a final witness,
     * and does not verify that the condition matches the descriptor or has matured.
     * Incompatible explicit version, sequence or locktime options fail in `finish()`.
     *
     * # JavaScript example
     *
     * For the three-branch vault in [#54](https://github.com/bitcoindevkit/bdk-wasm/issues/54),
     * select the owner + inheritance recovery path as follows. These child indexes
     * are specific to that policy; inspect your own tree and use its node IDs.
     *
     * ```typescript
     * const policy = Policy.from_descriptor(wallet.public_descriptor("external"));
     * if (!policy) throw new Error("Descriptor has no spending policy");
     * const tree = JSON.parse(policy.to_json());
     * const condition = policy.get_condition({
     *   [tree.id]: [1],          // choose the recovery subtree
     *   [tree.items[1].id]: [0], // owner + inheritance, with older(1008)
     * });
     * const psbt = wallet.build_tx()
     *   .do_not_spend_change()
     *   .set_condition(condition)
     *   .add_recipient(recipient)
     *   .finish();
     * ```
     *
     * If inputs from both keychains may be selected, derive both conditions and
     * pass `externalCondition.merge(internalCondition)` instead.
     * @param {Condition} condition
     * @returns {TxBuilder}
     */
    set_condition(condition) {
        const ptr = this.__destroy_into_raw();
        _assertClass(condition, Condition);
        const ret = wasm.txbuilder_set_condition(ptr, condition.__wbg_ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set the exact nSequence value for all transaction inputs.
     *
     * This can be used for fine-grained control over time-lock behavior (BIP 68),
     * Replace-By-Fee signaling, and other sequence-dependent features.
     * @param {number} n_sequence
     * @returns {TxBuilder}
     */
    set_exact_sequence(n_sequence) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_set_exact_sequence(ptr, n_sequence);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Replace the recipients already added with a new list
     * @param {Recipient[]} recipients
     * @returns {TxBuilder}
     */
    set_recipients(recipients) {
        const ptr = this.__destroy_into_raw();
        const ptr0 = passArrayJsValueToWasm0(recipients, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.txbuilder_set_recipients(ptr, ptr0, len0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Replace the internal list of unspendable utxos with a new list
     * @param {OutPoint[]} unspendable
     * @returns {TxBuilder}
     */
    unspendable(unspendable) {
        const ptr = this.__destroy_into_raw();
        const ptr0 = passArrayJsValueToWasm0(unspendable, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.txbuilder_unspendable(ptr, ptr0, len0);
        return TxBuilder.__wrap(ret);
    }
    /**
     * Set the transaction version.
     *
     * By default, transactions are created with version 1. Set to 2 if you need
     * features like OP_CSV (BIP 68/112/113).
     * @param {number} version
     * @returns {TxBuilder}
     */
    version(version) {
        const ptr = this.__destroy_into_raw();
        const ret = wasm.txbuilder_version(ptr, version);
        return TxBuilder.__wrap(ret);
    }
}
if (Symbol.dispose) TxBuilder.prototype[Symbol.dispose] = TxBuilder.prototype.free;

/**
 * Detailed information about a wallet transaction.
 *
 * This type provides a comprehensive view of a transaction from the wallet's perspective,
 * including sent/received amounts, fees, fee rate, balance delta, and chain position.
 *
 * Obtain a `TxDetails` by calling `Wallet::tx_details(txid)`.
 */
export class TxDetails {
    static __wrap(ptr) {
        const obj = Object.create(TxDetails.prototype);
        obj.__wbg_ptr = ptr;
        TxDetailsFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TxDetailsFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_txdetails_free(ptr, 0);
    }
    /**
     * The net effect of the transaction on the wallet balance, in satoshis.
     *
     * Positive values mean the wallet received more than it spent (net inflow).
     * Negative values mean the wallet spent more than it received (net outflow).
     * @returns {bigint}
     */
    get balance_delta_sat() {
        const ret = wasm.txdetails_balance_delta_sat(this.__wbg_ptr);
        return ret;
    }
    /**
     * The position of the transaction in the chain (confirmed or unconfirmed).
     * @returns {ChainPosition}
     */
    get chain_position() {
        const ret = wasm.txdetails_chain_position(this.__wbg_ptr);
        return ChainPosition.__wrap(ret);
    }
    /**
     * The fee paid for the transaction, if known.
     *
     * This will be `None` if the transaction has inputs not owned by this wallet
     * and their `TxOut` values have not been inserted via `Wallet::insert_txout`.
     * @returns {Amount | undefined}
     */
    get fee() {
        const ret = wasm.txdetails_fee(this.__wbg_ptr);
        return ret === 0 ? undefined : Amount.__wrap(ret);
    }
    /**
     * The fee rate paid for the transaction, if known.
     *
     * Same conditions as `fee` for when this is `None`.
     * @returns {FeeRate | undefined}
     */
    get fee_rate() {
        const ret = wasm.txdetails_fee_rate(this.__wbg_ptr);
        return ret === 0 ? undefined : FeeRate.__wrap(ret);
    }
    /**
     * The sum of the transaction outputs that send to script pubkeys tracked by
     * this wallet.
     * @returns {Amount}
     */
    get received() {
        const ret = wasm.txdetails_received(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * The sum of the transaction input amounts that spend from previous outputs
     * tracked by this wallet.
     * @returns {Amount}
     */
    get sent() {
        const ret = wasm.txdetails_sent(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
    /**
     * The complete transaction.
     * @returns {Transaction}
     */
    get tx() {
        const ret = wasm.txdetails_tx(this.__wbg_ptr);
        return Transaction.__wrap(ret);
    }
    /**
     * The transaction id.
     * @returns {Txid}
     */
    get txid() {
        const ret = wasm.txdetails_txid(this.__wbg_ptr);
        return Txid.__wrap(ret);
    }
}
if (Symbol.dispose) TxDetails.prototype[Symbol.dispose] = TxDetails.prototype.free;

/**
 * Bitcoin transaction input.
 *
 * It contains the location of the previous transaction's output,
 * that it spends and set of scripts that satisfy its spending
 * conditions.
 */
export class TxIn {
    static __wrap(ptr) {
        const obj = Object.create(TxIn.prototype);
        obj.__wbg_ptr = ptr;
        TxInFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TxInFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_txin_free(ptr, 0);
    }
    /**
     * Returns the base size of this input.
     *
     * Base size excludes the witness data.
     * @returns {number}
     */
    get base_size() {
        const ret = wasm.txin_base_size(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Returns true if this input enables the [`absolute::LockTime`] (aka `nLockTime`) of its
     * [`Transaction`].
     *
     * `nLockTime` is enabled if *any* input enables it. See [`Transaction::is_lock_time_enabled`]
     *  to check the overall state. If none of the inputs enables it, the lock time value is simply
     *  ignored. If this returns false and OP_CHECKLOCKTIMEVERIFY is used in the redeem script with
     *  this input then the script execution will fail [BIP-0065].
     * @returns {boolean}
     */
    get enables_lock_time() {
        const ret = wasm.txin_enables_lock_time(this.__wbg_ptr);
        return ret !== 0;
    }
    /**
     * The reference to the previous output that is being used as an input.
     * @returns {OutPoint}
     */
    get previous_output() {
        const ret = wasm.txin_previous_output(this.__wbg_ptr);
        return OutPoint.__wrap(ret);
    }
    /**
     * The script which pushes values on the stack which will cause
     * the referenced output's script to be accepted.
     * @returns {ScriptBuf}
     */
    get script_sig() {
        const ret = wasm.txin_script_sig(this.__wbg_ptr);
        return ScriptBuf.__wrap(ret);
    }
    /**
     * The sequence number, which suggests to miners which of two
     * conflicting transactions should be preferred, or 0xFFFFFFFF
     * to ignore this feature. This is generally never used since
     * the miner behaviour cannot be enforced.
     * @returns {number}
     */
    get sequence() {
        const ret = wasm.txin_sequence(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * Returns the total number of bytes that this input contributes to a transaction.
     *
     * Total size includes the witness data.
     * @returns {number}
     */
    get total_size() {
        const ret = wasm.txin_total_size(this.__wbg_ptr);
        return ret >>> 0;
    }
}
if (Symbol.dispose) TxIn.prototype[Symbol.dispose] = TxIn.prototype.free;

/**
 * Ordering of the transaction's inputs and outputs
 * @enum {0 | 1}
 */
export const TxOrdering = Object.freeze({
    /**
     * Randomized (default)
     */
    Shuffle: 0, "0": "Shuffle",
    /**
     * Unchanged
     */
    Untouched: 1, "1": "Untouched",
});

/**
 * Bitcoin transaction output.
 *
 * Defines new coins to be created as a result of the transaction,
 * along with spending conditions ("script", aka "output script"),
 * which an input spending it must satisfy.
 *
 * An output that is not yet spent by an input is called Unspent Transaction Output ("UTXO").
 */
export class TxOut {
    static __wrap(ptr) {
        const obj = Object.create(TxOut.prototype);
        obj.__wbg_ptr = ptr;
        TxOutFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TxOutFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_txout_free(ptr, 0);
    }
    /**
     * The script which must be satisfied for the output to be spent.
     * @returns {ScriptBuf}
     */
    get script_pubkey() {
        const ret = wasm.txout_script_pubkey(this.__wbg_ptr);
        return ScriptBuf.__wrap(ret);
    }
    /**
     * Returns the total number of bytes that this output contributes to a transaction.
     *
     * There is no difference between base size vs total size for outputs.
     * @returns {number}
     */
    get size() {
        const ret = wasm.txout_size(this.__wbg_ptr);
        return ret >>> 0;
    }
    /**
     * The value of the output, in satoshis.
     * @returns {Amount}
     */
    get value() {
        const ret = wasm.txout_value(this.__wbg_ptr);
        return Amount.__wrap(ret);
    }
}
if (Symbol.dispose) TxOut.prototype[Symbol.dispose] = TxOut.prototype.free;

/**
 * A bitcoin transaction hash/transaction ID.
 */
export class Txid {
    static __wrap(ptr) {
        const obj = Object.create(Txid.prototype);
        obj.__wbg_ptr = ptr;
        TxidFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        TxidFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_txid_free(ptr, 0);
    }
    /**
     * @param {string} txid_str
     * @returns {Txid}
     */
    static from_string(txid_str) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(txid_str, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.txid_from_string(retptr, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Txid.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {string}
     */
    toString() {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.txid_toString(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
}
if (Symbol.dispose) Txid.prototype[Symbol.dispose] = Txid.prototype.free;

export class UnconfirmedTx {
    static __unwrap(jsValue) {
        if (!(jsValue instanceof UnconfirmedTx)) {
            return 0;
        }
        return jsValue.__destroy_into_raw();
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        UnconfirmedTxFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_unconfirmedtx_free(ptr, 0);
    }
    /**
     * @returns {bigint}
     */
    get 1() {
        const ret = wasm.__wbg_get_unconfirmedtx_1(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
    /**
     * @param {bigint} arg0
     */
    set 1(arg0) {
        wasm.__wbg_set_unconfirmedtx_1(this.__wbg_ptr, arg0);
    }
    /**
     * @returns {bigint}
     */
    get last_seen() {
        const ret = wasm.unconfirmedtx_last_seen(this.__wbg_ptr);
        return BigInt.asUintN(64, ret);
    }
    /**
     * `tx` – your wrapped `Transaction`
     * `last_seen` – unix epoch seconds (same convention as the rest of the API)
     * @param {Transaction} tx
     * @param {bigint} last_seen
     */
    constructor(tx, last_seen) {
        _assertClass(tx, Transaction);
        var ptr0 = tx.__destroy_into_raw();
        const ret = wasm.unconfirmedtx_new(ptr0, last_seen);
        this.__wbg_ptr = ret;
        UnconfirmedTxFinalization.register(this, this.__wbg_ptr, this);
        return this;
    }
    /**
     * @returns {Transaction}
     */
    get tx() {
        const ret = wasm.unconfirmedtx_tx(this.__wbg_ptr);
        return Transaction.__wrap(ret);
    }
}
if (Symbol.dispose) UnconfirmedTx.prototype[Symbol.dispose] = UnconfirmedTx.prototype.free;

/**
 * An update to [`Wallet`].
 */
export class Update {
    static __wrap(ptr) {
        const obj = Object.create(Update.prototype);
        obj.__wbg_ptr = ptr;
        UpdateFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        UpdateFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_update_free(ptr, 0);
    }
}
if (Symbol.dispose) Update.prototype[Symbol.dispose] = Update.prototype.free;

export class Wallet {
    static __wrap(ptr) {
        const obj = Object.create(Wallet.prototype);
        obj.__wbg_ptr = ptr;
        WalletFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        WalletFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_wallet_free(ptr, 0);
    }
    /**
     * Apply a block to the wallet, explicitly specifying the connection point.
     *
     * The `connected_to` parameter tells the wallet how this block connects to the
     * internal chain. Use this when you have explicit knowledge of the chain topology,
     * e.g. when processing blocks out of order or from a specific fork.
     *
     * Returns a list of `WalletEvent`s describing what changed.
     * @param {Block} block
     * @param {number} height
     * @param {BlockId} connected_to
     * @returns {WalletEvent[]}
     */
    apply_block_connected_to_events(block, height, connected_to) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(block, Block);
            _assertClass(connected_to, BlockId);
            var ptr0 = connected_to.__destroy_into_raw();
            wasm.wallet_apply_block_connected_to_events(retptr, this.__wbg_ptr, block.__wbg_ptr, height, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
            if (r3) {
                throw takeObject(r2);
            }
            var v2 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v2;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Apply a block to the wallet, connecting it via its `prev_blockhash`.
     *
     * This is a convenience method that introduces a `Block` at the given `height`
     * and connects it to the chain using the block's `prev_blockhash` header field.
     *
     * Returns a list of `WalletEvent`s describing what changed (new transactions,
     * confirmations, etc.).
     * @param {Block} block
     * @param {number} height
     * @returns {WalletEvent[]}
     */
    apply_block_events(block, height) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(block, Block);
            wasm.wallet_apply_block_events(retptr, this.__wbg_ptr, block.__wbg_ptr, height);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
            if (r3) {
                throw takeObject(r2);
            }
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Mark unconfirmed transactions as evicted from the mempool.
     *
     * Evicted transactions are no longer considered canonical and won't appear in
     * `transactions()`. This is useful when a blockchain backend reports that certain
     * transactions have been dropped (e.g. due to low fees or conflicts).
     *
     * Only unconfirmed, canonical transactions are affected. An evicted transaction
     * can become canonical again if it is later observed on-chain or in the mempool
     * with higher priority.
     * @param {EvictedTx[]} evicted_txs
     */
    apply_evicted_txs(evicted_txs) {
        const ptr0 = passArrayJsValueToWasm0(evicted_txs, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        wasm.wallet_apply_evicted_txs(this.__wbg_ptr, ptr0, len0);
    }
    /**
     * @param {UnconfirmedTx[]} unconfirmed_txs
     */
    apply_unconfirmed_txs(unconfirmed_txs) {
        const ptr0 = passArrayJsValueToWasm0(unconfirmed_txs, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        wasm.wallet_apply_unconfirmed_txs(this.__wbg_ptr, ptr0, len0);
    }
    /**
     * @param {Update} update
     */
    apply_update(update) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(update, Update);
            var ptr0 = update.__destroy_into_raw();
            wasm.wallet_apply_update(retptr, this.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            if (r1) {
                throw takeObject(r0);
            }
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Apply an update and return wallet events describing what changed.
     *
     * Returns a list of `WalletEvent`s such as new transactions, confirmations, replacements, etc.
     * @param {Update} update
     * @returns {WalletEvent[]}
     */
    apply_update_events(update) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(update, Update);
            var ptr0 = update.__destroy_into_raw();
            wasm.wallet_apply_update_events(retptr, this.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
            if (r3) {
                throw takeObject(r2);
            }
            var v2 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v2;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {Balance}
     */
    get balance() {
        const ret = wasm.wallet_balance(this.__wbg_ptr);
        return Balance.__wrap(ret);
    }
    /**
     * Create a new transaction builder for fee-bumping (RBF) an existing transaction.
     *
     * The `txid` must refer to a transaction that is already in the wallet and signals RBF.
     * Returns a `TxBuilder` pre-configured for fee bumping. You can then set the new fee rate
     * or absolute fee and call `finish()`.
     * Only fee policy, ordering, dust allowance, witness-only UTXOs, and global xpub metadata
     * are supported; other builder settings cause `finish()` to return an error.
     * @param {Txid} txid
     * @returns {TxBuilder}
     */
    build_fee_bump(txid) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(txid, Txid);
            var ptr0 = txid.__destroy_into_raw();
            wasm.wallet_build_fee_bump(retptr, this.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return TxBuilder.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {TxBuilder}
     */
    build_tx() {
        const ret = wasm.wallet_build_tx(this.__wbg_ptr);
        return TxBuilder.__wrap(ret);
    }
    /**
     * @param {Transaction} tx
     * @returns {Amount}
     */
    calculate_fee(tx) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(tx, Transaction);
            wasm.wallet_calculate_fee(retptr, this.__wbg_ptr, tx.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Amount.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {Transaction} tx
     * @returns {FeeRate}
     */
    calculate_fee_rate(tx) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(tx, Transaction);
            wasm.wallet_calculate_fee_rate(retptr, this.__wbg_ptr, tx.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return FeeRate.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Inform the wallet that a transaction built from it will not be broadcast.
     *
     * This frees up the change address that was reserved when creating the transaction,
     * making it available for future transactions.
     * @param {Transaction} tx
     */
    cancel_tx(tx) {
        _assertClass(tx, Transaction);
        wasm.wallet_cancel_tx(this.__wbg_ptr, tx.__wbg_ptr);
    }
    /**
     * List all checkpoints in the wallet's internal chain, ordered by height.
     *
     * Returns an array of `CheckPoint`s representing the wallet's view of the blockchain.
     * @returns {CheckPoint[]}
     */
    checkpoints() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_checkpoints(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {Network} network
     * @param {string} external_descriptor
     * @param {string} internal_descriptor
     * @returns {Wallet}
     */
    static create(network, external_descriptor, internal_descriptor) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(external_descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            const ptr1 = passStringToWasm0(internal_descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len1 = WASM_VECTOR_LEN;
            wasm.wallet_create(retptr, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, ptr0, len0, ptr1, len1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Wallet.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Create a new [`Wallet`] from a BIP-389 two-path multipath descriptor.
     *
     * The descriptor must contain exactly two derivation paths (receive and change),
     * separated by a semicolon in angle brackets, e.g.:
     * `wpkh([fingerprint/path]xpub.../<0;1>/*)`
     *
     * The first path is used for the external (receive) keychain and the second
     * for the internal (change) keychain.
     * @param {Network} network
     * @param {string} descriptor
     * @returns {Wallet}
     */
    static create_from_two_path_descriptor(network, descriptor) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.wallet_create_from_two_path_descriptor(retptr, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Wallet.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Create a new single-descriptor [`Wallet`].
     *
     * Use this when the wallet only needs one descriptor (no separate change keychain).
     * Note that `change_policy` and related methods won't be available on single-descriptor wallets.
     * @param {Network} network
     * @param {string} descriptor
     * @returns {Wallet}
     */
    static create_single(network, descriptor) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            const ptr0 = passStringToWasm0(descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            const len0 = WASM_VECTOR_LEN;
            wasm.wallet_create_single(retptr, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, ptr0, len0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Wallet.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {KeychainKind} keychain
     * @returns {number | undefined}
     */
    derivation_index(keychain) {
        const ret = wasm.wallet_derivation_index(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
        return ret === Number.MAX_SAFE_INTEGER ? undefined : ret;
    }
    /**
     * @param {ScriptBuf} spk
     * @returns {SpkIndexed | undefined}
     */
    derivation_of_spk(spk) {
        _assertClass(spk, ScriptBuf);
        var ptr0 = spk.__destroy_into_raw();
        const ret = wasm.wallet_derivation_of_spk(this.__wbg_ptr, ptr0);
        return ret === 0 ? undefined : SpkIndexed.__wrap(ret);
    }
    /**
     * Get the descriptor checksum for the given keychain.
     *
     * Returns the checksum portion of the descriptor string (the part after `#`).
     * @param {KeychainKind} keychain
     * @returns {string}
     */
    descriptor_checksum(keychain) {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_descriptor_checksum(retptr, this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * Finalize a PSBT, putting the finalized script and witness values into the inputs.
     *
     * Returns `true` if the PSBT was fully finalized, `false` if some inputs could not
     * be finalized. Use `SignOptions::try_finalize` to control whether finalization is
     * attempted.
     * @param {Psbt} psbt
     * @param {SignOptions} options
     * @returns {boolean}
     */
    finalize_psbt(psbt, options) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(psbt, Psbt);
            _assertClass(options, SignOptions);
            var ptr0 = options.__destroy_into_raw();
            wasm.wallet_finalize_psbt(retptr, this.__wbg_ptr, psbt.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return r0 !== 0;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {Txid} txid
     * @returns {WalletTx | undefined}
     */
    get_tx(txid) {
        _assertClass(txid, Txid);
        var ptr0 = txid.__destroy_into_raw();
        const ret = wasm.wallet_get_tx(this.__wbg_ptr, ptr0);
        return ret === 0 ? undefined : WalletTx.__wrap(ret);
    }
    /**
     * @param {OutPoint} op
     * @returns {LocalOutput | undefined}
     */
    get_utxo(op) {
        _assertClass(op, OutPoint);
        var ptr0 = op.__destroy_into_raw();
        const ret = wasm.wallet_get_utxo(this.__wbg_ptr, ptr0);
        return ret === 0 ? undefined : LocalOutput.__wrap(ret);
    }
    /**
     * Insert a `TxOut` at the given `OutPoint` into the wallet's transaction graph.
     *
     * This is useful for providing previous output values so that
     * `calculate_fee` and `calculate_fee_rate` work on transactions with
     * inputs not owned by this wallet.
     * @param {OutPoint} outpoint
     * @param {TxOut} txout
     */
    insert_txout(outpoint, txout) {
        _assertClass(outpoint, OutPoint);
        var ptr0 = outpoint.__destroy_into_raw();
        _assertClass(txout, TxOut);
        var ptr1 = txout.__destroy_into_raw();
        wasm.wallet_insert_txout(this.__wbg_ptr, ptr0, ptr1);
    }
    /**
     * @param {ScriptBuf} script
     * @returns {boolean}
     */
    is_mine(script) {
        _assertClass(script, ScriptBuf);
        var ptr0 = script.__destroy_into_raw();
        const ret = wasm.wallet_is_mine(this.__wbg_ptr, ptr0);
        return ret !== 0;
    }
    /**
     * @returns {CheckPoint}
     */
    get latest_checkpoint() {
        const ret = wasm.wallet_latest_checkpoint(this.__wbg_ptr);
        return CheckPoint.__wrap(ret);
    }
    /**
     * @returns {LocalOutput[]}
     */
    list_output() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_list_output(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {LocalOutput[]}
     */
    list_unspent() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_list_unspent(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {KeychainKind} keychain
     * @returns {AddressInfo[]}
     */
    list_unused_addresses(keychain) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_list_unused_addresses(retptr, this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {ChangeSet} changeset
     * @param {string | null} [external_descriptor]
     * @param {string | null} [internal_descriptor]
     * @returns {Wallet}
     */
    static load(changeset, external_descriptor, internal_descriptor) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(changeset, ChangeSet);
            var ptr0 = changeset.__destroy_into_raw();
            var ptr1 = isLikeNone(external_descriptor) ? 0 : passStringToWasm0(external_descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            var len1 = WASM_VECTOR_LEN;
            var ptr2 = isLikeNone(internal_descriptor) ? 0 : passStringToWasm0(internal_descriptor, wasm.__wbindgen_export, wasm.__wbindgen_export2);
            var len2 = WASM_VECTOR_LEN;
            wasm.wallet_load(retptr, ptr0, ptr1, len1, ptr2, len2);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return Wallet.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Mark an address as used at the given keychain and derivation index.
     *
     * Returns whether the given index was present in the unused set and was removed.
     * @param {KeychainKind} keychain
     * @param {number} index
     * @returns {boolean}
     */
    mark_used(keychain, index) {
        const ret = wasm.wallet_mark_used(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1, index);
        return ret !== 0;
    }
    /**
     * @returns {Network}
     */
    get network() {
        const ret = wasm.wallet_network(this.__wbg_ptr);
        return __wbindgen_enum_Network[ret];
    }
    /**
     * @returns {NetworkKind}
     */
    get network_kind() {
        const ret = wasm.wallet_network_kind(this.__wbg_ptr);
        return __wbindgen_enum_NetworkKind[ret];
    }
    /**
     * Get the next derivation index for the given keychain.
     *
     * This is one more than the highest index that has been derived so far.
     * Unlike `derivation_index`, this always returns a value (0 if nothing has been derived).
     * @param {KeychainKind} keychain
     * @returns {number}
     */
    next_derivation_index(keychain) {
        const ret = wasm.wallet_next_derivation_index(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
        return ret >>> 0;
    }
    /**
     * @param {KeychainKind} keychain
     * @returns {AddressInfo}
     */
    next_unused_address(keychain) {
        const ret = wasm.wallet_next_unused_address(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
        return AddressInfo.__wrap(ret);
    }
    /**
     * @param {KeychainKind} keychain
     * @param {number} index
     * @returns {AddressInfo}
     */
    peek_address(keychain, index) {
        const ret = wasm.wallet_peek_address(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1, index);
        return AddressInfo.__wrap(ret);
    }
    /**
     * @param {KeychainKind} keychain
     * @returns {string}
     */
    public_descriptor(keychain) {
        let deferred1_0;
        let deferred1_1;
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_public_descriptor(retptr, this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            deferred1_0 = r0;
            deferred1_1 = r1;
            return getStringFromWasm0(r0, r1);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
            wasm.__wbindgen_export5(deferred1_0, deferred1_1, 1);
        }
    }
    /**
     * @param {KeychainKind} keychain
     * @param {number} index
     * @returns {AddressInfo[]}
     */
    reveal_addresses_to(keychain, index) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_reveal_addresses_to(retptr, this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1, index);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {KeychainKind} keychain
     * @returns {AddressInfo}
     */
    reveal_next_address(keychain) {
        const ret = wasm.wallet_reveal_next_address(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1);
        return AddressInfo.__wrap(ret);
    }
    /**
     * @param {Transaction} tx
     * @returns {SentAndReceived}
     */
    sent_and_received(tx) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(tx, Transaction);
            wasm.wallet_sent_and_received(retptr, this.__wbg_ptr, tx.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return SentAndReceived.__wrap(r0);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @param {Psbt} psbt
     * @param {SignOptions} options
     * @returns {boolean}
     */
    sign(psbt, options) {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            _assertClass(psbt, Psbt);
            _assertClass(options, SignOptions);
            var ptr0 = options.__destroy_into_raw();
            wasm.wallet_sign(retptr, this.__wbg_ptr, psbt.__wbg_ptr, ptr0);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
            if (r2) {
                throw takeObject(r1);
            }
            return r0 !== 0;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * @returns {FullScanRequest}
     */
    start_full_scan() {
        const ret = wasm.wallet_start_full_scan(this.__wbg_ptr);
        return FullScanRequest.__wrap(ret);
    }
    /**
     * @returns {SyncRequest}
     */
    start_sync_with_revealed_spks() {
        const ret = wasm.wallet_start_sync_with_revealed_spks(this.__wbg_ptr);
        return SyncRequest.__wrap(ret);
    }
    /**
     * @returns {ChangeSet | undefined}
     */
    take_staged() {
        const ret = wasm.wallet_take_staged(this.__wbg_ptr);
        return ret === 0 ? undefined : ChangeSet.__wrap(ret);
    }
    /**
     * @returns {WalletTx[]}
     */
    transactions() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallet_transactions(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * Get detailed information about a transaction in the wallet.
     *
     * Returns `TxDetails` containing the sent/received amounts, fee, fee rate,
     * balance delta, chain position, and the full transaction.
     *
     * Returns `None` if the transaction is not found in the wallet.
     * @param {Txid} txid
     * @returns {TxDetails | undefined}
     */
    tx_details(txid) {
        _assertClass(txid, Txid);
        var ptr0 = txid.__destroy_into_raw();
        const ret = wasm.wallet_tx_details(this.__wbg_ptr, ptr0);
        return ret === 0 ? undefined : TxDetails.__wrap(ret);
    }
    /**
     * Undo a previous `mark_used` call.
     *
     * Returns whether the index was inserted back into the unused set.
     * Has no effect if the address was actually used in a transaction.
     * @param {KeychainKind} keychain
     * @param {number} index
     * @returns {boolean}
     */
    unmark_used(keychain, index) {
        const ret = wasm.wallet_unmark_used(this.__wbg_ptr, (__wbindgen_enum_KeychainKind.indexOf(keychain) + 1 || 3) - 1, index);
        return ret !== 0;
    }
}
if (Symbol.dispose) Wallet.prototype[Symbol.dispose] = Wallet.prototype.free;

/**
 * An event representing a change to the wallet state.
 *
 * Returned by `Wallet::apply_update_events`.
 */
export class WalletEvent {
    static __wrap(ptr) {
        const obj = Object.create(WalletEvent.prototype);
        obj.__wbg_ptr = ptr;
        WalletEventFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        WalletEventFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_walletevent_free(ptr, 0);
    }
    /**
     * The confirmation block time, for `tx_confirmed` events.
     * @returns {ConfirmationBlockTime | undefined}
     */
    get block_time() {
        const ret = wasm.walletevent_block_time(this.__wbg_ptr);
        return ret === 0 ? undefined : ConfirmationBlockTime.__wrap(ret);
    }
    /**
     * The kind of event.
     * @returns {WalletEventKind}
     */
    get kind() {
        const ret = wasm.walletevent_kind(this.__wbg_ptr);
        return __wbindgen_enum_WalletEventKind[ret];
    }
    /**
     * The new chain tip, for `chain_tip_changed` events.
     * @returns {BlockId | undefined}
     */
    get new_tip() {
        const ret = wasm.walletevent_new_tip(this.__wbg_ptr);
        return ret === 0 ? undefined : BlockId.__wrap(ret);
    }
    /**
     * The previous confirmation block time, if the transaction was previously confirmed.
     *
     * Available for: `tx_confirmed` (reorg), `tx_unconfirmed` (reorg).
     * @returns {ConfirmationBlockTime | undefined}
     */
    get old_block_time() {
        const ret = wasm.walletevent_old_block_time(this.__wbg_ptr);
        return ret === 0 ? undefined : ConfirmationBlockTime.__wrap(ret);
    }
    /**
     * The old chain tip, for `chain_tip_changed` events.
     * @returns {BlockId | undefined}
     */
    get old_tip() {
        const ret = wasm.walletevent_old_tip(this.__wbg_ptr);
        return ret === 0 ? undefined : BlockId.__wrap(ret);
    }
    /**
     * The transaction, if applicable.
     *
     * Available for: `tx_confirmed`, `tx_unconfirmed`, `tx_replaced`, `tx_dropped`.
     * @returns {Transaction | undefined}
     */
    get tx() {
        const ret = wasm.walletevent_tx(this.__wbg_ptr);
        return ret === 0 ? undefined : Transaction.__wrap(ret);
    }
    /**
     * The transaction id, if applicable.
     *
     * Available for: `tx_confirmed`, `tx_unconfirmed`, `tx_replaced`, `tx_dropped`.
     * @returns {Txid | undefined}
     */
    get txid() {
        const ret = wasm.walletevent_txid(this.__wbg_ptr);
        return ret === 0 ? undefined : Txid.__wrap(ret);
    }
}
if (Symbol.dispose) WalletEvent.prototype[Symbol.dispose] = WalletEvent.prototype.free;

/**
 * A Transaction managed by a `Wallet`.
 */
export class WalletTx {
    static __wrap(ptr) {
        const obj = Object.create(WalletTx.prototype);
        obj.__wbg_ptr = ptr;
        WalletTxFinalization.register(obj, obj.__wbg_ptr, obj);
        return obj;
    }
    __destroy_into_raw() {
        const ptr = this.__wbg_ptr;
        this.__wbg_ptr = 0;
        WalletTxFinalization.unregister(this);
        return ptr;
    }
    free() {
        const ptr = this.__destroy_into_raw();
        wasm.__wbg_wallettx_free(ptr, 0);
    }
    /**
     * The blocks that the transaction is "anchored" in.
     * @returns {ConfirmationBlockTime[]}
     */
    get anchors() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallettx_anchors(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
            var v1 = getArrayJsValueFromWasm0(r0, r1);
            wasm.__wbindgen_export5(r0, r1 * 4, 4);
            return v1;
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * How the transaction is observed in the canonical chain (confirmed or unconfirmed).
     * @returns {ChainPosition}
     */
    get chain_position() {
        const ret = wasm.wallettx_chain_position(this.__wbg_ptr);
        return ChainPosition.__wrap(ret);
    }
    /**
     * The first-seen unix timestamp of the transaction as unconfirmed.
     * @returns {bigint | undefined}
     */
    get first_seen() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallettx_first_seen(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r2 = getDataViewMemory0().getBigInt64(retptr + 8 * 1, true);
            return r0 === 0 ? undefined : BigInt.asUintN(64, r2);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * The last-seen unix timestamp of the transaction as unconfirmed.
     * @returns {bigint | undefined}
     */
    get last_seen() {
        try {
            const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
            wasm.wallettx_last_seen(retptr, this.__wbg_ptr);
            var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
            var r2 = getDataViewMemory0().getBigInt64(retptr + 8 * 1, true);
            return r0 === 0 ? undefined : BigInt.asUintN(64, r2);
        } finally {
            wasm.__wbindgen_add_to_stack_pointer(16);
        }
    }
    /**
     * A partial or full representation of the transaction.
     * @returns {Transaction}
     */
    get tx() {
        const ret = wasm.wallettx_tx(this.__wbg_ptr);
        return Transaction.__wrap(ret);
    }
    /**
     * Txid of the transaction.
     * @returns {Txid}
     */
    get txid() {
        const ret = wasm.wallettx_txid(this.__wbg_ptr);
        return Txid.__wrap(ret);
    }
}
if (Symbol.dispose) WalletTx.prototype[Symbol.dispose] = WalletTx.prototype.free;

/**
 * @param {Uint8Array} seed
 * @param {Network} network
 * @param {AddressType} address_type
 * @returns {DescriptorPair}
 */
export function seed_to_descriptor(seed, network, address_type) {
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        const ptr0 = passArray8ToWasm0(seed, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        wasm.seed_to_descriptor(retptr, ptr0, len0, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, (__wbindgen_enum_AddressType.indexOf(address_type) + 1 || 6) - 1);
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
        if (r2) {
            throw takeObject(r1);
        }
        return DescriptorPair.__wrap(r0);
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
    }
}

/**
 * @param {Uint8Array} seed
 * @param {Network} network
 * @returns {string}
 */
export function seed_to_xpriv(seed, network) {
    let deferred3_0;
    let deferred3_1;
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        const ptr0 = passArray8ToWasm0(seed, wasm.__wbindgen_export);
        const len0 = WASM_VECTOR_LEN;
        wasm.seed_to_xpriv(retptr, ptr0, len0, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1);
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
        var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
        var ptr2 = r0;
        var len2 = r1;
        if (r3) {
            ptr2 = 0; len2 = 0;
            throw takeObject(r2);
        }
        deferred3_0 = ptr2;
        deferred3_1 = len2;
        return getStringFromWasm0(ptr2, len2);
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
        wasm.__wbindgen_export5(deferred3_0, deferred3_1, 1);
    }
}

/**
 * @param {any} slip10
 * @param {Network} network
 * @returns {string}
 */
export function slip10_to_extended(slip10, network) {
    let deferred2_0;
    let deferred2_1;
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        wasm.slip10_to_extended(retptr, addHeapObject(slip10), (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1);
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
        var r3 = getDataViewMemory0().getInt32(retptr + 4 * 3, true);
        var ptr1 = r0;
        var len1 = r1;
        if (r3) {
            ptr1 = 0; len1 = 0;
            throw takeObject(r2);
        }
        deferred2_0 = ptr1;
        deferred2_1 = len1;
        return getStringFromWasm0(ptr1, len1);
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
        wasm.__wbindgen_export5(deferred2_0, deferred2_1, 1);
    }
}

/**
 * @param {string} extended_privkey
 * @param {string} fingerprint
 * @param {Network} network
 * @param {AddressType} address_type
 * @returns {DescriptorPair}
 */
export function xpriv_to_descriptor(extended_privkey, fingerprint, network, address_type) {
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        const ptr0 = passStringToWasm0(extended_privkey, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(fingerprint, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len1 = WASM_VECTOR_LEN;
        wasm.xpriv_to_descriptor(retptr, ptr0, len0, ptr1, len1, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, (__wbindgen_enum_AddressType.indexOf(address_type) + 1 || 6) - 1);
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
        if (r2) {
            throw takeObject(r1);
        }
        return DescriptorPair.__wrap(r0);
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
    }
}

/**
 * @param {string} extended_pubkey
 * @param {string} fingerprint
 * @param {Network} network
 * @param {AddressType} address_type
 * @returns {DescriptorPair}
 */
export function xpub_to_descriptor(extended_pubkey, fingerprint, network, address_type) {
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        const ptr0 = passStringToWasm0(extended_pubkey, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len0 = WASM_VECTOR_LEN;
        const ptr1 = passStringToWasm0(fingerprint, wasm.__wbindgen_export, wasm.__wbindgen_export2);
        const len1 = WASM_VECTOR_LEN;
        wasm.xpub_to_descriptor(retptr, ptr0, len0, ptr1, len1, (__wbindgen_enum_Network.indexOf(network) + 1 || 6) - 1, (__wbindgen_enum_AddressType.indexOf(address_type) + 1 || 6) - 1);
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        var r2 = getDataViewMemory0().getInt32(retptr + 4 * 2, true);
        if (r2) {
            throw takeObject(r1);
        }
        return DescriptorPair.__wrap(r0);
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
    }
}
export function __wbg_Error_30c8987f7c2ed4e2(arg0, arg1) {
    const ret = Error(getStringFromWasm0(arg0, arg1));
    return addHeapObject(ret);
}
export function __wbg_Number_14af1003b8dd5ead(arg0) {
    const ret = Number(getObject(arg0));
    return ret;
}
export function __wbg_String_8564e559799eccda(arg0, arg1) {
    const ret = String(getObject(arg1));
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_bigint_get_as_i64_a2383202b9353e4c(arg0, arg1) {
    const v = getObject(arg1);
    const ret = typeof(v) === 'bigint' ? v : undefined;
    getDataViewMemory0().setBigInt64(arg0 + 8 * 1, isLikeNone(ret) ? BigInt(0) : ret, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
}
export function __wbg___wbindgen_boolean_get_5b446f51afd21013(arg0) {
    const v = getObject(arg0);
    const ret = typeof(v) === 'boolean' ? v : undefined;
    return isLikeNone(ret) ? 0xFFFFFF : ret ? 1 : 0;
}
export function __wbg___wbindgen_debug_string_4687d8d8c2017d52(arg0, arg1) {
    const ret = debugString(getObject(arg1));
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_in_92f62ee1427d9e49(arg0, arg1) {
    const ret = getObject(arg0) in getObject(arg1);
    return ret;
}
export function __wbg___wbindgen_is_bigint_b123553bed3bb382(arg0) {
    const ret = typeof(getObject(arg0)) === 'bigint';
    return ret;
}
export function __wbg___wbindgen_is_function_1f9d30630b8b1d3d(arg0) {
    const ret = typeof(getObject(arg0)) === 'function';
    return ret;
}
export function __wbg___wbindgen_is_object_3c45d4f2dde4e749(arg0) {
    const val = getObject(arg0);
    const ret = typeof(val) === 'object' && val !== null;
    return ret;
}
export function __wbg___wbindgen_is_string_90b56bc79aad6f6c(arg0) {
    const ret = typeof(getObject(arg0)) === 'string';
    return ret;
}
export function __wbg___wbindgen_is_undefined_8865fb403f8fe9d8(arg0) {
    const ret = getObject(arg0) === undefined;
    return ret;
}
export function __wbg___wbindgen_jsval_eq_02babf21faa37971(arg0, arg1) {
    const ret = getObject(arg0) === getObject(arg1);
    return ret;
}
export function __wbg___wbindgen_jsval_loose_eq_677f21e468d6b461(arg0, arg1) {
    const ret = getObject(arg0) == getObject(arg1);
    return ret;
}
export function __wbg___wbindgen_number_get_2e0e7dee9f701a71(arg0, arg1) {
    const obj = getObject(arg1);
    const ret = typeof(obj) === 'number' ? obj : undefined;
    getDataViewMemory0().setFloat64(arg0 + 8 * 1, isLikeNone(ret) ? 0 : ret, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
}
export function __wbg___wbindgen_string_get_0380ccaa2f57f0d9(arg0, arg1) {
    const obj = getObject(arg1);
    const ret = typeof(obj) === 'string' ? obj : undefined;
    var ptr1 = isLikeNone(ret) ? 0 : passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
    var len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg___wbindgen_throw_41e9ee4f547fc59a(arg0, arg1) {
    throw new Error(getStringFromWasm0(arg0, arg1));
}
export function __wbg__wbg_cb_unref_dcc1a90847f04c41(arg0) {
    getObject(arg0)._wbg_cb_unref();
}
export function __wbg_abort_334e7f918b7c5047(arg0, arg1) {
    getObject(arg0).abort(getObject(arg1));
}
export function __wbg_abort_f78b99d80248bacb(arg0) {
    getObject(arg0).abort();
}
export function __wbg_addressinfo_new(arg0) {
    const ret = AddressInfo.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_append_1938ed58fb5613b8() { return handleError(function (arg0, arg1, arg2, arg3, arg4) {
    getObject(arg0).append(getStringFromWasm0(arg1, arg2), getStringFromWasm0(arg3, arg4));
}, arguments); }
export function __wbg_arrayBuffer_f07be74819944ea2() { return handleError(function (arg0) {
    const ret = getObject(arg0).arrayBuffer();
    return addHeapObject(ret);
}, arguments); }
export function __wbg_bdkerror_new(arg0) {
    const ret = BdkError.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_call_187d372bd5fdd4aa() { return handleError(function (arg0, arg1, arg2) {
    const ret = getObject(arg0).call(getObject(arg1), getObject(arg2));
    return addHeapObject(ret);
}, arguments); }
export function __wbg_call_6137034ef55c9d0f() { return handleError(function (arg0, arg1) {
    const ret = getObject(arg0).call(getObject(arg1));
    return addHeapObject(ret);
}, arguments); }
export function __wbg_checkpoint_new(arg0) {
    const ret = CheckPoint.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_clearTimeout_6b8d9a38b9263d65(arg0) {
    const ret = clearTimeout(takeObject(arg0));
    return addHeapObject(ret);
}
export function __wbg_confirmationblocktime_new(arg0) {
    const ret = ConfirmationBlockTime.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_crypto_38df2bab126b63dc(arg0) {
    const ret = getObject(arg0).crypto;
    return addHeapObject(ret);
}
export function __wbg_done_b41a1d26cdb37fb6(arg0) {
    const ret = getObject(arg0).done;
    return ret;
}
export function __wbg_entries_fb6397112b1de25f(arg0) {
    const ret = Object.entries(getObject(arg0));
    return addHeapObject(ret);
}
export function __wbg_evictedtx_unwrap(arg0) {
    const ret = EvictedTx.__unwrap(getObject(arg0));
    return ret;
}
export function __wbg_feeestimates_new(arg0) {
    const ret = FeeEstimates.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_fetch_9dad4fe911207b37(arg0) {
    const ret = fetch(getObject(arg0));
    return addHeapObject(ret);
}
export function __wbg_fetch_efc64baf325b084d(arg0, arg1) {
    const ret = getObject(arg0).fetch(getObject(arg1));
    return addHeapObject(ret);
}
export function __wbg_getRandomValues_c44a50d8cfdaebeb() { return handleError(function (arg0, arg1) {
    getObject(arg0).getRandomValues(getObject(arg1));
}, arguments); }
export function __wbg_get_658f6698067d9515() { return handleError(function (arg0, arg1) {
    const ret = Reflect.get(getObject(arg0), getObject(arg1));
    return addHeapObject(ret);
}, arguments); }
export function __wbg_get_6c896e0571ddae51(arg0, arg1) {
    const ret = getObject(arg0)[arg1 >>> 0];
    return addHeapObject(ret);
}
export function __wbg_get_unchecked_288889d017702237(arg0, arg1) {
    const ret = getObject(arg0)[arg1 >>> 0];
    return addHeapObject(ret);
}
export function __wbg_get_with_ref_key_6412cf3094599694(arg0, arg1) {
    const ret = getObject(arg0)[getObject(arg1)];
    return addHeapObject(ret);
}
export function __wbg_has_5d6706e5209576c1() { return handleError(function (arg0, arg1) {
    const ret = Reflect.has(getObject(arg0), getObject(arg1));
    return ret;
}, arguments); }
export function __wbg_headers_eba93595f8944c2f(arg0) {
    const ret = getObject(arg0).headers;
    return addHeapObject(ret);
}
export function __wbg_instanceof_ArrayBuffer_a99f175873e5d9b8(arg0) {
    let result;
    try {
        result = getObject(arg0) instanceof ArrayBuffer;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_instanceof_Response_b8758567269c30b2(arg0) {
    let result;
    try {
        result = getObject(arg0) instanceof Response;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_instanceof_Uint8Array_828cef2aaacafc31(arg0) {
    let result;
    try {
        result = getObject(arg0) instanceof Uint8Array;
    } catch (_) {
        result = false;
    }
    const ret = result;
    return ret;
}
export function __wbg_isArray_e15a2ff68ffdbef2(arg0) {
    const ret = Array.isArray(getObject(arg0));
    return ret;
}
export function __wbg_isSafeInteger_717808ad6a54bd9e(arg0) {
    const ret = Number.isSafeInteger(getObject(arg0));
    return ret;
}
export function __wbg_iterator_e3c31c892080e444() {
    const ret = Symbol.iterator;
    return addHeapObject(ret);
}
export function __wbg_length_7f3c00c40364105e(arg0) {
    const ret = getObject(arg0).length;
    return ret;
}
export function __wbg_length_d4bdea10311bd9cf(arg0) {
    const ret = getObject(arg0).length;
    return ret;
}
export function __wbg_localoutput_new(arg0) {
    const ret = LocalOutput.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_msCrypto_bd5a034af96bcba6(arg0) {
    const ret = getObject(arg0).msCrypto;
    return addHeapObject(ret);
}
export function __wbg_new_1dbf7428bba60a42(arg0) {
    const ret = new Uint8Array(getObject(arg0));
    return addHeapObject(ret);
}
export function __wbg_new_2e41357094e99294() { return handleError(function () {
    const ret = new AbortController();
    return addHeapObject(ret);
}, arguments); }
export function __wbg_new_617a8cdb8bb1130e() {
    const ret = new Object();
    return addHeapObject(ret);
}
export function __wbg_new_83ca405eae412a62() { return handleError(function () {
    const ret = new Headers();
    return addHeapObject(ret);
}, arguments); }
export function __wbg_new_from_slice_9a868026ffa4208a(arg0, arg1) {
    const ret = new Uint8Array(getArrayU8FromWasm0(arg0, arg1));
    return addHeapObject(ret);
}
export function __wbg_new_typed_b01cb72a8af741a3(arg0, arg1) {
    try {
        var state0 = {a: arg0, b: arg1};
        var cb0 = (arg0, arg1) => {
            const a = state0.a;
            state0.a = 0;
            try {
                return __wasm_bindgen_func_elem_12065(a, state0.b, arg0, arg1);
            } finally {
                state0.a = a;
            }
        };
        const ret = new Promise(cb0);
        return addHeapObject(ret);
    } finally {
        state0.a = 0;
    }
}
export function __wbg_new_with_length_3da0ad195f6f63ba(arg0) {
    const ret = new Uint8Array(arg0 >>> 0);
    return addHeapObject(ret);
}
export function __wbg_new_with_str_and_init_4618dee4e950224f() { return handleError(function (arg0, arg1, arg2) {
    const ret = new Request(getStringFromWasm0(arg0, arg1), getObject(arg2));
    return addHeapObject(ret);
}, arguments); }
export function __wbg_next_33784799010f1bbe(arg0) {
    const ret = getObject(arg0).next;
    return addHeapObject(ret);
}
export function __wbg_next_f4aac29c42af995c() { return handleError(function (arg0) {
    const ret = getObject(arg0).next();
    return addHeapObject(ret);
}, arguments); }
export function __wbg_node_84ea875411254db1(arg0) {
    const ret = getObject(arg0).node;
    return addHeapObject(ret);
}
export function __wbg_now_aa4ccb83129e9e55() {
    const ret = Date.now();
    return ret;
}
export function __wbg_outpoint_unwrap(arg0) {
    const ret = OutPoint.__unwrap(getObject(arg0));
    return ret;
}
export function __wbg_process_44c7a14e11e9f69e(arg0) {
    const ret = getObject(arg0).process;
    return addHeapObject(ret);
}
export function __wbg_prototypesetcall_bc27214492979395(arg0, arg1, arg2) {
    Uint8Array.prototype.set.call(getArrayU8FromWasm0(arg0, arg1), getObject(arg2));
}
export function __wbg_queueMicrotask_9833f9a49df95a49(arg0) {
    const ret = getObject(arg0).queueMicrotask;
    return addHeapObject(ret);
}
export function __wbg_queueMicrotask_a72f977e97f23c5f(arg0) {
    queueMicrotask(getObject(arg0));
}
export function __wbg_randomFillSync_6c25eac9869eb53c() { return handleError(function (arg0, arg1) {
    getObject(arg0).randomFillSync(takeObject(arg1));
}, arguments); }
export function __wbg_recipient_unwrap(arg0) {
    const ret = Recipient.__unwrap(getObject(arg0));
    return ret;
}
export function __wbg_require_b4edbdcf3e2a1ef0() { return handleError(function () {
    const ret = module.require;
    return addHeapObject(ret);
}, arguments); }
export function __wbg_resolve_0076e10020304ede(arg0) {
    const ret = Promise.resolve(getObject(arg0));
    return addHeapObject(ret);
}
export function __wbg_setTimeout_a11e03e63cbd9ad0(arg0, arg1) {
    setTimeout(getObject(arg0), arg1);
}
export function __wbg_setTimeout_f757f00851f76c42(arg0, arg1) {
    const ret = setTimeout(getObject(arg0), arg1);
    return addHeapObject(ret);
}
export function __wbg_set_6be42768c690e380(arg0, arg1, arg2) {
    getObject(arg0)[takeObject(arg1)] = takeObject(arg2);
}
export function __wbg_set_body_1fb0f1008bfc7df6(arg0, arg1) {
    getObject(arg0).body = getObject(arg1);
}
export function __wbg_set_cache_7507c4cc5938ccc7(arg0, arg1) {
    getObject(arg0).cache = __wbindgen_enum_RequestCache[arg1];
}
export function __wbg_set_credentials_e0dcce31ca532b7d(arg0, arg1) {
    getObject(arg0).credentials = __wbindgen_enum_RequestCredentials[arg1];
}
export function __wbg_set_headers_40ad33dcf016613f(arg0, arg1) {
    getObject(arg0).headers = getObject(arg1);
}
export function __wbg_set_method_dcb32343247ec427(arg0, arg1, arg2) {
    getObject(arg0).method = getStringFromWasm0(arg1, arg2);
}
export function __wbg_set_mode_74e772635acb96ec(arg0, arg1) {
    getObject(arg0).mode = __wbindgen_enum_RequestMode[arg1];
}
export function __wbg_set_signal_2dbd377604627f26(arg0, arg1) {
    getObject(arg0).signal = getObject(arg1);
}
export function __wbg_signal_e5a49a2d9c65b7f6(arg0) {
    const ret = getObject(arg0).signal;
    return addHeapObject(ret);
}
export function __wbg_static_accessor_GLOBAL_266715b9d96ba635() {
    const ret = typeof global === 'undefined' ? null : global;
    return isLikeNone(ret) ? 0 : addHeapObject(ret);
}
export function __wbg_static_accessor_GLOBAL_THIS_10fb7dc1ae063179() {
    const ret = typeof globalThis === 'undefined' ? null : globalThis;
    return isLikeNone(ret) ? 0 : addHeapObject(ret);
}
export function __wbg_static_accessor_SELF_0b583911f537483a() {
    const ret = typeof self === 'undefined' ? null : self;
    return isLikeNone(ret) ? 0 : addHeapObject(ret);
}
export function __wbg_static_accessor_WINDOW_d7f903d1508cbdc4() {
    const ret = typeof window === 'undefined' ? null : window;
    return isLikeNone(ret) ? 0 : addHeapObject(ret);
}
export function __wbg_status_ce0a98d3c57125f3(arg0) {
    const ret = getObject(arg0).status;
    return ret;
}
export function __wbg_stringify_52ff602c1cc4fbb6() { return handleError(function (arg0) {
    const ret = JSON.stringify(getObject(arg0));
    return addHeapObject(ret);
}, arguments); }
export function __wbg_subarray_002b94d5e13d1411(arg0, arg1, arg2) {
    const ret = getObject(arg0).subarray(arg1 >>> 0, arg2 >>> 0);
    return addHeapObject(ret);
}
export function __wbg_text_ff3f476b3d6b1246() { return handleError(function (arg0) {
    const ret = getObject(arg0).text();
    return addHeapObject(ret);
}, arguments); }
export function __wbg_then_c949d5a25a4e78f8(arg0, arg1, arg2) {
    const ret = getObject(arg0).then(getObject(arg1), getObject(arg2));
    return addHeapObject(ret);
}
export function __wbg_then_e71170d78fcf8954(arg0, arg1) {
    const ret = getObject(arg0).then(getObject(arg1));
    return addHeapObject(ret);
}
export function __wbg_transaction_new(arg0) {
    const ret = Transaction.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_txin_new(arg0) {
    const ret = TxIn.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_txout_new(arg0) {
    const ret = TxOut.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_unconfirmedtx_unwrap(arg0) {
    const ret = UnconfirmedTx.__unwrap(getObject(arg0));
    return ret;
}
export function __wbg_update_new(arg0) {
    const ret = Update.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_url_8e28edeab4cd6bed(arg0, arg1) {
    const ret = getObject(arg1).url;
    const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_export, wasm.__wbindgen_export2);
    const len1 = WASM_VECTOR_LEN;
    getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
    getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
}
export function __wbg_value_f3c585ee8f5ba40c(arg0) {
    const ret = getObject(arg0).value;
    return addHeapObject(ret);
}
export function __wbg_versions_276b2795b1c6a219(arg0) {
    const ret = getObject(arg0).versions;
    return addHeapObject(ret);
}
export function __wbg_walletevent_new(arg0) {
    const ret = WalletEvent.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbg_wallettx_new(arg0) {
    const ret = WalletTx.__wrap(arg0);
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000001(arg0, arg1) {
    // Cast intrinsic for `Closure(Closure { owned: true, function: Function { arguments: [Externref], shim_idx: 1152, ret: Result(Unit), inner_ret: Some(Result(Unit)) }, mutable: true }) -> Externref`.
    const ret = makeMutClosure(arg0, arg1, __wasm_bindgen_func_elem_12063);
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000002(arg0, arg1) {
    // Cast intrinsic for `Closure(Closure { owned: true, function: Function { arguments: [], shim_idx: 500, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
    const ret = makeMutClosure(arg0, arg1, __wasm_bindgen_func_elem_3837);
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000003(arg0) {
    // Cast intrinsic for `F64 -> Externref`.
    const ret = arg0;
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000004(arg0, arg1) {
    // Cast intrinsic for `Ref(Slice(U8)) -> NamedExternref("Uint8Array")`.
    const ret = getArrayU8FromWasm0(arg0, arg1);
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000005(arg0, arg1) {
    // Cast intrinsic for `Ref(String) -> Externref`.
    const ret = getStringFromWasm0(arg0, arg1);
    return addHeapObject(ret);
}
export function __wbindgen_generic_0000000000000006(arg0) {
    // Cast intrinsic for `U64 -> Externref`.
    const ret = BigInt.asUintN(64, arg0);
    return addHeapObject(ret);
}
export function __wbindgen_object_clone_ref(arg0) {
    const ret = getObject(arg0);
    return addHeapObject(ret);
}
export function __wbindgen_object_drop_ref(arg0) {
    takeObject(arg0);
}
function __wasm_bindgen_func_elem_3837(arg0, arg1) {
    wasm.__wasm_bindgen_func_elem_3837(arg0, arg1);
}

function __wasm_bindgen_func_elem_12065(arg0, arg1, arg2, arg3) {
    wasm.__wasm_bindgen_func_elem_12065(arg0, arg1, addHeapObject(arg2), addHeapObject(arg3));
}

function __wasm_bindgen_func_elem_12063(arg0, arg1, arg2) {
    try {
        const retptr = wasm.__wbindgen_add_to_stack_pointer(-16);
        wasm.__wasm_bindgen_func_elem_12063(retptr, arg0, arg1, addHeapObject(arg2));
        var r0 = getDataViewMemory0().getInt32(retptr + 4 * 0, true);
        var r1 = getDataViewMemory0().getInt32(retptr + 4 * 1, true);
        if (r1) {
            throw takeObject(r0);
        }
    } finally {
        wasm.__wbindgen_add_to_stack_pointer(16);
    }
}


const __wbindgen_enum_AddressType = ["p2pkh", "p2sh", "p2wpkh", "p2wsh", "p2tr"];


const __wbindgen_enum_Denomination = ["BTC", "cBTC", "mBTC", "uBTC", "nBTC", "pBTC", "bits", "satoshi", "msat"];


const __wbindgen_enum_KeychainKind = ["external", "internal"];


const __wbindgen_enum_Network = ["bitcoin", "testnet", "testnet4", "signet", "regtest"];


const __wbindgen_enum_NetworkKind = ["main", "test"];


const __wbindgen_enum_RequestCache = ["default", "no-store", "reload", "no-cache", "force-cache", "only-if-cached"];


const __wbindgen_enum_RequestCredentials = ["omit", "same-origin", "include"];


const __wbindgen_enum_RequestMode = ["same-origin", "no-cors", "cors", "navigate"];


const __wbindgen_enum_WalletEventKind = ["chain_tip_changed", "tx_confirmed", "tx_unconfirmed", "tx_replaced", "tx_dropped"];
const AddressFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_address_free(ptr, 1));
const AddressInfoFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_addressinfo_free(ptr, 1));
const AmountFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_amount_free(ptr, 1));
const BalanceFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_balance_free(ptr, 1));
const BdkErrorFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_bdkerror_free(ptr, 1));
const BlockFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_block_free(ptr, 1));
const BlockIdFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_blockid_free(ptr, 1));
const ChainPositionFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_chainposition_free(ptr, 1));
const ChangeSetFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_changeset_free(ptr, 1));
const CheckPointFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_checkpoint_free(ptr, 1));
const ConditionFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_condition_free(ptr, 1));
const ConfirmationBlockTimeFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_confirmationblocktime_free(ptr, 1));
const DescriptorPairFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_descriptorpair_free(ptr, 1));
const EsploraClientFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_esploraclient_free(ptr, 1));
const EvictedTxFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_evictedtx_free(ptr, 1));
const FeeEstimatesFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_feeestimates_free(ptr, 1));
const FeeRateFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_feerate_free(ptr, 1));
const FullScanRequestFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_fullscanrequest_free(ptr, 1));
const InsufficientFundsFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_insufficientfunds_free(ptr, 1));
const LocalOutputFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_localoutput_free(ptr, 1));
const OutPointFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_outpoint_free(ptr, 1));
const PolicyFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_policy_free(ptr, 1));
const PsbtFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_psbt_free(ptr, 1));
const RecipientFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_recipient_free(ptr, 1));
const ScriptBufFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_scriptbuf_free(ptr, 1));
const SentAndReceivedFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_sentandreceived_free(ptr, 1));
const SignOptionsFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_signoptions_free(ptr, 1));
const SpkIndexedFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_spkindexed_free(ptr, 1));
const SyncRequestFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_syncrequest_free(ptr, 1));
const TransactionFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_transaction_free(ptr, 1));
const TxBuilderFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_txbuilder_free(ptr, 1));
const TxDetailsFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_txdetails_free(ptr, 1));
const TxInFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_txin_free(ptr, 1));
const TxOutFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_txout_free(ptr, 1));
const TxidFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_txid_free(ptr, 1));
const UnconfirmedTxFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_unconfirmedtx_free(ptr, 1));
const UpdateFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_update_free(ptr, 1));
const WalletFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_wallet_free(ptr, 1));
const WalletEventFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_walletevent_free(ptr, 1));
const WalletTxFinalization = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(ptr => wasm.__wbg_wallettx_free(ptr, 1));

function addHeapObject(obj) {
    if (heap_next === heap.length) heap.push(heap.length + 1);
    const idx = heap_next;
    heap_next = heap[idx];

    heap[idx] = obj;
    return idx;
}

function _assertClass(instance, klass) {
    if (!(instance instanceof klass)) {
        throw new Error(`expected instance of ${klass.name}`);
    }
}

const CLOSURE_DTORS = (typeof FinalizationRegistry === 'undefined')
    ? { register: () => {}, unregister: () => {} }
    : new FinalizationRegistry(state => wasm.__wbindgen_export4(state.a, state.b));

function debugString(val) {
    // primitive types
    const type = typeof val;
    if (type == 'number' || type == 'boolean' || val == null) {
        return  `${val}`;
    }
    if (type == 'string') {
        return `"${val}"`;
    }
    if (type == 'symbol') {
        const description = val.description;
        if (description == null) {
            return 'Symbol';
        } else {
            return `Symbol(${description})`;
        }
    }
    if (type == 'function') {
        const name = val.name;
        if (typeof name == 'string' && name.length > 0) {
            return `Function(${name})`;
        } else {
            return 'Function';
        }
    }
    // objects
    if (Array.isArray(val)) {
        const length = val.length;
        let debug = '[';
        if (length > 0) {
            debug += debugString(val[0]);
        }
        for(let i = 1; i < length; i++) {
            debug += ', ' + debugString(val[i]);
        }
        debug += ']';
        return debug;
    }
    // Test for built-in
    const builtInMatches = /\[object ([^\]]+)\]/.exec(toString.call(val));
    let className;
    if (builtInMatches && builtInMatches.length > 1) {
        className = builtInMatches[1];
    } else {
        // Failed to match the standard '[object ClassName]'
        return toString.call(val);
    }
    if (className == 'Object') {
        // we're a user defined class or Object
        // JSON.stringify avoids problems with cycles, and is generally much
        // easier than looping through ownProperties of `val`.
        try {
            return 'Object(' + JSON.stringify(val) + ')';
        } catch (_) {
            return 'Object';
        }
    }
    // errors
    if (val instanceof Error) {
        return `${val.name}: ${val.message}\n${val.stack}`;
    }
    // TODO we could test for more things here, like `Set`s and `Map`s.
    return className;
}

function dropObject(idx) {
    if (idx < 1028) return;
    heap[idx] = heap_next;
    heap_next = idx;
}

function getArrayJsValueFromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    const mem = getDataViewMemory0();
    const result = [];
    for (let i = ptr; i < ptr + 4 * len; i += 4) {
        result.push(takeObject(mem.getUint32(i, true)));
    }
    return result;
}

function getArrayU8FromWasm0(ptr, len) {
    ptr = ptr >>> 0;
    return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
}

let cachedDataViewMemory0 = null;
function getDataViewMemory0() {
    if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || (cachedDataViewMemory0.buffer.detached === undefined && cachedDataViewMemory0.buffer !== wasm.memory.buffer)) {
        cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
    }
    return cachedDataViewMemory0;
}

function getStringFromWasm0(ptr, len) {
    return decodeText(ptr >>> 0, len);
}

let cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
    if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
        cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
    }
    return cachedUint8ArrayMemory0;
}

function getObject(idx) { return heap[idx]; }

function handleError(f, args) {
    try {
        return f.apply(this, args);
    } catch (e) {
        wasm.__wbindgen_export3(addHeapObject(e));
    }
}

let heap = new Array(1024).fill(undefined);
heap.push(undefined, null, true, false);

let heap_next = heap.length;

function isLikeNone(x) {
    return x === undefined || x === null;
}

function makeMutClosure(arg0, arg1, f) {
    const state = { a: arg0, b: arg1, cnt: 1 };
    const real = (...args) => {

        // First up with a closure we increment the internal reference
        // count. This ensures that the Rust closure environment won't
        // be deallocated while we're invoking it.
        state.cnt++;
        const a = state.a;
        state.a = 0;
        try {
            return f(a, state.b, ...args);
        } finally {
            state.a = a;
            real._wbg_cb_unref();
        }
    };
    real._wbg_cb_unref = () => {
        if (--state.cnt === 0) {
            wasm.__wbindgen_export4(state.a, state.b);
            state.a = 0;
            CLOSURE_DTORS.unregister(state);
        }
    };
    CLOSURE_DTORS.register(real, state, state);
    return real;
}

function passArray8ToWasm0(arg, malloc) {
    const ptr = malloc(arg.length * 1, 1) >>> 0;
    getUint8ArrayMemory0().set(arg, ptr / 1);
    WASM_VECTOR_LEN = arg.length;
    return ptr;
}

function passArrayJsValueToWasm0(array, malloc) {
    const ptr = malloc(array.length * 4, 4) >>> 0;
    const mem = getDataViewMemory0();
    for (let i = 0; i < array.length; i++) {
        mem.setUint32(ptr + 4 * i, addHeapObject(array[i]), true);
    }
    WASM_VECTOR_LEN = array.length;
    return ptr;
}

function passStringToWasm0(arg, malloc, realloc) {
    if (realloc === undefined) {
        const buf = cachedTextEncoder.encode(arg);
        const ptr = malloc(buf.length, 1) >>> 0;
        getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
        WASM_VECTOR_LEN = buf.length;
        return ptr;
    }

    let len = arg.length;
    let ptr = malloc(len, 1) >>> 0;

    const mem = getUint8ArrayMemory0();

    let offset = 0;

    for (; offset < len; offset++) {
        const code = arg.charCodeAt(offset);
        if (code > 0x7F) break;
        mem[ptr + offset] = code;
    }
    if (offset !== len) {
        if (offset !== 0) {
            arg = arg.slice(offset);
        }
        ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
        const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
        const ret = cachedTextEncoder.encodeInto(arg, view);

        offset += ret.written;
        ptr = realloc(ptr, len, offset, 1) >>> 0;
    }

    WASM_VECTOR_LEN = offset;
    return ptr;
}

function takeObject(idx) {
    const ret = getObject(idx);
    dropObject(idx);
    return ret;
}

let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
const MAX_SAFARI_DECODE_BYTES = 2146435072;
let numBytesDecoded = 0;
function decodeText(ptr, len) {
    numBytesDecoded += len;
    if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
        cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
        cachedTextDecoder.decode();
        numBytesDecoded = len;
    }
    return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}

const cachedTextEncoder = new TextEncoder();

if (!('encodeInto' in cachedTextEncoder)) {
    cachedTextEncoder.encodeInto = function (arg, view) {
        const buf = cachedTextEncoder.encode(arg);
        view.set(buf);
        return {
            read: arg.length,
            written: buf.length
        };
    };
}

let WASM_VECTOR_LEN = 0;


let wasm;
export function __wbg_set_wasm(val) {
    wasm = val;
}
