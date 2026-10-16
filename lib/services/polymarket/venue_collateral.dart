// lib/services/polymarket/venue_collateral.dart
//
// A buy goes to the order book only once the book counts the money for it.
//
// The order book does not read the deposit wallet on chain when an order
// arrives: it keeps its own count of the wallet's pUSD and allowances and
// re-reads them only when asked (`/balance-allowance/update`). Money that
// just arrived is first USDC.e, which the book does not count at all, and
// once converted the book still counts the old pUSD until it re-reads, and
// a re-read made the moment the conversion is mined can still see the
// block before it. The first prediction after money arrived was refused
// for balance; the one refresh-and-retry inside the placement signed again
// at once, against the same stale count, and was refused again. Tapping
// again a minute later worked, because by then the count had caught up.
//
// So before any buy (the slip's direct order, a resting limit, the queued
// bet the autofire places once its funding lands):
//  1. read what the book counts and what the wallet holds, together; when
//     the book already counts the buy (balance and every allowance it
//     reports for the exchange) nothing else happens;
//  2. otherwise convert held USDC.e to pUSD (waiting for it to be mined),
//     set a pinned exchange allowance the book reports missing,
//  3. ask the book to re-read and poll it, briefly, until it counts the
//     buy; then the order is signed and posted.
// A book that cannot be read, or still does not count the buy, leaves
// placement pending. It never authorizes a post; a funded order waits
// under its existing approval and checks again, bounded. Nothing here
// moves money into Predictions: the only conversion is the wallet's own
// USDC.e, so a retry can never fund twice.

import 'dart:async';

import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrantException;
import 'package:kute/services/polymarket/market_protocol.dart';
import 'package:kute/services/polymarket/order_refusal.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart';

/// What the order book counts for the deposit wallet's collateral
/// (`GET /balance-allowance?asset_type=COLLATERAL&signature_type=3`), in
/// micro-pUSD.
class PolyVenueCount {
  const PolyVenueCount({required this.balance, this.allowances = const {}});

  final BigInt balance;

  /// pUSD allowances the book reported, by lower-case spender.
  final Map<String, BigInt> allowances;

  /// Null when [json] is not a count (no integer balance).
  static PolyVenueCount? fromClob(Map<String, dynamic>? json) {
    final balance = _integer(json?['balance']);
    if (balance == null) return null;
    final allowances = <String, BigInt>{};
    final raw = json?['allowances'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = _integer(entry.value);
        if (value != null) {
          allowances[entry.key.toString().toLowerCase()] = value;
        }
      }
    }
    return PolyVenueCount(balance: balance, allowances: allowances);
  }

  static BigInt? _integer(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^\d+$').hasMatch(text) ? BigInt.parse(text) : null;
  }

  /// The [spenders] the book reports an allowance under [costMicros] for.
  /// A spender it does not report is not counted as missing.
  List<String> shortSpenders(List<String> spenders, BigInt costMicros) => [
        for (final spender in spenders)
          if ((allowances[spender.toLowerCase()] ?? costMicros) < costMicros)
            spender.toLowerCase(),
      ];

  /// Whether the book counts a buy costing [costMicros] against
  /// [spenders].
  bool covers(BigInt costMicros, List<String> spenders) =>
      balance >= costMicros && shortSpenders(spenders, costMicros).isEmpty;
}

/// The exchange contracts that pull pUSD for a buy of [tokenId]: the V2
/// ExchangeV3 for a Protocol V2 position, else the CTF exchange, and for a
/// neg-risk market the Neg Risk Exchange and its adapter (the book checks
/// both).
List<String> polyBuySpenders(String tokenId, {required bool negRisk}) {
  final venue = PolyOrderVenue.forToken(tokenId, negRisk: negRisk);
  if (venue.isV2 || !negRisk) return [venue.exchange.toLowerCase()];
  return [
    PolymarketConstants.negRiskExchangeAddress.toLowerCase(),
    PolymarketConstants.legacyNegRiskAdapterAddress.toLowerCase(),
  ];
}

