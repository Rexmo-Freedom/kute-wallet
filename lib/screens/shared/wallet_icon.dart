import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Wallet visual config resolved from walletType string.
class WalletVisual {
  final String? svgAsset;
  final IconData icon;
  final Color color;
  final bool showLockBadge;

  const WalletVisual({
    this.svgAsset,
    required this.icon,
    required this.color,
    this.showLockBadge = false,
  });

  /// Resolves the correct icon/SVG/color for a wallet based on its properties.
  /// Matches the Add Wallet screen exactly.
  static WalletVisual fromWallet({
    required String walletType,
    required bool isHardware,
    required bool isWatchOnly,
    bool isSigner = false,
    required bool isDark,
  }) {
    // Signer device
    if (isSigner) {
      return const WalletVisual(
        svgAsset: 'lib/assets/kute_dog.svg',
        icon: Icons.phonelink_lock_rounded,
        color: Color(0xFFF7931A),
        showLockBadge: true,
      );
    }

    // Watch-only (non-hardware)
    if (isWatchOnly && !isHardware) {
      return const WalletVisual(
        icon: Icons.visibility_rounded,
        color: Color(0xFF007AFF),
      );
    }

    // Hardware wallets — match add_wallet_provider.dart exactly
    if (isHardware) {
      switch (walletType) {
        case 'kute':
          return const WalletVisual(
            svgAsset: 'lib/assets/kute_dog.svg',
            icon: Icons.smartphone_rounded,
            color: Color(0xFFF7931A),
            showLockBadge: true,
          );
        case 'ledger':
          return WalletVisual(
            svgAsset: 'lib/assets/ledger-logo.svg',
            icon: Icons.bluetooth_connected_rounded,
            color: isDark ? Colors.white : const Color(0xFF333333),
          );
        case 'jade':
          return const WalletVisual(
            svgAsset: 'lib/assets/jade-logo.svg',
            icon: Icons.qr_code_scanner_rounded,
            color: Color(0xFF00FFA3),
          );
        case 'passport':
          return const WalletVisual(
            svgAsset: 'lib/assets/passport-logo.svg',
            icon: Icons.airplane_ticket_rounded,
            color: Color(0xFF5ABCB9),
          );
        case 'seedsigner':
          return const WalletVisual(
            svgAsset: 'lib/assets/seedsigner-logo.svg',
            icon: Icons.qr_code_2_rounded,
            color: Color(0xFFFF6B00),
          );
        case 'krux':
          return const WalletVisual(
            icon: Icons.qr_code_2_rounded,
            color: Color(0xFFB388FF),
          );
        case 'keystone':
          return const WalletVisual(
            svgAsset: 'lib/assets/keystone-logo.svg',
            icon: Icons.qr_code_scanner_rounded,
            color: Color(0xFF4CAF50),
          );
        case 'generic':
          return const WalletVisual(
            icon: Icons.account_balance_wallet_rounded,
            color: Color(0xFF007AFF),
          );
        default:
          // Also covers legacy stored types from retired device
          // integrations (e.g. wallets created as 'coldcard' before
          // that vendor was dropped) — they degrade to the generic
          // hardware visual but keep working as watch-only wallets.
          return const WalletVisual(
            icon: Icons.usb_rounded,
            color: Color(0xFF4CAF50),
          );
      }
    }

    if (walletType == 'bitcoin') {
      return const WalletVisual(svgAsset: 'lib/assets/bitcoin-icon.svg',
          icon: Icons.currency_bitcoin_rounded, color: Color(0xFFF7931A));
    }

    // Hot wallet / Spark — use Kute dog mascot
    return const WalletVisual(
      svgAsset: 'lib/assets/kute_dog.svg',
      icon: Icons.bolt_rounded,
      color: AppColors.accent,
    );
  }
}

/// Renders a wallet icon matching the Add Wallet screen style.
/// Uses SVG logo when available, falls back to IconData.
class WalletIcon extends StatelessWidget {
  final WalletVisual visual;
  final double size;

  const WalletIcon({super.key, required this.visual, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = size.sp;

    Widget iconWidget;

    if (visual.svgAsset != null) {
      final isWhite = visual.color == Colors.white || visual.color == const Color(0xFF333333);
      iconWidget = SizedBox(
        width: s,
        height: s,
        child: SvgPicture.asset(
          visual.svgAsset!,
          width: s,
          height: s,
          colorFilter: isWhite
              ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
              : null,
        ),
      );
    } else {
      iconWidget = Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          color: visual.color.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(visual.icon, color: visual.color, size: s * 0.5),
      );
    }

    if (!visual.showLockBadge) return iconWidget;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: s * 0.38,
              height: s * 0.38,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.surface, width: 1.5),
              ),
              child: Icon(
                Icons.lock_rounded,
                color: visual.color,
                size: s * 0.22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
