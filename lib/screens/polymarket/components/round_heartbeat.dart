// lib/screens/polymarket/components/round_heartbeat.dart
//
// The final-seconds heartbeat of a 5 / 15 minute round: while the round's
// sheet is the screen in front, the app is foregrounded and the spending
// wallet holds a position in that round, one "lub-dub" a second for the
// last ten seconds ([RoundHeartbeatGate]). Draws nothing of its own.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/services/haptic_gates.dart';
import 'package:kute/services/kute_haptics.dart';

class RoundHeartbeat extends ConsumerStatefulWidget {
  const RoundHeartbeat({super.key, required this.asset, required this.child});

  /// The round's asset ('BTC'), as [cryptoPredictProvider] is keyed.
  final String asset;
  final Widget child;

  @override
  ConsumerState<RoundHeartbeat> createState() => _RoundHeartbeatState();
}

class _RoundHeartbeatState extends ConsumerState<RoundHeartbeat> {
  final RoundHeartbeatGate _gate = RoundHeartbeatGate();

  void _onTick(CryptoPredictState? round) {
    final event = round?.event;
    if (round == null || event == null) return;
    final tokens = {event.upTokenId, event.downTokenId}
      ..removeWhere((t) => t == null || t.isEmpty);
    final holds = tokens.isNotEmpty &&
        ref
            .read(polymarketActivePositionsProvider)
            .any((p) => p.size > 0 && tokens.contains(p.tokenId));
    if (_gate.due(
      secondsRemaining: round.secondsRemaining,
      holdsPosition: holds,
      // A bet slip or any other route on top hides the round.
      visible: ModalRoute.of(context)?.isCurrent ?? true,
      foreground: KuteHaptics.isForeground,
    )) {
      KuteHaptics.play(KuteHaptic.heartbeat);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<CryptoPredictState>>(
      cryptoPredictProvider(widget.asset),
      (_, next) => _onTick(next.asData?.value),
    );
    return widget.child;
  }
}
