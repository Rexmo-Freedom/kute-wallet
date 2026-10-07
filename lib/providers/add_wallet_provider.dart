import 'package:kute/constants/feature_flags.dart';
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show
        ledgerInvestingCapability,
        ledgerInvestmentAllowed,
        ledgerPredictionsCapability;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Venue logos on the Ledger row, in tab order (Investing, Predictions).
const List<String> kLedgerVenueBadgeAssets = [
  'lib/assets/hyperliquid-logo.svg',
  'lib/assets/polymarket-logo.svg',
];

class AddWalletState {
  final List<WalletDeviceConfig> hotWallets;
  final List<WalletDeviceConfig> coldWallets;
  final List<WalletDeviceConfig> trackingWallets;
  final String? selectedWalletType;
  final String? selectedWalletConfigId;

  const AddWalletState({
    this.hotWallets = const [],
    this.coldWallets = const [],
    this.trackingWallets = const [],
    this.selectedWalletType,
    this.selectedWalletConfigId,
  });

  AddWalletState copyWith({
    List<WalletDeviceConfig>? hotWallets,
    List<WalletDeviceConfig>? coldWallets,
    List<WalletDeviceConfig>? trackingWallets,
    String? selectedWalletType,
    String? selectedWalletConfigId,
  }) {
    return AddWalletState(
      hotWallets: hotWallets ?? this.hotWallets,
      coldWallets: coldWallets ?? this.coldWallets,
      trackingWallets: trackingWallets ?? this.trackingWallets,
      selectedWalletType: selectedWalletType ?? this.selectedWalletType,
      selectedWalletConfigId: selectedWalletConfigId ?? this.selectedWalletConfigId,
    );
  }
}

class AddWalletNotifier extends StateNotifier<AddWalletState> {
  AddWalletNotifier() : super(const AddWalletState()) {
    _initializeWallets();
  }

