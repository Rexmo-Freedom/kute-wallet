// lib/screens/home/shell_wallet_screen.dart
//
// The first shell tab when it is showing a wallet other than the spending
// account. No app bar and no back button (user decision September 2026):
// the wallet is a TAB in the existing top strip, so the only chrome it
// needs is the space the floating nav bar occupies.
//
// The body is the same on-chain Bitcoin body the pushed detail screen
// rendered ([WalletBitcoinBody], which the Ledger Bitcoin tab also reuses),
// with the same dock. For a Ledger wallet the Investing and Predictions
// venues are the strip's other two tabs (see shell_venue_tabs.dart), not an
// inner tab row.
//
// Wallet scoping (BDK scope, viewed wallet, carousel scope) is applied by
// [MainScreen] off [shellWalletIdProvider], never from this widget's
// lifecycle, so a tab swap never writes providers mid-teardown.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/home/home_wallet_switcher.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/wallet_bitcoin_body.dart';
import 'package:kute/theme/app_theme.dart';

/// Vertical room the floating [KuteTopNavBar] needs above a tab body. Same
/// value the Home and Hyperliquid tab pages reserve with their top sliver.
const double kShellTopBarSpacing = 64;

class ShellWalletScreen extends ConsumerWidget {
  const ShellWalletScreen({super.key, required this.wallet});

  final WalletConfig wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: AppDecorations.screenGradient(context),
      // Home's dock mount: frost band + floating dock, bound to the wallet
      // this tab is showing.
      child: KuteDockHost(
        dockBuilder: (onHeightChanged) => WalletBitcoinActionBar(
          wallet: wallet,
          onHeightChanged: onHeightChanged,
          onSearch: () => showKuteSearch(context,
              walletId: wallet.id, source: 'wallet_detail'),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kShellTopBarSpacing.h),
              if (needsWalletBackup(wallet))
                Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
                  child: SecurityActionCard(walletId: wallet.id),
                ),
              Expanded(child: WalletBitcoinBody(wallet: wallet)),
            ],
          ),
        ),
      ),
    );
  }
}
