// Account abstraction for the home / action screens.
//
// One `Account` represents a thing the user can act on — send from,
// receive into, deposit to, move between, fund predictions with, etc.
// It's wallet-and-asset specific so the spending wallet shows up as
// TWO accounts (BTC + USDC) since they live on different chains and
// route through different rails.
//
// Capability flags encode what each account supports so the action
// screens (Send / Receive / Move / Pay Link / Deposit / bet slip)
// can render the right affordances and the picker can filter to
// only accounts that are valid sources/destinations for the current
// action — without re-checking `isHardware && !isWatchOnly && ...`
// scattered everywhere.
//
// Add a new account type (fiat, debit card, exchange link) =
//   1. New variant of `Account`
//   2. Define its capability flags
//   3. Wire it into `accountsListProvider`
// Every screen picks it up automatically.

import 'package:flutter/material.dart';
import 'package:kute/models/settings_model.dart';

/// What operations an Account supports. Used both for filtering in
/// the picker and for muting / hiding chips in the action row.
class AccountCapabilities {
  final bool canSend;
  final bool canReceive;
  final bool canDeposit;
  final bool canMove;
  final bool canPayLink;
  /// Can fund a Polymarket prediction directly. Currently only the
  /// USDC spending account, but the BTC spending account becomes
  /// eligible once the auto-swap path is wired (Phase 4 territory).
  final bool canFundPredictions;
  /// Can be offered swap / cross-chain / alt-asset options (Orchestra
  /// routes, receive-in-other-crypto grids, exchange entries). Only
  /// the Spark spending accounts qualify: hardware, watch-only and
  /// tracked-address wallets are on-chain-bitcoin-only surfaces —
  /// they get plain BTC send/receive and nothing else.
  final bool canSwap;

  const AccountCapabilities({
    this.canSend = false,
    this.canReceive = false,
    this.canDeposit = false,
    this.canMove = false,
    this.canPayLink = false,
    this.canFundPredictions = false,
    this.canSwap = false,
  });

  static const none = AccountCapabilities();
}

/// Sealed-style base — Dart doesn't have first-class sealed classes
/// before 3.0; using `sealed` keyword here would limit future
/// downgrades. Sub-types are restricted to this library by
/// convention.
abstract class Account {
  /// Unique identifier across all accounts. Wallet variants append
  /// the asset to disambiguate: e.g., `spending-<walletId>-btc`,
  /// `spending-<walletId>-usdc`. Cold wallets stay simple:
  /// `cold-<walletId>`.
  String get id;

  /// User-facing name. "Bitcoin", "USDC", "Ledger Nano X", etc.
  String get name;

  /// Short asset label for badges/subtitle. "Bitcoin" / "USDC" /
  /// type-specific ("Hardware", "Watch-only", "Tracked").
  String get subtitle;

  /// Path to the SVG asset that represents this account in pickers
  /// and tiles. `lib/assets/bitcoin-icon.svg`, `lib/assets/usdc.svg`,
  /// etc.
  String get iconAsset;

  /// Accent color used for the card border / pager dot / pill.
  Color get accent;

  /// Capability bundle — what actions this account supports.
  AccountCapabilities get capabilities;

  /// Underlying wallet config. Null only for synthetic accounts
  /// (e.g., a future "All accounts" virtual aggregate that doesn't
  /// map to one wallet).
  WalletConfig? get wallet;
}

const Color _kBtcOrange = Color(0xFFF7931A);
const Color _kUsdcBlue = Color(0xFF2775CA);
const Color _kColdGrey = Color(0xFF6B7280);

class BtcSpendingAccount extends Account {
  @override
  final WalletConfig wallet;
  BtcSpendingAccount(this.wallet);

  @override
  String get id => 'spending-${wallet.id}-btc';
  @override
  String get name => 'Bitcoin';
  @override
  String get subtitle => 'Spending';
  @override
  String get iconAsset => 'lib/assets/bitcoin-icon.svg';
  @override
  Color get accent => _kBtcOrange;
  @override
  AccountCapabilities get capabilities => const AccountCapabilities(
        canSend: true,
        canReceive: true,
        canDeposit: true,
        canMove: true,
        canPayLink: true,
        // Bitcoin → USDC conversion happens at place-time once the
        // auto-swap path lands. For now, predictions require explicit
        // USDC; the bet slip's "switch account" header lets the user
        // pick USDC if they're on this card.
        canFundPredictions: false,
        canSwap: true,
      );
}

class UsdcSpendingAccount extends Account {
  @override
  final WalletConfig wallet;
  UsdcSpendingAccount(this.wallet);

  @override
  String get id => 'spending-${wallet.id}-usdc';
  // The dollar account is called USD on screen — in the account picker
  // the venue funding flows open, in the switcher pill, everywhere. The
  // class, the id and the events keep 'usdc': the rail did not change.
  @override
  String get name => 'USD';
  @override
  String get subtitle => 'Spending';
  @override
  String get iconAsset => 'lib/assets/usdc.svg';
  @override
  Color get accent => _kUsdcBlue;
  @override
  AccountCapabilities get capabilities => const AccountCapabilities(
        canSend: true,
        canReceive: true,
        canDeposit: true,
        canMove: true,
        canPayLink: true,
        canFundPredictions: true,
        canSwap: true,
      );
}

enum ColdAccountKind { hardware, watchOnly, tracked, signer, software }

class BtcColdAccount extends Account {
  @override
  final WalletConfig wallet;
  final ColdAccountKind kind;
  BtcColdAccount(this.wallet, this.kind);

  @override
  String get id => 'cold-${wallet.id}';
  @override
  String get name => wallet.name.isNotEmpty ? wallet.name : 'Bitcoin wallet';
  @override
  String get subtitle => switch (kind) {
        ColdAccountKind.hardware => 'Hardware',
        ColdAccountKind.watchOnly => 'Watch-only',
        ColdAccountKind.tracked => 'Tracked',
        ColdAccountKind.signer => 'Signer',
        ColdAccountKind.software => 'Bitcoin',
      };
  @override
  String get iconAsset => 'lib/assets/bitcoin-icon.svg';
  @override
  Color get accent => _kColdGrey;
  @override
  AccountCapabilities get capabilities => switch (kind) {
        // Signer is a paired remote — primary doesn't hold its keys,
        // so it's neither a Send source nor has its own receive
        // address. Filtered out of both pickers at the call site.
        ColdAccountKind.signer => const AccountCapabilities(
            canSend: true,
            canReceive: true,
          ),
        // Hardware + watch-only can be Send sources: the app builds
        // an unsigned PSBT, the user signs it externally on the
        // device (USB / scan-and-paste). confirm_send.dart's
        // `isExternalSigner` path handles this.
        ColdAccountKind.hardware ||
        ColdAccountKind.watchOnly ||
        ColdAccountKind.software =>
          const AccountCapabilities(
            canSend: true,
            canReceive: true,
          ),
        // Tracked = address-only (no keys, no PSBT path) → receive-only.
        ColdAccountKind.tracked =>
          const AccountCapabilities(canReceive: true),
      };
}
