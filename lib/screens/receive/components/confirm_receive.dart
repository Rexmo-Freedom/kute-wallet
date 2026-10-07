import 'dart:async';
import 'dart:io' show Platform;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/address_receive_provider.dart';
import 'package:kute/providers/pending_asset_provider.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show SafeSvgNetwork, kUsdMarkAsset;
import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show selectedNetworkTypeProvider;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usdc_balance_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/screens/receive/quoted_receive_screen.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/jade_device_picker.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/powered_by_badge.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/services/accumulation_address_cache.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/jade_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/sound_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

// ─── Receive-flow source pool ────────────────────────────────────
//
// Picks which on-wallet pool the user is generating a receive
// payload for. Step 0 only
// uses this to drive the wallet-switch + the BTC vs USDC default
// emphasis on the Share step (BTC pool surfaces unified BIP21 +
// fallback rows; USDC pool defaults to USDC fallback expanded).
enum _ReceivePool { btc, usdc }

// ─── Fallback address row identity ───────────────────────────────
//
// Ported verbatim from the prior `receive_bitcoin_widget.dart`.
// `unified` = unified BIP21 QR (Bitcoin + Lightning embedded) — the
// default state on Spark/hot wallets. `null` is reserved for flows
// where the toggle is bypassed entirely (swap mode,
// USDC pool default caption).
enum _FallbackAddress { bitcoin, unified, lightning, usdc }

class _DestAsset {
  final String code;
  final String name;
  final String? iconUrl;
  final String? svgAsset;
  final Color color;

  _DestAsset({
    required this.code,
    required this.name,
    required this.color,
    this.iconUrl,
    this.svgAsset,
  });

  Widget iconWidget({required double size}) {
    if (svgAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: SvgPicture.asset(svgAsset!, width: size, height: size),
      );
    }
    if (iconUrl != null) {
      final isSvg = Uri.tryParse(iconUrl!)?.path.endsWith('.svg') ?? false;
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: isSvg
            ? SafeSvgNetwork(
                url: iconUrl!,
                width: size,
                height: size,
                fallback: _textFallback(size),
              )
            : CachedNetworkImage(
                imageUrl: iconUrl!,
                width: size,
                height: size,
                // No BuildContext here — decode at ~3x the logical size as a
                // safe devicePixelRatio ceiling for these small coin icons.
                memCacheWidth: (size * 3).round(),
                placeholder: (ctx, url) => SizedBox(width: size, height: size),
                errorWidget: (ctx, url, err) => _textFallback(size),
              ),
      );
    }
    return _textFallback(size);
  }

  // Neutral fallback disc — no asset-colored tint/border around the
  // icon. Plain class (no BuildContext here), so use const neutral
  // greys rather than theme colors.
  Widget _textFallback(double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x14808080),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Center(
          child: Text(
            code.substring(0, code.length.clamp(0, 2)),
            style: TextStyle(
                color: const Color(0xFF888888),
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700),
          ),
        ),
      );
}

class _DestNetwork {
  final String network;
  final String name;
  final String addressHint;

  _DestNetwork({
    required this.network,
    required this.name,
    required this.addressHint,
  });
}

Color _getCoinColor(String code) {
  const colors = {
    'ETH': Color(0xFF627EEA),
    'USDT': Color(0xFF26A17B),
    'USDC': Color(0xFF2775CA),
    'BNB': Color(0xFFF3BA2F),
    'SOL': Color(0xFF9945FF),
    'XRP': Color(0xFF00AAE4),
    'TRX': Color(0xFFFF0013),
    'LTC': Color(0xFF345D9D),
    'POL': Color(0xFF8247E5),
    'DOGE': Color(0xFFC2A633),
    'ADA': Color(0xFF0033AD),
    'DOT': Color(0xFFE6007A),
    'AVAX': Color(0xFFE84142),
    'NEAR': Color(0xFF00C08B),
    'ATOM': Color(0xFF2E3148),
    'TON': Color(0xFF0098EA),
    'SUI': Color(0xFF4DA2FF),
    'SEI': Color(0xFFFF4545),
    'BTC': AppColors.accent,
    'WBTC': Color(0xFFF09242),
    'BCH': Color(0xFF8DC351),
    'STX': Color(0xFF5546FF),
    'TIA': Color(0xFF7B2BF9),
  };
  return colors[code] ?? Color(code.hashCode | 0xFF404040);
}

/// 2-step Receive stepper.
///
///   0 — Receive into  (pick wallet/pool)
///   1 — Share         (unified BIP21 QR + amount input + fallback rows
///                      ported from the prior `receive_bitcoin_widget`)
///
/// The Share step owns its own action buttons (`Generate invoice`,
/// `Update QR`, `Share`, hardware verify, etc.) so the shared CTA
/// row is hidden there. The "Receive into" step auto-advances on
/// tile tap, so the shared Continue button never surfaces.
class ConfirmReceive extends ConsumerStatefulWidget {
  const ConfirmReceive({super.key});

  @override
  ConsumerState<ConfirmReceive> createState() => _ConfirmReceiveState();
}

class _ConfirmReceiveState extends ConsumerState<ConfirmReceive> {
  // ─── Stepper state ─────────────────────────────────────────────
  int _step = 0;
  final Set<int> _completedSteps = <int>{};
  late final PageController _pageCtrl;

  // ─── Source pool / wallet ──────────────────────────────────────
  /// Capture the entry account once. The title and receive paths share this
  /// fixed destination until the user closes the flow.
  late final Account? _selectedAccount;
  _ReceivePool? _selectedPool;
  late final String? _selectedWalletId;

  // ─── Amount input (shared on the Share step) ───────────────────
  // Single source of truth for the optional receive amount — bound
  // to `inputAmountProvider` for BIP21 amount embedding and LN
  // invoice creation. The amount itself is typed in the request sheet
  // (`showRequestAmountSheet`); `_requestedSats` is what the live
  // request is for, in sats, for the pill label. Null when no amount
  // is requested.
  int? _requestedSats;

  // ─── Share-step UX state (ported from old widget) ──────────────
  /// Which fallback row is expanded. Resolved in initState based on
  /// the picked account — USDC stays `null` (the dedicated USDC
  /// caption renders), hardware/watch-only defaults to bitcoin
  /// (no on-wallet lightning), Spark/hot wallets default to
  /// `unified` (BIP21 with both rails embedded) so the QR works
  /// across any sender wallet.
  _FallbackAddress? _expandedFallback;

  // On-chain
  bool _includeAmountInOnChain = false;
  String _onChainWithAmount = '';

  // Spark Lightning invoice
  bool _isInvoiceLoading = false;
  ReceivePaymentResponse? _lnPaymentResponse;

  // Hardware verification
  bool _isLedgerVerifying = false;
  bool _isJadeVerifying = false;

  // Orchestra cross-chain receive
  _DestAsset? _selectedSourceAsset;
  _DestNetwork? _selectedSourceNetwork;
  String? _rateError;
  bool _creatingOrder = false;
  int _receiveRequestId = 0;
  bool Function()? _sameReceiveSdk;

  /// Orchestra deposit addresses are discovered through the recipient's
  /// order history rather than by id, so they get their own poller
  /// (shared with the dollars receive screen).
  late final OrchestraDepositPoller _orchestraPoller =
      OrchestraDepositPoller(ref);
  SwapOrder? _activeExchange;

  /// The Kute fee the shown Orchestra address's own terms charge, keyed
  /// by that address so a later address never inherits it. Null bps
  /// shows no fee line.
  ({String address, int? bps})? _activeAddressFee;

  /// Stops the deposit poll. A stale one left running would keep
  /// writing to a screen that moved on.
  void _stopPolling() {
    _orchestraPoller.cancel();
  }

  /// Independent poll that nudges the background sync while the
  /// Receive screen is open. The Spark/Lightning event stream is
  /// authoritative when it fires, but if it silently dropped (SDK
  /// disconnect, reconnect race, etc.) the UI would otherwise wait
  /// for the next 5 s background tick. This timer also primes the
  /// stream-fresh bypass so the poll value lands without being
  /// blocked by a stale stream guard.
  Timer? _balanceWatchTimer;

  // ─── `receive_flow_completed` baseline ─────────────────────────
  // Snapshot of the PICKED wallet's Spark sats and on-chain sats (kept
  // as separate legs so the rail can be told apart) plus USDC dollars
  // at first measurement after the screen opens. The balance-watch
  // tick compares each subsequent reading against this baseline and
  // emits a single PostHog event when the user-visible total rises
  // above the baseline. Reset only on screen open, so quick
  // close+reopen re-arms the flag for the next session.
  bool _paymentDetectedFired = false;
  int? _baselineSparkSats;
  int? _baselineOnChainSats;
  double? _baselineUsdcDollars;

  /// The dollar balance at first measurement. Its own leg because a
  /// dollar receive raises neither of the two above: the money lands in
  /// the spending account's dollar balance, not in bitcoin and not in
  /// the Predictions pool.
  double? _baselineUsdDollars;

