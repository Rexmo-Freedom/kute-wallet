// lib/screens/shared/components/tx_flow_graph.dart
//
// On-chain transaction tree, addresses first.
//
// LEFT   = one row per INPUT: its address (truncated "bc1q8m4…x7d2",
//          monospace, primary text) with the amount under it. The wallet's
//          own inputs show the address in orange and "· Your wallet" after
//          the amount.
// CENTER = the transaction itself, a small filled orange ₿ disc.
// RIGHT  = one row per OUTPUT, right-aligned: address first, then the amount
//          led by its role when the data gives one ("Your wallet", "Change",
//          "Recipient"). The network fee is its own last branch, no address.
//
// Connectors are straight orthogonal hairlines (1.5 px, round caps): each
// input runs across into a shared trunk left of the disc and into it; out of
// the disc a short run feeds a second trunk that branches to every output,
// ending in a small open chevron. The wallet's own legs are orange, the rest
// quiet grey, the fee branch dotted. On first show the lines draw once, left
// to right (inputs, then outputs), and then stay still; under Reduce Motion
// they are simply there. More than four rows on a side collapse behind
// "See all". Tapping an address copies it.
//
// A confirmed tx's inputs carry only their previousOutput (txid + vout), not a
// value, so input amounts are resolved lazily from mempool.space and filled in
// as they arrive (rows render immediately with a "…" placeholder; failures
// render label-only, never crash, never block).
//
// Given the tx's own `txid`, ONE `GET /tx/{txid}` supplies every input value
// and the counterparty address of each input/output (shown truncated in place
// of the "Input #i" / "Output #i" label), and can build the whole tree when
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
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
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

  /// Draws the lines once on first show: inputs over the first ~700 ms,
  /// outputs from ~650 ms (see [_TreePainter]).
  late final AnimationController _ctrl;
  bool _drawScheduled = false;

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

  /// True once the person asked to see every row of a long side.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _TreePainter.drawMs),
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

  /// A counterparty address truncated to "bc1q8m4…x7d2" so it fits the
  /// row; null when mempool.space has no address for the script.
  static String? _short(String? address) {
    if (address == null || address.isEmpty) return null;
    final n = address.length;
    if (n <= 13) return address;
    return '${address.substring(0, 7)}…${address.substring(n - 4)}';
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
        address: vin?.address,
        sats: _resolved[i],
        // A quiet "…" while the lookup is in flight; label-only once it
        // failed (offline), never an ugly "—" column.
        resolving: _resolved[i] == null && !_failed[i],
        // Local inputs on a send are the spending wallet's own coins.
        own: useOwn ? _isOwn(vin?.address) : widget.isSend,
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
        address: vout?.address,
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
          address: r.inputs[i].address,
          // A coinbase input has no prevout value: render it label-only.
          sats: r.inputs[i].valueSats,
          own: useOwn && _isOwn(r.inputs[i].address),
        ),
    ];

    final outputs = <_Leg>[
      // Fee first, as with local rows; the tree draws it last.
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
        address: o.address,
        sats: o.valueSats,
        own: own,
        recipient: recipient,
      ));
    }
    return (inputs, outputs);
  }

  /// The tree's rows: inputs as they come (the wallet's own named after the
  /// amount), outputs led by their role when the data gives one, and the
  /// network fee as the last branch.
  (List<_TreeRow>, List<_TreeRow>) _treeRows(BuildContext context,
      List<_Leg> inputs, List<_Leg> outputs, String unit) {
    final l10n = context.l10n;
    final isSend = widget.isSend;

    // "…" while the value resolves, empty (label-only) when unknown for good.
    String amount(_Leg leg) => leg.sats != null
        ? _satsLabel(leg.sats, unit)
        : (leg.resolving ? '…' : '');
    String dot(List<String?> parts) =>
        parts.whereType<String>().where((p) => p.isNotEmpty).join(' · ');

    // On a send the recipient is the matched output when the payload
    // carried no address, otherwise everything that is not the wallet's.
    // On a receive the rest has no role worth naming.
    final matched = outputs.any((o) => o.recipient);
    String? role(_Leg o) {
      if (o.own) {
        return isSend ? l10n.activityChangeOutput : l10n.activityYourWallet;
      }
      if (o.recipient || (isSend && !matched)) return l10n.recipient;
      return null;
    }

    final ins = <_TreeRow>[
      for (final leg in inputs)
        _TreeRow(
          title: leg.label,
          address: leg.address,
          detail: dot([amount(leg), if (leg.own) l10n.activityYourWallet]),
          own: leg.own,
        ),
    ];
    final outs = <_TreeRow>[
      for (final o in outputs.where((o) => !o.isFee))
        _TreeRow(
          title: o.label,
          address: o.address,
          detail: dot([role(o), amount(o)]),
          own: o.own,
        ),
      for (final o in outputs.where((o) => o.isFee))
        _TreeRow(
          title: l10n.activityNetworkFee,
          detail: amount(o),
          fee: true,
        ),
    ];
    return (ins, outs);
  }

  static const _collapsedRows = 4;

  /// A long side shows its first rows until "See all"; the fee branch
  /// always stays in view.
  List<_TreeRow> _collapse(List<_TreeRow> rows) {
    if (_expanded || rows.length <= _collapsedRows) return rows;
    final fee = rows.where((r) => r.fee).toList();
    return [
      ...rows.where((r) => !r.fee).take(_collapsedRows - fee.length),
      ...fee,
    ];
  }

  /// Shows every row. One way: there is nothing to put back, so the
  /// button simply leaves once the rows are on screen.
  void _expand() {
    if (_expanded) return;
    HapticFeedback.selectionClick();
    TrackingService.track('tx_flow_detail_opened');
    setState(() => _expanded = true);
  }

  void _copy(String address) {
    HapticFeedback.selectionClick();
    Clipboard.setData(ClipboardData(text: address));
    showMessageSnackBarInfo(
        context: context, message: context.l10n.copiedToClipboard);
  }

  /// Draws the lines once, after the tree's first frame; under Reduce
  /// Motion they are complete at once.
  void _scheduleDraw(bool reduceMotion) {
    if (_drawScheduled) return;
    _drawScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (reduceMotion) {
        _ctrl.value = 1;
      } else {
        _ctrl.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = widget.inputs.isNotEmpty || widget.outputs.isNotEmpty;
    final remote = _remote;
    // Every amount follows the sats or BTC setting, like the sheet above it.
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
    final reduceMotion = kuteReduceMotion(context);
    _scheduleDraw(reduceMotion);

    final (inputLegs, outputLegs) =
        hasLocal ? _localLegs() : _remoteLegs(context, remote!);
    final (ins, outs) = _treeRows(context, inputLegs, outputLegs, unit);
    final collapsible = math.max(ins.length, outs.length) > _collapsedRows;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Text(
            context.l10n.tnTransaction.toUpperCase(),
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        _TxTree(
          inputs: _collapse(ins),
          outputs: _collapse(outs),
          draw: reduceMotion ? kAlwaysCompleteAnimation : _ctrl,
          onCopy: _copy,
        ),
        if (collapsible && !_expanded) _SeeAllButton(onTap: _expand),
      ],
    );
  }
}

