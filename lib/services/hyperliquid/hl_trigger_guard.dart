// lib/services/hyperliquid/hl_trigger_guard.dart
//
// The last check on a protective trigger (a stop loss or take profit that
// closes a position) before it is signed: the venue triggers on the mark,
// so a trigger already past the price fires at once, which is never what a
// protective order is for. The sheets check it as the person types
// (hl_protect_rules.dart) and again after the approval; the trading
// notifier checks it once more against the freshest price it has, right
// before signing, and refuses with nothing sent.

/// A protective trigger the price has crossed since it was checked: thrown
/// before anything is signed. [closeIsBuy] is the closing side (a buy
/// closes a short), [tpsl] 'sl' or 'tp', [mark] the price it was read at.
class HlTriggerCrossedException implements Exception {
  const HlTriggerCrossedException(
      {required this.closeIsBuy, required this.tpsl, required this.mark});

  final bool closeIsBuy;
  final String tpsl;
  final double mark;

  @override
  String toString() => 'HlTriggerCrossedException($tpsl)';
}

/// Whether a trigger closing on [closeIsBuy] at [trigger] is on the wrong
/// side of [mark] (or at it): a sell stop at or over the price, a buy stop
/// at or under it; a sell take at or under it, a buy take at or over it.
/// False without a price.
bool hlTriggerCrossed({
  required bool closeIsBuy,
  required String tpsl,
  required double trigger,
  required double mark,
}) {
  if (!(mark > 0) || !(trigger > 0)) return false;
  if (tpsl == 'sl') return closeIsBuy ? trigger <= mark : trigger >= mark;
  if (tpsl == 'tp') return closeIsBuy ? trigger >= mark : trigger <= mark;
  return false;
}
