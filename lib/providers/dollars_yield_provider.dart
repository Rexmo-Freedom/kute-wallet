// lib/providers/dollars_yield_provider.dart
//
// Which received bitcoin payments are the Dollars yield (the daily reward
// on the Dollars balance, paid as bitcoin): the activity rows, the receipt
// and the export title them "Dollars yield" (founder, 25 November 2026).
// Recognition rules: lib/services/dollars_yield.dart.
//
// The lists never wait on the rewards service. They label from the payout
// rows already held (on disk per wallet, read at launch) and re-label when
// a fresher ledger lands; with the service down, or the wallet not
// eligible, nothing is labelled and every row builds exactly as before.
//
// This reads the payout ledger only to NAME payments already in the
// wallet. It shows no rate, no balance and no ledger, so it is not the
// Earn surface `usd.earn` gates (Earn stays hidden). No analytics.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/breez/sdk_instance.dart' show BreezSdkSpark;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/usd_rewards_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart'
    show usdRewardsApiProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/dollars_yield.dart';

/// The paid payout rows held per wallet id.
final dollarsYieldLedgerProvider = StateNotifierProvider<
    DollarsYieldLedgerNotifier,
    Map<String, List<RewardPayout>>>((ref) => DollarsYieldLedgerNotifier());

class DollarsYieldLedgerNotifier
    extends StateNotifier<Map<String, List<RewardPayout>>> {
  DollarsYieldLedgerNotifier({Map<String, List<RewardPayout>>? initial})
      : super(initial ?? DollarsYieldLedgerStore.readAll());

  /// Replaces [walletId]'s rows (only the paid ones are kept) and saves
  /// them for the next launch.
  void put(String walletId, List<RewardPayout> payouts) {
    final paid = payouts.where((p) => p.isPaid).toList(growable: false);
    state = {...state, walletId: paid};
    unawaited(DollarsYieldLedgerStore.write(walletId, paid));
  }
}

/// The ids of the payments that are Dollars yield, every wallet's ledger
/// matched against that same wallet's own payments.
final dollarsYieldPaymentIdsProvider = Provider<Set<String>>((ref) {
  final ledger = ref.watch(dollarsYieldLedgerProvider);
  if (ledger.isEmpty) return const <String>{};
  final cache = ref.watch(walletTransactionCacheProvider);
  final out = <String>{};
  ledger.forEach((walletId, payouts) {
    final spark = cache[walletId]?.sparkTransactions;
    if (spark == null || spark.isEmpty) return;
    out.addAll(matchDollarsYieldPayments(payouts, spark));
  });
  return out;
});

/// Whether the payment [id] is Dollars yield. Rows watch this, so one
/// fresher ledger re-labels only the rows it changes.
bool watchIsDollarsYield(WidgetRef ref, String id) => ref
    .watch(dollarsYieldPaymentIdsProvider.select((ids) => ids.contains(id)));

/// Keeps the spending wallet's payout ledger fresh: fetched once a session
/// when its activity is there, again when a received Spark payment lands
/// that nothing labels yet (a payout lands as one), and at most every few
/// minutes. Bootstrapped by Home; never touches the SDK before it exists.
final dollarsYieldSyncProvider = Provider<DollarsYieldSync>((ref) {
  final sync = DollarsYieldSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

class DollarsYieldSync {
  final Ref ref;
  late final ProviderSubscription<Map<String, Transaction>> _sub;
  final Map<String, DateTime> _lastFetch = {};
  final Map<String, Set<String>> _seenReceives = {};
  bool _inFlight = false;

  /// The least time between two ledger reads for one wallet.
  static const Duration minInterval = Duration(minutes: 3);

  /// A read with nothing new to look for, at most this often.
  static const Duration refreshInterval = Duration(hours: 6);

  DollarsYieldSync(this.ref) {
    _sub = ref.listen<Map<String, Transaction>>(
        walletTransactionCacheProvider, (_, next) => _maybeFetch(next),
        fireImmediately: true);
  }

  void dispose() => _sub.close();

  void _maybeFetch(Map<String, Transaction> cache) {
    if (_inFlight) return;
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) return;
    final spark = cache[walletId]?.sparkTransactions;
    if (spark == null || spark.isEmpty) return;
    final receives = {
      for (final t in spark)
        if (t.type == TransactionType.received &&
            t.sparkType == SparkTransactionType.spark)
          t.id
    };
    final seen = _seenReceives[walletId];
    final labelled = ref.read(dollarsYieldPaymentIdsProvider);
    final fresh = seen == null
        ? receives.isNotEmpty
        : receives.any((id) => !seen.contains(id) && !labelled.contains(id));
    final now = DateTime.now();
    final last = _lastFetch[walletId];
    final due = last == null ||
        (fresh && now.difference(last) >= minInterval) ||
        now.difference(last) >= refreshInterval;
    if (!due) return;
    unawaited(_fetch(walletId, receives));
  }

  Future<void> _fetch(String walletId, Set<String> receives) async {
    // Never start the SDK from here: only an SDK already up is asked.
    if (!ref.exists(breezSDKProvider)) return;
    // A reload (the spending wallet just changed) still carries the old
    // wallet's SDK as its previous value: only a settled one is asked.
    final sdkState = ref.read(breezSDKProvider);
    if (sdkState is! AsyncData<BreezSdkSpark>) return;
    final sdk = sdkState.value.instance;
    if (sdk == null) return;
    _inFlight = true;
    _lastFetch[walletId] = DateTime.now();
    _seenReceives[walletId] = receives;
    try {
      final info = await sdk.getInfo(request: const GetInfoRequest());
      final pubkey = info.identityPubkey;
      if (pubkey.isEmpty) return;
      PayoutHistoryResponse? page;
      try {
        page = await ref
            .read(usdRewardsApiProvider)
            .getPayoutHistory(pubkey, limit: 90);
      } on RewardsApiException catch (e) {
        // Not eligible: no payouts, so nothing is yield.
        if (!e.isNotEligible) rethrow;
        page = null;
      }
      // The spending wallet changed under the read: its rows are not
      // this wallet's.
      if (pickSpendingWallet(ref.read(settingsProvider))?.id != walletId) {
        return;
      }
      if (page != null && page.pubkey.isNotEmpty && page.pubkey != pubkey) {
        return;
      }
      ref
          .read(dollarsYieldLedgerProvider.notifier)
          .put(walletId, page?.payouts ?? const []);
    } catch (_) {
      // Service down or offline: keep the rows already held.
    } finally {
      _inFlight = false;
    }
  }
}
