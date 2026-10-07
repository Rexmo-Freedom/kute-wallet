import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/standing_deposit_refund_action.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_guard.dart';

/// A status such as "unfulfilled" alone cannot authorize a refund. Join this
/// exact swap to the authenticated wallet's provider deposit before offering it.
///
/// This is the one way back for money held on a standing deposit address:
/// an order row joins by its order id, and a stuck-deposit row (a deposit
/// that never became an order) by its deposit id. Either way the refund
/// itself is [StandingDepositRefundAction], with its refund-address check,
/// in-flight guard, journal and wallet-scope checks.
class OrchestraSwapRefundAction extends ConsumerStatefulWidget {
  const OrchestraSwapRefundAction({super.key, required this.order});
  final SwapOrder order;
  @override
  ConsumerState<OrchestraSwapRefundAction> createState() =>
      _OrchestraSwapRefundActionState();
}

class _OrchestraSwapRefundActionState
    extends ConsumerState<OrchestraSwapRefundAction> {
  StandingDepositRecord? _record;
  Map<String, dynamic>? _deposit;
  Timer? _timer;
  bool _loading = false;
  late final String? _wallet = widget.order.walletId;
  late final _scope =
      _wallet == null ? null : StandingDepositStore.capture(_wallet);
  bool get _current =>
      mounted &&
      _scope != null &&
      StandingDepositStore.current(_scope) &&
      ref.read(settingsProvider).activeWalletId == _wallet;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer =
        Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_current || !widget.order.isOrchestra) return;
    _loading = true;
    try {
      final order = widget.order;
      final records = await StandingDepositStore.records(_wallet!);
      for (final record in records) {
        if (!_current) return;
        if (!sameSparkAddress(record.recipient, order.withdrawalAddress) ||
            record.asset != order.coinTo) {
          continue;
        }
        final deposits =
            await StandingDepositStore.deposits(record, () => _current);
        for (final deposit in deposits) {
          // Order IDs are authoritative links; never infer a refund from a
          // shared USDC asset or the venue label (Investing/Predictions).
          // A stuck-deposit row has no order: its provider deposit id is
          // the link instead, under the same asset and chain checks.
          final linked = order.isStuckStandingDeposit
              ? deposit['id'] == order.stuckStandingDepositId
              : deposit['orderId'] == order.id;
          if (!linked ||
              deposit['asset'] != order.coinFrom ||
              deposit['chain'] !=
                  (networkCodeToOrchestraChain(order.networkFrom) ??
                      order.networkFrom.toLowerCase())) {
            continue;
          }
          if (_current) {
            setState(() {
              _record = record;
              _deposit = deposit;
            });
          }
          return;
        }
      }
      if (_current) {
        setState(() {
          _record = null;
          _deposit = null;
        });
      }
    } catch (_) {
      // An offline read is not affirmative evidence of refund eligibility.
      if (_current) {
        setState(() {
          _record = null;
          _deposit = null;
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current || _record == null || _deposit == null) {
      return const SizedBox.shrink();
    }
    return StandingDepositRefundAction(
      key: ValueKey('${_record!.label}:${_deposit!['id']}'),
      record: _record!,
      deposit: _deposit!,
      refundAddress: widget.order.refundAddress,
    );
  }
}