/// How the book's count ended before the order: a closed word for the
/// placement timeline (`venue_count`).
enum PolyVenueReadiness {
  /// The book already counted the buy; nothing ran.
  counted,

  /// The book counts it now, after a conversion, an approval or a re-read.
  refreshed,

  /// The wallet holds the money but the book did not count it within the
  /// wait. Nothing may be signed yet.
  notCounted,

  /// The wallet does not hold enough pUSD for the buy even after the
  /// conversion. Nothing may be signed; a funded market order can be
  /// resized only after its own complete delivery is proved.
  short,

  /// The book's count could not be read. Placement remains pending.
  unread,
}

/// The account operations [polyReadyVenueCollateral] runs, injected so the
/// steps can be tested without a wallet.
class PolyVenueCollateralOps {
  const PolyVenueCollateralOps({
    required this.readVenue,
    required this.readSplit,
    required this.wrap,
    required this.refreshVenue,
    required this.approveSpender,
    this.ensureCurrent,
    this.onStep,
    this.sleep = _sleep,
  });

  /// The book's count; null when it cannot be read.
  final Future<PolyVenueCount?> Function() readVenue;

  /// The wallet's pUSD and USDC.e on chain; [fresh] skips a prefetched
  /// read. Every final placement check requests it fresh. Null is unknown.
  final Future<({BigInt pusd, BigInt usdce})?> Function({required bool fresh})
      readSplit;

  /// Converts the USDC.e the wallet holds to pUSD and waits until it is
  /// mined; the micro-USDC.e converted.
  final Future<BigInt> Function() wrap;

  /// Asks the book to re-read the wallet's collateral.
  final Future<void> Function() refreshVenue;

  /// Sets the pinned [spender]'s allowance when it is missing on chain;
  /// whether an approval was sent.
  final Future<bool> Function(String spender) approveSpender;

  /// Throws when the account or the order's approval changed.
  final void Function()? ensureCurrent;

  /// Progress for the slip ('approving').
  final void Function(String step)? onStep;

  final Future<void> Function(Duration) sleep;

  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);
}

