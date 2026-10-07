import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/arbitrum_read_rpc.dart';
import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/tracking_service.dart';

/// What one EVM account holds or has done. Each signal is true (found),
/// false (every read answered and found nothing) or null (unknown: a read
/// failed or timed out). Unknown is never read as "nothing".
class EvmVenueHistory {
  const EvmVenueHistory({
    this.hyperliquid,
    this.polymarket,
    this.polygonFunds,
    this.arbitrumFunds,
    this.sent,
  });

  /// Every signal answered with nothing.
  const EvmVenueHistory.empty()
      : this(
            hyperliquid: false,
            polymarket: false,
            polygonFunds: false,
            arbitrumFunds: false,
            sent: false);

  /// Hyperliquid funds or history.
  final bool? hyperliquid;

  /// Polymarket funds or history (Safe or deposit wallets).
  final bool? polymarket;

  /// POL, USDC, USDC.e or pUSD above dust on the EOA itself, on Polygon.
  final bool? polygonFunds;

  /// ETH or USDC above dust on the EOA itself, on Arbitrum One.
  final bool? arbitrumFunds;

  /// The EOA has sent a transaction (nonce above zero) on Polygon or
  /// Arbitrum One.
  final bool? sent;

  List<bool?> get _signals =>
      [hyperliquid, polymarket, polygonFunds, arbitrumFunds, sent];

  /// At least one signal found funds or history.
  bool get active => _signals.contains(true);

  /// The answer is known: something was found, or every signal answered
  /// with nothing.
  bool get complete => active || _signals.every((s) => s == false);

  /// `legacy_signal` for analytics, categorical only: the strongest signal
  /// found (venue | polygon_balance | arbitrum_balance | nonce), or null
  /// when none was.
  String? get signal => hyperliquid == true || polymarket == true
      ? 'venue'
      : polygonFunds == true
          ? 'polygon_balance'
          : arbitrumFunds == true
              ? 'arbitrum_balance'
              : sent == true
                  ? 'nonce'
                  : null;
}

/// Reads the history of one account-zero EOA. Never throws.
typedef EvmVenueProbe = Future<EvmVenueHistory> Function(String eoa);

/// Both account-zero EOAs of one phrase.
typedef EvmRecoveryAccounts = ({String legacy, String standard});

/// Plain reads of one EVM chain. Every method throws on failure, so a
/// failed read can never pass for an empty account.
abstract class EvmChainReads {
  Future<BigInt> nativeBalance(String owner);
  Future<BigInt> nonce(String owner);
  Future<BigInt> erc20Balance({required String token, required String owner});
}

/// Polygon over the onboarding service's RPC fallback (chain id checked,
/// slow endpoints skipped).
class _PolygonChainReads implements EvmChainReads {
  _PolygonChainReads(this._onboarding);
  final PolymarketOnboardingService _onboarding;

  @override
  Future<BigInt> nativeBalance(String owner) =>
      _onboarding.readNativeBalanceOrThrow(owner);
  @override
  Future<BigInt> nonce(String owner) => _onboarding.readNonceOrThrow(owner);
  @override
  Future<BigInt> erc20Balance({required String token, required String owner}) =>
      _onboarding.readErc20BalanceOrThrow(token: token, owner: owner);
}

/// Arbitrum One over its public RPC fallback list.
class _ArbitrumChainReads implements EvmChainReads {
  _ArbitrumChainReads(this._rpc);
  final ArbitrumReadRpc _rpc;

  @override
  Future<BigInt> nativeBalance(String owner) => _rpc.nativeBalance(owner);
  @override
  Future<BigInt> nonce(String owner) => _rpc.nonce(owner);
  @override
  Future<BigInt> erc20Balance({required String token, required String owner}) =>
      _rpc.erc20Balance(token: token, owner: owner);
}

