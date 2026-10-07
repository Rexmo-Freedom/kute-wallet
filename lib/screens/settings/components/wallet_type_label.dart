// lib/screens/settings/components/wallet_type_label.dart
//
// The plain type label shared by the wallets list and the export picker:
// "Hardware wallet", "View only", "Tracked address", "Bitcoin wallet" or
// "Kute wallet". Never a mechanism (xpub, mempool, a vendor name).

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';

String walletTypeLabel(AppLocalizations l10n, WalletConfig wallet) {
  if (wallet.isBitcoinSoftware) return l10n.walletTypeBitcoin;
  if (wallet.isExternalAddress) return l10n.walletTypeTracked;
  if (wallet.isHardware) return l10n.walletTypeHardware;
  if (wallet.isWatchOnly) return l10n.walletTypeViewOnly;
  return l10n.walletTypeKute;
}
