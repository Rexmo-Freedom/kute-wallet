// Account aggregation provider.
//
// Single source of truth for "every account the user can interact
// with on this device". Each consumer (action screens, pickers,
// home cards) reads this list, filters by capability for its use
// case, and renders without needing to know the WalletConfig flag
// soup (isHardware && !isWatchOnly && !isExternalAddress && …).
//
// Today: derived from `settingsProvider.wallets`, with the unique
// spending wallet expanded into BTC + USDC sub-accounts.
//
// Future: append fiat accounts, debit-card accounts, exchange-linked
// accounts here. The shape (`Account` sealed class) absorbs new
// types without action screens needing to know.

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/account.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/home/components/wallet_cards.dart'
    show selectedWalletCardProvider, WalletCardType;

/// Flat list of every Account the user has, in render order:
///   1. Spending BTC
///   2. Spending USDC
///   3. Hardware wallets (in creation order)
///   4. Watch-only wallets
///   5. Tracked addresses
///   6. Signer-only wallets (paired devices)
final accountsListProvider = Provider<List<Account>>((ref) {
  final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
  final accounts = <Account>[];

  // Spending wallet — Bitcoin only. The legacy USDC sub-account was
  // surfaced on Send / Receive pickers as a separate "USDC · Spending"
  // tile that routed to the Polymarket Safe. Always-BTC architecture:
  // USDC is plumbing handled by Orchestra under the hood,
  // never a user-pickable destination. `UsdcSpendingAccount` is kept
  // in `models/account.dart` for narrow internal callers but is no
  // longer added to the account list, so it can't appear in any
  // generic picker.
  for (final w in wallets) {
    final isSpending = w.isSparkWallet;
    if (isSpending) {
      accounts.add(BtcSpendingAccount(w));
    }
  }
  for (final w in wallets) {
    if (w.isBitcoinSoftware) accounts.add(BtcColdAccount(w, ColdAccountKind.software));
  }
  for (final w in wallets) {
    if (w.isHardware && !w.isExternalAddress) {
      accounts.add(BtcColdAccount(w, ColdAccountKind.hardware));
    }
  }
  for (final w in wallets) {
    if (w.isWatchOnly && !w.isHardware && !w.isExternalAddress) {
      accounts.add(BtcColdAccount(w, ColdAccountKind.watchOnly));
    }
  }
  for (final w in wallets) {
    if (w.isExternalAddress) {
      accounts.add(BtcColdAccount(w, ColdAccountKind.tracked));
    }
  }
  for (final w in wallets) {
    if (w.isSigner) {
      accounts.add(BtcColdAccount(w, ColdAccountKind.signer));
    }
  }

  return accounts;
});

/// Whether the currently-foregrounded account may be offered swap /
/// cross-chain / alt-asset options it would have to SIGN for.
/// Hardware, watch-only and tracked-address wallets hold bitcoin and
/// nothing else, so they get no swap or exchange entries and no
/// cross-chain send destinations. Read this at every such entry point
/// (send destination picker, deposit-in-crypto, exchange sheets) so
/// the gating lives in one place instead of re-deriving the wallet
/// flag soup per screen. Defaults to false when no account resolves —
/// swaps are an opt-in affordance, not a fallback.
///
/// TAKING a deposit is deliberately NOT behind this. A cold wallet
/// signs nothing to be paid: the sender pays Orchestra and bitcoin
/// arrives at an address the wallet already owns, through the one-time
/// quoted deposit address the receive screen offers
/// (confirm_receive.dart, one_time_deposit_sheet.dart). The receive
/// screen keeps this gate on the STANDING address rail, which only the
/// spending wallet can be handed.
final swapOffersEnabledProvider = Provider<bool>((ref) {
  final account = ref.watch(selectedAccountProvider);
  return account?.capabilities.canSwap ?? false;
});

/// The currently-foregrounded Account on Home, derived from the
/// existing `activeWalletId` + `selectedWalletCardProvider`. This is
/// the canonical "where the user is right now" — every action screen
/// (Receive / Send / Move / Pay Link / Deposit / bet slip) reads it
/// to know the default funding source.
///
/// Resolution order:
///   1. `bdkScopeWalletIdProvider` — when set (the user is inside a
///      hardware/watch-only detail surface), the scoped wallet wins
///      and Send / Move / Receive route against it.
///   2. `activeWalletId` — the spending wallet otherwise. Home's
///      carousel never flips this away from spending, so the default
///      always lands on the hot wallet.
final selectedAccountProvider = Provider<Account?>((ref) {
  final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
  final asset = ref.watch(selectedWalletCardProvider);

  // BDK scope override — surfaces the cold wallet's account record
  // whenever the user is inside the wallet detail screen or a flow
  // pushed from it. activeWalletId is intentionally not consulted in
  // this branch because the new architecture keeps it pinned to the
  // spending wallet at all times.
  final scopeId = ref.watch(bdkScopeWalletIdProvider);
  if (scopeId != null) {
    final scopeWallet = wallets.firstWhereOrNull((w) => w.id == scopeId);
    if (scopeWallet != null) {
      if (scopeWallet.isBitcoinSoftware) {
        return BtcColdAccount(scopeWallet, ColdAccountKind.software);
      }
      if (scopeWallet.isHardware) {
        return BtcColdAccount(scopeWallet, ColdAccountKind.hardware);
      }
      if (scopeWallet.isWatchOnly) {
        return BtcColdAccount(scopeWallet, ColdAccountKind.watchOnly);
      }
      if (scopeWallet.isExternalAddress) {
        return BtcColdAccount(scopeWallet, ColdAccountKind.tracked);
      }
      if (scopeWallet.isSigner) {
        return BtcColdAccount(scopeWallet, ColdAccountKind.signer);
      }
      // Spending-class wallet scoped (rare — wallet detail entry from
      // a non-cold row). Fall through to the activeWalletId path.
    }
  }

  final activeId =
      ref.watch(settingsProvider.select((s) => s.activeWalletId));
  final activeWallet =
      wallets.firstWhereOrNull((w) => w.id == activeId);
  if (activeWallet == null) return null;
  if (activeWallet.isBitcoinSoftware) {
    return BtcColdAccount(activeWallet, ColdAccountKind.software);
  }
  if (activeWallet.isHardware) {
    return BtcColdAccount(activeWallet, ColdAccountKind.hardware);
  }
  if (activeWallet.isWatchOnly) {
    return BtcColdAccount(activeWallet, ColdAccountKind.watchOnly);
  }
  if (activeWallet.isExternalAddress) {
    return BtcColdAccount(activeWallet, ColdAccountKind.tracked);
  }
  if (activeWallet.isSigner) {
    return BtcColdAccount(activeWallet, ColdAccountKind.signer);
  }
  return asset == WalletCardType.usdc
      ? UsdcSpendingAccount(activeWallet)
      : BtcSpendingAccount(activeWallet);
});