/// The way to every row of a long side, under the tree. A plain row in
/// the sheet's own detail vocabulary: a label and a chevron, the same as
/// every other row that leads somewhere.
class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        // Flush with the tree's text.
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.seeAll,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18.sp, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// The wallet's own legs, the disc and own addresses.
const Color _kOwnOrange = Color(0xFFF29B2D);

/// The tree itself: the rows as real text (each a semantics node; an
/// address copies on tap) over the painted hairlines and the ₿ disc.
class _TxTree extends StatelessWidget {
  const _TxTree({
    required this.inputs,
    required this.outputs,
    required this.draw,
    required this.onCopy,
  });

  final List<_TreeRow> inputs;
  final List<_TreeRow> outputs;
  final Animation<double> draw;
  final ValueChanged<String> onCopy;

  /// Room between the disc and each trunk.
  static const _trunkGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    final base = DefaultTextStyle.of(context).style;
    final mono = TextStyle(
      fontSize: 12.5.sp,
      height: 1.3,
      fontWeight: FontWeight.w600,
      fontFamily: 'Menlo',
      fontFamilyFallback: const ['monospace', 'Courier New'],
    );
    final plain = TextStyle(
      fontSize: 12.5.sp,
      height: 1.3,
      fontWeight: FontWeight.w600,
    );
    final detail = TextStyle(
      color: c.textSecondary,
      fontSize: 12.sp,
      height: 1.35,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    TextStyle titleStyle(_TreeRow r) =>
        (r.address != null ? mono : plain).copyWith(
            color:
                r.own ? _kOwnOrange : (r.fee ? c.textTertiary : c.textPrimary));

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cx = w / 2;
      final trunkL = cx - _TreePainter.discR - _trunkGap;
      final trunkR = w - trunkL;
      // Text never reaches a trunk.
      final colW = math.max(40.0, trunkL - 18);
      final titleH = scaler.scale(12.5.sp) * 1.3;
      final detailH = scaler.scale(12.sp) * 1.35;
      // ~58 px apart, more when large text needs it (a detail may wrap).
      final pitch = math.max(58.0, titleH + 2 + detailH * 2 + 10);
      final n = math.max(1, math.max(inputs.length, outputs.length));
      final top = titleH / 2 + 2;
      final mid = top + (n - 1) * pitch / 2;
      // Row anchors sit on each address line, centred on the disc.
      List<double> anchors(int k) =>
          [for (var i = 0; i < k; i++) mid + (i - (k - 1) / 2) * pitch];
      final inY = anchors(inputs.length);
      final outY = anchors(outputs.length);

      double titleW(_TreeRow r) => (TextPainter(
            text: TextSpan(text: r.title, style: base.merge(titleStyle(r))),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: colW))
              .width;
      double detailBelow(_TreeRow r) => r.detail.isEmpty
          ? 0
          : (TextPainter(
              text: TextSpan(text: r.detail, style: base.merge(detail)),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 2,
              ellipsis: '…',
            )..layout(maxWidth: colW))
              .height;
      // Tall enough for the lowest row's detail, never more.
      final height = [
            mid + _TreePainter.discR,
            for (var i = 0; i < inputs.length; i++)
              inY[i] + titleH / 2 + 2 + detailBelow(inputs[i]),
            for (var i = 0; i < outputs.length; i++)
              outY[i] + titleH / 2 + 2 + detailBelow(outputs[i]),
          ].reduce(math.max) +
          4;

      Widget row(_TreeRow r, double y, {required bool left}) {
        final align = left ? TextAlign.left : TextAlign.right;
        final copy = r.address;
        final tap = copy == null ? null : () => onCopy(copy);
        return Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: y - titleH / 2,
          width: colW,
          child: Semantics(
            container: true,
            excludeSemantics: true,
            label: [r.title, r.detail].where((s) => s.isNotEmpty).join(', '),
            onTap: tap,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    left ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: align,
                      style: titleStyle(r)),
                  SizedBox(height: 2),
                  if (r.detail.isNotEmpty)
                    Text(r.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: align,
                        style: detail),
                ],
              ),
            ),
          ),
        );
      }

      return SizedBox(
        width: w,
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TreePainter(
                  draw: draw,
                  // Lines start / end 8 px clear of each address.
                  inputs: [
                    for (var i = 0; i < inputs.length; i++)
                      (
                        x: titleW(inputs[i]) + 8,
                        y: inY[i],
                        own: inputs[i].own,
                        fee: false,
                      ),
                  ],
                  outputs: [
                    for (var i = 0; i < outputs.length; i++)
                      (
                        x: w - titleW(outputs[i]) - 8,
                        y: outY[i],
                        own: outputs[i].own,
                        fee: outputs[i].fee,
                      ),
                  ],
                  mid: mid,
                  trunkL: trunkL,
                  trunkR: trunkR,
                  line: c.textDisabled,
                  dots: c.textTertiary,
                  // The app's own face, which carries the ₿ glyph.
                  glyph: base.merge(TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  )),
                ),
              ),
            ),
            for (var i = 0; i < inputs.length; i++)
              row(inputs[i], inY[i], left: true),
            for (var i = 0; i < outputs.length; i++)
              row(outputs[i], outY[i], left: false),
          ],
        ),
      );
    });
  }
}