/// Read-only history over the app's existing public reads, all started at
/// once and bounded by one [timeout]:
///
/// * Hyperliquid: equity, a position or a spot balance
///   (`clearinghouseState` + `spotClearinghouseState`), any fill, or any
///   non-funding ledger update (deposit, withdrawal, transfer).
/// * Polymarket: for the EOA's legacy Safe and both deposit wallet
///   addresses (UUPS and the factory's current one), Data API positions or
///   activity, or a pUSD / USDC.e balance; or Safe contract code (the app
///   no longer deploys Safes, so code there is history). Deposit wallet
///   code alone does not count: the app deploys one for every account it
///   provisions.
/// * Funds sent straight to the EOA: POL, USDC, USDC.e or pUSD on Polygon,
///   ETH or USDC on Arbitrum One. Dust below about a cent is ignored so an
///   airdrop cannot decide the format.
/// * A nonce above zero on Polygon or Arbitrum One (the EOA sent a
///   transaction).
///
/// Signs nothing and creates nothing. Addresses are only sent to the
/// venues' and chains' own public read endpoints, never tracked or logged.
class EvmVenueHistoryReader {
  EvmVenueHistoryReader({
    HyperliquidModel? hyperliquid,
    PolymarketAccountReads? polymarket,
    Future<bool> Function(String account)? polymarketActivity,
    EvmChainReads? polygon,
    EvmChainReads? arbitrum,
    this.timeout = RecoveryEvmFormat.checkTimeout,
  }) : _hl = hyperliquid ?? HyperliquidModel() {
    final model = PolymarketModel();
    PolymarketOnboardingService? onboarding;
    PolymarketOnboardingService sharedOnboarding() =>
        onboarding ??= PolymarketOnboardingService();
    _pm = polymarket ??
        OnboardingPolymarketAccountReads(
            onboarding: sharedOnboarding(), model: model);
    _pmActivity = polymarketActivity ??
        ((account) async =>
            (await model.getUserActivityOrThrow(account)).isNotEmpty);
    _polygon = polygon ?? _PolygonChainReads(sharedOnboarding());
    _arbitrum = arbitrum ?? _ArbitrumChainReads(ArbitrumReadRpc());
  }

  final HyperliquidModel _hl;
  late final PolymarketAccountReads _pm;
  late final Future<bool> Function(String account) _pmActivity;
  late final EvmChainReads _polygon;
  late final EvmChainReads _arbitrum;
  final Duration timeout;

  /// 0.01 of a 6-decimal dollar token (USDC, USDC.e, pUSD).
  @visibleForTesting
  static final stablecoinDust = BigInt.from(10000);

  /// 0.001 POL.
  @visibleForTesting
  static final polDust = BigInt.from(10).pow(15);

  /// 0.00001 ETH, a few cents.
  @visibleForTesting
  static final ethDust = BigInt.from(10).pow(13);

  Future<EvmVenueHistory> read(String eoa) async {
    final results = await Future.wait([
      _hyperliquid(eoa),
      _polymarket(eoa),
      _polygonFunds(eoa),
      _arbitrumFunds(eoa),
      _sent(eoa),
    ]);
    return EvmVenueHistory(
      hyperliquid: results[0],
      polymarket: results[1],
      polygonFunds: results[2],
      arbitrumFunds: results[3],
      sent: results[4],
    );
  }

  Future<bool?> _polygonFunds(String eoa) => anyTrue([
        () async => await _polygon.nativeBalance(eoa) >= polDust,
        for (final token in const [
          PolymarketConstants.usdcAddress,
          PolymarketConstants.usdcEAddress,
          PolymarketConstants.pusdAddress,
        ])
          () async =>
              await _polygon.erc20Balance(token: token, owner: eoa) >=
              stablecoinDust,
      ], timeout);

  Future<bool?> _arbitrumFunds(String eoa) => anyTrue([
        () async => await _arbitrum.nativeBalance(eoa) >= ethDust,
        () async =>
            await _arbitrum.erc20Balance(
                token: ArbitrumReadRpc.usdcAddress, owner: eoa) >=
            stablecoinDust,
      ], timeout);

  Future<bool?> _sent(String eoa) => anyTrue([
        () async => await _polygon.nonce(eoa) > BigInt.zero,
        () async => await _arbitrum.nonce(eoa) > BigInt.zero,
      ], timeout);

  Future<bool?> _hyperliquid(String eoa) => anyTrue([
        () async {
          final snapshot = await _hl.getAccountSnapshot(eoa);
          return snapshot.hasActivity ||
              snapshot.spotBalances.any((b) => b.total > 0);
        },
        () => _hl.hasAnyFill(eoa),
        () => _hl.hasAnyLedgerUpdate(eoa),
      ], timeout);

