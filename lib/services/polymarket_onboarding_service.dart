// lib/services/polymarket_onboarding_service.dart
//
// Polymarket Enable Trading — deploys Gnosis Safe + sets V2 token approvals
// via Polymarket Relayer. All signing on-device, relayer pays gas.
//
// Flow:
//  1. Derive Safe address deterministically (CREATE2)
//  2. Check if already deployed → deploy via SAFE-CREATE
//  3. Check token approvals → set via SAFE transactions
//  4. Return proxy wallet (Safe) address
//
// V2 Token Approvals (one-time, gasless via relayer):
//  1. USDC.e → approve(CollateralOnramp, MAX)   — lets Safe wrap USDC.e → pUSD
//  2. pUSD   → approve(CollateralOfframp, MAX)  — lets Safe unwrap pUSD → USDC.e (claim)
//  3. pUSD   → approve(CTF Exchange V2, MAX)
//  4. pUSD   → approve(Neg Risk Exchange V2, MAX)
//  5. CTF    → setApprovalForAll(CTF Exchange V2, true)
//  6. CTF    → setApprovalForAll(Neg Risk Exchange V2, true)
//  7. CTF    → setApprovalForAll(CtfCollateralAdapter, true)
//  8. CTF    → setApprovalForAll(NegRiskCtfCollateralAdapter, true)
//  9. USDC   → approve(Uniswap V3 SwapRouter02, MAX) — bet path: USDC → USDC.e
// 10. USDC.e → approve(Uniswap V3 SwapRouter02, MAX) — winnings path: USDC.e → USDC
//
// The CLOB v1 Neg Risk Adapter (0xd91E…) is deprecated and is no longer
// approved; see polymarket_approval_inventory.dart for the full inventory.
//
// EIP-712 signatures:
//  - SAFE-CREATE uses CreateProxy typed data (Polymarket Contract Proxy Factory domain)
//  - SAFE (approvals) uses SafeTx typed data (GnosisSafe domain with chainId + verifyingContract)
//  - Safe transactions use eth_sign style: sign(prefix + eip712Hash), v += 4

import 'dart:convert';
import 'package:kute/services/polymarket/relayer_transaction.dart';
import 'package:kute/services/polymarket_claim_receipt.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    hide EthereumAddress, PolymarketConstants;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/constants/polymarket_approval_inventory.dart';
import 'package:kute/services/polymarket/market_protocol.dart';

/// Sentinel for `_pollTransaction` to escape the inner catch-and-
/// retry loop when the relayer reports a terminal state. Plain
/// `Exception(...)` was getting filtered by the legacy "rethrow only
/// if message contains FAILED/INVALID/ERROR" check, which silently
/// swallowed `PRECHECK_SKIPPED` errors and made the loop run until
/// timeout. Instances of this class always rethrow.
class _PollTerminalException implements Exception {
  final String message;
  const _PollTerminalException(this.message);
  @override
  String toString() => 'Exception: $message';
}

/// Raised when the Safe doesn't have enough of [token] to cover an operation.
/// Caller is expected to top up via the Orchestra BTC→USDC route before retry.
class InsufficientFundsException implements Exception {
  final BigInt needed; // 6-decimal base units
  final BigInt have; // 6-decimal base units
  final String token; // human label, e.g. "USDC.e"

  InsufficientFundsException({
    required this.needed,
    required this.have,
    required this.token,
  });

  /// Shortfall in human dollars (USD). 6-decimal token assumed.
  double get deficitUsd => (needed - have).toDouble() / 1e6;

  @override
  String toString() =>
      'InsufficientFundsException(need ${needed.toDouble() / 1e6} '
      '$token, have ${have.toDouble() / 1e6})';
}

/// Every hot Polymarket signing key in this file is built here, so the
/// Ledger scope guard (Phase 5 plan B12) refuses all of them inside a
/// Ledger operation.
EthPrivateKey _hotCredentials(String privateKey) {
  LedgerOperationScope.assertHotAllowed(
      HotSigningAction.polymarketHotCredentials);
  return EthPrivateKey.fromHex(privateKey);
}

// Aliases keep call-site churn minimal; PolymarketConstants is the canonical source.
const _kSafeFactory = PolymarketConstants.safeFactoryAddress;
const _kDepositWalletFactory = PolymarketConstants.depositWalletFactoryAddress;
const _kDepositWalletImpl =
    PolymarketConstants.depositWalletImplementationAddress;
const _kZeroAddress = PolymarketConstants.zeroAddress;
const _kUsdcAddress =
    PolymarketConstants.usdcAddress; // canonical user-facing stables
const _kUsdcEAddress =
    PolymarketConstants.usdcEAddress; // at-rest token in Safe
const _kPusdAddress =
    PolymarketConstants.pusdAddress; // signed-order collateral
const _kCollateralOnrampAddress = PolymarketConstants.collateralOnrampAddress;
const _kCollateralOfframpAddress = PolymarketConstants.collateralOfframpAddress;
const _kCtfAddress = PolymarketConstants.ctfAddress;
const _kExchangeAddress = PolymarketConstants.exchangeAddress; // V2
const _kNegRiskExchangeAddress =
    PolymarketConstants.negRiskExchangeAddress; // V2
const _kNegRiskCtfCollateralAdapterAddress =
    PolymarketConstants.negRiskCtfCollateralAdapterAddress;
const _kCtfCollateralAdapterAddress =
    PolymarketConstants.ctfCollateralAdapterAddress;
// Still required by the CLOB for neg-risk orders (pUSD + CTF approvals).
const _kLegacyNegRiskAdapterAddress =
    PolymarketConstants.legacyNegRiskAdapterAddress;
const _kSwapRouter02Address = PolymarketConstants.uniswapV3SwapRouter;
const _kMaxUint256Hex = PolymarketConstants.maxUint256Hex;

/// A Polygon RPC or relayer read that failed or returned no usable result.
/// Thrown only by the strict read variants; callers flag the read as
/// failed instead of treating it as zero.
class PolymarketReadException implements Exception {
  final String message;
  const PolymarketReadException(this.message);

  @override
  String toString() => 'PolymarketReadException: $message';
}

class PolymarketOnboardingService {
  final Map<String, Map<String, dynamic>> _verifiedReceipts = {};

  double? confirmedClaimCredit(String hash, String owner) {
    final receipt = _verifiedReceipts[hash.toLowerCase()];
    if (receipt == null) return null;
    final raw = claimCreditFromReceipt(receipt, owner);
    return raw == null ? null : raw.toDouble() / 1e6;
  }

  /// Backend relay base — kept for the two endpoints that MUST stay
  /// on the backend for revenue / attribution:
  ///   * POST /submit       — injects builder HMAC headers
  ///                          (POLY_BUILDER_API_KEY etc.) so Polymarket
  ///                          credits Safe deploy + exec to our builder
  ///                          account
  /// The previously-proxied read endpoints (`/deployed`,
  /// `/transaction`) are pure plumbing with no auth requirement and
  /// have been migrated to direct calls below — `eth_getCode` on
  /// Polygon RPC for deployment status, and a direct GET against
  /// `relayer-v2.polymarket.com/transaction` for relayer-tx polling.
  /// That removes the backend as a single point of failure for those
  /// two paths without touching the attribution-bearing /submit.
  String get _baseUrl {
    final backend = dotenv.env['BACKEND'] ?? '';
    return '$backend/api/v1/pm/relay';
  }

  /// Polymarket's relayer-v2. Public GETs (`/transaction`, `/nonce`,
  /// `/deployed`) require no auth; only the POST /submit needs HMAC
  /// builder headers (still served via our own backend).
  static const String _kPmRelayerBaseUrl = 'https://relayer-v2.polymarket.com';

  Future<String> deriveSafeAddress(String eoaAddress) async {
    final data = 'd600539a${_addressToHex32(eoaAddress)}';
    final result = await _ethCall(_kSafeFactory, data);
    final addrHex =
        result.length >= 64 ? result.substring(result.length - 40) : result;
    return _toChecksumAddress('0x$addrHex');
  }

  /// Compute the deterministic V2 Deposit Wallet address for [eoaAddress]
  /// — fully offline (no RPC call). Port of `deriveDepositWallet` from
  /// `@polymarket/builder-relayer-client/dist/builder/derive.js`.
  ///
  /// The wallet is a minimal ERC-1967 proxy (Solady LibClone style)
  /// `CREATE2`-deployed by the DepositWalletFactory at:
  ///   salt = keccak256(abi.encode(factory, walletId))
  ///   walletId = bytes32(owner)  (left-padded 20-byte address)
  ///   bytecodeHash = initCodeHashERC1967(implementation, args)
  ///     where args = abi.encode(factory, walletId)
  ///
  /// We return a checksummed 0x-prefixed address. Pure function — safe
  /// to call without the Safe being deployed.
  String deriveDepositWalletAddress(String eoaAddress) {
    final factoryBytes = _hexToBytes(_kDepositWalletFactory.substring(2));
    final implBytes = _hexToBytes(_kDepositWalletImpl.substring(2));

    // walletId = bytes32(owner) — left-pad the 20-byte address.
    final walletId = Uint8List(32);
    final ownerBytes = _hexToBytes(eoaAddress.substring(2));
    walletId.setRange(12, 32, ownerBytes);

    // args = abi.encode(address factory, bytes32 walletId)
    //   first 32 bytes: address (left-padded)
    //   next  32 bytes: walletId (already 32 bytes)
    final args = Uint8List(64);
    args.setRange(12, 32, factoryBytes);
    args.setRange(32, 64, walletId);

    // salt = keccak256(args)
    final salt = _keccak256(args);

    // bytecodeHash = initCodeHashERC1967(implementation, args)
    final bytecodeHash = _initCodeHashErc1967(implBytes, args);

    // CREATE2 address: keccak256(0xff || factory || salt || bytecodeHash)[12:]
    final create2Buf = Uint8List(1 + 20 + 32 + 32);
    create2Buf[0] = 0xff;
    create2Buf.setRange(1, 21, factoryBytes);
    create2Buf.setRange(21, 53, salt);
    create2Buf.setRange(53, 85, bytecodeHash);
    final hash = _keccak256(create2Buf);
    final addrHex = _bytesToHex(Uint8List.sublistView(hash, 12, 32));
    return _toChecksumAddress('0x$addrHex');
  }

  /// True when the deposit wallet contract is deployed at the EOA's
  /// derived address (eth_getCode returns non-empty bytecode).
  Future<bool> isDepositWalletDeployed(String eoaAddress) async {
    final addr = deriveDepositWalletAddress(eoaAddress);
    try {
      final code = await _ethGetCode(addr);
      return code.length > 2;
    } catch (_) {
      return false;
    }
  }

  /// Ask the factory itself for the address it will mint for [eoaAddress]:
  /// `predictWalletAddress(bytes32 id)` where id = bytes32(owner). Returns
  /// whatever variant the factory currently deploys (beacon today).
  /// Selector 0x04f1d3c7.
  Future<String> predictDepositWalletOnChain(String eoaAddress) async {
    final id =
        '000000000000000000000000${eoaAddress.substring(2).toLowerCase()}';
    final result = (await _rpcFirstAnswer('eth_call', [
      {'to': _kDepositWalletFactory, 'data': '0x04f1d3c7$id'},
      'latest',
    ]))
        .replaceFirst('0x', '');
    final addrHex =
        result.length >= 64 ? result.substring(result.length - 40) : result;
    return _toChecksumAddress('0x$addrHex');
  }

  /// Canonical deposit wallet for [eoaAddress]. Position-safe:
  ///   - if the legacy (UUPS) wallet is registered on the relayer OR has
  ///     on-chain code (the user already traded / holds positions there) →
  ///     KEEP it, so their balances and open bets stay visible + tradeable;
  ///   - otherwise → ask the FACTORY what it mints today via
  ///     `predictWalletAddress` (beacon now). No per-variant CREATE2
  ///     constants to keep in sync — if Polymarket upgrades the factory
  ///     again, this keeps working with no code change.
  /// Never-traded users (empty, undeployed UUPS) move to the current variant;
  /// anyone with a funded/deployed UUPS wallet is left where their money and
  /// positions already are.
  ///
  /// Throws [PolymarketReadException] when Polygon gives no answer. It never
  /// guesses: falling back to the UUPS address on an RPC failure pointed
  /// beacon-wallet users at an empty, undeployed wallet (shown as $0, and a
  /// deposit there would be stranded). Callers keep the last confirmed
  /// address instead (see the trading provider).
  Future<String> resolveDepositWalletAddress(String eoaAddress) async {
    final uups = deriveDepositWalletAddress(eoaAddress);
    // 1. Relayer registry — the authoritative "this wallet can trade" signal.
    //    `type=WALLET` on `/deployed` is undocumented (the relayer spec
    //    lists PROXY and SAFE) and has no documented replacement; any
    //    failure here falls through to the on-chain check below.
    try {
      final uri = Uri.parse('$_kPmRelayerBaseUrl/deployed').replace(
        queryParameters: {'address': uups, 'type': 'WALLET'},
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 &&
          (jsonDecode(resp.body) as Map<String, dynamic>)['deployed'] == true) {
        return uups; // legacy trader — keep their funded wallet
      }
    } catch (_) {
      // fall through
    }
    // 2. On-chain code — keep ANY already-deployed UUPS wallet; it is one the
    //    user has traded on and it works forever where it is. Only a clean
    //    empty answer means undeployed; if every RPC fails this throws.
    final code = await _rpcFirstAnswer('eth_getCode', [uups, 'latest']);
    if (code.length > 2) return uups; // deployed — keep, never repoint
    // 3. Undeployed UUPS → the factory's current (beacon) address, which is
    //    where every newer wallet (deployed or not) lives. Throws when no
    //    RPC answers.
    return predictDepositWalletOnChain(eoaAddress);
  }

  /// Public Polygon endpoints for every on-chain READ (wallet resolve,
  /// deploy check, approval scan, balances, receipts), tried in order. One
  /// public RPC hanging or answering "upstream overloaded" must not decide
  /// which wallet a user sees or abort Enable trading. Signed transactions
  /// never go here: they are submitted through the backend relay.
  @visibleForTesting
  static const polygonReadRpcs = [
    PolymarketConstants.polygonRpc,
    'https://polygon.drpc.org',
    'https://1rpc.io/matic',
    'https://polygon.gateway.tenderly.co',
  ];

  /// Per-request timeout for one endpoint.
  @visibleForTesting
  static Duration polygonRpcTimeout = const Duration(seconds: 5);

  /// How long an endpoint that just failed is tried after the others, so a
  /// hanging RPC costs one timeout rather than one per read.
  static const _kRpcCooldown = Duration(minutes: 1);
  static final Map<String, DateTime> _rpcCooldownUntil = {};