/// One leg of the tree as painted: [x] is where the line leaves an input
/// (or meets an output's chevron), [y] its row's address line.
typedef _Branch = ({double x, double y, bool own, bool fee});

/// Orthogonal hairlines into a trunk left of the disc and out of a trunk
/// right of it, the ₿ disc in the middle. [draw] runs 0 → 1 once: inputs
/// over the first [_inMs], outputs from [_outStartMs] to the end.
class _TreePainter extends CustomPainter {
  static const drawMs = 1350;
  static const _inMs = 700;
  static const _outStartMs = 650;
  static const discR = 11.0;

  /// Lines stop this far short of the disc.
  static const _discGap = 4.0;

  final Animation<double> draw;
  final List<_Branch> inputs;
  final List<_Branch> outputs;
  final double mid;
  final double trunkL;
  final double trunkR;
  final Color line;
  final Color dots;
  final TextStyle glyph;

  _TreePainter({
    required this.draw,
    required this.inputs,
    required this.outputs,
    required this.mid,
    required this.trunkL,
    required this.trunkR,
    required this.line,
    required this.dots,
    required this.glyph,
  }) : super(repaint: draw);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final ms = draw.value * drawMs;
    final tIn = Curves.easeInOut.transform((ms / _inMs).clamp(0.0, 1.0));
    final tOut = Curves.easeInOut.transform(
        ((ms - _outStartMs) / (drawMs - _outStartMs)).clamp(0.0, 1.0));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The fee's dots first so shared runs read solid, then grey, then the
    // wallet's orange on top.
    int layer(_Branch b) => b.own ? 2 : (b.fee ? 0 : 1);
    for (var pass = 0; pass < 3; pass++) {
      for (final b in inputs) {
        if (layer(b) != pass) continue;
        final p = Path()
          ..moveTo(b.x, b.y)
          ..lineTo(trunkL, b.y)
          ..lineTo(trunkL, mid)
          ..lineTo(cx - discR - _discGap, mid);
        _stroke(canvas, p, tIn, b, stroke);
      }
      for (final b in outputs) {
        if (layer(b) != pass) continue;
        final p = Path()
          ..moveTo(cx + discR + _discGap, mid)
          ..lineTo(trunkR, mid)
          ..lineTo(trunkR, b.y)
          ..lineTo(b.x, b.y);
        _stroke(canvas, p, tOut, b, stroke);
        // The open chevron settles in as the line arrives.
        final a = ((tOut - 0.85) / 0.15).clamp(0.0, 1.0);
        if (a > 0) {
          final colour = b.own ? _kOwnOrange : (b.fee ? dots : line);
          canvas.drawPath(
            Path()
              ..moveTo(b.x - 3.5, b.y - 3.5)
              ..lineTo(b.x, b.y)
              ..lineTo(b.x - 3.5, b.y + 3.5),
            stroke..color = colour.withValues(alpha: colour.a * a),
          );
        }
      }
    }

