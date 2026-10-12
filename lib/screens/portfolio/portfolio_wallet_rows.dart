// lib/screens/portfolio/portfolio_wallet_rows.dart
//
// The Portfolio's Wallet section: the spending account's bitcoin and
// dollars as two rows on the portfolio cards' frame (HlPortfolioCard, the
// spot holding's card), so they read like the positions under them. The
// money's mark where a market's logo sits, the account's name over the
// native amount, and on the right what it is worth in the chosen
// currency. Both honour hidden balances. A tap opens that account's own
// tab (Home for bitcoin, Dollars for dollars).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';

/// The spending account's bitcoin in sats: Home's hero figure (Spark plus
/// on-chain), from the same provider.
final portfolioBitcoinSatsProvider = Provider<int>((ref) {
  final balance = ref.watch(balanceNotifierProvider);
  return balance.sparkBitcoinbalance + balance.onChainBtcBalance;
});

/// What a hidden balance shows in its place (Home's mask).
const String kPortfolioHiddenAmount = '••••••';

/// The Wallet section's rows: Bitcoin, and Dollars when the account has
/// them ([showDollars]).
class PortfolioWalletRows extends StatelessWidget {
  const PortfolioWalletRows({super.key, required this.showDollars});

  final bool showDollars;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BitcoinRow(key: ValueKey('portfolio-wallet-bitcoin')),
          if (showDollars)
            const _DollarsRow(key: ValueKey('portfolio-wallet-dollars')),
        ],
      );
}

class _BitcoinRow extends ConsumerWidget {
  const _BitcoinRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sats = ref.watch(portfolioBitcoinSatsProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final fiatPerBtc = ref.watch(selectedCurrencyProvider(currency)).toDouble();
    final raw = sats / 1e8 * fiatPerBtc;
    // A rate not loaded yet must not throw in NumberFormat (Home's guard).
    final fiat = raw.isFinite ? raw : 0.0;
    final unit = btcFormat == 'sats' ? 'sats' : 'BTC';
    return HlPortfolioCard(
      coin: 'BTC',
      leading: AssetIcon(assetCode: 'BTC', size: 36.w),
      name: context.l10n.bitcoin,
      caption: visible
          ? '${sats.toFormattedString(btcFormat)} $unit'
          : kPortfolioHiddenAmount,
      trailing: PortfolioCardValue(
        value: visible
            ? NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
                .format(fiat)
            : kPortfolioHiddenAmount,
      ),
      onTap: () => _openAccount(context, ref, '/home'),
    );
  }
}

class _DollarsRow extends ConsumerWidget {
  const _DollarsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dollars = ref.watch(usdBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    // The figure follows the chosen currency, as every amount on the
    // Portfolio does; the dollars themselves are the caption only when
    // that currency is not the dollar (otherwise it would say it twice).
    return HlPortfolioCard(
      coin: 'USD',
      leading: AssetIcon(assetCode: 'USD', size: 36.w),
      name: context.l10n.usdAccountTab,
      caption: currency == 'USD'
          ? ''
          : visible
              ? NumberFormat.simpleCurrency(name: 'USD', decimalDigits: 2)
                  .format(dollars)
              : kPortfolioHiddenAmount,
      trailing: PortfolioCardValue(
        value:
            visible ? formatPolyAmount(ref, dollars) : kPortfolioHiddenAmount,
      ),
      onTap: () => _openAccount(context, ref, '/usd'),
    );
  }
}

/// Opens the spending account's tab at [path] from the Portfolio: closes
/// the Portfolio and switches the shell. When another wallet holds the
/// first tab, bringing the spending account back asks the same step-up
/// the Financial hub's wallet switch asks.
Future<void> _openAccount(
    BuildContext context, WidgetRef ref, String path) async {
  HapticFeedback.selectionClick();
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  if (ref.read(shellWalletIdProvider) != null) {
    final spending = pickSpendingWallet(ref.read(settingsProvider));
    if (spending == null) return;
    final approved = await approveLocalAction(
      context,
      ref,
      intent: walletSwitchIntent(spending.id),
      reason: context.l10n.stepUpReasonSwitchWallet(spending.name),
    );
    if (!approved || !context.mounted) return;
    ref.read(shellWalletIdProvider.notifier).state = null;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();
  router.go(path);
}
