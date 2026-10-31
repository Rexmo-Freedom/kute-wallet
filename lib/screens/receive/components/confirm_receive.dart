import 'package:kute/screens/shared/app_bottom_sheet.dart' show showKuteModalSheet;
import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shimmer/shimmer.dart';

import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/address_receive_provider.dart';
import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show selectedNetworkTypeProvider;
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usdc_balance_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/receive/receive_sheet.dart'
    show showOtherCoinsReceiveSheet;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/jade_device_picker.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/ledger/ledger_failure_copy.dart';
import 'package:kute/screens/shared/ledger_device_picker.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/orchestra/reusable_deposit_address.dart'
    show standingDestinationsProvider;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/jade_service.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/sound_service.dart';
import 'package:kute/services/success_feedback.dart' show moneyFailureFeedback;
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
// default state on Spark/hot wallets. `null` is reserved for the USDC
// pool's default caption, where the toggle is bypassed entirely.
enum _FallbackAddress { bitcoin, unified, lightning, usdc }

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

  /// The wallet's own Bitcoin address whose minimum was last recorded,
  /// so `receive_address_generated` fires once per address shown.
  String? _onChainMinimumTrackedFor;

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
        ref
            .read(settingsProvider)
            .wallets
            .where((w) => w.id == _selectedWalletId)
            .firstOrNull;
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
      props: {
        'pool': selected is UsdcSpendingAccount ? 'usdc' : 'btc',
        'presentation': 'sheet',
      },
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

  /// Rail (`lightning` | `bitcoin`) for a BTC balance rise on the picked
  /// wallet. An on-chain leg rise is always `bitcoin`. A Spark leg rise
  /// depends on what the sender could have paid: the plain Bitcoin address
  /// on a Spark wallet is the SDK deposit address, claimed into the Spark
  /// balance (`bitcoin`); the invoice / unified BIP21 QR is paid over
  /// `lightning` in practice.
  String _railForBtcDelta(
      {required int sparkDelta, required int onChainDelta}) {
    if (onChainDelta > 0 && sparkDelta <= 0) return 'bitcoin';
    if (_expandedFallback == _FallbackAddress.bitcoin) return 'bitcoin';
    return 'lightning';
  }

  String? _receiveWalletKind;
  bool _payloadExported = false;

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
    _balanceWatchTimer?.cancel();
    super.dispose();
  }

  // ─── Stepper helpers ───────────────────────────────────────────

  void _onLeadingTap() {
    // Single-page flow now: close button always closes the sheet.
    _closeAndReset();
  }

  /// Closes the receive sheet (the route a deep link opened is the same
  /// sheet, so popping it is right either way).
  void _closeAndReset() {
    try {
      ref.read(inputAmountProvider.notifier).state = '0.0';
    } catch (_) {}
    Navigator.of(context).maybePop();
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
      // Opens as a sheet over the current screen (receive_sheet.dart):
      // the close button and the account the money lands in sit in the
      // sheet's header row, where the app bar had them.
      child: KeyboardDismissOnTap(
        child: ReceiveSheetFrame(
          leading: KuteCloseButton(onPressed: _onLeadingTap),
          // The destination stays fixed for the entire receive flow.
          title: AccountSwitcherPill(
            pickerTitle: context.l10n.receiveInto,
            account: _selectedAccount,
            readOnly: true,
          ),
          child: _buildStepperBody(context, c),
        ),
      ),
    );
  }

  /// The sheet's body. The sheet container already keeps it above the
  /// home indicator and the keyboard.
  Widget _buildStepperBody(BuildContext context, AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Column(
        children: [
          // A single receive surface for the account shown in the header.
          // No title over it: the sheet already says "receive", and the
          // header row (close + "Receive into") is the top, so the code
          // gets the room.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 12.h),
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

    if (_selectedPool == _ReceivePool.usdc) {
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

    final bool isUsdcFallback = _expandedFallback == _FallbackAddress.usdc;
    // Request amount is offered on the native rails of a hot wallet.
    // In the unified and Lightning formats the request is a Lightning
    // invoice for the amount; in the Bitcoin-only format it is a BIP21
    // amount on the on-chain address, so the QR always matches the
    // request. Cold wallets (hardware / watch-only / software bitcoin
    // / tracked) show just the QR and the address, as before.
    final bool showRequestAmount = canUseLightning &&
        !isUsdcFallback &&
        _selectedPool != _ReceivePool.usdc;

    // Imported and hardware wallets read their address from BDK, and
    // the first open of an imported wallet holds the native wallet slot
    // for a full scan. Say why the plate is still shimmering.
    final bool showSyncingCaption = activeWallet != null &&
        activeWallet.usesBdk &&
        !canUseLightning &&
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
    final bool showFormatPicker = canUseLightning &&
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
                if (_selectedPool == _ReceivePool.usdc &&
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
                      displayOnChainAddress.isNotEmpty) ...[
                    _buildMinimalAddress(
                      icon: Icons.link_rounded,
                      iconColor: c.accent,
                      address: displayOnChainAddress,
                      copyText: displayOnChainAddress,
                    ),
                    // The Spark wallet's Bitcoin address has no route
                    // minimum (Bitcoin itself sets none); only that it
                    // was shown is recorded.
                    if (activeWallet != null && activeWallet.isSparkWallet)
                      Builder(builder: (_) {
                        _trackOnChainAddressShown(baseOnChainAddress);
                        return const SizedBox.shrink();
                      }),
                  ],
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

                // 2a. Share. It lives right under the address (which
                // copies on tap) and hands out the exact payload the QR
                // encodes (unified BIP21, invoice, address or swap
                // deposit address), with request amount as a quiet
                // text action under it. Hidden while the plate shimmers
                // or shows an error: nothing verified to share yet.
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
                // One quiet line: the words, a few coin marks and a count.
                // A tap opens the Dollars receive's sheet over this one.
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
                    displayOnChainAddress.isNotEmpty)
                  _buildMinimalAddress(
                    icon: Icons.link_rounded,
                    iconColor: c.accent,
                    address: displayOnChainAddress,
                    copyText: displayOnChainAddress,
                  ),

                // 3. Hardware wallet verify
                if ((_expandedFallback == _FallbackAddress.bitcoin ||
                        !canUseLightning) &&
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
              ],
            ),
          ),

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

  /// Share under the address (copy lives on the address line), acting
  /// on [payload], the exact string the QR encodes. With
  /// [showRequestAmount] a quiet text action under it opens the
  /// amount sheet; once a request is live it shows the requested amount
  /// and a tap clears it.
  Widget _buildActionPills({
    required String payload,
    required bool showRequestAmount,
  }) {
    final requested = _requestedSats;
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReceiveActionPills(
          onShare: () => _sharePayload(payload),
        ),
        if (showRequestAmount) ...[
          SizedBox(height: 4.h),
          requested == null
              ? AppTextButton(
                  key: const ValueKey('receive-request-amount'),
                  onPressed: _isInvoiceLoading ? null : _requestAmount,
                  text: context.l10n.receiveRequestAmount,
                  icon: Icons.add_rounded,
                )
              : AppTextButton(
                  key: const ValueKey('receive-request-amount'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(_clearAmountRequest);
                  },
                  text: '₿${requested.toFormattedString(btcFormat)}',
                  icon: Icons.close_rounded,
                ),
        ],
      ],
    );
  }

  /// Hands the QR payload to the OS share sheet. Text only: every
  /// wallet and messenger can take the string, and the payload is what
  /// a scanner of the QR would read. No address or invoice contents
  /// reach analytics, only the payload kind.
  Future<void> _sharePayload(String payload) async {
    if (!mounted || payload.isEmpty) return;
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
  /// by the address row and its copy icon.
  void _copyPayload(String payload) {
    if (!mounted || payload.isEmpty) return;
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

  /// The coins the Bitcoin receive also takes from other networks, folded
  /// one per coin: exactly the set its "other coins" sheet offers (a
  /// reusable standing address into the Investments dollar balance where
  /// that route may serve the coin, else a one-time address into
  /// `spark:BTC` while the policy allows them). Empty off the spending
  /// wallet, on the USDC pool, and for accounts that may not be offered
  /// swaps.
  List<CoinAssetGroup> _alsoAcceptedCoins() {
    // Kick the live Flashnet route-catalog fetch (and rebuild when it
    // lands) so the offering matches today's routes.
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final offersOn = ref.watch(swapOffersEnabledProvider);
    final destinations = ref.watch(standingDestinationsProvider).valueOrNull;
    if (_selectedPool == _ReceivePool.usdc) return const [];
    if (!_isPickedWalletSparkSpending()) return const [];
    // `swapOffersEnabledProvider` answers whether an account may be
    // offered swap affordances IT would have to sign for, which is why
    // a cold account is refused them.
    if (!offersOn) return const [];
    return coinGroupsOfferedUnderPolicy(
      receiveCoinGroups(catalog, context.l10n,
          destinationAsset: 'BTC', standingDestinations: destinations),
      otherLegAsset: 'BTC',
      reusableLegAsset: kOrchestraUsdAssetCode,
      depositAddress: true,
    ).groups;
  }

  /// The line under the format buttons: what else the Bitcoin receive
  /// takes. A tap opens the coin sheet over this one (closing it comes
  /// back here as it was); a picked coin shows the reusable Dollars
  /// address (landing in Investments, as its note says) or, where that
  /// cannot serve it, asks its amount and shows a one-time address that
  /// delivers bitcoin. Null when there is nothing to offer, so the line
  /// is gone.
  Widget? _buildAlsoAcceptsSlot(AppColorsExtension c) {
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
        unawaited(showOtherCoinsReceiveSheet(context));
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
    return ReceiveAddressLine(
      address: address,
      compact: compact,
      onCopy: () => _copyPayload(copyText),
      onEdit: showEdit && editUsername != null
          ? () => _showEditUsernameModal(editUsername)
          : null,
    );
  }

  /// Records the Spark wallet's Bitcoin address as shown, once per
  /// address. No minimum: the network sets none.
  void _trackOnChainAddressShown(String address) {
    if (address.isEmpty || _onChainMinimumTrackedFor == address) return;
    _onChainMinimumTrackedFor = address;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.track('receive_address_generated', params: {
        'asset': 'btc',
        'network': 'bitcoin',
        'provider': 'breez',
        'destination': 'spark_btc',
        'address_kind': 'static_deposit',
      });
    });
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
      // The invoice the person asked for could not be made.
      unawaited(moneyFailureFeedback());
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

  /// True when the wallet picked on Step 0 is the Spark spending
  /// wallet — the only wallet the Dollars receive's addresses pay (its
  /// spending account's dollar balance). Same predicate as
  /// `_pickSpending` in breez_config_provider.dart.
  bool _isPickedWalletSparkSpending() {
    final settings = ref.read(settingsProvider);
    final spending = settings.wallets.where((w) => w.isSparkWallet).firstOrNull;
    return spending != null && spending.id == _pickedReceiveWalletId;
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
    showKuteModalSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditUsernameModalSheet(currentUsername: currentUsername),
    );
  }

  // ─── Hardware verify (Ledger / Jade) ──────────────────────────

  /// The same result sheet every money moment ends on, with the address
  /// the device confirmed in full as its context line. Done only closes
  /// the sheet, so the user is back on the share step with the verified
  /// address still on screen.
  void _showAddressVerified({
    required String message,
    required String device,
    required String address,
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
        contextLine: address.isEmpty ? null : address,
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
            address: displayAddress,
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
            address: displayAddress,
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
