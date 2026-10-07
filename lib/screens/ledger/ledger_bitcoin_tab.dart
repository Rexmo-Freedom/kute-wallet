// lib/screens/ledger/ledger_bitcoin_tab.dart
//
// Bitcoin tab of the Ledger account screen (Wallet hardening Phase 4,
// P4.4): today's wallet detail Bitcoin body, unchanged.

import 'package:flutter/widgets.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/shared/wallet_bitcoin_body.dart';

class LedgerBitcoinTab extends StatelessWidget {
  final WalletConfig wallet;

  const LedgerBitcoinTab({super.key, required this.wallet});

  @override
  Widget build(BuildContext context) => WalletBitcoinBody(wallet: wallet);
}
