import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';

enum BitcoinAddressType {
  nativeSegwit(
    label: 'Native SegWit',
    description: 'Lower fees, modern standard (bc1q...)',
    derivationPath: "m/84'/0'/0'",
  ),
  taproot(
    label: 'Taproot',
    description: 'Lowest fees, enhanced privacy (bc1p...)',
    derivationPath: "m/86'/0'/0'",
  ),
  nestedSegwit(
    label: 'Nested SegWit',
    description: 'Compatible with most wallets (3...)',
    derivationPath: "m/49'/0'/0'",
  ),
  legacy(
    label: 'Legacy',
    description: 'Traditional addresses, widely supported (1...)',
    derivationPath: "m/44'/0'/0'",
  );

  const BitcoinAddressType({
    required this.label,
    required this.description,
    required this.derivationPath,
  });

  final String label;
  final String description;
  final String derivationPath;
}

class WalletDeviceConfig {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String importTitle;
  final IconData icon;
  final Color color;
  final String? primaryActionLabel;
  final String? svgAsset;

  final bool isBluetooth;
  final bool isCable;
  final bool isQrCodeSigning;
  final bool isSdCard;
  final bool showLockBadge;

  /// Venue logos shown between the title and the chevron on the Add Wallet
  /// row (Wallet hardening Phase 4, P4.2). Only the Ledger row sets them,
  /// one per Ledger venue that is on (`ledgerInvestmentAllowed`).
  final List<String> venueBadges;

  /// [title] in [l10n]'s language. Device brand names stay as they are.
  String titleIn(AppLocalizations l10n) => switch (id) {
        'create_spark' => l10n.addWalletCreateNew,
        'recover_spark' => l10n.addWalletRecover,
        'generic' => l10n.addWalletOther,
        'track_address' => l10n.trackAddress,
        'bitcoin' => l10n.walletTypeBitcoin,
        _ => title,
      };

  /// [subtitle] in [l10n]'s language. Model lists stay as they are.
  String subtitleIn(AppLocalizations l10n) => switch (id) {
        'create_spark' => l10n.addWalletCreateNewSubtitle,
        'recover_spark' => l10n.addWalletRecoverSubtitle,
        'seedsigner' => l10n.addWalletSeedSignerSubtitle,
        'krux' => l10n.addWalletKruxSubtitle,
        'track_address' => l10n.addWalletTrackSubtitle,
        'bitcoin' => l10n.btcSetupCreateOrRecover,
        _ => subtitle,
      };

  /// [importTitle] in [l10n]'s language.
  String importTitleIn(AppLocalizations l10n) => switch (id) {
        'create_spark' => l10n.addWalletCreateNew,
        'recover_spark' => l10n.addWalletRecover,
        'ledger' => l10n.connectLedger,
        'jade' => l10n.addWalletImportDevice('Jade'),
        'passport' => l10n.addWalletImportDevice('Passport'),
        'seedsigner' => l10n.addWalletImportDevice('SeedSigner'),
        'krux' => l10n.addWalletImportDevice('Krux'),
        'keystone' => l10n.addWalletImportDevice('Keystone'),
        'generic' => l10n.addWalletImportWallet,
        'track_address' => l10n.trackAddress,
        _ => importTitle,
      };

  const WalletDeviceConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.importTitle,
    required this.icon,
    required this.color,
    this.primaryActionLabel,
    this.svgAsset,
    this.isBluetooth = false,
    this.isCable = false,
    this.isQrCodeSigning = false,
    this.isSdCard = false,
    this.showLockBadge = false,
    this.venueBadges = const [],
  });
}