  Future<bool?> _polymarket(String eoa) {
    final zero = PolymarketConstants.zeroAddress.toLowerCase();
    String? usable(String address) =>
        address.toLowerCase() == zero ? null : address;
    final safe = _pm.deriveSafeAddress(eoa).then(usable);
    final uups = Future.sync(() => usable(_pm.deriveDepositWalletAddress(eoa)));
    final current = _pm.predictDepositWallet(eoa).then(usable);
    // Every read below awaits its address inside the same closure, so a
    // failed address read is caught there and never goes unhandled.
    safe.ignore();
    uups.ignore();
    current.ignore();

    List<Future<bool> Function()> accountReads(Future<String?> account) => [
          () async {
            final a = await account;
            return a != null && (await _pm.positions(a)).isNotEmpty;
          },
          () async {
            final a = await account;
            return a != null && await _pmActivity(a);
          },
          for (final token in const [
            PolymarketConstants.pusdAddress,
            PolymarketConstants.usdcEAddress,
          ])
            () async {
              final a = await account;
              return a != null &&
                  await _pm.erc20Balance(token: token, owner: a) > BigInt.zero;
            },
        ];

    return anyTrue([
      () async {
        final a = await safe;
        return a != null && await _pm.hasCode(a);
      },
      ...accountReads(safe),
      ...accountReads(uups),
      ...accountReads(current),
    ], timeout);
  }

  /// True as soon as any read answers true; false when every read answered
  /// false; null when none answered true and at least one failed or the
  /// [timeout] passed first.
  @visibleForTesting
  static Future<bool?> anyTrue(
      List<Future<bool> Function()> reads, Duration timeout) {
    if (reads.isEmpty) return Future.value(false);
    final done = Completer<bool?>();
    var pending = reads.length;
    var failed = false;
    for (final read in reads) {
      Future.sync(read).then((found) {
        if (found && !done.isCompleted) done.complete(true);
      }, onError: (Object _) {
        failed = true;
      }).whenComplete(() {
        pending--;
        if (pending == 0 && !done.isCompleted) {
          done.complete(failed ? null : false);
        }
      });
    }
    return done.future.timeout(timeout, onTimeout: () => null);
  }
}

/// The EVM format a phrase recovery persists, and how it was decided.
class RecoveryEvmChoice {
  const RecoveryEvmChoice({
    required this.version,
    required this.checked,
    this.hyperliquidActive = false,
    this.legacySignal,
  });

  final EvmDerivationVersion version;

  /// False when the venue check did not finish; the wallet then gets
  /// [WalletConfig.evmFormatCheckPending] and the next unlock retries.
  final bool checked;

  /// The chosen account has Hyperliquid funds or history.
  final bool hyperliquidActive;

  /// For a legacy choice, what proved the legacy account in use
  /// ([EvmVenueHistory.signal]); `legacy_signal` on `recovery_seed_entered`.
  final String? legacySignal;

  /// `evm_format` on `recovery_seed_entered`: legacy | standard | unchecked.
  String get analyticsValue => !checked
      ? 'unchecked'
      : version == EvmDerivationVersion.legacySha256
          ? 'legacy'
          : 'standard';
}

/// Picks the EVM format for a wallet recovered by typing its phrase.
///
/// Wallets created before the standard format derive their EVM account with
/// the legacy SHA256 seed stretch, so the same 12 words lead to two
/// different account-zero EOAs. A phrase alone does not say which one the
/// user's Predictions and Investing live on, so recovery asks the venues
/// and the chains: the legacy format is kept when its account has venue
/// funds or history, funds sent straight to it on Polygon or Arbitrum, or
/// a sent transaction (also when both accounts do, for continuity);
/// otherwise the standard format, as before. A legacy read that fails or
/// times out never counts as "nothing there": without conclusive legacy
/// activity it leaves the choice unchecked.
abstract final class RecoveryEvmFormat {
  static const checkTimeout = Duration(seconds: 5);

  /// Both account-zero EOAs, derived together in one background isolate
  /// and kept in the session memo, so the account recovery then provisions
  /// is not stretched again on the UI isolate.
  static Future<EvmRecoveryAccounts> deriveAccounts(String mnemonic) async {
    final both =
        await EvmWalletDerivation.deriveBothAsync(RecoveryCheck.normalize(mnemonic));
    return (legacy: both.legacy.address, standard: both.standard.address);
  }

  static EvmVenueProbe get _defaultProbe => EvmVenueHistoryReader().read;

