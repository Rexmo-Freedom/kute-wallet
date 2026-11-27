// The exposure rule (lib/services/hyperliquid/hl_exposure_rule.dart) asks
// for the position on a market before an order is approved, funded or
// placed, and refuses when it cannot be read. Tests whose fake account has
// no address read it as known and flat with this override; tests of the
// rule itself use the real reader or their own.

import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hlHeldPositionProvider;
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';

final hlFlatPositionsOverride = hlHeldPositionProvider
    .overrideWithValue((_) => const HlHeldPosition.flat());
