import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/tracking_service.dart';

/// What the venues hold for one EVM account. Each venue is true (funds or
/// history found), false (every read answered and found nothing) or null
/// (unknown: a read failed or timed out).
class EvmVenueHistory {
  const EvmVenueHistory({this.hyperliquid, this.polymarket});

  final bool? hyperliquid;
  final bool? polymarket;

  /// Funds or history on at least one venue.
  bool get active => hyperliquid == true || polymarket == true;

  /// The answer is known: something was found, or both venues answered
  /// with nothing.
  bool get complete =>
      active || (hyperliquid == false && polymarket == false);
}

/// Reads the venue history of one account-zero EOA. Never throws.
typedef EvmVenueProbe = Future<EvmVenueHistory> Function(String eoa);

/// Both account-zero EOAs of one phrase.
typedef EvmRecoveryAccounts = ({String legacy, String standard});

/// Read-only venue history over the app's existing public reads:
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
///
/// Signs nothing and creates nothing. Addresses are only sent to the
/// venues' own public read endpoints, never tracked or logged.
class EvmVenueHistoryReader {
  EvmVenueHistoryReader({
    HyperliquidModel? hyperliquid,
    PolymarketAccountReads? polymarket,
    Future<bool> Function(String account)? polymarketActivity,
    this.timeout = RecoveryEvmFormat.checkTimeout,
  }) : _hl = hyperliquid ?? HyperliquidModel() {
    final model = PolymarketModel();
    _pm = polymarket ?? OnboardingPolymarketAccountReads(model: model);
    _pmActivity = polymarketActivity ??
        ((account) async =>
            (await model.getUserActivityOrThrow(account)).isNotEmpty);
  }

  final HyperliquidModel _hl;
  late final PolymarketAccountReads _pm;
  late final Future<bool> Function(String account) _pmActivity;
  final Duration timeout;

  Future<EvmVenueHistory> read(String eoa) async {
    final results = await Future.wait([_hyperliquid(eoa), _polymarket(eoa)]);
    return EvmVenueHistory(hyperliquid: results[0], polymarket: results[1]);
  }

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
  });

  final EvmDerivationVersion version;

  /// False when the venue check did not finish; the wallet then gets
  /// [WalletConfig.evmFormatCheckPending] and the next unlock retries.
  final bool checked;

  /// The chosen account has Hyperliquid funds or history.
  final bool hyperliquidActive;

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
/// user's Predictions and Investing live on, so recovery asks the venues:
/// the legacy format is kept when its account has funds or history (also
/// when both do, for continuity); otherwise the standard format, as before.
abstract final class RecoveryEvmFormat {
  static const checkTimeout = Duration(seconds: 5);

  /// Both account-zero EOAs, derived off the UI isolate.
  static Future<EvmRecoveryAccounts> deriveAccounts(String mnemonic) =>
      Isolate.run(() => (
            legacy: RecoveryCheck.deriveSync(mnemonic,
                version: EvmDerivationVersion.legacySha256),
            standard: RecoveryCheck.deriveSync(mnemonic,
                version: EvmDerivationVersion.standardBip39),
          ));

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
            hyperliquidActive: legacy.hyperliquid == true);
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
  /// still has no venue funds or history and its legacy account does; an
  /// account with activity is never switched away from. A retry that does
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
          TrackingService.recoveryEvmFormatRechecked(result: 'switched_legacy');
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