  @override
  void initState() {
    super.initState();
    // Capture the entry account once; the receive destination stays fixed
    // until this flow closes.
    final selected = ref.read(selectedAccountProvider);
    _selectedAccount = selected;
    _selectedWalletId =
        selected?.wallet?.id ?? ref.read(settingsProvider).activeWalletId;
    final entryWallet = selected?.wallet ??
        ref.read(settingsProvider).wallets.where((w) => w.id == _selectedWalletId).firstOrNull;
    _receiveWalletKind = entryWallet == null
        ? null
        : TrackingService.walletKind(
            isLedger: entryWallet.isLedger,
            isHardware: entryWallet.isHardware,
            isWatchOnly: entryWallet.isWatchOnly,
            isSigner: entryWallet.isSigner,
            isExternalAddress: entryWallet.isExternalAddress,
          );
    TrackingService.moneyFlowStarted(
      'receive',
      event: 'receive_opened',
      entrySource: TrackingService.takeEntrySource('receive'),
      walletKind: _receiveWalletKind,
      network: selected is UsdcSpendingAccount ? 'polygon' : 'bitcoin',
      props: {'pool': selected is UsdcSpendingAccount ? 'usdc' : 'btc'},
    );
    // Seed the pool + network branch the Share body reads off of.
    // `_selectedPool` is what flips the QR to the Polymarket Safe and
    // hides the BTC/Lightning fallback rows; `selectedNetworkTypeProvider`
    // is what other downstream widgets branch on.
    if (selected is UsdcSpendingAccount) {
      _selectedPool = _ReceivePool.usdc;
      // USDC pool — the dedicated USDC caption (Polymarket Safe
      // address + Polygon network hint) handles display; we keep
      // `_expandedFallback` null so the LN/BTC caption branches
      // don't preempt it.
      _expandedFallback = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(selectedNetworkTypeProvider.notifier).state =
            'Polygon Network';
        // Trigger Safe deploy on demand when the user explicitly
        // lands on the USDC pool with no proxy yet. The provider's
        // own auto-deploy at build() time can fail silently
        // (cancelled biometric, relayer hiccup, race with PIN
        // hydration); without this retry the receive screen would
        // shimmer forever and the user has no obvious way to
        // recover. `enableTrading` short-circuits when the proxy
        // already exists, so re-firing is safe.
        _ensureSafeForUsdc();
      });
    } else {
      _selectedPool = _ReceivePool.btc;
      // Spark/hot wallets default to the unified BIP21 QR so a
      // single code serves both on-chain and Lightning senders, and
      // the BTC + Lightning address rows render side-by-side under
      // the QR. Cold wallets (hardware / watch-only / external)
      // can't sign Lightning, so they default to the plain on-chain
      // address (no row 2, no toggle — the unified branch is
      // suppressed by `showFormatPicker` / `canUseLightning`).
      final wallet = selected?.wallet;
      final hasLightning = wallet != null &&
          wallet.sparkEnabled &&
          !wallet.isHardware &&
          !wallet.isWatchOnly &&
          !wallet.isExternalAddress;
      _expandedFallback =
          hasLightning ? _FallbackAddress.unified : _FallbackAddress.bitcoin;
    }
    _completedSteps.add(0);
    _step = 1;
    _pageCtrl = PageController(initialPage: 1);

    // Per-step PostHog `$screen` — only `receive` route is observed;
    // each stepper page emits its own screen view.
    const stepNames = ['receive_account_picker', 'receive_share'];
    void emitStepScreen(int s) {
      if (s >= 0 && s < stepNames.length) {
        TrackingService.screenView(stepNames[s]);
      }
    }

    int? lastTrackedStep = _step;
    emitStepScreen(_step);
    _pageCtrl.addListener(() {
      final p = _pageCtrl.page?.round();
      if (p == null || p == lastTrackedStep) return;
      lastTrackedStep = p;
      emitStepScreen(p);
    });
    // Kick the balance watcher immediately so the user sees fresh
    // numbers as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // We deliberately do NOT invalidate the address providers
      // on every receive-screen open:
      //   * Spark (`getSparkBitcoinAddressProvider`) is bound with
      //     `newAddress: true` on first fetch — subsequent reads
      //     return the SAME deposit address until the SDK rotates
      //     it on a `claimedDeposits` push event (push pipeline
      //     invalidates the provider on that event).
      //   * BDK-side `walletAddressProvider` now uses
      //     `nextUnusedAddress`, which is idempotent: the same
      //     unused address is returned on every call until that
      //     scriptPubKey actually receives funds. Invalidating
      //     here would have been harmless under the new
      //     implementation, but burning a fresh BDK address on
      //     every receive-screen mount was the original bug — so
      //     we leave the cache warm.
      // A sender who saw address A 30 s ago and now sees B both
      // sends to the same wallet, but the swap looks broken — so
      // the right rule is "rotate the address only when funds
      // have actually arrived at the prior one."
      //
      // The one exception is a CACHED ERROR. The BDK family providers
      // are not autoDispose, so a failed address fetch (the first-open
      // full scan held the native slot, the session failed to open,
      // ...) stays cached across screen opens and the QR plate shimmers
      // until restart. Drop the stale error so this open fetches again.
      final pickedId = _pickedReceiveWalletId;
      if (pickedId != null) {
        var pickedUsesBdk = false;
        for (final w in ref.read(settingsProvider).wallets) {
          if (w.id == pickedId) {
            pickedUsesBdk = w.usesBdk;
            break;
          }
        }
        if (pickedUsesBdk) {
          if (ref.read(walletReceiveInfoProvider(pickedId)).hasError ||
              ref.read(walletAddressProvider(pickedId)).hasError) {
            ref.invalidate(walletReceiveInfoProvider(pickedId));
            ref.invalidate(walletAddressProvider(pickedId));
          }
          if (ref.read(bitcoinModelForWalletProvider(pickedId)).hasError) {
            // Cascades through restore, wallet, model and address.
            ref.invalidate(bitcoinConfigForWalletProvider(pickedId));
          }
        }
      }
      _primeReceiveRefresh();
      _balanceWatchTimer?.cancel();
      // Periodic kick to ensure the cache catches a late-arriving
      // payment when no stream tick fires. Calls `syncNow()` directly
      // (NOT `_primeReceiveRefresh`) — re-priming the cache's
      // `primePoll` bypass every 5s previously caused first-receive
      // balance oscillation: a stale SDK `getInfo()` mid-reconcile
      // would return 0, the always-armed bypass would let it
      // overwrite the stream-credited value, and the display would
      // bounce between 0 and the real amount until the SDK settled.
      // The on-mount `_primeReceiveRefresh` above is enough for the
      // "stream value arrived right before" case the bypass is meant
      // to handle.
      _balanceWatchTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) {
          if (!mounted) return;
          BackgroundSyncService().syncNow();
          _checkForIncomingPayment();
        },
      );

      // One-shot "open the full cross-asset picker" hand-off from the Add
      // Funds → From crypto tile. No asset pre-selected: shows the whole
      // "Receive other assets" list.
      final openOtherAssets = ref.read(pendingReceiveOpenOtherAssetsProvider);
      if (openOtherAssets) {
        ref.read(pendingReceiveOpenOtherAssetsProvider.notifier).state = false;
        _showSourceAssetPicker();
      }
    });
  }

  // Opening Receive from a hardware/watch-only wallet no longer kicks a
  // BDK scan — these wallets sync only on the user's pull-to-refresh in
  // the detail screen. The receive address is read from the wallet's
  // last-synced state; pull-to-refresh there advances it past any newly
  // used scriptPubKeys.

  /// Prime the cache to accept the next poll value (bypassing the
  /// Fire-and-forget Safe deploy when the user opens the USDC
  /// receive surface with no proxy yet. `enableTrading` is
  /// idempotent — short-circuits once the proxy exists — so calling
  /// it again from here is the cheap retry path for the provider-
  /// init flow that may have failed (cancelled biometric, race with
  /// PIN hydration, relayer hiccup). Without this the shimmer
  /// renders forever and the user has no way to recover short of
  /// closing and reopening the screen.
  void _ensureSafeForUsdc() {
    try {
      // Accelerate the polymarket trading provider's poll cadence
      // from 10s to 3s while the user is staring at the USDC receive
      // address. An inbound USDC transfer is then detected on the
      // very next tick. The dispose() above flips this back off.
      ref.read(polymarketTradingProvider.notifier).setAwaitingDeposit(true);
      // Task #170: pUSD is the resting state. Kick off a deposit-arrival
      // poll so any USDC.e landing on the proxy while the user has the
      // receive screen open gets wrapped to pUSD automatically.
      ref.read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();
      final current = ref.read(polymarketTradingProvider).valueOrNull;
      final proxy = current?.proxyWalletAddress ?? '';
      if (proxy.isNotEmpty) return;
      // ignore: discarded_futures
      unawaited(ref
          .read(polymarketTradingProvider.notifier)
          .enableTrading()
          .catchError((_) {}));
    } catch (_) {
      // Provider not yet ready or already mid-flight — the periodic
      // refresh will catch up.
    }
  }

  /// stream-fresh guard) for both the active and spending wallet,
  /// then trigger an immediate background sync. Called on screen
  /// mount, every 5 s while open, and after a payment is detected.
  void _primeReceiveRefresh() {
    try {
      final settings = ref.read(settingsProvider);
      final cacheNotifier = ref.read(walletBalanceCacheProvider.notifier);
      final activeId = settings.activeWalletId;
      if (activeId != null) cacheNotifier.primePoll(activeId);
      // The picked receive wallet is what `_checkForIncomingPayment`
      // reads; prime it too when it is not the active wallet.
      final pickedId = _pickedReceiveWalletId;
      if (pickedId != null && pickedId != activeId) {
        cacheNotifier.primePoll(pickedId);
      }
      final spending = settings.wallets.where((w) => w.isSparkWallet);
      for (final w in spending) {
        cacheNotifier.primePoll(w.id);
      }
    } catch (_) {}
    BackgroundSyncService().syncNow();
  }

  /// Map the currently-expanded fallback to the PostHog enum for
  /// `receive_qr_shared` events. Returns `'bip21'` when no fallback
  /// is expanded (Spark hot-wallet default = unified BIP21 QR).
  String _invoiceTypeForShare() {
    switch (_expandedFallback) {
      case _FallbackAddress.bitcoin:
        return 'bitcoin_address';
      case _FallbackAddress.lightning:
        return 'bolt11';
      case _FallbackAddress.usdc:
        return 'usdc_address';
      case _FallbackAddress.unified:
      case null:
        return 'bip21';
    }
  }

  /// Baseline + delta check for `receive_flow_completed`. Reads the
  /// PICKED wallet's balance (`balanceForWalletProvider`, not the
  /// active-wallet notifier — the two diverge whenever Receive targets
  /// a non-active wallet), `usdBalanceProvider` and
  /// `usdcBalanceProvider`. On the first call we capture a baseline
  /// snapshot; subsequent calls fire ONCE per receive session when
  /// the user-visible total rises by at least 1 sat OR 1 cent. The
  /// rail is inferred from which leg moved and what the screen shows
  /// (see [_railForBtcDelta]); a dollar or USDC bump is `spark`.
  void _checkForIncomingPayment() {
    if (_paymentDetectedFired) return;
    try {
      final pickedId = _pickedReceiveWalletId;
      final balance = pickedId == null
          ? ref.read(balanceNotifierProvider)
          : ref.read(balanceForWalletProvider(pickedId));
      final sparkSats = balance.sparkBitcoinbalance;
      final onChainSats = balance.onChainBtcBalance;
      final usdcDollars = ref.read(usdcBalanceProvider);
      final usdDollars = ref.read(usdBalanceProvider);

      // First measurement: capture baseline only.
      if (_baselineSparkSats == null ||
          _baselineOnChainSats == null ||
          _baselineUsdcDollars == null ||
          _baselineUsdDollars == null) {
        _baselineSparkSats = sparkSats;
        _baselineOnChainSats = onChainSats;
        _baselineUsdcDollars = usdcDollars;
        _baselineUsdDollars = usdDollars;
        return;
      }

      final sparkDelta = sparkSats - _baselineSparkSats!;
      final onChainDelta = onChainSats - _baselineOnChainSats!;
      final btcDelta = sparkDelta + onChainDelta;
      final usdcDelta = usdcDollars - _baselineUsdcDollars!;
      final usdDelta = usdDollars - _baselineUsdDollars!;

      String? network;
      double amountUsd = 0;
      // A landed payment refreshes the balances behind this screen and
      // is recorded once. It never interrupts the user with an overlay
      // (user decision): the QR stays up until they close it.
      var detected = false;
      if (btcDelta > 0) {
        network = _railForBtcDelta(
            sparkDelta: sparkDelta, onChainDelta: onChainDelta);
        // Convert sats → USD via the cached BTC rate. Defensive read:
        // if the rate provider is not ready we still emit the event
        // with a `0-1` bucket — that's still useful funnel signal.
        try {
          final usdPerBtc =
              ref.read(selectedCurrencyProvider('usd')).toDouble();
          amountUsd = (btcDelta / 100000000.0) * usdPerBtc;
        } catch (_) {}
        detected = true;
      } else if (usdDelta > 0) {
        // The dollar balance rose: a cross-asset receive converted and
        // settled on the wallet's own Spark address. Same enum value as
        // the pool below — the money landed on the Spark side.
        network = 'spark';
        amountUsd = usdDelta;
        detected = true;
      } else if (usdcDelta > 0) {
        // Polymarket Safe is a Polygon Safe; USDC-on-Polygon doesn't
        // map cleanly to bitcoin/lightning/spark, but the closest
        // semantic match for this enum is `spark` (the wallet's USDC
        // pool is always backed by the Polymarket Safe deployed via
        // the Spark wallet's seed).
        network = 'spark';
        amountUsd = usdcDelta;
        detected = true;
      }

      if (network == null || !detected) return;

      _paymentDetectedFired = true;
      // The money is here: stop kicking the sync every 5 s. `dispose`
      // still cancels for the no-payment case.
      _balanceWatchTimer?.cancel();
      _balanceWatchTimer = null;
      // One event per receive (the `_paymentDetectedFired` latch above).
      // `receive_payment_detected` used to fire alongside this for the
      // same receive; it is folded in here — `amount_bucket` included.
      TrackingService.track('receive_flow_completed', params: {
        'network': network,
        'amount_bucket': TrackingService.usdBucket(amountUsd),
        ..._receiveFlowInputs(),
        ...TrackingService.moneyParams(
          amountUsd: amountUsd,
          amount: btcDelta > 0 ? btcDelta / 1e8 : amountUsd,
          asset: btcDelta > 0 ? 'btc' : 'usd',
          amountSats: btcDelta > 0 ? btcDelta : null,
        ),
      });
      TrackingService.moneyFlowFinished('receive');
      SoundService.playSuccess();
    } catch (_) {
      // Provider not ready / disposed — silently retry on next tick.
    }
  }

  /// Rail (`lightning` | `spark` | `bitcoin`) for a BTC balance rise on
  /// the picked wallet. An on-chain leg rise is always `bitcoin`. A
  /// Spark leg rise depends on what the sender could have paid: a
  /// cross-asset deposit address converts and settles on the Spark
  /// address (`spark`); the plain Bitcoin address on a Spark wallet is
  /// the SDK deposit address, claimed into the Spark balance
  /// (`bitcoin`); the invoice / unified BIP21 QR is paid over
  /// `lightning` in practice.
  String _railForBtcDelta(
      {required int sparkDelta, required int onChainDelta}) {
    if (onChainDelta > 0 && sparkDelta <= 0) return 'bitcoin';
    if (_activeExchange != null) return 'spark';
    if (_expandedFallback == _FallbackAddress.bitcoin) return 'bitcoin';
    return 'lightning';
  }

  String? _receiveWalletKind;
  bool _payloadExported = false;
  String? _sourceAssetPicked;
  String? _sourceNetworkPicked;

  /// Receive funnel props: what was set up so far. Never an address,
  /// invoice or balance.
  Map<String, Object> _receiveFlowInputs() {
    final requested = _requestedSats;
    double? usd;
    if (requested != null && requested > 0) {
      try {
        final rate = ref.read(selectedCurrencyProvider('usd')).toDouble();
        if (rate > 0) usd = requested / 1e8 * rate;
      } catch (_) {}
    }
    return {
      'pool': _selectedPool == _ReceivePool.usdc ? 'usdc' : 'btc',
      if (_receiveWalletKind != null) 'wallet_kind': _receiveWalletKind!,
      'invoice_type': _invoiceTypeForShare(),
      'amount_requested': requested != null && requested > 0,
      'payload_exported': _payloadExported,
      'source_asset_picked': _sourceAssetPicked != null,
      if (_sourceAssetPicked != null)
        ...TrackingService.routeParams(
          fromAsset: _sourceAssetPicked,
          fromNetwork: _sourceNetworkPicked,
          toAsset: 'btc',
          toNetwork: 'spark',
          provider: 'orchestra',
        ),
      ...TrackingService.moneyParams(
        amountUsd: usd,
        amount: requested != null && requested > 0 ? requested / 1e8 : null,
        asset: 'btc',
        amountSats: requested != null && requested > 0 ? requested : null,
      ),
    };
  }

  @override
  void dispose() {
    if (_paymentDetectedFired) {
      TrackingService.moneyFlowFinished('receive');
    } else {
      TrackingService.moneyFlowAbandoned('receive',
          props: _receiveFlowInputs());
    }
    // Stop the polymarket trading provider's accelerated USDC-receive
    // poll (3s) so it relaxes back to 10s when the user leaves the
    // Receive screen. Safe to call when never set — the method
    // short-circuits on no-op.
    try {
      ref.read(polymarketTradingProvider.notifier).setAwaitingDeposit(false);
    } catch (_) {}
    _pageCtrl.dispose();
    _stopPolling();
    _balanceWatchTimer?.cancel();
    super.dispose();
  }

  // ─── Stepper helpers ───────────────────────────────────────────

  void _onLeadingTap() {
    // Single-page flow now: close button always closes the sheet.
    _closeAndReset();
  }

  void _closeAndReset() {
    try {
      ref.read(inputAmountProvider.notifier).state = '0.0';
    } catch (_) {}
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen(breezSDKProvider, (old, next) {
      if (_sameReceiveSdk != null && !_sameReceiveSdk!()) {
        setState(_resetShareState);
      }
    });
    ref.listen(settingsProvider.select((s) => s.wallets), (old, next) {
      if (_sameReceiveSdk != null && !_isPickedWalletSparkSpending()) {
        setState(_resetShareState);
      }
    });
    final c = context.colors;
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) {
          // Defer the provider mutation. `onPopInvoked` can fire
          // during a navigator-driven build phase (e.g. when the
          // resume handler resets the stack to /home) — Riverpod
          // refuses to update state mid-build.
          Future.microtask(() {
            try {
              ref.read(inputAmountProvider.notifier).state = '0.0';
            } catch (_) {}
          });
        }
      },
      child: KeyboardDismissOnTap(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: c.background,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            centerTitle: true,
            // The destination stays fixed for the entire receive flow.
            title: AccountSwitcherPill(
              pickerTitle: context.l10n.receiveInto,
              account: _selectedAccount,
              readOnly: true,
            ),
            leading: Center(
              child: KuteCloseButton(onPressed: _onLeadingTap),
            ),
          ),
          body: _buildStepperBody(context, c),
        ),
      ),
    );
  }

  Widget _buildStepperBody(BuildContext context, AppColorsExtension c) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    // Android-only system-nav inset (see camera.dart / confirm_send.dart
    // for rationale — iOS keeps the 20.h baseline so we don't introduce
    // a "fake bar" under the home indicator).
    final androidNavInset =
        Platform.isAndroid ? MediaQuery.of(context).padding.bottom : 0.0;
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w,
              20.h + androidNavInset + (viewInsets > 0 ? viewInsets : 0)),
          child: Column(
            children: [
              // A single receive surface for the account shown in the header.
              Expanded(
                child: StepPageWrapper(
                  title: context.l10n.receive,
                  subtitle: context.l10n.receiveScanOrShareSubtitle,
                  colors: c,
                  child: _sharePage(c),
                ),
              ),
              // Share step owns its own primary actions (Generate
              // invoice / Update QR / Share / verify-on-device), and
              // Step 0 auto-advances on tile tap, so the shared CTA
              // never surfaces. Kept here for shape-parity with the
              // Send stepper in case future steps need a Continue.
              SharedStepCta(
                step: _step,
                colors: c,
                visibleSteps: const <int>{},
                enabled: false,
                onContinue: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step 0: Receive into ──────────────────────────────────────

  // ───────────────────────────────────────────────────────────────
  // Step 1: Share — ported from `receive_bitcoin_widget.dart` body.
  //
  // Renders the unified BIP21 QR for Spark wallets, with three
  // expandable fallback rows (Bitcoin / Lightning / USDC). For
  // hardware/watch-only wallets it offers on-chain BTC. Cross-chain and
  // Cash-App-style payment links live below the fallback rows.
  // ───────────────────────────────────────────────────────────────

  Widget _sharePage(AppColorsExtension c) {
    // Respect the OS "reduce motion" setting for the decorative
    // expand/collapse transitions on this page (Show-addresses /
    // Advanced options). Loading shimmers + dot-wave spinners convey
    // state and are left running regardless.
    final setupLnAddressAsync = ref.watch(setupLnAddressProvider);
    // Resolve the wallet the user picked on Step 0 — falls back to
    // the active (carousel-current) wallet when no explicit pick was
    // made (e.g. legacy entry points). The selected wallet drives
    // both the address shown on the QR and which receive paths are
    // available below.
    final settings = ref.watch(settingsProvider);
    final pickedWalletId = _selectedWalletId ?? settings.activeWalletId;
    final pickedWallet = pickedWalletId == null
        ? settings.activeWallet
        : settings.wallets.firstWhere(
            (w) => w.id == pickedWalletId,
            orElse: () => settings.activeWallet!,
          );
    final activeWallet = pickedWallet;

    final bool isExternalAddress = activeWallet?.isExternalAddress ?? false;
    final bool canUseLightning = activeWallet != null &&
        activeWallet.sparkEnabled &&
        !activeWallet.isWatchOnly &&
        !activeWallet.isHardware &&
        !isExternalAddress;

    // Address always resolves via the wallet-id-keyed
    // `walletAddressProvider`, never via the active-wallet-bound
    // `addressProvider`. The latter would return whichever wallet the
    // home carousel is currently parked on — wrong when the user
    // picked a different wallet in the receive picker. The provider
    // internally branches:
    //   * spending wallet → Spark deposit address (cached, stable)
    //   * hardware/watch-only → BDK `nextUnusedAddress` (idempotent)
    //   * external address → stored address
    final AsyncValue<String>? onChainAddressAsync = activeWallet == null
        ? null
        : ref.watch(walletAddressProvider(activeWallet.id));
    final String baseOnChainAddress = onChainAddressAsync?.valueOrNull ?? '';
    final displayOnChainAddress =
        _includeAmountInOnChain ? _onChainWithAmount : baseOnChainAddress;

    // `qrPayload` is the exact string the QR encodes. The Share and
    // Copy pills under the address act on this same payload, so what
    // the user sends is what a scanner would read. While it is null the
    // plate shows `qrPlaceholder` (an error) or the shimmer.
    String? qrPayload;
    Widget? qrPlaceholder;

    if (_selectedSourceAsset != null && _creatingOrder) {
      // Shimmer while the deposit address is being minted.
    } else if (_selectedSourceAsset != null &&
        _activeExchange != null &&
        _activeSwapAddressUnsupported) {
      // FUND-SAFETY: a cached Orchestra accumulation address whose
      // (asset, network) pair fell off the live receive catalog must
      // never be shown — the "reusable, converts automatically"
      // promise no longer holds and a deposit could strand.
      qrPlaceholder =
          _buildErrorDisplay(context.l10n.receiveAssetTemporarilyUnavailable);
    } else if (_selectedSourceAsset != null && _activeExchange != null) {
      final ex = _activeExchange!;
      qrPayload = ex.depositExtraId != null && ex.depositExtraId!.isNotEmpty
          ? '${ex.depositAddress}?memo=${ex.depositExtraId}'
          : ex.depositAddress;
    } else if (_selectedPool == _ReceivePool.usdc) {
      // USDC pool wins regardless of wallet type. The Polymarket Safe
      // is per-user (derived from the spending wallet's seed-derived
      // EOA) and is the same address whether the user is parked on the
      // spending card or on a hardware/watch-only card. Without this
      // gate ahead of the `!canUseLightning` branch below, savings
      // wallets would render the BTC on-chain address even when the
      // user explicitly picked the USDC tab.
      final safe =
          ref.watch(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
      if (safe != null && safe.isNotEmpty) qrPayload = safe;
    } else if (!canUseLightning) {
      if (displayOnChainAddress.isNotEmpty) qrPayload = displayOnChainAddress;
    } else if (_isInvoiceLoading) {
      // Generating a specific-amount Lightning invoice — show the
      // shimmer, NOT a momentary revert of the QR to the previous code.
    } else if (_lnPaymentResponse != null) {
      // A specific-amount Lightning invoice was generated from the
      // Request amount pill. It wins over every native format below,
      // so the QR can never keep showing a plain address while the
      // user believes an amount was requested.
      qrPayload = _lnPaymentResponse!.paymentRequest;
    } else if (_expandedFallback == _FallbackAddress.bitcoin) {
      // `displayOnChainAddress` already carries the BIP21 amount when
      // one was requested in this format.
      if (displayOnChainAddress.isNotEmpty) qrPayload = displayOnChainAddress;
    } else if (_expandedFallback == _FallbackAddress.usdc) {
      final safe =
          ref.watch(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
      if (safe != null && safe.isNotEmpty) qrPayload = safe;
    } else if (_expandedFallback == _FallbackAddress.lightning) {
      final lnResult = setupLnAddressAsync.valueOrNull;
      if (setupLnAddressAsync.hasError) {
        qrPlaceholder = _buildErrorDisplay(context.l10n.failedToGetAddress);
      } else if (lnResult != null) {
        if (lnResult.lnurl != null) {
          qrPayload = lnResult.lnurl!.toUpperCase();
        } else if (lnResult.lightningAddress != null) {
          qrPayload = 'lightning:${lnResult.lightningAddress!}';
        } else {
          qrPlaceholder = _buildErrorDisplay(context.l10n.failedToGetAddress);
        }
      }
    } else {
      // `_FallbackAddress.unified` (the default on Spark/hot wallets)
      // and the legacy `null` state both render the BIP21 unified URI
      // — Bitcoin address + embedded LNURL — so one QR satisfies both
      // on-chain and Lightning senders.
      if (baseOnChainAddress.isNotEmpty) {
        if (setupLnAddressAsync.hasError) {
          qrPayload = 'bitcoin:$baseOnChainAddress';
        } else if (setupLnAddressAsync.hasValue) {
          qrPayload = _buildUnifiedUri(
              baseOnChainAddress, setupLnAddressAsync.valueOrNull?.lnurl);
        }
      }
    }

    // A failed address derivation has to SAY so. Every branch above that
    // wants the on-chain address only checks whether it is empty, and an
    // error yields exactly that: empty. So the screen fell through to the
    // shimmer and sat there for good, which is what "it never loads" was.
    // The Lightning branch already handled its own error; this does the
    // same for the on-chain one, whichever branch asked for it.
    if (qrPayload == null &&
        qrPlaceholder == null &&
        onChainAddressAsync?.hasError == true) {
      qrPlaceholder = _buildErrorDisplay(context.l10n.failedToGetAddress);
    }

    final Widget qrContent = qrPayload != null
        ? buildQrCode(qrPayload, context)
        : (qrPlaceholder ?? const ReceiveQrShimmer());

    final Lnurl? lnData = setupLnAddressAsync.valueOrNull;
    final String? lightningAddress = lnData?.lightningAddress;
    final String? lnUsername = lightningAddress?.split('@').first;

    final bool isSwapMode = _selectedSourceAsset != null;
    final bool isUsdcFallback = _expandedFallback == _FallbackAddress.usdc;
    // Request amount is offered on the native rails of a hot wallet.
    // In the unified and Lightning formats the request is a Lightning
    // invoice for the amount; in the Bitcoin-only format it is a BIP21
    // amount on the on-chain address, so the QR always matches the
    // request. Cold wallets (hardware / watch-only / software bitcoin
    // / tracked) show just the QR and the address, as before.
    final bool showRequestAmount = canUseLightning &&
        !isSwapMode &&
        !isUsdcFallback &&
        _selectedPool != _ReceivePool.usdc;

    // Imported and hardware wallets read their address from BDK, and
    // the first open of an imported wallet holds the native wallet slot
    // for a full scan. Say why the plate is still shimmering.
    final bool showSyncingCaption = activeWallet != null &&
        activeWallet.usesBdk &&
        !canUseLightning &&
        !isSwapMode &&
        _selectedPool != _ReceivePool.usdc &&
        displayOnChainAddress.isEmpty &&
        onChainAddressAsync != null &&
        onChainAddressAsync.isLoading &&
        !onChainAddressAsync.hasValue;

    // Spark / hot wallets can sign both Bitcoin on-chain and
    // Lightning, so the unified BIP21 QR is the default and the
    // "QR format" override chips inside Advanced options let the
    // user force a single-rail QR if a sender wallet needs it.
    // Cold wallets (hardware / watch-only / signer / tracked) can't
    // sign Lightning at all — the override hides and the on-chain
    // address is shown by itself. USDC pool also hides the override
    // (the QR points to the Polymarket Safe; BTC/LN doesn't apply).
    // Hidden in swap mode: the three formats answer "which bitcoin
    // code", which is not the question on screen once the address is
    // another coin's. The way back is the card under the address.
    final bool showFormatPicker = canUseLightning &&
        !isSwapMode &&
        !isUsdcFallback &&
        _selectedPool != _ReceivePool.usdc;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chromeless step body — drops the old surface card so the
          // Receive screen reads as a single flat surface matching
          // the home balance card's no-chrome hierarchy. QR keeps
          // its own white plate (needed for QR contrast); everything
          // else floats directly on the screen gradient.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. QR Code — the shared plate, so the dollars receive
                // cannot end up with a differently sized code.
                ReceiveQrPlate(child: qrContent),
                if (showSyncingCaption) ...[
                  SizedBox(height: ReceiveGaps.qrToCaption),
                  ReceiveCaption(
                      text: context.l10n.receiveSyncingWalletCaption),
                ],

                SizedBox(height: ReceiveGaps.qrToAddress),

                // 2. Address display below QR
                if (isSwapMode && _activeExchange != null) ...[
                  // Suppressed for a stale Orchestra address (see
                  // `_activeSwapAddressUnsupported`) — the copy row
                  // would hand out the very address the QR gate hides.
                  if (!_activeSwapAddressUnsupported) ...[
                    _buildMinimalAddress(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: _selectedSourceAsset!.color,
                      address: _activeExchange!.depositAddress,
                      copyText: _activeExchange!.depositAddress,
                    ),
                    ReceiveKuteFeeCaption(
                      bps: _activeAddressFee?.address ==
                              _activeExchange!.depositAddress
                          ? _activeAddressFee!.bps
                          : null,
                    ),
                  ],
                ] else if (_selectedPool == _ReceivePool.usdc &&
                    _expandedFallback == null) ...[
                  // USDC pool default — caption mirrors the Polymarket
                  // Safe address so the user can copy it without
                  // expanding the fallback row.
                  Builder(builder: (_) {
                    final safe = ref
                        .watch(polymarketTradingProvider)
                        .valueOrNull
                        ?.proxyWalletAddress;
                    if (safe == null || safe.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                      children: [
                        _buildMinimalAddress(
                          icon: Icons.attach_money_rounded,
                          iconColor: const Color(0xFF2775CA),
                          address: safe,
                          copyText: safe,
                        ),
                        SizedBox(height: 8.h),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          child: _UsdcCaption(
                            text: context
                                .l10n.receiveSendUsdcOnPolygonAutoConvert,
                          ),
                        ),
                      ],
                    );
                  }),
                ] else ...[
                  if (_expandedFallback == _FallbackAddress.bitcoin &&
                      displayOnChainAddress.isNotEmpty)
                    _buildMinimalAddress(
                      icon: Icons.link_rounded,
                      iconColor: c.accent,
                      address: displayOnChainAddress,
                      copyText: displayOnChainAddress,
                    ),
                  if (_expandedFallback == _FallbackAddress.unified &&
                      displayOnChainAddress.isNotEmpty) ...[
                    // Unified caption — flipped from "everything behind
                    // a Show-addresses expander" to "Lightning address
                    // always visible, on-chain hidden behind expander".
                    // Tap on the row copies; the small pencil renames.
                    // The QR above already carries both rails, so most
                    // users only need the LN address handy for the
                    // common case of pasting `name@paykute.com` into
                    // a sender app.
                    if (canUseLightning && lightningAddress != null)
                      // Once a specific-amount invoice is generated, the
                      // top row shows the INVOICE (so Copy grabs the
                      // amount-locked bolt11), not the reusable LN
                      // address. Reverts to the @ address on "Done".
                      _lnPaymentResponse != null
                          ? _buildMinimalAddress(
                              icon: Icons.bolt_rounded,
                              iconColor: const Color(0xFFFFD700),
                              address: _lnPaymentResponse!.paymentRequest,
                              copyText: _lnPaymentResponse!.paymentRequest,
                            )
                          : _buildMinimalAddress(
                              icon: Icons.bolt_rounded,
                              iconColor: const Color(0xFFFFD700),
                              address: lightningAddress,
                              copyText: lightningAddress,
                              showEdit: true,
                              editUsername: lnUsername,
                            ),
                  ],
                  if (_expandedFallback == _FallbackAddress.lightning) ...[
                    if (_lnPaymentResponse != null)
                      _buildMinimalAddress(
                        icon: Icons.bolt_rounded,
                        iconColor: const Color(0xFFFFD700),
                        address: _lnPaymentResponse!.paymentRequest,
                        copyText: _lnPaymentResponse!.paymentRequest,
                      )
                    else if (lightningAddress != null)
                      _buildMinimalAddress(
                        icon: Icons.bolt_rounded,
                        iconColor: const Color(0xFFFFD700),
                        address: lightningAddress,
                        copyText: lightningAddress,
                        showEdit: true,
                        editUsername: lnUsername,
                      ),
                  ],
                  if (_expandedFallback == _FallbackAddress.usdc) ...[
                    Builder(builder: (_) {
                      final safe = ref
                          .watch(polymarketTradingProvider)
                          .valueOrNull
                          ?.proxyWalletAddress;
                      if (safe == null || safe.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _buildMinimalAddress(
                        icon: Icons.attach_money_rounded,
                        iconColor: const Color(0xFF2775CA),
                        address: safe,
                        copyText: safe,
                      );
                    }),
                    SizedBox(height: 8.h),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: _UsdcCaption(
                          text: context.l10n.receiveSendUsdcOnPolygon),
                    ),
                  ],
                ],

                // 2a. Share / Copy pills. The subtitle promises "scan or
                // share this code", so the share lives right under the
                // address and hands out the exact payload the QR
                // encodes (unified BIP21, invoice, address or swap
                // deposit address). Hidden while the plate shimmers or
                // shows an error: nothing verified to share yet.
                if (qrPayload != null) ...[
                  SizedBox(height: ReceiveGaps.addressToActions),
                  _buildActionPills(
                      payload: qrPayload, showRequestAmount: showRequestAmount),
                ],

                // Advanced expander (Bitcoin address, QR format,
                // request amount) stays mounted across QR-format
                // switches — picking "Lightning invoice" used to
                // unmount the whole panel because it lived inside
                // the unified-only branch, so the disclosure
                // appeared to snap shut before the user could set
                // an amount. Sits below the pills so the address,
                // the actions and then the options read top-down.
                // The QR format, chosen straight from three buttons.
                // It used to sit two taps deep: a More options
                // disclosure, then a picker sheet. The choice is
                // three states and it belongs on the screen (user
                // decision September 2026).
                if (showFormatPicker &&
                    _selectedPool != _ReceivePool.usdc &&
                    _expandedFallback != _FallbackAddress.usdc) ...[
                  SizedBox(height: 12.h),
                  _QrFormatButtons(
                    selected: _expandedFallback,
                    onSelect: (format) {
                      if (_expandedFallback == format) return;
                      HapticFeedback.selectionClick();
                      TrackingService.track('receive_qr_format_selected',
                          params: {'format': _formatEventName(format)});
                      setState(() => _expandedFallback = format);
                    },
                    unifiedLabel: context.l10n.receiveQrFormatUnified,
                    bitcoinLabel: context.l10n.receiveQrFormatBitcoinOnly,
                    lightningLabel: context.l10n.receiveQrFormatLightningOnly,
                  ),
                ],
                // 2a'. What else this address takes, UNDER the three
                // format buttons (owner decision). Those answer "which
                // bitcoin code"; this states a property of the address
                // they all encode, so it reads after them, not before.
                // At rest it is one quiet line: the words, a few coin
                // marks and a count. With a coin picked, the same slot
                // names the pick, says what it arrives as, and carries
                // the way back to the wallet's own bitcoin.
                ...() {
                  final card = _buildAlsoAcceptsSlot(c);
                  if (card == null) return const <Widget>[];
                  return <Widget>[SizedBox(height: 12.h), card];
                }(),

                // 2b. Lightning address shimmer (Spark wallets,
                // unified view only). The actual lightning row is
                // rendered inline with the BTC row above once the
                // LN address resolves; this branch only handles the
                // loading state so the dual-row block doesn't pop
                // in suddenly when the LN setup future completes.
                if (canUseLightning &&
                    _expandedFallback == _FallbackAddress.unified &&
                    lightningAddress == null &&
                    !(isSwapMode && _activeExchange != null) &&
                    _selectedPool != _ReceivePool.usdc) ...[
                  SizedBox(height: 10.h),
                  setupLnAddressAsync.when(
                    data: (_) => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    loading: () => Center(
                      child: Shimmer.fromColors(
                        baseColor: context.isDark
                            ? Colors.grey.shade700
                            : Colors.grey.shade300,
                        highlightColor: context.isDark
                            ? Colors.grey.shade600
                            : Colors.grey.shade100,
                        child: Container(
                          width: 220.w,
                          height: 18.h,
                          decoration: BoxDecoration(
                            color: c.surfaceLight,
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // 2c. Non-Spark on-chain address. Skipped when the bitcoin fallback row above
                // already rendered the same address — for hardware
                // wallets, `_expandedFallback` defaults to bitcoin,
                // so without this guard the address renders twice.
                if (!canUseLightning &&
                    _expandedFallback != _FallbackAddress.bitcoin &&
                    displayOnChainAddress.isNotEmpty &&
                    !(isSwapMode && _activeExchange != null))
                  _buildMinimalAddress(
                    icon: Icons.link_rounded,
                    iconColor: c.accent,
                    address: displayOnChainAddress,
                    copyText: displayOnChainAddress,
                  ),

                // 3. Hardware wallet verify
                if ((_expandedFallback == _FallbackAddress.bitcoin ||
                        !canUseLightning) &&
                    !isSwapMode &&
                    _activeExchange == null &&
                    activeWallet != null &&
                    activeWallet.isHardware &&
                    activeWallet.walletType == 'ledger' &&
                    activeWallet.scriptType != null) ...[
                  SizedBox(height: 12.h),
                  AppButton(
                    onPressed: _isLedgerVerifying ? null : _verifyOnLedger,
                    text: _isLedgerVerifying
                        ? context.l10n.verifying
                        : context.l10n.verifyOnLedger,
                    icon: Icons.verified_user_outlined,
                    isLoading: _isLedgerVerifying,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                  ),
                ],
                if ((_expandedFallback == _FallbackAddress.bitcoin ||
                        !canUseLightning) &&
                    !isSwapMode &&
                    _activeExchange == null &&
                    activeWallet != null &&
                    activeWallet.isHardware &&
                    activeWallet.walletType == 'jade' &&
                    activeWallet.scriptType != null) ...[
                  SizedBox(height: 12.h),
                  AppButton(
                    onPressed: _isJadeVerifying ? null : _verifyOnJade,
                    text: _isJadeVerifying
                        ? context.l10n.verifying
                        : context.l10n.verifyOnJade,
                    icon: Icons.verified_user_outlined,
                    isLoading: _isJadeVerifying,
                    variant: AppButtonVariant.secondary,
                    compact: true,
                  ),
                ],

                // 4. Cross-asset deposit details. Only swap mode has
                // content here; the native rails used to open this
                // block too and render a lone divider over empty space.
                if (isSwapMode) ...[
                  SizedBox(height: 12.h),
                  if (_activeExchange == null) ...[
                    if (_creatingOrder)
                      // Skeleton mimicking the rate card about to render.
                      KuteSkeleton(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          child:
                              SkeletonBar(double.infinity, 64.h, radius: 12.r),
                        ),
                      )
                    else if (_rateError != null)
                      Container(
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(_rateError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.error, fontSize: 14.sp)),
                      ),
                    if (!_creatingOrder && _rateError != null)
                      _quotedAlternativeAction(),
                  ] else ...[
                    if (_activeSwapAddressUnsupported)
                      _buildUnsupportedSwapNotice(c)
                    else
                      _buildSwapDepositSection(c),
                  ],
                ],
              ],
            ),
          ),
          // Powered-by attribution. Every cross-chain receive settles
          // through Orchestra, the only rail this screen presents, so a
          // retired provider's name never appears here.
          if (isSwapMode || _activeExchange != null) ...[
            SizedBox(height: 14.h),
            const PoweredByBadge(provider: 'Orchestra'),
          ],

          // Bottom breathing room so the last More Way row clears
          // the iOS home indicator. The page's outer SafeArea
          // explicitly turns off the bottom inset to avoid a "fake
          // bar" under the indicator, which left the final row
          // (typically "Show Lightning address") tucked behind the
          // indicator on most phones. Reserving the inset PLUS a
          // 16.h baseline inside the scroll content keeps every
          // option fully visible after a scroll.
          SizedBox(height: 16.h + MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ─── Share-step helpers (ported from old widget) ──────────────

  String _buildUnifiedUri(String bitcoinAddress, String? lnurlBech32) {
    if (lnurlBech32 != null && lnurlBech32.isNotEmpty) {
      return 'bitcoin:$bitcoinAddress?lightning=$lnurlBech32';
    }
    return 'bitcoin:$bitcoinAddress';
  }

  /// Solid Share pill and neutral Copy pill side by side under the
  /// address. Both act on [payload], the exact string the QR encodes.
  /// With [showRequestAmount] a third pill opens the amount sheet; once
  /// a request is live it shows the requested sats and a tap clears it.
  Widget _buildActionPills({
    required String payload,
    required bool showRequestAmount,
  }) {
    final requested = _requestedSats;
    final orchestraId = _activeExchange?.providerName == 'Orchestra'
        ? _activeExchange?.id : null;
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    // Three pills share the row, so labels drop to 14sp and lose the
    // leading icon; the request pill gets more room for its longer copy.
    return ReceiveActionPills(
      onShare: () => _sharePayload(payload, orchestraId: orchestraId),
      onCopy: () => _copyPayload(payload, orchestraId: orchestraId),
      trailing: !showRequestAmount
          ? null
          : requested == null
              ? AppButton(
                  onPressed: _isInvoiceLoading ? null : _requestAmount,
                  text: context.l10n.receiveRequestAmount,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  fontSize: 14.sp,
                  isLoading: _isInvoiceLoading,
                )
              : AppButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(_clearAmountRequest);
                  },
                  text: '₿${requested.toFormattedString(btcFormat)}',
                  icon: Icons.close_rounded,
                  variant: AppButtonVariant.secondary,
                  compact: true,
                  fontSize: 14.sp,
                ),
    );
  }

  /// Hands the QR payload to the OS share sheet. Text only: every
  /// wallet and messenger can take the string, and the payload is what
  /// a scanner of the QR would read. No address or invoice contents
  /// reach analytics, only the payload kind.
  Future<void> _sharePayload(String payload, {String? orchestraId}) async {
    if (!_canExportReceivePayload(payload, orchestraId)) return;
    final invoiceType = _invoiceTypeForShare();
    TrackingService.addressShared(invoiceType);
    TrackingService.track('receive_qr_shared', params: {
      'method': 'share',
      'invoice_type': invoiceType,
    });
    _payloadExported = true;
    TrackingService.moneyFlowStep('receive', 'shared',
        props: _receiveFlowInputs());
    // iPad anchors the share popover to this rect; phones ignore it.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(ShareParams(
      text: payload,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : Rect.zero,
    ));
  }

  /// Clipboard copy with the shared snackbar and the copy events. Used
  /// by the Copy pill and the copy icon on every address row.
  void _copyPayload(String payload, {String? orchestraId}) {
    if (!_canExportReceivePayload(payload, orchestraId)) return;
    Clipboard.setData(ClipboardData(text: payload));
    TrackingService.addressCopied('address');
    TrackingService.track('receive_qr_shared', params: {
      'method': 'copy',
      'invoice_type': _invoiceTypeForShare(),
    });
    _payloadExported = true;
    TrackingService.moneyFlowStep('receive', 'shared',
        props: _receiveFlowInputs());
    showMessageSnackBar(
      message: context.l10n.addressCopiedToClipboard,
      error: false,
      context: context,
    );
  }

  bool _canExportReceivePayload(String payload, String? orchestraId) {
    if (!mounted || payload.isEmpty) return false;
    if (orchestraId == null) return true;
    return _activeExchange?.id == orchestraId &&
        _activeExchange?.depositAddress == payload &&
        _isPickedWalletSparkSpending() &&
        (_sameReceiveSdk?.call() ?? false) &&
        !_activeSwapAddressUnsupported;
  }

  /// Catalog receive options grouped by coin. Both reusable addresses and
  /// quoted deposits here deliver to the Spark spending wallet. Hardware
  /// and watch-only accounts use their own funding flows.
  List<CoinAssetGroup> _alsoAcceptedCoins() {
    // Kick the live Flashnet route-catalog fetch (and rebuild when it
    // lands) so the offering matches today's routes — static
    // stablecoin fallback until then / when offline.
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offersOn = ref.watch(swapOffersEnabledProvider);
    if (_selectedPool == _ReceivePool.usdc) return const [];
    if (!_isPickedWalletSparkSpending()) return const [];
    // `swapOffersEnabledProvider` answers whether an account may be
    // offered swap affordances IT would have to sign for, which is why
    // a cold account is refused them.
    if (!offersOn) return const [];
    return receiveCoinGroups(catalog, context.l10n);
  }

  /// The same gate, read rather than watched, for the sheet that opens
  /// from the line above.
  bool _alsoAcceptsReachable() {
    if (_selectedPool == _ReceivePool.usdc) return false;
    if (!_isPickedWalletSparkSpending()) return false;
    return ref.read(swapOffersEnabledProvider);
  }

  /// The slot under the action pills.
  ///
  /// At rest: one quiet line stating what else the address on screen
  /// takes. With a coin picked: the pick, what it arrives as, and the
  /// way back to the wallet's own bitcoin address.
  Widget? _buildAlsoAcceptsSlot(AppColorsExtension c) {
    final swapAsset = _selectedSourceAsset;
    final swapNetwork = _selectedSourceNetwork;
    if (swapAsset != null && swapNetwork != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OtherAssetsCard(
            leading: swapAsset.iconWidget(size: 36.sp),
            title: swapAsset.name,
            subtitle: context.l10n
                .receiveAssetOnNetwork(swapAsset.code, swapNetwork.name),
            onTap: () {
              HapticFeedback.lightImpact();
              _showSourceAssetPicker();
            },
            // "Back to Bitcoin" is the way out of a coin pick: the
            // native rails are what this screen is otherwise showing.
            secondaryIcon: Icons.arrow_back_rounded,
            secondaryLabel: context.l10n.receiveBackToBitcoin,
            onSecondaryTap: _backToBitcoin,
          ),
          SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: Text(
              context.l10n.receiveFundsLandAsBitcoin,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
    }
    final groups = _alsoAcceptedCoins();
    if (groups.isEmpty) return null;
    return CoinMarksLine(
      label: context.l10n.receiveAlsoAccepts,
      groups: groups,
      moreLabel: context.l10n.receiveAlsoAcceptsMore,
      onTap: () {
        HapticFeedback.lightImpact();
        TrackingService.track('receive_also_accepts_opened',
            params: {'source': 'address', 'coins': groups.length});
        _showSourceAssetPicker();
      },
    );
  }

  /// Stable analytics name for a QR format, independent of copy.
  String _formatEventName(_FallbackAddress? f) {
    switch (f) {
      case _FallbackAddress.bitcoin:
        return 'bitcoin_only';
      case _FallbackAddress.lightning:
        return 'lightning_only';
      default:
        return 'unified';
    }
  }

  /// The address under the QR. Presentation lives in
  /// [ReceiveAddressLine], shared with the dollars receive screen so
  /// the two cannot drift on type, truncation or button size.
  ///
  /// `icon` / `iconColor` are kept on the signature so the call sites
  /// scattered through the Share body don't need a rewrite, but the
  /// leading rail icon is not rendered: it was visual noise next to a
  /// QR that already conveys the rail.
  Widget _buildMinimalAddress({
    required IconData icon,
    required Color iconColor,
    required String address,
    required String copyText,
    bool showEdit = false,
    String? editUsername,
    bool compact = false,
  }) {
    final orchestraId = _activeExchange?.providerName == 'Orchestra'
        ? _activeExchange?.id : null;
    return ReceiveAddressLine(
      address: address,
      compact: compact,
      onCopy: () => _copyPayload(copyText, orchestraId: orchestraId),
      onEdit: showEdit && editUsername != null
          ? () => _showEditUsernameModal(editUsername)
          : null,
    );
  }

  // ─── On-chain BIP21 amount embedding ─────────────────────────

  /// Request amount pill. Opens the hero amount sheet and turns the
  /// result into the request the current QR format can carry: a BIP21
  /// amount on the on-chain address in the Bitcoin-only format, a
  /// Lightning invoice otherwise.
  Future<void> _requestAmount() async {
    TrackingService.moneyFlowStep('receive', 'request_amount',
        props: _receiveFlowInputs());
    final requested = await showRequestAmountSheet(context);
    if (requested == null || !mounted) return;
    ref.read(inputAmountProvider.notifier).state = requested.amount;
    final onChain = _expandedFallback == _FallbackAddress.bitcoin;
    TrackingService.receiveAmountEntered(
        network: onChain ? 'bitcoin' : 'lightning');
    final requestedSats = ref.read(inputToSatsProvider(
        (amount: requested.amount, currency: requested.currency)));
    if (requestedSats > 0) _requestedSats = requestedSats;
    TrackingService.moneyFlowStep('receive', 'amount_entered', props: {
      ..._receiveFlowInputs(),
      'network': onChain ? 'bitcoin' : 'lightning',
      'amount_unit': requested.currency.toLowerCase(),
    });
    if (onChain) {
      _updateOnChainQr(requested);
    } else {
      await _createLightningInvoice(requested);
    }
  }

  /// Drops the live request so the QR goes back to the reusable code.
  /// Callers wrap this in setState.
  void _clearAmountRequest() {
    _lnPaymentResponse = null;
    _includeAmountInOnChain = false;
    _onChainWithAmount = '';
    _requestedSats = null;
  }

  void _updateOnChainQr(RequestedAmount requested) {
    // Build the BIP21 URI from the PICKED wallet's address, the same
    // source the QR renders from. `addressProvider` is pinned to the
    // active spending wallet, so reading it here embedded the spending
    // wallet's address in a QR the user believed pointed at the picked
    // (imported / hardware) wallet.
    final pickedId = _pickedReceiveWalletId;
    final address = pickedId == null
        ? ''
        : (ref.read(walletAddressProvider(pickedId)).valueOrNull ?? '');
    if (address.isEmpty) return;
    final args = (amount: requested.amount, currency: requested.currency);
    final sats = ref.read(inputToSatsProvider(args));
    if (sats <= 0) return;
    final btcAmount = ref.read(inputToBtcStringProvider(args));
    setState(() {
      _includeAmountInOnChain = true;
      _onChainWithAmount = 'bitcoin:$address?amount=$btcAmount';
      _requestedSats = sats;
    });
    HapticFeedback.mediumImpact();
  }

  // ─── Lightning invoice (Spark hot wallet) ─────────────────────

  Future<void> _createLightningInvoice(RequestedAmount requested) async {
    final amountSat = ref.read(inputToSatsProvider(
        (amount: requested.amount, currency: requested.currency)));
    if (amountSat <= 0) {
      showMessageSnackBar(
        context: context,
        message: context.l10n.pleaseEnterAValidAmount,
        error: true,
      );
      return;
    }
    setState(() => _isInvoiceLoading = true);
    try {
      // The memo the payer's wallet shows; a plain localized sentence.
      final response = await ref.read(receivePaymentProvider((
        amount: BigInt.from(amountSat),
        description: context.l10n.lightningInvoiceMemo,
      )).future);
      if (!mounted) return;
      setState(() {
        _lnPaymentResponse = response;
        _requestedSats = amountSat;
      });
      // Feedback that the invoice is live — the QR, top row, and the
      // pill switch to it; a haptic confirms the tap registered.
      HapticFeedback.mediumImpact();
      TrackingService.receiveInvoiceGenerated(hasAmount: amountSat > 0);
      TrackingService.moneyFlowStep('receive', 'invoice_generated',
          props: _receiveFlowInputs());
    } catch (e) {
      TrackingService.moneyFlowError('receive', e);
      if (!mounted) return;
      showMessageSnackBar(
        context: context,
        message: railSafeErrorCopy(context, e,
            fallback: context.l10n.receiveRequestFailed),
        error: true,
      );
      setState(() {
        _lnPaymentResponse = null;
      });
    } finally {
      if (mounted) setState(() => _isInvoiceLoading = false);
    }
  }

  /// The wallet the user picked on Step 0 (falls back to active). Receive
  /// must settle to THIS wallet, not the active/spending wallet that
  /// `addressProvider` is pinned to.
  String? get _pickedReceiveWalletId =>
      _selectedWalletId ?? ref.read(settingsProvider).activeWalletId;

  /// BTC settle address of the picked wallet. Falls back to the active
  /// wallet's `addressProvider` cache only when the picked wallet IS the
  /// active wallet; otherwise returns '' so the caller's empty-address
  /// handling runs.
  ///
  /// FUND-SAFETY: a swap must never settle to a different wallet than
  /// the one the user picked. `addressProvider` is pinned to the active
  /// wallet, so using it as a fallback for another pick would redirect
  /// the deposit.
  Future<String> _resolvePickedBtcAddress() async {
    final pickedId = _pickedReceiveWalletId;
    if (pickedId != null) {
      try {
        final addr = await ref.read(walletAddressProvider(pickedId).future);
        if (addr.isNotEmpty) return addr;
      } catch (_) {
        // Fall through to the active wallet address below.
      }
      if (pickedId != ref.read(settingsProvider).activeWalletId) return '';
    }
    return ref.read(addressProvider).bitcoinAddress;
  }

  // ─── Orchestra cross-chain receive ────────────────────────────

  /// FUND-SAFETY: true when the active swap deposit address must not
  /// be offered to pay into. Two cases:
  ///   * it is not an Orchestra accumulation address at all. Orchestra
  ///     is the only rail this screen mints for; any other provider's
  ///     order is a legacy swap order whose address is retired, and
  ///     its history belongs in Activity, never on the Receive QR.
  ///   * it is an Orchestra address whose (asset, network) pair is NOT
  ///     on Orchestra's current receive catalog (live Flashnet catalog,
  ///     static fallback — orchestra_routes.dart). Such an address
  ///     comes from the reuse cache: it was minted when the catalog
  ///     still carried the pair, and rendering it again under the
  ///     "reusable, converts automatically" caption invites a deposit
  ///     the retired route may never convert.
  bool get _activeSwapAddressUnsupported {
    final order = _activeExchange;
    if (order == null) return false;
    if (order.providerName != 'Orchestra') return true;
    final asset = _selectedSourceAsset;
    final network = _selectedSourceNetwork;
    if (asset == null || network == null) return false;
    if (!_isPickedWalletSparkSpending() ||
        !(_sameReceiveSdk?.call() ?? false)) {
      return true;
    }
    return orchestraReceiveChainForDestination(asset.code, network.network,
            destinationAsset: order.coinTo) ==
        null;
  }

  /// Quiet replacement for `_buildSwapDepositSection` when
  /// [_activeSwapAddressUnsupported]: no address, no reusable promise,
  /// just the notice plus the supported-asset picker as the way
  /// forward.
  Widget _buildUnsupportedSwapNotice(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Text(
            context.l10n.receiveAssetTemporarilyUnavailable,
            style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: 12.h),
        AppButton(
          onPressed: () {
            TrackingService.receiveUnsupportedAssetPickerOpened(
              asset: _selectedSourceAsset?.code ?? '',
              network: _selectedSourceNetwork?.network ?? '',
            );
            _resetSwapState();
            _showSourceAssetPicker();
          },
          text: context.l10n.receiveOtherAssets,
        ),
      ],
    );
  }

  Widget _buildSwapDepositSection(AppColorsExtension c) {
    final order = _activeExchange!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order.depositExtraId != null &&
            order.depositExtraId!.isNotEmpty) ...[
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: order.depositExtraId!));
              showMessageSnackBar(
                  message: context.l10n.addressCopiedToClipboard,
                  error: false,
                  context: context);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.note_outlined, size: 14.sp, color: Colors.orange),
                  SizedBox(width: 6.w),
                  Text(context.l10n.memoColon,
                      style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500)),
                  Expanded(
                    child: Text(order.depositExtraId!,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace')),
                  ),
                  Icon(Icons.copy_rounded, size: 12.sp, color: c.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// What a one-off address is, said before the user shares it: one
  /// payment, roughly this much, gone in a couple of minutes, and
  /// where anything that misses goes. Once it lapses the same block
  /// says so and offers a fresh one, which is the whole bargain of
  /// this rail: no standing address, new ones on demand.
  void _resetSwapState() {
    _receiveRequestId++;
    _stopPolling();
    setState(() {
      _selectedSourceAsset = null;
      _selectedSourceNetwork = null;
      _rateError = null;
      _activeExchange = null;
      _activeAddressFee = null;
      _creatingOrder = false;
    });
  }

  /// Leaves swap mode and restores the wallet's default native format:
  /// the unified BIP21 code on hot wallets, the on-chain address on
  /// cold ones (the same rule `initState` applies).
  void _backToBitcoin() {
    HapticFeedback.selectionClick();
    _resetSwapState();
    final wallet = _selectedAccount?.wallet;
    final hasLightning = wallet != null &&
        wallet.sparkEnabled &&
        !wallet.isHardware &&
        !wallet.isWatchOnly &&
        !wallet.isExternalAddress;
    setState(() {
      // The USDC pool keeps `null` so its own caption renders.
      _expandedFallback = _selectedPool == _ReceivePool.usdc
          ? null
          : hasLightning
              ? _FallbackAddress.unified
              : _FallbackAddress.bitcoin;
    });
    TrackingService.track('receive_invoice_type_selected',
        params: {'invoice_type': _invoiceTypeForShare()});
  }

  void _resetShareState() {
    _receiveRequestId++;
    _sameReceiveSdk = null;
    _isInvoiceLoading = false;
    _clearAmountRequest();
    _selectedSourceAsset = null;
    _selectedSourceNetwork = null;
    _activeExchange = null;
    _activeAddressFee = null;
    _rateError = null;
    _creatingOrder = false;
    _stopPolling();
  }

  Future<void> _createReceiveOrder(double userAmount) async {
    final asset = _selectedSourceAsset;
    final network = _selectedSourceNetwork;
    if (asset == null || network == null) return;

    final requestId = ++_receiveRequestId;
    final walletId = _pickedReceiveWalletId;
    bool current() => mounted && requestId == _receiveRequestId &&
        walletId == _pickedReceiveWalletId &&
        _isPickedWalletSparkSpending() &&
        identical(asset, _selectedSourceAsset) &&
        identical(network, _selectedSourceNetwork);

    final btcAddress = await _resolvePickedBtcAddress();
    if (!current() || btcAddress.isEmpty) return;

    // Orchestra (Flashnet) accumulation address for BTC-pool receives
    // on the Spark spending wallet when (asset, network) is on
    // Orchestra's stablecoin→BTC table (orchestra_routes.dart).
    // Persistent + reusable, and delivers BTC natively on Spark — no
    // L1 settle leg. Hardware/watch-only wallets can't take this path
    // (accumulation addresses need a `recipientSparkAddress`) and have
    // no second rail, which is why they are never offered a coin to
    // pick in the first place. The USDC pool settles to the Polygon
    // Safe, which no deposit address can pay, and it is refused at the
    // bottom with a reason rather than routed somewhere else.
    // Why the MINT refused, when it was reached and refused. Null
    // means it was never reached at all, which is a different refusal
    // with a different way out, and the two must not borrow each
    // other's sentence.
    String? mintRefusal;
    if (_selectedPool != _ReceivePool.usdc && _isPickedWalletSparkSpending()) {
      final orchChain = orchestraReceiveChainForDestination(
          asset.code, network.network,
          destinationAsset: 'BTC');
      if (orchChain != null) {
        mintRefusal = await _createOrchestraReceiveAddress(
          asset: asset,
          network: network,
          sourceChain: orchChain,
          current: current,
        );
        if (!current() || mintRefusal == null) return;
      }
    }

    // Orchestra could not take it, and there is no second rail. The
    // coin and chain they picked are fine; it is the destination that
    // cannot be delivered to, so the refusal must say so rather than
    // call the route "temporarily unavailable".
    //
    // What still reaches here is a receive into the Predictions
    // balance, which settles on Polygon at a Safe no deposit address
    // can pay; a coin picked on a wallet the standing rail cannot
    // deliver to; and a standing address the mint itself refused. The
    // third used to wear the second's sentence, so someone already on
    // the spending wallet was told to switch to it. Each says what
    // actually happened and what to do next instead.
    if (mounted && current()) {
      final message = _selectedPool == _ReceivePool.usdc
          ? context.l10n.receiveOtherCoinsNotToPredictions
          : mintRefusal ?? context.l10n.receiveOtherCoinsSpendingOnly;
      setState(() {
        _creatingOrder = false;
        _rateError = message;
      });
      showMessageSnackBar(message: message, error: true, context: context);
    }
  }

  /// True when the wallet picked on Step 0 is the Spark spending
  /// wallet — the only wallet Orchestra accumulation addresses can
  /// deliver to. `sparkSelfAddressProvider` resolves through
  /// `breezSDKProvider`, which is pinned to the spending wallet for the
  /// whole session (see breez_config_provider.dart), so a "hot but not
  /// spending" pick would silently land the BTC in the wrong wallet.
  /// Same predicate as `_pickSpending` there.
  bool _isPickedWalletSparkSpending() {
    final settings = ref.read(settingsProvider);
    final spending = settings.wallets.where((w) => w.isSparkWallet).firstOrNull;
    return spending != null && spending.id == _pickedReceiveWalletId;
  }

  /// Orchestra receive: get-or-create the persistent accumulation
  /// address for (sourceChain, asset) → BTC on Spark and surface it as
  /// the active "exchange". Deliberately records NO exchange row here —
  /// accumulation addresses have no order id at creation (Flashnet
  /// spawns an `ord_…` order per inbound deposit), so a row written now
  /// would make background sync poll a nonexistent id forever. The
  /// history poll in `_startOrchestraHistoryPolling` discovers spawned
  /// orders and records them then.
  ///
  /// Returns null when the address is on screen, and otherwise the
  /// sentence to show: there is no other rail to fall back to, so the
  /// caller refuses the receive and this is the reason it refuses
  /// with. It must never be the wrong-wallet sentence, which is what a
  /// bare false used to collapse into.
  Future<String?> _createOrchestraReceiveAddress({
    required _DestAsset asset,
    required _DestNetwork network,
    required String sourceChain,
    required bool Function() current,
  }) async {
    setState(() {
      _creatingOrder = true;
    });

    TrackingService.receiveSourceSelected(
        asset: asset.code, network: network.network, provider: 'orchestra');
    _sourceAssetPicked = asset.code;
    _sourceNetworkPicked = network.network;
    TrackingService.moneyFlowStep('receive', 'source_selected',
        props: _receiveFlowInputs());

    try {
      final wrapper = await ref.read(breezSDKProvider.future);
      if (!current()) return _mintRefusedWhileGone;
      final sdk = wrapper.instance;
      if (sdk == null) throw StateError('Wallet unavailable');
      bool sameSdk() => identical(wrapper.instance, sdk) &&
          identical(ref.read(breezSDKProvider).asData?.value.instance, sdk);
      _sameReceiveSdk = sameSdk;
      final received = await sdk.receivePayment(
        request: const ReceivePaymentRequest(
          paymentMethod: ReceivePaymentMethod.sparkAddress(),
        ),
      );
      if (!current() || !sameSdk()) return _mintRefusedWhileGone;
      final sparkAddress = received.paymentRequest;
      const destinationAsset = 'BTC';
      // Snapshot of already-issued deposit addresses, compared in memory
      // only, so `receive_address_generated` can say whether this is a
      // reuse. The address itself never leaves the device.
      final priorAddresses = AccumulationAddressCache.getAll()
          .map((a) => a.depositAddress)
          .toSet();
      final result = await AccumulationAddressCache.getOrCreate(
        sourceChain: sourceChain,
        sourceAsset: orchestraAssetCodeFor(asset.code),
        destinationAsset: destinationAsset,
        recipientSparkAddress: sparkAddress,
      );
      final depositAddress = result.data?.depositAddress ?? '';
      final kuteFeeBps = result.data?.kuteFeeBps;
      if (!current() || !sameSdk()) return _mintRefusedWhileGone;
      if (depositAddress.isEmpty) {
        throw result.error ?? 'Failed to create deposit address';
      }

      // Local display object only — drives the QR, the address row and
      // the reusable-address caption (`providerName == 'Orchestra'` in
      // `_buildSwapDepositSection`). NOT added to `swapOrdersProvider`;
      // see the doc comment above.
      final display = SwapOrder(
        activityDirection: 'receive',
        id: result.data!.id,
        coinFrom: asset.code,
        networkFrom: network.network,
        coinTo: destinationAsset,
        networkTo: 'SPARK',
        depositAddress: depositAddress,
        depositAmount: '0',
        withdrawalAmount: '0',
        status: 'wait',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: sparkAddress,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: _pickedReceiveWalletId,
      );

      // No `swap_initiated` here: showing (or re-showing) a reusable
      // deposit address is not a swap, and counting it inflated the
      // swap funnel.
      TrackingService.track('receive_address_generated', params: {
        'asset': asset.code,
        'network': network.network,
        'provider': 'orchestra',
        'reused': priorAddresses.contains(depositAddress),
        'destination': 'spark_btc',
        'address_kind': 'reusable_deposit',
        if (kuteFeeBps != null) 'kute_fee_bps': kuteFeeBps,
      });
      TrackingService.moneyFlowStep('receive', 'deposit_address_shown',
          props: _receiveFlowInputs());
      if (mounted) {
        setState(() {
          _creatingOrder = false;
          _activeExchange = display;
          _activeAddressFee = (address: depositAddress, bps: kuteFeeBps);
        });
        _startPolling(display);
      }
      return null;
    } catch (e) {
      TrackingService.swapFailed(
          fromCoin: asset.code,
          toCoin: 'BTC',
          provider: 'orchestra',
          reason: e.toString());
      // There is no second rail. Hand the caller the reason so it can
      // say the coin or the network is the problem, rather than the
      // wallet the person is already on.
      if (!current()) return _mintRefusedWhileGone;
      TrackingService.track('receive_address_failed', params: {
        'asset': asset.code,
        'network': network.network,
        'provider': 'orchestra',
        'error_category': TrackingService.errorCategory(e),
      });
      TrackingService.moneyFlowError('receive', e);
      setState(() => _creatingOrder = false);
      return _mintRefusalCopy(e);
    }
  }

  /// Stands in for the reason when the screen went away mid-mint. The
  /// caller only ever puts a reason on screen while mounted, so this
  /// is never read as copy; it exists so "refused" stays distinct from
  /// "never attempted" on a path that cannot ask for a sentence.
  static const String _mintRefusedWhileGone = 'mint_refused';

  /// What to say when the MINT refused, as opposed to when the wallet
  /// was the wrong one. The guard against the rails' own vocabulary
  /// lives in [railSafeErrorCopy], shared with the dollars receive.
  String _mintRefusalCopy(Object error) => railSafeErrorCopy(
        context,
        error,
        fallback: context.l10n.receiveCoinNetworkUnavailable,
      );

  void _startPolling(SwapOrder exchange) {
    _stopPolling();
    // Orchestra accumulation addresses have no order to poll by id —
    // the address history is the discovery mechanism. Nothing else is
    // ever polled from this screen.
    if (exchange.providerName != 'Orchestra') return;
    _startOrchestraHistoryPolling(exchange);
  }

  /// Orchestra variant of `_startPolling`. An accumulation address
  /// spawns an `ord_…` order server-side only when a deposit actually
  /// arrives, so poll the address history on the same 10 s cadence:
  /// each newly-seen order is recorded as a
  /// SwapOrder(provider: 'Orchestra') — from there the shared
  /// tx UI and background sync's getStatus poller take over — and
  /// mirrored into `_activeExchange` as arrival progress. The timer
  /// deliberately never self-cancels: the address is reusable and more
  /// deposits may follow; `dispose`/`_resetSwapState` cancel it.
  /// Off-screen deposits are covered by background sync's
  /// accumulation-address sweep, which shares this loop's vocabulary
  /// and attribution rule (orchestra_routes.dart).
  void _startOrchestraHistoryPolling(SwapOrder display) {
    _orchestraPoller.start(
      display,
      stillWanted: () => mounted && _pickedReceiveWalletId == display.walletId,
      onProgress: (exchange) {
        if (mounted) setState(() => _activeExchange = exchange);
      },
    );
  }

  void _showSourceAssetPicker({String? initialAssetCode}) {
    // THE ENTRY POINT IS THE GATE. A wallet Kute does not spend from
    // has no rail to take another coin on (see [_alsoAcceptedCoins]),
    // so the picker does not open at all, including from the one-shot
    // hand-offs that ask for it on mount. An empty sheet would be the
    // same dead end one screen later.
    if (!_isPickedWalletSparkSpending()) return;
    _showTwoPaneReceivePicker(initialAssetCode: initialAssetCode);
  }

  /// Choose a coin, then its network when needed. Reusable options mint
  /// an address; one-time options first collect an amount and return address.
  void _showTwoPaneReceivePicker({String? initialAssetCode}) {
    // Rows only where a deposit address can actually deliver: the BTC
    // pool on the spending wallet, with swap offers on. Every other
    // wallet never reaches here (the entry point refuses first).
    final reachable = _alsoAcceptsReachable();
    final closed = showAppBottomSheet<void>(
      context: context,
      builder: (sheetCtx) => Consumer(
        builder: (ctx, sheetRef, _) {
          // Watch so the offering re-folds the moment the live catalog
          // lands (static fallback serves until then).
          final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
          final loading =
              sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
          final offered = reachable
              ? receiveCoinGroups(catalog, ctx.l10n)
              : const <CoinAssetGroup>[];
          return CoinAssetPickerSheet(
            groups: offered,
            title: ctx.l10n.receiveAlsoAcceptsTitle,
            subtitle: ctx.l10n.receiveAlsoAcceptsSubtitle,
            // Still fetching is not the same as nothing to offer.
            emptyLabel:
                loading ? ctx.l10n.receiveCoinsLoading : ctx.l10n.noResults,
            flow: 'receive',
            depositAddress: true,
            initialAssetCode: initialAssetCode,
            selectedOptionId: _selectedSourceAsset != null &&
                    _selectedSourceNetwork != null
                ? '${_selectedSourceNetwork!.network}:${_selectedSourceAsset!.code}'
                : null,
            onPicked: (option) {
              Navigator.of(sheetCtx).pop();
              TrackingService.track('receive_also_accepts_selected', params: {
                'asset': option.assetCode,
                'chain': option.chain,
              });
              _pickOrchestraOption(option);
            },
          );
        },
      ),
    );
    unawaited(closed);
  }

  /// Reusable pairs stay on this page. Quoted deposits collect their
  /// source amount and refund address in the shared receive flow.
  void _pickOrchestraOption(OrchestraReceiveOption option) {
    // The event keeps the catalogue's asset code, like every other row.
    TrackingService.swapAssetSelected(flow: 'receive', asset: option.assetCode);
    if (!mounted || !_alsoAcceptsReachable()) return;
    if (!option.reusableAddress) {
      _openQuotedReceive(option);
      return;
    }
    final isDollars = isOrchestraUsdRoute(option.chain, option.assetCode);
    setState(() {
      _resetShareState();
      _selectedSourceAsset = _DestAsset(
        code: option.assetCode,
        // Already the localized label for the dollar row (the sheet
        // rewrote it before handing the option over).
        name: option.displayName,
        color: _getCoinColor(option.displaySymbol.toUpperCase()),
        // The dollar balance has a local mark; the catalogue ships no
        // artwork for it.
        svgAsset: isDollars ? kUsdMarkAsset : null,
        iconUrl: isDollars
            ? null
            : (option.assetIconUrl ?? orchestraAssetIconUrl(option.assetCode)),
      );
      _selectedSourceNetwork = _DestNetwork(
        network: option.chain,
        name: option.chainDisplayName,
        addressHint: '',
      );
      _expandedFallback = null;
    });
    _createReceiveOrder(0);
  }

  void _openQuotedReceive(OrchestraReceiveOption option) {
    if (!_alsoAcceptsReachable()) return;
    // One-time addresses are an operator switch; a hand-off must not
    // reach the quoted screen while it is off.
    if (!oneTimeReceiveAllowed(RuntimeCapabilitiesService.instance)) return;
    _receiveRequestId++;
    _stopPolling();
    unawaited(Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => QuotedReceiveScreen(
        option: option,
        destinationAsset: 'BTC',
      ),
    )));
  }

  Widget _quotedAlternativeAction() {
    if (!_alsoAcceptsReachable()) return const SizedBox.shrink();
    if (!oneTimeReceiveAllowed(RuntimeCapabilitiesService.instance)) {
      return const SizedBox.shrink();
    }
    final option = ref.watch(orchestraSupportedRoutesProvider)
        .receiveOptions()
        .where((o) => o.assetCode == _selectedSourceAsset?.code &&
            o.chain == _selectedSourceNetwork?.network &&
            !isVenueInternalRoute(o.chain, o.assetCode) &&
            orchestraCanQuoteReceiveOn(o.chain))
        .firstOrNull;
    if (option == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: ReceiveGaps.block),
      child: AppButton(
        text: context.l10n.receiveOneOffUseAddress,
        variant: AppButtonVariant.secondary,
        compact: true,
        onPressed: () => _openQuotedReceive(option),
      ),
    );
  }

  // ─── Misc helpers ─────────────────────────────────────────────

  Widget _buildErrorDisplay(String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.error, fontSize: 14.sp),
        ),
      ),
    );
  }

  // ─── Username edit modal (ported verbatim from old widget) ────

  void _showEditUsernameModal(String currentUsername) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditUsernameModalSheet(currentUsername: currentUsername),
    );
  }

  // ─── Hardware verify (Ledger / Jade) ──────────────────────────

  /// The same confirmation every money moment ends on: one check, one
  /// line, Done. Done only pops the overlay, so the user lands back on
  /// the share step with the verified address still on screen.
  void _showAddressVerified({
    required String message,
    required String device,
  }) {
    if (device == 'ledger') {
      TrackingService.ledgerAddressVerified(context: 'receive');
    }
    TrackingService.track('receive_verify_confirmation_shown',
        params: {'device': device});
    final rootNav = Navigator.of(context, rootNavigator: true);
    pushKuteSuccessOverlay(
      navigator: rootNav,
      overlay: KuteConfirmation(
        message: message,
        onDone: () => rootNav.pop(),
      ),
    );
  }

  Future<void> _verifyOnLedger() async {
    final settings = ref.read(settingsProvider);
    // Use the picked wallet (the one whose address is on the QR), not
    // settings.activeWallet — those diverge whenever the receive flow
    // is opened on a savings wallet while a Spark spending wallet is
    // system-active. Reading the spending wallet's null scriptType
    // here is what was crashing the verify call.
    final pickedWalletId = _selectedWalletId ?? settings.activeWalletId;
    final pickedWallet = pickedWalletId == null
        ? null
        : settings.wallets.firstWhere(
            (w) => w.id == pickedWalletId,
            orElse: () => settings.activeWallet!,
          );
    if (pickedWallet == null ||
        !pickedWallet.isHardware ||
        pickedWallet.walletType != 'ledger' ||
        pickedWallet.scriptType == null) {
      return;
    }
    // BDK's `nextUnusedAddress` skips past every previously-used
    // scriptPubKey in history, so the displayed address can be at any
    // derivation index (1, 2, … not just 0). Read the same `(address,
    // index)` pair that the QR is rendered from and pass the index to
    // the Ledger so the device's verify screen derives the matching
    // address. Hardcoding 0 here silently mismatched whenever index 0
    // had ever been used — fund-loss-risk bug.
    final info =
        ref.read(walletReceiveInfoProvider(pickedWallet.id)).valueOrNull;
    final addressIndex = info?.index ?? 0;
    final displayAddress = info?.address ?? '';
    final ledger = ref.read(ledgerServiceProvider.notifier);
    final device = await showLedgerDevicePicker(context, ref);
    if (device == null || !mounted) return;
    setState(() => _isLedgerVerifying = true);
    try {
      final ledgerAddress = await ledger.verifyReceiveAddress(
        scriptType: pickedWallet.scriptType,
        addressIndex: addressIndex,
      );
      if (mounted && ledgerAddress != null) {
        if (ledgerAddress == displayAddress) {
          _showAddressVerified(
            message: context.l10n.addressVerifiedOnLedger,
            device: 'ledger',
          );
        } else {
          showMessageSnackBar(
            message:
                context.l10n.addressMismatchTheAddressOnYourLedgerDoesNotMatch,
            error: true,
            context: context,
          );
        }
      } else if (mounted) {
        final failure = ref.read(ledgerServiceProvider).failure;
        if (failure != null) {
          showMessageSnackBar(
            message: ledgerFailureMessage(context.l10n, failure),
            error: true,
            context: context,
          );
        }
      }
      await ledger.disconnect();
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          message: ledgerErrorMessage(context.l10n, e),
          error: true,
          context: context,
        );
      }
    } finally {
      if (mounted) setState(() => _isLedgerVerifying = false);
    }
  }

  Future<void> _verifyOnJade() async {
    final settings = ref.read(settingsProvider);
    final pickedWalletId = _selectedWalletId ?? settings.activeWalletId;
    final pickedWallet = pickedWalletId == null
        ? null
        : settings.wallets.firstWhere(
            (w) => w.id == pickedWalletId,
            orElse: () => settings.activeWallet!,
          );
    if (pickedWallet == null ||
        !pickedWallet.isHardware ||
        pickedWallet.walletType != 'jade' ||
        pickedWallet.scriptType == null) {
      return;
    }
    // See `_verifyOnLedger` — `nextUnusedAddress` may pick a non-zero
    // derivation index. Verify must request the exact same index so
    // the on-device address matches the QR.
    final info =
        ref.read(walletReceiveInfoProvider(pickedWallet.id)).valueOrNull;
    final addressIndex = info?.index ?? 0;
    final displayAddress = info?.address ?? '';
    final jade = ref.read(jadeServiceProvider.notifier);
    final device = await showJadeDevicePicker(context, ref);
    if (device == null || !mounted) return;
    setState(() => _isJadeVerifying = true);
    try {
      final connected = await jade.connectToDevice(device);
      if (!connected) {
        if (mounted) {
          final jadeState = ref.read(jadeServiceProvider);
          showMessageSnackBar(
            message: userErrorCopy(context, jadeState.errorMessage,
                fallback: context.l10n.receiveConnectionFailed),
            error: true,
            context: context,
          );
        }
        return;
      }
      if (mounted) {
        showMessageSnackBar(
          message: context.l10n.enterYourPinOnTheJadeDevice,
          error: false,
          context: context,
        );
      }
      final authenticated = await jade.authenticate();
      if (!authenticated) {
        if (mounted) {
          final jadeState = ref.read(jadeServiceProvider);
          showMessageSnackBar(
            message: jadeState.errorMessage ??
                context.l10n.receiveAuthenticationFailed,
            error: true,
            context: context,
          );
        }
        await jade.disconnect();
        return;
      }
      final jadeAddress = await jade.verifyReceiveAddress(
        scriptType: pickedWallet.scriptType,
        addressIndex: addressIndex,
      );
      if (mounted && jadeAddress != null) {
        if (jadeAddress == displayAddress) {
          _showAddressVerified(
            message: context.l10n.addressVerifiedOnJade,
            device: 'jade',
          );
        } else {
          showMessageSnackBar(
            message:
                context.l10n.addressMismatchTheAddressOnYourJadeDoesNotMatch,
            error: true,
            context: context,
          );
        }
      } else if (mounted) {
        final jadeState = ref.read(jadeServiceProvider);
        showMessageSnackBar(
          message: railSafeErrorCopy(context, jadeState.errorMessage,
              fallback: context.l10n.receiveFailedToVerifyAddressOnJade),
          error: true,
          context: context,
        );
      }
      await jade.disconnect();
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
          message: railSafeErrorCopy(context, e,
              fallback: context.l10n.receiveFailedToVerifyAddressOnJade),
          error: true,
          context: context,
        );
      }
    } finally {
      if (mounted) setState(() => _isJadeVerifying = false);
    }
  }
}

