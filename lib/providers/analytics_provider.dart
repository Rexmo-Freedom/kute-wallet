import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:kute/helpers/extension.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/datetime_range_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter_riverpod/flutter_riverpod.dart';

DateTimeSelect getCurrentMonthDateRange() {
  final DateTime now = DateTime.now();
  final startDate = now.subtract(const Duration(days: 30));
  return DateTimeSelect(
    start: startDate,
    end: now.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
  );
}

final dateTimeSelectProvider = StateNotifierProvider.autoDispose<DateTimeSelectProvider, DateTimeSelect>((ref) {
  return DateTimeSelectProvider(getCurrentMonthDateRange());
});

final selectedDaysDateArrayProvider = StateProvider.autoDispose<List<DateTime>>((ref) {
  final DateTimeSelect dateTimeSelect = ref.watch(dateTimeSelectProvider);
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(dateTimeSelect.start * 1000).toLocal();
  final DateTime currentDay = DateTime.now().toLocal();
  final DateTime end = DateTime.fromMillisecondsSinceEpoch(dateTimeSelect.end * 1000).toLocal();

  final effectiveEnd = currentDay.isAfter(end) ? currentDay : end;

  final List<DateTime> selectedDays = [];
  for (int i = 0; i <= effectiveEnd.difference(start).inDays; i++) {
    selectedDays.add(start.add(Duration(days: i)));
  }
  return selectedDays;
});

