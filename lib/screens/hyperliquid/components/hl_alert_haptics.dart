// lib/screens/hyperliquid/components/hl_alert_haptics.dart
//
// The haptic an Investing alert banner arrives with (HlTradeAlertsHost
// `_show`, once per banner): warnings feel nothing like fills.

import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/services/kute_haptics.dart';

export 'package:kute/services/kute_haptics.dart' show KuteHaptics;

/// Warnings (liquidation, liquidation risk, a stop-loss near, a funding
/// spike, a venue cancel) get the warning pattern; a fill and a
/// take-profit the fill tap; everything else (a stop-loss or a trigger
/// firing, a level coming near) the light notice.
KuteHaptic hlAlertHaptic(HlTradeAlertType type) {
  if (type.isWarning) return KuteHaptic.warning;
  return switch (type) {
    HlTradeAlertType.filled || HlTradeAlertType.takeProfit => KuteHaptic.fill,
    _ => KuteHaptic.notice,
  };
}
