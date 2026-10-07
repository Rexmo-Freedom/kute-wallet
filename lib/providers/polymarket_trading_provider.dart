import 'package:kute/services/polymarket/market_buy_quote.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/send_time_read.dart';
import 'package:kute/services/polymarket/combos/combo_service.dart';
import 'package:kute/services/polymarket/combos/combo_transport.dart';
import 'package:kute/services/polymarket/credential_identity.dart';
import 'package:kute/services/polymarket/clob_auth.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/trade_notification_store.dart';
import 'dart:async';
import 'package:kute/helpers/polymarket_account_readiness.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/passkey_service.dart'
    show resolveBip39MnemonicFor;
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_owner_link_service.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/usdc_balance_history_service.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/kute_state_provider.dart';
import 'package:kute/providers/milestone_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/settings_model.dart' show Settings;
import 'package:kute/services/milestone_service.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/dex_swap_service.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket/hot_withdrawal_guard.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket/order_amounts.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket_optimistic_activity_service.dart';
import 'package:kute/providers/transactions_provider.dart'
    show transactionNotifierProvider;
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/polymarket_bet_funding_service.dart';
import 'package:kute/services/polymarket_suppression_service.dart';
import 'package:kute/services/polymarket_usdc_cache_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    hide PolymarketConstants, InsufficientFundsException;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// debugPrint wrapper that no-ops in release/profile builds. Flutter's
/// own `debugPrint` still writes to stdout when the app is built in
/// profile mode and on a device connected to Xcode/ADB anyone can
/// read the console output. The audit flagged these specific call
/// sites because they interpolate proxyWallet (Polygon Safe addr),
/// USDC balances, tx hashes, and share counts — all of which would
/// surface in logcat / Console.app on a release-test build.
void _devLog(Object? msg) {
  if (kDebugMode) debugPrint(msg?.toString());
}

class PolymarketTradingState {
  final bool isAuthenticated;

  /// SUM of pUSD + USDC.e + native USDC held on the Polymarket proxy,
  /// in human dollars. All three are 1:1 USD on Polygon — the
  /// breakdown only matters mid-flow (deposit arrives as USDC.e and
  /// wraps to pUSD; cashout unwraps pUSD back to USDC.e and then ships
  /// it out). At rest balances live in pUSD per task #170, but legacy
  /// or in-flight USDC.e is still coalesced into this number so the
  /// home USDC tile reads as one balance.
  final double usdcBalance;
  final double totalPnl;
  final double totalPnlPercent;
  final List<Position> openPositions;
  final List<ClosedPosition> closedPositions;
  final List<Order> openOrders;
  final String? walletAddress; // EOA (derived from mnemonic)
  final String? proxyWalletAddress; // Polymarket proxy wallet (for Data API)
  final String? error;
  final bool isPlacingOrder;

  /// Tokens currently being sold. Their cards render a "Selling…" state
  /// (instead of being optimistically removed) until the Data API confirms
  /// the on-chain settlement. Reconciled each refresh in [_fetchAllData].
  final Set<String> pendingSaleTokens;

  /// Condition ids whose redeem tx SUCCEEDED but the Data API hasn't
  /// confirmed yet (position not in closedPositions, still returned as
  /// redeemable). The resolved-rail card renders a locked spinner for
  /// these instead of a tappable Claim/Clear that "showed up again"
  /// after the user already cleared it. Bounded: entries older than
  /// [PolymarketTradingNotifier._clearingSpinnerWindow] revert to the
  /// button so a claim the chain silently dropped stays retryable.
  final Set<String> clearingConditionIds;

  /// Whether [usdcBalance] is a balance that was read. False on the
  /// placeholder states (no spending wallet, a locked session, setup that
  /// failed) and when the balance read itself failed, where the 0 stands
  /// for "unknown": the slip waits instead of offering a deposit on it.
  final bool balanceKnown;

  const PolymarketTradingState({
    this.isAuthenticated = false,
    this.usdcBalance = 0,
    this.totalPnl = 0,
    this.totalPnlPercent = 0,
    this.openPositions = const [],
    this.closedPositions = const [],
    this.openOrders = const [],
    this.walletAddress,
    this.proxyWalletAddress,
    this.error,
    this.isPlacingOrder = false,
    this.pendingSaleTokens = const {},
    this.clearingConditionIds = const {},
    this.balanceKnown = true,
  });

  PolymarketTradingState copyWith({
    bool? isAuthenticated,
    double? usdcBalance,
    double? totalPnl,
    double? totalPnlPercent,
    List<Position>? openPositions,
    List<ClosedPosition>? closedPositions,
    List<Order>? openOrders,
    String? walletAddress,
    String? proxyWalletAddress,
    String? error,
    bool? isPlacingOrder,
    Set<String>? pendingSaleTokens,
    Set<String>? clearingConditionIds,
    bool? balanceKnown,
  }) {
    return PolymarketTradingState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      usdcBalance: usdcBalance ?? this.usdcBalance,
      totalPnl: totalPnl ?? this.totalPnl,
      totalPnlPercent: totalPnlPercent ?? this.totalPnlPercent,
      openPositions: openPositions ?? this.openPositions,
      closedPositions: closedPositions ?? this.closedPositions,
      openOrders: openOrders ?? this.openOrders,
      walletAddress: walletAddress ?? this.walletAddress,
      proxyWalletAddress: proxyWalletAddress ?? this.proxyWalletAddress,
      error: error,
      isPlacingOrder: isPlacingOrder ?? this.isPlacingOrder,
      pendingSaleTokens: pendingSaleTokens ?? this.pendingSaleTokens,
      clearingConditionIds: clearingConditionIds ?? this.clearingConditionIds,
      balanceKnown: balanceKnown ?? this.balanceKnown,
    );
  }

  static bool _samePositionValues(List<Position> a, List<Position> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!mapEquals(a[i].toJson(), b[i].toJson())) return false;
    }
    return true;
  }

  // Upstream Position equality compares identity only. Compare the wire
  // fields as well so a newly redeemable holding, partial fill, or valuation
  // update is not silently discarded by _setData.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PolymarketTradingState) return false;
    return isAuthenticated == other.isAuthenticated &&
        usdcBalance == other.usdcBalance &&
        totalPnl == other.totalPnl &&
        totalPnlPercent == other.totalPnlPercent &&
        walletAddress == other.walletAddress &&
        proxyWalletAddress == other.proxyWalletAddress &&
        error == other.error &&
        isPlacingOrder == other.isPlacingOrder &&
        setEquals(pendingSaleTokens, other.pendingSaleTokens) &&
        setEquals(clearingConditionIds, other.clearingConditionIds) &&
        _samePositionValues(openPositions, other.openPositions) &&
        listEquals(closedPositions, other.closedPositions) &&
        listEquals(openOrders, other.openOrders);
  }

  @override
  int get hashCode => Object.hash(
        isAuthenticated,
        usdcBalance,
        totalPnl,
        totalPnlPercent,
        walletAddress,
        proxyWalletAddress,
        error,
        isPlacingOrder,
        Object.hashAll(openPositions),
        Object.hashAll(closedPositions),
        Object.hashAll(openOrders),
        Object.hashAll(pendingSaleTokens),
        Object.hashAll(clearingConditionIds),
      );
}

const _kPmCredsPrefix = 'pm_api_credentials_';
const _kPmProxyPrefix = 'pm_proxy_wallet_';

String _credsKey(String walletId) => '$_kPmCredsPrefix$walletId';

/// The wallet whose Polymarket CLOB credentials the hot trading notifier
/// owns: the spending wallet it was built for, else the current spending
/// wallet. Never `settings.activeWalletId`, which can be a Ledger or any
/// other carousel page (Wallet hardening Phase 3, P3.9).
String? polymarketCredentialsWalletId(
  Settings settings, {
  String? pinnedWalletId,
}) =>
    pinnedWalletId ?? pickSpendingWallet(settings)?.id;
String _proxyKey(String walletId) => '$_kPmProxyPrefix$walletId';

/// Drops [walletId]'s cached Polymarket deposit wallet address and CLOB
/// credentials. Used when a recovered wallet's EVM account changes
/// (`RecoveryEvmFormat.retryPending`): both were set up for the old
/// account and must be resolved again for the new one.
Future<void> forgetPolymarketAccountCache(String walletId) async {
  for (final key in [_proxyKey(walletId), _credsKey(walletId)]) {
    try {
      await secureStorage.delete(key: key);
    } catch (_) {}
  }
}

/// The hot wallet's Polymarket deposit wallet, for display in Settings.
/// Prefers the live trading state when the notifier is already built for
/// [walletId], else the address the notifier cached on its last build
/// (`resolveDepositWalletAddress`). Never builds the trading notifier and
/// never reaches the network. Null until Predictions has been set up.
final polymarketDepositWalletAddressProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, walletId) async {
  if (ref.exists(polymarketTradingProvider) &&
      pickSpendingWallet(ref.read(settingsProvider))?.id == walletId) {
    final live = ref.read(polymarketTradingProvider).valueOrNull;
    final proxy = live?.proxyWalletAddress;
    if (proxy != null && proxy.isNotEmpty) return proxy;
  }
  try {
    final cached = await secureStorage.read(key: _proxyKey(walletId));
    return (cached == null || cached.isEmpty) ? null : cached;
  } catch (_) {
    return null;
  }
});

class _CredentialsWithNonce {
  final ApiCredentials credentials;
  final int nonce;
  const _CredentialsWithNonce({required this.credentials, required this.nonce});
}

/// Provisions Polymarket API credentials from a mnemonic.
/// Called at wallet creation/login. Silent on failure.
Future<void> provisionPolymarketCredentials({
  required String mnemonic,
  required String walletId,
  required EvmDerivationVersion evmDerivationVersion,
}) async {
  const storage = secureStorage;
  try {
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: evmDerivationVersion, index: 0);
    final existing = await storage.read(key: _credsKey(walletId));
    if (existing != null) {
      try {
        final record = jsonDecode(existing);
        if (record is Map &&
            PolymarketCredentialIdentity.matches(record,
                ownerAddress: wallet.address, version: evmDerivationVersion)) {
          return;
        }
      } on FormatException {/* Recreate malformed cached credentials. */}
    }

    // Create client with private key
    final client = PolymarketClient.withPrivateKey(
      privateKey: wallet.privateKey,
      walletAddress: wallet.address,
    );

    try {
      // Derive or create API key via EIP-712 signing.
      // deriveApiKey may throw ValidationException (not ApiException) for
      // new wallets, so we catch all errors and fall back to createApiKey.
      ApiCredentials? credentials;
      try {
        credentials = await client.clob.auth?.deriveApiKey();
      } catch (_) {
        credentials = await client.clob.auth?.createApiKey();
      }
      if (credentials != null) {
        // Note: nonce=0 since the library doesn't capture it.
        // The trading provider will re-derive with the correct nonce on first use.
        final json = jsonEncode({
          'apiKey': credentials.apiKey,
          'secret': credentials.secret,
          'passphrase': credentials.passphrase,
          'nonce': 0,
          ...PolymarketCredentialIdentity.metadata(
              ownerAddress: wallet.address, version: evmDerivationVersion),
        });
        await storage.write(key: _credsKey(walletId), value: json);
      }
    } finally {
      client.close();
    }
  } catch (_) {
    // Silent — wallet may not be registered on Polymarket yet.
    // Credentials will be retried when user opens Polymarket screen.
  }
}

/// Full Polymarket account setup: deploy Safe proxy wallet, set token
/// approvals, and provision CLOB API credentials. Idempotent — skips
/// steps that are already done. Called at wallet creation/login so the
/// account is ready before the user opens Polymarket.
Future<void> provisionPolymarketAccount({
  required String mnemonic,
  required String walletId,
  required EvmDerivationVersion evmDerivationVersion,
}) async {
  const storage = secureStorage;
  try {
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: evmDerivationVersion, index: 0);
    final onboarding = PolymarketOnboardingService();

    // Step 1: Deploy Safe + set token approvals (skips if already done).
    final proxyWallet = await onboarding.enableTrading(
      eoaAddress: wallet.address,
      privateKey: wallet.privateKey,
    );

    // Persist proxy wallet address
    await storage.write(key: _proxyKey(walletId), value: proxyWallet);

    // Step 2: Provision CLOB API credentials
    await provisionPolymarketCredentials(
      mnemonic: mnemonic,
      walletId: walletId,
      evmDerivationVersion: evmDerivationVersion,
    );
  } catch (_) {
    // Silent — network may be unavailable. Will be retried when user opens
    // Polymarket screen via _autoEnableTrading.
  }
}

/// Emitted when a position transitions to resolved (redeemable).
class ResolvedPositionEvent {
  final String title;
  final String outcome;
  final bool won;
  final double payout; // USDC value if won, 0 if lost

  /// The market it was in, for the match moment that opens it.
  final String? eventSlug;
  final String? conditionId;
  const ResolvedPositionEvent(
      {required this.title,
      required this.outcome,
      required this.won,
      this.payout = 0,
      this.eventSlug,
      this.conditionId});
}

/// True when [e] is an expected connectivity failure (no internet, DNS
/// failure, stalled/timed-out request) rather than a real bug — used to keep
/// offline conditions out of crash reporting.
bool _isOfflineError(Object e) {
  if (e is TimeoutException) return true;
  final s = e.toString().toLowerCase();
  // 'timeoutexception' string check catches timeouts wrapped/rethrown
  // inside another exception type (only the raw dart:async instance
  // hits the `is` check above).
  return s.contains('timeoutexception') ||
      s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('connection refused') ||
      s.contains('clientexception') ||
      s.contains('handshakeexception') ||
      s.contains('xmlhttprequest');
}

/// A claim tapped before the market's result is reported on chain
/// (`payoutDenominator` is still 0), so nothing was sent. The claim
/// surfaces say the result is still being recorded instead of the generic
/// "not completed".
/// A claim of a position whose tokens are no longer on the wallet (sold,
/// or claimed already), so nothing was sent.
class PolymarketNothingToClaimException implements Exception {
  const PolymarketNothingToClaimException();

  @override
  String toString() => 'No outcome tokens left on the wallet to claim.';
}

class PolymarketResultNotOnChainException implements Exception {
  const PolymarketResultNotOnChainException();

  @override
  String toString() => 'This market hasn\'t finished settling on-chain yet. '
      'Payouts usually open a few minutes after resolution. '
      'Your winnings are safe, try again shortly.';
}