  /// Never throws: any failure falls back to the standard format with
  /// [RecoveryEvmChoice.checked] false.
  static Future<RecoveryEvmChoice> choose(
    String mnemonic, {
    EvmVenueProbe? probe,
    Future<EvmRecoveryAccounts> Function(String mnemonic)? derive,
  }) async {
    const unchecked = RecoveryEvmChoice(
        version: EvmDerivationVersion.standardBip39, checked: false);
    try {
      final accounts = await (derive ?? deriveAccounts)(mnemonic);
      final read = probe ?? _defaultProbe;
      final results = await Future.wait([
        read(accounts.legacy),
        read(accounts.standard),
      ]).timeout(checkTimeout + const Duration(seconds: 1));
      final legacy = results[0];
      final standard = results[1];
      if (legacy.active) {
        return RecoveryEvmChoice(
            version: EvmDerivationVersion.legacySha256,
            checked: true,
            hyperliquidActive: legacy.hyperliquid == true,
            legacySignal: legacy.signal);
      }
      return RecoveryEvmChoice(
          version: EvmDerivationVersion.standardBip39,
          checked: legacy.complete,
          hyperliquidActive: standard.hyperliquid == true);
    } catch (_) {
      return unchecked;
    }
  }

  static bool _retriedThisLaunch = false;

  @visibleForTesting
  static void resetForTest() => _retriedThisLaunch = false;

  /// Retries the venue check for wallets whose recovery check did not
  /// finish. Runs at most once per launch, after an unlock; [readMnemonic]
  /// reads a wallet's phrase with that session (automatic access only).
  /// A wallet moves to the legacy format only when its standard account
  /// still has no funds, history or sent transactions (every signal
  /// answered) and its legacy account has some; an account with activity
  /// is never switched away from. A retry that does
  /// not finish leaves the flag for the next launch.
  ///
  /// [onAdopted] runs after a switch so the caller can drop per-wallet
  /// venue caches and rebuild what derived the old account.
  static Future<void> retryPending({
    required SettingsModel settings,
    required List<WalletConfig> wallets,
    required Future<String?> Function(String walletId) readMnemonic,
    EvmVenueProbe? probe,
    Future<EvmRecoveryAccounts> Function(String mnemonic)? derive,
    Future<void> Function(String walletId, String mnemonic,
            {required bool hyperliquidActive})?
        onAdopted,
  }) async {
    final pending = wallets
        .where((w) => w.evmFormatCheckPending && RecoveryCheck.holdsStoredSeed(w))
        .toList();
    if (pending.isEmpty || _retriedThisLaunch) return;
    _retriedThisLaunch = true;
    final read = probe ?? _defaultProbe;
    for (final wallet in pending) {
      try {
        final current = settings.walletById(wallet.id);
        if (current == null || !current.evmFormatCheckPending) continue;
        if (current.evmDerivationVersion !=
            EvmDerivationVersion.standardBip39) {
          await settings.clearEvmFormatCheckPending(wallet.id);
          continue;
        }
        final mnemonic = await readMnemonic(wallet.id);
        if (mnemonic == null) continue;
        final accounts = await (derive ?? deriveAccounts)(mnemonic);

        final standard = await read(accounts.standard);
        if (standard.active) {
          await settings.clearEvmFormatCheckPending(wallet.id);
          TrackingService.recoveryEvmFormatRechecked(result: 'standard_active');
          continue;
        }
        if (!standard.complete) {
          TrackingService.recoveryEvmFormatRechecked(result: 'incomplete');
          continue;
        }
        final legacy = await read(accounts.legacy);
        if (legacy.active) {
          final adopted = await settings.adoptLegacyEvmAfterRecoveryCheck(
              wallet.id,
              recoveryCheckAddress: accounts.legacy);
          if (!adopted) continue;
          TrackingService.recoveryEvmFormatRechecked(
              result: 'switched_legacy', legacySignal: legacy.signal);
          await onAdopted?.call(wallet.id, mnemonic,
              hyperliquidActive: legacy.hyperliquid == true);
        } else if (legacy.complete) {
          await settings.clearEvmFormatCheckPending(wallet.id);
          TrackingService.recoveryEvmFormatRechecked(result: 'kept_standard');
        } else {
          TrackingService.recoveryEvmFormatRechecked(result: 'incomplete');
        }
      } catch (_) {
        // Best effort; the flag stays for the next launch.
      }
    }
  }
}