    // The transaction: a plain orange ₿ disc.
    canvas.drawCircle(Offset(cx, mid), discR, Paint()..color = _kOwnOrange);
    final mark = TextPainter(
      text: TextSpan(text: '₿', style: glyph),
      textDirection: TextDirection.ltr,
    )..layout();
    mark.paint(canvas, Offset(cx - mark.width / 2, mid - mark.height / 2));
  }

  /// The first [t] of [path]: solid, or dotted one on four for the fee.
  void _stroke(Canvas canvas, Path path, double t, _Branch b, Paint stroke) {
    if (t <= 0) return;
    for (final m in path.computeMetrics()) {
      final len = m.length * t;
      if (b.fee) {
        final dot = Paint()..color = dots;
        for (var d = 0.0; d <= len; d += 5) {
          final pos = m.getTangentForOffset(d)?.position;
          if (pos != null) canvas.drawCircle(pos, 0.9, dot);
        }
      } else {
        canvas.drawPath(
            m.extractPath(0, len), stroke..color = b.own ? _kOwnOrange : line);
      }
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.draw != draw ||
      old.mid != mid ||
      old.trunkL != trunkL ||
      old.line != line ||
      old.dots != dots ||
      !listEquals(old.inputs, inputs) ||
      !listEquals(old.outputs, outputs);
}

/// Compact placeholder while a tree with no local rows waits on
/// mempool.space: two input bars on the left, two outputs and the fee on
/// the right, at about the height of a three-row tree so the sheet does
/// not jump.
class _TxFlowSkeleton extends StatelessWidget {
  const _TxFlowSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row({required bool alignEnd}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SkeletonBar(88.w, 12.h),
            SizedBox(height: 5.h),
            SkeletonBar(64.w, 10.h),
          ],
        );
    return KuteSkeleton(
      child: SizedBox(
        height: 180.h,
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

/// One input or output with what the tree knows about it: the label
/// (truncated address or index), the full [address] when known (copied on
/// tap), its value when known, whether it is the wallet's own, the matched
/// recipient on a send, or the fee. [resolving] keeps the "…" placeholder
/// apart from a failed lookup.
class _Leg {
  final String label;
  final String? address;
  final int? sats;
  final bool resolving;
  final bool own;
  final bool recipient;
  final bool isFee;
  const _Leg({
    required this.label,
    required this.sats,
    this.address,
    this.resolving = false,
    this.own = false,
    this.recipient = false,
    this.isFee = false,
  });
}

/// A tree row ready for layout: [title] is the truncated address (or the
/// fallback label, or "Network fee"), [detail] the line under it.
class _TreeRow {
  final String title;
  final String? address;
  final String detail;
  final bool own;
  final bool fee;
  const _TreeRow({
    required this.title,
    required this.detail,
    this.address,
    this.own = false,
    this.fee = false,
  });
}

/// A resolved, paint-ready row of [SimpleFlowGraph]'s braid.
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

/// The braid behind [SimpleFlowGraph]: labeled outer columns, curves
/// through a central pinch, traveling dots.
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
// still draws the older braid (labeled outer columns, a central pinch with
// animated energy dots), not [TxFlowGraph]'s tree, and derives everything
// from the local transaction fields the caller passes in. It never hits the network,
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
