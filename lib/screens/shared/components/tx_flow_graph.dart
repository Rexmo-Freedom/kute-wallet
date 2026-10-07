// lib/screens/shared/components/tx_flow_graph.dart
//
// mempool.space / Coconut-wallet style on-chain transaction flow graph.
//
// By default the graph is a people view: one source row ("Sender" or "Your
// wallet") and up to three destination rows ("Network fee", "Your wallet" or
// "Change", "Recipient" or "Others"), each summed from the real inputs and
// outputs. "Show inputs and outputs" under the graph reveals the full braid:
//
// Two labeled columns:
//   LEFT  = one row per INPUT ("Input #0" / "₿61,954"), evenly spaced.
//   RIGHT = "Fee" / amount at the top, then one row per OUTPUT ("Output #0"
//           / amount). The output the wallet received is accent-colored with a
//           small right-chevron. Amounts follow the sats or BTC setting.
// CENTER = thin curved bezier connectors that weave each left row through a
//          shared central pinch point and back out to each right row (the
//          classic crossing "braid"/hourglass look), with a subtle continuous
//          animated "energy" flow of dots traveling along the curves.
//
// A confirmed tx's inputs carry only their previousOutput (txid + vout), not a
// value, so input amounts are resolved lazily from mempool.space and filled in
// as they arrive (rows render immediately with a "…" placeholder; failures
// render label-only, never crash, never block).
//
// Given the tx's own `txid`, ONE `GET /tx/{txid}` supplies every input value
// and the counterparty address of each input/output (shown truncated in place
// of the "Input #i" / "Output #i" label), and can build the whole graph when
// the caller has no local rows at all (cached cold-wallet shells, tracked
// addresses). Rows paying to / spent from one of `ownAddresses` are
// highlighted; without own addresses the received-amount heuristic applies.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// One input row on the left column. [sats] is null until resolved (renders a
/// "…" placeholder); [prevTxid]/[prevVout] let the widget resolve the value
/// from mempool.space. If [prevTxid]/[prevVout] are null the row stays a
/// placeholder.
class TxFlowInput {
  final String label; // e.g. "Input #0"
  final int? sats; // null while resolving; resolved value otherwise
  final String? prevTxid; // previousOutput txid to resolve the value from
  final int? prevVout; // previousOutput index
  const TxFlowInput({
    required this.label,
    this.sats,
    this.prevTxid,
    this.prevVout,
  });
}

/// One output row on the right column (an output, or the fee).
class TxFlowNode {
  final String label; // e.g. "Output #0" / "Fee"
  final int sats;
  final bool highlight; // the user's own output (received) — accent colored
  final bool isFee;
  const TxFlowNode({
    required this.label,
    required this.sats,
    this.highlight = false,
    this.isFee = false,
  });
}

/// "₿150,000" or "₿0.00 150 000" per the user's [unit] (the same string
/// `conversionProvider` produces), "…" while resolving.
String _satsLabel(int? sats, String unit) =>
    sats == null ? '…' : '₿${sats.toFormattedString(unit)}';

class TxFlowGraph extends ConsumerStatefulWidget {
  /// Input rows (left column, top-to-bottom). Values resolve lazily. May be
  /// empty when [txid] is set: the rows are then built from mempool.space.
  final List<TxFlowInput> inputs;

  /// Output + fee rows (right column, top-to-bottom). Fee should come first.
  /// May be empty when [txid] is set (see [inputs]).
  final List<TxFlowNode> outputs;

  /// When set, ONE `GET /tx/{txid}` fills every input value and the
  /// counterparty addresses in a single round trip, and builds the rows
  /// outright when [inputs] and [outputs] are empty. Without it, input
  /// values fall back to one `GET /tx/{prevTxid}` per input.
  final String? txid;

  /// The wallet's own addresses: rows paid to (or spent from) one of them
  /// are highlighted. Leave empty to keep the caller's [TxFlowNode.highlight]
  /// flags on local rows, or the [receivedSats] heuristic on mempool rows.
  final Set<String> ownAddresses;

  /// Heuristic highlight for mempool-built rows when [ownAddresses] is
  /// empty: the first output worth exactly this many sats is the wallet's
  /// own (what it received, or its change on a send whose local rows carry
  /// the flag). 0 disables it.
  final int receivedSats;