/// Caption under the USDC address: the plain instruction, with the bridged
/// token note as a smaller details line so the main sentence stays simple.
class _UsdcCaption extends StatelessWidget {
  const _UsdcCaption({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Text(
          text,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 2.h),
        Text(
          context.l10n.receiveBridgedUsdcAccepted,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 11.sp,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─── Username edit modal sheet ──────────────────────────────────
//
// Ported verbatim from the prior `receive_bitcoin_widget.dart`.
// Surfaces from the Lightning fallback row's pencil icon and from
// the inline `username@paykute.com` chip in the unified Spark view.
class EditUsernameModalSheet extends ConsumerStatefulWidget {
  final String currentUsername;
  const EditUsernameModalSheet({super.key, required this.currentUsername});

  @override
  ConsumerState<EditUsernameModalSheet> createState() =>
      _EditUsernameModalSheetState();
}

class _EditUsernameModalSheetState
    extends ConsumerState<EditUsernameModalSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.currentUsername);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submitEditUsername() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final newUsername = _usernameController.text;
    try {
      final result =
          await ref.read(createOrEditLnurlProvider(newUsername).future);

      if (result.lightningAddress != null) {
        ref
            .read(addressProvider.notifier)
            .updateLightningAddress(result.lightningAddress);
        // Keep the backend's affiliate payout_address in sync with the
        // user's newly-chosen @paykute address. Fire-and-forget: the local
        // edit must not block on (or fail because of) the backend, and the
        // boot-time background registration re-syncs if this misses.
        unawaited(
          AffiliateService.syncPayoutAddress(result.lightningAddress!),
        );
      }

      if (mounted) {
        ref.invalidate(setupLnAddressProvider);

        showMessageSnackBar(
          message: context.l10n.usernameUpdatedSuccessfully,
          error: false,
          context: context,
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (e is UsernameConflictException) {
            _errorMessage = context.l10n.usernameAlreadyExists;
          } else {
            _errorMessage = context.l10n.anErrorOccurredPleaseTryAgain;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: AnimatedPadding(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 100),
        padding: EdgeInsets.only(
          bottom: bottomInset,
          left: 20.w,
          right: 20.w,
          top: 12.h,
        ),
        // Bottom sheets must clear the OS bottom inset on both platforms.
        child: SafeArea(
          top: false,
          bottom: bottomInset <= 0,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: c.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Text(
                    context.l10n.editLightningAddress,
                    style: TextStyle(
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary,
                        letterSpacing: -0.6),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    context.l10n.receivePickANewHandle,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  TextFormField(
                    controller: _usernameController,
                    keyboardType: TextInputType.text,
                    autofocus: true,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: c.textPrimary.withValues(alpha: 0.04),
                      hintText: context.l10n.username,
                      hintStyle: TextStyle(
                          color: c.textTertiary,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w500),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide(
                            color: context.colors.accent, width: 1.5),
                      ),
                      suffixText: '@paykute.com',
                      suffixStyle: TextStyle(
                          color: c.textTertiary,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 18.h),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return context.l10n.pleaseEnterAUsername;
                      }
                      if (RegExp(r'[^a-z0-9._-]').hasMatch(value)) {
                        return context
                            .l10n.onlyLowercaseLettersNumbersAndAreAllowed2;
                      }
                      return null;
                    },
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: EdgeInsets.only(top: 10.h),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                            color: AppColors.error,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  SizedBox(height: 24.h),
                  AppButton(
                    onPressed: _isLoading ? null : _submitEditUsername,
                    text: context.l10n.saveChanges,
                    isLoading: _isLoading,
                  ),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The receive screen's other-assets card: a neutral surface card in
/// the house grammar (hairline border, 14 radius) with one full-width
/// row per action. The first row is the door to the picker, or the
/// selected asset once one is picked; the optional second row is the
/// way back to bitcoin. Rows are 56pt tall targets and the labels wrap
/// at large text scales instead of clipping.
class _OtherAssetsCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? secondaryIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  const _OtherAssetsCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.secondaryIcon,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hasSecondary = secondaryLabel != null && onSecondaryTap != null;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                child: Row(
                  children: [
                    leading,
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 2.h),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(Icons.chevron_right_rounded,
                        color: c.textTertiary, size: 22.sp),
                  ],
                ),
              ),
            ),
            if (hasSecondary) ...[
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: c.borderSubtle,
                indent: 14.w,
                endIndent: 14.w,
              ),
              InkWell(
                onTap: onSecondaryTap,
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                  child: Row(
                    children: [
                      if (secondaryIcon != null) ...[
                        Icon(secondaryIcon, color: c.textPrimary, size: 18.sp),
                        SizedBox(width: 10.w),
                      ],
                      Expanded(
                        child: Text(
                          secondaryLabel!,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tappable circular icon button used next to the receive address
/// row (copy, edit). Larger 36×36 target with a subtle tinted
/// background so users can hit it without precision tapping, and
/// the icon itself stays readable at arm's length. Replaces the
/// 14sp grey icons that were hard to see and hard to tap.
class _QrFormatButtons extends StatelessWidget {
  const _QrFormatButtons({
    required this.selected,
    required this.onSelect,
    required this.unifiedLabel,
    required this.bitcoinLabel,
    required this.lightningLabel,
  });

  final _FallbackAddress? selected;
  final ValueChanged<_FallbackAddress?> onSelect;
  final String unifiedLabel;
  final String bitcoinLabel;
  final String lightningLabel;

  @override
  Widget build(BuildContext context) {
    final options = <(_FallbackAddress?, String)>[
      (_FallbackAddress.unified, unifiedLabel),
      (_FallbackAddress.bitcoin, bitcoinLabel),
      (_FallbackAddress.lightning, lightningLabel),
    ];
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: 8.w),
          Expanded(
            child: _QrFormatButton(
              label: options[i].$2,
              // Unified is the resting state, so a null selection is it.
              active: (selected ?? _FallbackAddress.unified) == options[i].$1,
              onTap: () => onSelect(options[i].$1),
            ),
          ),
        ],
      ],
    );
  }
}

class _QrFormatButton extends StatelessWidget {
  const _QrFormatButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            height: 40.h,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            decoration: BoxDecoration(
              color: active ? c.surfaceElevated : c.surface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(
                color: active ? c.border : c.borderSubtle,
                width: active ? 1.0 : 0.5,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? c.textPrimary : c.textSecondary,
                fontSize: 13.sp,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