class PolymarketTradingNotifier
    extends AutoDisposeAsyncNotifier<PolymarketTradingState> {
  PolymarketClient? _client;
  PolymarketBackendService? _backendService;

  /// Exposed so the CLOB user-channel WS provider can grab fresh L2
  /// auth headers for the `subscribe` payload. Null until the user
  /// has enabled trading and we've derived API credentials.
  PolymarketBackendService? get backendService => _backendService;

  /// Read-only SDK client handle for metadata lookups (market min size,
  /// tick size). Null until trading is initialized.
  PolymarketClient? get clobClient => _client;
  PolymarketModel? _publicModel;
  Timer? _refreshTimer;
  String?
      _privateKey; // EOA private key for order signing (never leaves device)

  /// The spending wallet this notifier was built for. CLOB credentials are
  /// always saved, healed and refreshed under this ID, never under the
  /// carousel's active wallet (Wallet hardening Phase 3, P3.9).
  String? _spendingWalletId;
  int _apiNonce =
      0; // Nonce from API key creation (required for POLY_NONCE header)
  // The L2 authentication address is persisted with the credentials.
  // Fresh credentials use the EOA; order signing uses the deposit wallet.
  String? _apiKeyBoundAddress;

  /// Per-session set of conditionIds we've already auto-claimed (or
  /// tried to). Resets at app restart, which is fine — successful
  /// claims drop out of `openPositions` on the next refresh, and
  /// failed ones can be retried after a relaunch. Without this guard
  /// the 10 s refresh tick would keep firing `redeemPosition` against
  /// a position whose first auto-claim is still propagating through
  /// the relayer, racing the manual claim button if the user happens
  /// to tap it at the same time.
  final Set<String> _autoClaimedIds = {};

  /// Calldata for a USDC.e-collateral fallback redemption, prepared at
  /// the same time as the primary pUSD-collateral attempt. Cleared
  /// after the redeem completes (or fallback fires). Lets us retry
  /// without rebuilding the offset/length boilerplate.
  String? _redeemFallbackCalldata;
  final Set<String> _knownRedeemableIds =
      {}; // Sticky: once redeemable, stays redeemable
  // Condition IDs we've just redeemed on-chain. The Data API lags behind
  // on-chain state by a minute or two, so without this filter the sticky
  // redeemable logic below would resurrect the position on the very next
  // refresh and the "Claim" row would flash back into view right after
  // the user tapped it. Window is short on purpose: if the on-chain
  // redemption silently failed, the row comes back quickly so the user
  // sees something's wrong and can retry instead of being gaslit by a
  // fake "Claimed" that hides the real state for half an hour.
  // In-memory mirror of `PolymarketSuppressionService` for fast filter
  // lookups. Seeded from disk in `_loadSuppressedFromDisk()`.
  final Map<String, DateTime> _recentlyClaimedIds = {};
  static const _claimSuppressionWindow =
      PolymarketSuppressionService.suppressionWindow;

  /// Public hook for sell flows: mark a position as "user-removed" so the
  /// home Activity section drops it immediately, instead of the row hanging
  /// around for the seconds/minutes it takes the Polymarket Data API to
  /// reflect the on-chain settlement. Reuses the same suppression set as
  /// redeems and persists to Hive so the suppression survives app restart
  /// (the Data API can lag for several minutes).
  ///
  /// Accepts the CTF outcome [tokenId] (= `Position.asset`) which the
  /// frontend wrapper has at hand, and resolves it to a `conditionId`
  /// internally via the current openPositions list.
  void markPositionLocallyRemovedByToken(String tokenId) {
    if (tokenId.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final match =
        current.openPositions.where((p) => p.asset == tokenId).firstOrNull;
    if (match == null) return;
    _recentlyClaimedIds[match.conditionId] = DateTime.now();
    PolymarketSuppressionService.mark(match.conditionId);
    _setData(current.copyWith(
      openPositions: current.openPositions
          .where((p) => p.conditionId != match.conditionId)
          .toList(),
    ));
  }

  /// Tokens sold in the last 30s. Guards against a SECOND sell firing on a
  /// stale open-position tile: an instant fill empties the on-chain
  /// balance, but the Data API can lag and re-surface the position, so a
  /// re-tap would otherwise submit another order against balance 0 and get
  /// "not enough balance / allowance".
  final Map<String, DateTime> _recentlySoldTokens = {};

  void markTokenSold(String tokenId) {
    if (tokenId.isEmpty) return;
    _recentlySoldTokens[tokenId] = DateTime.now();
  }

  /// Tokens whose sell order has been accepted but whose on-chain settlement
  /// the Data API hasn't reflected yet. Drives the "Selling…" card state.
  final Map<String, DateTime> _pendingSaleTokens = {};

  /// Mark a position as "selling" so its card shows a pending state until the
  /// Data API confirms the settlement — instead of optimistically removing the
  /// row, which then popped back when the next refresh re-read the (lagging)
  /// Data API. Reconciled in [_fetchAllData]: the marker is dropped once the
  /// position leaves the API's list (sale settled) or after a short safety TTL
  /// so a sale that silently failed doesn't pin the card in selling mode.
  ///
  /// The sell sheet marks a token here from the moment the venue accepts a
  /// market sell until the trade is on chain (or the sale ends without a
  /// fill), so the Portfolio card says "Selling…" for exactly that span;
  /// it then calls [markSoldOptimistically] and [clearPositionSelling].
  void markPositionSelling(String tokenId) {
    if (tokenId.isEmpty) return;
    _pendingSaleTokens[tokenId] = DateTime.now();
    final current = state.valueOrNull;
    if (current == null) return;
    _setData(current.copyWith(
      pendingSaleTokens: _pendingSaleTokens.keys.toSet(),
    ));
  }

  /// The sale marked by [markPositionSelling] has an answer.
  void clearPositionSelling(String tokenId) {
    if (_pendingSaleTokens.remove(tokenId) == null) return;
    final current = state.valueOrNull;
    if (current == null) return;
    _setData(current.copyWith(
      pendingSaleTokens: _pendingSaleTokens.keys.toSet(),
    ));
  }

  /// A sale just landed on chain: read the account now and again while the
  /// Data API catches up (it shows a trade ~2-8 s after the match), rather
  /// than waiting for the next 5 s tick.
  void refreshAfterSale() {
    invalidateBalanceCache();
    unawaited(refresh().catchError((_) {}));
    for (final seconds in const [3, 6, 10]) {
      Future<void>.delayed(Duration(seconds: seconds), () {
        if (_disposed) return;
        invalidateBalanceCache();
        unawaited(refresh().catchError((_) {}));
      });
    }
  }

  bool wasRecentlySold(String tokenId) {
    final t = _recentlySoldTokens[tokenId];
    if (t == null) return false;
    if (DateTime.now().difference(t) > const Duration(seconds: 30)) {
      _recentlySoldTokens.remove(tokenId);
      return false;
    }
    return true;
  }

  /// Tokens whose FULL sell we've optimistically applied to state. The
  /// Data API keeps returning the position for up to ~a minute after the
  /// CLOB accepts a FOK sell (worst on 'delayed' fills), so without this
  /// filter the next refresh would resurrect the card the user just
  /// watched disappear. In-memory only on purpose: unlike a claim (whose
  /// suppression must survive restart because the API lags for minutes),
  /// a relaunch mid-window just briefly re-shows the row until the API
  /// catches up — and never hides real holdings.
  final Map<String, DateTime> _optimisticallySoldTokens = {};

  /// Bounded on purpose (same reconciliation TTL as `_pendingSaleTokens`,
  /// chosen for the identical Data-API-settlement lag): if the sell
  /// actually failed on-chain, the position is still in the API response
  /// once the window lapses and reappears naturally — we never trust the
  /// optimistic marker longer than this.
  static const _soldSuppressionWindow = Duration(seconds: 120);

  /// Optimistic sell reconciliation — called by the sell sheet the moment
  /// the CLOB ACCEPTS a FOK sell ('matched' OR 'delayed'), before the Data
  /// API has indexed anything:
  ///
  ///   - FULL sell (>= 95% of held size — same generous threshold as the
  ///     sheet's `sellingAll`, because "Sell Max" rounds 10 shares down to
  ///     ~9.96): drop the position from `openPositions` NOW and record a
  ///     suppression marker so the refresh loop doesn't resurrect it.
  ///   - PARTIAL sell: shrink the position in place, NO suppression — the
  ///     row should stay, just smaller. The next refresh may briefly
  ///     restore the API's stale larger size until it indexes the fill;
  ///     that errs on showing more (never hides shares) and self-corrects.
  ///
  /// Reconciliation story: `_fetchAllData` drops the marker as soon as the
  /// Data API stops returning the position (sale settled — the natural
  /// list is already correct) or after [_soldSuppressionWindow], whichever
  /// comes first. A sell that silently failed on-chain therefore brings
  /// the card back within the window instead of gaslighting the user.
  void markSoldOptimistically({
    required String tokenId,
    required double sharesSold,
  }) {
    if (tokenId.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final match =
        current.openPositions.where((p) => p.asset == tokenId).firstOrNull;
    if (match == null) return;

    final sellingAll = sharesSold >= match.size * 0.95;
    if (sellingAll) {
      _optimisticallySoldTokens[tokenId] = DateTime.now();
      _setData(current.copyWith(
        openPositions:
            current.openPositions.where((p) => p.asset != tokenId).toList(),
      ));
      return;
    }

    // Partial sell — rebuild with the sold shares removed. The package
    // Position has no copyWith, so mirror the full-constructor rebuild
    // used by the redeemable override in `_fetchAllData`. Value fields
    // scale proportionally so avgPrice / curPrice / percentPnl stay
    // invariant and the card's numbers remain internally consistent.
    final newSize = (match.size - sharesSold).clamp(0.0, double.infinity);
    final remainingFraction = match.size > 0 ? newSize / match.size : 0.0;
    final shrunk = Position(
      proxyWallet: match.proxyWallet,
      asset: match.asset,
      conditionId: match.conditionId,
      size: newSize,
      avgPrice: match.avgPrice,
      initialValue: match.initialValue * remainingFraction,
      currentValue: match.currentValue * remainingFraction,
      cashPnl: match.cashPnl * remainingFraction,
      percentPnl: match.percentPnl,
      totalBought: match.totalBought,
      realizedPnl: match.realizedPnl,
      percentRealizedPnl: match.percentRealizedPnl,
      curPrice: match.curPrice,
      redeemable: match.redeemable,
      mergeable: match.mergeable,
      title: match.title,
      slug: match.slug,
      icon: match.icon,
      eventSlug: match.eventSlug,
      outcome: match.outcome,
      outcomeIndex: match.outcomeIndex,
      oppositeOutcome: match.oppositeOutcome,
      oppositeAsset: match.oppositeAsset,
      endDate: match.endDate,
      negativeRisk: match.negativeRisk,
    );
    _setData(current.copyWith(
      openPositions: current.openPositions
          .map((p) => p.asset == tokenId ? shrunk : p)
          .toList(),
    ));
  }

  void _loadSuppressedFromDisk() {
    try {
      // Retroactive migration — wipe permanent-settled markers that
      // were written by the pre-fallback `redeemPosition` path. Users
      // who hit the wrong-contract-precheck bug had their Claim row
      // hidden forever even though the outcome tokens still sit in
      // their Safe. After this migration runs once per install,
      // those rows return and the user can re-claim via the new
      // cross-contract fallback.
      // ignore: discarded_futures
      PolymarketSuppressionService.migrateClearPermanentSettledOnce();
      final disk = PolymarketSuppressionService.snapshot();
      _recentlyClaimedIds.addAll(disk);
    } catch (_) {
      // Hive not ready / corrupted box — ignore; in-memory suppression
      // still works for the current session.
    }
  }

  /// Invalidate the on-chain balance cache so the next refresh forces a
  /// fresh RPC query. Call after sell/redeem/sweep so the polling loop
  /// inside the 30-second cache window actually sees the new pUSD/USDC.e
  /// balance instead of the stale pre-action snapshot.
  void invalidateBalanceCache() {
    _publicModel?.invalidateBalanceCache();
  }

  int _currentRefreshInterval = 5; // Adaptive: 3s near expiry, 5s normal
  bool _disposed = false;
  final _accountReadiness = PolymarketAccountReadiness();

  /// The Predictions account's one-time setup (wallet deployment and
  /// approvals) is done and nothing is setting it up now.
  bool get tradingReady => _accountReadiness.isReady;
  int _accountGeneration = 0;

  /// Stream of newly resolved positions (for UI notifications).
  final _resolvedController =
      StreamController<ResolvedPositionEvent>.broadcast();
  Stream<ResolvedPositionEvent> get resolvedPositions =>
      _resolvedController.stream;

  static const _storage = secureStorage;

  /// Safe wrapper around `state = AsyncData(...)`. Writing to a disposed
  /// AutoDisposeAsyncNotifier throws — and since a lot of our state updates
  /// happen after long-running async work (placeOrder, enableTrading, refresh),
  /// the user can easily navigate away before we get here. We silently drop
  /// the update in that case instead of crashing the app.
  void _setData(PolymarketTradingState newState) {
    if (_disposed) return;
    try {
      state = AsyncData(newState);
    } catch (_) {
      // Riverpod threw after disposal — nothing to update, ignore.
    }
  }

  @override
  Future<PolymarketTradingState> build() async {
    final generation = ++_accountGeneration;
    _disposed = false;
    unawaited(VenueAnalytics.warmUp());
    // keepAlive prevents the autoDispose tear-down when the only
    // widget reading this provider unmounts — without it, scrolling
    // the home carousel away from the USDC page disposes the
    // notifier, and scrolling back triggers a full re-init from
    // the mnemonic (a few seconds of `valueOrNull == null`,
    // surfacing as USDC $0.00). The provider itself only fully
    // tears down when the user explicitly invalidates it (wallet
    // switch via home_wallet_switcher) or the app exits.
    ref.keepAlive();
    ref.onDispose(() {
      _disposed = true;
      _refreshTimer?.cancel();
      _client?.close();
      _publicModel?.dispose();
      _resolvedController.close();
    });

    // Hydrate "recently sold/redeemed" suppression from disk so positions
    // stay hidden across app restart while the Polymarket Data API catches
    // up on the on-chain settlement.
    _loadSuppressedFromDisk();

    // Derive ETH wallet from the SPENDING wallet's mnemonic — not
    // the active wallet's. Polymarket positions live on a Safe whose
    // owner key is the spending EOA, so the trading provider must
    // pin to that wallet regardless of which carousel page the user
    // is viewing. Routing through `activeWalletId` here means a user
    // parked on a hardware/savings page (no mnemonic on disk) sees
    // "Could not decrypt wallet" even though their Polymarket Safe
    // is fine; their xpub-only wallet just isn't the right key.
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);

    if (spending == null) {
      return const PolymarketTradingState(balanceKnown: false);
    }
    // Nothing derives while the session is locked, passkey wallets
    // included. A build behind the lock returns the empty state and
    // builds again once the session unlocks, so the USDC balance and
    // proxy address fill in right after unlock.
    if (!watchSessionUnlock(ref)) {
      return const PolymarketTradingState(balanceKnown: false);
    }

    try {
      // `resolveBip39MnemonicFor` routes passkey wallets through Breez
      // SDK (`Passkey.getWallet` → entropy → BIP39) and stored
      // wallets through `AuthModel.readMnemonic`. Both return real
      // BIP39 words for the wallet’s versioned EVM derivation.
      final mnemonic = await resolveBip39MnemonicFor(spending,
          access: SeedAccess.automatic, session: ref.read(seedSessionProvider));
      if (mnemonic == null) {
        return const PolymarketTradingState(
          balanceKnown: false,
          error: 'Could not decrypt spending wallet mnemonic',
        );
      }
      final walletId = spending.id;
      _spendingWalletId = walletId;

      // Preserve the wallet’s seed format at m/44'/60'/0'/0/0.
      final wallet = await EvmWalletDerivation.deriveWalletAsync(
          mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);
      _privateKey = wallet.privateKey;

      // Create initial client with EOA for credential operations
      _client = PolymarketClient.withPrivateKey(
        privateKey: wallet.privateKey,
        walletAddress: wallet.address,
      );

      // Public model for positions/portfolio (Data API, no auth needed)
      _publicModel = PolymarketModel();

      // V2 deposit-wallet address — pure offline derivation from the EOA
      // (Solady ERC-1967 CREATE2 via the deposit-wallet factory). No RPC,
      // no profile API, no storage lookup needed: the address is fully
      // determined by the EOA + the known factory + the known impl.
      //
      // We deliberately do NOT use the profile API or storage for the V2
      // path: the profile API returns the user's V1 Gnosis Safe address
      // for accounts that pre-date the V2 cutover, and storage caches
      // whichever address was derived in the previous session — both of
      // which can be the WRONG (V1) address, which would make every
      // order's `maker` mismatch the deposit wallet we actually deployed.
      // Re-derive from EOA → deterministic V2 wallet, every session.
      String? proxyWallet;
      final onboarding = PolymarketOnboardingService();
      try {
        proxyWallet =
            await onboarding.resolveDepositWalletAddress(wallet.address);
        // A confirmed answer: overwrite any cached V1 Safe (or wrongly
        // guessed) address so the rest of the provider reads it too.
        await _storage.write(key: _proxyKey(walletId), value: proxyWallet);
      } catch (_) {
        // Polygon gave no answer. Keep the last confirmed wallet. Older
        // builds stored the never-used UUPS guess on exactly this failure,
        // so a cached UUPS address is dropped rather than trusted (a real
        // UUPS trader is confirmed again by the relayer on the next resolve).
        final cached = await _storage.read(key: _proxyKey(walletId));
        final uups = onboarding.deriveDepositWalletAddress(wallet.address);
        if (cached != null &&
            cached.isNotEmpty &&
            cached.toLowerCase() != uups.toLowerCase()) {
          proxyWallet = cached;
        } else if (cached != null) {
          await _storage.delete(key: _proxyKey(walletId));
        }
      }
      // Prove, once per account, that this hot wallet owns its Polymarket
      // signer and trading wallet so builder-fee trades are credited to
      // the user (VenueOwnerLinkService). Silent, never blocks, hot only.
      if (!spending.isHardware) {
        try {
          unawaited(VenueOwnerLinkService.ensureLinked(
            venue: VenueOwnerLinkService.polymarket,
            key: _hotPolymarketCredentials(wallet.privateKey),
            tradingAddress: (proxyWallet != null && proxyWallet.isNotEmpty
                    ? proxyWallet
                    : wallet.address)
                .toLowerCase(),
          ));
        } catch (_) {
          // Best-effort only.
        }
      }
      // Load or create API credentials (with nonce for POLY_NONCE header)
      _CredentialsWithNonce? credsWithNonce = await _loadCredentials(walletId,
          ownerAddress: wallet.address,
          version: spending.evmDerivationVersion,
          depositWallet: proxyWallet);

      if (credsWithNonce == null) {
        try {
          credsWithNonce = await _deriveOrCreateApiKey(funder: proxyWallet);
          if (credsWithNonce != null) {
            await _saveCredentials(walletId, credsWithNonce.credentials,
                nonce: credsWithNonce.nonce);
          }
        } catch (e) {
          // Credentials stay null and trading degrades gracefully. Offline /
          // timeout failures are EXPECTED (no internet, stalled network) —
          // they're not bugs and would spam Error Tracking on every retry, so
          // only report genuinely unexpected provisioning failures.
          if (!_isOfflineError(e)) {
            TrackingService.recordCrash(e, null,
                reason: 'polymarket_credential_provisioning');
          }
        }
      }

      final credentials = credsWithNonce?.credentials;
      if (credsWithNonce != null) {
        _apiNonce = credsWithNonce.nonce;
      }

      if (credentials != null) {
        _client!.clob.auth?.setCredentials(credentials);
        _backendService = _createBackendService(credentials, wallet.address,
            funder: proxyWallet);

        // One-shot CLOB allowance cache refresh per session. The CLOB
        // caches each wallet's balance/allowance snapshot — without an
        // explicit `/balance-allowance/update` call the cache can be
        // hours stale, blocking orders even when on-chain approvals are
        // set. signature_type=3 (POLY_1271) matches the V2 deposit-wallet
        // order sigType we sign.
        if (proxyWallet != null && proxyWallet.isNotEmpty) {
          // ignore: discarded_futures
          _backendService!
              .updateBalanceAllowance(assetType: 'COLLATERAL', signatureType: 3)
              .then((_) => _devLog('[pm-init] balance-allowance/update OK'))
              .catchError((Object e) =>
                  _devLog('[pm-init] balance-allowance/update threw: $e'));
        }
      }

      // Recreate client with funder (proxy wallet) for Safe order signing
      if (proxyWallet != null &&
          proxyWallet.isNotEmpty &&
          credentials != null) {
        _client?.close();
        _client = PolymarketClient.authenticated(
          credentials: credentials,
          funder: proxyWallet,
          privateKey: wallet.privateKey,
        );
      }

      final isAuth = credentials != null ||
          (proxyWallet != null && proxyWallet.isNotEmpty);

      // Fetch data — don't let a network failure hide valid credentials
      PolymarketTradingState data;
      try {
        data = await _fetchAllData(
          wallet.address,
          proxyWallet: proxyWallet,
        );
      } catch (_) {
        // Data fetch failed but credentials are valid — still authenticated
        data = PolymarketTradingState(
          walletAddress: wallet.address,
          proxyWalletAddress: proxyWallet,
          balanceKnown: false,
        );
      }

      // Auto-refresh every 5s by default so open positions feel live;
      // _adjustRefreshRate drops this to 3s for near-expiry markets.
      _refreshTimer = Timer.periodic(
        Duration(seconds: _currentRefreshInterval),
        (_) => _silentRefresh(),
      );

      // Task #170: pUSD is now the resting state. We no longer
      // background-normalize the Safe's stables. Deposits (BTC →
      // USDC.e via Orchestra) trigger a one-shot wrap to pUSD on
      // delivery; withdrawals (cashout to BTC) unwrap pUSD on demand
      // inside `withdrawUsdc`. Won/sold proceeds land as pUSD and
      // stay there. The displayed USDC balance is the SUM of pUSD +
      // USDC.e + native USDC (see `getOnChainUsdcBalance`) so any
      // mid-flow split is invisible to the user.

      // A predicted address exists before the wallet is deployed. Always
      // verify deployment and approvals once per account session; the
      // onboarding service skips operations already complete on-chain.
      // Use the event queue so build's account state is published first.
      Future<void>(() async {
        if (_disposed || generation != _accountGeneration) return;
        try {
          await enableTrading();
        } catch (_) {
          // The next explicit deposit/setup call retries a failed setup.
        }
        if (_disposed || generation != _accountGeneration) return;
        // A deposit that landed while the app was closed is still USDC.e.
        await wrapIdleUsdcE(trigger: 'open');
        if (_disposed || generation != _accountGeneration) return;
        // A prediction an earlier session left unanswered is looked up now,
        // not on the person's next tap.
        await reconcilePendingOrders();
      });

      return data.copyWith(isAuthenticated: isAuth);
    } catch (e) {
      return PolymarketTradingState(
          balanceKnown: false, error: 'Authentication failed: $e');
    }
  }

  Future<_CredentialsWithNonce?> _loadCredentials(
    String walletId, {
    required String ownerAddress,
    required EvmDerivationVersion version,
    String? depositWallet,
  }) async {
    try {
      final json = await _storage.read(key: _credsKey(walletId));
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      if (!PolymarketCredentialIdentity.matches(map,
          ownerAddress: ownerAddress, version: version)) {
        return null;
      }
      final boundAddress = PolymarketClobAuth.cachedAddress(map,
          ownerAddress: ownerAddress, depositWallet: depositWallet);
      if (boundAddress == null) return null;
      _apiKeyBoundAddress = boundAddress;
      return _CredentialsWithNonce(
        credentials: ApiCredentials(
          apiKey: map['apiKey'] as String,
          secret: map['secret'] as String,
          passphrase: map['passphrase'] as String,
        ),
        nonce: (map['nonce'] as int?) ?? 0,
      );
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveCredentials(
    String walletId,
    ApiCredentials credentials, {
    int nonce = 0,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Predictions account changed');
    }
    final wallet = ref
        .read(settingsProvider)
        .wallets
        .where((wallet) => wallet.id == walletId)
        .firstOrNull;
    final privateKey = _privateKey;
    if (wallet == null || privateKey == null || _spendingWalletId != walletId) {
      return;
    }
    final identity = PolymarketCredentialIdentity.metadata(
      ownerAddress: HdWallet.getAddress(privateKey),
      version: wallet.evmDerivationVersion,
    );
    try {
      final json = jsonEncode({
        'apiKey': credentials.apiKey,
        'secret': credentials.secret,
        'passphrase': credentials.passphrase,
        'nonce': nonce,
        'authAddress': _apiKeyBoundAddress ?? identity['ownerAddress'],
        ...identity,
      });
      await _storage.write(key: _credsKey(walletId), value: json);
    } catch (_) {}
    if (isCurrent != null && !isCurrent()) {
      throw StateError('Predictions account changed');
    }
  }

  String? _credentialsWalletId() =>
      polymarketCredentialsWalletId(ref.read(settingsProvider),
          pinnedWalletId: _spendingWalletId);

  /// The wallet orders are signed with. `placeOrder` review intents bind it
  /// (Wallet Hardening Phase 1b.4).
  String? get signingWalletId => _credentialsWalletId();

  /// L2 authentication uses the address that provisioned the API key.
  /// New credentials belong to the owner EOA; the deposit wallet remains
  /// the order's maker/signer under the separate POLY_1271 order protocol.
  PolymarketBackendService _createBackendService(
    ApiCredentials creds,
    String eoaAddress, {
    String? funder,
  }) {
    final polyAddress = _apiKeyBoundAddress ?? eoaAddress;
    return PolymarketBackendService(
      apiKey: creds.apiKey,
      secret: creds.secret,
      passphrase: creds.passphrase,
      walletAddress: polyAddress,
    );
  }

  Future<_CredentialsWithNonce?> _deriveOrCreateApiKey({
    String? funder,
    bool Function()? isCurrent,
  }) async {
    void checkAccount() {
      if (isCurrent != null && !isCurrent()) {
        throw StateError('Predictions account changed');
      }
    }

    checkAccount();
    final privateKey = _privateKey;
    if (privateKey == null) {
      return null;
    }

    String? eoaAddress = state.valueOrNull?.walletAddress;
    if (eoaAddress == null) {
      try {
        eoaAddress = HdWallet.getAddress(privateKey);
      } catch (e) {
        return null;
      }
    }

    final headers = await PolymarketClobAuth.headers(
      credentials: _hotPolymarketCredentials(privateKey),
      address: eoaAddress,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    checkAccount();
    final result = await PolymarketClobAuth().deriveOrCreate(headers);
    checkAccount();
    _apiKeyBoundAddress = eoaAddress;
    return _CredentialsWithNonce(credentials: result, nonce: 0);
  }

  Future<PolymarketTradingState> _fetchAllData(
    String eoaAddress, {
    String? proxyWallet,
  }) async {
    final model = _publicModel!;

    // All Polymarket data is indexed by the proxy wallet (Safe), not EOA.
    // EOA is only used for signing — never for data queries.
    final addr = proxyWallet;

    // Fetch each independently — don't let one failure kill the others.
    // A balance that could not be read stays 0 but is marked unknown.
    var balanceRead = addr != null;
    final results = await Future.wait([
      addr != null
          ? model.getPositions(addr).catchError((_) => <Position>[])
          : Future.value(<Position>[]),
      (_backendService?.getOpenOrders() ?? Future.value(<Order>[]))
          .catchError((_) => <Order>[]),
      addr != null
          ? model.getOnChainUsdcBalance(addr).catchError((_) {
              balanceRead = false;
              return 0.0;
            })
          : Future.value(0.0),
      addr != null
          ? model.getPortfolioTotalValue(addr).catchError((_) => 0.0)
          : Future.value(0.0),
      addr != null
          ? model.getClosedPositions(addr).catchError((_) => <ClosedPosition>[])
          : Future.value(<ClosedPosition>[]),
    ]);

    var positions = results[0] as List<Position>;
    final orders = results[1] as List<Order>;
    final onChainUsdc = results[2] as double;
    // The settled rows held to their result (the state's closedPositions,
    // which the history reads as Won / Lost) and, for everything below
    // (the claim bookkeeping, the on-chain scan, the P&L), every settled
    // row as before: the ones sold before their result too.
    final heldToResult = results[4] as List<ClosedPosition>;
    final closed = [...heldToResult, ...model.closedSoldPositions];

    // Drop stale entries from the "recently claimed" suppression set so
    // they don't hide a position forever if the Data API somehow never
    // reflects the claim (e.g. on-chain tx succeeded but closedPositions
    // never catches up — genuinely shouldn't happen, but don't trust it).
    final now = DateTime.now();
    _recentlyClaimedIds.removeWhere(
      (_, claimedAt) => now.difference(claimedAt) > _claimSuppressionWindow,
    );

    // Sticky redeemable: once a position is seen as redeemable, remember it
    // so the Data API's inconsistent flag doesn't cause flickering.
    for (final p in positions) {
      if (p.redeemable) {
        _knownRedeemableIds.add(p.conditionId);
      }
    }
    // Remove from known redeemable if it's now in closed positions (fully
    // claimed). Also clear the recently-claimed suppression — the Data
    // API has caught up, so there's no reason to hide the row anymore.
    for (final c in closed) {
      _knownRedeemableIds.remove(c.conditionId);
      _recentlyClaimedIds.remove(c.conditionId);
      // Position is fully settled — drop the auto-claim guard so a
      // future re-resolved condition (very unusual but possible on
      // markets that get unresolved + re-finalised) can still be
      // auto-claimed on the next refresh.
      _autoClaimedIds.remove(c.conditionId);
    }

    // Suppression disabled per user directive — every position the
    // Data API returns is surfaced. The previous "filter recently-
    // claimed" / "filter permanent-settled" branches were a frequent
    // source of "I claimed but nothing arrived" bugs (the row would
    // vanish optimistically while the on-chain claim silently
    // failed). Keeping positions visible lets the user retry until
    // the Data API itself removes them via `closedPositions`.

    // On-chain claimable scanner — DISCOVERY-LAYER PATCH.
    //
    // The Polymarket Data API's `redeemable: bool` lags or fails on
    // some positions (case in point: 2026-05-14 tx 0xb3abf55e on
    // Safe 0x13AE…). When that happens the Claim button never
    // appears and the user can't trigger a redeem even though they
    // demonstrably hold the winning outcome tokens on-chain.
    //
    // Mitigation: after fetching, batch-query CTF.balanceOfBatch
    // against every position's `pos.asset` (winning-side positionId)
    // for the Safe. Any non-zero balance whose underlying market
    // looks resolved (`curPrice >= 0.99`, i.e. the winning side
    // settled at $1) gets `redeemable` flipped to true locally,
    // bypassing the API.
    //
    // Costs one extra eth_call per refresh tick — cheap; balanceOf
    // is a static read.
    if (proxyWallet != null) {
      // Collect positionIds from BOTH open and closed positions. The
      // Data API moves a position to `closedPositions` aggressively
      // whenever it sees any redeem-event attempt — even one the
      // contract rejected with payout=0. If the actual on-chain
      // outcome tokens weren't burned (e.g. pre-fix relayer rejected
      // PRECHECK_SKIPPED so nothing went on-chain), the Safe still
      // holds the tokens. Without scanning closedPositions too, those
      // get permanently dropped from the Claim rail.
      final openAssetIds = positions
          .where((p) => p.asset.isNotEmpty)
          .map((p) => p.asset)
          .toList(growable: false);
      final closedAssetIds = closed
          .where((p) => p.asset.isNotEmpty)
          .map((p) => p.asset)
          .toList(growable: false);
      final allAssetIds =
          <String>{...openAssetIds, ...closedAssetIds}.toList(growable: false);
      if (allAssetIds.isNotEmpty) {
        try {
          final balances = await PolymarketOnboardingService()
              .readCtfBalancesBatch(
                  positionIds: allAssetIds, owner: proxyWallet);

          final finalizedPayouts = <String, double>{};
          for (final p
              in positions.where((p) => p.curPrice >= .99 && !p.redeemable)) {
            if ((balances[p.asset] ?? BigInt.zero) == BigInt.zero) continue;
            final payout = await PolymarketOnboardingService()
                .settledPayout(p.conditionId, p.outcomeIndex);
            if (payout != null) finalizedPayouts[p.asset] = payout;
          }

          // Pass 1: open-position override.
          positions = positions.map((p) {
            final bal = balances[p.asset] ?? BigInt.zero;
            final looksWon = finalizedPayouts[p.asset] == 1;
            final shouldOverride =
                !p.redeemable && bal > BigInt.zero && looksWon;
            if (!shouldOverride &&
                !(_knownRedeemableIds.contains(p.conditionId) &&
                    !p.redeemable)) {
              return p;
            }
            return Position(
              proxyWallet: p.proxyWallet,
              asset: p.asset,
              conditionId: p.conditionId,
              size: p.size,
              avgPrice: p.avgPrice,
              initialValue: p.initialValue,
              currentValue: p.currentValue,
              cashPnl: p.cashPnl,
              percentPnl: p.percentPnl,
              totalBought: p.totalBought,
              realizedPnl: p.realizedPnl,
              percentRealizedPnl: p.percentRealizedPnl,
              curPrice: p.curPrice,
              redeemable: true,
              mergeable: p.mergeable,
              title: p.title,
              slug: p.slug,
              icon: p.icon,
              eventSlug: p.eventSlug,
              outcome: p.outcome,
              outcomeIndex: p.outcomeIndex,
              oppositeOutcome: p.oppositeOutcome,
              oppositeAsset: p.oppositeAsset,
              endDate: p.endDate,
              negativeRisk: p.negativeRisk,
            );
          }).toList();

          // Pass 2: resurrect closed positions that still have
          // on-chain balance. The Data API thinks they're done; the
          // chain disagrees. Only a result that is on chain counts, and
          // only what the wallet holds now: see [heldClosedClaims].
          final openConditionIds = positions.map((p) => p.conditionId).toSet();
          final closedPayouts = <String, double>{};
          for (final c in closed) {
            if (c.asset.isEmpty) continue;
            if (openConditionIds.contains(c.conditionId)) continue;
            if ((balances[c.asset] ?? BigInt.zero) < _kClaimDustUnits) {
              continue;
            }
            final payout = await PolymarketOnboardingService()
                .settledPayout(c.conditionId, c.outcomeIndex);
            if (payout != null) closedPayouts[c.asset] = payout;
          }
          positions = [
            ...positions,
            ...heldClosedClaims(
              closed: closed,
              openConditionIds: openConditionIds,
              balances: balances,
              settledPayouts: closedPayouts,
              negRiskConditionIds: model.closedNegRiskConditionIds,
            ),
          ];
        } catch (_) {
          // RPC failure — fall back to API trust silently. The next
          // refresh tick will retry.
        }
      }
    }

    // Optimistic full-sell suppression — the refresh-loop counterpart of
    // `markSoldOptimistically`. First reconcile the markers: drop any the
    // Data API has caught up on (position no longer returned → the sale
    // settled, the natural list is already correct) and any older than
    // the bounded window (the sell may have silently failed on-chain —
    // let the position reappear rather than hide real holdings). Whatever
    // survives is still lagging: filter those positions out so the
    // just-sold card doesn't resurrect between the optimistic removal
    // and the API indexing the fill (up to ~a minute on 'delayed' FOKs).
    _optimisticallySoldTokens.removeWhere((tok, at) =>
        now.difference(at) > _soldSuppressionWindow ||
        !positions.any((p) => p.asset == tok));
    if (_optimisticallySoldTokens.isNotEmpty) {
      positions = positions
          .where((p) => !_optimisticallySoldTokens.containsKey(p.asset))
          .toList();
    }

    // A claim opens only once the result is on chain. The Data API flags a
    // position `redeemable` when the market resolves, minutes before the
    // result is reported to the Conditional Tokens contract; a redeem in
    // that gap is refused (see `_redeemPosition`). Such a position stays
    // in its awaiting state ("You won · Ready to claim soon") until then.
    final finality = <String, bool?>{};
    for (final p in positions.where((p) => p.redeemable)) {
      finality[p.conditionId] ??= await _conditionFinalized(p.conditionId);
    }
    positions = holdUntilFinalized(positions, finality);

    // Compute PnL from open + closed positions
    double totalPnl = 0;
    double totalInvested = 0;
    for (final p in positions) {
      totalPnl += p.cashPnl;
      totalInvested += p.initialValue;
    }
    for (final p in closed) {
      totalPnl += p.cashPnl;
      totalInvested += p.initialValue;
    }
    final totalPnlPercent =
        totalInvested > 0 ? (totalPnl / totalInvested) * 100 : 0.0;

    // Reconcile "Selling…" markers: drop a token once the Data API stops
    // returning its position (the sale settled — the card now disappears for
    // real) or after a short safety TTL (a sale that silently failed must not
    // pin the card in selling mode forever). While the position still shows
    // (the Data API lags on-chain settlement by seconds–minutes) the marker
    // stays, so the card holds its selling state instead of vanishing and
    // popping back.
    final nowSale = DateTime.now();
    _pendingSaleTokens.removeWhere((tok, at) =>
        nowSale.difference(at) > const Duration(seconds: 120) ||
        !positions.any((p) => p.asset == tok));

    return PolymarketTradingState(
      usdcBalance: onChainUsdc,
      totalPnl: totalPnl,
      totalPnlPercent: totalPnlPercent,
      openPositions: positions,
      closedPositions: heldToResult,
      openOrders: orders,
      walletAddress: eoaAddress,
      proxyWalletAddress: proxyWallet,
      pendingSaleTokens: _pendingSaleTokens.keys.toSet(),
      clearingConditionIds: _clearingIdsSnapshot(),
      balanceKnown: balanceRead,
    );
  }

  /// Recently-claimed conditions still inside the spinner window — the
  /// resolved rail renders these locked as "Clearing…" instead of a
  /// tappable Claim/Clear. Positions are NOT filtered (the row hiding
  /// that used to do that caused "I claimed but nothing arrived" bugs);
  /// the row stays visible, just honest about being in flight. After
  /// [_clearingSpinnerWindow] the button returns so a silently-dropped
  /// claim is retryable (an already-settled retry lands on the friendly
  /// PRECHECK_SKIPPED path).
  Set<String> _clearingIdsSnapshot() {
    final now = DateTime.now();
    return {
      for (final e in _recentlyClaimedIds.entries)
        if (now.difference(e.value) <= _clearingSpinnerWindow) e.key,
    };
  }

  static const _clearingSpinnerWindow = Duration(minutes: 5);

  Future<void> _silentRefresh() async {
    // Foreground gate: the periodic timer keeps firing while the app
    // is backgrounded (iOS grants minutes of grace, Android longer) —
    // each tick fans out to 8+ network calls for a UI nobody can see.
    // `lifecycleState` is null until the first lifecycle event lands;
    // treat that as foreground so a cold start still refreshes.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return;
    }
    // Overlap guard: `_fetchAllData` can outlive a 3s tick on slow
    // networks — without this, ticks stack and the fan-out multiplies.
    if (_refreshInFlight) return;
    final current = state.valueOrNull;
    if (current == null ||
        current.walletAddress == null ||
        _publicModel == null) {
      return;
    }
    _refreshInFlight = true;
    try {
      // The proxy address is resolved ONCE in build() and never
      // re-pointed here. This block used to overwrite the in-memory AND
      // persisted proxy from the profile API on every 3-60s tick, which
      // defeated build()'s explicit guard against that API (it returns
      // the V1 Gnosis Safe for pre-cutover accounts, making every
      // subsequent order's maker mismatch) — and it persisted under the
      // ACTIVE wallet id while build() keys by the spending wallet, so
      // viewing a non-spending wallet corrupted the wrong key.
      final proxy = current.proxyWalletAddress;

      final data = await _fetchAllData(
        current.walletAddress!,
        proxyWallet: proxy,
      );

      // Detect newly resolved positions (was not redeemable, now is).
      final prevIds = current.openPositions
          .where((p) => !p.redeemable)
          .map((p) => p.conditionId)
          .toSet();
      for (final p in data.openPositions) {
        if (p.redeemable && prevIds.contains(p.conditionId)) {
          final won = p.curPrice >= 0.5;
          final payout = won ? p.size : 0.0;
          if (!_resolvedController.isClosed) {
            _resolvedController.add(ResolvedPositionEvent(
              title: p.title,
              outcome: p.outcome,
              won: won,
              payout: payout,
              eventSlug: p.eventSlug,
              conditionId: p.conditionId,
            ));
          }
        }
      }

      // Adaptive polling: speed up when positions are expiring soon
      _adjustRefreshRate(data.openPositions);

      // A refresh whose balance read failed keeps the last balance that
      // was read, rather than reading as 0 until the next tick.
      final keepBalance = !data.balanceKnown && current.balanceKnown;
      _setData(data.copyWith(
        isAuthenticated: current.isAuthenticated,
        isPlacingOrder: current.isPlacingOrder,
        usdcBalance: keepBalance ? current.usdcBalance : null,
        balanceKnown: keepBalance ? true : null,
      ));

      // Record USDC balance snapshot for analytics charts
      if (data.usdcBalance > 0) {
        UsdcBalanceHistoryService.record(data.usdcBalance);
      }

      // Auto-claim DISABLED — user directive: manual claims only.
      // The user must tap Claim explicitly on each resolved position.
      //
      // Task #170: background normalize REMOVED. pUSD is now the
      // resting state — don't touch at-rest balances. The deposit
      // path (BTC → USDC.e via Orchestra) fires a one-shot wrap to
      // pUSD on delivery via `wrapIncomingUsdcEToPusd`; the cashout
      // path (`withdrawUsdc`) unwraps pUSD on demand. Won/sold
      // proceeds land as pUSD and stay there.
      //
      // BTC-route queue drainer also DISABLED (task #129). No new
      // entries are enqueued anymore. Any pre-existing queue entries
      // left over from prior installs stay parked on disk — they
      // will not auto-fire.
    } catch (_) {
      // Silent — don't break UI on background refresh failure
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Overlap guard for [_silentRefresh] — see comment at its top.
  bool _refreshInFlight = false;

  /// Less than this many outcome-token units (6 decimals: 0.01 share)
  /// is dust worth under a cent whatever the result, such as what a
  /// "sell all" leaves behind. It never makes a claim of its own.
  static final BigInt _kClaimDustUnits = BigInt.from(10000);

  /// Closed rows the wallet still holds outcome tokens for, put back on
  /// the Claim rail as open positions. The Data API closes a position on
  /// a redeem attempt the contract may have rejected, and closes one sold
  /// mid-market too, leaving the dust the sale did not take.
  ///
  /// A row comes back only when its result is on chain ([settledPayouts],
  /// keyed by token id: the payout per share, 0 for a lost side) and the
  /// wallet holds at least 0.01 share. Its size and value are the tokens
  /// held now ([balances]), never the closed row's lifetime size: a CS2
  /// position sold for $1.95 on 5 Oct 2026 left 0.0029 shares and came
  /// back as "Claim $2.07" for 2.07 shares, before the game's result was
  /// even reported. [negRiskConditionIds] routes a neg-risk market's
  /// claim through the neg-risk adapter.
  @visibleForTesting
  static List<Position> heldClosedClaims({
    required List<ClosedPosition> closed,
    required Set<String> openConditionIds,
    required Map<String, BigInt> balances,
    required Map<String, double> settledPayouts,
    Set<String> negRiskConditionIds = const {},
  }) {
    final out = <Position>[];
    final seen = <String>{...openConditionIds};
    for (final c in closed) {
      if (c.asset.isEmpty || seen.contains(c.conditionId)) continue;
      final bal = balances[c.asset] ?? BigInt.zero;
      if (bal < _kClaimDustUnits) continue;
      final payout = settledPayouts[c.asset];
      if (payout == null) continue;
      seen.add(c.conditionId);
      final held = bal.toDouble() / 1e6;
      final cost = held * c.avgPrice;
      final value = held * payout;
      out.add(Position(
        proxyWallet: c.proxyWallet,
        asset: c.asset,
        conditionId: c.conditionId,
        size: held,
        avgPrice: c.avgPrice,
        initialValue: cost,
        currentValue: value,
        cashPnl: value - cost,
        percentPnl: cost > 0 ? (value - cost) / cost * 100 : 0.0,
        totalBought: c.size,
        realizedPnl: c.cashPnl,
        percentRealizedPnl: c.percentPnl,
        curPrice: payout,
        redeemable: true,
        mergeable: false,
        title: c.title,
        slug: c.slug,
        icon: c.icon,
        eventSlug: c.eventSlug,
        outcome: c.outcome,
        outcomeIndex: c.outcomeIndex,
        oppositeOutcome: '',
        oppositeAsset: '',
        endDate: c.resolutionDate?.toIso8601String() ?? '',
        negativeRisk: negRiskConditionIds.contains(c.conditionId),
      ));
    }
    return out;
  }

  /// Whether a read of the wallet's [held] outcome tokens for [ids] (both
  /// sides of a position) found less than [_kClaimDustUnits] of each, so a
  /// redeem would move nothing. A read missing any id (an RPC failure)
  /// is not proof of that.
  @visibleForTesting
  static bool nothingHeldToClaim(List<String> ids, Map<String, BigInt> held) =>
      ids.isNotEmpty &&
      ids.every((id) => held.containsKey(id)) &&
      ids.every((id) => held[id]! < _kClaimDustUnits);

  /// [positions] with `redeemable` cleared where [finalized] says the
  /// condition's result is not on chain yet (false). Unknown (null, an
  /// RPC failure) keeps the flag: a claim is never blocked on a blip, and
  /// the redeem checks again before it sends anything.
  @visibleForTesting
  static List<Position> holdUntilFinalized(
      List<Position> positions, Map<String, bool?> finalized) {
    if (!finalized.containsValue(false)) return positions;
    return [
      for (final p in positions)
        if (p.redeemable && finalized[p.conditionId] == false)
          _withRedeemable(p, false)
        else
          p,
    ];
  }

  static Position _withRedeemable(Position p, bool redeemable) => Position(
        proxyWallet: p.proxyWallet,
        asset: p.asset,
        conditionId: p.conditionId,
        size: p.size,
        avgPrice: p.avgPrice,
        initialValue: p.initialValue,
        currentValue: p.currentValue,
        cashPnl: p.cashPnl,
        percentPnl: p.percentPnl,
        totalBought: p.totalBought,
        realizedPnl: p.realizedPnl,
        percentRealizedPnl: p.percentRealizedPnl,
        curPrice: p.curPrice,
        redeemable: redeemable,
        mergeable: p.mergeable,
        title: p.title,
        slug: p.slug,
        icon: p.icon,
        eventSlug: p.eventSlug,
        outcome: p.outcome,
        outcomeIndex: p.outcomeIndex,
        oppositeOutcome: p.oppositeOutcome,
        oppositeAsset: p.oppositeAsset,
        endDate: p.endDate,
        negativeRisk: p.negativeRisk,
      );

  /// Conditions whose result is on chain. A result once reported is
  /// final, so it is remembered for the session.
  final Set<String> _finalizedConditions = {};

  /// When a condition was last read as not finalised: re-read at most
  /// every 20 s (the awaiting poll's pace), not on every 5 s refresh.
  final Map<String, DateTime> _unfinalizedCheckedAt = {};

  Future<bool?> _conditionFinalized(String conditionId) async {
    if (_finalizedConditions.contains(conditionId)) return true;
    final checked = _unfinalizedCheckedAt[conditionId];
    if (checked != null &&
        DateTime.now().difference(checked) < const Duration(seconds: 20)) {
      return false;
    }
    final finalized =
        await PolymarketOnboardingService().isConditionFinalized(conditionId);
    if (finalized == true) {
      _finalizedConditions.add(conditionId);
      _unfinalizedCheckedAt.remove(conditionId);
    } else if (finalized == false) {
      _unfinalizedCheckedAt[conditionId] = DateTime.now();
    }
    return finalized;
  }

  /// Whether [p] has ended and is waiting for its result: not redeemable
  /// yet, and its end (a short round's own, from the slug; else the
  /// market's end date) passed within the last 6 hours. Past that the
  /// result is late enough (a dispute, a postponed game) that the normal
  /// pace is enough.
  @visibleForTesting
  static bool awaitingResolution(Position p, DateTime now) {
    if (p.redeemable) return false;
    final round = RegExp(r'-(5|15)m-(\d{10})$').firstMatch(p.eventSlug);
    final DateTime? end = round != null
        ? DateTime.fromMillisecondsSinceEpoch(int.parse(round[2]!) * 1000,
                isUtc: true)
            .add(Duration(minutes: int.parse(round[1]!)))
        : DateTime.tryParse(p.endDate ?? '');
    if (end == null || end.isAfter(now)) return false;
    return now.difference(end) < const Duration(hours: 6);
  }

  /// Adjust polling rate based on the closest position expiry. Three
  /// tiers, picked by the *most urgent* open position:
  ///   - <60 min to resolve  → 3s   (hourly / soon-to-resolve markets)
  ///   - otherwise           → 5s   (default; open positions feel live)
  /// Without the 1s tier, sub-5-minute markets felt frozen — by the
  /// time the user's PnL chip caught up the position had already
  /// resolved. Polymarket's Data API caches at ~1s anyway so we won't
  /// burn through their rate limits.
  void _adjustRefreshRate(List<Position> positions) {
    final now = DateTime.now();
    int? minMinutesToExpiry;
    for (final p in positions) {
      if (p.redeemable) continue;
      if (p.endDate != null && p.endDate!.isNotEmpty) {
        try {
          final end = DateTime.parse(p.endDate!);
          final mins = end.difference(now).inMinutes;
          if (end.isBefore(now)) continue;
          if (minMinutesToExpiry == null || mins < minMinutesToExpiry) {
            minMinutesToExpiry = mins;
          }
        } catch (_) {}
      }
    }

    // Floor at 3s (was 1s for soon-to-resolve positions). Each tick
    // fans out to 8+ network calls. At 1s that became a per-second
    // flame-graph dominator on low-end Android (frame skips, GC
    // pressure). 3s is still under Polymarket Data API's ~1s cache
    // TTL of meaningful staleness for the user staring at a
    // sub-minute market — price chip catches up within 2-3 ticks of
    // the actual resolution event.
    //
    // Receive-screen accelerator: when the user is actively staring
    // at their USDC receive address waiting for a deposit, we drop
    // to 3s polling so the inbound USDC.e → pUSD wrap fires within
    // ~6-10s of the transfer landing on-chain instead of 10-20s.
    // The receive screen sets `_awaitingDeposit = true` on mount
    // and clears it on dispose.
    // Any open (un-redeemed) bet → poll at 3s so the live value + P&L feel
    // responsive (the cards animate each tick via RollingNumberText). 5s is
    // reserved for when the user holds nothing open.
    final hasOpenBet = positions.any((p) => !p.redeemable);
    // A held position whose market has ended but is not claimable yet
    // (Polymarket is still resolving it: a short round for about a minute
    // and a half, a game for 15 minutes to 2 hours). Its card says so, and
    // turns claimable on the refresh that sees `redeemable`, so off the
    // Predictions surface it is polled every 20 s instead of 30.
    final awaitingResult = positions.any((p) => awaitingResolution(p, now));
    final int targetInterval;
    if (_awaitingDeposit) {
      // Receive-screen accelerator outranks the visibility backoff —
      // the user is staring at the receive address on a different
      // surface, so `_polymarketVisible` may well be false while a
      // deposit is inbound.
      targetInterval = 3;
    } else if (!_polymarketVisible) {
      // Predictions surface off-screen: nothing animates, so the fast
      // tier is pure network/battery burn. Back off hard — 30s with
      // open bets (positions still track loosely for the home tile),
      // 60s when the user holds nothing open.
      targetInterval = awaitingResult ? 20 : (hasOpenBet ? 30 : 60);
    } else if (minMinutesToExpiry != null && minMinutesToExpiry < 60) {
      targetInterval = 3;
    } else if (hasOpenBet) {
      targetInterval = 3;
    } else {
      targetInterval = 5;
    }

    // Only recreate timer if interval changed
    if (_currentRefreshInterval != targetInterval) {
      _currentRefreshInterval = targetInterval;
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        Duration(seconds: targetInterval),
        (_) => _silentRefresh(),
      );
    }
  }

  /// Set by the Receive screen when the user lands on the USDC pool
  /// view — drops the periodic poll from 10s to 3s so an incoming
  /// USDC transfer is detected within one tick and routed to BTC
  /// quickly. Cleared when the screen disposes. Idempotent.
  bool _awaitingDeposit = false;
  void setAwaitingDeposit(bool waiting) {
    if (_awaitingDeposit == waiting) return;
    _awaitingDeposit = waiting;
    // Force a re-evaluation of the polling interval — without this,
    // the rate only updates on the next `_silentRefresh` tick, which
    // could be up to 10s away.
    final current = state.valueOrNull;
    if (current != null) {
      _adjustRefreshRate(current.openPositions);
    }
  }

  /// Set by the Predictions surface when it mounts/unmounts — the fast
  /// 3-5s poll tiers only apply while the user can actually see the
  /// cards animate; off-screen we back off to 30-60s. Defaults to
  /// `true` so behavior is unchanged until the screens are wired up.
  /// Idempotent; mirrors [setAwaitingDeposit].
  bool _polymarketVisible = true;
  void setPolymarketVisible(bool visible) {
    if (_polymarketVisible == visible) return;
    _polymarketVisible = visible;
    if (visible) unawaited(wrapIdleUsdcE(trigger: 'open'));
    // Re-evaluate immediately — same rationale as setAwaitingDeposit.
    final current = state.valueOrNull;
    if (current != null) {
      _adjustRefreshRate(current.openPositions);
    }
  }

  Future<void> refresh() async {
    // Guard first: this is called from delayed/debounced callbacks in the
    // live-price + user-channel notifiers (Future.delayed), which can fire
    // after this autoDispose notifier has been torn down. Reading `state`
    // post-dispose throws; bail before touching it.
    if (_disposed) return;
    final current = state.valueOrNull;
    if (current == null ||
        current.walletAddress == null ||
        _publicModel == null) {
      return;
    }
    try {
      final data = await _fetchAllData(
        current.walletAddress!,
        proxyWallet: current.proxyWalletAddress,
      );

      _setData(data.copyWith(
        isAuthenticated: current.isAuthenticated,
      ));

      // Auto-claim is OFF — claims are user-initiated only.
    } catch (e) {
      _setData(current.copyWith(error: 'Refresh failed: $e'));
    }
  }

  /// Resolves only the recorded order. This never signs or submits an order.
  /// A resolved result is surfaced once before a fresh review can proceed.
  Future<void> checkPendingOrder({String? tokenId}) async {
    final walletId = _credentialsWalletId();
    final account = state.valueOrNull?.proxyWalletAddress;
    final backend = _backendService;
    if (_disposed || walletId == null || account == null || backend == null) {
      // No account loaded means nothing could be checked, which is a
      // connection state, not evidence of a submission.
      throw const PolymarketOrderCheckUnavailable();
    }
    await HotPolymarketOrderGuard().run<void>(
      walletId: walletId,
      depositWallet: account,
      tokenId: tokenId,
      lookup: backend.getOrderById,
      action: (_) async {},
      // A placement still running here holds the account: wait for its
      // answer, then read what it left, instead of reporting it as an
      // unknown submission.
      busyWait: const Duration(seconds: 45),
    );
  }

  /// Settles submissions an earlier session left waiting for their answer
  /// (a row in `submitting`), so the next prediction is not refused for an
  /// order that was never accepted or has long settled. Reads only; never
  /// signs or sends. Runs at account start when such a row exists.
  Future<void> reconcilePendingOrders() async {
    final account = state.valueOrNull?.proxyWalletAddress;
    if (account == null ||
        account.isEmpty ||
        !await HotPolymarketOrderGuard.hasUnsettled(account)) {
      return;
    }
    for (var i = 0; i < 5; i++) {
      try {
        await checkPendingOrder();
        return;
      } on ResolvedPolymarketOrder {
        // One row settled; read the rest.
        continue;
      } catch (e) {
        // Still unaccounted for or unreachable: the row keeps protecting
        // the account and the next placement checks it again.
        _devLog('[order-journal] reconcile stopped: ${e.runtimeType}');
        return;
      }
    }
  }

  Future<Map<String, dynamic>> placeOrder({
    required String tokenId,
    required OrderSide side,
    required double size,
    required double price,
    bool negRisk = false,
    PolymarketMarketBuyQuote? marketQuote,
    OrderType orderType = OrderType.fok,
    // Optional metadata for optimistic position display
    String? marketTitle,
    String? marketImage,
    String? marketOutcome,
    String? conditionId,
    String? eventSlug,
    String? endDate,
    // Optional analytics metadata — surfaces in polymarket_bet_placed
    // so we can answer "what kinds of markets do users bet on?".
    String? marketCategory,
    String? source, // 'btc_pool' | 'usdc_pool'
    // Surface the bet slip was opened from (feed_card | search | ...).
    // Analytics only — becomes entry_source on polymarket_bet_placed.
    String? entrySource,
    // Extra analytics properties for the outcome event (origin of an
    // autofired bet, ticket settings).
    Map<String, Object>? analytics,
    // Phase 1b.4: `pmBet` for a buy, `pmSell` for a sell. See `PmGrants`
    // in lib/helpers/venue_intents.dart.
    required AuthGrant grant,
    // Named for the person while a self-heal runs inside this placement:
    // 'setup' (the wallet's one-time setup) or 'approving' (allowances).
    // Progress only; it changes nothing about the order.
    void Function(String step)? onStep,
  }) async {
    final orderWalletId = _credentialsWalletId();
    final orderEoa = state.valueOrNull?.walletAddress;
    final orderPrivateKey = _privateKey;
    final orderGeneration = _accountGeneration;
    final orderSession = ref.read(sessionAuthProvider);
    if (orderWalletId == null ||
        orderEoa == null ||
        orderPrivateKey == null ||
        orderSession == null ||
        _client == null) {
      throw StateError('Predictions account is not connected.');
    }
    bool isCurrentAccount() =>
        !_disposed &&
        orderGeneration == _accountGeneration &&
        _credentialsWalletId() == orderWalletId &&
        pickSpendingWallet(ref.read(settingsProvider))?.id == orderWalletId &&
        _privateKey == orderPrivateKey &&
        state.valueOrNull?.walletAddress?.toLowerCase() ==
            orderEoa.toLowerCase() &&
        identical(ref.read(sessionAuthProvider), orderSession) &&
        ref.read(sessionUnlockedProvider);
    void checkAccount() {
      if (!isCurrentAccount()) {
        throw StateError('The selected Predictions account changed.');
      }
    }

    if (orderType == OrderType.gtc || orderType == OrderType.gtd) {
      await RuntimeCapabilitiesService.instance
          .ensureAllowed('trading.advanced');
    }
    checkAccount();
    // The slip re-checked this at the tap; a policy fetched within the
    // last minute is read, not fetched again, so the book has less time
    // to move away from the quoted cap before the post.
    // A buy needs opening predictions and, for a sports or politics
    // market, that category's gate; a sell is an exit and needs neither.
    await RuntimeCapabilitiesService.instance.ensureAllAllowed(
      side == OrderSide.buy
          ? polymarketBetCapabilitiesFor([tokenId, conditionId, eventSlug],
              fallbackCategory: marketCategory)
          : const ['polymarket.close'],
      maxAge: const Duration(seconds: 60),
    );
    PolymarketPlacementTimeline.mark('policy');
    PolymarketPlacementTimeline.trace('policy');
    checkAccount();

    // Phase 1b.4: the grant covers exactly this order (token, side, amount,
    // price and order type). It is consumed before credentials, wraps or
    // the order are signed, so drift throws `ReauthRequired` and nothing is
    // sent. The in-order self-heal below re-checks it on every retry.
    final grantIsBuy = side == OrderSide.buy;
    SensitiveIntent executedOrder() => PmGrants.executedOrder(
          grant,
          walletId: _credentialsWalletId() ?? '',
          tokenId: tokenId,
          isBuy: grantIsBuy,
          size: size,
          price: price,
          orderType: orderType.name,
        );
    GrantGuard.consume(
      grant,
      executedOrder(),
      allowed: PmGrants.orderActions(grantIsBuy),
    );

    // The derived deposit address alone does not mean the contract or its
    // approvals exist. Share the same setup already started by account boot
    // and deposits before signing an order against it.
    await enableTrading();
    PolymarketPlacementTimeline.trace('account_ready');
    checkAccount();
    PmGrants.checkRetry(grant, executedOrder());
    final current = state.valueOrNull;
    if (current == null || _client == null) {
      throw Exception('Not authenticated');
    }

    if (_backendService == null) {
      try {
        final result = await _deriveOrCreateApiKey(
          funder: current.proxyWalletAddress,
          isCurrent: isCurrentAccount,
        );
        checkAccount();
        if (result != null) {
          await _saveCredentials(
            orderWalletId,
            result.credentials,
            nonce: result.nonce,
            isCurrent: isCurrentAccount,
          );
          checkAccount();
          _apiNonce = result.nonce;
          _client!.clob.auth?.setCredentials(result.credentials);
          _backendService = _createBackendService(
            result.credentials,
            current.walletAddress!,
            funder: current.proxyWalletAddress,
          );
          if (current.proxyWalletAddress != null &&
              current.proxyWalletAddress!.isNotEmpty) {
            _client?.close();
            _client = PolymarketClient.authenticated(
              credentials: result.credentials,
              funder: current.proxyWalletAddress!,
              privateKey: orderPrivateKey,
            );
          }
        } else {
          throw Exception('API returned null credentials');
        }
      } catch (e) {
        checkAccount();
        throw Exception('Could not connect to Polymarket: $e');
      }
    }

    checkAccount();
    final orderAccount = current.proxyWalletAddress;
    final orderBackend = _backendService!;
    if (orderAccount == null || orderAccount.isEmpty) {
      throw StateError('Predictions account is still being prepared.');
    }
    void ensureCurrent() {
      checkAccount();
      if (state.valueOrNull?.proxyWalletAddress?.toLowerCase() !=
          orderAccount.toLowerCase()) {
        throw StateError('The selected Predictions account changed.');
      }
      PmGrants.checkRetry(grant, executedOrder());
    }

    ensureCurrent();
    // Ready pUSD goes directly to the order book. A deposit that landed
    // while the app was closed (or a moment ago) is still USDC.e, which the
    // order book does not count: when pUSD alone is short and pUSD + USDC.e
    // covers this buy, convert it before signing instead of waiting for the
    // refusal. The refusal path inside the guard stays as the fallback.
    //
    // This runs before the order guard takes the account, not inside it:
    // the conversion joins one already running for the wallet and can take
    // a relayer round trip, and while the guard is held every other tap
    // (and the status check) is refused as "a previous prediction is still
    // being confirmed" although nothing was sent.
    if (side == OrderSide.buy) {
      PolymarketPlacementTimeline.trace('collateral_wait');
      final split = await _collateralSplitForOrder(orderAccount);
      PolymarketPlacementTimeline.trace('collateral');
      ensureCurrent();
      if (split != null &&
          polyShouldWrapBeforeBuy(
            pusd: split.pusd,
            usdce: split.usdce,
            // The venue counts the fees against pUSD too: a buy whose
            // notional fits pUSD but not its fees is refused all the same.
            costMicros: polyBuyCostMicros(size: size, price: price) +
                BigInt.from(((marketQuote?.tokenId == tokenId
                                ? marketQuote!.feeCeiling
                                : 0.0) *
                            1e6)
                        .ceil()),
          )) {
        onStep?.call('approving');
        try {
          final wrapped = await _wrapHeldUsdcE(
            eoa: orderEoa,
            privateKey: orderPrivateKey,
            wallet: orderAccount,
            trigger: 'order',
            ensureCurrent: ensureCurrent,
          ).timeout(PolymarketPlacementWaits.conversion);
          ensureCurrent();
          if (wrapped > BigInt.zero) {
            await _backendService?.updateBalanceAllowance(
              assetType: 'COLLATERAL',
              signatureType: 3,
            );
          }
        } on TimeoutException {
          // The conversion keeps going; nothing has been signed. Saying so
          // beats an order the book would refuse for want of pUSD.
          ensureCurrent();
          throw const PolymarketFundsConverting();
        } catch (e) {
          // A changed account or grant still stops the order here;
          // a failed conversion leaves it to the refusal path.
          ensureCurrent();
          _devLog('[wrap] before-order conversion failed: $e');
        }
      }
      ensureCurrent();
    }
    return HotPolymarketOrderGuard().run(
      walletId: orderWalletId,
      depositWallet: orderAccount,
      tokenId: tokenId,
      lookup: orderBackend.getOrderById,
      action: (submit) async {
        ensureCurrent();
        _setData(current.copyWith(isPlacingOrder: true));
        try {
          // Auto-detect negRisk from the CLOB (authoritative — it decides
          // the EIP-712 verifying contract). When the probe FAILS we keep
          // the caller's flag, which the UI now threads down from the
          // event/position metadata — before, a failed probe silently
          // assumed false and signed negRisk orders against the wrong
          // exchange.
          final terms = marketQuote != null &&
                  marketQuote.tokenId == tokenId &&
                  marketQuote.hasFreshTerms
              ? marketQuote
              : null;
          bool detectedNegRisk = terms?.negRisk ?? negRisk;
          PolymarketPlacementTimeline.trace(
              terms == null ? 'terms_stale_refetch' : 'terms_fresh');
          if (terms == null) {
            try {
              detectedNegRisk = await _client!.clob.markets
                  .getNegRisk(tokenId)
                  .timeout(const Duration(seconds: 8));
            } catch (_) {}
          }
          ensureCurrent();

          // Re-read state inside the closure so the retry that follows
          // `enableTrading(force: true)` picks up the newly-deployed Safe
          // address. Capturing `current.proxyWalletAddress` at the top of
          // `placeOrder` froze the value at "null" for users in the
          // post-migration shape — the heal deployed the Safe but the
          // retry rebuilt the order with the stale empty proxy and got
          // the same "maker address not allowed" 400.
          Future<SignedOrderV2> buildOrder() {
            final live = state.valueOrNull ?? current;
            return _buildSignedOrder(
              privateKey: orderPrivateKey,
              ensureCurrent: ensureCurrent,
              tokenId: tokenId,
              side: side,
              size: size,
              price: price,
              negRisk: detectedNegRisk,
              proxyWallet: live.proxyWalletAddress,
              eoaAddress: live.walletAddress ?? current.walletAddress!,
              orderType: orderType,
              preparedTerms: terms,
            );
          }

          // Submit with silent self-healing retries:
          //  - InvalidApiKey      → refresh credentials
          //  - "allowance" error  → run enableTrading() (deploys Safe + sets approvals)
          // All retries are invisible to the UI — there's no separate permissions
          // banner; permission setup is folded into the bet-placement flow.
          // (V2 orders carry no fee rate — fees are set at match time — so
          // there is no "fix the fee rate and resubmit" retry any more.)
          Map<String, dynamic>? submitted;
          bool credsRefreshed = false;
          bool approvalsFixed = false;
          bool balanceRefreshed = false;
          bool keyRebound = false;
          bool spenderApproved = false;

          // Each venue refusal is noted. When the approval runs out
          // during the repair that follows one, nothing
          // was placed and the refusal is why: that is what the slip says
          // and what the failure event records, not "approval expired".
          await polymarketSurfaceRefusalOnExpiry((refused) async {
            for (var attempt = 0; attempt < 5; attempt++) {
              // Phase 1b.4: every self-heal retry (credential refresh, the forced
              // enableTrading) stays inside this order's grant:
              // the same bounds, not revoked and not expired.
              if (attempt > 0) PmGrants.checkRetry(grant, executedOrder());
              try {
                ensureCurrent();
                PolymarketPlacementTimeline.mark('auth');
                PolymarketPlacementTimeline.trace('guard');
                final signed = await buildOrder();
                PolymarketPlacementTimeline.mark('sign');
                PolymarketPlacementTimeline.trace('sign');
                ensureCurrent();
                final backend = _backendService!;
                submitted = await submit(
                  order: signed,
                  exchange: PolyOrderVenue.forToken(signed.order.tokenId,
                          negRisk: detectedNegRisk)
                      .exchange,
                  ensureCurrent: ensureCurrent,
                  send: (beforePost) => backend.submitOrder(
                    signedOrder: signed,
                    orderType: orderType,
                    beforePost: beforePost,
                  ),
                );
                PolymarketPlacementTimeline.mark('post');
                PolymarketPlacementTimeline.trace('post');
                break;
              } on InvalidApiKeyException {
                if (credsRefreshed) {
                  throw Exception(
                    'Authentication failed. Please re-enable trading in settings.',
                  );
                }
                credsRefreshed = true;
                try {
                  await _refreshCredentials(
                    orderEoa,
                    ensureCurrent: ensureCurrent,
                    isCurrent: isCurrentAccount,
                  );
                } catch (_) {
                  throw Exception(
                    'Authentication failed. Please re-enable trading in settings.',
                  );
                }
                continue;
              } catch (e) {
                // Only a documented refusal permits signing a replacement.
                if (e is! PolymarketOrderNotAcceptedException) rethrow;
                refused(e);
                final heal = polymarketRefusalHeal(
                  e.reason,
                  balanceRefreshed: balanceRefreshed,
                  keyRebound: keyRebound,
                  approvalsFixed: approvalsFixed,
                  spenderApproved: spenderApproved,
                );
                if (heal != PolymarketRefusalHeal.stop &&
                    heal != PolymarketRefusalHeal.approveSpender) {
                  PolymarketPlacementDiagnostics.selfHeal(
                    heal: heal.name,
                    refusal: e.reason,
                    attempt: attempt,
                    negRisk: detectedNegRisk,
                  );
                }

                // A documented refusal proves the first order was not accepted.
                // Do not run relayer funding or balance refresh on every funded bet,
                // and never reach this retry after a timeout or ambiguous response.
                if (heal == PolymarketRefusalHeal.refreshBalance) {
                  balanceRefreshed = true;
                  onStep?.call('approving');
                  ensureCurrent();
                  if (side == OrderSide.buy) {
                    await _wrapHeldUsdcE(
                      eoa: orderEoa,
                      privateKey: orderPrivateKey,
                      wallet: orderAccount,
                      trigger: 'refusal',
                      ensureCurrent: ensureCurrent,
                    );
                    ensureCurrent();
                  }
                  await _backendService!.updateBalanceAllowance(
                    assetType:
                        side == OrderSide.buy ? 'COLLATERAL' : 'CONDITIONAL',
                    signatureType: 3,
                    tokenId: side == OrderSide.sell ? tokenId : null,
                  );
                  ensureCurrent();
                  continue;
                }

                // Refresh stale credentials once using the documented EOA L1
                // contract; order signatures remain deposit-wallet POLY_1271.
                if (heal == PolymarketRefusalHeal.rebindKey) {
                  keyRebound = true;
                  try {
                    await _refreshCredentials(
                      orderEoa,
                      ensureCurrent: ensureCurrent,
                      isCurrent: isCurrentAccount,
                    );
                    // Refresh CLOB allowance cache. signature_type=3 (POLY_1271)
                    // — matches the V2 deposit-wallet order sigType.
                    try {
                      await _backendService?.updateBalanceAllowance(
                        assetType: 'COLLATERAL',
                        signatureType: 3,
                      );
                      _devLog('[pm-heal] balance-allowance/update OK');
                    } catch (e) {
                      _devLog('[pm-heal] balance-allowance/update threw: $e');
                    }
                  } catch (e) {
                    _devLog('[pm-heal] refreshCredentials threw: $e');
                    rethrow;
                  }
                  continue;
                }

                // Silent permission setup: deploy the wallet + fix token
                // approvals, then retry. Only for refusals that name approvals
                // or the maker (`not approved`, `transfer amount exceeds
                // allowance`, `maker address X has no allowance` / `has not
                // been registered`): the wallet is missing on chain or an
                // exchange approval is. `enableTrading()` deploys the wallet
                // (idempotent) and re-runs the approve sequence. The balance
                // refusal never comes here, although it says "allowance": a
                // second one ends the placement below with what the venue
                // said instead of re-running setup behind "Setting up…".
                if (heal == PolymarketRefusalHeal.repairSetup) {
                  approvalsFixed = true;
                  onStep?.call('setup');
                  try {
                    // force:true bypasses the "already deployed" short-circuit so
                    // we actually re-derive the Safe, re-run fixMissingApprovals,
                    // and refresh credentials. Without it, a stale state with a
                    // wrong-but-non-empty proxyWalletAddress (the polybrainz
                    // migration left some users in this shape) makes enableTrading
                    // a no-op and the retry hits the same rejection.
                    ensureCurrent();
                    try {
                      await enableTrading(force: true)
                          .timeout(PolymarketPlacementWaits.setup);
                    } on TimeoutException {
                      // The repair keeps running; this order (already
                      // refused) ends with a retry instead of holding the
                      // account until it is done.
                      throw const PolymarketSetupIncomplete(timedOut: true);
                    }
                    ensureCurrent();
                    await Future.delayed(const Duration(seconds: 3));
                  } catch (_) {
                    rethrow;
                  }
                  continue;
                }

                // The refusal names the one approval the venue checks and
                // finds missing, on one of Polymarket's pinned contracts:
                // set exactly that (bounded by the setup wait, once), have
                // the venue re-read it, and sign again.
                if (heal == PolymarketRefusalHeal.approveSpender) {
                  spenderApproved = true;
                  onStep?.call('approving');
                  ensureCurrent();
                  void report(String result) =>
                      PolymarketPlacementDiagnostics.selfHeal(
                        heal: heal.name,
                        refusal: e.reason,
                        attempt: attempt,
                        negRisk: detectedNegRisk,
                        result: result,
                      );
                  try {
                    final sent = await PolymarketOnboardingService()
                        .approveRefusalSpender(
                          eoaAddress: orderEoa,
                          privateKey: orderPrivateKey,
                          walletAddress: orderAccount,
                          spender: polymarketRefusalSpender(e.reason)!,
                          ensureCurrent: ensureCurrent,
                        )
                        .timeout(PolymarketPlacementWaits.setup);
                    report(sent ? 'sent' : 'already_set');
                  } on TimeoutException {
                    report('timed_out');
                    throw const PolymarketSetupIncomplete(timedOut: true);
                  } catch (error) {
                    // A changed account or approval still stops here as
                    // itself; a failed approval batch is a setup failure.
                    if (error is AuthGrantException || error is StateError) {
                      rethrow;
                    }
                    report('failed');
                    throw PolymarketSetupIncomplete(cause: error);
                  }
                  ensureCurrent();
                  await _backendService!.updateBalanceAllowance(
                    assetType: 'COLLATERAL',
                    signatureType: 3,
                  );
                  ensureCurrent();
                  continue;
                }

                // Earlier matched trades are still reserved against a
                // balance that covers this order (py-clob-client-v2#112):
                // not a shortage, so never "add funds".
                if (isPolymarketStaleReservation(e.reason)) {
                  throw PolymarketStaleReservation(e.reason);
                }

                // The balance came back refused after the one refresh: the
                // venue does not count enough collateral for this order on
                // this market. Said as such, with the venue's own words kept
                // for the failure event.
                if (isPolymarketBalanceRefusal(e.reason)) {
                  throw PolymarketBalanceRefused(e.reason);
                }
                rethrow;
              }
            }
          });

          final response = submitted;
          if (response == null) {
            throw Exception('Order placement failed. Please try again.');
          }

          if (isCurrentAccount()) {
            _setData(
              (state.valueOrNull ?? current).copyWith(isPlacingOrder: false),
            );
          }

          // Polymarket's real order hash from the CLOB submit response. This is
          // the join key the backend uses to attribute the exact builder fee
          // (fee_usdc) to this user: provider_order_id = taker_order_hash.
          final responseOrderId = (response['orderID'] ??
                  response['orderId'] ??
                  response['order_id'])
              ?.toString();

          final making = double.tryParse(
            '${response['makingAmount'] ?? response['making_amount']}',
          );
          final taking = double.tryParse(
            '${response['takingAmount'] ?? response['taking_amount']}',
          );
          final hasFill =
              response['status']?.toString().toLowerCase() == 'matched' &&
                  making != null &&
                  making.isFinite &&
                  making > 0 &&
                  taking != null &&
                  taking.isFinite &&
                  taking > 0;
          // Submitted orders are not filled activity. Indexing supplies the final
          // amounts when the acknowledgement does not contain a verified fill.
          // Keyed by the trade id (never a CLOB id posing as a chain hash);
          // the Data API fill evicts it by trade shape.
          final optimisticKey =
              PolymarketOptimisticActivityService.optimisticTradeKey(response);
          if (side == OrderSide.buy && hasFill && optimisticKey != null) {
            try {
              final filledUsdc = making;
              final filledShares = taking;
              final fillPrice = filledUsdc / filledShares;

              PolymarketOptimisticActivityService.record(
                Activity(
                  proxyWallet: current.proxyWalletAddress ?? '',
                  timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                  conditionId: conditionId ?? '',
                  type: 'TRADE',
                  size: filledShares,
                  usdcSize: filledUsdc,
                  transactionHash: optimisticKey,
                  price: fillPrice,
                  asset: tokenId,
                  side: side == OrderSide.buy ? 'BUY' : 'SELL',
                  title: marketTitle,
                  slug: eventSlug,
                  eventSlug: eventSlug,
                  outcome: marketOutcome,
                  icon: marketImage,
                ),
              );
              ref
                  .read(transactionNotifierProvider.notifier)
                  .refreshOptimisticPolymarketActivity();
            } catch (_) {
              // Optimistic injection is a UX nicety — never block the success path.
            }
          }

          // Poll to pick up the real position from the Data API.
          for (final delay in [1, 3, 6, 10]) {
            Future.delayed(Duration(seconds: delay), () {
              if (!isCurrentAccount()) return;
              try {
                refresh();
              } catch (_) {}
            });
          }

          if (hasFill) {
            TrackingService.polymarketBetPlaced(
              // SELLs are reported by polymarket_position_sold (market) or
              // polymarket_limit_sell_placed (GTC); counting them here too
              // made every sale also a "bet". Backend provider-event logging
              // still runs inside the helper when emitAnalytics is false.
              emitAnalytics: side == OrderSide.buy,
              side: side == OrderSide.buy ? 'buy' : 'sell',
              orderType:
                  (orderType == OrderType.gtc || orderType == OrderType.gtd)
                      ? 'limit'
                      : 'market',
              marketOutcome: marketOutcome,
              walletKind: 'hot',
              entrySource: entrySource,
              marketId: tokenId,
              outcome: side == OrderSide.buy ? 'buy' : 'sell',
              amount: side == OrderSide.buy ? making : taking,
              price: side == OrderSide.buy ? making / taking : taking / making,
              shares: (side == OrderSide.buy ? taking : making).round(),
              // Real Polymarket order hash → backend joins it to the builder trade
              // for exact fee_usdc attribution (synthetic fallback inside if null).
              providerOrderId: responseOrderId,
              category: marketCategory,
              marketTitle: marketTitle,
              source: source,
              // Coarse market type (moneyline / yes_no / over_under / spread /
              // … / other) so the funnel can split placement by bet structure —
              // including politics multi-outcome. Pure name classification, no
              // sensitive data.
              betType: polymarketMarketType(
                marketTitle ?? '',
                outcome: marketOutcome,
              ),
              // Polymarket bets are gated to the spending wallet (the Safe's
              // owner EOA is the spending wallet's BIP39 derivation). The
              // analytics dashboard still gets the explicit param so future
              // signers/hardware support shows up as a distinct cohort if
              // we ever lift the restriction.
              walletCategory: 'spending',
              // Market sells get their provider_events row from the sell
              // sheet's `polymarketPositionSold` (same orderID, correct
              // pm_shares → USDC direction) — logging from here too created a
              // duplicate backend row per sell order. Resting GTC sells never
              // reach that path, so they keep logging from here.
              logAffiliateEvent:
                  side == OrderSide.buy || orderType == OrderType.gtc,
              extra: {
                ...?analytics,
                // v1 (CTF) | v2 (Protocol V2 / ExchangeV3), from the token.
                'market_protocol': PolyMarketProtocol.wireForToken(tokenId),
                // biometric | fast_window | allowance: how this order
                // was approved (FastBetWindow.approvalParam).
                'approval': FastBetWindow.approvalParam(grant.method),
              },
            );
          }
          // Tag the funding source for the auto-sweep on resolve. We
          // only tag BUYs (sells don't need tagging — selling closes
          // the position; the sweep is for the winnings on a held
          // outcome). First write wins per conditionId so a follow-up
          // top-up from a different asset doesn't re-route the original
          // stake. `source == 'btc_pool'` means the user came in via the
          // BTC card; `usdc_pool` means they had existing USDC.
          if (side == OrderSide.buy && conditionId != null) {
            final fundingSource = source == 'btc_pool'
                ? BetFundingSource.btc
                : BetFundingSource.usdc;
            // ignore: discarded_futures
            PolymarketBetFundingService.tag(
              conditionId: conditionId,
              source: fundingSource,
              marketTitle: marketTitle,
            );
          }
          // First-bet milestone — gated once-per-device by OnceFlagsService.
          // Buys only: a sell is not a bet and must not unlock the first-bet
          // milestone or bump the lifetime bet counter.
          if (hasFill && side == OrderSide.buy) {
            TrackingService.polymarketFirstBetPlaced();
            // Surface the in-app celebration card too (quiet variant — no
            // confetti, see HARD RULE: we celebrate outcomes not bets).
            try {
              ref
                  .read(pendingMilestoneProvider.notifier)
                  .unlock(MilestoneKeys.firstPrediction);
            } catch (_) {}
            // Bump lifetime bet count + primary-rail user property so the
            // Firebase admin segments (e.g. "active predictors in last 30d")
            // don't require a BigQuery aggregation.
            // A bet is not a swap: revenueEventCompleted bumped
            // lifetime_swap_count for every Polymarket fill. Revenue itself is
            // recorded server-side from the provider event, so only the
            // lifetime bet props are refreshed here.
            TrackingService.refreshLifetimeProps(
              isFunded: true,
              lifetimeBetCount: TrackingService.bumpBetCount(),
              primaryRail: 'predictions',
            );
          }
          // Note: tracking_service.polymarketBetPlaced internally calls
          // AffiliateService.logProviderEvent with status='completed', which
          // triggers the backend's first_polymarket action milestone on the
          // user's first bet. No separate reportMilestone call needed.

          return response;
        } catch (e) {
          if (isCurrentAccount()) {
            _setData(
              (state.valueOrNull ?? current).copyWith(isPlacingOrder: false),
            );
          }
          // A grant failure on a retry signed nothing new. Not an order failure.
          if (e is AuthGrantException) rethrow;
          // No polymarket_bet_failed here: the controller walks a FAK price
          // ladder and a rejected rung is retried, so this fired for bets
          // that went on to fill. The terminal failure is reported once by
          // the caller (bet controller / sell sheet).
          rethrow;
        }
      },
    );
  }

  /// The hot Predictions account, ready for the combo RFQ flow
  /// (`polymarket_combos_provider.dart`): the deposit wallet deployed and
  /// approved, CLOB credentials provisioned, and a Requester transport
  /// signing with those L2 credentials. [refreshCredentials] re-derives
  /// the API key first (after a 401). Hot wallet only: the key stays
  /// inside the returned account and is never handed out.
  Future<PolymarketComboAccount> comboAccount(
      {bool refreshCredentials = false}) async {
    final walletId = _credentialsWalletId();
    final eoa = state.valueOrNull?.walletAddress;
    final privateKey = _privateKey;
    final generation = _accountGeneration;
    final session = ref.read(sessionAuthProvider);
    if (walletId == null ||
        eoa == null ||
        privateKey == null ||
        session == null ||
        _client == null) {
      throw StateError('Predictions account is not connected.');
    }
    bool isCurrentAccount() =>
        !_disposed &&
        generation == _accountGeneration &&
        _credentialsWalletId() == walletId &&
        pickSpendingWallet(ref.read(settingsProvider))?.id == walletId &&
        _privateKey == privateKey &&
        state.valueOrNull?.walletAddress?.toLowerCase() == eoa.toLowerCase() &&
        identical(ref.read(sessionAuthProvider), session) &&
        ref.read(sessionUnlockedProvider);
    void checkAccount() {
      if (!isCurrentAccount()) {
        throw StateError('The selected Predictions account changed.');
      }
    }

    await enableTrading();
    checkAccount();
    final current = state.valueOrNull;
    final depositWallet = current?.proxyWalletAddress;
    if (depositWallet == null || depositWallet.isEmpty) {
      throw StateError('Predictions account is still being prepared.');
    }
    if (_backendService == null || refreshCredentials) {
      await _refreshCredentials(eoa,
          ensureCurrent: checkAccount, isCurrent: isCurrentAccount);
    }
    checkAccount();
    if (_backendService == null) {
      throw StateError('Predictions account is not connected.');
    }
    bool isCurrentWallet() =>
        isCurrentAccount() &&
        state.valueOrNull?.proxyWalletAddress?.toLowerCase() ==
            depositWallet.toLowerCase();
    return PolymarketComboAccount(
      walletId: walletId,
      eoaAddress: eoa,
      depositWallet: depositWallet,
      privateKey: privateKey,
      isCurrent: isCurrentWallet,
      credentials: _hotPolymarketCredentials,
      transport: RequesterComboTransport(
        // Read live: a credential refresh swaps the backend service.
        sign: ({required method, required path, body}) {
          final backend = _backendService;
          if (backend == null || !isCurrentWallet()) {
            throw StateError('The selected Predictions account changed.');
          }
          return backend.l2Headers(method: method, path: path, body: body);
        },
      ),
    );
  }

  Future<SignedOrderV2> _buildSignedOrder({
    required String privateKey,
    required void Function() ensureCurrent,
    required String tokenId,
    required OrderSide side,
    required double size,
    required double price,
    required bool negRisk,
    required String eoaAddress,
    String? proxyWallet,
    PolymarketMarketBuyQuote? preparedTerms,
    OrderType orderType = OrderType.fok,
  }) async {
    ensureCurrent();
    final hasWallet = proxyWallet != null && proxyWallet.isNotEmpty;
    final maker = hasWallet ? proxyWallet : eoaAddress;
    // V2 deposit-wallet flow: sigType = 3 (POLY_1271), both `maker` and
    // `signer` set to the deposit wallet address. The EOA only acts as
    // the signing key; the CLOB calls `wallet.isValidSignature(orderHash,
    // wrappedSig)` server-side to verify. The legacy POLY_GNOSIS_SAFE
    // path (sigType=2, signer=EOA) is dead for new wallets — see
    // /trading/deposit-wallets in Polymarket's docs and our V2 migration
    // notes in `polymarket_order_v2.dart`.
    const polyV2_1271 = 3;
    final sigType = hasWallet
        ? polyV2_1271 // 3 = POLY_1271 (V2 deposit wallet)
        : SignatureType.eoa.value; // 0 = plain EOA (no wallet)
    // POLY_1271 requires `signer == maker == DepositWallet`.
    final signerForOrder = maker;

    // Fetch current terms before signing. A failed or unrecognized response
    // must not silently substitute a different price increment.
    String? rawTick =
        preparedTerms?.tokenId == tokenId && preparedTerms!.hasFreshTerms
            ? preparedTerms.tickSize
            : null;
    if (rawTick == null) {
      final tickResp = await http
          .get(
            Uri.https(
                'clob.polymarket.com', '/tick-size', {'token_id': tokenId}),
          )
          .timeout(const Duration(seconds: 8));
      if (tickResp.statusCode != 200) {
        throw StateError('Could not verify the current market price increment');
      }
      final parsedTick = jsonDecode(tickResp.body);
      final responseTick = parsedTick is Map
          ? parsedTick['minimum_tick_size'] ?? parsedTick['tick_size']
          : parsedTick;
      rawTick = '$responseTick';
    }
    final amounts = PolymarketOrderAmounts.encode(
      tickSize: rawTick,
      price: price,
      size: size,
      isBuy: side == OrderSide.buy,
      isMarket: orderType == OrderType.fok || orderType == OrderType.fak,
    );
    final makerAmount = amounts.maker;
    final takerAmount = amounts.taker;

    // Salt: small int matching py-clob-client's generate_seed()
    //   Python: round(now_seconds * random())  →  fits in JSON number
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nowSec = nowMs / 1000;
    final salt = BigInt.from((nowSec * Random.secure().nextDouble()).round());

    final builderCode = await PolymarketBackendService.getBuilderCode();

    final order = OrderStructV2(
      salt: salt,
      maker: maker,
      signer: signerForOrder,
      tokenId: tokenId,
      makerAmount: makerAmount,
      takerAmount: takerAmount,
      side: side == OrderSide.buy ? 0 : 1,
      signatureType: sigType,
      timestamp: BigInt.from(nowMs),
      metadata: PolymarketConstants.bytes32Zero,
      builder: builderCode,
    );

    // CTF tokens sign for the CTF exchange of [negRisk] under domain "2";
    // Protocol V2 positions for ExchangeV3 under "3" (market_protocol.dart).
    PolyMarketProtocol.ensureSignable(tokenId);
    final venue = PolyOrderVenue.forToken(tokenId, negRisk: negRisk);

    ensureCurrent();
    final signature = sigType == polyV2_1271
        ? await signOrderV2Poly1271(
            order: order,
            credentials: _hotPolymarketCredentials(privateKey),
            verifyingContract: venue.exchange,
            domainVersion: venue.domainVersion,
          )
        : await signOrderV2(
            order: order,
            credentials: _hotPolymarketCredentials(privateKey),
            verifyingContract: venue.exchange,
            domainVersion: venue.domainVersion,
          );

    return SignedOrderV2(order: order, signature: signature);
  }

  Future<void> _refreshCredentials(
    String eoaAddress, {
    required void Function() ensureCurrent,
    required bool Function() isCurrent,
  }) async {
    ensureCurrent();
    final walletId = _credentialsWalletId();
    final privateKey = _privateKey;
    final funder = state.valueOrNull?.proxyWalletAddress;
    if (walletId == null || privateKey == null) {
      throw StateError('Predictions account is not connected.');
    }

    // Keep the previous cancellation credentials until a replacement is
    // ready, and never install an old request's result into another account.
    final result = await _deriveOrCreateApiKey(
      funder: funder,
      isCurrent: isCurrent,
    );
    ensureCurrent();
    if (result == null) {
      throw Exception('Could not refresh API credentials');
    }
    await _saveCredentials(
      walletId,
      result.credentials,
      nonce: result.nonce,
      isCurrent: isCurrent,
    );
    ensureCurrent();
    _apiNonce = result.nonce;
    _client!.clob.auth?.setCredentials(result.credentials);
    _backendService = _createBackendService(
      result.credentials,
      eoaAddress,
      funder: funder,
    );
    if (funder != null && funder.isNotEmpty) {
      _client?.close();
      _client = PolymarketClient.authenticated(
        credentials: result.credentials,
        funder: funder,
        privateKey: privateKey,
      );
    }
  }

  /// Resting (unfilled) GTC limit orders for this account. Empty when
  /// trading isn't set up. Used by `polymarketOpenOrdersProvider`.
  Future<List<Order>> getOpenOrders() async {
    if (_backendService == null) return const [];
    return _backendService!.getOpenOrders();
  }

  Future<void> cancelOrder(String orderId) async {
    await RuntimeCapabilitiesService.instance
        .ensureAllowed('polymarket.cancel');
    if (_backendService == null) {
      throw StateError('Polymarket account is not connected.');
    }
    await _backendService!.cancelOrder(orderId);
    await refresh();
  }

  Future<void> cancelAllOrders() async {
    await RuntimeCapabilitiesService.instance
        .ensureAllowed('polymarket.cancel');
    if (_backendService == null) {
      throw StateError('Polymarket account is not connected.');
    }
    await _backendService!.cancelAllOrders();
    await refresh();
  }

  /// Background auto-claim. Fires from the periodic refresh tick when
  /// the trading state lists redeemable positions. Both the
  /// `redeemPositions` call and the follow-up pUSD → USDC.e unwrap
  /// are relayer-paid, so the user never sees a gas prompt. Idempotent
  /// at the contract level: a second redeem of the same condition
  /// burns nothing and transfers nothing, so a redundant call is just
  /// wasted RPC.
  ///
  /// Guards:
  ///   * Skip if no spending wallet / no proxy / EOA private key not
  ///     yet derived (we'd throw immediately in `redeemPosition`).
  ///   * Per-session `_autoClaimedIds` set prevents the same condition
  ///     from re-firing every 10 s while a successful claim is still
  ///     propagating through the Polymarket Data API.
  ///   * Errors from individual condition redeems are swallowed —
  ///     the next refresh will retry, and the manual Claim button is
  ///     still available if the user wants explicit feedback.

  /// [trigger] (auto | manual) and [surface] tag the redeem analytics.
  /// A thrown failure reports polymarket_redeem_failed exactly once, here;
  /// callers check [redeemFailureTracked] before reporting their own.
  /// [reportFailure] false (auto-claim backoff retries) records nothing but
  /// still marks the error tracked.
  Future<double?> redeemPosition({
    required String conditionId,
    List<int> indexSets = const [1, 2],
    String? trigger,
    String? surface,
    bool reportFailure = true,
  }) async {
    try {
      return await _redeemPosition(
        conditionId: conditionId,
        indexSets: indexSets,
        trigger: trigger,
        surface: surface,
      );
    } catch (e) {
      if (!redeemFailureTracked(e)) {
        if (reportFailure) {
          TrackingService.polymarketRedeemFailed(
            marketId: conditionId,
            // Fixed code only — the raw exception text can carry the
            // conditionId, balances or relayer bodies.
            reason: _redeemFailureCode[e] ?? TrackingService.errorCategory(e),
            trigger: trigger,
            surface: surface,
          );
        }
        _markRedeemFailure(e);
      }
      rethrow;
    }
  }

  static final Expando<bool> _redeemFailureTracked =
      Expando<bool>('redeemFailureTracked');
  static final Expando<String> _redeemFailureCode =
      Expando<String>('redeemFailureCode');

  /// Whether [redeemPosition] already reported this thrown [error] as
  /// polymarket_redeem_failed, so a caller's catch does not report it twice.
  static bool redeemFailureTracked(Object error) {
    try {
      return _redeemFailureTracked[error] ?? false;
    } catch (_) {
      return false; // strings/numbers cannot carry an Expando
    }
  }

  static void _markRedeemFailure(Object error) {
    try {
      _redeemFailureTracked[error] = true;
    } catch (_) {}
  }

  /// A lost position with no tokens left: nothing to pay out, the row is
  /// just cleared (and kept hidden while the Data API catches up).
  void _treatLostAsCleared(String conditionId) {
    _recentlyClaimedIds[conditionId] = DateTime.now();
    PolymarketSuppressionService.mark(conditionId);
    _knownRedeemableIds.remove(conditionId);
    final st = state.valueOrNull;
    if (st != null) {
      _setData(st.copyWith(
        openPositions:
            st.openPositions.where((p) => p.conditionId != conditionId).toList(),
      ));
    }
  }

  Future<double?> _redeemPosition({
    required String conditionId,
    required List<int> indexSets,
    String? trigger,
    String? surface,
  }) async {
    await RuntimeCapabilitiesService.instance.ensureAllowed('polymarket.close');
    final current = state.valueOrNull;
    if (current == null || current.walletAddress == null) {
      throw Exception('No wallet address');
    }
    final eoa = current.walletAddress!;
    final proxyWallet = current.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      throw Exception('Trading not enabled');
    }

    // Polymarket positions live on the per-user Safe whose owner key
    // is the SPENDING wallet's EOA — not whichever wallet is parked
    // on the carousel right now. Using `settings.activeWalletId` here
    // would route the redeem signing through e.g. a hardware wallet
    // when the user happens to be viewing it, then fail with
    // "Could not decrypt wallet" because watch-only wallets only
    // carry the xpub. Always resolve the spending wallet so the user
    // can claim from any carousel page.
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) {
      throw Exception(
          'No spending wallet. Polymarket claims need the hot wallet that owns the Safe.');
    }
    final session = ref.read(seedSessionProvider);
    if (!session.unlocked) {
      throw Exception('Wallet locked. Please unlock first.');
    }
    final mnemonic = await resolveBip39MnemonicFor(spending,
        access: SeedAccess.automatic, session: session);
    if (mnemonic == null) {
      throw Exception('Could not decrypt spending wallet');
    }
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);

    final onboarding = PolymarketOnboardingService();

    // Look up the position so we can pick the right redemption contract.
    // Polymarket has two kinds of resolved positions:
    //
    //   1. Standard CTF markets — one binary condition. Redeemed via the
    //      base ConditionalTokens contract, signature:
    //        redeemPositions(IERC20 collateral, bytes32 parentCollectionId,
    //                        bytes32 conditionId, uint256[] indexSets)
    //      Selector 0x01b7037c. indexSets=[1,2] redeems whichever outcome
    //      won; the contract handles the rest.
    //
    //   2. Multi-outcome ("neg-risk") markets — each sub-question is
    //      binary but they share collateral via a wrapper contract.
    //      Redemption MUST go through the NegRiskCtfCollateralAdapter
    //      (see below). The CLOB v1 Neg Risk Adapter at 0xd91E… is
    //      deprecated: the relayer stopped accepting redeems aimed at
    //      it on 2026-07-17, so there is no legacy fallback for it.
    //
    // Calling the CTF path on a neg-risk position reverts silently,
    // which is what was causing "Claimed" to show without anything
    // actually happening.
    final pos = current.openPositions
        .where((p) => p.conditionId == conditionId)
        .firstOrNull;
    final isNegRisk = pos?.negativeRisk ?? false;
    _devLog('[redeem] start conditionId=$conditionId '
        'isNegRisk=$isNegRisk size=${pos?.size} curPrice=${pos?.curPrice} '
        'outcomeIndex=${pos?.outcomeIndex} safe=$proxyWallet');

    // Nothing to redeem: the wallet holds (next to) no tokens of either
    // side, so the row is stale: sold, or claimed already. A redeem would
    // move nothing. A failed read (empty map) never blocks a claim.
    if (pos != null) {
      final ids = {pos.asset, pos.oppositeAsset}
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        final held = await onboarding.readCtfBalancesBatch(
            positionIds: ids, owner: proxyWallet);
        if (nothingHeldToClaim(ids, held)) {
          _devLog('[redeem] no outcome tokens on the wallet — abort');
          // A lost side with nothing left is cleared, as when the relayer
          // reports a zero balance below.
          if (pos.curPrice <= 0.02) {
            _treatLostAsCleared(conditionId);
            return 0;
          }
          throw const PolymarketNothingToClaimException();
        }
      }
    }

    // Don't submit a redeem the chain can't honour yet. The Data API
    // flips `redeemable` as soon as the MARKET resolves, but the CTF
    // only pays out once the oracle result is reported on Polygon
    // (payoutDenominator > 0) — a gap of minutes to (rarely) hours.
    // Redeeming inside the gap reverts or no-ops, which the old code
    // surfaced as the generic "Claim failed" / "no payout received"
    // that made winning users think their money was gone. Skip the
    // check on RPC failure (null) — never block a claim on a blip.
    final finalized = await onboarding.isConditionFinalized(conditionId);
    if (finalized == false) {
      _devLog('[redeem] condition not finalised on-chain yet — abort');
      throw const PolymarketResultNotOnChainException();
    }

    // V2: collateral on CTF redemption is pUSD (not USDC.e). The redeemed
    // payout lands in the Safe as pUSD; we unwrap it to USDC.e at the end.
    const kCtfAddress = PolymarketConstants.ctfAddress;
    const kCtfCollateralAdapterAddress =
        PolymarketConstants.ctfCollateralAdapterAddress;
    const kNegRiskCtfCollateralAdapterAddress =
        PolymarketConstants.negRiskCtfCollateralAdapterAddress;
    const kZero32 =
        '0000000000000000000000000000000000000000000000000000000000000000';

    final cleanCondition = conditionId.replaceFirst('0x', '').padLeft(64, '0');

    // Self-heal approvals before either redemption path. The redeem
    // can revert silently if any of these are missing:
    //   - CTF.setApprovalForAll(NegRiskCtfCollateralAdapter, true)
    //     (negRisk markets)
    //   - CTF.setApprovalForAll(CtfCollateralAdapter, true)
    //     (standard markets)
    //   - pUSD → CollateralOfframp (later unwrap step)
    // V2 approvals are baked into the deposit-wallet onboarding batch
    // (USDC.e → CTF/Exchanges/redeem adapters; CTF.setApprovalForAll
    // for every operator in the inventory). The legacy `fixMissingApprovals`
    // helper only handled the V1 Safe path — no longer relevant here.
    // If a redeem fails for missing-approval reasons, the user should
    // re-run `enableTrading` which re-batches the missing ones.
    _devLog('[redeem] V2 deposit wallet — approvals set at onboarding');

    String toAddress;
    String calldata;

    // Protocol V2 (binary and neg-risk alike): the shares sit on the
    // PositionManager and redeem through the Router, one
    // `redeem(bytes31, outcome, amount)` per held side, for its exact
    // balance (onboarding approved the Router as PositionManager operator).
    final v2Calls = pos != null && PolyMarketProtocol.isV2PositionId(pos.asset)
        ? await onboarding.v2RedeemCalls(
            positionId: pos.asset, owner: proxyWallet)
        : null;
    if (v2Calls != null && v2Calls.isEmpty) {
      if (pos!.curPrice <= 0.02) {
        _treatLostAsCleared(conditionId);
        return 0;
      }
      throw const PolymarketNothingToClaimException();
    }

    if (v2Calls != null) {
      toAddress = PolymarketConstants.comboRouterAddress;
      calldata = v2Calls.first.data;
    } else if (isNegRisk) {
      // NegRiskCtfCollateralAdapter (NEW — deployed by Polymarket
      // 2026-04-30, supersedes the legacy NegRiskAdapter for redeems).
      //
      // The new adapter exposes the SAME external signature as the
      // standard CTF.redeemPositions:
      //   redeemPositions(address, bytes32, bytes32 _conditionId, uint256[])
      // Selector: 0x01b7037c.
      //
      // Only `_conditionId` is actually used in the call — the other
      // three args (placeholder address, placeholder bytes32,
      // placeholder uint256[]) are kept for IConditionalTokens
      // interface compatibility. The adapter:
      //   1. derives positionIds from (WRAPPED_COLLATERAL, conditionId)
      //      internally — we don't pass them, we don't compute them
      //   2. reads msg.sender's (the Safe's) balance of both outcomes
      //   3. pulls those tokens from the Safe (requires
      //      setApprovalForAll(newAdapter, true) on CTF)
      //   4. calls the legacy NegRiskAdapter to do the actual redeem
      //   5. wraps the USDC.e payout into pUSD and sends to the Safe
      //
      // Previously we targeted the legacy NegRiskAdapter directly with
      // `redeemPositions(bytes32, uint256[])` (selector 0xdbeccb23) and
      // a manually-built amounts array. After the new adapter shipped,
      // recent NegRisk markets stopped redeeming through that path —
      // Polymarket's relayer prechecks the new adapter's positionId
      // space and (correctly) reported "zero position balance" for
      // calls aimed at the legacy contract.
      //
      // Source:
      //   github.com/Polymarket/ctf-exchange-v2/blob/main/src/adapters/
      //     NegRiskCtfCollateralAdapter.sol
      //
      // ABI layout (post-selector), 4 args at 32-byte slots:
      //   [0x00..0x20) address  (placeholder, 0x0 padded)
      //   [0x20..0x40) bytes32  (placeholder, 0x0)
      //   [0x40..0x60) bytes32  conditionId
      //   [0x60..0x80) uint256[] tail offset = 0x80
      //   [0x80..0xA0) uint256[] length = 0
      //   (no array elements — empty)
      const placeholderAddr = kZero32;
      const placeholderBytes32 = kZero32;
      final indexSetsTailOffset =
          (4 * 32).toRadixString(16).padLeft(64, '0'); // 0x80
      final indexSetsLengthZero =
          BigInt.zero.toRadixString(16).padLeft(64, '0');

      toAddress = kNegRiskCtfCollateralAdapterAddress;
      calldata = '01b7037c'
          '$placeholderAddr'
          '$placeholderBytes32'
          '$cleanCondition'
          '$indexSetsTailOffset'
          '$indexSetsLengthZero';
    } else {
      // Standard (non-NegRisk) redeem.
      //
      // PRIMARY: route through the NEW CtfCollateralAdapter at
      // `0xAdA100Db00Ca00073811820692005400218FcE1f` (deployed
      // 2026-04-29). Same shape as the NegRisk variant above —
      // 4-arg redeemPositions(address, bytes32, bytes32 _conditionId,
      // uint256[]) with only `_conditionId` actually used. The
      // adapter derives positionIds from `(pUSD, conditionId)`
      // internally, pulls outcome tokens from the Safe (msg.sender),
      // calls CTF.redeemPositions, and wraps the USDC.e payout back
      // into pUSD for the Safe. Mirrors how the NegRiskCtfCollateral-
      // Adapter wraps the legacy NegRiskAdapter.
      //
      // FALLBACK: kept the legacy direct-CTF path with USDC.e
      // collateral. Pre-V2 markets resolved on USDC.e (not pUSD),
      // so their positionId hash uses USDC.e as the collateral
      // address — calling the new adapter on those would derive
      // the wrong positionId and find zero balance. The
      // `_redeemFallbackCalldata` retry covers them.
      //
      // Source for new adapter: github.com/Polymarket/ctf-exchange-v2/
      //   src/adapters/CtfCollateralAdapter.sol
      const placeholderAddr = kZero32;
      const placeholderBytes32 = kZero32;
      final indexSetsTailOffset =
          (4 * 32).toRadixString(16).padLeft(64, '0'); // 0x80
      final indexSetsLengthZero =
          BigInt.zero.toRadixString(16).padLeft(64, '0');

      toAddress = kCtfCollateralAdapterAddress;
      calldata = '01b7037c'
          '$placeholderAddr'
          '$placeholderBytes32'
          '$cleanCondition'
          '$indexSetsTailOffset'
          '$indexSetsLengthZero';

      // Stash a direct-CTF USDC.e-collateral fallback for pre-V2
      // markets. Triggers via the cross-contract fallback below if
      // the new adapter precheck rejects.
      final indexSetsOffsetLegacy = (4 * 32).toRadixString(16).padLeft(64, '0');
      final indexSetsLengthLegacy =
          indexSets.length.toRadixString(16).padLeft(64, '0');
      final indexSetsEncodedLegacy =
          indexSets.map((s) => s.toRadixString(16).padLeft(64, '0')).join();
      final usdceCollatHex = PolymarketConstants.usdcEAddress
          .replaceFirst('0x', '')
          .padLeft(64, '0');
      _redeemFallbackCalldata = '01b7037c'
          '$usdceCollatHex'
          '$kZero32'
          '$cleanCondition'
          '$indexSetsOffsetLegacy'
          '$indexSetsLengthLegacy'
          '$indexSetsEncodedLegacy';
    }

    _devLog('[redeem] submitting Safe tx → $toAddress '
        'calldata.len=${calldata.length} '
        'selector=${calldata.substring(0, 8)}');

    // Diagnostic: read the on-chain ERC-1155 balance for the actual
    // positionId reported by the Data API (`pos.asset` = winning
    // outcome the user holds, `pos.oppositeAsset` = the other
    // outcome). Previously this used a buggy in-Dart positionId
    // derivation (`keccak(conditionId, outcome)`) that never
    // matched any real id — every read returned 0 and triggered
    // false-positive "settled" suppression. Now we trust the SDK's
    // ids (which are the actual storage keys on CTF) and query CTF
    // directly.
    //
    // Read BOTH the Safe AND the EOA so we can distinguish
    //   - Safe non-zero → redeem from Safe (current flow). Relayer
    //     precheck rejection is then a relayer-side bug.
    //   - EOA non-zero  → settlement-routing bug: tokens never
    //     reached the Safe. Redeem must be re-routed from EOA.
    //   - Both zero     → API stale (genuinely no claim tokens).
    if (isNegRisk && pos != null && v2Calls == null) {
      try {
        final yesAsset = pos.outcomeIndex == 0 ? pos.asset : pos.oppositeAsset;
        final noAsset = pos.outcomeIndex == 0 ? pos.oppositeAsset : pos.asset;
        final safeBalances = await onboarding.readNegRiskOutcomeBalances(
          yesPositionId: yesAsset,
          noPositionId: noAsset,
          owner: proxyWallet,
        );
        final eoaBalances = await onboarding.readNegRiskOutcomeBalances(
          yesPositionId: yesAsset,
          noPositionId: noAsset,
          owner: eoa,
        );
        final expectedMicro = BigInt.from(pos.size * 1000000);
        _devLog('[redeem][diag] safe=$proxyWallet '
            'yes=${safeBalances.$1} no=${safeBalances.$2} '
            'expected≈$expectedMicro outcomeIdx=${pos.outcomeIndex}');
        _devLog('[redeem][diag] eoa=$eoa '
            'yes=${eoaBalances.$1} no=${eoaBalances.$2}');
      } catch (e) {
        _devLog('[redeem][diag] negRisk balance read failed: '
            '${e.toString().split('\n').first}');
      }
    }

    // Read both possible payout token balances *before* the redeem so
    // we can detect which collateral the position actually credits.
    final pusdBefore = await onboarding.readErc20Balance(
      token: PolymarketConstants.pusdAddress,
      owner: proxyWallet,
    );
    final usdceBefore = await onboarding.readErc20Balance(
      token: PolymarketConstants.usdcEAddress,
      owner: proxyWallet,
    );
    _devLog('[redeem] pre-redeem balances: pUSD=$pusdBefore '
        'USDC.e=$usdceBefore micro');

    // Sign and submit via relayer. Returns the on-chain tx hash once
    // the relayer marks it mined.
    //
    // The relayer's pre-check ("PRECHECK_SKIPPED: redeem skipped:
    // zero position balance") fires when the Safe doesn't hold any
    // outcome tokens in the *specified collateral's* position-id
    // space. V2 markets use pUSD, but V1 / legacy markets use
    // USDC.e — so a winning legacy position fails the pUSD redeem
    // before it even goes on-chain. When that happens, retry with
    // the USDC.e calldata that we stashed during the calldata
    // build. This also catches the inverse case (a market that
    // resolved on USDC.e where pUSD was tried first).
    String txHash;
    try {
      txHash = v2Calls != null && v2Calls.length > 1
          ? await onboarding.executeDepositWalletBatch(
              eoaAddress: eoa,
              signer: CredentialsDepositWalletBatchSigner(wallet.privateKey),
              walletAddress: proxyWallet,
              calls: v2Calls,
              deadline: DateTime.now()
                      .add(const Duration(minutes: 10))
                      .millisecondsSinceEpoch ~/
                  1000,
            )
          : await onboarding.submitDepositWalletCall(
              eoaAddress: eoa,
              privateKey: wallet.privateKey,
              walletAddress: proxyWallet,
              to: toAddress,
              data: calldata,
            );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isPositionEmptyPrecheck = msg.contains('zero position balance') ||
          msg.contains('precheck_skipped');
      if (!isPositionEmptyPrecheck) {
        rethrow;
      }
      // Precheck rejected the SUBMITTED contract. The only alternate
      // redeem path left is the direct-CTF USDC.e-collateral calldata
      // stashed above for standard markets (legacy V1 markets that
      // resolved pre-pUSD cutover). NegRisk has a single path — the
      // NegRiskCtfCollateralAdapter — because the CLOB v1 Neg Risk
      // Adapter (0xd91E…) is deprecated and the relayer stopped
      // accepting redeems aimed at it on 2026-07-17; a NegRisk
      // precheck rejection therefore goes straight to the handling
      // below.
      final fallbackCalldata = _redeemFallbackCalldata;
      _redeemFallbackCalldata = null;
      String? fallbackTx;
      if (fallbackCalldata != null) {
        _devLog('[redeem] precheck zero-balance on $toAddress — '
            'trying USDC.e-collateral CTF fallback before giving up…');
        try {
          fallbackTx = await onboarding.submitDepositWalletCall(
            eoaAddress: eoa,
            privateKey: wallet.privateKey,
            walletAddress: proxyWallet,
            to: kCtfAddress,
            data: fallbackCalldata,
          );
          _devLog('[redeem] inverse-contract retry submitted to $kCtfAddress');
        } catch (e2) {
          final msg2 = e2.toString().toLowerCase();
          final inverseAlsoEmpty = msg2.contains('zero position balance') ||
              msg2.contains('precheck_skipped');
          if (!inverseAlsoEmpty) {
            rethrow;
          }
        }
      }
      if (fallbackTx == null) {
        // Every available contract rejected with the relayer's
        // zero-balance precheck. That used to be treated as "settled,
        // hide forever" — wrong. The relayer's precheck has historically
        // been buggy for Neg Risk (e.g. checking the wrong owner).
        // The diagnostic `[redeem][diag] safe=… eoa=…` above logs
        // the actual on-chain balances; if any of those four reads
        // came back non-zero, the relayer's verdict is a lie. Never
        // suppress — keep the row visible so the user can retry or
        // contact support.
        _devLog('[redeem] relayer precheck rejected every redeem path — '
            'see [redeem][diag] for actual on-chain balances.');
        // For a LOST position a zero-balance precheck isn't a broken
        // claim — there's nothing to pay out (the losing tokens may
        // already have been settled away). The user is just clearing
        // the row; treat it as cleared instead of scaring them with a
        // "contact support" error for $0.
        if (pos != null && pos.curPrice <= 0.02) {
          _devLog('[redeem] lost position with zero balance — '
              'treating as cleared');
          _treatLostAsCleared(conditionId);
          return 0;
        }
        throw Exception('Polymarket\'s relayer rejected this claim. The '
            'on-chain balance is logged in [redeem][diag] above. '
            'Please contact support and include this conditionId: '
            '$conditionId');
      }
      txHash = fallbackTx;
    }
    _devLog('[redeem] relayer returned txHash=$txHash');

    // Don't trust the relayer blindly: fetch the actual on-chain receipt
    // and verify status == success. `strict: true` so opaque relayer
    // ids and receipt-fetch timeouts throw instead of silently passing
    // — the silent-success path is exactly what lost the user's claim
    // earlier (UI said "claimed!" while no money moved on-chain).
    final ok = await onboarding.verifyReceipt(txHash, strict: true);
    _devLog('[redeem] verifyReceipt result: $ok');
    if (!ok) {
      throw Exception('Claim failed on-chain. Please try again in a moment.');
    }

    // Sanity check: did either pUSD or USDC.e increase? If neither did
    // and we have a USDC.e fallback queued (standard-CTF path only),
    // retry with USDC.e collateral. Legacy V1 markets land on USDC.e.
    var pusdAfter = await onboarding.readErc20Balance(
      token: PolymarketConstants.pusdAddress,
      owner: proxyWallet,
    );
    var usdceAfter = await onboarding.readErc20Balance(
      token: PolymarketConstants.usdcEAddress,
      owner: proxyWallet,
    );
    _devLog('[redeem] post-redeem balances: pUSD=$pusdAfter '
        'USDC.e=$usdceAfter micro');

    final pusdDelta = pusdAfter - pusdBefore;
    final usdceDelta = usdceAfter - usdceBefore;
    final didCredit = pusdDelta > BigInt.zero || usdceDelta > BigInt.zero;
    if (!didCredit && _redeemFallbackCalldata != null) {
      _devLog('[redeem] no payout — retrying with USDC.e collateral…');
      final fallbackTx = await onboarding.submitDepositWalletCall(
        eoaAddress: eoa,
        privateKey: wallet.privateKey,
        walletAddress: proxyWallet,
        to: kCtfAddress,
        data: _redeemFallbackCalldata!,
      );
      _devLog('[redeem] fallback txHash=$fallbackTx');
      // Same `strict: true` rationale as the primary path — the
      // fallback redeem is still a claim flow; silent success
      // without effect costs the user real money.
      final fbOk = await onboarding.verifyReceipt(fallbackTx, strict: true);
      if (!fbOk) throw Exception('Claim fallback failed on-chain.');
      txHash = fallbackTx;
      _devLog('[redeem] fallback verifyReceipt: $fbOk');
      pusdAfter = await onboarding.readErc20Balance(
        token: PolymarketConstants.pusdAddress,
        owner: proxyWallet,
      );
      usdceAfter = await onboarding.readErc20Balance(
        token: PolymarketConstants.usdcEAddress,
        owner: proxyWallet,
      );
      _devLog('[redeem] post-fallback balances: pUSD=$pusdAfter '
          'USDC.e=$usdceAfter micro');
    }
    _redeemFallbackCalldata = null;
    final finalPusdDelta = pusdAfter - pusdBefore;
    final finalUsdceDelta = usdceAfter - usdceBefore;
    // A LOST position redeems for exactly $0 — the tx burns the
    // worthless outcome tokens and credits nothing. That's success,
    // not failure: without this carve-out the zero-delta check below
    // threw "no payout was received" on every losing "Clear" tap,
    // even though the on-chain redeem had already gone through (the
    // row then vanished on the next refresh, making the error read
    // like a lie).
    final isLostPosition = pos != null && pos.curPrice <= 0.02;
    if (finalPusdDelta <= BigInt.zero &&
        finalUsdceDelta <= BigInt.zero &&
        !isLostPosition) {
      // Genuinely couldn't redeem — both attempts no-op'd. Surface so
      // the user knows the claim didn't credit, and so we DON'T mark
      // the position suppressed (otherwise the Claim row would vanish
      // from the home feed for 30 min while the funds stay claimable).
      // Tagged, not tracked here: the redeemPosition wrapper reports it
      // once with this fixed code plus the trigger/surface.
      final noPayout = Exception(
        'Claim transaction succeeded but no payout was received. '
        'The market may not be finalised yet.',
      );
      try {
        _redeemFailureCode[noPayout] = 'no_payout_credited';
      } catch (_) {}
      throw noPayout;
    }
    _devLog(
        '[redeem] credited: pUSD=+$finalPusdDelta USDC.e=+$finalUsdceDelta');

    // Task #170: redemption lands as pUSD in the Safe — that's the
    // canonical resting state now, so we don't sweep to USDC.e.
    // Subsequent bets draw straight from pUSD without an extra step;
    // a cashout via `withdrawUsdc` unwraps to USDC.e on demand. We
    // still invalidate the breakdown cache so the home tile updates
    // promptly with the new pUSD total.
    invalidateBalanceCache();

    // Task #129: auto-route to BTC DISABLED. Claimed proceeds now
    // remain as USDC in the Safe — the user sees them as their USDC
    // balance and can either use them for the next prediction or
    // explicitly convert to BTC via the (future) Move/Convert UI.
    // The per-bet funding-currency tag stays recorded in Hive (we
    // don't `.clear()` here anymore) so a future "convert proceeds
    // back to original funding currency" affordance has the data it
    // needs. Note: this means the Hive box can grow — small price,
    // and the future UI can wipe stale tags itself.
    _devLog('[redeem] proceeds held as USDC: '
        '+${finalUsdceDelta + finalPusdDelta} micro');

    // Record the successful on-chain claim — both in-memory AND on
    // disk via PolymarketSuppressionService. Without the disk-side
    // mark, restarting the app would clear the in-memory map and the
    // Data API (still showing the position as redeemable for a while)
    // would surface the Claim row again — exactly the bug the user
    // hit.
    _recentlyClaimedIds[conditionId] = DateTime.now();
    PolymarketSuppressionService.mark(conditionId);
    _knownRedeemableIds.remove(conditionId);
    _devLog('[redeem] suppression mark persisted for $conditionId');

    // The receipt isolates this claim even when other wallet operations ran
    // concurrently. Refresh absolute cash instead of adding proceeds twice.
    final credited = onboarding.confirmedClaimCredit(txHash, proxyWallet);
    final refreshedCash =
        await _publicModel?.getOnChainUsdcBalance(proxyWallet);
    final latestState = state.valueOrNull;
    final payoutUsdc = credited ?? 0.0;
    String outcome = 'unknown';
    if (latestState != null) {
      final redeemedPos = latestState.openPositions
          .where((p) => p.conditionId == conditionId)
          .firstOrNull;
      outcome = redeemedPos?.outcome.toLowerCase() ?? 'unknown';
      _setData(latestState.copyWith(
        openPositions: latestState.openPositions
            .where((p) => p.conditionId != conditionId)
            .toList(),
        usdcBalance: refreshedCash ?? latestState.usdcBalance,
        // If the lagging Data API resurrects this row on the next
        // refresh, it comes back LOCKED as "Clearing…" (see
        // clearingConditionIds) instead of a tappable Claim/Clear the
        // user already pressed.
        clearingConditionIds: _clearingIdsSnapshot(),
      ));
    }

    // Analytics — the redeem is on-chain confirmed AND the balance
    // delta verified. Fire `polymarketPositionRedeemed` (was defined
    // but never called) so wins/losses appear in BigQuery. The win/
    // loss event is a separate emit so the cohort funnel can be built
    // off it independently of the routine redemption noise.
    final redeemedPos = latestState?.openPositions
        .where((p) => p.conditionId == conditionId)
        .firstOrNull;
    TrackingService.polymarketPositionRedeemed(
      marketId: conditionId,
      outcome: outcome,
      shares: redeemedPos?.size ?? 0.0,
      payout: payoutUsdc,
      trigger: trigger,
      surface: surface,
      walletKind: 'hot',
    );
    // A payout includes returned stake. Only unlock a profit milestone when
    // it exceeds a known cost basis.
    final redeemedCost = latestState?.openPositions
            .where((p) => p.conditionId == conditionId)
            .fold<double>(0, (sum, p) => sum + p.initialValue) ??
        0;
    // pnl is the payout net of cost basis (not the raw payout), and the
    // outcome is win/loss (not the backed outcome's name, which is already
    // on polymarket_position_redeemed).
    TrackingService.polymarketPositionWinLoss(
      marketId: conditionId,
      pnl: payoutUsdc - redeemedCost,
      outcome: payoutUsdc > 0 ? 'win' : 'loss',
    );
    if (credited != null && redeemedCost > 0 && credited > redeemedCost) {
      TrackingService.polymarketFirstProfitableRedeem(
          pnl: credited - redeemedCost);
      // In-app celebration card + mascot's `winPrediction` pose.
      // Losses and returned stake do not unlock this milestone.
      try {
        ref
            .read(pendingMilestoneProvider.notifier)
            .unlock(MilestoneKeys.firstRedeemProfit);
      } catch (_) {}
      try {
        ref
            .read(kuteStateProvider.notifier)
            .onPredictionWin(payoutUsdc: payoutUsdc);
      } catch (_) {}
    }

    // Automatic claims can remove a winning position before the inbox poll.
    // Persist the result here too, using the same settlement identity.
    if (credited != null && redeemedPos != null) {
      try {
        final payout = await onboarding.settledPayout(
            conditionId, redeemedPos.outcomeIndex);
        if (payout != null) {
          final matching = latestState!.openPositions
              .where((p) => p.conditionId == conditionId)
              .toList();
          final cost =
              matching.fold<double>(0, (sum, p) => sum + p.initialValue);
          await TradeNotificationStore.add(TradeNotification(
            id: 'pm:${proxyWallet.toLowerCase()}:${redeemedPos.asset}:$payout',
            account: proxyWallet.toLowerCase(),
            product: 'predictions',
            title: payout == 1 ? 'Prediction won' : 'Prediction settled',
            subtitle: redeemedPos.title,
            time: DateTime.now().millisecondsSinceEpoch,
            positive: payout == 1 && cost > 0 && credited > cost,
            rows: {
              'Claim credited': '\$${credited.toStringAsFixed(2)}',
              'Destination': 'Predictions balance',
              if (cost > 0)
                'Position cost basis': '\$${cost.toStringAsFixed(2)}',
              'Profit details': 'Additional fees may affect net profit',
            },
          ));
        }
      } catch (_) {
        /* A notification failure must not fail a confirmed claim. */
      }
    }

    // Background refresh to sync with actual on-chain state
    for (final delay in [2, 5, 10]) {
      Future.delayed(Duration(seconds: delay), () {
        try {
          refresh();
        } catch (_) {}
      });
    }
    return credited;
  }

  // Task #170: the previous `autoSweepIfIdle` / `_runSweepSafeToUsdcE`
  // / `sweepProceedsToUsdcE` trio normalized everything to USDC.e on
  // every refresh tick. New spec: pUSD is the resting state. At-rest
  // balances must NOT be touched by background work. The deposit
  // path now fires a one-shot `wrapIncomingUsdcEToPusd` after Orchestra
  // delivers; the withdraw path unwraps pUSD on demand inside
  // `withdrawUsdc`. Won/sold proceeds land as pUSD and stay there.

  /// Fire-and-forget wrap: polls the Safe's USDC.e balance for up to
  /// [timeout] after a deposit completes, and when it crosses zero
  /// wraps the full amount → pUSD via CollateralOnramp.
  ///
  /// Called from the BTC → predictions deposit flow once Orchestra has
  /// `submitDeposit`-acked the order. Orchestra typically credits the
  /// Safe within 1–3 minutes of the BTC tx landing on Spark; this poll
  /// detects that arrival and wraps it so the end state is pUSD per
  /// the resting-state contract.
  ///
  /// Skipped silently while a prediction is routing — that in-flight
  /// USDC.e would be mid-bet collateral, not a deposit arrival.
  ///
  /// Idempotent at the contract level: a second `wrap()` call on a
  /// zero balance no-ops.
  /// V2 deposit-wallet wrap-on-arrival poll. Watches the deposit wallet
  /// for incoming USDC.e (from an Orchestra deposit, a sell, or a claim)
  /// and wraps it to pUSD so it becomes V2 trading collateral.
  ///
  /// Polls every [interval] for up to [timeout]. First non-zero USDC.e
  /// read triggers a single wrap call via the deposit-wallet relayer
  /// batch, then exits. The in-flight mutex in
  /// [PolymarketOnboardingService.executeDepositWalletBatch] coalesces
  /// against any other batched action so we don't double-up with the
  /// approvals tick.
  ///
  /// IMPORTANT: don't call this from `withdrawUsdc` — withdraw unwraps
  /// pUSD → USDC.e in the same wallet, and a poll racing the unwrap
  /// would re-wrap the funds mid-flight and break "max withdraw". The
  /// withdraw path uses [scheduleDelayedUsdceRewrap] instead, which
  /// only fires AFTER a 5-min cool-off so any in-flight swap finishes
  /// first.
  ///
  /// One watch runs at a time: a call while one runs only pushes its end
  /// out, so a deposit sent from the Move sheet and the same deposit's
  /// order completing in the background sync never start two. Every
  /// conversion goes through [_wrapHeldUsdcE].
  void wrapIncomingUsdcEToPusd({
    Duration timeout = const Duration(minutes: 8),
    Duration interval = const Duration(seconds: 4),
  }) {
    final until = DateTime.now().add(timeout);
    final running = _wrapWatchUntil;
    if (running == null || until.isAfter(running)) _wrapWatchUntil = until;
    if (running != null) return;
    Future.microtask(() async {
      try {
        while (!_disposed && DateTime.now().isBefore(_wrapWatchUntil!)) {
          try {
            final current = state.valueOrNull;
            final eoa = current?.walletAddress;
            final wallet = current?.proxyWalletAddress;
            final key = _privateKey;
            if (current == null ||
                eoa == null ||
                wallet == null ||
                wallet.isEmpty ||
                key == null) {
              return;
            }
            // A first deposit can land while the wallet's one-time setup
            // (deployment, approvals) is still running. A conversion then
            // fails without the onramp approval and, while its batch runs,
            // refuses the setup's own approvals batch. Keep watching and
            // convert once setup is done.
            if (!tradingReady) {
              await Future<void>.delayed(interval);
              continue;
            }
            final wrapped = await _wrapHeldUsdcE(
              eoa: eoa,
              privateKey: key,
              wallet: wallet,
              trigger: 'arrival',
            );
            if (wrapped > BigInt.zero) return;
          } catch (e) {
            _devLog('[wrap] poll threw: $e — retrying');
          }
          await Future<void>.delayed(interval);
        }
      } finally {
        _wrapWatchUntil = null;
      }
    });
  }

  /// When the running [wrapIncomingUsdcEToPusd] watch stops; null when
  /// none runs.
  DateTime? _wrapWatchUntil;

  /// One conversion at a time per deposit wallet (usdce_wrap_gate.dart).
  final UsdceWrapGate _wrapGate = UsdceWrapGate();

  /// Withdrawals in flight. A withdrawal sizes one batch from the wallet's
  /// pUSD and USDC.e read just before it; a conversion landing in between
  /// would have that batch refused, so the idle conversion waits.
  int _withdrawsInFlight = 0;

  /// Below this much USDC.e (one cent) there is nothing worth converting
  /// when the app opens.
  static final BigInt _kIdleWrapDustMicros = BigInt.from(10000);

  /// When [wrapIdleUsdcE] last read the wallet.
  DateTime? _idleWrapCheckedAt;

  /// Converts every micro-USDC.e the deposit wallet holds right now to
  /// pUSD (never more than the balance read before signing), through the
  /// shared gate: a caller arriving while a conversion runs gets that one's
  /// result. Returns the micro-USDC.e converted, zero when there was none.
  Future<BigInt> _wrapHeldUsdcE({
    required String eoa,
    required String privateKey,
    required String wallet,
    required String trigger,
    void Function()? ensureCurrent,
  }) {
    return _wrapGate.run(wallet, () async {
      final wrapped = await PolymarketOnboardingService()
          .wrapHeldUsdceToPusdInDepositWallet(
        eoaAddress: eoa,
        privateKey: privateKey,
        walletAddress: wallet,
        ensureCurrent: ensureCurrent,
      );
      if (wrapped > BigInt.zero) {
        invalidateBalanceCache();
        // The order book keeps its own count of the wallet's pUSD and only
        // re-reads it on request. A deposit converted in the background
        // was otherwise still counted as 0 by the venue, which refused the
        // first prediction after it.
        try {
          await _backendService
              ?.updateBalanceAllowance(
                  assetType: 'COLLATERAL', signatureType: 3)
              .timeout(const Duration(seconds: 8));
        } catch (_) {
          // The order path refreshes it again on a refusal.
        }
        TrackingService.polymarketDepositConverted(
            amountUsd: wrapped.toDouble() / 1e6, trigger: trigger);
      }
      return wrapped;
    });
  }

  /// A deposit that landed while the app was closed is still USDC.e. On
  /// app resume, on Predictions open and when the account starts, convert
  /// it once: at most one read every 30 s, only for an unlocked session,
  /// and never during a withdrawal or while a claim is waiting (a claim
  /// reads the wallet's balances around its redeem).
  Future<void> wrapIdleUsdcE({required String trigger}) async {
    if (_disposed || _withdrawsInFlight > 0) return;
    final now = DateTime.now();
    final last = _idleWrapCheckedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 30)) {
      return;
    }
    final current = state.valueOrNull;
    final eoa = current?.walletAddress;
    final wallet = current?.proxyWalletAddress;
    final key = _privateKey;
    if (current == null ||
        eoa == null ||
        wallet == null ||
        wallet.isEmpty ||
        key == null ||
        // Not before the one-time setup is done (see the arrival watch).
        !tradingReady ||
        !ref.read(sessionUnlockedProvider) ||
        current.openPositions.any((p) => p.redeemable) ||
        _wrapGate.isRunning(wallet)) {
      return;
    }
    _idleWrapCheckedAt = now;
    try {
      final usdce = await PolymarketOnboardingService().readErc20Balance(
        token: PolymarketConstants.usdcEAddress,
        owner: wallet,
      );
      if (usdce < _kIdleWrapDustMicros ||
          _disposed ||
          _withdrawsInFlight > 0 ||
          state.valueOrNull?.proxyWalletAddress?.toLowerCase() !=
              wallet.toLowerCase()) {
        return;
      }
      await _wrapHeldUsdcE(
          eoa: eoa, privateKey: key, wallet: wallet, trigger: trigger);
    } catch (e) {
      _devLog('[wrap] idle conversion threw: $e');
    }
  }

  /// Withdraw cleanup. The withdraw flow does `unwrap pUSD → USDC.e →
  /// swap → send`; any USDC.e left over after the swap stays in the
  /// wallet. We can't wrap it back immediately (would race the in-flight
  /// swap and break max withdraw). Schedule the re-wrap for [after] later
  /// — long enough that any pending swap has landed.
  ///
  /// If new outbound activity happens before the timer fires, no harm:
  /// `wrapUsdceToPusdInDepositWallet` reads the current balance at fire
  /// time and no-ops if there's nothing left.
  void scheduleDelayedUsdceRewrap({
    Duration after = const Duration(minutes: 5),
  }) {
    Timer(after, () async {
      try {
        final current = state.valueOrNull;
        final eoa = current?.walletAddress;
        final wallet = current?.proxyWalletAddress;
        if (current == null ||
            eoa == null ||
            wallet == null ||
            wallet.isEmpty ||
            _privateKey == null) {
          return;
        }
        final wrapped =
            await PolymarketOnboardingService().wrapUsdceToPusdInDepositWallet(
          eoaAddress: eoa,
          privateKey: _privateKey!,
          walletAddress: wallet,
        );
        if (wrapped) {
          _devLog('[wrap] post-withdraw delayed rewrap landed');
          invalidateBalanceCache();
        }
      } catch (e) {
        _devLog('[wrap] post-withdraw delayed rewrap threw: $e');
      }
    });
  }

  /// V2 deposit-wallet withdraw. Sends [amount] USD-equivalent from the
  /// wallet to [toAddress] on Polygon in a single batched relayer tx.
  /// Converts the Safe's stranded NATIVE USDC into USDC.e (one Uniswap
  /// V3 stable-stable hop, output straight back to the Safe) so it
  /// becomes spendable and withdrawable again. Task #170 removed the
  /// background sweep that normalized this automatically; this is the
  /// user-triggered replacement, surfaced by the claim-winnings sheet
  /// whenever the stables breakdown shows native USDC. Returns the
  /// batch tx hash. The Uniswap allowance for native USDC is granted
  /// during onboarding, so no approval leg is needed here.
  Future<String> convertNativeUsdcToUsdce() async {
    await RuntimeCapabilitiesService.instance
        .ensureAllowed('polymarket.withdraw');
    final current = state.valueOrNull;
    if (current == null || current.walletAddress == null) {
      throw Exception('No wallet address');
    }
    final eoa = current.walletAddress!;
    final proxyWallet = current.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      throw Exception('Trading not enabled');
    }

    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) {
      throw Exception('No spending wallet.');
    }
    final session = ref.read(seedSessionProvider);
    if (!session.unlocked) {
      throw Exception('Wallet locked. Please unlock first.');
    }
    final mnemonic = await resolveBip39MnemonicFor(spending,
        access: SeedAccess.automatic, session: session);
    if (mnemonic == null) {
      throw Exception('Could not decrypt spending wallet');
    }
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);

    final onboarding = PolymarketOnboardingService();
    final usdcBal = await onboarding.readErc20Balance(
      token: PolymarketConstants.usdcAddress,
      owner: proxyWallet,
    );
    if (usdcBal <= BigInt.from(10000)) {
      // Nothing material to convert (a cent or less).
      throw Exception('No native USDC to convert.');
    }

    final swapData = DexSwapService.encodeUsdcToUsdce(
      amount: usdcBal,
      recipient: proxyWallet,
    );
    final deadline = DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch ~/
        1000;
    final txHash = await onboarding.executeDepositWalletBatch(
      eoaAddress: eoa,
      signer: CredentialsDepositWalletBatchSigner(wallet.privateKey),
      walletAddress: proxyWallet,
      calls: [
        (
          target: PolymarketConstants.uniswapV3SwapRouter,
          value: BigInt.zero,
          data: swapData,
        ),
      ],
      deadline: deadline,
    );
    TrackingService.track('polymarket_native_usdc_converted', params: {
      'amount_bucket': TrackingService.usdBucket(usdcBal.toDouble() / 1e6),
    });

    // The breakdown provider re-reads on trading-state ticks; nudge a
    // refresh so the claim sheet's figures update without a restart.
    unawaited(refresh());
    return txHash;
  }

  ///
  /// With V2 deposit wallets there's no pUSD layer — USDC.e is the
  /// at-rest token (and the direct trading collateral). The withdraw
  /// path is:
  ///   bridged=true  →  USDC.e transfer (1 call)
  ///   bridged=false →  USDC.e→USDC Uniswap V3 swap + USDC transfer
  ///                    (2 calls in the same batch)
  ///
  /// The Uniswap swap routes recipient = toAddress directly so we don't
  /// need a separate transfer leg for the false branch; on-chain the
  /// swap router's `exactInputSingle` lands USDC at the recipient.
  ///
  /// Returns the on-chain tx hash of the batch. Withdrawable collateral
  /// is pUSD + USDC.e only; native USDC sitting in the Safe is NOT
  /// directly withdrawable here (it must be swept/converted first). A
  /// request that exceeds the withdrawable balance by more than a
  /// rounding epsilon throws rather than silently sending less and
  /// reporting the full amount to the caller's success UI.
  ///
  /// [exactMicroUsdc] binds the send to a quoted amount: exactly that many
  /// micro-USDC leave, and a balance that cannot cover it throws instead
  /// of clamping. Quote it from [payableMicroUsdc].
  ///
  /// [grant] (Phase 1b.4) is an Orchestra-funded `venueWithdraw`, `send` or
  /// `moveTransfer` grant, and it only covers a quote-bound
  /// [exactMicroUsdc] paid to the Orchestra quote's deposit address. It is
  /// checked before the seed is read and consumed right before the batch is
  /// signed.
  Future<String> withdrawUsdc({
    required String toAddress,
    required double amount,
    bool bridged = false,
    BigInt? exactMicroUsdc,
    required AuthGrant grant,
  }) async {
    // A quote-bound withdrawal was gated on this same capability by its
    // Orchestra quote moments ago; a policy fetched within the last
    // minute is read, not fetched again, the way an order post re-checks
    // after its slip. Any other withdrawal fetches the policy as before.
    await RuntimeCapabilitiesService.instance.ensureAllowed(
        'polymarket.withdraw',
        maxAge: exactMicroUsdc != null
            ? const Duration(seconds: 60)
            : Duration.zero);
    // Validate the destination BEFORE any signing/relayer call. The ABI
    // encoders left-pad to 64 chars, so a malformed address (pasted tx
    // hash, truncated string) would otherwise be sent funds at a
    // zero-padded address nobody controls. Fail loudly instead.
    if (!DexSwapService.isValidEvmAddress(toAddress)) {
      throw Exception(l10nForLanguage(ref.read(settingsProvider).language)
          .invalidRecipientNothingSent);
    }
    final current = state.valueOrNull;
    if (current == null || current.walletAddress == null) {
      throw Exception('No wallet address');
    }
    final eoa = current.walletAddress!;
    final proxyWallet = current.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      throw Exception('Trading not enabled');
    }

    // Phase 1b.4: nothing is read or signed unless the grant covers this
    // withdrawal. A clamp below only lowers the amount, so the requested
    // figure is the most this call can send.
    SensitiveIntent executedWithdraw(BigInt micros) =>
        PmGrants.executedWithdraw(
          grant,
          account: proxyWallet,
          amountMicros: micros,
          bridged: bridged,
          quoteBound: exactMicroUsdc != null,
        );
    GrantGuard.check(
      grant,
      executedWithdraw(exactMicroUsdc ?? BigInt.from((amount * 1e6).round())),
      allowed: PmGrants.withdrawActions,
    );

    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) {
      throw Exception(
          'No spending wallet. Polymarket withdraws need the hot wallet that owns the deposit wallet.');
    }
    final onboarding = PolymarketOnboardingService();
    _withdrawsInFlight++;
    return HotPolymarketWithdrawalGuard().run(
      walletId: spending.id,
      depositWallet: proxyWallet,
      transactionState: onboarding.relayerTransactionState,
      // The same pUSD + USDC.e spendable figure the batch is sized from.
      depositWalletBalance: () =>
          _readSpendableMicroUsdc(onboarding, proxyWallet),
      submit: ({required beforeSubmit, required onSubmitted}) async {
        void checkAccount() {
          final latest = state.valueOrNull;
          if (!ref.read(seedSessionProvider).unlocked ||
              pickSpendingWallet(ref.read(settingsProvider))?.id !=
                  spending.id ||
              latest?.walletAddress?.toLowerCase() != eoa.toLowerCase() ||
              latest?.proxyWalletAddress?.toLowerCase() !=
                  proxyWallet.toLowerCase()) {
            throw StateError(
                'Predictions account changed. Review the withdrawal again.');
          }
        }

        checkAccount();
        final session = ref.read(seedSessionProvider);
        if (!session.unlocked) {
          throw Exception('Wallet locked. Please unlock first.');
        }
        final mnemonic = await resolveBip39MnemonicFor(spending,
            access: SeedAccess.automatic, session: session);
        if (mnemonic == null) {
          throw Exception('Could not decrypt spending wallet');
        }
        final wallet = await EvmWalletDerivation.deriveWalletAsync(
            mnemonic: mnemonic,
            version: spending.evmDerivationVersion,
            index: 0);
        checkAccount();
        if (wallet.address.toLowerCase() != eoa.toLowerCase()) {
          throw StateError(
              'Predictions account changed. Review the withdrawal again.');
        }

        // V2 deposit wallet holds pUSD as its canonical collateral. To
        // withdraw we:
        //   1. unwrap pUSD → USDC.e (CollateralOfframp.unwrap)
        //   2. transfer USDC.e to dest (bridged=true) OR swap USDC.e → USDC
        //      via Uniswap then transfer (bridged=false)
        // All three calls go through ONE executeDepositWalletBatch so
        // they're atomic + a single signature + a single relayer fee.
        //
        // If the wallet also has some loose USDC.e (e.g. from a deposit
        // that hasn't been wrapped yet), include it in the spendable
        // total — no need to wrap then immediately unwrap.
        final balances = await Future.wait([
          onboarding.readErc20Balance(
            token: PolymarketConstants.pusdAddress,
            owner: proxyWallet,
          ),
          onboarding.readErc20Balance(
            token: PolymarketConstants.usdcEAddress,
            owner: proxyWallet,
          ),
        ]);
        final usdceBal = balances[1];
        final spendable = balances[0] + usdceBal;
        final amountAtomic = exactMicroUsdc != null
            ? checkExactWithdrawMicroUsdc(exactMicroUsdc, spendable)
            : clampWithdrawMicroUsdc(
                BigInt.from((amount * 1e6).round()), spendable);

        // Phase 1b.4: consume against exactly what the batch sends, before it is
        // signed.
        checkAccount();
        GrantGuard.consume(grant, executedWithdraw(amountAtomic),
            allowed: PmGrants.withdrawActions);

        // How much pUSD we actually need to unwrap to top up USDC.e.
        final unwrapMicro =
            amountAtomic > usdceBal ? (amountAtomic - usdceBal) : BigInt.zero;

        final calls = <({String target, BigInt value, String data})>[];

        // Step 1 — unwrap pUSD → USDC.e (only if needed).
        if (unwrapMicro > BigInt.zero) {
          calls.add((
            target: onboarding.collateralOfframpAddress,
            value: BigInt.zero,
            data: '0x${onboarding.encodeUnwrapCall(
              PolymarketConstants.usdcEAddress,
              proxyWallet,
              unwrapMicro,
            )}',
          ));
        }

        if (bridged) {
          // Step 2 — single ERC-20 transfer of USDC.e to dest. Validated
          // (not raw-padded) so a malformed toAddress can't be coerced into
          // a different valid address.
          final cleanTo = DexSwapService.abiEncodeAddress(toAddress);
          final amountHex = amountAtomic.toRadixString(16).padLeft(64, '0');
          calls.add((
            target: PolymarketConstants.usdcEAddress,
            value: BigInt.zero,
            data: '0xa9059cbb$cleanTo$amountHex',
          ));
        } else {
          // Step 2 — USDC.e → native USDC swap; Uniswap V3 router drops
          // the output at `toAddress` directly so no extra transfer leg.
          final swapData = DexSwapService.encodeUsdceToUsdc(
            amount: amountAtomic,
            recipient: toAddress,
          );
          calls.add((
            target: PolymarketConstants.uniswapV3SwapRouter,
            value: BigInt.zero,
            data: swapData,
          ));
        }

        // Optimistic UI deduction.
        final preSendBalance = current.usdcBalance;
        _setData(current.copyWith(
          usdcBalance: (current.usdcBalance - amount).clamp(0, double.infinity),
        ));

        final deadline = DateTime.now()
                .add(const Duration(minutes: 10))
                .millisecondsSinceEpoch ~/
            1000;
        final txHash = await onboarding.executeDepositWalletBatch(
          eoaAddress: eoa,
          signer: CredentialsDepositWalletBatchSigner(wallet.privateKey),
          walletAddress: proxyWallet,
          calls: calls,
          deadline: deadline,
          requireConfirmed: true,
          beforeSubmit: (nonce) async {
            checkAccount();
            await beforeSubmit(nonce,
                amountMicros: amountAtomic, balanceMicros: spendable);
            checkAccount();
          },
          onSubmitted: onSubmitted,
        );

        // Fee accounting for the Uniswap leg (false branch only).
        if (!bridged) {
          try {
            final amountIn = amountAtomic.toDouble() / 1e6;
            final feeUsd = amountIn * 0.0001;
            if (feeUsd > 0) {
              FeeHistoryService.log(
                id: txHash,
                kind: FeeKind.uniswapSwap,
                microUsd: (feeUsd * 1000000).round(),
                nativeAmount: feeUsd.toStringAsFixed(6),
                nativeUnit: 'usdc',
                source: 'Uniswap V3',
                txId: txHash,
                walletId: spending.id,
              );
            }
          } catch (_) {}
        }

        // Poll on-chain balance until it reflects the send, *without*
        // letting stale reads overwrite the optimistic deduction. Two
        // failure modes we saw before:
        //   1) RPC hadn't indexed the new balance yet; refresh() pulled
        //      the pre-send amount and the UI bounced from 0 back up to
        //      the old balance until the next poll caught up.
        //   2) The wallet looked "stuck" until the user force-restarted.
        // Strategy: refetch at 3/6/10/20/40s and only apply the new
        // balance once it actually differs from preSendBalance (i.e. the
        // chain reflects the transfer). If all polls return stale, we
        // leave the optimistic value in place — a restart isn't needed.
        for (final delay in [3, 6, 10, 20, 40]) {
          Future.delayed(Duration(seconds: delay), () async {
            try {
              final latest = state.valueOrNull;
              if (latest == null ||
                  latest.walletAddress == null ||
                  _publicModel == null) {
                return;
              }
              final data = await _fetchAllData(
                latest.walletAddress!,
                proxyWallet: latest.proxyWalletAddress,
              );
              // Stale read — RPC hasn't seen the transfer. Ignore so we
              // don't unwind the optimistic deduction.
              if ((data.usdcBalance - preSendBalance).abs() < 0.000001) return;
              _setData(data.copyWith(isAuthenticated: latest.isAuthenticated));
            } catch (_) {}
          });
        }
        return txHash;
      },
    ).whenComplete(() => _withdrawsInFlight--);
  }

  /// The deposit wallet's pUSD and USDC.e, read side by side, or null
  /// when either read fails or takes over 5 s: the order then goes on as
  /// before and the refusal path converts if needed.
  PolymarketSendTimeRead<({BigInt pusd, BigInt usdce})?>? _splitPrefetch;
  String? _splitPrefetchWallet;

  /// Starts the reads a buy makes before it is signed (the deposit
  /// wallet's pUSD and USDC.e) while its approval is on screen, so the
  /// order does not wait for them after it. Used within 20 seconds.
  void prefetchOrderReads() {
    final wallet = state.valueOrNull?.proxyWalletAddress;
    _splitPrefetch?.cancel();
    _splitPrefetch = null;
    if (wallet == null || wallet.isEmpty) return;
    _splitPrefetchWallet = wallet.toLowerCase();
    _splitPrefetch = PolymarketSendTimeRead<({BigInt pusd, BigInt usdce})?>(
        () => _readCollateralSplit(wallet),
        maxAge: const Duration(seconds: 20))
      ..start();
  }

  /// The pUSD / USDC.e split for a buy: the prefetched read for [wallet]
  /// when there is one, else a new read. A stale "pUSD covers it" costs
  /// nothing: the order book's balance refusal still converts and retries.
  Future<({BigInt pusd, BigInt usdce})?> _collateralSplitForOrder(
      String wallet) {
    final prefetched = _splitPrefetch;
    _splitPrefetch = null;
    if (prefetched != null && _splitPrefetchWallet == wallet.toLowerCase()) {
      return prefetched.take();
    }
    prefetched?.cancel();
    return _readCollateralSplit(wallet);
  }

  static Future<({BigInt pusd, BigInt usdce})?> _readCollateralSplit(
      String wallet) async {
    try {
      final onboarding = PolymarketOnboardingService();
      final balances = await Future.wait([
        onboarding.readErc20Balance(
            token: PolymarketConstants.pusdAddress, owner: wallet),
        onboarding.readErc20Balance(
            token: PolymarketConstants.usdcEAddress, owner: wallet),
      ]).timeout(const Duration(seconds: 5));
      return (pusd: balances[0], usdce: balances[1]);
    } catch (_) {
      return null;
    }
  }

  /// The micro-USDC [withdrawUsdc] would send for [amount] from the
  /// deposit wallet's current pUSD + USDC.e balance. Quote-bound flows
  /// quote this figure, then pass the quoted amount as `exactMicroUsdc`.
  Future<BigInt> payableMicroUsdc(double amount) async {
    return clampWithdrawMicroUsdc(
        BigInt.from((amount * 1e6).round()), await spendableMicroUsdc());
  }

  /// Everything [withdrawUsdc] can send right now: the deposit wallet's
  /// live pUSD + USDC.e, read on-chain, in micro-USDC. This is what a
  /// 100% withdrawal quotes and sends. The displayed Predictions balance
  /// also counts native USDC (which this path cannot move) and is cached,
  /// so sizing "everything" from it could ask for more than the batch
  /// can fund and be refused.
  Future<BigInt> spendableMicroUsdc() async {
    final proxyWallet = state.valueOrNull?.proxyWalletAddress;
    if (proxyWallet == null || proxyWallet.isEmpty) {
      throw Exception('Trading not enabled');
    }
    final onboarding = PolymarketOnboardingService();
    return _readSpendableMicroUsdc(onboarding, proxyWallet);
  }

  /// The deposit wallet's pUSD + USDC.e, in micro-USDC. The two reads are
  /// independent, so they run side by side rather than one after the
  /// other; a failed read still throws its own error.
  static Future<BigInt> _readSpendableMicroUsdc(
      PolymarketOnboardingService onboarding, String proxyWallet) async {
    final balances = await Future.wait([
      onboarding.readErc20Balance(
        token: PolymarketConstants.pusdAddress,
        owner: proxyWallet,
      ),
      onboarding.readErc20Balance(
        token: PolymarketConstants.usdcEAddress,
        owner: proxyWallet,
      ),
    ]);
    return balances[0] + balances[1];
  }

  /// Tolerates sub-cent rounding (Max computes the amount as a USD
  /// double, so the atomic figure can land a hair above the on-chain
  /// balance) by clamping to [spendable]. Rejects a MATERIAL shortfall:
  /// it means the requested amount counted native USDC that this path
  /// can't withdraw, and silently sending less while the caller's modal
  /// reports the full amount is the bug this prevents.
  @visibleForTesting
  static BigInt clampWithdrawMicroUsdc(BigInt requested, BigInt spendable) {
    if (spendable <= BigInt.zero) {
      throw Exception('Insufficient balance. Wallet is empty.');
    }
    final overage = requested - spendable;
    if (overage <= BigInt.zero) return requested;
    if (overage > BigInt.from(10000)) {
      final avail = spendable.toDouble() / 1e6;
      throw Exception(
          'Only \$${avail.toStringAsFixed(2)} is available to withdraw '
          'right now. Native USDC must be converted before it can be sent.');
    }
    return spendable;
  }

  /// A quote-bound withdrawal sends exactly [quoted] or nothing.
  @visibleForTesting
  static BigInt checkExactWithdrawMicroUsdc(BigInt quoted, BigInt spendable) {
    if (quoted <= BigInt.zero || quoted > spendable) {
      throw const WalletGuardException(WalletGuardReason.amountMismatch);
    }
    return quoted;
  }

  Future<void> enableTrading({
    void Function(String status)? onProgress,
    bool force = false,
  }) {
    final current = state.valueOrNull;
    if (current == null || current.walletAddress == null) {
      return Future.error(StateError('No wallet address'));
    }
    final walletId = _spendingWalletId;
    if (walletId == null) {
      return Future.error(StateError('No spending wallet'));
    }
    final eoa = current.walletAddress!;
    final generation = _accountGeneration;
    final session = ref.read(sessionAuthProvider);
    bool isCurrent() =>
        !_disposed &&
        generation == _accountGeneration &&
        _spendingWalletId == walletId &&
        state.valueOrNull?.walletAddress?.toLowerCase() == eoa.toLowerCase() &&
        pickSpendingWallet(ref.read(settingsProvider))?.id == walletId &&
        session != null &&
        identical(ref.read(sessionAuthProvider), session) &&
        ref.read(seedSessionProvider).unlocked;

    return _accountReadiness.ensure(
      scope: '$generation:$walletId:${eoa.toLowerCase()}',
      isCurrent: isCurrent,
      force: force,
      initialize: () => _enableTradingAccount(
        eoa: eoa,
        walletId: walletId,
        isCurrent: isCurrent,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _enableTradingAccount({
    required String eoa,
    required String walletId,
    required bool Function() isCurrent,
    void Function(String status)? onProgress,
  }) async {
    void checkAccount() {
      if (!isCurrent()) throw StateError('Predictions account changed');
    }

    checkAccount();

    // Derive wallet once — needed for Safe deployment and client recreation.
    // Pin to the spending wallet because that's where the Safe owner
    // key derives from; the active wallet may be a savings card with
    // no mnemonic on disk.
    final settings = ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) {
      throw Exception('No spending wallet');
    }
    final session = ref.read(seedSessionProvider);
    if (!session.unlocked) {
      throw Exception('Wallet locked. Please unlock first.');
    }
    final mnemonic = await resolveBip39MnemonicFor(spending,
        access: SeedAccess.automatic, session: session);
    checkAccount();
    if (mnemonic == null) {
      throw Exception('Could not decrypt wallet');
    }
    final wallet = await EvmWalletDerivation.deriveWalletAsync(
        mnemonic: mnemonic, version: spending.evmDerivationVersion, index: 0);
    if (spending.id != walletId ||
        wallet.address.toLowerCase() != eoa.toLowerCase()) {
      throw StateError('Predictions account changed');
    }

    // Step 1: Deploy Safe + set token approvals via relayer (gasless)
    // onProgress receives: "deploying" → "approvals" from onboarding service
    final onboarding = PolymarketOnboardingService();
    final proxyWallet = await onboarding.enableTrading(
      eoaAddress: eoa,
      privateKey: wallet.privateKey,
      onProgress: onProgress,
      ensureCurrent: checkAccount,
    );
    checkAccount();

    // Persist proxy wallet so it survives app restarts
    await _storage.write(key: _proxyKey(walletId), value: proxyWallet);
    checkAccount();

    // Keep the deposit-wallet identity current for order signing.
    final preCredsState = state.valueOrNull;
    if (preCredsState != null) {
      _setData(preCredsState.copyWith(proxyWalletAddress: proxyWallet));
    }

    // Provision EOA credentials without deleting the previous cache first;
    // a network failure must not destroy usable cancellation credentials.

    // Step 2: Derive/create CLOB API credentials (after Safe is deployed)
    onProgress?.call('credentials');
    if (_client != null) {
      _CredentialsWithNonce? result;
      // Retry up to 3 times (CLOB API may need a moment after Safe deployment)
      for (var attempt = 1; attempt <= 3 && result == null; attempt++) {
        try {
          checkAccount();
          result = await _deriveOrCreateApiKey(
              funder: proxyWallet, isCurrent: isCurrent);
          checkAccount();
        } catch (e) {
          checkAccount();
          if (attempt < 3) {
            await Future.delayed(const Duration(seconds: 2));
          } else if (!_isOfflineError(e)) {
            // All retries exhausted — credentials stay null and the
            // flow degrades, but report the swallowed failure (scrubbed,
            // release-gated) rather than silently dropping it. Offline /
            // timeout failures are EXPECTED (same rule as the build-time
            // provisioning catch) and stay out of Error Tracking.
            TrackingService.recordCrash(e, null,
                reason: 'polymarket_enable_trading');
          }
        }
      }
      if (result != null) {
        _apiNonce = result.nonce;
        await _saveCredentials(walletId, result.credentials,
            nonce: _apiNonce, isCurrent: isCurrent);
        checkAccount();
        _client!.clob.auth?.setCredentials(result.credentials);
        _backendService = _createBackendService(
          result.credentials,
          eoa,
          funder: proxyWallet,
        );

        // Step 2b: Force the CLOB to re-read this Safe's on-chain allowance
        // snapshot. Required by V2: the CLOB caches allowances and refuses
        // to match orders against stale numbers. Without this call a freshly
        // -onboarded Safe still 400s with "not approved" / "maker address
        // not allowed" until the cache naturally evicts.
        try {
          await _backendService!.updateBalanceAllowance(
            assetType: 'COLLATERAL',
            signatureType: 3, // POLY_1271 — V2 deposit-wallet sigType
          );
        } catch (e) {
          _devLog('[enableTrading] balance-allowance/update failed: $e — '
              'continuing; orders may still reject until cache evicts.');
        }
      }
    }
    checkAccount();

    // Step 3: Recreate client with funder (proxy wallet) for Safe order signing
    if (_client?.clob.auth?.credentials != null) {
      _client?.close();
      _client = PolymarketClient.authenticated(
        credentials: _client!.clob.auth!.credentials!,
        funder: proxyWallet,
        privateKey: wallet.privateKey,
      );
    }

    // Account readiness must not wait for portfolio indexing, price history,
    // or redemption checks. Those reads cannot make an order more executable.
    checkAccount();
    onProgress?.call('done');
    final ready = state.valueOrNull;
    if (ready != null) {
      _setData(ready.copyWith(
        isAuthenticated: _client?.clob.auth?.credentials != null,
      ));
    }
    unawaited(() async {
      try {
        final data = await _fetchAllData(eoa, proxyWallet: proxyWallet);
        if (!isCurrent()) return;
        final live = state.valueOrNull;
        _setData(data.copyWith(
          isAuthenticated: _client?.clob.auth?.credentials != null,
          isPlacingOrder: live?.isPlacingOrder ?? false,
        ));
      } catch (_) {
        // The existing portfolio poll retries; setup itself already succeeded.
      }
    }());
  }
}

final polymarketTradingProvider = AsyncNotifierProvider.autoDispose<
    PolymarketTradingNotifier, PolymarketTradingState>(
  PolymarketTradingNotifier.new,
);

/// Lazy-initialised in-memory mirror of the Hive cache so we don't hit
/// disk on every provider rebuild. Populated on first access from
/// [PolymarketUsdcCacheService.read()] and then kept in sync as fresh
/// trading states arrive. The cache survives app restarts (Hive) and
/// session-level provider tear-down (module-level field) — together
/// they guarantee the displayed USDC balance never flashes $0.00 when
/// the underlying trading state is briefly between fresh reads.
double? _lastKnownPolymarketUsdc;

final polymarketBalanceProvider = Provider.autoDispose<double>((ref) {
  // Keep this provider alive across the home carousel swipes. The
  // wallet-card sparkline conditionally stops watching the USDC
  // provider on non-spending wallets, and without keepAlive the
  // autoDispose chain tears down the trading state too.
  ref.keepAlive();
  // Lazy-hydrate the in-memory mirror from disk on first access.
  _lastKnownPolymarketUsdc ??= PolymarketUsdcCacheService.read();
  final state = ref.watch(polymarketTradingProvider);
  final fresh = state.valueOrNull?.usdcBalance;
  if (fresh != null) {
    // Fresh value — even if it's 0, that's a real read. Trust it,
    // update the in-memory mirror, and write through to Hive so the
    // next cold start picks up where we left off.
    if (_lastKnownPolymarketUsdc != fresh) {
      _lastKnownPolymarketUsdc = fresh;
      PolymarketUsdcCacheService.write(fresh);
    }
    return fresh;
  }
  // Loading or error — return the last value we successfully read.
  // Better to show a slightly stale balance than to flash 0 mid-swap
  // or while polymarketTradingProvider is hydrating after a wallet
  // switch.
  return _lastKnownPolymarketUsdc ?? 0;
});

/// The CLOB market's minimum order size (in SHARES) for one condition.
/// Null on any failure — callers keep their static floor then. Used by
/// the bet slip to raise the user-facing minimum on markets whose real
/// floor (minimumOrderSize × price) exceeds the $2 default, instead of
/// letting the CLOB reject with a raw size error.
final polymarketMinOrderSizeProvider = FutureProvider.autoDispose
    .family<double?, String>((ref, conditionId) async {
  final client = ref.watch(polymarketTradingProvider.notifier).clobClient;
  if (client == null || conditionId.isEmpty) return null;
  try {
    final market = await client.clob.markets.getMarket(conditionId);
    return market.minimumOrderSize;
  } catch (_) {
    return null;
  }
});

final polymarketActivityProvider =
    FutureProvider.autoDispose<List<Activity>>((ref) async {
  final tradingState = ref.watch(polymarketTradingProvider).valueOrNull;
  final addr = tradingState?.proxyWalletAddress;
  if (addr == null || addr.isEmpty) return [];
  List<Activity> apiActivity = const [];
  try {
    final model = PolymarketModel();
    apiActivity = await model.getUserActivity(addr);
    model.dispose();
  } catch (_) {}
  // Merge in any optimistic entries the user just created (sells, redeems)
  // that the Data API hasn't indexed yet. Drop entries the API now confirms.
  return _mergeOptimisticActivity(apiActivity);
});

/// Prepend optimistic local activities (recent buys/sells/redeems) ahead of
/// the API result, dropping the ones the API now reports. Optimistic entries
/// auto-expire after 30 minutes, after which the API has typically caught up.
///
/// A BUY is recorded under the CLOB orderID, never the chain hash the API
/// reports, so the hash match alone kept both rows once the trade was
/// indexed: the position's trade-history cost basis counted the bet twice
/// (a 15¢ fill read "Bought 30¢" and -50% until another reader of the box
/// evicted the row). The shape match ([confirmed]) drops it here too.
@visibleForTesting
List<Activity> mergeOptimisticPolymarketActivity(List<Activity> apiActivity) =>
    _mergeOptimisticActivity(apiActivity);

List<Activity> _mergeOptimisticActivity(List<Activity> apiActivity) {
  final apiHashes =
      apiActivity.map((a) => a.transactionHash.toLowerCase()).toSet();
  final optimistic = PolymarketOptimisticActivityService.snapshot(
    confirmedHashes: apiHashes,
    confirmed: apiActivity,
  );
  if (optimistic.isEmpty) return apiActivity;
  // Newest first — match the API's typical sort.
  final merged = [...optimistic, ...apiActivity];
  merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return merged;
}

/// Hot Polymarket signing keys in this provider are built here, so the
/// Ledger scope guard (Phase 5 plan B12) refuses them inside a Ledger
/// operation.
EthPrivateKey _hotPolymarketCredentials(String privateKey) {
  LedgerOperationScope.assertHotAllowed(
      HotSigningAction.polymarketHotCredentials);
  return EthPrivateKey.fromHex(privateKey);
}
