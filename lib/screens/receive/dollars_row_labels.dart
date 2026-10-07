// lib/screens/receive/dollars_row_labels.dart
//
// The dollar balance wears plain dollars on every row a person reads.
// The catalogue's own spelling of the token, and of the rail it settles
// on, is internal: it stays on [OrchestraReceiveOption.assetCode] and
// [OrchestraReceiveOption.chain], which are what the deposit address is
// minted with, and never reaches a label.
//
// Its own file because both receive screens need it: the dollar row is
// an ordinary source for a BITCOIN receive too, so the bitcoin picker
// has to rename it just as the dollars picker does.

import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_routes.dart' show isOrchestraUsdRoute;

OrchestraReceiveOption dollarsRowLabels(
    OrchestraReceiveOption option, AppLocalizations l10n) {
  if (!isOrchestraUsdRoute(option.chain, option.assetCode)) return option;
  return OrchestraReceiveOption(
    assetCode: option.assetCode,
    displayName: l10n.assetDollars,
    displaySymbol: 'USD',
    chain: option.chain,
    chainDisplayName: l10n.instant,
    decimals: option.decimals,
    chainIconUrl: option.chainIconUrl,
    assetIconUrl: option.assetIconUrl,
    reusableAddress: option.reusableAddress,
  );
}