  /// Send-side twin of [receivedSats] for mempool-built rows: the first
  /// output worth exactly this many sats is the recipient's (a Spark
  /// withdrawal's payload carries no address). 0 disables it.
  final int sentSats;

  /// Whether the wallet is the sender. Names the people view's rows: the
  /// source is "Your wallet" and the own output is "Change" on a send, the
  /// source is "Sender" and the own output is "Your wallet" on a receive.
  final bool isSend;

  const TxFlowGraph({
    super.key,
    this.inputs = const [],
    this.outputs = const [],
    this.txid,
    this.ownAddresses = const {},
    this.receivedSats = 0,
    this.sentSats = 0,
    this.isSend = false,
  });

  @override
  ConsumerState<TxFlowGraph> createState() => _TxFlowGraphState();
}

class _TxFlowGraphState extends ConsumerState<TxFlowGraph>
    with SingleTickerProviderStateMixin {
  static const _lookupTimeout = Duration(seconds: 15);
  int _loadGeneration = 0;

  late final AnimationController _ctrl;

  /// Resolved input values, parallel to widget.inputs. Seeded from the
  /// caller-provided sats (usually null) and filled in as fetches complete.
  /// A `false` placeholder distinguishes "still resolving" (null) from
  /// "resolved/failed" (handled via [_failed]).
  late List<int?> _resolved;
  late List<bool> _failed; // true once a fetch finished without a value

  /// The single `GET /tx/{txid}` payload (values + addresses for every
  /// input and output). Null while loading or when `widget.txid` is unset;
  /// [_remoteFailed] tells a failed fetch apart from one still in flight.
  MempoolTxDetails? _remote;
  bool _remoteFailed = false;

  /// True once the person asked for the full input and output braid.
  bool _showDetail = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _seed();
    _load();
  }

  @override
  void didUpdateWidget(TxFlowGraph old) {
    super.didUpdateWidget(old);
    if (!_sameInputs(old.inputs, widget.inputs) || old.txid != widget.txid) {
      _seed();
      _load();
    }
  }

  static bool _sameInputs(List<TxFlowInput> a, List<TxFlowInput> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label ||
          a[i].sats != b[i].sats ||
          a[i].prevTxid != b[i].prevTxid ||
          a[i].prevVout != b[i].prevVout) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrent(int generation) => mounted && generation == _loadGeneration;

  void _seed() {
    _loadGeneration++;
    _resolved = widget.inputs.map((i) => i.sats).toList();
    _failed = List<bool>.filled(widget.inputs.length, false);
    _remote = null;
    _remoteFailed = false;
  }

  /// One `GET /tx/{txid}` (cached on the service) when the caller knows the
  /// txid, then the per-input prevout lookups for whatever is still unknown
  /// (no txid, the fetch failed offline, or an outpoint it did not list).
  Future<void> _load() async {
    final generation = _loadGeneration;
    final txid = widget.txid;
    if (txid != null) {
      final details = await MempoolAddressService.fetchTransaction(txid)
          .timeout(_lookupTimeout, onTimeout: () => null);
      if (!_isCurrent(generation)) return;
      setState(() {
        if (details == null) {
          _remoteFailed = true;
        } else {
          _remote = details;
          for (var i = 0; i < widget.inputs.length; i++) {
            if (_resolved[i] != null) continue;
            final sats = _remoteInputFor(details, widget.inputs[i])?.valueSats;
            if (sats != null) _resolved[i] = sats;
          }
        }
      });
    }
    if (_isCurrent(generation)) await _resolveInputs(generation);
  }

  /// The remote `vin` for a local input, matched by outpoint (never by
  /// index) so a mismatched payload can never mislabel a row.
  MempoolTxInput? _remoteInputFor(MempoolTxDetails r, TxFlowInput local) {
    if (local.prevTxid == null || local.prevVout == null) return null;
    for (final vin in r.inputs) {
      if (vin.prevTxid == local.prevTxid && vin.prevVout == local.prevVout) {
        return vin;
      }
    }
    return null;
  }

  /// Resolve every unknown input value via mempool.space with bounded
  /// concurrency. Each `GET /tx/{prevTxid}` is read for `vout[prevVout].value`.
  /// Failures mark the row failed (renders "—"); nothing blocks the UI.
  Future<void> _resolveInputs(int generation) async {
    const concurrency = 4;
    final inputs = List<TxFlowInput>.of(widget.inputs);
    final pending = <int>[];
    for (var i = 0; i < widget.inputs.length; i++) {
      final inp = widget.inputs[i];
      if (_resolved[i] == null &&
          inp.prevTxid != null &&
          inp.prevVout != null) {
        pending.add(i);
      }
    }
    if (pending.isEmpty) return;

    var cursor = 0;
    Future<void> worker() async {
      while (_isCurrent(generation) && cursor < pending.length) {
        final idx = pending[cursor++];
        final inp = inputs[idx];
        final sats = await _fetchPrevoutValue(inp.prevTxid!, inp.prevVout!);
        if (!_isCurrent(generation)) return;
        setState(() {
          if (sats != null) {
            _resolved[idx] = sats;
          } else {
            _failed[idx] = true;
          }
        });
      }
    }

    await Future.wait(
      List.generate(math.min(concurrency, pending.length), (_) => worker()),
    );
  }

  Future<int?> _fetchPrevoutValue(String txid, int vout) async {
    final details = await MempoolAddressService.fetchTransaction(txid)
        .timeout(_lookupTimeout, onTimeout: () => null);
    if (details == null || vout < 0 || vout >= details.outputs.length) {
      return null;
    }
    return details.outputs[vout].valueSats;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// A counterparty address truncated to "bc1qab…xyz123" so it fits the
  /// label column; null when mempool.space has no address for the script.
  static String? _short(String? address) {
    if (address == null || address.isEmpty) return null;
    final n = address.length;
    if (n <= 14) return address;
    return '${address.substring(0, 6)}…${address.substring(n - 6)}';
  }

  bool _isOwn(String? address) =>
      address != null && widget.ownAddresses.contains(address);

  /// Caller-provided legs, enriched with whatever the remote payload knows:
  /// counterparty addresses as labels and the own-address flag. Amounts
  /// stay local (outputs + fee) or come from [_resolved] (inputs).
  (List<_Leg>, List<_Leg>) _localLegs() {
    final r = _remote;
    final useOwn = r != null && widget.ownAddresses.isNotEmpty;

    final inputs = <_Leg>[];
    for (var i = 0; i < widget.inputs.length; i++) {
      final local = widget.inputs[i];
      final vin = r == null ? null : _remoteInputFor(r, local);
      inputs.add(_Leg(
        label: _short(vin?.address) ?? local.label,
        sats: _resolved[i],
        // A quiet "…" while the lookup is in flight; label-only once it
        // failed (offline), never an ugly "—" column.
        resolving: _resolved[i] == null && !_failed[i],
        own: useOwn && _isOwn(vin?.address),
      ));
    }

    // The local output list carries the fee node at the top and the remote
    // `vout[]` does not, so map by position only when the non-fee counts
    // agree; otherwise the index labels stay.
    final nonFee = widget.outputs.where((o) => !o.isFee).length;
    final remoteOuts =
        r != null && r.outputs.length == nonFee ? r.outputs : null;
    var j = 0;
    final outputs = <_Leg>[];
    for (final o in widget.outputs) {
      MempoolTxOutput? vout;
      if (!o.isFee && remoteOuts != null) vout = remoteOuts[j++];
      outputs.add(_Leg(
        label: o.isFee ? o.label : (_short(vout?.address) ?? o.label),
        sats: o.sats,
        // The caller's flag marks the wallet's own output (what it
        // received, or its change on a send).
        own: !o.isFee && (useOwn ? _isOwn(vout?.address) : o.highlight),
        isFee: o.isFee,
      ));
    }
    return (inputs, outputs);
  }

  /// Legs built entirely from the remote payload, for callers with no local
  /// inputs/outputs (cached cold-wallet shells, tracked addresses, Spark
  /// deposits and withdrawals).
  (List<_Leg>, List<_Leg>) _remoteLegs(
      BuildContext context, MempoolTxDetails r) {
    final l10n = context.l10n;
    final useOwn = widget.ownAddresses.isNotEmpty;

    final inputs = <_Leg>[
      for (var i = 0; i < r.inputs.length; i++)
        _Leg(
          label: _short(r.inputs[i].address) ?? l10n.activityInputIndex('$i'),
          // A coinbase input has no prevout value: render it label-only.
          sats: r.inputs[i].valueSats,
          own: useOwn && _isOwn(r.inputs[i].address),
        ),
    ];

    final outputs = <_Leg>[
      // Fee sits at the top of the right column, as with local rows.
      if (r.fee > 0) _Leg(label: l10n.fee, sats: r.fee, isFee: true),
    ];
    var ownMatched = false;
    var recipientMatched = false;
    for (var i = 0; i < r.outputs.length; i++) {
      final o = r.outputs[i];
      bool own;
      var recipient = false;
      if (useOwn) {
        own = _isOwn(o.address);
      } else {
        // Same rule as the spending wallet: only the first output matching
        // the amount is the wallet's own; on a send without addresses the
        // first output matching the amount sent is the recipient's.
        own = !ownMatched &&
            widget.receivedSats > 0 &&
            o.valueSats == widget.receivedSats;
        if (own) ownMatched = true;
        recipient = !own &&
            !recipientMatched &&
            widget.sentSats > 0 &&
            o.valueSats == widget.sentSats;
        if (recipient) recipientMatched = true;
      }
      outputs.add(_Leg(
        label: _short(o.address) ?? l10n.activityOutputIndex('$i'),
        sats: o.valueSats,
        own: own,
        recipient: recipient,
      ));
    }
    return (inputs, outputs);
  }

  /// The full braid: one painted row per leg, addresses or indexes as
  /// labels, the wallet's own output (or the matched recipient) accented.
  List<_Row> _detailRows(List<_Leg> legs, String unit) => [
        for (final leg in legs)
          _Row(
            label: leg.label,
            amount: leg.sats != null
                ? _satsLabel(leg.sats, unit)
                : (leg.resolving ? '…' : ''),
            highlight: leg.own || leg.recipient,
          ),
      ];

  /// The people view: one source row and at most three destination rows
  /// (network fee, the wallet's own money, everyone else), each the sum of
  /// the legs behind it, so the sheet reads "Sender → Your wallet" instead
  /// of an input and output braid.
  (List<_Row>, List<_Row>) _summaryRows(BuildContext context, List<_Leg> inputs,
      List<_Leg> outputs, String unit) {
    final l10n = context.l10n;
    final isSend = widget.isSend;

    // Sum of the legs; "…" while any value is still resolving and empty
    // (label-only) when one is unknown for good.
    String sum(Iterable<_Leg> legs) {
      var total = 0;
      var resolving = false;
      for (final leg in legs) {
        final sats = leg.sats;
        if (sats == null) {
          if (!leg.resolving) return '';
          resolving = true;
        } else {
          total += sats;
        }
      }
      return resolving ? '…' : _satsLabel(total, unit);
    }

    final fees = outputs.where((o) => o.isFee).toList();
    final own = outputs.where((o) => !o.isFee && o.own).toList();
    final matched = outputs.where((o) => o.recipient).toList();
    // On a send the recipient is the matched output when the payload
    // carried no address, otherwise everything that is not the wallet's.
    // On a receive everything that is not the wallet's went elsewhere.
    final counterparty = matched.isNotEmpty
        ? matched
        : outputs.where((o) => !o.isFee && !o.own).toList();
    final others = outputs
        .where((o) => !o.isFee && !o.own && !counterparty.contains(o))
        .toList();

    final source = _Row(
      label: isSend ? l10n.activityYourWallet : l10n.activitySender,
      amount: sum(inputs),
      highlight: isSend,
    );
    final ownRow = own.isEmpty
        ? null
        : _Row(
            label: isSend ? l10n.activityChangeOutput : l10n.activityYourWallet,
            amount: sum(own),
            highlight: !isSend,
          );
    final counterpartyRow = counterparty.isEmpty
        ? null
        : _Row(
            label: isSend ? l10n.recipient : l10n.activityOtherOutputs,
            amount: sum(counterparty),
            highlight: isSend,
          );
    final destinations = <_Row>[
      if (fees.isNotEmpty)
        _Row(
            label: l10n.activityNetworkFee,
            amount: sum(fees),
            highlight: false),
      // Money that changed hands first, the wallet's own change after it.
      if (isSend) ...[
        if (counterpartyRow != null) counterpartyRow,
        if (ownRow != null) ownRow,
      ] else ...[
        if (ownRow != null) ownRow,
        if (counterpartyRow != null) counterpartyRow,
      ],
      if (others.isNotEmpty)
        _Row(
            label: l10n.activityOtherOutputs,
            amount: sum(others),
            highlight: false),
    ];
    return ([source], destinations);
  }

  /// Opens the full braid. One way: there is nothing to put back, so
  /// the button simply leaves once the detail is on screen.
  void _openDetail() {
    if (_showDetail) return;
    HapticFeedback.selectionClick();
    TrackingService.track('tx_flow_detail_opened');
    setState(() => _showDetail = true);
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = widget.inputs.isNotEmpty || widget.outputs.isNotEmpty;
    final remote = _remote;
    // Every node follows the sats or BTC setting, like the sheet above it.
    final unit = ref.watch(settingsProvider.select((s) => s.btcFormat));
    if (!hasLocal && remote == null) {
      // Nothing local to draw: a compact skeleton while the single fetch is
      // in flight, and nothing at all (never an error) once it has failed or
      // when there is no txid to fetch.
      return widget.txid != null && !_remoteFailed
          ? const _TxFlowSkeleton()
          : const SizedBox.shrink();
    }

    final c = context.colors;
    // The traveling "energy" dots are decorative (the curves + labels render
    // statically regardless of progress), so suspend the repeating loop when
    // the user prefers reduced motion. The graph stays fully readable.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }

    final (inputLegs, outputLegs) =
        hasLocal ? _localLegs() : _remoteLegs(context, remote!);
    // The people view needs to know which output is the wallet's (or, on a
    // send, that everything else is the recipient's); otherwise only the
    // braid is honest.
    final canSummarize =
        widget.isSend || outputLegs.any((o) => !o.isFee && o.own);
    final detail = _showDetail || !canSummarize;
    final (inputs, outputs) = detail
        ? (_detailRows(inputLegs, unit), _detailRows(outputLegs, unit))
        : _summaryRows(context, inputLegs, outputLegs, unit);
    final rows = math.max(inputs.length, outputs.length);
    final height = (40.0 + rows.clamp(1, 16) * 34.0).h;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              painter: _TxFlowPainter(
                progress: _ctrl.value,
                inputs: inputs,
                outputs: outputs,
                accent: c.accent,
                textPrimary: c.textPrimary,
                textSecondary: c.textSecondary,
                textTertiary: c.textTertiary,
              ),
            ),
          ),
        ),
        // Only while the detail is hidden. It used to flip to "Hide
        // inputs and outputs", which read as a disclosure the user was
        // managing rather than one more thing they could look at.
        if (canSummarize && !_showDetail) _DetailButton(onTap: _openDetail),
      ],
    );
  }
}