  /// Per endpoint: whether `eth_chainId` answered Polygon (137). A pending or
  /// settled check; an unanswered one is dropped so the next read retries.
  static final Map<String, Future<bool?>> _rpcChainChecks = {};

  @visibleForTesting
  static void debugResetPolygonRpcs() {
    _rpcCooldownUntil.clear();
    _rpcChainChecks.clear();
    polygonRpcTimeout = const Duration(seconds: 5);
  }

  /// Endpoints in try order: the ones that have not failed recently in list
  /// order, then the cooling ones (still tried before failing closed).
  static List<String> _polygonReadOrder() {
    final now = DateTime.now();
    final ready = <String>[];
    final cooling = <String>[];
    for (final rpc in polygonReadRpcs) {
      final until = _rpcCooldownUntil[rpc];
      (until != null && now.isBefore(until) ? cooling : ready).add(rpc);
    }
    return [...ready, ...cooling];
  }

  static void _rpcFailed(String rpc) =>
      _rpcCooldownUntil[rpc] = DateTime.now().add(_kRpcCooldown);

  /// One JSON-RPC request to [rpc]. Null on timeout, a non-200 status, a
  /// JSON-RPC error or a malformed body; otherwise the `result` (which may
  /// itself be null, e.g. a receipt not mined yet).
  static Future<({Object? result})?> _rpcRequest(
    String rpc,
    String method,
    List<Object> params, {
    Duration? timeout,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(rpc),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': method,
              'params': params,
              'id': 1,
            }),
          )
          .timeout(timeout ?? polygonRpcTimeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map || json['error'] != null) return null;
      return (result: json['result']);
    } catch (_) {
      return null;
    }
  }

  /// True once [rpc] has answered `eth_chainId` with Polygon. A wrong chain
  /// is remembered and the endpoint skipped for the rest of the session; an
  /// unanswered check marks it failed and is retried on a later read.
  static Future<bool> _isPolygonRpc(String rpc) async {
    final check = _rpcChainChecks.putIfAbsent(rpc, () async {
      final answer = await _rpcRequest(rpc, 'eth_chainId', const []);
      final result = answer?.result;
      if (result is! String) return null;
      return int.tryParse(result.replaceFirst('0x', ''), radix: 16) ==
          PolymarketConstants.polygonChainId;
    });
    final ok = await check;
    if (ok == null) {
      if (identical(_rpcChainChecks[rpc], check)) _rpcChainChecks.remove(rpc);
      _rpcFailed(rpc);
    }
    return ok ?? false;
  }

  /// The first usable `result` among [polygonReadRpcs]: an endpoint that
  /// times out, errors or is not on Polygon is skipped for the next one.
  /// Throws [PolymarketReadException] only when none answers, so strict
  /// callers still fail closed.
  Future<String> _rpcFirstAnswer(String method, List<Object> params) async {
    for (final rpc in _polygonReadOrder()) {
      if (!await _isPolygonRpc(rpc)) continue;
      final result = (await _rpcRequest(rpc, method, params))?.result;
      if (result is String) {
        _rpcCooldownUntil.remove(rpc);
        return result;
      }
      _rpcFailed(rpc);
    }
    throw PolymarketReadException('$method: no Polygon RPC answered');
  }

  /// Solady LibClone.initCodeHashERC1967(implementation, args).
  ///
  /// Hash of the runtime bytecode the proxy will deploy with:
  ///   prefix(10) || implementation(20) || 0x6009(2) || const2(32)
  ///     || const1(32) || args(n)
  ///
  /// where prefix is `0x61003d3d8160233d3973` with byte 1 (the high byte
  /// of the embedded length word) OR-ed with `(args.length >> 1) << 0`
  /// in the JS — actually `n << 56n` in 8-byte little-endian. We
  /// re-derive that bit position below.
  Uint8List _initCodeHashErc1967(Uint8List implementation, Uint8List args) {
    final n = BigInt.from(args.length);

    // PREFIX combined with `(n << 56)`. The original JS:
    //   const ERC1967_PREFIX = 0x61003d3d8160233d3973n;
    //   const combined = ERC1967_PREFIX + (n << 56n);
    //   toHex(combined, { size: 10 })
    // 10 bytes big-endian. The shift puts `n` into byte index 1 (from
    // the right end of a 10-byte word: bits 56..63).
    final prefixBig =
        BigInt.parse(PolymarketConstants.erc1967Prefix, radix: 16);
    final combined = prefixBig + (n << 56);
    final prefix = Uint8List(10);
    var temp = combined;
    for (var i = 9; i >= 0; i--) {
      prefix[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }

    final const1 = _hexToBytes(PolymarketConstants.erc1967Const1);
    final const2 = _hexToBytes(PolymarketConstants.erc1967Const2);

    // 0x6009 — 2-byte literal between implementation and const2.
    final mid = Uint8List.fromList([0x60, 0x09]);

    final buf = Uint8List(
      prefix.length +
          implementation.length +
          mid.length +
          const2.length +
          const1.length +
          args.length,
    );
    var off = 0;
    buf.setRange(off, off += prefix.length, prefix);
    buf.setRange(off, off += implementation.length, implementation);
    buf.setRange(off, off += mid.length, mid);
    buf.setRange(off, off += const2.length, const2);
    buf.setRange(off, off += const1.length, const1);
    buf.setRange(off, off += args.length, args);

    return _keccak256(buf);
  }

  /// True when the Safe proxy contract is already deployed at the
  /// EOA's predicted address. Reads on-chain via `eth_getCode` — no
  /// backend involvement, no third-party indexer. A non-`0x` code
  /// blob means contract bytecode is live at that address.
  Future<bool> isDeployed(String eoaAddress) async {
    final safeAddress = await deriveSafeAddress(eoaAddress);
    try {
      final code = await _ethGetCode(safeAddress);
      // `0x` (or empty) = no contract at that address yet.
      return code.length > 2;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasApprovals(String safeAddress) async {
    try {
      final results = await Future.wait([
        // Wrap path: USDC.e → CollateralOnramp.wrap()
        _ethCall(_kUsdcEAddress,
            _encodeAllowanceCall(safeAddress, _kCollateralOnrampAddress)),
        // Unwrap path: pUSD → CollateralOfframp.unwrap()
        _ethCall(_kPusdAddress,
            _encodeAllowanceCall(safeAddress, _kCollateralOfframpAddress)),
        // Trading collateral: pUSD → V2 Exchange contracts
        _ethCall(_kPusdAddress,
            _encodeAllowanceCall(safeAddress, _kExchangeAddress)),
        _ethCall(_kPusdAddress,
            _encodeAllowanceCall(safeAddress, _kNegRiskExchangeAddress)),
        // CTF outcome shares
        _ethCall(_kCtfAddress,
            _encodeIsApprovedForAllCall(safeAddress, _kExchangeAddress)),
        _ethCall(_kCtfAddress,
            _encodeIsApprovedForAllCall(safeAddress, _kNegRiskExchangeAddress)),
        _ethCall(
            _kCtfAddress,
            _encodeIsApprovedForAllCall(
                safeAddress, _kNegRiskCtfCollateralAdapterAddress)),
        _ethCall(
            _kCtfAddress,
            _encodeIsApprovedForAllCall(
                safeAddress, _kCtfCollateralAdapterAddress)),
        // Uniswap V3 router — USDC ↔ USDC.e for bet/winnings pipeline.
        _ethCall(_kUsdcAddress,
            _encodeAllowanceCall(safeAddress, _kSwapRouter02Address)),
        _ethCall(_kUsdcEAddress,
            _encodeAllowanceCall(safeAddress, _kSwapRouter02Address)),
        // The CLOB still checks the v1 Neg Risk Adapter for neg-risk orders.
        _ethCall(_kPusdAddress,
            _encodeAllowanceCall(safeAddress, _kLegacyNegRiskAdapterAddress)),
        _ethCall(
            _kCtfAddress,
            _encodeIsApprovedForAllCall(
                safeAddress, _kLegacyNegRiskAdapterAddress)),
      ]);

      final wrapAllowance = _decodeUint256(results[0]);
      final unwrapAllowance = _decodeUint256(results[1]);
      final pusdExchange = _decodeUint256(results[2]);
      final pusdNegRisk = _decodeUint256(results[3]);
      final ctfExchange = _decodeBool(results[4]);
      final ctfNegRisk = _decodeBool(results[5]);
      final ctfNegRiskCollateralAdapter = _decodeBool(results[6]);
      final ctfCollateralAdapter = _decodeBool(results[7]);
      final usdcRouter = _decodeUint256(results[8]);
      final usdceRouter = _decodeUint256(results[9]);
      final pusdLegacyNegRiskAdapter = _decodeUint256(results[10]);
      final ctfLegacyNegRiskAdapter = _decodeBool(results[11]);

      return wrapAllowance > BigInt.zero &&
          unwrapAllowance > BigInt.zero &&
          pusdExchange > BigInt.zero &&
          pusdNegRisk > BigInt.zero &&
          ctfExchange &&
          ctfNegRisk &&
          ctfNegRiskCollateralAdapter &&
          ctfCollateralAdapter &&
          usdcRouter > BigInt.zero &&
          usdceRouter > BigInt.zero &&
          pusdLegacyNegRiskAdapter > BigInt.zero &&
          ctfLegacyNegRiskAdapter;
    } catch (e) {
      return false;
    }
  }

  /// Fix only MISSING approvals — checks each one individually and skips
  /// contracts that already have sufficient allowance. V2 approval set:
  ///   - USDC.e → CollateralOnramp (for wrap)
  ///   - pUSD   → V2 Exchange + V2 NegRisk Exchange
  ///   - CTF    → setApprovalForAll(V2 Exchange) + (V2 NegRisk) +
  ///              (CtfCollateralAdapter) + (NegRiskCtfCollateralAdapter)
  Future<void> fixMissingApprovals({
    required String eoaAddress,
    required String privateKey,
    required String safeAddress,
  }) async {
    final credentials = _hotCredentials(privateKey);

    // 1) USDC.e → CollateralOnramp (wrap path)
    try {
      final allowanceHex = await _ethCall(
        _kUsdcEAddress,
        _encodeAllowanceCall(safeAddress, _kCollateralOnrampAddress),
      );
      if (_decodeUint256(allowanceHex) <= BigInt.zero) {
        await _submitSingleApproval(
          credentials: credentials,
          eoaAddress: eoaAddress,
          safeAddress: safeAddress,
          contract: _kUsdcEAddress,
          data: _encodeApprove(_kCollateralOnrampAddress),
        );
      }
    } catch (_) {}

    // 2) pUSD → CollateralOfframp (unwrap / claim path)
    try {
      final allowanceHex = await _ethCall(
        _kPusdAddress,
        _encodeAllowanceCall(safeAddress, _kCollateralOfframpAddress),
      );
      if (_decodeUint256(allowanceHex) <= BigInt.zero) {
        await _submitSingleApproval(
          credentials: credentials,
          eoaAddress: eoaAddress,
          safeAddress: safeAddress,
          contract: _kPusdAddress,
          data: _encodeApprove(_kCollateralOfframpAddress),
        );
      }
    } catch (_) {}

    // 3) pUSD → Exchange / NegRisk Exchange
    final pusdSpenders = [
      _kExchangeAddress,
      _kNegRiskExchangeAddress,
      _kLegacyNegRiskAdapterAddress,
    ];
    for (final spender in pusdSpenders) {
      try {
        final allowanceHex = await _ethCall(
          _kPusdAddress,
          _encodeAllowanceCall(safeAddress, spender),
        );
        if (_decodeUint256(allowanceHex) > BigInt.zero) continue;
      } catch (_) {}

      try {
        await _submitSingleApproval(
          credentials: credentials,
          eoaAddress: eoaAddress,
          safeAddress: safeAddress,
          contract: _kPusdAddress,
          data: _encodeApprove(spender),
        );
      } catch (_) {}
    }

    // 4) CTF.setApprovalForAll → Exchange / NegRisk Exchange /
    //    NegRiskCtfCollateralAdapter (wrapper for NegRisk redeems on
    //    post-2026-04-30 markets) / CtfCollateralAdapter (wrapper for
    //    standard-CTF redeems on V2 markets — symmetric to the NegRisk
    //    one) / the CLOB v1 Neg Risk Adapter, which the CLOB still checks
    //    for neg-risk orders.
    final ctfOperators = [
      _kExchangeAddress,
      _kNegRiskExchangeAddress,
      _kNegRiskCtfCollateralAdapterAddress,
      _kCtfCollateralAdapterAddress,
      _kLegacyNegRiskAdapterAddress,
    ];
    for (final operator in ctfOperators) {
      try {
        final approvedHex = await _ethCall(
          _kCtfAddress,
          _encodeIsApprovedForAllCall(safeAddress, operator),
        );
        if (_decodeBool(approvedHex)) continue;
      } catch (_) {}

      try {
        await _submitSingleApproval(
          credentials: credentials,
          eoaAddress: eoaAddress,
          safeAddress: safeAddress,
          contract: _kCtfAddress,
          data: _encodeSetApprovalForAll(operator),
        );
      } catch (_) {}
    }

    // 5) Uniswap V3 router: USDC + USDC.e (bet/winnings same-chain swaps)
    final routerSpenders = [_kUsdcAddress, _kUsdcEAddress];
    for (final token in routerSpenders) {
      try {
        final allowanceHex = await _ethCall(
          token,
          _encodeAllowanceCall(safeAddress, _kSwapRouter02Address),
        );
        if (_decodeUint256(allowanceHex) > BigInt.zero) continue;
      } catch (_) {}

      try {
        await _submitSingleApproval(
          credentials: credentials,
          eoaAddress: eoaAddress,
          safeAddress: safeAddress,
          contract: token,
          data: _encodeApprove(_kSwapRouter02Address),
        );
      } catch (_) {}
    }
  }

  Future<void> _submitSingleApproval({
    required EthPrivateKey credentials,
    required String eoaAddress,
    required String safeAddress,
    required String contract,
    required String data,
  }) async {
    final nonce = await _getSafeNonce(safeAddress);
    final signature = await _signSafeTx(
      credentials: credentials,
      safeAddress: safeAddress,
      to: contract,
      data: data,
      nonce: nonce,
    );
    final txRequest = {
      'type': 'SAFE',
      'from': eoaAddress,
      'to': contract,
      'proxyWallet': safeAddress,
      'data': '0x$data',
      'value': '0',
      'nonce': nonce.toString(),
      'signature': signature,
      'signatureParams': {
        'gasPrice': '0',
        'operation': '0',
        'safeTxnGas': '0',
        'baseGas': '0',
        'gasToken': _kZeroAddress,
        'refundReceiver': _kZeroAddress,
      },
    };
    final txId = await _submit(txRequest);
    await _pollTransaction(txId);
  }

  Future<void> setApprovals({
    required String eoaAddress,
    required String privateKey,
    required String safeAddress,
  }) async {
    final credentials = _hotCredentials(privateKey);

    final approvals = [
      // Wrap path: lets Safe pull USDC.e during wrap()
      (
        contract: _kUsdcEAddress,
        data: _encodeApprove(_kCollateralOnrampAddress),
        label: 'USDC.e→Onramp'
      ),
      // Unwrap path: lets Offramp pull pUSD during unwrap() (claim flow)
      (
        contract: _kPusdAddress,
        data: _encodeApprove(_kCollateralOfframpAddress),
        label: 'pUSD→Offramp'
      ),
      // pUSD trading collateral
      (
        contract: _kPusdAddress,
        data: _encodeApprove(_kExchangeAddress),
        label: 'pUSD→Exchange'
      ),
      (
        contract: _kPusdAddress,
        data: _encodeApprove(_kNegRiskExchangeAddress),
        label: 'pUSD→NegRisk'
      ),
      // CTF outcome shares
      (
        contract: _kCtfAddress,
        data: _encodeSetApprovalForAll(_kExchangeAddress),
        label: 'CTF→Exchange'
      ),
      (
        contract: _kCtfAddress,
        data: _encodeSetApprovalForAll(_kNegRiskExchangeAddress),
        label: 'CTF→NegRisk'
      ),
      (
        contract: _kCtfAddress,
        data: _encodeSetApprovalForAll(_kNegRiskCtfCollateralAdapterAddress),
        label: 'CTF→NegRiskCtfCollateralAdapter'
      ),
      (
        contract: _kCtfAddress,
        data: _encodeSetApprovalForAll(_kCtfCollateralAdapterAddress),
        label: 'CTF→CtfCollateralAdapter'
      ),
      // Uniswap V3 router — same-chain stable-stable swaps (bet & winnings paths)
      (
        contract: _kUsdcAddress,
        data: _encodeApprove(_kSwapRouter02Address),
        label: 'USDC→Uniswap'
      ),
      (
        contract: _kUsdcEAddress,
        data: _encodeApprove(_kSwapRouter02Address),
        label: 'USDC.e→Uniswap'
      ),
    ];

    for (final approval in approvals) {
      final nonce = await _getSafeNonce(safeAddress);

      final signature = await _signSafeTx(
        credentials: credentials,
        safeAddress: safeAddress,
        to: approval.contract,
        data: approval.data,
        nonce: nonce,
      );

      final txRequest = {
        'type': 'SAFE',
        'from': eoaAddress,
        'to': approval.contract,
        'proxyWallet': safeAddress,
        'data': '0x${approval.data}',
        'value': '0',
        'nonce': nonce.toString(),
        'signature': signature,
        'signatureParams': {
          'gasPrice': '0',
          'operation': '0',
          'safeTxnGas': '0',
          'baseGas': '0',
          'gasToken': _kZeroAddress,
          'refundReceiver': _kZeroAddress,
        },
      };

      final txId = await _submit(txRequest);

      await _pollTransaction(txId);
    }
  }

  /// Deploy the V2 Deposit Wallet for [eoaAddress] (if needed), set all
  /// trading approvals in a single signed batch, and return the wallet
  /// address. This is the canonical V2 onboarding sequence — replaces
  /// the legacy SAFE-CREATE + per-approval Safe-tx flow.
  ///
  /// USDC.e is the **only** collateral the V2 deposit wallet needs to
  /// approve — there's no pUSD wrapper layer in the V2 deposit-wallet
  /// flow (the V1 pUSD wrap/unwrap was specific to the Gnosis Safe
  /// pattern). All approvals fit in one batched WALLET tx.
  ///
  /// Approval set (lifted from Polymarket's
  /// `turnkey-safe-builder-example/utils/approvals.ts`):
  ///   USDC.e → CTF contract            (max-uint256)
  ///   USDC.e → CTF Exchange (V2)       (max-uint256)
  ///   USDC.e → NegRisk CTF Exchange    (max-uint256)
  ///   USDC.e → the two collateral redeem adapters
  ///   CTF.setApprovalForAll(CTF Exchange)    = true
  ///   CTF.setApprovalForAll(NegRisk Exchange) = true
  ///   CTF.setApprovalForAll(both redeem adapters) = true
  /// (the example's CLOB v1 Neg Risk Adapter entries are deprecated and
  /// dropped — see PolymarketApprovalInventoryConstants).
  ///
  /// Idempotent: if the wallet is already deployed and all approvals are
  /// in place, both legs short-circuit (deployment via `isDepositWalletDeployed`
  /// pre-check, approvals via the existing on-chain allowance scan).
  ///
  /// One setup at a time per owner: the account start, the wallet's own
  /// provisioning at unlock and a deposit can all ask at once, and two
  /// approvals batches for one wallet refuse each other (`busy`). A call
  /// while one runs shares that run's result instead of starting a second,
  /// unless that run has gone on past [setupJoinWindow].
  Future<String> enableTrading({
    required String eoaAddress,
    required String privateKey,
    void Function(String phase)? onProgress,
    void Function()? ensureCurrent,
  }) {
    final key = eoaAddress.toLowerCase();
    final running = _setupsInFlight[key];
    if (running != null &&
        DateTime.now().difference(running.startedAt) < setupJoinWindow) {
      return running.future.then((wallet) {
        ensureCurrent?.call();
        return wallet;
      });
    }
    final future = Future<String>.sync(() => _enableTradingOnce(
          eoaAddress: eoaAddress,
          privateKey: privateKey,
          onProgress: onProgress,
          ensureCurrent: ensureCurrent,
        ));
    final entry = (future: future, startedAt: DateTime.now());
    _setupsInFlight[key] = entry;
    void done() {
      if (identical(_setupsInFlight[key], entry)) _setupsInFlight.remove(key);
    }

    future.then((_) => done(), onError: (Object _) => done());
    return future;
  }

  /// Setups running now, by owner address.
  static final Map<String, ({Future<String> future, DateTime startedAt})>
      _setupsInFlight = {};

  /// How long a running setup is shared with later callers. Every step in
  /// it is bounded, so one still running past this is stuck on something
  /// a fresh attempt may not be; the later caller starts its own.
  static const setupJoinWindow = Duration(minutes: 5);

  /// How long the approvals step waits for another batch on the same
  /// deposit wallet (a deposit's conversion, a withdrawal) to finish
  /// before it reads the wallet's allowances.
  static const batchIdleWait = Duration(seconds: 150);

  /// Whether a relayer batch for [walletAddress] is running in this app.
  static bool batchInFlight(String walletAddress) =>
      _inFlightBatches.contains(walletAddress.toLowerCase());

  /// Waits until no relayer batch for [walletAddress] runs in this app, or
  /// [timeout] passes. True when the wallet is free.
  static Future<bool> waitForIdleBatch(String walletAddress,
      {Duration timeout = batchIdleWait}) async {
    final key = walletAddress.toLowerCase();
    final until = DateTime.now().add(timeout);
    while (_inFlightBatches.contains(key)) {
      if (!DateTime.now().isBefore(until)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return true;
  }

  Future<String> _enableTradingOnce({
    required String eoaAddress,
    required String privateKey,
    void Function(String phase)? onProgress,
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    // Resolve the CANONICAL deposit wallet, not the stale local UUPS
    // derivation: the factory was upgraded (~2026-07-07) to mint beacon
    // proxies, so new users get the beacon address while existing traders
    // (funded/registered UUPS wallets) are kept where their money + positions
    // already live. Everything downstream (deploy check, approvals batch, the
    // returned proxy the trading provider signs with) uses this one address.
    final walletAddress = await resolveDepositWalletAddress(eoaAddress);
    ensureCurrent?.call();

    onProgress?.call('deploying');
    final deployed = await _isAddressDeployed(walletAddress);
    ensureCurrent?.call();
    if (!deployed) {
      await deployDepositWallet(
          eoaAddress: eoaAddress, ensureCurrent: ensureCurrent);
    }

    ensureCurrent?.call();
    onProgress?.call('approvals');
    await _setDepositWalletApprovalsIfMissing(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      walletAddress: walletAddress,
      ensureCurrent: ensureCurrent,
    );

    return walletAddress;
  }

  /// eth_getCode deployment check for an explicit address (not the derived
  /// one) — used by [enableTrading] against the resolved deposit wallet.
  Future<bool> _isAddressDeployed(String addr) => hasContractCodeOrThrow(addr);

  /// Build the V2 deposit-wallet approval calldata batch — one entry per
  /// allowance/operator pair, each as a (target, value=0, data) call. The
  /// batch is signed + submitted in one go via [executeDepositWalletBatch],
  /// which is much cheaper than the legacy per-tx Safe loop.
  ///
  /// On-chain allowances are checked first; already-set approvals are
  /// skipped so this is safe to call repeatedly.
  ///
  /// Approval set covers EVERY trading + redeem + withdraw path:
  ///
  ///   USDC.e → CTF                          (V1 fallback redeem path)
  ///   USDC.e → CTF Exchange (V2)            (standard BUY collateral)
  ///   USDC.e → NegRisk CTF Exchange (V2)    (neg-risk BUY collateral)
  ///   USDC.e → CtfCollateralAdapter         (NEW standard redeem)
  ///   USDC.e → NegRiskCtfCollateralAdapter  (NEW neg-risk redeem)
  ///   USDC.e → Uniswap V3 SwapRouter        (withdraw USDC.e → USDC)
  ///   USDC   → Uniswap V3 SwapRouter        (reverse swap on bridged=true)
  ///   CTF.setApprovalForAll(CTF Exchange)             true
  ///   CTF.setApprovalForAll(NegRisk Exchange)         true
  ///   CTF.setApprovalForAll(CtfCollateralAdapter)     true
  ///   CTF.setApprovalForAll(NegRiskCtfCollateralAdpr) true
  Future<void> _setDepositWalletApprovalsIfMissing({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    void Function()? ensureCurrent,
  }) async {
    // A conversion or withdrawal batch running on this wallet would refuse
    // the approvals batch (`busy`), so the allowances are read once it is
    // done. Approvals are read fresh on every pass, so a pass that follows
    // another setup's batch finds them set and sends nothing.
    for (var pass = 0;; pass++) {
      ensureCurrent?.call();
      await waitForIdleBatch(walletAddress);
      ensureCurrent?.call();
      try {
        await _setMissingApprovalsOnce(
          eoaAddress: eoaAddress,
          privateKey: privateKey,
          walletAddress: walletAddress,
          ensureCurrent: ensureCurrent,
        );
        return;
      } on LedgerFailure catch (e) {
        if (e.code != LedgerFailureCode.busy || pass >= 2) rethrow;
      }
    }
  }

  Future<void> _setMissingApprovalsOnce({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    void Function()? ensureCurrent,
  }) async {
    // ERC-20 spenders that need USDC.e allowance from the deposit wallet.
    // CollateralOnramp is the WRAP path — V2 deposit wallets trade pUSD
    // as collateral on the Exchange, NOT USDC.e directly (the
    // `turnkey-safe-builder-example` uses Gnosis Safe + sigType=2 which
    // doesn't have this wrap step; POLY_1271 docs explicitly require
    // pUSD funding). The wallet pulls USDC.e from itself via this
    // allowance whenever it calls `CollateralOnramp.wrap()`.
    final usdcESpenders = PolymarketApprovalInventoryConstants.usdcESpenders;
    // pUSD also needs spender approvals — primarily for the Exchange
    // contracts that pull collateral on match, and for the Offramp
    // (unwrap pUSD → USDC.e during withdraws/claims).
    final pusdSpenders = PolymarketApprovalInventoryConstants.pusdSpenders;
    // Native USDC also needs Uniswap allowance for the reverse swap
    // (used by `bridged=true` withdraws).
    final usdcSpenders = PolymarketApprovalInventoryConstants.usdcSpenders;
    // ERC-1155 operators that need setApprovalForAll, per share ledger:
    // CTF (both Exchange contracts and every redeem adapter we route
    // claims through) and the Protocol V2 PositionManager (ExchangeV3 for
    // sells, the Router for claims).
    final ctfOperators = PolymarketApprovalInventoryConstants.ctfOperators;
    final positionOperators =
        PolymarketApprovalInventoryConstants.positionManagerOperators;

    final calls = <({String target, BigInt value, String data})>[];

    // Bound concurrency to four RPC reads. A timeout/error is unknown, never
    // a missing allowance: finish a successful scan before signing any batch.
    final checks = <Future<void> Function()>[];
    for (final entry in PolymarketApprovalInventoryConstants
        .activeErc20SpendersByToken.entries) {
      for (final spender in entry.value) {
        checks.add(() async {
          final allowance = await readApprovalOrThrow(
              token: entry.key, owner: walletAddress, spender: spender);
          if (allowance > BigInt.zero) return;
          calls.add((
            target: entry.key,
            value: BigInt.zero,
            data: '0x${_encodeApprove(spender)}',
          ));
        });
      }
    }
    for (final entry in PolymarketApprovalInventoryConstants
        .activeOperatorsByToken.entries) {
      for (final operator in entry.value) {
        checks.add(() async {
          final approved = await readApprovalOrThrow(
              token: entry.key,
              owner: walletAddress,
              spender: operator,
              operatorApproval: true);
          if (approved == BigInt.one) return;
          calls.add((
            target: entry.key,
            value: BigInt.zero,
            data: '0x${_encodeSetApprovalForAll(operator)}',
          ));
        });
      }
    }
    for (var offset = 0; offset < checks.length; offset += 4) {
      ensureCurrent?.call();
      await Future.wait(checks.skip(offset).take(4).map((check) => check()));
      ensureCurrent?.call();
    }

    if (calls.isEmpty) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[poly-relayer] all deposit-wallet approvals already set');
      }
      return;
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] queueing ${calls.length} approval calls '
          '(${usdcESpenders.length} USDC.e + ${pusdSpenders.length} pUSD '
          '+ ${usdcSpenders.length} USDC + ${ctfOperators.length} CTF '
          '+ ${positionOperators.length} PositionManager)');
    }

    // 10-minute deadline gives the relayer plenty of headroom even
    // during Polygon congestion.
    final deadline = DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;

    await executeDepositWalletBatch(
      eoaAddress: eoaAddress,
      signer: CredentialsDepositWalletBatchSigner(privateKey),
      walletAddress: walletAddress,
      calls: calls,
      deadline: deadline,
      ensureCurrent: ensureCurrent,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Combos (Positions Framework): approvals, balances, redeem calldata
  // ──────────────────────────────────────────────────────────────────

  /// The one-time combo approvals, set in ONE gasless deposit-wallet batch
  /// through the same relayer path as onboarding, only for what is missing:
  ///
  ///   pUSD.approve(Exchange v3, MAX)                       BUY stake
  ///   PositionManager.setApprovalForAll(Exchange v3, true) SELL (close)
  ///   PositionManager.setApprovalForAll(Router, true)      claim (redeem)
  ///
  /// Reads every allowance first; an unreadable one throws instead of
  /// being treated as missing. Returns true when a batch was sent.
  Future<bool> ensureComboApprovals({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    void Function()? ensureCurrent,
  }) async {
    final calls = <({String target, BigInt value, String data})>[];
    ensureCurrent?.call();
    for (final spender
        in PolymarketApprovalInventoryConstants.comboPusdSpenders) {
      final allowance = await readApprovalOrThrow(
          token: PolymarketConstants.pusdAddress,
          owner: walletAddress,
          spender: spender);
      if (allowance > BigInt.zero) continue;
      calls.add((
        target: PolymarketConstants.pusdAddress,
        value: BigInt.zero,
        data: '0x${_encodeApprove(spender)}',
      ));
    }
    for (final operator
        in PolymarketApprovalInventoryConstants.comboPositionOperators) {
      final approved = await readApprovalOrThrow(
          token: PolymarketConstants.comboPositionManagerAddress,
          owner: walletAddress,
          spender: operator,
          operatorApproval: true);
      if (approved == BigInt.one) continue;
      calls.add((
        target: PolymarketConstants.comboPositionManagerAddress,
        value: BigInt.zero,
        data: '0x${_encodeSetApprovalForAll(operator)}',
      ));
    }
    ensureCurrent?.call();
    if (calls.isEmpty) return false;
    final deadline = DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    await executeDepositWalletBatch(
      eoaAddress: eoaAddress,
      signer: CredentialsDepositWalletBatchSigner(privateKey),
      walletAddress: walletAddress,
      calls: calls,
      deadline: deadline,
      ensureCurrent: ensureCurrent,
    );
    return true;
  }

  /// Sets the one approval an order refusal named ("the allowance is not
  /// enough -> spender: 0x…"): what [polymarketPinnedSpenderApprovals]
  /// lists for [spender] (pUSD, and the CTF or PositionManager operator
  /// approval where that contract moves shares), each only when it reads
  /// as missing, in one gasless deposit-wallet batch. [spender] must
  /// be one of Polymarket's pinned contracts (polymarketPinnedSpenders);
  /// any other address throws and nothing is signed. True when a batch was
  /// sent. Callers bound the wait; the batch itself is idempotent.
  Future<bool> approveRefusalSpender({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    required String spender,
    void Function()? ensureCurrent,
  }) async {
    final address = spender.toLowerCase();
    final approvals = polymarketPinnedSpenderApprovals[address];
    if (approvals == null || !polymarketPinnedSpenders.containsKey(address)) {
      throw ArgumentError('Not a pinned Polymarket contract');
    }
    ensureCurrent?.call();
    await waitForIdleBatch(walletAddress);
    ensureCurrent?.call();
    final calls = <({String target, BigInt value, String data})>[];
    if (approvals.contains(PolymarketSpenderApproval.pusd)) {
      final allowance = await readApprovalOrThrow(
          token: PolymarketConstants.pusdAddress,
          owner: walletAddress,
          spender: address);
      if (allowance == BigInt.zero) {
        calls.add((
          target: PolymarketConstants.pusdAddress,
          value: BigInt.zero,
          data: '0x${_encodeApprove(address)}',
        ));
      }
    }
    for (final (kind, ledger) in const [
      (PolymarketSpenderApproval.ctfOperator, _kCtfAddress),
      (
        PolymarketSpenderApproval.positionOperator,
        PolymarketConstants.comboPositionManagerAddress
      ),
    ]) {
      if (!approvals.contains(kind)) continue;
      final approved = await readApprovalOrThrow(
          token: ledger,
          owner: walletAddress,
          spender: address,
          operatorApproval: true);
      if (approved != BigInt.one) {
        calls.add((
          target: ledger,
          value: BigInt.zero,
          data: '0x${_encodeSetApprovalForAll(address)}',
        ));
      }
    }
    ensureCurrent?.call();
    if (calls.isEmpty) return false;
    final deadline = DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    await executeDepositWalletBatch(
      eoaAddress: eoaAddress,
      signer: CredentialsDepositWalletBatchSigner(privateKey),
      walletAddress: walletAddress,
      calls: calls,
      deadline: deadline,
      ensureCurrent: ensureCurrent,
    );
    return true;
  }

  /// Combo shares [owner] holds of [positionId] (decimal), in base units:
  /// `PositionManager.balanceOf(address,uint256)`. Throws on RPC failure so
  /// a failed read never claims zero.
  Future<BigInt> readComboBalanceOrThrow({
    required String owner,
    required String positionId,
  }) async {
    final id = BigInt.tryParse(positionId);
    if (id == null || id.isNegative) {
      throw const PolymarketReadException('not a position id');
    }
    final hex = await _ethCallStrict(
        PolymarketConstants.comboPositionManagerAddress,
        '00fdd58e${_addressToHex32(owner)}'
        '${id.toRadixString(16).padLeft(64, '0')}');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const PolymarketReadException('balanceOf returned no uint256');
    }
    return BigInt.parse(hex, radix: 16);
  }

  /// Router `redeem(bytes31 conditionId, uint256 outcomeIndex,
  /// uint256 amount)` calldata (0x-prefixed). The 31-byte condition id is
  /// left-aligned in its word, as `bytes31` encodes.
  static String comboRedeemCalldata({
    required String conditionId,
    required int outcomeIndex,
    required BigInt amount,
  }) {
    final clean = conditionId.toLowerCase().replaceFirst('0x', '');
    if (clean.length != 62 || !RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
      throw ArgumentError('conditionId must be 31 bytes');
    }
    if (outcomeIndex != 0 && outcomeIndex != 1) {
      throw ArgumentError('outcomeIndex must be 0 or 1');
    }
    if (amount <= BigInt.zero) throw ArgumentError('amount must be positive');
    return '0xd217a3cc'
        '${clean}00'
        '${BigInt.from(outcomeIndex).toRadixString(16).padLeft(64, '0')}'
        '${amount.toRadixString(16).padLeft(64, '0')}';
  }

  /// Redeems [amount] combo shares of [conditionId] (YES, outcome 0) through
  /// the Router in one gasless deposit-wallet batch. Returns the tx hash.
  Future<String> redeemComboPosition({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    required String conditionId,
    required BigInt amount,
    int outcomeIndex = 0,
    void Function()? ensureCurrent,
  }) =>
      submitDepositWalletCall(
        eoaAddress: eoaAddress,
        privateKey: privateKey,
        walletAddress: walletAddress,
        to: PolymarketConstants.comboRouterAddress,
        data: comboRedeemCalldata(
            conditionId: conditionId,
            outcomeIndex: outcomeIndex,
            amount: amount),
        ensureCurrent: ensureCurrent,
      );

  // ──────────────────────────────────────────────────────────────────
  // Protocol V2 positions: payouts and the Router claim
  // ──────────────────────────────────────────────────────────────────

  static String? _getPayoutSelector;

  /// Payout per share of YES (`[0]`) and NO (`[1]`) of the V2 condition
  /// [conditionId31] (31 bytes), from `PositionManager.getPayout(uint256
  /// positionId, uint256 amount)` for one share each. Null while the
  /// condition is unresolved (the call reverts, or pays nothing on either
  /// side) or unreadable. A resolved condition pays its full share across
  /// the two sides, so a zero side is a verified loss.
  Future<List<double>?> readV2Payouts(String conditionId31) async {
    try {
      final selector = _getPayoutSelector ??= KeccakDigest(256)
          .process(
              Uint8List.fromList(utf8.encode('getPayout(uint256,uint256)')))
          .take(4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final share = BigInt.from(1000000);
      final out = <BigInt>[];
      for (final outcome in const [0, 1]) {
        final id = BigInt.parse(
            PolyMarketProtocol.v2PositionId(conditionId31, outcome));
        final hex = await _ethCallStrict(
            PolymarketConstants.comboPositionManagerAddress,
            '$selector${id.toRadixString(16).padLeft(64, '0')}'
            '${share.toRadixString(16).padLeft(64, '0')}');
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) return null;
        out.add(BigInt.parse(hex, radix: 16));
      }
      final total = out[0] + out[1];
      if (total == BigInt.zero || out.any((v) => v > share)) return null;
      return [for (final v in out) v.toDouble() / share.toDouble()];
    } catch (_) {
      return null;
    }
  }

  /// Router `redeem` calls for every side of the V2 position [positionId]'s
  /// condition that [owner] holds, each for its full PositionManager
  /// balance (V2 redeems one outcome per call). Empty when nothing is
  /// held. Throws on an unreadable balance.
  Future<List<({String target, BigInt value, String data})>> v2RedeemCalls(
      {required String positionId, required String owner}) async {
    final split = PolyMarketProtocol.splitV2(positionId);
    final ids = [
      PolyMarketProtocol.v2PositionId(split.conditionId, 0),
      PolyMarketProtocol.v2PositionId(split.conditionId, 1),
    ];
    final held =
        await readCtfBalancesBatchOrThrow(positionIds: ids, owner: owner);
    return [
      for (var outcome = 0; outcome < 2; outcome++)
        if ((held[ids[outcome]] ?? BigInt.zero) > BigInt.zero)
          (
            target: PolymarketConstants.comboRouterAddress,
            value: BigInt.zero,
            data: comboRedeemCalldata(
                conditionId: split.conditionId,
                outcomeIndex: outcome,
                amount: held[ids[outcome]]!),
          ),
    ];
  }

  // ──────────────────────────────────────────────────────────────────
  // LEGACY: pre-V2 Safe path. Kept compiled so existing wallets can
  // still be read (`isDeployed`, `deriveSafeAddress`) but no longer
  // routes any of the actual trading flow.
  // ──────────────────────────────────────────────────────────────────

  Future<String> enableTradingLegacySafe({
    required String eoaAddress,
    required String privateKey,
    void Function(String phase)? onProgress,
  }) async {
    final safeAddress = await deriveSafeAddress(eoaAddress);

    onProgress?.call('deploying');
    final deployed = await isDeployed(eoaAddress);
    if (!deployed) {
      final credentials = _hotCredentials(privateKey);
      final signature = await _signCreateProxy(credentials);

      final txRequest = {
        'type': 'SAFE-CREATE',
        'from': eoaAddress,
        'to': _kSafeFactory,
        'proxyWallet': safeAddress,
        'data': '0x',
        'signature': signature.startsWith('0x') ? signature : '0x$signature',
        'signatureParams': {
          'paymentToken': _kZeroAddress,
          'payment': '0',
          'paymentReceiver': _kZeroAddress,
        },
      };

      final txId = await _submit(txRequest);

      await _pollTransaction(txId);
    }

    onProgress?.call('approvals');
    // Use fixMissingApprovals to only set what's actually missing,
    // avoiding issues with re-submitting existing approvals.
    await fixMissingApprovals(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      safeAddress: safeAddress,
    );

    return safeAddress;
  }

  /// Read the V2 Deposit Wallet's relayer nonce for [eoaAddress].
  ///
  /// Different namespace from the Safe nonce. Reads the documented
  /// Deposit Wallet route first,
  /// `GET /v1/account/transactions/params?address=<signer>&type=WALLET`
  /// (docs: trading/wallets-auth), which
  /// answers `{address, nonce}` without auth. The relayer's `/nonce` only
  /// documents `type ∈ {PROXY, SAFE}`; its undocumented `type=WALLET`
  /// answer is the fallback when the documented route fails. Both are
  /// keyed by the signer and gave the same nonce for every live signer
  /// checked on 2026-10-07. The `address` the documented route returns is
  /// not used: it can name the factory's current wallet rather than the
  /// (legacy UUPS) wallet the batch is for. Public GETs, so straight to
  /// Polymarket's relayer, as for SAFE nonces.
  Future<String> _getDepositWalletNonce(String eoaAddress) async {
    try {
      return await _readWalletNonce(
          _kRelayerWalletParamsPath, eoaAddress, const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[poly-relayer] WALLET params nonce failed ($e), '
            'falling back to /nonce');
      }
      return _readWalletNonce(
          '/nonce', eoaAddress, const Duration(seconds: 15));
    }
  }

  /// The documented Deposit Wallet nonce route on the relayer.
  static const _kRelayerWalletParamsPath = '/v1/account/transactions/params';

  Future<String> _readWalletNonce(
      String path, String eoaAddress, Duration timeout) async {
    final uri = Uri.parse('$_kPmRelayerBaseUrl$path').replace(
      queryParameters: {'address': eoaAddress, 'type': 'WALLET'},
    );
    final resp = await http.get(uri).timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception('relayer $path(WALLET) failed: ${resp.statusCode}');
    }
    final nonce = parseRelayerWalletNonce(jsonDecode(resp.body));
    if (nonce == null) {
      throw Exception('relayer $path(WALLET) returned no nonce');
    }
    return nonce;
  }

  /// The nonce of a relayer nonce answer (`{nonce}` from `/nonce`,
  /// `{address, nonce}` from `/v1/account/transactions/params`) as a
  /// decimal string, or null when it is missing or not a non-negative
  /// integer (a signature must never commit to a garbled nonce).
  @visibleForTesting
  static String? parseRelayerWalletNonce(Object? decoded) {
    if (decoded is! Map) return null;
    final raw = decoded['nonce'];
    if (raw is! String && raw is! int) return null;
    final value = BigInt.tryParse('$raw'.trim());
    if (value == null || value.isNegative) return null;
    return value.toString();
  }

  // A transfer must never receive an approval or another transfer's hash.
  // Keep each wallet exclusive until its batch finishes or fails.
  static final Set<String> _inFlightBatches = {};

  /// Execute a batch of calls atomically on the user's V2 Deposit Wallet.
  ///
  /// Mirrors `RelayClient.executeDepositWalletBatch` in
  /// `@polymarket/builder-relayer-client`. Single EIP-712 signature over
  /// `Batch(address wallet,uint256 nonce,uint256 deadline,Call[] calls)`
  /// covering N transfer/approve/swap calls — strict ordering, all-or-
  /// nothing execution. Each [calls] entry is `(target, value, data)`.
  ///
  /// [deadline] is a Unix-seconds timestamp; the relayer rejects the
  /// batch if it can't mine it before then. Caller chooses — 5–10 min
  /// from now is plenty.
  ///
  /// Returns the on-chain tx hash once the relayer mines it.
  ///
  /// Concurrent calls for the same wallet fail with `busy` before signing.
  /// Even identical calls may represent separate withdrawals, so a caller
  /// must retry its own operation after the in-flight batch is reconciled.
  Future<String> executeDepositWalletBatch({
    required String eoaAddress,
    required DepositWalletBatchSigner signer,
    required String walletAddress, // user's deposit wallet
    required List<({String target, BigInt value, String data})> calls,
    required int deadline, // unix seconds
    // Ledger submission tracking: called after signing and before the
    // relayer POST with the WALLET nonce the signature commits to, then
    // with the relayer transaction ID once accepted. A throw from
    // [beforeSubmit] aborts before anything is sent.
    Future<void> Function(String relayerNonce)? beforeSubmit,
    Future<void> Function(String relayerTxId)? onSubmitted,
    bool requireConfirmed = false,
    void Function()? ensureCurrent,
  }) async {
    final lockKey = walletAddress.toLowerCase();
    if (!_inFlightBatches.add(lockKey)) {
      throw const LedgerFailure(LedgerFailureCode.busy);
    }
    try {
      return await _executeDepositWalletBatchInner(
        eoaAddress: eoaAddress,
        signer: signer,
        walletAddress: walletAddress,
        calls: calls,
        deadline: deadline,
        beforeSubmit: beforeSubmit,
        onSubmitted: onSubmitted,
        requireConfirmed: requireConfirmed,
        ensureCurrent: ensureCurrent,
      );
    } finally {
      _inFlightBatches.remove(lockKey);
    }
  }

  Future<String> _executeDepositWalletBatchInner({
    required String eoaAddress,
    required DepositWalletBatchSigner signer,
    required String walletAddress,
    required List<({String target, BigInt value, String data})> calls,
    required int deadline,
    Future<void> Function(String relayerNonce)? beforeSubmit,
    Future<void> Function(String relayerTxId)? onSubmitted,
    bool requireConfirmed = false,
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    final nonce = await _getDepositWalletNonce(eoaAddress);
    ensureCurrent?.call();

    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET batch prep: wallet=$walletAddress '
          'nonce=$nonce calls=${calls.length} deadline=$deadline');
    }

    final signature = await _signDepositWalletBatch(
      signer: signer,
      walletAddress: walletAddress,
      nonce: BigInt.parse(nonce),
      deadline: BigInt.from(deadline),
      calls: calls,
    );

    // The relayer expects the calls inline under `depositWalletParams`.
    // Each call's `data` must include the 0x prefix.
    final callsJson = calls
        .map((c) => {
              'target': c.target,
              'value': c.value.toString(),
              'data': c.data.startsWith('0x') ? c.data : '0x${c.data}',
            })
        .toList();

    final txRequest = {
      'type': 'WALLET',
      'from': eoaAddress,
      'to': _kDepositWalletFactory,
      'nonce': nonce,
      'signature': signature,
      'depositWalletParams': {
        'depositWallet': walletAddress,
        'deadline': deadline.toString(),
        'calls': callsJson,
      },
    };

    if (beforeSubmit != null) await beforeSubmit(nonce);

    final String txId;
    try {
      txId = await _submit(txRequest, ensureCurrent: ensureCurrent);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[poly-relayer] WALLET batch /submit threw: $e');
      }
      rethrow;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET batch accepted, txId=$txId — polling…');
    }
    if (onSubmitted != null) await onSubmitted(txId);
    final String hash;
    try {
      hash = await _pollTransaction(txId, requireConfirmed: requireConfirmed);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[poly-relayer] WALLET batch poll threw for txId=$txId: $e');
      }
      rethrow;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET batch hash=$hash');
    }
    return hash;
  }

  /// PRE-SIGN variant of [_executeDepositWalletBatchInner]: fetches the
  /// wallet nonce, signs the batch, and returns the relayer `/submit` body
  /// WITHOUT posting it — the instant-placement flow hands this to the
  /// backend, which relays it when the funding swap lands. The [deadline]
  /// (unix seconds) is baked into the EIP-712 signature, so callers must
  /// pass a GENEROUS one (hours, not the interactive path's 10 minutes):
  /// a cross-chain swap can outlive a short deadline and a pre-signed
  /// batch past its deadline is dead (relayer + contract reject it).
  ///
  /// GOTCHA: the signature also bakes in the CURRENT deposit-wallet nonce.
  /// If any other WALLET batch for this deposit wallet executes between
  /// pre-signing and the backend's relay, this body is invalidated. The
  /// instant flow relies on the backend relaying it BEFORE the app's own
  /// balance-reading wrap could run (and treats wrap failure as non-fatal:
  /// the CLOB balance check is the authoritative gate).
  Future<Map<String, dynamic>> buildDepositWalletBatchRequest({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    required List<({String target, BigInt value, String data})> calls,
    required int deadline, // unix seconds
  }) async {
    final nonce = await _getDepositWalletNonce(eoaAddress);

    final signature = await _signDepositWalletBatch(
      signer: CredentialsDepositWalletBatchSigner(privateKey),
      walletAddress: walletAddress,
      nonce: BigInt.parse(nonce),
      deadline: BigInt.from(deadline),
      calls: calls,
    );

    // Same shape _executeDepositWalletBatchInner posts: calls inline under
    // `depositWalletParams`, each call's data 0x-prefixed.
    final callsJson = calls
        .map((c) => {
              'target': c.target,
              'value': c.value.toString(),
              'data': c.data.startsWith('0x') ? c.data : '0x${c.data}',
            })
        .toList();

    return {
      'type': 'WALLET',
      'from': eoaAddress,
      'to': _kDepositWalletFactory,
      'nonce': nonce,
      'signature': signature,
      'depositWalletParams': {
        'depositWallet': walletAddress,
        'deadline': deadline.toString(),
        'calls': callsJson,
      },
    };
  }

  /// Public calldata builders so the trading provider can construct
  /// multi-call deposit-wallet batches (e.g. unwrap + swap + transfer
  /// in a single atomic withdraw). Returns hex WITHOUT a `0x` prefix —
  /// callers add it when packing into batch entries.
  String encodeWrapCall(String asset, String to, BigInt amount) =>
      _encodeWrap(asset, to, amount);
  String encodeUnwrapCall(String asset, String to, BigInt amount) =>
      _encodeUnwrap(asset, to, amount);

  /// Address constants exposed so call sites don't import the constants
  /// file just to read these two contract targets.
  String get collateralOnrampAddress => _kCollateralOnrampAddress;
  String get collateralOfframpAddress => _kCollateralOfframpAddress;

  /// V2 deposit-wallet wrap: convert any USDC.e in the wallet to pUSD
  /// in a single batched call (`CollateralOnramp.wrap(USDC.e, wallet, amount)`).
  ///
  /// V2 deposit wallets fund the Exchange in **pUSD** — the Polymarket
  /// docs are explicit on `/trading/deposit-wallets`. USDC.e arriving
  /// from a deposit (Orchestra → wallet) doesn't count as collateral
  /// until it's wrapped to pUSD via the on-chain CollateralOnramp.
  /// Without this step, the CLOB checks the wallet's pUSD balance,
  /// sees zero, and rejects every order with
  ///   "not enough balance / allowance — balance: 0, order amount: …"
  /// regardless of how much USDC.e is actually there.
  ///
  /// Returns `true` when a wrap was submitted (and confirmed), `false`
  /// when no USDC.e was present to wrap. Idempotent + cheap to call
  /// before every order placement as a defensive step.
  Future<bool> wrapUsdceToPusdInDepositWallet({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    void Function()? ensureCurrent,
  }) async =>
      await wrapHeldUsdceToPusdInDepositWallet(
        eoaAddress: eoaAddress,
        privateKey: privateKey,
        walletAddress: walletAddress,
        ensureCurrent: ensureCurrent,
      ) >
      BigInt.zero;

  /// [wrapUsdceToPusdInDepositWallet], returning the micro-USDC.e wrapped:
  /// exactly the balance read just before signing, never more, or zero
  /// when there was none.
  Future<BigInt> wrapHeldUsdceToPusdInDepositWallet({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    final usdce = await readErc20Balance(
      token: _kUsdcEAddress,
      owner: walletAddress,
    );
    ensureCurrent?.call();
    if (usdce <= BigInt.zero) return BigInt.zero;

    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WRAP $usdce micro USDC.e → pUSD '
          'in deposit wallet $walletAddress');
    }
    await submitDepositWalletCall(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      walletAddress: walletAddress,
      to: _kCollateralOnrampAddress,
      data: _encodeWrap(_kUsdcEAddress, walletAddress, usdce),
      ensureCurrent: ensureCurrent,
    );
    return usdce;
  }

  /// Convenience wrapper around [executeDepositWalletBatch] for a single
  /// call — same arity as the legacy [submitSafeTx] so V1-shaped call
  /// sites can be ported with minimal diff. Use the batched form
  /// directly when you have 2+ calls to keep them atomic + single-fee.
  Future<String> submitDepositWalletCall({
    required String eoaAddress,
    required String privateKey,
    required String walletAddress,
    required String to,
    required String data, // hex with or without 0x prefix
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    final deadline = DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    return executeDepositWalletBatch(
      eoaAddress: eoaAddress,
      signer: CredentialsDepositWalletBatchSigner(privateKey),
      walletAddress: walletAddress,
      calls: [
        (
          target: to,
          value: BigInt.zero,
          data: data.startsWith('0x') ? data : '0x$data',
        )
      ],
      deadline: deadline,
      ensureCurrent: ensureCurrent,
    );
  }

  /// The builder's own domain separator and Batch struct hash, exposed so
  /// tests can pin the generic typed data encoder equal to them.
  @visibleForTesting
  ({Uint8List domain, Uint8List message}) debugDepositWalletBatchHashes({
    required String walletAddress,
    required BigInt nonce,
    required BigInt deadline,
    required List<({String target, BigInt value, String data})> calls,
  }) =>
      (
        domain: _hashDepositWalletDomain(walletAddress: walletAddress),
        message: _hashBatchStruct(
          walletAddress: walletAddress,
          nonce: nonce,
          deadline: deadline,
          calls: calls,
        ),
      );

  /// EIP-712 sign the DepositWallet Batch struct.
  ///
  ///   domain: { name: "DepositWallet", version: "1", chainId,
  ///             verifyingContract: walletAddress }
  ///   Call(address target,uint256 value,bytes data)
  ///   Batch(address wallet,uint256 nonce,uint256 deadline,Call[] calls)
  ///
  /// Returns the 0x-prefixed 65-byte ECDSA signature (r||s||v).
  Future<String> _signDepositWalletBatch({
    required DepositWalletBatchSigner signer,
    required String walletAddress,
    required BigInt nonce,
    required BigInt deadline,
    required List<({String target, BigInt value, String data})> calls,
  }) async {
    final domainSep = _hashDepositWalletDomain(walletAddress: walletAddress);
    final batchStructHash = _hashBatchStruct(
      walletAddress: walletAddress,
      nonce: nonce,
      deadline: deadline,
      calls: calls,
    );

    // keccak256(0x1901 ++ domainSep ++ batchStructHash) is signed inside
    // signTypedDataHashes; an external signer also gets the full typed
    // data, checked equal to these hashes before any prompt.
    final sig = await signer.signBatch(
      domain: domainSep,
      message: batchStructHash,
      kind: depositWalletBatchKind(calls.map((c) => c.data)),
      typedData: () => depositWalletBatchTypedData(
        walletAddress: walletAddress,
        nonce: nonce,
        deadline: deadline,
        calls: calls,
      ),
    );
    final sigBytes = Uint8List(65);
    sigBytes.setRange(0, 32, _bigIntToBytes32(sig.r));
    sigBytes.setRange(32, 64, _bigIntToBytes32(sig.s));
    // Plain ECDSA v (27/28) — DepositWallet's isValidSignature uses
    // ecrecover directly. No Safe-style +4 adjustment.
    sigBytes[64] = sig.v;
    return '0x${_bytesToHex(sigBytes)}';
  }

  /// EIP-712 domain separator for the DepositWallet's Batch / Call typed
  /// data. Uses the FOUR-field domain (name/version/chainId/verifyingContract)
  /// per the reference impl — NOT the 3-field variant our `_hashDomain`
  /// helper uses for the legacy Safe CreateProxy. Mismatched domain
  /// fields → wrong domain separator → "invalid batch signature" on
  /// the relayer.
  Uint8List _hashDepositWalletDomain({required String walletAddress}) {
    final typeHash = _keccak256(Uint8List.fromList(utf8.encode(
      'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
    )));
    final nameHash = _keccak256(Uint8List.fromList(
        utf8.encode(PolymarketConstants.depositWalletDomainName)));
    final versionHash = _keccak256(Uint8List.fromList(
        utf8.encode(PolymarketConstants.depositWalletDomainVersion)));
    return _keccak256(Uint8List.fromList([
      ...typeHash,
      ...nameHash,
      ...versionHash,
      ..._bigIntToBytes32(BigInt.from(137)),
      ..._addressToBytes32(walletAddress),
    ]));
  }

  /// keccak256 of the EIP-712 typehash for `Call`. Used inside the
  /// Batch typehash and per-Call struct hashes.
  Uint8List get _callTypeHash {
    return _keccak256(Uint8List.fromList(utf8.encode(
      'Call(address target,uint256 value,bytes data)',
    )));
  }

  /// keccak256 of the EIP-712 typehash for `Batch` — includes the nested
  /// Call type definition, per EIP-712 rules for referenced types.
  Uint8List get _batchTypeHash {
    return _keccak256(Uint8List.fromList(utf8.encode(
      'Batch(address wallet,uint256 nonce,uint256 deadline,Call[] calls)'
      'Call(address target,uint256 value,bytes data)',
    )));
  }

  Uint8List _hashCallStruct({
    required String target,
    required BigInt value,
    required String data, // hex with or without 0x
  }) {
    final cleanData = data.startsWith('0x') ? data.substring(2) : data;
    final dataBytes = cleanData.isEmpty ? Uint8List(0) : _hexToBytes(cleanData);
    return _keccak256(Uint8List.fromList([
      ..._callTypeHash,
      ..._addressToBytes32(target),
      ..._bigIntToBytes32(value),
      // `bytes` field: keccak256 of the raw bytes (EIP-712 dynamic encoding).
      ..._keccak256(dataBytes),
    ]));
  }

  Uint8List _hashBatchStruct({
    required String walletAddress,
    required BigInt nonce,
    required BigInt deadline,
    required List<({String target, BigInt value, String data})> calls,
  }) {
    // Call[] dynamic field: keccak256 of the concatenated struct hashes.
    final callHashes = <int>[];
    for (final c in calls) {
      callHashes.addAll(_hashCallStruct(
        target: c.target,
        value: c.value,
        data: c.data,
      ));
    }
    final callsArrayHash = _keccak256(Uint8List.fromList(callHashes));

    return _keccak256(Uint8List.fromList([
      ..._batchTypeHash,
      ..._addressToBytes32(walletAddress),
      ..._bigIntToBytes32(nonce),
      ..._bigIntToBytes32(deadline),
      ...callsArrayHash,
    ]));
  }

  /// Deploy a V2 Deposit Wallet for [eoaAddress] via the relayer.
  ///
  /// Mirrors `RelayClient.deployDepositWallet()` in the official builder-
  /// relayer-client package: POST a `WALLET-CREATE` typed tx with
  /// `to = DepositWalletFactory`. The relayer figures out the rest from
  /// the `from` address (derived deterministically).
  ///
  /// No EIP-712 signature required for WALLET-CREATE — the factory uses
  /// `from` directly. Idempotent: a second call after deployment returns
  /// quickly because Polymarket's relayer dedups by sender.
  ///
  /// Returns the deployed wallet address. Use [deriveDepositWalletAddress]
  /// when you need the address without touching the relayer.
  Future<String> deployDepositWallet({
    required String eoaAddress,
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    final walletAddress = deriveDepositWalletAddress(eoaAddress);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET-CREATE: from=$eoaAddress '
          'wallet=$walletAddress factory=$_kDepositWalletFactory');
    }

    final txRequest = {
      'type': 'WALLET-CREATE',
      'from': eoaAddress,
      'to': _kDepositWalletFactory,
    };

    final String txId;
    try {
      txId = await _submit(txRequest, ensureCurrent: ensureCurrent);
    } catch (e) {
      // The relayer 400s a WALLET-CREATE for an already-deployed wallet
      // instead of returning a no-op, so the docstring's promised idempotency
      // isn't delivered by the server — we deliver it here. An already-deployed
      // wallet is exactly the success state this call is trying to reach, so
      // treat it as done rather than aborting the whole enable-trading flow
      // (which is what surfaced as the "wallet already deployed" 400 in the
      // relayer logs during a force:true re-deploy / eth_getCode race).
      if (e.toString().toLowerCase().contains('already deployed')) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[poly-relayer] WALLET-CREATE: $walletAddress already '
              'deployed — treating as success');
        }
        return walletAddress;
      }
      rethrow;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET-CREATE accepted, txId=$txId — polling…');
    }
    await _pollTransaction(txId);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] WALLET-CREATE confirmed for $walletAddress');
    }
    return walletAddress;
  }

  /// Submits a Safe transaction and returns the on-chain transaction hash.
  ///
  /// Heavy logging on the debug path so a stuck claim can be
  /// diagnosed from logcat alone — every step (sign / submit /
  /// poll) prints what it sent and what came back.
  Future<String> submitSafeTx({
    required String eoaAddress,
    required String privateKey,
    required String safeAddress,
    required String to,
    required String data, // hex without 0x prefix
  }) async {
    final credentials = _hotCredentials(privateKey);
    final nonce = await _getSafeNonce(safeAddress);

    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] safe-tx prep: to=$to nonce=$nonce '
          'safeAddress=$safeAddress dataLen=${data.length}');
    }

    final signature = await _signSafeTx(
      credentials: credentials,
      safeAddress: safeAddress,
      to: to,
      data: data,
      nonce: nonce,
    );

    final txRequest = {
      'type': 'SAFE',
      'from': eoaAddress,
      'to': to,
      'proxyWallet': safeAddress,
      'data': '0x$data',
      'value': '0',
      'nonce': nonce.toString(),
      'signature': signature,
      'signatureParams': {
        'gasPrice': '0',
        'operation': '0',
        'safeTxnGas': '0',
        'baseGas': '0',
        'gasToken': _kZeroAddress,
        'refundReceiver': _kZeroAddress,
      },
    };

    String txId;
    try {
      txId = await _submit(txRequest);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[poly-relayer] _submit threw: $e');
      }
      rethrow;
    }
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] relayer accepted, txId=$txId — polling…');
    }
    final hash = await _pollTransaction(txId);
    if (kDebugMode) {
      // ignore: avoid_print
      print('[poly-relayer] poll returned hash=$hash for txId=$txId');
    }
    return hash;
  }

  Future<String> _signCreateProxy(EthPrivateKey credentials) async {
    final domainSeparator = _hashDomain(
      name: 'Polymarket Contract Proxy Factory',
      chainId: 137,
      verifyingContract: _kSafeFactory,
    );

    final structHash = _hashCreateProxyStruct(
      paymentToken: _kZeroAddress,
      payment: BigInt.zero,
      paymentReceiver: _kZeroAddress,
    );

    final digest = _keccak256(Uint8List.fromList([
      0x19,
      0x01,
      ...domainSeparator,
      ...structHash,
    ]));

    final sig = await credentials.signToSignature(digest);
    return sig.toHex();
  }

  Uint8List _hashDomain({
    required String name,
    required int chainId,
    required String verifyingContract,
  }) {
    final typeHash = _keccak256(Uint8List.fromList(utf8.encode(
      'EIP712Domain(string name,uint256 chainId,address verifyingContract)',
    )));
    final nameHash = _keccak256(Uint8List.fromList(utf8.encode(name)));
    final chainIdBytes = _bigIntToBytes32(BigInt.from(chainId));
    final contractBytes = _addressToBytes32(verifyingContract);

    return _keccak256(Uint8List.fromList([
      ...typeHash,
      ...nameHash,
      ...chainIdBytes,
      ...contractBytes,
    ]));
  }

  Uint8List _hashCreateProxyStruct({
    required String paymentToken,
    required BigInt payment,
    required String paymentReceiver,
  }) {
    final typeHash = _keccak256(Uint8List.fromList(utf8.encode(
      'CreateProxy(address paymentToken,uint256 payment,address paymentReceiver)',
    )));
    return _keccak256(Uint8List.fromList([
      ...typeHash,
      ..._addressToBytes32(paymentToken),
      ..._bigIntToBytes32(payment),
      ..._addressToBytes32(paymentReceiver),
    ]));
  }

  Future<String> _signSafeTx({
    required EthPrivateKey credentials,
    required String safeAddress,
    required String to,
    required String data, // hex without 0x prefix
    required int nonce,
  }) async {
    final domainSeparator = _hashSafeDomain(safeAddress);
    final structHash = _hashSafeTxStruct(
      to: to,
      value: BigInt.zero,
      data: _hexToBytes(data),
      operation: 0,
      safeTxGas: BigInt.zero,
      baseGas: BigInt.zero,
      gasPrice: BigInt.zero,
      gasToken: _kZeroAddress,
      refundReceiver: _kZeroAddress,
      nonce: BigInt.from(nonce),
    );

    final eip712Hash = _keccak256(Uint8List.fromList([
      0x19,
      0x01,
      ...domainSeparator,
      ...structHash,
    ]));

    final prefix = Uint8List.fromList([
      0x19,
      ...utf8.encode('Ethereum Signed Message:\n32'),
    ]);
    final ethSignDigest = _keccak256(Uint8List.fromList([
      ...prefix,
      ...eip712Hash,
    ]));

    final sig = await credentials.signToSignature(ethSignDigest);

    final adjustedV = sig.v + 4;
    final sigBytes = Uint8List(65);
    sigBytes.setRange(0, 32, _bigIntToBytes32(sig.r));
    sigBytes.setRange(32, 64, _bigIntToBytes32(sig.s));
    sigBytes[64] = adjustedV;

    return '0x${_bytesToHex(sigBytes)}';
  }

  Uint8List _hashSafeDomain(String safeAddress) {
    final typeHash = _keccak256(Uint8List.fromList(utf8.encode(
      'EIP712Domain(uint256 chainId,address verifyingContract)',
    )));
    return _keccak256(Uint8List.fromList([
      ...typeHash,
      ..._bigIntToBytes32(BigInt.from(137)),
      ..._addressToBytes32(safeAddress),
    ]));
  }

  Uint8List _hashSafeTxStruct({
    required String to,
    required BigInt value,
    required Uint8List data,
    required int operation,
    required BigInt safeTxGas,
    required BigInt baseGas,
    required BigInt gasPrice,
    required String gasToken,
    required String refundReceiver,
    required BigInt nonce,
  }) {
    final typeHash = _keccak256(Uint8List.fromList(utf8.encode(
      'SafeTx(address to,uint256 value,bytes data,uint8 operation,'
      'uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,'
      'address gasToken,address refundReceiver,uint256 nonce)',
    )));

    final dataHash = _keccak256(data);

    return _keccak256(Uint8List.fromList([
      ...typeHash,
      ..._addressToBytes32(to),
      ..._bigIntToBytes32(value),
      ...dataHash,
      ..._bigIntToBytes32(BigInt.from(operation)),
      ..._bigIntToBytes32(safeTxGas),
      ..._bigIntToBytes32(baseGas),
      ..._bigIntToBytes32(gasPrice),
      ..._addressToBytes32(gasToken),
      ..._addressToBytes32(refundReceiver),
      ..._bigIntToBytes32(nonce),
    ]));
  }

  String _encodeApprove(String spender) {
    return '095ea7b3'
        '${_addressToHex32(spender)}'
        '$_kMaxUint256Hex';
  }

  String _encodeSetApprovalForAll(String operator) {
    return 'a22cb465'
        '${_addressToHex32(operator)}'
        '${_bytesToHex(_bigIntToBytes32(BigInt.one))}';
  }

  String _encodeAllowanceCall(String owner, String spender) {
    return 'dd62ed3e'
        '${_addressToHex32(owner)}'
        '${_addressToHex32(spender)}';
  }

  String _encodeIsApprovedForAllCall(String owner, String operator) {
    return 'e985e9c5'
        '${_addressToHex32(owner)}'
        '${_addressToHex32(operator)}';
  }

  String _encodeBalanceOfCall(String owner) {
    return '70a08231${_addressToHex32(owner)}';
  }

  /// CollateralOnramp.wrap(address asset, address to, uint256 amount)
  String _encodeWrap(String asset, String to, BigInt amount) {
    return '62355638'
        '${_addressToHex32(asset)}'
        '${_addressToHex32(to)}'
        '${_bytesToHex(_bigIntToBytes32(amount))}';
  }

  /// CollateralOfframp.unwrap(address asset, address to, uint256 amount)
  String _encodeUnwrap(String asset, String to, BigInt amount) {
    return '8cc7104f'
        '${_addressToHex32(asset)}'
        '${_addressToHex32(to)}'
        '${_bytesToHex(_bigIntToBytes32(amount))}';
  }

  String _addressToHex32(String address) {
    return address.replaceFirst('0x', '').padLeft(64, '0');
  }

  /// Read an ERC-20 balance for [owner] on [token]. Returns 0 on RPC failure.
  Future<BigInt> readErc20Balance({
    required String token,
    required String owner,
  }) async {
    try {
      final hex = await _ethCall(token, _encodeBalanceOfCall(owner));
      return _decodeUint256(hex);
    } catch (_) {
      return BigInt.zero;
    }
  }

  /// Read ERC-1155 outcome-token balances held by [owner] for a
  /// Neg Risk market. Returns `(yesBalance, noBalance)` in 6-decimal
  /// base units. Positions live on the **CTF** contract (the
  /// NegRiskAdapter just proxies `balanceOf` to it) so we query CTF
  /// directly.
  ///
  /// Position IDs come from the Polymarket Data API — passed in here
  /// as decimal `uint256` strings from `Position.asset` (the slot the
  /// user holds) and `Position.oppositeAsset` (the other slot). DO
  /// NOT re-derive them in Dart: the real derivation is
  ///   keccak256(wcol_address, getCollectionId(0, conditionId, indexSet))
  /// where `getCollectionId` is an elliptic-curve compressed-point
  /// hash from `CTHelpers.sol` — not a plain `keccak`. The previous
  /// in-Dart `_negRiskPositionId` computed `keccak(conditionId, outcome)`
  /// which doesn't correspond to any real on-chain id, and every
  /// `balanceOf(owner, garbage_id)` call returned (correctly) zero —
  /// silently triggering the "BOTH contracts precheck-empty →
  /// permanent suppress" branch even for positions the user
  /// demonstrably held.
  ///
  /// Batch ERC-1155 `balanceOfBatch(address[] owners, uint256[] ids)`
  /// against CTF. Returns balances in the same order as [positionIds].
  ///
  /// Used by the trading provider's on-chain claimable scanner to
  /// override `redeemable=false` flags from the Polymarket Data API
  /// when the user demonstrably still holds outcome tokens.
  /// Without this, positions the user previously tried (and failed)
  /// to claim via the legacy adapter never re-appear in the Claim
  /// rail — the Data API treats them as "done" even though the
  /// underlying outcome tokens are still on the Safe.
  ///
  /// Returns `{}` on RPC failure (callers fall back to API trust).
  ///
  /// Protocol V2 position ids are read from the PositionManager instead
  /// (their shares never sit on CTF); a mixed list is split by protocol.
  Future<Map<String, BigInt>> readCtfBalancesBatch({
    required List<String> positionIds,
    required String owner,
  }) async {
    if (positionIds.isEmpty) return const {};
    final v2 = positionIds.where(PolyMarketProtocol.isV2PositionId).toList();
    if (v2.isNotEmpty) {
      final ctf = positionIds
          .where((id) => !PolyMarketProtocol.isV2PositionId(id))
          .toList();
      final reads = await Future.wait([
        _balanceOfBatchSoft(
            PolymarketConstants.comboPositionManagerAddress, v2, owner),
        ctf.isEmpty
            ? Future.value(const <String, BigInt>{})
            : readCtfBalancesBatch(positionIds: ctf, owner: owner),
      ]);
      // One failed half reads as a failed read, as a single batch does.
      if (reads[0].isEmpty || (ctf.isNotEmpty && reads[1].isEmpty)) {
        return const {};
      }
      return {...reads[1], ...reads[0]};
    }
    return _balanceOfBatchSoft(_kCtfAddress, positionIds, owner);
  }

  /// ERC-1155 `balanceOfBatch` on [token]; `{}` on any failure.
  Future<Map<String, BigInt>> _balanceOfBatchSoft(
      String token, List<String> positionIds, String owner) async {
    try {
      // ERC-1155.balanceOfBatch(address[] _owners, uint256[] _ids)
      // selector: 0x4e1273f4
      // Encoding (post-selector):
      //   [0x00..0x20) offset to owners array (= 0x40)
      //   [0x20..0x40) offset to ids array    (= 0x40 + 32 + 32*n)
      //   [0x40..0x60) owners.length          (= n)
      //   [0x60..]     owners[0..n-1]         (each 32 bytes)
      //   [...]        ids.length             (= n)
      //   [...]        ids[0..n-1]            (each 32 bytes)
      String hexId(String decimalUint) {
        final v = BigInt.tryParse(decimalUint) ?? BigInt.zero;
        return v.toRadixString(16).padLeft(64, '0');
      }

      final n = positionIds.length;
      final ownersOffset = BigInt.from(64).toRadixString(16).padLeft(64, '0');
      final idsOffset =
          BigInt.from(64 + 32 + 32 * n).toRadixString(16).padLeft(64, '0');
      final ownersLen = BigInt.from(n).toRadixString(16).padLeft(64, '0');
      final ownersData = List.filled(n, _addressToHex32(owner)).join();
      final idsLen = BigInt.from(n).toRadixString(16).padLeft(64, '0');
      final idsData = positionIds.map(hexId).join();
      final data = '4e1273f4'
          '$ownersOffset'
          '$idsOffset'
          '$ownersLen'
          '$ownersData'
          '$idsLen'
          '$idsData';
      final hex = await _ethCall(token, data);
      // Response: uint256[] — abi-encoded:
      //   [0x00..0x20) tail offset (= 0x20)
      //   [0x20..0x40) length
      //   [0x40..]     elements
      if (hex.length < 128) return const {};
      final lenHex = hex.substring(64, 128);
      final len = BigInt.tryParse(lenHex, radix: 16)?.toInt() ?? 0;
      if (len != n) return const {};
      final result = <String, BigInt>{};
      for (var i = 0; i < n; i++) {
        final start = 128 + i * 64;
        final end = start + 64;
        if (end > hex.length) break;
        final bal = BigInt.tryParse(hex.substring(start, end), radix: 16) ??
            BigInt.zero;
        result[positionIds[i]] = bal;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  // ── Strict read variants (Wallet hardening Phase 3, P3.7) ─────────────
  // Next to the fail-soft reads above, which hot callers keep using. These
  // THROW [PolymarketReadException] on any RPC failure or empty result so
  // the Ledger account providers never render a failed read as zero.

  /// An unreadable allowance must never trigger a replacement approval.
  Future<BigInt> readApprovalOrThrow({
    required String token,
    required String owner,
    required String spender,
    bool operatorApproval = false,
  }) async {
    final hex = await _ethCallStrict(
        token,
        operatorApproval
            ? _encodeIsApprovedForAllCall(owner, spender)
            : _encodeAllowanceCall(owner, spender));
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const PolymarketReadException('Approval returned no uint256');
    }
    final value = BigInt.parse(hex, radix: 16);
    if (operatorApproval && value != BigInt.zero && value != BigInt.one) {
      throw const PolymarketReadException('Approval returned no boolean');
    }
    return value;
  }

  /// ERC-20 balance, throwing on RPC failure.
  Future<BigInt> readErc20BalanceOrThrow({
    required String token,
    required String owner,
  }) async {
    final hex = await _ethCallStrict(token, _encodeBalanceOfCall(owner));
    if (hex.length != 64) {
      throw const PolymarketReadException('balanceOf returned no uint256');
    }
    return BigInt.parse(hex, radix: 16);
  }

  /// Native POL balance of [owner] in wei, throwing on RPC failure or a
  /// malformed answer.
  Future<BigInt> readNativeBalanceOrThrow(String owner) =>
      _readQuantityOrThrow('eth_getBalance', owner);

  /// Transactions [owner] has sent on Polygon (its nonce), throwing on RPC
  /// failure or a malformed answer.
  Future<BigInt> readNonceOrThrow(String owner) =>
      _readQuantityOrThrow('eth_getTransactionCount', owner);

  Future<BigInt> _readQuantityOrThrow(String method, String owner) async {
    final result = await _rpcStrict(method, [owner, 'latest']);
    final value = BigInt.tryParse(result.substring(2), radix: 16);
    if (value == null) {
      throw PolymarketReadException('$method returned no quantity');
    }
    return value;
  }

  /// ERC-1155 `balanceOfBatch` on CTF, throwing on RPC failure or a
  /// malformed response.
  Future<Map<String, BigInt>> readCtfBalancesBatchOrThrow({
    required List<String> positionIds,
    required String owner,
  }) async {
    if (positionIds.isEmpty) return const {};
    final v2 = positionIds.where(PolyMarketProtocol.isV2PositionId).toList();
    if (v2.isNotEmpty) {
      final ctf = positionIds
          .where((id) => !PolyMarketProtocol.isV2PositionId(id))
          .toList();
      return {
        if (ctf.isNotEmpty)
          ...await readCtfBalancesBatchOrThrow(positionIds: ctf, owner: owner),
        ...await _balanceOfBatchStrict(
            PolymarketConstants.comboPositionManagerAddress, v2, owner),
      };
    }
    return _balanceOfBatchStrict(_kCtfAddress, positionIds, owner);
  }

  Future<Map<String, BigInt>> _balanceOfBatchStrict(
      String token, List<String> positionIds, String owner) async {
    final n = positionIds.length;
    String word(BigInt v) => v.toRadixString(16).padLeft(64, '0');
    final ids = positionIds.map((id) {
      final v = BigInt.tryParse(id);
      if (v == null || v.isNegative) {
        throw ArgumentError('positionIds must be decimal uint256 strings');
      }
      return word(v);
    }).join();
    final data = '4e1273f4'
        '${word(BigInt.from(64))}'
        '${word(BigInt.from(64 + 32 + 32 * n))}'
        '${word(BigInt.from(n))}'
        '${List.filled(n, _addressToHex32(owner)).join()}'
        '${word(BigInt.from(n))}'
        '$ids';
    final hex = await _ethCallStrict(token, data);
    if (hex.length != 128 + 64 * n ||
        BigInt.parse(hex.substring(64, 128), radix: 16) != BigInt.from(n)) {
      throw const PolymarketReadException('balanceOfBatch shape mismatch');
    }
    return {
      for (var i = 0; i < n; i++)
        positionIds[i]:
            BigInt.parse(hex.substring(128 + 64 * i, 192 + 64 * i), radix: 16),
    };
  }

  /// True when [address] has contract code; throws on RPC failure.
  Future<bool> hasContractCodeOrThrow(String address) async {
    final code = await _rpcStrict('eth_getCode', [address, 'latest']);
    return code.length > 2;
  }

  /// The factory's current deposit wallet for [eoaAddress]; throws on RPC
  /// failure instead of returning a malformed address.
  Future<String> predictDepositWalletOrThrow(String eoaAddress) async {
    final id =
        '000000000000000000000000${eoaAddress.substring(2).toLowerCase()}';
    final hex = await _ethCallStrict(_kDepositWalletFactory, '04f1d3c7$id');
    if (hex.length != 64) {
      throw const PolymarketReadException('predictWalletAddress: no address');
    }
    return _toChecksumAddress('0x${hex.substring(24)}');
  }

  /// The legacy Safe for [eoaAddress]; throws on RPC failure.
  Future<String> deriveSafeAddressOrThrow(String eoaAddress) async {
    final hex = await _ethCallStrict(
        _kSafeFactory, 'd600539a${_addressToHex32(eoaAddress)}');
    if (hex.length != 64) {
      throw const PolymarketReadException('computeProxyAddress: no address');
    }
    return _toChecksumAddress('0x${hex.substring(24)}');
  }

  /// Relayer registry check for a WALLET address. Null when the relayer
  /// could not be read (unknown, not "undeployed"). `type=WALLET` on
  /// `/deployed` is undocumented and has no documented replacement, so a
  /// refusal reads as unknown.
  Future<bool?> relayerWalletDeployed(String address) async {
    try {
      final uri = Uri.parse('$_kPmRelayerBaseUrl/deployed').replace(
        queryParameters: {'address': address, 'type': 'WALLET'},
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map || decoded['deployed'] is! bool) return null;
      return decoded['deployed'] as bool;
    } catch (_) {
      return null;
    }
  }

  /// One read of a relayer transaction: the upper-case state and the
  /// on-chain hash when known. Null when the relayer could not be read.
  /// Used by Ledger reconciliation; never resubmits.
  Future<({String state, String? hash})?> relayerTransactionState(
      String txId) async {
    try {
      final uri = Uri.parse('$_kPmRelayerBaseUrl/transaction')
          .replace(queryParameters: {'id': txId});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final parsed = relayerTransactionForId(jsonDecode(response.body), txId);
      if (parsed == null) return null;
      final state =
          (parsed['state'] ?? parsed['status'] ?? '').toString().toUpperCase();
      final hash =
          (parsed['transactionHash'] ?? parsed['txHash'] ?? parsed['hash'])
              ?.toString();
      return (state: state, hash: hash == null || hash.isEmpty ? null : hash);
    } catch (_) {
      return null;
    }
  }

  Future<String> _ethCallStrict(String to, String data) async {
    final result = await _rpcStrict('eth_call', [
      {'to': to, 'data': '0x$data'},
      'latest',
    ]);
    return result.substring(2);
  }

  Future<String> _rpcStrict(String method, List<Object> params) async {
    final result = await _rpcFirstAnswer(method, params);
    if (!result.startsWith('0x')) {
      throw PolymarketReadException('$method returned no result');
    }
    return result;
  }

  /// Returns `(BigInt.zero, BigInt.zero)` on RPC failure.
  Future<(BigInt, BigInt)> readNegRiskOutcomeBalances({
    required String yesPositionId,
    required String noPositionId,
    required String owner,
  }) async {
    try {
      // ERC-1155 balanceOf selector = 0x00fdd58e
      String hexId(String decimalUint) {
        final n = BigInt.tryParse(decimalUint) ?? BigInt.zero;
        return n.toRadixString(16).padLeft(64, '0');
      }

      String encodeCall(String idHex) =>
          '00fdd58e${_addressToHex32(owner)}$idHex';
      final results = await Future.wait([
        _ethCall(_kCtfAddress, encodeCall(hexId(yesPositionId))),
        _ethCall(_kCtfAddress, encodeCall(hexId(noPositionId))),
      ]);
      return (_decodeUint256(results[0]), _decodeUint256(results[1]));
    } catch (_) {
      return (BigInt.zero, BigInt.zero);
    }
  }

  /// Ensure the Safe holds at least [minPusd] of pUSD by wrapping from
  /// USDC.e via the CollateralOnramp. USDC.e is the canonical at-rest
  /// token in this wallet — predictions and convert flows rely on the
  /// instant 1:1 wrap (no Uniswap, no slippage, no async swap).
  ///
  /// Native USDC that occasionally lands in the Safe (e.g. an external
  /// exchange send picked the wrong token) is *not* consulted here —
  /// it gets normalized to USDC.e by the background trickle sweep on
  /// the next refresh tick, then becomes available for the next
  /// prediction.
  ///
  /// Throws [InsufficientFundsException] (token = "USDC.e") if pUSD +
  /// USDC.e still falls short. The caller's overlay routes that to the
  /// BTC top-up flow via Orchestra.
  ///
  /// All amounts in 6-decimal base units (micro-USD).
  Future<void> ensurePusdBalance({
    required String eoaAddress,
    required String privateKey,
    required String safeAddress,
    required BigInt minPusd,
  }) async {
    final pusd = await readErc20Balance(
      token: PolymarketConstants.pusdAddress,
      owner: safeAddress,
    );
    if (pusd >= minPusd) return;

    final deficit = minPusd - pusd;
    final usdce = await readErc20Balance(
      token: PolymarketConstants.usdcEAddress,
      owner: safeAddress,
    );
    if (usdce < deficit) {
      throw InsufficientFundsException(
        needed: deficit,
        have: usdce,
        token: 'USDC.e',
      );
    }

    // Wrap the deficit USDC.e → pUSD.
    //
    // Self-heal the USDC.e → Onramp approval before the wrap. Same
    // silent-revert risk as the Uniswap leg: the relayer can return
    // CONFIRMED while the inner `wrap()` reverts because the Safe
    // hasn't approved Onramp to pull USDC.e. fixMissingApprovals is
    // idempotent so the cost is just a handful of allowance reads
    // when everything is already set.
    await fixMissingApprovals(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      safeAddress: safeAddress,
    );
    final data = _encodeWrap(
      PolymarketConstants.usdcEAddress,
      safeAddress,
      deficit,
    );
    final wrapTxHash = await submitSafeTx(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      safeAddress: safeAddress,
      to: PolymarketConstants.collateralOnrampAddress,
      data: data,
    );
    final wrapOk = await verifyReceipt(wrapTxHash);
    if (!wrapOk) {
      throw Exception(
        'Wrap to pUSD reverted on-chain. Try again in a moment.',
      );
    }
    // No post-wrap balance read: the receipt-verify above already
    // confirms the wrap mined successfully on-chain. A balance read
    // here races the RPC indexer (the public node can lag the
    // chain state by a couple of seconds), and a stale 0 here
    // would falsely fail an order that's actually fundable. The
    // CLOB will use its own subscription to see the new pUSD.
  }

  /// Unwrap [amount] of pUSD back to USDC.e in the Safe (gasless via relayer).
  /// Used after position resolution to sweep dust back toward USDC.e (which
  /// then gets swapped to BTC via Orchestra in a separate step).
  Future<void> unwrapPusd({
    required String eoaAddress,
    required String privateKey,
    required String safeAddress,
    required BigInt amount,
  }) async {
    if (amount <= BigInt.zero) return;
    final data = _encodeUnwrap(
      PolymarketConstants.usdcEAddress,
      safeAddress,
      amount,
    );
    await submitSafeTx(
      eoaAddress: eoaAddress,
      privateKey: privateKey,
      safeAddress: safeAddress,
      to: PolymarketConstants.collateralOfframpAddress,
      data: data,
    );
  }

  /// Poll the Polygon RPC for a transaction receipt and return whether
  /// the tx actually succeeded on-chain. Critical for redeem/claim flows:
  /// our relayer sometimes reports a tx as CONFIRMED while the underlying
  /// contract call reverted (mined-but-reverted), which would otherwise
  /// let the UI show "Claimed" for a tx that did nothing.
  ///
  /// Returns true if `status == 0x1`. Returns false if the receipt shows
  /// a failed status (mined-but-reverted) OR — when [strict] is set —
  /// if the relayer handed us an opaque id instead of a hash, or the
  /// receipt fetch times out.
  ///
  /// [strict] should be `true` for any flow where a silent success-
  /// without-effect costs the user real money (claim/redeem above
  /// all). For idempotent / retryable flows (approvals, wraps), the
  /// old "trust the relayer on infra quirks" default is still safer
  /// — those can be retried cheaply on the next tick if they didn't
  /// actually land.
  ///
  /// Throws on no-network outright when [strict] is true; otherwise
  /// degrades to the legacy true-on-timeout behaviour.
  Future<bool> verifyReceipt(
    String txHash, {
    Duration timeout = const Duration(seconds: 60),
    bool strict = false,
  }) async {
    if (txHash.isEmpty || !txHash.startsWith('0x') || txHash.length != 66) {
      if (strict) {
        // Opaque relayer id or malformed hash. For claims, this is
        // the silent-failure path we MUST surface — better a clear
        // error the user can act on (retry) than "Claimed!" with no
        // money credited.
        throw Exception(
          'Relayer did not return a valid transaction hash. The claim could not be verified. '
          'Please try again in a moment.',
        );
      }
      // Legacy non-strict behaviour preserved for non-claim flows
      // (approvals, wraps) where retry is cheap.
      return true;
    }
    final deadline = DateTime.now().add(timeout);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      // Rotate endpoints so one stalled public RPC can't use up the wait.
      // Only endpoints that answered Polygon's chain id are trusted with a
      // receipt (it decides claim credit).
      final rpc = polygonReadRpcs[attempt++ % polygonReadRpcs.length];
      if (await _isPolygonRpc(rpc)) {
        final result = (await _rpcRequest(
                rpc, 'eth_getTransactionReceipt', [txHash],
                timeout: const Duration(seconds: 10)))
            ?.result;
        if (result is Map<String, dynamic>) {
          final status = (result['status'] as String?)?.toLowerCase() ?? '';
          // status is hex: 0x1 = success, 0x0 = reverted
          final success = status == '0x1' || status == '0x01';
          if (success) _verifiedReceipts[txHash.toLowerCase()] = result;
          return success;
        }
        // Receipt not yet available or RPC blip — retry until deadline.
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    if (strict) {
      throw Exception(
        'Could not confirm the claim transaction on-chain within ${timeout.inSeconds}s. '
        'The transaction may still settle. Check Polygonscan for $txHash before retrying.',
      );
    }
    // Couldn't fetch a receipt in time. Don't throw — let the caller
    // decide based on the relayer's earlier signal.
    return true;
  }

  static final Map<String, double> _settlementCache = {};

  /// Exact finalized payout per share. Null means unresolved or unavailable;
  /// zero is a verified losing outcome. Never infer settlement from price.
  static final Map<String, DateTime> _settlementChecked = {};
  static final Map<String, Future<double?>> _settlementPending = {};

  Future<double?> settledPayout(String conditionId, int outcomeIndex) async {
    final key = '${conditionId.toLowerCase()}:$outcomeIndex';
    if (_settlementCache.containsKey(key)) return _settlementCache[key];
    final pending = _settlementPending[key];
    if (pending != null) return pending;
    final checked = _settlementChecked[key];
    if (checked != null &&
        DateTime.now().difference(checked) < const Duration(seconds: 30)) {
      return null;
    }
    final request = _fetchSettledPayout(conditionId, outcomeIndex);
    _settlementPending[key] = request;
    try {
      return await request;
    } finally {
      _settlementPending.remove(key);
      _settlementChecked[key] = DateTime.now();
    }
  }

  Future<double?> _fetchSettledPayout(
      String conditionId, int outcomeIndex) async {
    final v2Condition = PolyMarketProtocol.v2ConditionId(conditionId);
    if (v2Condition != null) {
      if (outcomeIndex < 0 || outcomeIndex > 1) return null;
      final payouts = await readV2Payouts(v2Condition);
      if (payouts == null) return null;
      return _settlementCache['${conditionId.toLowerCase()}:$outcomeIndex'] =
          payouts[outcomeIndex];
    }
    if (!RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(conditionId) ||
        outcomeIndex < 0 ||
        outcomeIndex > 1) {
      return null;
    }
    final key = '${conditionId.toLowerCase()}:$outcomeIndex';
    if (_settlementCache.containsKey(key)) return _settlementCache[key];
    try {
      final backend = dotenv.env['BACKEND'] ?? '';
      if (backend.isNotEmpty) {
        final response = await http
            .get(Uri.parse(
                '$backend/api/v1/pm/settlement/$conditionId?outcome=$outcomeIndex'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['finalized'] == false) return null;
          final denominator = BigInt.tryParse('${data['denominator']}');
          final numerator = BigInt.tryParse('${data['numerator']}');
          if (data['finalized'] == true &&
              denominator != null &&
              numerator != null &&
              denominator > BigInt.zero &&
              numerator >= BigInt.zero &&
              numerator <= denominator) {
            return _settlementCache[key] =
                numerator.toDouble() / denominator.toDouble();
          }
        }
      }
    } catch (_) {/* Public RPC fallback also supports backend rollout lag. */}
    try {
      final condition = conditionId.substring(2);
      final denominator =
          _decodeUint256(await _ethCall(_kCtfAddress, 'dd34de67$condition'));
      if (denominator == BigInt.zero) return null;
      final hash = KeccakDigest(256).process(
          Uint8List.fromList(utf8.encode('payoutNumerators(bytes32,uint256)')));
      final selector =
          hash.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final numerator = _decodeUint256(await _ethCall(_kCtfAddress,
          '$selector$condition${outcomeIndex.toRadixString(16).padLeft(64, '0')}'));
      if (numerator < BigInt.zero || numerator > denominator) return null;
      return _settlementCache[key] =
          numerator.toDouble() / denominator.toDouble();
    } catch (_) {
      return null;
    }
  }

  /// Whether a condition's oracle result has been reported on-chain.
  /// CTF sets `payoutDenominator(conditionId) > 0` the moment
  /// `reportPayouts` lands — before that, ANY redeem (either adapter
  /// or the CTF directly) reverts/no-ops even though the Data API may
  /// already flag the position `redeemable`. That gap is the "my
  /// winning bet won't claim" report: the market UI says resolved but
  /// the oracle result hasn't finalised on Polygon yet.
  ///
  /// Returns:
  ///   * `true`  — payouts reported; a redeem can succeed.
  ///   * `false` — not finalised yet; a redeem WILL fail. Don't submit.
  ///   * `null`  — RPC failure; caller should proceed on API trust
  ///     rather than blocking a legitimate claim on a network blip.
  ///
  /// A Protocol V2 condition is final once the PositionManager pays out on
  /// it; an unreadable payout is `null` (never blocks a claim).
  Future<bool?> isConditionFinalized(String conditionId) async {
    final v2Condition = PolyMarketProtocol.v2ConditionId(conditionId);
    if (v2Condition != null) {
      return await readV2Payouts(v2Condition) != null ? true : null;
    }
    try {
      final cleanCondition =
          conditionId.replaceFirst('0x', '').padLeft(64, '0');
      // payoutDenominator(bytes32) — selector 0xdd34de67.
      final hex = await _ethCall(_kCtfAddress, 'dd34de67$cleanCondition');
      return _decodeUint256(hex) > BigInt.zero;
    } catch (_) {
      return null;
    }
  }

  Future<String> _ethCall(String to, String data) async {
    // Same fallback endpoints as the wallet resolve: one overloaded public
    // RPC used to stall bet setup for its full timeout.
    final result = await _rpcFirstAnswer('eth_call', [
      {'to': to, 'data': '0x$data'},
      'latest',
    ]);
    return result.replaceFirst('0x', '');
  }

  /// Returns the contract bytecode at `address` (or `'0x'` when no
  /// contract exists yet). Used by [isDeployed] to confirm the Safe
  /// proxy has been created without leaning on any backend or
  /// third-party indexer.
  Future<String> _ethGetCode(String address) async {
    return _rpcFirstAnswer('eth_getCode', [address, 'latest']);
  }

  Future<int> _getSafeNonce(String safeAddress) async {
    final result = await _ethCall(safeAddress, 'affed0e0');
    return _decodeUint256(result).toInt();
  }

  BigInt _decodeUint256(String hex) {
    if (hex.isEmpty) return BigInt.zero;
    return BigInt.parse(hex, radix: 16);
  }

  bool _decodeBool(String hex) {
    if (hex.isEmpty) return false;
    return BigInt.parse(hex, radix: 16) > BigInt.zero;
  }

  @visibleForTesting
  Future<String> submitForTest(Map<String, dynamic> txRequest) =>
      _submit(txRequest);

  Future<String> _submit(
    Map<String, dynamic> txRequest, {
    void Function()? ensureCurrent,
  }) async {
    ensureCurrent?.call();
    final body = jsonEncode(txRequest);
    // The relay requires the wallet session. Without one this throws the
    // localized WalletSessionUnavailable and nothing is submitted.
    final response = await AffiliateService.sendWithSession('pm_relay', (auth) {
      ensureCurrent?.call();
      return http
          .post(
            Uri.parse('$_baseUrl/submit'),
            headers: {'Content-Type': 'application/json', ...auth},
            body: body,
          )
          .timeout(const Duration(seconds: 30));
    });

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Relayer submit failed: ${response.statusCode} ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final txId = data['transactionID'] ??
        data['id'] ??
        data['transactionId'] ??
        data['hash'];
    if (txId == null) {
      throw Exception(
        'No transaction ID in relayer response: ${response.body}',
      );
    }
    return txId.toString();
  }

  /// Polls until the relayer transaction is confirmed. Returns the on-chain tx hash.
  ///
  /// 90 s timeout. Polygon settlement under load can take 30–60 s; a
  /// shorter cutoff regularly false-fires "claim timed out" while
  /// the tx is still healthy. Terminal state failures (FAILED /
  /// SKIPPED) propagate immediately, so the timeout only kicks in
  /// when the relayer never reaches a definitive state.
  Future<String> _pollTransaction(String txId,
      {Duration timeout = const Duration(seconds: 90),
      bool requireConfirmed = false}) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      _PollTerminalException? terminal;
      try {
        // Direct call to Polymarket's relayer — the public GET
        // doesn't require HMAC auth. Was previously proxied through
        // `$BACKEND/api/v1/pm/relay/transaction`; the backend was
        // pure plumbing for this read-only endpoint (no attribution,
        // no transformation) so we cut the hop.
        final uri = Uri.parse('$_kPmRelayerBaseUrl/transaction')
            .replace(queryParameters: {'id': txId});
        final response =
            await http.get(uri).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = relayerTransactionForId(jsonDecode(response.body), txId);
          if (data == null) {
            // Malformed or unrelated history never resolves this operation.
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }

          final state =
              (data['state'] ?? data['status'] ?? '').toString().toUpperCase();

          final txHash =
              (data['transactionHash'] ?? data['txHash'] ?? data['hash'])
                      ?.toString() ??
                  '';

          final confirmed =
              const {'STATE_CONFIRMED', 'CONFIRMED', 'DONE'}.contains(state);
          if (confirmed || (!requireConfirmed && state.contains('MINED'))) {
            if (!requireConfirmed ||
                RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(txHash)) {
              return txHash.isNotEmpty ? txHash : txId;
            }
          }
          if (state.contains('FAILED') ||
              state.contains('INVALID') ||
              state.contains('ERROR') ||
              state.contains('SKIPPED')) {
            // State-based failure: relayer returned a terminal
            // status. We MUST surface this immediately — looping
            // until timeout buys nothing because the relayer's
            // state won't change. Wrap in a sentinel exception
            // type so the surrounding catch (which used to filter
            // by string match on the message) always rethrows.
            final errorMsg = data['errorMsg']?.toString() ?? '';
            String friendlyMsg;
            if (errorMsg.contains('execution reverted')) {
              friendlyMsg =
                  'Transaction reverted on-chain. The position may already be redeemed or not yet resolved.';
            } else if (errorMsg.contains('insufficient funds')) {
              friendlyMsg = 'Insufficient funds for transaction.';
            } else if (errorMsg.isNotEmpty) {
              final match = RegExp(r'err:(.+?)\]').firstMatch(errorMsg);
              friendlyMsg = match != null ? match.group(1)!.trim() : errorMsg;
            } else {
              friendlyMsg = 'Transaction failed. Please try again.';
            }
            terminal = _PollTerminalException(friendlyMsg);
            throw terminal;
          }
          if (!requireConfirmed && txHash.isNotEmpty) {
            return txHash;
          }
        }
      } catch (e) {
        // Only swallow non-terminal errors (HTTP blip, JSON decode
        // hiccup, transient connection issue). Terminal state
        // errors must propagate so the caller can branch on them
        // (e.g. retry redeem with the alternate collateral).
        if (e is _PollTerminalException) {
          rethrow;
        }
        if (terminal != null) {
          throw terminal;
        }
        // Legacy keyword check for older relayer payloads that
        // don't surface the state cleanly — keep so we don't
        // regress on edge cases.
        final s = e.toString();
        if (s.contains('FAILED') ||
            s.contains('INVALID') ||
            s.contains('ERROR')) {
          rethrow;
        }
      }

      await Future.delayed(const Duration(seconds: 3));
    }

    throw Exception('The relayer has not confirmed this transaction yet. '
        'It may still settle. Check its status before starting another transfer.');
  }

  Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceFirst('0x', '');
    if (clean.isEmpty) return Uint8List(0);
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  Uint8List _addressToBytes32(String address) {
    final clean = address.replaceFirst('0x', '').padLeft(64, '0');
    return _hexToBytes(clean);
  }

  Uint8List _bigIntToBytes32(BigInt value) {
    final bytes = Uint8List(32);
    var temp = value;
    for (var i = 31; i >= 0; i--) {
      bytes[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }
    return bytes;
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _keccak256(Uint8List data) {
    final digest = KeccakDigest(256);
    return digest.process(data);
  }

  String _toChecksumAddress(String address) {
    final clean = address.replaceFirst('0x', '').toLowerCase();
    final hash = _keccak256(Uint8List.fromList(clean.codeUnits));
    final hashHex = _bytesToHex(hash);

    final result = StringBuffer('0x');
    for (var i = 0; i < clean.length; i++) {
      final c = clean[i];
      if (c.codeUnitAt(0) >= 97 /* 'a' */ && c.codeUnitAt(0) <= 102 /* 'f' */) {
        final hashNibble = int.parse(hashHex[i], radix: 16);
        result.write(hashNibble >= 8 ? c.toUpperCase() : c);
      } else {
        result.write(c);
      }
    }
    return result.toString();
  }
}
