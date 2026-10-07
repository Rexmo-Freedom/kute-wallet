import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class StandingDepositRefundAction extends ConsumerStatefulWidget {
  const StandingDepositRefundAction(
      {super.key,
      required this.record,
      required this.deposit,
      this.refundAddress});
  final StandingDepositRecord record;
  final Map<String, dynamic> deposit;
  final String? refundAddress;
  @override
  ConsumerState<StandingDepositRefundAction> createState() =>
      _StandingDepositRefundActionState();
}

class _StandingDepositRefundActionState
    extends ConsumerState<StandingDepositRefundAction> {
  static final _inFlight = <String>{};
  late final _scope = StandingDepositStore.capture(widget.record.walletId);
  late StandingDepositRecord _record = widget.record;
  bool _busy = false;
  String? _error;
  bool get _current =>
      mounted &&
      StandingDepositStore.current(_scope) &&
      ref.read(settingsProvider).activeWalletId == widget.record.walletId;
  Future<void> _refresh() async {
    if (!_current) return;
    try {
      final records =
          await StandingDepositStore.records(widget.record.walletId);
      final matching = records.where((r) => r.label == widget.record.label);
      if (_current && matching.isNotEmpty) {
        setState(() => _record = matching.first);
      }
    } catch (_) {
      if (_current) {
        setState(() => _error = context.l10n.standingDepositsUnknownRefund);
      }
    }
  }

  Future<void> _request() async {
    final key =
        '${widget.record.walletId}:${widget.record.label}:${widget.deposit['id']}';
    if (_busy || !_current || !_inFlight.add(key)) return;
    setState(() => _busy = true);
    try {
      await _refund(_record, widget.deposit);
    } finally {
      _inFlight.remove(key);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund(
      StandingDepositRecord record, Map<String, dynamic> deposit) async {
    if (!_current) return;
    final id = deposit['id'] as String?;
    final chain = deposit['chain'] as String?;
    final asset = deposit['asset'] as String?;
    final amount = BigInt.tryParse('${deposit['amount']}');
    if (id == null ||
        chain == null ||
        asset == null ||
        amount == null ||
        amount <= BigInt.zero) {
      return;
    }
    final input = TextEditingController(text: widget.refundAddress);
    String? address;
    try {
      address = await showAppBottomSheet<String>(
          context: context,
          builder: (ctx) => StatefulBuilder(
                builder: (ctx, setSheetState) => Padding(
                    padding: EdgeInsets.fromLTRB(
                        24, 24, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(ctx.l10n.standingDepositsRefund,
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700))),
                            IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close))
                          ]),
                          const SizedBox(height: 16),
                          Text('${orchestraChainDisplayName(chain)} · $asset'),
                          const SizedBox(height: 12),
                          Text(ctx.l10n.standingDepositsRefundNote),
                          const SizedBox(height: 16),
                          TextField(
                              controller: input,
                              autocorrect: false,
                              enableSuggestions: false,
                              onChanged: (_) => setSheetState(() {}),
                              onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
                              decoration: InputDecoration(
                                  hintText: ctx.l10n.ledgerFundReviewRefund,
                                  filled: true,
                                  fillColor: ctx.colors.surface,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none))),
                          const SizedBox(height: 12),
                          Text(ctx.l10n.receiveOwnRefundAddress),
                          const SizedBox(height: 20),
                          AppButton(
                              text: ctx.l10n.standingDepositsRefund,
                              onPressed: formatMatchesChain(
                                          chain, input.text.trim(),
                                          mainnet: true) ==
                                      AddressFormatMatch.ok
                                  ? () => Navigator.pop(ctx, input.text.trim())
                                  : null),
                        ])),
              ));
    } finally {
      // Bottom-sheet route removal can still animate with its field mounted.
      Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    }
    if (address == null || !_current) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // One outcome per refund request that reached the network step or
    // failed on the way there. Chain/asset are categorical; no ids,
    // addresses or amounts.
    var reported = false;
    void report(String outcome) {
      if (reported) return;
      reported = true;
      TrackingService.track('orchestra_refund_requested', params: {
        'chain': chain,
        'asset': asset,
        'outcome': outcome,
      });
    }

    try {
      final records =
          await StandingDepositStore.records(widget.record.walletId);
      final latest = records.firstWhere((r) => r.label == record.label);
      if (_refundPending(latest, id)) {
        throw StateError('Refund already requested');
      }
      final intent = SensitiveIntent(
          action: SensitiveAction.sparkRefund,
          walletId: widget.record.walletId,
          venue: 'orchestra',
          account: record.label,
          destination: address,
          asset: '$chain:$asset',
          amountMax: amount,
          limits: {'depositId': id});
      if (!_current) return;
      final grant = await requireFreshAuthGrant(context, ref,
          intent: intent, reason: context.l10n.standingDepositsRefund);
      if (grant == null || !_current) return;
      final key = OrchestraService.generateIdempotencyKey();
      // Journal BEFORE dispatch. A lost reply must not enable a second request
      // to another recipient. Provider status is the only settlement evidence.
      await StandingDepositStore.recordRefund(
          record: latest,
          scope: _scope,
          depositId: id,
          requestKey: key,
          address: address);
      if (!_current) return;
      var dispatched = false;
      try {
        await OrchestraService.standingRequest(
            operation: 'resolve',
            label: record.label,
            current: () => _current,
            idempotencyKey: key,
            body: {
              'depositIds': [id],
              'refundAddress': address
            },
            beforeDispatch: () {
              if (!dispatched) {
                AuthGrants.consume(grant, intent);
              } else {
                // An authenticated transport retry uses the exact same body/key.
                if (grant.revoked) throw const GrantRevoked();
                if (grant.isExpiredAt(DateTime.now())) {
                  throw const GrantExpired();
                }
              }
              dispatched = true;
            });
        report('submitted');
      } catch (error) {
        report(error is StandingRequestException &&
                error.refundDefinitelyRefused
            ? 'refused'
            : 'failed');
        if ((!dispatched ||
                (error is StandingRequestException &&
                    error.refundDefinitelyRefused)) &&
            _current) {
          await StandingDepositStore.recordRefund(
              record: latest,
              scope: _scope,
              depositId: id,
              requestKey: key,
              address: address,
              refused: true);
        }
        rethrow;
      }
    } catch (_) {
      report('failed');
      if (_current) {
        setState(() => _error = context.l10n.standingDepositsUnknownRefund);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  bool _refundPending(StandingDepositRecord record, Object? id) {
    final row = record.refunds[id];
    return row != null && (row is! Map || row['state'] != 'refused');
  }

  @override
  Widget build(BuildContext context) {
    if (!_current || widget.deposit['refundTxId'] != null) {
      return const SizedBox.shrink();
    }
    final pending = _refundPending(_record, widget.deposit['id']);
    if (!pending && widget.deposit['status'] != 'held') {
      return const SizedBox.shrink();
    }
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!)),
          if (pending)
            Text(context.l10n.standingDepositsRefundRequested)
          else if (widget.deposit['chain'] == 'tron')
            Text(context.l10n.standingDepositsOperatorRefund)
          else
            AppButton(
                text: context.l10n.requestRefund,
                variant: AppButtonVariant.secondary,
                isLoading: _busy,
                onPressed: _busy ? null : _request),
        ]));
  }
}