/// The way into the full braid, under the people view. A plain row in
/// the sheet's own detail vocabulary: a label and a chevron, the same
/// as every other row that leads somewhere.
class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.inputsOutputs,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18.sp, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Compact placeholder while a graph with no local rows waits on
/// mempool.space: two input bars on the left, fee + two output bars on the
/// right, at the height of a three-row graph so the sheet does not jump.
class _TxFlowSkeleton extends StatelessWidget {
  const _TxFlowSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row({required bool alignEnd}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SkeletonBar(64.w, 10.h),
            SizedBox(height: 5.h),
            SkeletonBar(88.w, 12.h),
          ],
        );
    return KuteSkeleton(
      child: SizedBox(
        height: (40.0 + 3 * 34.0).h,
        width: double.infinity,
        child: Row(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [row(alignEnd: false), row(alignEnd: false)],
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                row(alignEnd: true),
                row(alignEnd: true),
                row(alignEnd: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One input or output with what the graph knows about it: the detailed
/// label (address or index), its value when known, whether it is the
/// wallet's own, the matched recipient on a send, or the fee. [resolving]
/// keeps the "…" placeholder apart from a failed lookup.
class _Leg {
  final String label;
  final int? sats;
  final bool resolving;
  final bool own;
  final bool recipient;
  final bool isFee;
  const _Leg({
    required this.label,
    required this.sats,
    this.resolving = false,
    this.own = false,
    this.recipient = false,
    this.isFee = false,
  });
}

/// A resolved, paint-ready row.
class _Row {
  final String label;
  final String amount;
  final bool highlight;
  const _Row({
    required this.label,
    required this.amount,
    required this.highlight,
  });

  @override
  bool operator ==(Object other) =>
      other is _Row &&
      other.label == label &&
      other.amount == amount &&
      other.highlight == highlight;

  @override
  int get hashCode => Object.hash(label, amount, highlight);
}

class _TxFlowPainter extends CustomPainter {
  final double progress;
  final List<_Row> inputs;
  final List<_Row> outputs;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  _TxFlowPainter({
    required this.progress,
    required this.inputs,
    required this.outputs,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (inputs.isEmpty && outputs.isEmpty) return;

    // Reserve the OUTER columns for the labels and keep the connectors in the
    // central channel only — a curve must NEVER be drawn over label text.
    final labelW = size.width * 0.36;
    final leftConnectorX = labelW;
    final rightConnectorX = size.width - labelW;
    final pinchX = size.width / 2;
    final pinchY = size.height / 2;

    final leftYs = _evenY(size.height, inputs.length);
    final rightYs = _evenY(size.height, outputs.length);

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;

    final braid = <(Path, bool)>[]; // (path, highlighted)

    // Each input weaves from the inner edge of the left label column to the
    // shared central pinch point.
    final lspan = pinchX - leftConnectorX;
    for (final y0 in leftYs) {
      final p = Path()
        ..moveTo(leftConnectorX, y0)
        ..cubicTo(leftConnectorX + lspan * 0.5, y0, pinchX - lspan * 0.2,
            pinchY, pinchX, pinchY);
      braid.add((p, false));
    }
    // The pinch fans back out to the inner edge of the right label column.
    final rspan = rightConnectorX - pinchX;
    for (var i = 0; i < rightYs.length; i++) {
      final y1 = rightYs[i];
      final hot = outputs[i].highlight;
      final p = Path()
        ..moveTo(pinchX, pinchY)
        ..cubicTo(pinchX + rspan * 0.2, pinchY, rightConnectorX - rspan * 0.5,
            y1, rightConnectorX, y1);
      braid.add((p, hot));
    }

    // Subtle gray lines first, accent (highlighted) lines on top.
    for (final (p, hot) in braid) {
      if (hot) continue;
      canvas.drawPath(
        p,
        linePaint..color = textTertiary.withValues(alpha: 0.30),
      );
    }
    for (final (p, hot) in braid) {
      if (!hot) continue;
      canvas.drawPath(
        p,
        linePaint..color = accent.withValues(alpha: 0.85),
      );
    }

    // Traveling "energy" dots along every connector.
    for (final (p, hot) in braid) {
      final base = hot
          ? accent.withValues(alpha: 0.95)
          : textTertiary.withValues(alpha: 0.55);
      for (final metric in p.computeMetrics()) {
        const particles = 2;
        for (var k = 0; k < particles; k++) {
          final t = (progress + k / particles) % 1.0;
          final pos = metric.getTangentForOffset(metric.length * t);
          if (pos == null) continue;
          final edge = math.min(t, 1 - t);
          final fade = (edge * 4).clamp(0.0, 1.0);
          canvas.drawCircle(
            pos.position,
            hot ? 2.2 : 1.8,
            Paint()..color = base.withValues(alpha: base.a * fade),
          );
        }
      }
    }

    // Labels live in the OUTER columns (x ∈ [0, labelW] left, [w-labelW, w]
    // right), so they never sit under the central connectors.
    for (var i = 0; i < inputs.length; i++) {
      _drawLabel(
        canvas,
        inputs[i],
        2.w,
        leftYs[i],
        leftAlign: true,
        maxWidth: labelW - 10.w,
      );
    }
    for (var i = 0; i < outputs.length; i++) {
      _drawLabel(
        canvas,
        outputs[i],
        size.width - 2.w,
        rightYs[i],
        leftAlign: false,
        maxWidth: labelW - 10.w,
      );
    }
  }

  /// Evenly spaced row centers down [height] for [n] rows.
  List<double> _evenY(double height, int n) {
    if (n <= 0) return const [];
    if (n == 1) return [height / 2];
    final pad = (12.0).h;
    final usable = height - pad * 2;
    return [for (var i = 0; i < n; i++) pad + usable * i / (n - 1)];
  }

  void _drawLabel(
    Canvas canvas,
    _Row row,
    double anchorX,
    double centerY, {
    required bool leftAlign,
    required double maxWidth,
  }) {
    final labelColor = row.highlight ? accent : textTertiary;
    // The highlighted amount is INFORMATIONAL value text; the brand accent
    // (blue ~3.2:1 on white in light mode) fails ~4.5:1, so paint the value in
    // high-contrast textPrimary. The highlight identity is still carried by the
    // accent label + its '›' chevron (non-colour cues), so nothing is lost.
    final amountColor = row.highlight ? textPrimary : textSecondary;
    final align = leftAlign ? TextAlign.left : TextAlign.right;

    // Right-chevron on the received output's label (right column only).
    final labelText =
        (!leftAlign && row.highlight) ? '${row.label} ›' : row.label;

    // When [amount] is empty the graph is a labels-only flow diagram (the
    // numbers live in the sheet's detail rows / header, so we never repeat
    // them here). Render the label alone, sized up to read as primary text.
    final hasAmount = row.amount.isNotEmpty;
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
          text: hasAmount ? '$labelText\n' : labelText,
          style: TextStyle(
            color: hasAmount ? labelColor : amountColor,
            fontSize: hasAmount ? 11.sp : 13.sp,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (hasAmount)
          TextSpan(
            text: row.amount,
            style: TextStyle(
              color: amountColor,
              fontSize: 13.sp,
              height: 1.25,
              fontWeight: row.highlight ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
      ]),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
    )..layout(maxWidth: math.max(40.0, maxWidth));

    final x = leftAlign ? anchorX : anchorX - tp.width;
    tp.paint(canvas, Offset(x, centerY - tp.height / 2));
  }

  @override
  bool shouldRepaint(_TxFlowPainter old) =>
      old.progress != progress ||
      !listEquals(old.inputs, inputs) ||
      !listEquals(old.outputs, outputs);
}

// ---------------------------------------------------------------------------
// SimpleFlowGraph
// ---------------------------------------------------------------------------
//
// A network-free 1→N flow for accounts that have NO on-chain UTXOs (Lightning
// / Spark sends, Polymarket / Orchestra deposits + withdrawals, etc.). It
// reuses the same visual language as [TxFlowGraph] — labeled outer columns,
// a central pinch with animated energy dots — but derives everything from the
// local transaction fields the caller passes in. It never hits the network,
// so it always renders (no offline gating needed).
//
// LEFT  = a single source row ("Your wallet" / "Predictions").
// RIGHT = one row per destination, plus an optional fee row at the top. The
//         primary destination can be highlighted (accent + chevron).

/// One side of a [SimpleFlowGraph] row. [amount] is a fully formatted,
/// network-free string already in the user's unit (e.g. "₿0.00 120 000",
/// "$12.50", "₿1,200").
class SimpleFlowNode {
  final String label;
  final String amount;
  final bool highlight;
  const SimpleFlowNode({
    required this.label,
    required this.amount,
    this.highlight = false,
  });
}

class SimpleFlowGraph extends StatefulWidget {
  /// The single source on the left (e.g. "Your wallet").
  final SimpleFlowNode source;

  /// Destinations on the right, top-to-bottom. A fee row, if any, should be
  /// listed first so it sits at the top like the BTC graph.
  final List<SimpleFlowNode> destinations;

  const SimpleFlowGraph({
    super.key,
    required this.source,
    required this.destinations,
  });

  @override
  State<SimpleFlowGraph> createState() => _SimpleFlowGraphState();
}

class _SimpleFlowGraphState extends State<SimpleFlowGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Decorative energy-dot loop — suspend it under reduced motion. The flow
    // diagram (curves + labels) renders identically without it.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    final rows = math.max(1, widget.destinations.length);
    final height = (40.0 + rows.clamp(1, 16) * 34.0).h;

    final inputs = <_Row>[
      _Row(
        label: widget.source.label,
        amount: widget.source.amount,
        highlight: widget.source.highlight,
      ),
    ];
    final outputs = <_Row>[
      for (final d in widget.destinations)
        _Row(label: d.label, amount: d.amount, highlight: d.highlight),
    ];

    return SizedBox(
      height: height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          painter: _TxFlowPainter(
            progress: _ctrl.value,
            inputs: inputs,
            outputs: outputs,
            accent: c.accent,
            textPrimary: c.textPrimary,
            textSecondary: c.textSecondary,
            textTertiary: c.textTertiary,
          ),
        ),
      ),
    );
  }
}