/// Waits until the order book counts a buy costing [costMicros] against
/// [spenders], doing what is missing first (see the file header).
/// [afterRefusal] is the venue's balance refusal's one refresh: the
/// wallet is re-read on chain, any USDC.e it holds is converted, and the
/// count is re-read even if the book already reported enough.
///
/// Throws [PolymarketFundsConverting] when the conversion does not finish
/// within [PolymarketPlacementWaits.conversion] and
/// [PolymarketSetupIncomplete] when a missing allowance cannot be set; a
/// changed account or approval ([PolyVenueCollateralOps.ensureCurrent])
/// stops it as itself. Anything else is left to the order's refusal path.
Future<PolyVenueReadiness> polyReadyVenueCollateral({
  required BigInt costMicros,
  required List<String> spenders,
  required PolyVenueCollateralOps ops,
  bool afterRefusal = false,
}) async {
  if (costMicros <= BigInt.zero) return PolyVenueReadiness.counted;
  ops.ensureCurrent?.call();
  final reads = await Future.wait<Object?>([
    _safe(ops.readVenue),
    _safe(() => ops.readSplit(fresh: true)),
  ]);
  ops.ensureCurrent?.call();
  final venue = reads[0] as PolyVenueCount?;
  var split = reads[1] as ({BigInt pusd, BigInt usdce})?;
  if (!afterRefusal &&
      venue != null &&
      venue.covers(costMicros, spenders) &&
      split != null &&
      split.pusd >= costMicros) {
    return PolyVenueReadiness.counted;
  }
  var pusd = split?.pusd;
  final usdce = split?.usdce ?? BigInt.zero;
  final convert = split != null &&
      (afterRefusal
          ? usdce > BigInt.zero
          : polyShouldWrapBeforeBuy(
              pusd: split.pusd, usdce: usdce, costMicros: costMicros));
  if (convert) {
    ops.onStep?.call('approving');
    try {
      await ops.wrap().timeout(PolymarketPlacementWaits.conversion);
    } on TimeoutException {
      // The conversion keeps going; nothing has been signed.
      ops.ensureCurrent?.call();
      throw const PolymarketFundsConverting();
    } catch (e) {
      ops.ensureCurrent?.call();
      if (e is PolymarketFundsConverting) rethrow;
      // A failed conversion leaves it to the refusal path.
    }
    ops.ensureCurrent?.call();
    // A concurrent caller may have joined a conversion sized before a
    // second deposit arrived. Its reported wrapped amount is not proof of
    // the current aggregate pUSD balance.
    split = await _safe(() => ops.readSplit(fresh: true));
    ops.ensureCurrent?.call();
    pusd = split?.pusd;
  }

  // An exchange the book reports no allowance for: set it (pinned
  // contracts only, bounded), then have the book re-read it.
  final missing = venue?.shortSpenders(spenders, costMicros) ?? const [];
  for (final spender in missing) {
    if (!polymarketPinnedSpenders.containsKey(spender)) continue;
    ops.onStep?.call('approving');
    try {
      await ops.approveSpender(spender).timeout(PolymarketPlacementWaits.setup);
    } on TimeoutException {
      ops.ensureCurrent?.call();
      throw const PolymarketSetupIncomplete(timedOut: true);
    } catch (e) {
      ops.ensureCurrent?.call();
      // A changed account or approval still stops here as itself.
      if (e is AuthGrantException || e is StateError) rethrow;
      throw PolymarketSetupIncomplete(cause: e);
    }
    ops.ensureCurrent?.call();
  }

  // The wallet does not hold the buy in pUSD: no cached venue count can
  // certify it. Report the short/unread result without posting an order.
  final holds = pusd != null && pusd >= costMicros;
  final counted = await polyAwaitVenueCount(
    costMicros: costMicros,
    spenders: spenders,
    ops: ops,
    wait: holds ? PolymarketPlacementWaits.venueCount : Duration.zero,
  );
  if (counted == null || pusd == null) return PolyVenueReadiness.unread;
  if (counted && holds) return PolyVenueReadiness.refreshed;
  return holds ? PolyVenueReadiness.notCounted : PolyVenueReadiness.short;
}

/// A pending read never authorizes signing. Kept separate from the
/// preparation operation so callers can show its fixed readiness result.
void polyRequireConfirmedCollateral(PolyVenueReadiness readiness) {
  if (readiness != PolyVenueReadiness.counted &&
      readiness != PolyVenueReadiness.refreshed) {
    throw const PolymarketCollateralPending();
  }
}

/// Asks the book to re-read the wallet's collateral, then reads its count
/// until it covers [costMicros] against [spenders] or [wait] runs out,
/// asking again before every read. True when it counts it, false when it
/// still does not, null when it could never be read. A failed re-read
/// request (the book answers 404 for a wallet it has not indexed yet) is
/// not an error: the read after it decides.
Future<bool?> polyAwaitVenueCount({
  required BigInt costMicros,
  required List<String> spenders,
  required PolyVenueCollateralOps ops,
  Duration? wait,
}) async {
  final budget = wait ?? PolymarketPlacementWaits.venueCount;
  final interval = PolymarketPlacementWaits.venueCountPoll;
  var waited = Duration.zero;
  var read = false;
  while (true) {
    await _safe(ops.refreshVenue);
    ops.ensureCurrent?.call();
    final count = await _safe(ops.readVenue);
    ops.ensureCurrent?.call();
    if (count != null) {
      read = true;
      if (count.covers(costMicros, spenders)) return true;
    } else if (!read) {
      // This bounded read returns unknown; the caller keeps placement pending.
      return null;
    }
    if (waited >= budget) break;
    await ops.sleep(interval);
    waited += interval;
  }
  return read ? false : null;
}

/// A read or re-read request that failed is no answer, never an error.
Future<T?> _safe<T>(Future<T?> Function() read) async {
  try {
    return await read();
  } catch (_) {
    return null;
  }
}
