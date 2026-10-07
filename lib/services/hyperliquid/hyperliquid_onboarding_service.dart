import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/models/evm_derivation_version.dart';
// lib/services/hyperliquid/hyperliquid_onboarding_service.dart
//
// "Enable trading" for Hyperliquid — which, unlike Polymarket, needs
// NOTHING on-chain: no proxy deploy, no approvals. The exchange account
// simply IS the user's EOA (same m/44'/60'/0'/0/0 derivation Polymarket
// uses), and it springs into existence when the first deposit lands.
//
// Two responsibilities:
//   1. provisionHyperliquidAccount — derive the signing key from the
//      wallet mnemonic and mark HL enabled for this wallet in secure
//      storage. Pure local work; safe to call repeatedly.
//   2. ensureBuilderFeeApproved — one-time user-signed approval that lets
//      the builder the backend publishes (never an address built into the
//      app) attach its fee to the user's orders. Repeats when the
//      published builder rotates. The
//      exchange's `maxBuilderFee` query is the source of truth (never
//      just the local flag). MUST run after the first deposit lands: an
//      unfunded account can't post user-signed actions.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

class HyperliquidOnboardingService {
  HyperliquidOnboardingService._();

  static String _enabledKey(String walletId) => 'hl_enabled_$walletId';
  static String _builderApprovedKey(String walletId) =>
      'hl_builder_approved_$walletId';

  /// Derives the Hyperliquid signer (index 0 — the same EOA as
  /// Polymarket's) and persists the enabled flag. The private key is
  /// returned to the caller and NEVER written to storage by this service —
  /// it is re-derivable from the mnemonic on demand.
  static Future<({EthPrivateKey credentials, String address})>
      provisionHyperliquidAccount({
    required String mnemonic,
    required String walletId,
    required EvmDerivationVersion evmDerivationVersion,
  }) async {
    LedgerOperationScope.assertHotAllowed(
        HotSigningAction.hyperliquidHotCredentials);
    final wallet = EvmWalletDerivation.deriveWallet(
        mnemonic: mnemonic, version: evmDerivationVersion, index: 0);
    final credentials = EthPrivateKey.fromHex(wallet.privateKey);
    await markEnabled(walletId);
    return (credentials: credentials, address: wallet.address);
  }

  /// Enables native balance polling after a deposit is created, without
  /// deriving or retaining a trading key. Also used for external onramps.
  static Future<void> markEnabled(String walletId) async {
    if (walletId.isEmpty) return;
    try {
      await secureStorage.write(key: _enabledKey(walletId), value: 'true');
    } catch (_) {
      // Balance polling while an Investing surface is open still works.
    }
  }