DateTime normalizeDate(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

/// The viewed wallet's bitcoin balance changes, each at the moment it
/// happened: (when, net sats), oldest first, with the live balance they
/// end on and the balance before the first of them. Shared by the
/// day-keyed series below and the Balance chart's steps, so both walk
/// the same transactions with the same rules.
({int current, int opening, List<(DateTime, int)> events})
    _bitcoinBalanceEvents(Ref ref, {bool log = false}) {
  // Follow the VIEWED wallet, not the active one. On Home this
  // matches the active wallet (no scoping override), so home
  // analytics stay correct. On the per-wallet detail screen
  // (`wallet_detail_screen.dart`) `viewedWalletIdProvider` is set
  // to that wallet's id and we route the analytics chain to that
  // wallet's txs + balance — otherwise the spending wallet's
  // history bleeds onto every cold-wallet detail page.
  final transactionData = ref.watch(viewedWalletTransactionsProvider);
  final settings = ref.watch(settingsProvider);
  final liveBalance = ref.watch(viewedWalletBalanceProvider);

  // Determine the wallet's traits using the viewed wallet id (with
  // active-wallet fallback for the home / null-viewed case).
  final viewedId = ref.watch(viewedWalletIdProvider);
  final activeWallet = settings.activeWallet;
  final viewedWallet = (viewedId == null || viewedId == activeWallet?.id)
      ? activeWallet
      : settings.wallets.cast<WalletConfig?>().firstWhere(
            (w) => w?.id == viewedId,
            orElse: () => activeWallet,
          );
  final isSparkEnabled = viewedWallet?.sparkEnabled ?? false;
  final isExternalAddress = viewedWallet?.isExternalAddress ?? false;

  // Live current balance is the anchor: the SDK's running balance is
  // authoritative, while listPayments may only return a recent slice.
  // Walking transactions forward from `currentBalance - sumOfNetAmounts`
  // keeps today's value exact and yields correct history regardless of
  // how far back the local payment list reaches.
  final int currentBalance = isSparkEnabled
      ? liveBalance.sparkBitcoinbalance
      : liveBalance.onChainBtcBalance;

  final List<BaseTransaction> allTransactions = [
    ...transactionData.bitcoinTransactions,
    if (isSparkEnabled) ...transactionData.sparkTransactions,
    if (isExternalAddress) ...transactionData.mempoolTransactions,
  ];

  // Build a list of (date, net) events, dropping unconfirmed / failed
  // entries and any with a missing (epoch-0) timestamp — those would
  // otherwise plant a 1970 anchor and skew everything downstream.
  final List<(DateTime, int)> events = [];
  for (final tx in allTransactions) {
    int net = 0;
    DateTime? txDate;

    if (tx is BitcoinTransaction) {
      // Cache-built BitcoinTransactions have no live `btcDetails` —
      // fall back to the primitive timestamp on the BaseTransaction
      // and accept that the chain-position confirmation filter is
      // skipped for cached entries (the next sync will replace
      // them with live ones, at which point this filter applies).
      // Unconfirmed on-chain transactions are already inside the live
      // balance this chart anchors on (BDK's total includes pending),
      // so they must appear as an event too, dated today. Skipping
      // them shifted the entire history by the pending amount and drew
      // a flat line after a fresh deposit.
      final details = tx.btcDetails;
      if (details != null) {
        final cp = details.chainPosition;
        if (cp is ConfirmedChainPosition) {
          final t = cp.confirmationBlockTime.confirmationTime;
          if (t == 0) continue;
          txDate = DateTime.fromMillisecondsSinceEpoch(t * 1000);
        } else {
          txDate = DateTime.now();
        }
      } else {
        txDate = tx.isConfirmed ? tx.timestamp : DateTime.now();
      }
      net = tx.receivedSats - tx.sentSats;
    } else if (tx is SparkTransaction) {
      // Cached shells (no live SDK payload) skip the analytics
      // contribution — they don't carry fees or settlement
      // timestamps. Live entries get the precise SDK timestamp;
      // the next sync replaces shells.
      final live = tx.details;
      if (live != null) {
        if (live.status != breez.PaymentStatus.completed) continue;
        final ts = live.timestamp.toInt();
        if (ts == 0) continue;
        txDate = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final amt = live.amount.toInt();
        if (live.paymentType == breez.PaymentType.receive) {
          net = amt;
        } else {
          net = -(amt + live.fees.toInt());
        }
      } else {
        if (tx.isPending) continue;
        txDate = tx.timestamp;
        final amt = tx.amountSats;
        net = tx.type == TransactionType.received ? amt : -amt;
      }
    } else if (tx is MempoolAddressTransaction) {
      // Same as above: the tracked-address balance counts mempool
      // transactions, so the chart must too.
      txDate = tx.isConfirmed ? tx.timestamp : DateTime.now();
      net = tx.details.balanceChange;
    }

    if (txDate != null) {
      events.add((txDate, net));
    }
  }

  // Sort ascending by the moment each happened, which also keeps every
  // day's events together and in order for the day-keyed series.
  events.sort((a, b) => a.$1.compareTo(b.$1));

  final totalChange = events.fold<int>(0, (a, e) => a + e.$2);
  if (log && kDebugMode) {
    // What the balance chart is built from. A flat line means this list
    // is empty or every event fell on one day.
    final spark = allTransactions.whereType<SparkTransaction>();
    final id = viewedWallet?.id ?? '';
    debugPrint('[balance-chart] wallet=${id.length > 6 ? id.substring(0, 6) : id} '
        'txs=${allTransactions.length} spark=${spark.length} '
        'sparkLive=${spark.where((t) => t.details != null).length} '
        'events=${events.length} '
        'span=${events.isEmpty ? '-' : '${events.first.$1.toIso8601String().substring(0, 10)}..${events.last.$1.toIso8601String().substring(0, 10)}'} '
        'current=$currentBalance netChange=$totalChange');
  }
  return (
    current: currentBalance,
    opening: currentBalance - totalChange,
    events: events,
  );
}

final bitcoinBalanceOverPeriod = Provider.autoDispose<Map<DateTime, num>>((ref) {
  final walk = _bitcoinBalanceEvents(ref, log: true);
  final currentBalance = walk.current;
  final events = walk.events;
  int balance = walk.opening;

  // The final assignment to a day is its end-of-day balance.
  final Map<DateTime, num> balancePerDay = {};
  for (final e in events) {
    balance += e.$2;
    balancePerDay[normalizeDate(e.$1)] = balance;
  }

  // Ensure today is anchored on the live current balance even when
  // there are no transactions in the local list (e.g. fresh sync, or
  // listPayments returned nothing). Without this the chart would
  // regress to 0 for today and read as broken.
  if (events.isEmpty || balance != currentBalance) {
    balancePerDay[normalizeDate(DateTime.now())] = currentBalance;
  }

  return balancePerDay;
});

/// The viewed wallet's bitcoin balance in sats as the moments it changed,
/// for the Balance chart: the same walk as [bitcoinBalanceOverPeriod],
/// kept at the time of each change instead of folded into days, so a
/// deposit an hour ago is drawn an hour ago.
final bitcoinBalanceStepsProvider =
    Provider.autoDispose<BalanceHistory>((ref) {
  final walk = _bitcoinBalanceEvents(ref);
  var balance = walk.opening;
  final changes = <(DateTime, double)>[];
  for (final e in walk.events) {
    balance += e.$2;
    changes.add((e.$1, (balance < 0 ? 0 : balance).toDouble()));
  }
  return BalanceHistory(
    opening: (walk.opening < 0 ? 0 : walk.opening).toDouble(),
    changes: changes,
    current: walk.current.toDouble(),
  );
});

final bitcoinBalanceOverPeriodByDayProvider = Provider.autoDispose<Map<DateTime, num>>((ref) {
  final balanceOverPeriod = ref.watch(bitcoinBalanceOverPeriod);
  final selectedDays = ref.watch(selectedDaysDateArrayProvider);

  final Map<DateTime, num> balancePerDay = {};
  num lastKnownBalance = 0;

  if (balanceOverPeriod.isEmpty) {
    for (DateTime day in selectedDays) {
      balancePerDay[normalizeDate(day)] = 0;
    }
    return balancePerDay;
  }

  DateTime firstDay = balanceOverPeriod.keys.first;

  // Fill in gaps in history
  for (var entry in balanceOverPeriod.entries) {
    DateTime balanceDate = entry.key;
    num balanceValue = entry.value;

    while (firstDay.isBefore(balanceDate)) {
      balancePerDay[normalizeDate(firstDay)] = lastKnownBalance;
      firstDay = firstDay.add(const Duration(days: 1));
    }

    lastKnownBalance = balanceValue;
    balancePerDay[normalizeDate(balanceDate)] = lastKnownBalance;
  }

  // Fill up to today
  DateTime today = normalizeDate(DateTime.now());
  while (firstDay.isBefore(today) || firstDay.isAtSameMomentAs(today)) {
    balancePerDay[normalizeDate(firstDay)] = lastKnownBalance;
    firstDay = firstDay.add(const Duration(days: 1));
  }

  // Filter for the selected range
  final Map<DateTime, num> selectedBalancePerDay = {};
  num lastBalanceForSelectedRange = 0;

  if (selectedDays.isNotEmpty) {
    final dayBeforeStart = normalizeDate(selectedDays.first.subtract(const Duration(days: 1)));
    lastBalanceForSelectedRange = balancePerDay[dayBeforeStart] ?? 0;
  }

  for (DateTime day in selectedDays) {
    final normalizedDay = normalizeDate(day);
    if (balancePerDay.containsKey(normalizedDay)) {
      selectedBalancePerDay[normalizedDay] = balancePerDay[normalizedDay]!;
      lastBalanceForSelectedRange = balancePerDay[normalizedDay]!;
    } else {
      selectedBalancePerDay[normalizedDay] = lastBalanceForSelectedRange;
    }
  }

  return selectedBalancePerDay;
});

final bitcoinBalanceInFormatByDayProvider = Provider.autoDispose<Map<DateTime, double>>((ref) {
  final balanceByDay = ref.watch(bitcoinBalanceOverPeriodByDayProvider);
  final btcFormat = ref.watch(settingsProvider).btcFormat;

  final Map<DateTime, double> balanceInFormatByDay = {};

  for (DateTime day in balanceByDay.keys) {
    // 1. Get the balance in Sats (ensure it is int)
    final int sats = balanceByDay[day]!.toInt();

    // 2. Use the new extension method directly
    // This replaces 'btcInDenominationNum(sats, btcFormat)'
    balanceInFormatByDay[day] = sats.toDoubleValue(btcFormat);
  }

  return Map.fromEntries(
      balanceInFormatByDay.entries.toList()..sort((e1, e2) => e1.key.compareTo(e2.key))
  );
});

// ─────────────────────────────────────────────────────────────────────────────
// MONTHLY INSIGHTS
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// CASHFLOW BY PERIOD
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// FEE ANALYTICS
// ─────────────────────────────────────────────────────────────────────────────