  void _initializeWallets() {
    final hot = [
      const WalletDeviceConfig(
        id: 'create_spark',
        type: 'spark',
        title: "Create New Wallet",
        subtitle: "Instant setup for daily spending.",
        importTitle: 'Create Spark',
        icon: Icons.add_circle_outline_rounded,
        color: Color(0xFFF7931A),
        isBluetooth: false, isCable: false, isQrCodeSigning: false, isSdCard: false,
      ),
      const WalletDeviceConfig(
        id: 'recover_spark',
        type: 'spark',
        title: "Recover Wallet",
        subtitle: "Restore using 12/24 seed words.",
        importTitle: 'Recover Spark',
        icon: Icons.history_rounded,
        color: Color(0xFFF7931A),
        isBluetooth: false, isCable: false, isQrCodeSigning: false, isSdCard: false,
      ),
    ];

    final cold = [
      WalletDeviceConfig(
        id: 'ledger',
        type: 'ledger',
        title: "Ledger",
        subtitle: "Nano X, Stax, Flex",
        importTitle: 'Connect Ledger',
        icon: Icons.bluetooth_connected_rounded,
        color: Colors.white,
        primaryActionLabel: 'Connect Ledger',
        svgAsset: 'lib/assets/ledger-logo.svg',
        isBluetooth: true,
        isCable: true,
        isQrCodeSigning: false,
        isSdCard: false,
        // Hyperliquid and Polymarket work with a Ledger (Phase 4, P4.2).
        // Each badge only while that Ledger venue is on (its runtime
        // capability); with both off the Ledger row is a plain bitcoin
        // hardware wallet.
        venueBadges: [
          if (kLedgerInvestingEnabled &&
              ledgerInvestmentAllowed(ledgerInvestingCapability))
            kLedgerVenueBadgeAssets[0],
          if (kLedgerInvestingEnabled &&
              ledgerInvestmentAllowed(ledgerPredictionsCapability))
            kLedgerVenueBadgeAssets[1],
        ],
      ),
      const WalletDeviceConfig(
        id: 'jade',
        type: 'jade',
        title: "Blockstream Jade",
        subtitle: "Jade, Jade Plus",
        importTitle: 'Import Jade',
        icon: Icons.bluetooth_connected_rounded,
        // Blockstream cyan — matches the dashed-rings brand mark in
        // jade-logo.svg (used only as the icon fallback tint; the
        // SVG carries its own colors).
        color: Color(0xFF00C3FF),
        svgAsset: 'lib/assets/jade-logo.svg',
        isBluetooth: true,
        isCable: false,
        isQrCodeSigning: true,
        isSdCard: false,
        primaryActionLabel: 'Connect Jade',
      ),
      const WalletDeviceConfig(
        id: 'passport',
        type: 'passport',
        title: "Foundation Passport",
        subtitle: "Passport (Batch 2)",
        importTitle: 'Import Passport',
        icon: Icons.airplane_ticket_rounded,
        // Foundation's warm clay tone — matches the tri-arc mark
        // baked into passport-logo.svg.
        color: Color(0xFFDA8E74),
        svgAsset: 'lib/assets/passport-logo.svg',
        primaryActionLabel: 'Scan QR Code',
        isBluetooth: false,
        isCable: true,
        isQrCodeSigning: true,
        isSdCard: true,
      ),
      const WalletDeviceConfig(
        id: 'seedsigner',
        type: 'seedsigner',
        title: "SeedSigner",
        subtitle: "Air-gapped DIY signer",
        importTitle: 'Import SeedSigner',
        icon: Icons.qr_code_2_rounded,
        // SeedSigner's official orange (#FF7300), as in the pill
        // wordmark SVG.
        color: Color(0xFFFF7300),
        svgAsset: 'lib/assets/seedsigner-logo.svg',
        primaryActionLabel: 'Scan QR Code',
        isBluetooth: false,
        isCable: false,
        isQrCodeSigning: true,
        isSdCard: false,
      ),
      const WalletDeviceConfig(
        id: 'krux',
        type: 'krux',
        title: "Krux",
        subtitle: "Open-source air-gapped signer",
        importTitle: 'Import Krux',
        icon: Icons.qr_code_2_rounded,
        // Krux's mark is monochrome (k-with-cross); Colors.white
        // flags it for the textPrimary tint path so it adapts to
        // both themes — same treatment as Ledger.
        color: Colors.white,
        svgAsset: 'lib/assets/krux-logo.svg',
        primaryActionLabel: 'Scan QR Code',
        isBluetooth: false,
        isCable: false,
        isQrCodeSigning: true,
        isSdCard: false,
      ),
      const WalletDeviceConfig(
        id: 'keystone',
        type: 'keystone',
        title: "Keystone",
        subtitle: "Keystone 3 Pro / Essential",
        importTitle: 'Import Keystone',
        icon: Icons.qr_code_scanner_rounded,
        // Keystone blue — matches the double-wedge brand mark.
        color: Color(0xFF1F5AFF),
        svgAsset: 'lib/assets/keystone-logo.svg',
        primaryActionLabel: 'Scan QR Code',
        isBluetooth: false,
        isCable: false,
        isQrCodeSigning: true,
        isSdCard: false,
      ),
      const WalletDeviceConfig(
        id: 'generic',
        type: 'generic',
        title: "Other Wallet",
        subtitle: "BitBox02, Trezor, Specter, etc.",
        importTitle: 'Import Wallet',
        icon: Icons.account_balance_wallet_rounded,
        // Monochrome outline mark — Colors.white flags the
        // textPrimary tint path (see _DeviceTile / WalletIcon).
        color: Colors.white,
        svgAsset: 'lib/assets/generic-wallet-logo.svg',
        primaryActionLabel: 'Scan QR Code',
        isBluetooth: false,
        isCable: true,
        isQrCodeSigning: true,
        isSdCard: true,
      ),
    ];

    final tracking = [
      const WalletDeviceConfig(
        id: 'track_address',
        type: 'external_address',
        title: "Track Address",
        subtitle: "Monitor any Bitcoin address (view only).",
        importTitle: 'Track Address',
        icon: Icons.visibility_rounded,
        color: Color(0xFF007AFF),
        isBluetooth: false, isCable: false, isQrCodeSigning: false, isSdCard: false,
      ),
    ];

    // Pull the popular vendors to the top of the hardware list so
    // first-time users land on the most likely choice. The cold
    // entries above are kept in their historical source order to
    // minimise diff churn — the ordering for the picker is a
    // separate concern, applied here. Any id we don't list here
    // (future additions) appends in source order at the end.
    const coldOrder = [
      'ledger',
      'jade',
      'keystone',
      'passport',
      'seedsigner',
      'krux',
      'generic',
    ];
    final byId = {for (final c in cold) c.id: c};
    final coldSorted = <WalletDeviceConfig>[
      for (final id in coldOrder)
        if (byId.containsKey(id)) byId[id]!,
      ...cold.where((c) => !coldOrder.contains(c.id)),
    ];

    state = state.copyWith(hotWallets: hot, coldWallets: coldSorted, trackingWallets: tracking);
  }

  void selectWallet(String configId, String walletType) {
    state = state.copyWith(
      selectedWalletConfigId: configId,
      selectedWalletType: walletType,
    );
  }
}

final addWalletProvider = StateNotifierProvider<AddWalletNotifier, AddWalletState>((ref) {
  return AddWalletNotifier();
});