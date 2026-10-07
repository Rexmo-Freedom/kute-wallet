// lib/screens/receive/orchestra_deposit_poller.dart
//
// Orchestra deposit-address polling, lifted out of the bitcoin receive
// screen so the dollars receive screen can share it verbatim rather
// than grow a second, slightly different copy of the same subtle loop.
//
// An Orchestra deposit address — the standing accumulation address or a
// quoted one-off — spawns an `ord_…` order server-side only when a
// deposit actually arrives, so there is no id to poll by. The address
// history IS the discovery mechanism: each newly-seen order is recorded
// as a SwapOrder(provider: 'Orchestra'), and from there the shared tx UI
// and background sync's getStatus poller take over.
//
// The timer deliberately never self-cancels: a standing address is
// reusable and more deposits may follow. The owning screen cancels it.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDecimalString;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_history.dart';
import 'package:kute/services/orchestra_routes.dart';

/// Polls the recipient's Orchestra history for deposits to one address.
class OrchestraDepositPoller {
  OrchestraDepositPoller(this._ref);

  final WidgetRef _ref;
  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Starts (or restarts) the 10 s history poll for [display].
  ///
  /// [stillWanted] is asked on every tick and on every in-flight
  /// response: it must go false when the screen is gone or the address
  /// on screen has changed, so a late response can never replace a
  /// newly selected receive address.
  ///
  /// [onProgress] receives the LATEST mapped status for the address so
  /// the screen can advance wait → exchanging → success. Only the
  /// screen's local copy is updated by it: rewriting the STORED row
  /// terminal here would steal the pending→terminal transition
  /// background sync's getStatus poller keys its completion analytics
  /// on.
  void start(
    SwapOrder display, {
    required bool Function() stillWanted,
    required void Function(SwapOrder) onProgress,
  }) {
    cancel();
    // Orders spawned before this receive session (previous deposits to
    // the same reusable address) were recorded by earlier sessions or
    // background sync's sweep — the `known` id check below keeps them
    // from double-recording; the session-start stamp keeps a stale
    // terminal order from flipping the on-screen arrival state.
    final sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    // Ids seen NON-terminal during this polling session. They may
    // legitimately advance to success/failed on-screen later — without
    // this, the pre-session stamp check below would freeze the arrival
    // UI at the last in-flight status for orders older than the stamp.
    final liveThisSession = <String>{};
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final result =
            await OrchestraService.getHistory(display.withdrawalAddress);
        final orders = result.data;
        // Canceling a timer cannot cancel an HTTP request already in
        // flight. An old response must never replace a newly selected
        // receive address.
        if (orders == null ||
            !stillWanted() ||
            !timer.isActive ||
            !identical(_timer, timer)) {
          return;
        }
        final known = _ref.read(swapOrdersProvider).map((e) => e.id).toSet();
        for (final order in orders) {
          if (order.id.isEmpty) continue;
          // A reusable address may serve multiple quotes. A one-time
          // receive must not display another quote's deposit as its own.
          if (display.id.startsWith('q_') && order.quoteId != display.id) {
            continue;
          }
          if (!orchestraHistoryMatchesDeposit(order,
              sourceChain: display.networkFrom,
              sourceAsset: display.coinFrom,
              destinationAsset: display.coinTo,
              depositAddress: display.depositAddress,
              recipientSparkAddress: display.withdrawalAddress)) {
            continue;
          }
          // Shared Flashnet→exchange vocabulary (orchestra_routes.dart)
          // — background sync's accumulation sweep maps with the same
          // helper, so a row reads identically no matter which path
          // discovered it. Terminal gates below use the MAPPED status,
          // never `order.isTerminal`: that getter compares the raw
          // status case-SENSITIVELY and Flashnet casing varies, so
          // 'COMPLETED' would read as non-terminal there.
          final mappedStatus = orchestraExchangeStatus(order.status);
          final isTerminal = orchestraExchangeStatusIsTerminal(mappedStatus);
          // Flashnet amounts are in smallest units (micro-stable in,
          // sats out) — convert to the human-readable decimals every
          // other exchange row stores.
          // Chain-aware decimals: networkFrom carries the Orchestra
          // chain slug for catalog picks, so an 18-decimal source
          // token (BSC-pegged stables, ETH) scales correctly instead
          // of falling back to the ticker table.
          final depAmt = order.amountIn != null
              ? orchestraAmountToDecimalString(order.amountIn!, display.coinFrom,
                  chain: display.networkFrom)
              : '0';
          final wdAmt = order.amountOut != null
              // The landing side is whatever this flow settles in —
              // bitcoin or dollars — and the two do not share decimals.
              ? orchestraAmountToDecimalString(order.amountOut!, display.coinTo,
                  chain: 'spark')
              : '0';
          final createdMs =
              DateTime.tryParse(order.createdAt)?.millisecondsSinceEpoch ??
                  DateTime.now().millisecondsSinceEpoch;
          final exchange = display.copyWith(
            id: order.id,
            status: mappedStatus,
            depositAmount: depAmt,
            withdrawalAmount: wdAmt,
            timestamp: createdMs,
          );
          // The `known` guard only prevents double-RECORDING (and with
          // it double attribution) — mapping and the progress mirror
          // below still run for known ids every tick.
          // Terminal-at-discovery orders are recorded WITH their
          // mapped terminal status so background sync never polls
          // them as pending. First-insert attribution — the 'pending'
          // provider_events row, or the completed/failed fan-out for
          // terminal-discovered orders — is owned by the shared
          // reportDiscoveredOrchestraOrder rule: whichever discoverer
          // (this poller or background sync's sweep) inserts the row
          // first reports exactly once; the other skips the id here.
          if (!known.contains(order.id)) {
            _ref.read(swapOrdersProvider.notifier).addExchange(exchange);
            reportDiscoveredOrchestraOrder(exchange);
          }
          // Arrival progress: mirror the LATEST mapped status into the
          // screen each tick — including for already-recorded ids, so
          // this poller advances wait → exchanging → success instead of
          // freezing at first sight. Pre-session terminal orders stay
          // off the UI (a deposit from last week shouldn't flip this
          // session to "completed") unless we watched them run live
          // this session.
          if (!isTerminal) liveThisSession.add(order.id);
          if (!isTerminal ||
              createdMs >= sessionStartMs ||
              liveThisSession.contains(order.id)) {
            if (stillWanted()) onProgress(exchange);
          }
        }
      } catch (_) {}
    });
  }
}