  /// True when this wallet has been provisioned for Hyperliquid.
  static Future<bool> isEnabled(String walletId) async {
    try {
      return await secureStorage.read(key: _enabledKey(walletId)) == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Makes sure the wallet has approved the builder the backend currently
  /// publishes, at the fee orders will carry.
  ///
  /// An approval already on the exchange for that address is reused. A new
  /// one is signed only for [reviewed]: the exact settings the caller is
  /// about to attach to its order. If they no longer match what the
  /// backend publishes, nothing is signed, so an approval and the orders
  /// it covers can never name different builders. A rotated builder is
  /// simply a builder this wallet has not approved yet, so it goes through
  /// this same first-time path. No builder published means nothing to
  /// approve.
  static Future<bool> ensureBuilderFeeApproved({
    required HyperliquidExchangeService exchange,
    required String walletAddress,
    required String walletId,
    HlBuilderInfo? reviewed,
  }) async {
    try {
      final builder = await HyperliquidFundingService.getBuilder();
      if (builder == null) return true; // none published — sign nothing

      final current = await _currentMaxBuilderFee(
        user: walletAddress,
        builder: builder.builderAddress,
      );
      if (current != null && current >= builder.defaultFeeTenthsBp) {
        await _persistApproved(walletId, builder, current);
        lastFailure = null;
        return true;
      }

      final matchesReviewed = reviewed != null &&
          reviewed.builderAddress.toLowerCase() ==
              builder.builderAddress.toLowerCase() &&
          reviewed.maxFeeRate == builder.maxFeeRate &&
          reviewed.defaultFeeTenthsBp == builder.defaultFeeTenthsBp;
      if (!matchesReviewed) {
        lastFailure = 'out_of_scope';
        return false;
      }
      final cap =
          HyperliquidFundingService.builderFeeCapTenthsBp(builder.maxFeeRate)!;
      await exchange.approveBuilderFee(
        builder: builder.builderAddress,
        maxFeeRate: builder.maxFeeRate,
      );
      await _persistApproved(walletId, builder, cap);
      lastFailure = null;
      return true;
    } catch (e) {
      // Keep WHY. This used to swallow the exception and answer a bare
      // false, so an order that died on "approve the trading fee" gave
      // no way to find out what the venue had actually said: an
      // unfunded account, a rejected signature and a dead network all
      // looked identical from the outside, including in the logs.
      lastFailure = e.toString();
      TrackingService.track('hl_builder_fee_approval_failed',
          params: {'reason': _reasonTag(e)});
      return false;
    }
  }

  /// Approves the builder as soon as an account has funds, which is the
  /// moment the venue will accept it.
  ///
  /// A user-signed action needs a funded account, so this cannot run at
  /// wallet creation, and it must not first be tried at order time
  /// either: that is the tap where a failure costs the person their
  /// trade and costs Kute the fee. Call it whenever a deposit credits.
  /// It is cheap when already approved, since the flag short-circuits
  /// before any network call, and it never throws.
  static Future<void> approveAfterFunding({
    required HyperliquidExchangeService exchange,
    required String walletAddress,
    required String walletId,
  }) async {
    try {
      if (await hasApprovedBuilderFee(walletId)) return;
      final builder = await HyperliquidFundingService.getBuilder();
      if (builder == null) return;
      await ensureBuilderFeeApproved(
        exchange: exchange,
        walletAddress: walletAddress,
        walletId: walletId,
        reviewed: builder,
      );
    } catch (_) {
      // Opportunistic: the order path retries, and a failure here must
      // never surface on a deposit the person already completed.
    }
  }

  /// Why the last approval attempt did not succeed, or null after one
  /// that did. Read by the order path so the person is told the actual
  /// obstacle instead of being asked to approve something with nothing
  /// on screen to approve.
  static String? lastFailure;

  /// A short, non-identifying label for analytics. Never the raw message,
  /// which can carry an address or an amount.
  static String _reasonTag(Object e) {
    final text = e.toString().toLowerCase();
    if (text.contains('insufficient') || text.contains('not funded')) {
      return 'unfunded';
    }
    if (text.contains('nonce')) return 'nonce';
    if (text.contains('signature') || text.contains('sign')) return 'signature';
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('network')) {
      return 'network';
    }
    return 'other';
  }

  /// True when this wallet's persisted approval covers the builder the
  /// backend currently publishes (same address, cap at or above the order
  /// fee), or when no builder is published. A cheap local hint only —
  /// [ensureBuilderFeeApproved] re-checks the exchange. A rotated address
  /// never matches the stored record, so it reads as unapproved.
  static Future<bool> hasApprovedBuilderFee(String walletId) async {
    try {
      final builder = await HyperliquidFundingService.getBuilder();
      if (builder == null || builder.defaultFeeTenthsBp == 0) return true;
      final raw = await secureStorage.read(key: _builderApprovedKey(walletId));
      // Older builds stored a bare 'true' without naming the builder; it
      // proves nothing about the published one, so the exchange decides.
      final record = raw == null || raw == 'true' ? null : jsonDecode(raw);
      return record is Map &&
          record['builder'] == builder.builderAddress.toLowerCase() &&
          record['cap'] is int &&
          record['cap'] >= builder.defaultFeeTenthsBp;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _persistApproved(
      String walletId, HlBuilderInfo builder, int cap) async {
    try {
      await secureStorage.write(
          key: _builderApprovedKey(walletId),
          value: jsonEncode({
            'builder': builder.builderAddress.toLowerCase(),
            'cap': cap,
          }));
    } catch (_) {}
  }

  /// The user's current approved fee for [builder] in tenths of a basis
  /// point, or null when unknown (never approved / network failure).
  static Future<int?> _currentMaxBuilderFee({
    required String user,
    required String builder,
  }) async {
    try {
      final resp = await http
          .post(
            HyperliquidConstants.infoUri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'type': 'maxBuilderFee',
              'user': user,
              'builder': builder.toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is num) return decoded.toInt();
      return int.tryParse(decoded.toString());
    } catch (_) {
      return null;
    }
  }
}
