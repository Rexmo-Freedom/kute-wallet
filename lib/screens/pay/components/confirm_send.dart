import 'package:kute/services/security/address_guard.dart';
import 'package:kute/screens/pay/components/bitcoin_coin_selection_sheet.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'dart:async';
import 'dart:io' show HandshakeException, SocketException;
import 'package:http/http.dart' show ClientException;
import 'package:intl/intl.dart';
import 'package:kute/services/bitcoin/bitcoin_fee_estimate_service.dart'
    show BitcoinFeeUnavailableException;
import 'package:kute/services/bitcoin/fee_draft_while_syncing.dart';
import 'package:kute/helpers/common_operation_methods.dart'
    show stripBitcoinAddress;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart'
    show SparkTransaction;
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/models/bitcoin_model.dart' show TransactionBuilder;
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/onchain/bitcoin_software_send.dart';
import 'package:kute/services/bitcoin/bitcoin_transaction_review.dart';
import 'package:kute/services/onchain/native_onchain_service.dart'
    show NativeOnchainService, OnchainException;
import 'package:kute/providers/bitcoin_labels_provider.dart';
import 'package:kute/providers/bitcoin_software_send_provider.dart';
import 'package:kute/models/onchain_types.dart' as onchain;
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:kute/services/sound_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/helpers/extension.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/models/breez/error_handling.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show
        OrchestraReceiveOption,
        OrchestraRoutesCatalog,
        RouteKey,
        orchestraChainIconUrl,
        orchestraAssetIconUrl;
import 'package:kute/providers/orchestra_supported_routes_provider.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/providers/bitcoin_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/address_receive_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/spark_contacts_provider.dart';
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/models/send_tx_model.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/screens/shared/account_switcher_pill.dart';
import 'package:kute/services/swap/swap_models.dart';
import 'package:kute/screens/pay/components/bitcoin_advanced_settings_sheet.dart';
import 'package:kute/screens/pay/components/watch_only_screen.dart';
import 'package:kute/screens/shared/amount_unit_picker.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/asset_network_picker.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show SafeSvgNetwork, kUsdMarkAsset;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/btc_amount_text.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/powered_by_badge.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/transaction_modal.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, AmountPercentChips, canonicalDecimalText;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' hide PaymentType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// The cross-chain Review's "Route details" sheet: the two legs of the
/// route and who settles it. Opened from the Route details line of the
/// quote card. Cross-chain routes are single-leg Orchestra deliveries
/// from bitcoin on Spark to the destination coin (orchestra_routes.dart).
void _showSendRouteDetails(
    BuildContext context, _DestAsset? destAsset, _DestNetwork? destNetwork) {
  const providerName = 'Orchestra';
  final l10n = context.l10n;
  const from = 'Bitcoin';
  final networkName = destNetwork?.name ?? destNetwork?.network ?? '—';
  final to = l10n.sendAssetOnNetwork(destAsset?.code ?? '', networkName);
  TrackingService.track('send_route_details_opened',
      params: {'provider': providerName.toLowerCase()});
  showAppBottomSheet<void>(
    context: context,
    builder: (ctx) => AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.sendRouteDetails,
            subtitle: l10n.sendRouteDetailsSubtitle,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetDetailRow(label: l10n.from, value: from),
                SheetDetailRow(label: l10n.to, value: to),
                SheetDetailRow(label: l10n.provider, value: providerName),
                SizedBox(height: 12.h),
                const PoweredByBadge(provider: providerName),
              ],
            ),
          ),
          SizedBox(height: 8.h),
          AppBottomSheetTextButton(
            text: l10n.done,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    ),
  );
}

// _SharedStepCta and _StepPageWrapper were extracted into
// `lib/screens/shared/stepper/stepper_widgets.dart` so they can be
// reused by `confirm_receive.dart`. Use `SharedStepCta` /
// `StepPageWrapper` from that import.

// The recipient field and its inline icon buttons live in
// shared/send/send_flow_widgets.dart (`SendRecipientField`), shared
// with the dollar send.

/// Inferred network/asset for an address. We don't run the full
/// `identifyInputTypeProvider` here (it's async + has side effects);
/// instead we do quick heuristics covering the common cases. The
/// router downstream still does the authoritative parse.
class _DetectedAddressInfo {
  final String label;
  final IconData icon;
  final Color color;
  final bool valid;
  const _DetectedAddressInfo({
    required this.label,
    required this.icon,
    required this.color,
    required this.valid,
  });
}

/// Maps an address to its consensus "rail family" so the destination
/// picker can hide incompatible networks. Stricter than
/// [_detectAddressType] for base58 strings — Tron/XRP/Solana are
/// disambiguated by leading char so a Tron address (`T...`) doesn't
/// fall through into the Solana bucket the way it would in the broader
/// detector. Anything we don't recognise returns `'unknown'` and the
/// picker keeps every Orchestra-routable destination (user takes the
/// risk).
String _addressRailFamily(String raw) => orchestraAddressFamily(raw);

/// Chain identifiers that are valid recipients for a given address rail
/// family. Keys are the values [_addressRailFamily] can return; values
/// are lower-cased chain slugs — the Orchestra catalog slugs the
/// picker feeds, plus older network spellings (we compare against
/// `network.toLowerCase()`). Synonyms (e.g. `arbitrum` vs
/// `arbitrum-one`) are listed explicitly because those spellings were
/// inconsistent across endpoints.
const Map<String, Set<String>> _eligibleNetworksForFamily =
    <String, Set<String>>{
  'evm': {
    ...kEvmAddressChains,
    'binancesmartchain',
    'arbitrumone',
    'arbitrum-one',
    'avalanchec',
    'avalanche-c',
    'linea',
    'mantle',
    'opbnb',
    'blast',
    'zksync',
    'zksync-era',
    'zksyncera',
    'sonic',
    'polygonzkevm',
    'scroll',
    'fantom',
    'celo',
  },
  'bitcoin': {'bitcoin'},
  'litecoin': {'litecoin'},
  'zcash': {'zcash'},
  'ton': {'ton'},
  'solana': {'solana'},
  'tron': {'tron'},
  'xrp': {'ripple', 'xrp', 'xrpl'},
  // Where the dollar balance settles. One chain, and the only thing
  // reachable there is the dollar row itself.
  'spark': {'spark'},
};

_DetectedAddressInfo _detectAddressType(String raw) {
  var addr = raw.trim();
  if (addr.isEmpty) {
    return const _DetectedAddressInfo(
      label: 'Address',
      icon: Icons.alternate_email_rounded,
      color: Color(0xFF8E93A1),
      valid: false,
    );
  }
  // Strip a leading URI scheme before classifying. Wallets, the iOS
  // share sheet and "Copy invoice" buttons hand us scheme-prefixed
  // payloads like `lightning:lnbc…`, `lightning:LNURL1…` or
  // `bitcoin:bc1…?amount=…`. The bare-prefix checks below
  // (`startsWith('lnbc')`, the `bc1` regex, …) would otherwise fall
  // through to "Unknown" and wrongly gate Continue behind the
  // cross-chain network picker. The Breez SDK parses the prefixed form
  // fine, so we only normalize here so detection agrees with it.
  addr = addr.replaceFirst(
      RegExp(r'^(lightning|bitcoin):(//)?', caseSensitive: false), '');
  // Drop any BIP21 / LUD query string (`bc1…?amount=…&lightning=…`) —
  // the rail is decided by the address itself and the anchored regexes
  // below require a clean tail.
  final qIdx = addr.indexOf('?');
  if (qIdx != -1) addr = addr.substring(0, qIdx);
  final lower = addr.toLowerCase();
  // Lightning invoice (Bolt11)
  if (lower.startsWith('lnbc') || lower.startsWith('lntb')) {
    return const _DetectedAddressInfo(
      label: 'Lightning invoice',
      icon: Icons.bolt_rounded,
      color: Color(0xFFB388FF),
      valid: true,
    );
  }
  // LNURL
  if (lower.startsWith('lnurl')) {
    return const _DetectedAddressInfo(
      label: 'LNURL',
      icon: Icons.bolt_rounded,
      color: Color(0xFFB388FF),
      valid: true,
    );
  }
  // Lightning address (user@domain)
  if (RegExp(r'^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+$').hasMatch(addr)) {
    return const _DetectedAddressInfo(
      label: 'Lightning address',
      icon: Icons.alternate_email_rounded,
      color: Color(0xFFB388FF),
      valid: true,
    );
  }
  // Bitcoin on-chain (bc1, 1, 3 prefixes — very rough)
  if (RegExp(r'^(bc1|tb1)[a-z0-9]{20,}$').hasMatch(lower) ||
      RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$').hasMatch(addr)) {
    return const _DetectedAddressInfo(
      label: 'Bitcoin on-chain',
      icon: Icons.currency_bitcoin_rounded,
      color: Color(0xFFF7931A),
      valid: true,
    );
  }
  // Spark address (typically prefixed `sp` / `spark`)
  if (lower.startsWith('sp1') ||
      lower.startsWith('sprt1') ||
      lower.startsWith('spark1')) {
    return const _DetectedAddressInfo(
      label: 'Spark address',
      icon: Icons.flash_on_rounded,
      color: Color(0xFFB388FF),
      valid: true,
    );
  }
  // EVM hex (Polygon / ETH / etc.)
  if (RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(addr)) {
    return const _DetectedAddressInfo(
      label: 'EVM address',
      icon: Icons.account_tree_rounded,
      color: Color(0xFF2775CA),
      valid: true,
    );
  }
  final family = orchestraAddressFamily(addr);
  if (const {'litecoin', 'zcash', 'tron', 'ton', 'xrp'}.contains(family)) {
    return _DetectedAddressInfo(
        label: orchestraChainDisplayName(family),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF2775CA),
        valid: true);
  }
  // Solana base58 (32–44 chars, no 0/I/l/O)
  if (RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(addr)) {
    return const _DetectedAddressInfo(
      label: 'Solana address',
      icon: Icons.brightness_7_rounded,
      color: Color(0xFF9945FF),
      valid: true,
    );
  }
  return const _DetectedAddressInfo(
    label: 'Unknown',
    icon: Icons.help_outline_rounded,
    color: Color(0xFF8E93A1),
    valid: false,
  );
}

/// Plain words for the badge under the address field. The routing
/// compares [_DetectedAddressInfo.label], so only the displayed string
/// changes here; the technical label stays in the Review nerd data.
String _detectedAddressDisplayLabel(
    BuildContext context, _DetectedAddressInfo detected) {
  final l10n = context.l10n;
  switch (detected.label) {
    case 'Lightning invoice':
    case 'LNURL':
      return l10n.sendDetectedLightningPayment;
    case 'Lightning address':
      return l10n.sendDetectedLightningAddress;
    case 'Bitcoin on-chain':
      return l10n.sendDetectedBitcoinAddress;
    case 'Spark address':
      return l10n.sendDetectedSpendingWalletAddress;
    case 'EVM address':
      return l10n.sendDetectedEthereumStyleAddress;
    case 'Solana address':
      return l10n.sendDetectedSolanaAddress;
    default:
      return detected.label;
  }
}

/// Subtle pill that appears below the address field once we've
/// identified what was pasted. Tells the user "we got this — sending
/// to a Bitcoin on-chain address" without needing them to manually
/// pick a network.
class _DetectedNetworkBadge extends StatelessWidget {
  final String address;
  final AppColorsExtension colors;
  const _DetectedNetworkBadge({required this.address, required this.colors});

  @override
  Widget build(BuildContext context) {
    final detected = _detectAddressType(address);
    if (!detected.valid) return const SizedBox.shrink();
    return SendDetectedBadge(
      label: _detectedAddressDisplayLabel(context, detected),
      icon: detected.icon,
      color: detected.color,
      identity: detected.label,
    );
  }
}

// The Send to list row and card, shared with the dollar send.
typedef _SendToListRow = SendToListRow;
typedef _SendToListCard = SendToListCard;

/// Slide-to-confirm gesture — drag the thumb from left to right past
/// 80 % of the track to fire `onConfirmed`. Feels deliberate for the
/// irreversible "send funds" action; anti-pattern for taps.
class _SlideToConfirm extends StatefulWidget {
  final AppColorsExtension colors;
  final String label;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onConfirmed;

  const _SlideToConfirm({
    required this.colors,
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.onConfirmed,
  });

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm>
    with SingleTickerProviderStateMixin {
  double _dragX = 0.0;
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    // Slow ambient shimmer over the label to invite the gesture —
    // ~2 s loop, restarts forever. Pauses while loading so the
    // spinner doesn't compete for attention. The decorative loop is
    // started in didChangeDependencies so we can honour the OS
    // "Reduce Motion" preference (MediaQuery isn't ready in initState).
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Accessibility: the shimmer is purely decorative (an invitation to
    // drag), so suppress the repeating loop when the user has asked the
    // OS to reduce motion. Stop it if it was running and the preference
    // flipped on; (re)start it otherwise.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      if (_shimmerCtrl.isAnimating) _shimmerCtrl.stop();
    } else if (!_shimmerCtrl.isAnimating) {
      _shimmerCtrl.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final h = 60.h;
    return LayoutBuilder(
      builder: (context, cons) {
        final maxDrag = cons.maxWidth - h;
        final progress = maxDrag > 0 ? (_dragX / maxDrag).clamp(0.0, 1.0) : 0.0;
        final disabled = !widget.enabled || widget.isLoading;
        return Opacity(
          opacity: disabled && !widget.isLoading ? 0.55 : 1.0,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  c.surfaceLight,
                  Color.lerp(c.surfaceLight, c.accent, 0.06)!,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(h / 2),
              border: Border.all(
                color: c.accent.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Filled accent gradient that grows as the user drags.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(h / 2),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              c.accent.withValues(alpha: 0.55),
                              c.accent.withValues(alpha: 0.28),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Label + shimmer + chevrons. Label fades out as the
                // progress grows so the visual focus shifts to the
                // moving thumb.
                Positioned.fill(
                  child: Center(
                    child: AnimatedOpacity(
                      duration: MediaQuery.of(context).disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      opacity: 1.0 - progress * 0.85,
                      child: widget.isLoading
                          ? LoadingAnimationWidget.staggeredDotsWave(
                              color: c.accent, size: 24.sp)
                          : AnimatedBuilder(
                              animation: _shimmerCtrl,
                              builder: (_, __) {
                                final t = _shimmerCtrl.value;
                                return ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: [
                                        c.textPrimary.withValues(alpha: 0.85),
                                        c.accent,
                                        c.textPrimary.withValues(alpha: 0.85),
                                      ],
                                      stops: const [0.0, 0.5, 1.0],
                                      begin: Alignment(-1.0 + t * 2.0, 0),
                                      end: Alignment(1.0 + t * 2.0, 0),
                                    ).createShader(bounds);
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.chevron_right_rounded,
                                          size: 18.sp, color: Colors.white),
                                      Icon(Icons.chevron_right_rounded,
                                          size: 18.sp, color: Colors.white),
                                      SizedBox(width: 4.w),
                                      Text(
                                        widget.label,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17.sp,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),
                // Draggable thumb — solid accent circle with a subtle
                // outer ring + shadow so it reads as a physical knob
                // floating above the rail.
                Positioned(
                  left: _dragX,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragUpdate: disabled
                        ? null
                        : (d) {
                            setState(() {
                              _dragX =
                                  (_dragX + d.delta.dx).clamp(0.0, maxDrag);
                            });
                          },
                    onHorizontalDragEnd: disabled
                        ? null
                        : (_) {
                            if (progress >= 0.8) {
                              setState(() => _dragX = maxDrag);
                              HapticFeedback.mediumImpact();
                              widget.onConfirmed();
                            } else {
                              setState(() => _dragX = 0.0);
                            }
                          },
                    child: Padding(
                      padding: EdgeInsets.all(4.w),
                      child: Container(
                        width: h - 8.w,
                        height: h - 8.w,
                        decoration: BoxDecoration(
                          color: c.accent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.28),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: c.accent.withValues(alpha: 0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 0),
                            ),
                          ],
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.0,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 24.sp,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// _StepperProgress was extracted into
// `lib/screens/shared/stepper/stepper_widgets.dart` so it can be
// reused by `confirm_receive.dart`. Use `StepperProgress` from that
// import.

/// Single step in the progressive-disclosure send flow.
///
/// Three visual treatments driven by `isExpanded` + `isCompleted`:
///   1. Active (expanded): elevated card, accent border, prominent
///      icon-bearing badge, full body content.
///   2. Completed (collapsed, tappable): flat surface, soft border,
///      green check badge, summary line + edit pencil.
///   3. Locked (collapsed, untappable): just a row — number badge in
///      muted color, dim title, no border, no shadow. Reads as
///      "you'll get to this".
///
/// Each step also draws a subtle vertical connector line on its left
/// edge that ties into the next step, so the four cards read as one
/// continuous timeline rather than four disconnected boxes.

/// Header row inside each `_StepCard`. Renders the badge (number /
/// check / locked dot) + title + optional summary + optional edit
/// pencil. Animated transitions between the three states so the badge
/// morphs smoothly when a step lands.

class _DestAsset {
  final String code;
  final String name;
  final String? iconUrl;
  final String? svgAsset;
  final Color color;
  _DestAsset(
      {required this.code,
      required this.name,
      required this.color,
      this.iconUrl,
      this.svgAsset});

  Widget iconWidget({required double size}) {
    if (svgAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: SvgPicture.asset(svgAsset!, width: size, height: size),
      );
    }
    if (iconUrl != null) {
      final isSvg = Uri.tryParse(iconUrl!)?.path.endsWith('.svg') ?? false;
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.3),
        child: isSvg
            ? SafeSvgNetwork(
                url: iconUrl!,
                width: size,
                height: size,
                fallback: _textFallback(size),
              )
            : CachedNetworkImage(
                imageUrl: iconUrl!,
                width: size,
                height: size,
                // No BuildContext here — ~3x logical size is a safe decode ceiling.
                memCacheWidth: (size * 3).round(),
                placeholder: (ctx, url) => SizedBox(width: size, height: size),
                errorWidget: (ctx, url, err) => _textFallback(size)),
      );
    }
    return _textFallback(size);
  }

  Widget _textFallback(double size) => Text(
        code.substring(0, code.length.clamp(0, 2)),
        style: TextStyle(
            color: color, fontSize: size * 0.5, fontWeight: FontWeight.w700),
      );
}

/// The picked destination chain. `network` is the Orchestra chain slug
/// (lowercase) the quote / route APIs take; `name` is its display name.
class _DestNetwork {
  final String network;
  final String name;
  final String addressHint;
  _DestNetwork(
      {required this.network, required this.name, required this.addressHint});
}

/// One send-direction destination option: an (asset, chain) pair
/// Orchestra can deliver from BTC-on-Spark, clipped to
/// [kOrchestraSendableChains] — the send flow validates recipient
/// addresses per rail family, so only chains it can actually check
/// and dispatch to are offered.
class _SendDestOption {
  /// Asset code as Flashnet spells it ('USDC.e' keeps its casing).
  final String assetCode;
  final String displayName;
  final String displaySymbol;

  /// Chain slug, lowercase (the value quote/route APIs take).
  final String chain;
  final String chainDisplayName;

  /// Absolute URL for the chain's artwork: the catalog's `chainIcon`
  /// (the API's only image field), else the host's conventional path
  /// via [orchestraChainIconUrl], so the static fallback shows real
  /// marks too.
  final String? chainIconUrl;

  const _SendDestOption({
    required this.assetCode,
    required this.displayName,
    required this.displaySymbol,
    required this.chain,
    required this.chainDisplayName,
    this.chainIconUrl,
  });
}

/// Send destination options from the live catalog (static stablecoin
/// fallback until it lands / offline). Local composition: the catalog
/// model ships `receiveOptions()` but no send-side twin, so the
/// pairing is derived here the same way, send-direction, clipped to
/// [kOrchestraSendableChains].
List<_SendDestOption> _sendDestOptions(
    OrchestraRoutesCatalog catalog, AppLocalizations l10n) {
  final options = <_SendDestOption>[];
  if (catalog.hasLiveData) {
    final btc = catalog.sparkBtc!;
    for (final a in catalog.assets) {
      final chain = a.chain.toLowerCase();
      if (!kOrchestraSendableChains.contains(chain)) continue;
      if (a.asset.toUpperCase() == 'BTC') continue;
      // Investing's and Predictions' own rails: the venue flows reach
      // them directly, and a person never picks them as a destination.
      if (isVenueInternalRoute(chain, a.asset)) continue;
      if (!btc.to.contains(a.id, selfId: btc.id)) continue;
      options.add(_SendDestOption(
        assetCode: a.asset,
        displayName: a.displayName,
        displaySymbol: a.displaySymbol,
        chain: chain,
        chainDisplayName: a.chainDisplayName.isNotEmpty
            ? a.chainDisplayName
            : orchestraChainDisplayName(chain),
        chainIconUrl: a.chainIconUrl ?? orchestraChainIconUrl(chain),
      ));
    }
  } else {
    const staticNames = {'USDT': 'Tether USD', 'USDC': 'USD Coin'};
    kOrchestraSendRoutes.forEach((code, chains) {
      for (final chain in chains) {
        if (!kOrchestraSendableChains.contains(chain)) continue;
        if (isVenueInternalRoute(chain, code)) continue;
        options.add(_SendDestOption(
          assetCode: code,
          displayName: staticNames[code] ?? code,
          displaySymbol: code,
          chain: chain,
          chainDisplayName: orchestraChainDisplayName(chain),
          chainIconUrl: orchestraChainIconUrl(chain),
        ));
      }
    });
  }
  // The dollar balance wears plain dollars on the row a person reads.
  // The catalogue's own spelling of the token, and of the rail it
  // settles on, stays on `assetCode` and `chain` — which is what the
  // quote is opened with — and never reaches a label.
  for (var i = 0; i < options.length; i++) {
    final o = options[i];
    if (!isOrchestraUsdRoute(o.chain, o.assetCode)) continue;
    options[i] = _SendDestOption(
      assetCode: o.assetCode,
      displayName: l10n.assetDollars,
      displaySymbol: 'USD',
      chain: o.chain,
      chainDisplayName: l10n.instant,
      chainIconUrl: o.chainIconUrl,
    );
  }
  options.sort((a, b) {
    final bySymbol =
        a.displaySymbol.toLowerCase().compareTo(b.displaySymbol.toLowerCase());
    if (bySymbol != 0) return bySymbol;
    return a.chainDisplayName
        .toLowerCase()
        .compareTo(b.chainDisplayName.toLowerCase());
  });
  // Bridged USDC.e is never a send destination (user decision,
  // September 2026): it only moves between Predictions and the person's
  // bitcoin or dollars, through the venue deposit and withdrawal flows.
  return options;
}

/// The send picker's rows as `chain:asset` ids, for tests of which
/// destinations a person can pick.
@visibleForTesting
List<String> debugSendDestinationIds(
        OrchestraRoutesCatalog catalog, AppLocalizations l10n) =>
    _sendDestOptions(catalog, l10n)
        .map((o) => '${o.chain}:${o.assetCode}')
        .toList();

/// Runs one Send tap with the button busy from the tap itself.
///
/// [setBusy] (true) runs synchronously, before [dispatch] reaches its
/// first await, so the button spins on the frame after the tap — not
/// after a balance sync, a quote or a PSBT build lands. When [dispatch]
/// finishes, by any return or throw, busy is cleared again unless
/// [releaseBusy] says the busy state is no longer this tap's to clear
/// (already cleared by the route, or owned by a newer build).
@visibleForTesting
Future<void> runSendTapBusy({
  required void Function(bool busy) setBusy,
  required bool Function() releaseBusy,
  required Future<void> Function() dispatch,
}) async {
  setBusy(true);
  try {
    await dispatch();
  } finally {
    if (releaseBusy()) setBusy(false);
  }
}

/// A send destination as a row the shared coin picker can show.
///
/// [CoinAssetPickerSheet] speaks [OrchestraReceiveOption] in both
/// directions on purpose: the type carries exactly what a picker row
/// needs — the coin, the chain and the artwork for each — and nothing
/// about how money is deposited. Every send destination is an ordinary
/// address the recipient already holds, so `reusableAddress` is true
/// and no row here ever wears the one-off note. `decimals` never
/// reaches the picker (the quote carries the units that matter), so it
/// is not carried across.
OrchestraReceiveOption _sendDestPickerRow(_SendDestOption o) =>
    OrchestraReceiveOption(
      assetCode: o.assetCode,
      displayName: o.displayName,
      displaySymbol: o.displaySymbol,
      chain: o.chain,
      chainDisplayName: o.chainDisplayName,
      decimals: 0,
      chainIconUrl: o.chainIconUrl,
    );

Color _getCoinColor(String code) {
  const colors = {
    'ETH': Color(0xFF627EEA),
    'USDT': Color(0xFF26A17B),
    'USDC': Color(0xFF2775CA),
    'BNB': Color(0xFFF3BA2F),
    'SOL': Color(0xFF9945FF),
    'XRP': Color(0xFF00AAE4),
    'TRX': Color(0xFFFF0013),
    'LTC': Color(0xFF345D9D),
    'POL': Color(0xFF8247E5),
    'DOGE': Color(0xFFC2A633),
    'ADA': Color(0xFF0033AD),
    'DOT': Color(0xFFE6007A),
    'AVAX': Color(0xFFE84142),
    'NEAR': Color(0xFF00C08B),
    'ATOM': Color(0xFF2E3148),
    'TON': Color(0xFF0098EA),
    'SUI': Color(0xFF4DA2FF),
    'SEI': Color(0xFFFF4545),
    'BTC': AppColors.accent,
    'WBTC': Color(0xFFF09242),
    'BCH': Color(0xFF8DC351),
    'STX': Color(0xFF5546FF),
    'TIA': Color(0xFF7B2BF9),
  };
  return colors[code] ?? Color(code.hashCode | 0xFF404040);
}

// Helper model for displaying fee breakdown
class FeeDetail {
  final String label;
  final int amountSats;
  FeeDetail({required this.label, required this.amountSats});
}

/// Simple Fast/Standard/Slow picker for cases where we don't yet have
/// a `SendOnchainFeeQuote` to display sat numbers (e.g. while the
/// destination of a Spark hot wallet send is still resolving).
/// Returns `null` if the user dismisses.
Future<OnchainConfirmationSpeed?> _showSimpleSpeedPicker(
    BuildContext context, OnchainConfirmationSpeed current) async {
  final options = [
    {
      'label': context.l10n.fast,
      'speed': OnchainConfirmationSpeed.fast,
      'time': context.l10n.k10Min,
      'icon': Icons.rocket_launch,
    },
    {
      'label': context.l10n.standard,
      'speed': OnchainConfirmationSpeed.medium,
      'time': context.l10n.k30Min,
      'icon': Icons.timer,
    },
    {
      'label': context.l10n.slow,
      'speed': OnchainConfirmationSpeed.slow,
      'time': context.l10n.k60Min,
      'icon': Icons.directions_walk,
    },
  ];
  return await showAppBottomSheet<OnchainConfirmationSpeed>(
    context: context,
    builder: (ctx) {
      return AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.networkSpeed,
              subtitle: context
                  .l10n.fasterIsMoreExpensiveSlowerIsCheaperButTakesLonger,
              icon: Icons.speed,
            ),
            SizedBox(height: 8.h),
            ...options.map((opt) {
              final speed = opt['speed'] as OnchainConfirmationSpeed;
              return AppBottomSheetListTile(
                title: opt['label'] as String,
                subtitle: opt['time'] as String,
                icon: opt['icon'] as IconData,
                isSelected: speed == current,
                onTap: () => ctx.pop(speed),
              );
            }),
            SizedBox(height: 8.h),
            AppBottomSheetTextButton(
              text: context.l10n.cancel,
              onPressed: () => ctx.pop(),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      );
    },
  );
}

/// Sats from a fee value the SDK hands back as BigInt or num.
int _feeSats(Object? raw) => raw is BigInt ? raw.toInt() : (raw as num).toInt();

Future<OnchainConfirmationSpeed?> _showFeePicker(
    BuildContext context, SendOnchainFeeQuote quote) async {
  // The row shows the total per speed; the L1 broadcast fee (varies by
  // speed) and the operator's service fee sit in the Nerd data section.
  // The SDK charges userFeeSat (service) PLUS l1BroadcastFeeSat
  // (network) — `SendOnchainSpeedFeeQuote::total_fee_sat`.
  // The service fee is quoted per speed too; one row stands for all three
  // only when they agree.
  final serviceBySpeed = sparkOnchainServiceFeesBySpeed(quote);

  final options = [
    {
      'label': context.l10n.fast,
      'networkFee': quote.speedFast.l1BroadcastFeeSat,
      'totalFee': sparkOnchainFeeSats(quote, OnchainConfirmationSpeed.fast),
      'speed': OnchainConfirmationSpeed.fast,
      'time': context.l10n.k10Min,
      'icon': Icons.rocket_launch
    },
    {
      'label': context.l10n.standard,
      'networkFee': quote.speedMedium.l1BroadcastFeeSat,
      'totalFee': sparkOnchainFeeSats(quote, OnchainConfirmationSpeed.medium),
      'speed': OnchainConfirmationSpeed.medium,
      'time': context.l10n.k30Min,
      'icon': Icons.timer
    },
    {
      'label': context.l10n.slow,
      'networkFee': quote.speedSlow.l1BroadcastFeeSat,
      'totalFee': sparkOnchainFeeSats(quote, OnchainConfirmationSpeed.slow),
      'speed': OnchainConfirmationSpeed.slow,
      'time': context.l10n.k60Min,
      'icon': Icons.directions_walk
    },
  ];

  return await showAppBottomSheet<OnchainConfirmationSpeed>(
    context: context,
    builder: (ctx) {
      return AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.networkSpeed,
              subtitle: context
                  .l10n.fasterIsMoreExpensiveSlowerIsCheaperButTakesLonger,
              icon: Icons.speed,
            ),
            SizedBox(height: 8.h),
            ...options.map((opt) {
              final totalFee = _feeSats(opt['totalFee']);
              return AppBottomSheetListTile(
                title: opt['label'] as String,
                subtitle: context.l10n.sendFeeTimeTotal(
                    opt['time'] as String, totalFee.toFormattedString('sats')),
                icon: opt['icon'] as IconData,
                onTap: () => ctx.pop(opt['speed'] as OnchainConfirmationSpeed),
              );
            }),
            // The network and service split per speed, one tap away.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: SheetNerdDataSection(children: [
                for (final opt in options)
                  SheetDetailRow(
                    label:
                        context.l10n.sendNetworkFeeFor(opt['label'] as String),
                    value:
                        '₿${_feeSats(opt['networkFee']).toFormattedString('sats')}',
                  ),
                if (serviceBySpeed.values.toSet().length == 1) ...[
                  if (serviceBySpeed.values.first > 0)
                    SheetDetailRow(
                      label: context.l10n.serviceFee,
                      value:
                          '₿${serviceBySpeed.values.first.toFormattedString('sats')}',
                    ),
                ] else
                  for (final opt in options)
                    SheetDetailRow(
                      label: '${context.l10n.serviceFee} · ${opt['label']}',
                      value:
                          '₿${serviceBySpeed[opt['speed']]!.toFormattedString('sats')}',
                    ),
              ]),
            ),
            SizedBox(height: 8.h),
            AppBottomSheetTextButton(
              text: context.l10n.cancel,
              onPressed: () => ctx.pop(),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      );
    },
  );
}

Future<bool> showConfirmationModal(
    BuildContext context,
    int amountSats,
    String address,
    List<FeeDetail> fees,
    String btcFormat,
    WidgetRef ref) async {
  final amountString = amountSats.toFormattedString(btcFormat);
  final amountFiat = ref.read(conversionToFiatProvider(amountSats));

  // Pushed as a full-screen route on the rootNavigator (not a Dialog),
  // so the confirmation feels like a destination instead of a modal
  // popup. Matches the swap-confirmation page styling for one
  // consistent confirm-tx pattern across the app.
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      pageBuilder: (_, __, ___) => _StandardConfirmationPage(
        amountString: amountString,
        unit: btcFormat,
        amountFiat: amountFiat,
        address: address,
        fees: fees,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
  return result ?? false;
}

class ConfirmSend extends ConsumerStatefulWidget {
  const ConfirmSend({super.key});

  @override
  _ConfirmSendState createState() => _ConfirmSendState();
}

class _ConfirmSendState extends ConsumerState<ConfirmSend>
    with TickerProviderStateMixin {
  final TextEditingController controller = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  bool isProcessing = false;

  /// Pulse animation fired on each amount keystroke. Owning the
  /// controller as state (instead of via a keyed
  /// `TweenAnimationBuilder`) lets us run the bounce WITHOUT
  /// rebuilding the TextField subtree — which would otherwise tear
  /// down the input on every char and dismiss the keyboard.
  late final AnimationController _amountPulse;

  /// Hardware / watch-only — base64 PSBT built when the user
  /// confirmed Review and tapped Continue. Stored here so the Sign
  /// step can render the embedded WatchOnlySigningScreen with this
  /// PSBT instead of having to push a separate route.
  String? _builtPsbt;
  String? _builtPsbtRecipientAddress;
  WalletConfig? _builtPsbtWallet;

  /// Recipient output amount (sats) parsed from the built PSBT — what
  /// the destination address actually receives. Mirrors the "Amount"
  /// row the Ledger screen shows, so the Sign card can display the
  /// same number rather than the gross input total.
  int? _builtPsbtRecipientSats;

  /// On-chain fee (sats) parsed from the built PSBT. Shown alongside
  /// the recipient amount on the Sign card so the breakdown matches
  /// the Ledger device's Amount + Fees rows.
  int? _builtPsbtFeeSats;

  /// Last-used (toAddress, amountSats) tuple for the Sign step. Stored
  /// so the Sign page can rebuild the PSBT after the user changes
  /// network speed / coin-control in the Advanced sheet, or hits
  /// "Try again" after a build failure — without us having to drag
  /// those params back out of provider state (where they may have
  /// already drifted).
  String? _signLastToAddress;
  int? _signLastAmountSats;

  /// Provider and final recipient of the last Sign-step build, so a
  /// rebuild binds the same step-up intent (Phase 1b.2).
  String _signLastProvider = 'psbt';
  String? _signLastRecipient;

  /// The intent the Sign-step PSBT was approved for. Consumed when the
  /// signed PSBT comes back.
  SensitiveIntent? _signApprovedIntent;

  /// Step-up grant for the current send attempt (Phase 1b.2). Issued
  /// after the route, SDK prepare, quote and provider deposit address
  /// exist; laddered retries `check` it and the call that moves funds
  /// `consume`s it.
  AuthGrant? _sendGrant;

  /// Review snapshot of the current attempt: the field classes the user
  /// changed since tapping Send. Checked right after a fresh approval.
  Set<DriftField> Function()? _sendReviewDrift;

  /// Inline error surfaced by the Sign step when the PSBT build fails.
  /// Non-null → the page renders an error card with a "Try again" CTA
  /// in place of the embedded signing screen, so the user can recover
  /// without backing out of the stepper or chasing a snackbar.
  String? _signPageError;

  /// Raw text behind [_signPageError], for the card's nerd data row.
  String? _signPageErrorDetail;

  /// True once the embedded `WatchOnlySigningScreen` has accepted the
  /// signed PSBT — the user is in the post-sign state, about to
  /// broadcast. Drives the Sign step's chrome: the Network settings
  /// pill is hidden because adjusting fee/UTXOs would invalidate
  /// the already-signed PSBT. Reset whenever we rebuild the PSBT
  /// (`_rebuildSignPagePsbt`, the back-to-Review path).
  bool _signedPsbtAccepted = false;
  bool _signerBusy = false;
  int _hardwareBuildGeneration = 0;

  /// Review "To" row toggled open to show the full destination with a
  /// copy action (hardware users compare it with the device screen).
  bool _reviewToExpanded = false;

  /// Address or invoice found in the clipboard on entering the Send to
  /// step, offered as a one-line "Use it?" chip. Cleared once used or
  /// dismissed; the dismissed text is remembered so the same clipboard
  /// content is not offered again on the next visit.
  String? _clipboardCandidate;
  String? _clipboardDismissed;

  /// Preserve the wallet scope that opened Send when nested flows close.
  /// Captured at entry and restored in dispose without selecting another wallet.
  String? _entryBdkScopeWalletId;

  /// Spark hot wallet → on-chain BTC withdrawal — confirmation speed
  /// the user picked on Review. Defaults to Standard (the middle tier,
  /// not the most expensive one); Fast stays one tap away in the
  /// Network speed sheet. `_handleSend` skips the `_showFeePicker`
  /// popup and uses this directly.
  OnchainConfirmationSpeed _sparkOnchainSpeed = OnchainConfirmationSpeed.medium;
  bool isInvoice = false;
  bool isCalculatingMax = false;
  bool _isDraining = false;

  /// Wallet, address, fee rate and coin-selection size the drain probe
  /// last ran for, so Review refreshes the real max once per context
  /// instead of on every rebuild.
  String? _drainProbeKey;

  /// Drain ("send everything") must be visible to the BUILDERS too, not
  /// just to this screen: `sendBitcoinTransactionProvider` and the coin
  /// selection sheet read `sendTxProvider.drain` to choose the
  /// drain-wallet build and to size the fee with no change output.
  /// While the model's flag stayed false, MAX asked those paths to cover
  /// amount plus fee out of the whole balance, which cannot be built, so
  /// no fee came back and the Sign step never enabled.
  void _setDraining(bool value) {
    _isDraining = value;
    ref.read(sendTxProvider.notifier).updateDrain(value);
  }

  late String btcFormat;
  late String currency;

  /// ATM-mode raw digit accumulator for Bitcoin amount entry. While
  /// the user is entering sats/BTC, every keypress appends a digit to
  /// this string and the displayed value is formatted from it (digits
  /// flow in from the right, ATM-style). Empty string == nothing
  /// typed yet. Max 10 digits (≈100 BTC ceiling). Ignored in fiat
  /// mode, where the existing decimal-entry TextField stays in
  /// charge.
  String _atmDigits = '';
  static const int _atmMaxDigits = 10;

  // Destination: null = Bitcoin/Lightning/Spark (default), otherwise cross-chain swap
  _DestAsset? _selectedDestAsset;
  _DestNetwork? _selectedDestNetwork;
  SwapQuote? _swapQuote;
  bool _loadingRate = false;
  String? _rateError;
  Timer? _rateDebounce;

  /// Account captured at entry for the static wallet title. Always a
  /// bitcoin account: Send draws from bitcoin only, so an entry on the
  /// dollar (Predictions) card maps to the same wallet's bitcoin
  /// account. Predictions money moves through the venue deposit and
  /// withdrawal flows (Move sheet), never through Send.
  Account? _selectedAccount;

  /// True once Send has a source account to draw bitcoin from.
  bool get _hasSource => _selectedAccount != null;

  /// Wallet that opened Send. Hardware and separate Bitcoin sources stay
  /// pinned to this ID while the active account remains the spending wallet.
  String? _selectedWalletId;

  /// Active step in the progressive-disclosure stepper.
  ///   0 — Pay with (source pool)
  ///   1 — Amount (and Max)
  ///   2 — Send to (network + address)
  ///   3 — Review (sticky; Send button enabled)
  /// Steps "lock" past their currently active value: tapping a
  /// previously-completed step re-opens it for editing and resets
  /// `_step` to that index, leaving downstream entries intact but
  /// re-confirmable.
  int _step = 0;

  /// True once each step has been confirmed at least once. Used to
  /// render the collapsed summary line on completed sections.
  final Set<int> _completedSteps = <int>{};

  /// True when the address was preloaded into `sendTxProvider` before
  /// this screen mounted (scanner / contact entry) AND the detected
  /// rail is a native BTC one — Bitcoin on-chain, Lightning, Spark.
  /// The Send-to step (index 1) is then hidden from the stepper and
  /// the Amount Continue jumps straight to Review.
  bool _skipSendToStep = false;

  /// True when the preloaded address already carries a fixed amount
  /// (Bolt11/12 invoice with amount, Spark invoice with amount). The
  /// Amount step (index 0) is then hidden too and the user lands
  /// directly on Review.
  bool _skipAmountStep = false;

  /// Fiat unit the user last typed in on the Amount step. The swap
  /// icon under the hero flips Bitcoin <-> this unit, so a user who
  /// picked EUR in the unit sheet comes back to EUR, not the settings
  /// currency.
  String? _lastFiatUnit;

  /// Address the fixed-amount Bolt11 fast path last auto-advanced to
  /// Review for. One-shot per address so a user who deliberately backs
  /// out of Review isn't yanked forward again by a re-parse of the
  /// same invoice (build's post-frame sync re-runs detection).
  String? _invoiceFastPathAddress;

  /// Phase 3 send-funnel one-shots. `_amountEnteredTracked` gates
  /// `send_amount_entered` so it fires exactly once even if the user
  /// swipes back and re-confirms Amount; `_reviewShownTracked` does the
  /// same for `send_review_shown`.
  bool _amountEnteredTracked = false;
  String? _addressEntryMethod;
  String? _amountMethod;
  Map<String, Object> _lastSendInputs = const {};
  bool _reviewShownTracked = false;

  /// Phase 3: set true once a send is signed/broadcast so dispose can
  /// tell a finished flow from an abandoned one.
  bool _sendCompleted = false;
  bool _paymentAuthInFlight = false;

  /// True while a MAX tap is parked waiting for the send wallet's BDK
  /// coins to load. Re-entrancy guard: the scan this wait kicks calls
  /// `_setMaxAmount` again on completion, and two of them racing would
  /// fight over `isCalculatingMax`.
  bool _maxAwaitingCoins = false;

  /// True between a Send tap that arrived before the draft was ready
  /// and the moment it either dispatches or gives up. Drives the
  /// button's own spinner so the wait reads as work in progress
  /// instead of a dead control.
  bool _sendAwaitingReady = false;

  /// Drives the swipeable PageView body. Each step is its own
  /// full-screen page; tapping a step's primary action animates to
  /// the next page (and `_completedSteps` is updated). User can
  /// swipe back to a prior step at any time.
  late final PageController _pageCtrl;

  /// Root container captured while live — `ref` is unusable inside
  /// [dispose] (Riverpod tears the element's ref down before
  /// `state.dispose()` on unmount; same class as the 1.3.8 Polymarket
  /// prod fatal). The old swallowed `ref.read`s meant the bdkScope
  /// restore silently FAILED on teardown, stranding the scope on a
  /// hardware wallet id.
  ProviderContainer? _container;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _amountPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    final settings = ref.read(settingsProvider);
    btcFormat = settings.btcFormat;
    currency = settings.currency;
    final sendTxState = ref.read(sendTxProvider);
    // The amount opens in the currency chosen in Settings when it is one
    // the keypad can price (owner decision); bitcoin stays one flip away.
    // Written after the first frame so an autoDispose default is not
    // fought during build.
    final settingsFiat = settings.currency.toUpperCase();
    if (const {'USD', 'EUR', 'GBP', 'BRL', 'CHF'}.contains(settingsFiat)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(sendTxProvider).amount > 0) return;
        ref.read(inputCurrencyProvider.notifier).state = settingsFiat;
        _lastFiatUnit = settingsFiat;
      });
    }

    // Capture the entry account once. The header identifies this wallet;
    // changing wallets happens before entering Send. Step 0 is Amount.
    final selected = ref.read(selectedAccountProvider);
    _entryBdkScopeWalletId = ref.read(bdkScopeWalletIdProvider);
    if (selected != null && selected.capabilities.canSend) {
      // Send always draws from bitcoin: the dollar account resolves to
      // the same wallet's bitcoin account, never to the dollar balance.
      final source = selected is UsdcSpendingAccount
          ? BtcSpendingAccount(selected.wallet)
          : selected;
      _selectedAccount = source;
      _selectedWalletId = source.wallet?.id;
    }
    // Default initial step. Overridden below when the address is
    // preset (scanner / contact / external-entry) so the stepper
    // collapses past steps the user has effectively already answered.
    _step = 0;

    // Pre-filled state shortcut. The smart scanner and any other
    // upstream entry writes `address` (and optionally `amount`) into
    // `sendTxProvider` before pushing this screen, so the address
    // step is redundant. Skip it. The amount step also skips when
    // the address carries its own amount — fixed-amount Lightning
    // invoice (Bolt11/12 + amount > 0) or a Spark invoice with amount.
    // LN address / LNURL (no embedded amount) and on-chain BTC still
    // need the Amount step. Non-native rails (EVM / Solana / Unknown)
    // keep the Send-to step in the flow so the user can pick a
    // destination chain via the "needs attention" tile.
    final preAddress = sendTxState.address;
    if (preAddress.isNotEmpty) {
      final detected = _detectAddressType(preAddress);
      final isNativeBtcRail = detected.label == 'Bitcoin on-chain' ||
          detected.label == 'Lightning invoice' ||
          detected.label == 'Lightning address' ||
          detected.label == 'LNURL' ||
          detected.label == 'Spark address';
      final hasFixedAmount = sendTxState.amount > 0 &&
          (sendTxState.type == PaymentType.Lightning ||
              sendTxState.type == PaymentType.Spark);
      if (isNativeBtcRail && hasFixedAmount) {
        _skipSendToStep = true;
        _skipAmountStep = true;
        _step = 2;
        // Both Amount and Send-to are answered by the preset address +
        // embedded amount, so the user lands straight on Review without
        // tapping Continue on either. Pre-mark them complete or the
        // Review "Send" button (gates on {0, 1}) stays disabled.
        _completedSteps.addAll({0, 1});
        // Phase 3 send funnel: amount + review are reached at mount on
        // this fixed-amount shortcut path (the user never taps through
        // Amount/Review). Mark both one-shots so we count them once.
        _amountEnteredTracked = true;
        _reviewShownTracked = true;
        TrackingService.sendAmountEntered(
            network: _networkLabel(sendTxState.type));
        TrackingService.sendReviewShown(
            network: _networkLabel(sendTxState.type));
        // Same one-shot the async fast path uses — the initState
        // `_checkAndPopulateInvoiceAmount` below re-parses this address
        // and must not double-fire the fastpath event for it.
        _invoiceFastPathAddress = preAddress;
        TrackingService.track('send_invoice_fastpath',
            params: {'entry': 'mount'});
      } else if (isNativeBtcRail) {
        _skipSendToStep = true; // Amount → Review, skip Send-to
        _step = 0;
      }
      // Non-native rails fall through: _step stays 0, no auto-skip;
      // the user advances through Amount → Send-to and the
      // attention-flagged tile on Send-to forces a chain pick.
    }
    _pageCtrl = PageController(initialPage: _step);

    // Per-step PostHog `$screen` — the route observer only sees the
    // outer `pay_send` route, so each stepper page needs its own emit.
    // Fires once on mount + on every swipe/animate to a new page.
    const stepNames = [
      'pay_send_amount',
      'pay_send_send_to',
      'pay_send_review',
      'pay_send_sign',
    ];
    void emitStepScreen(int s) {
      if (s >= 0 && s < stepNames.length) {
        TrackingService.screenView(stepNames[s]);
      }
    }

    int? lastTrackedStep = _step;
    emitStepScreen(_step);
    _pageCtrl.addListener(() {
      final p = _pageCtrl.page?.round();
      if (p == null || p == lastTrackedStep) return;
      lastTrackedStep = p;
      emitStepScreen(p);
      TrackingService.moneyFlowStep('send', _sendStepName(p),
          props: _sendFlowInputs());
    });

    // Ensure payment type is set for this screen context so that the
    // in-screen camera knows to prefer Lightning/Spark when parsing BIP-21.
    if (sendTxState.type == PaymentType.Unknown) {
      Future(() => ref
          .read(sendTxProvider.notifier)
          .updatePaymentType(PaymentType.Spark));
    }

    updateControllerText(sendTxState.amount);
    addressController.text = sendTxState.address;
    _checkAndPopulateInvoiceAmount(sendTxState.address);

    // Funnel entry — fires once per Send screen mount. The matching
    // _sendCompleted lives at the broadcast site; abandonment fires
    // in dispose() below when neither a tx-id nor a step-advance
    // happened.
    _addressEntryMethod = preAddress.isNotEmpty ? 'prefilled' : null;
    if (sendTxState.amount > 0) _amountMethod = 'prefilled';
    TrackingService.moneyFlowStarted(
      'send',
      event: 'send_flow_started',
      abandonEvent: 'send_flow_abandoned',
      entrySource: TrackingService.takeEntrySource('send',
          fallback: preAddress.isNotEmpty ? 'prefilled' : 'unknown'),
      walletKind: _sendWalletKind(),
      network: _networkLabel(sendTxState.type),
      props: {
        'source_asset': 'btc',
        'address_prefilled': preAddress.isNotEmpty,
        'amount_prefilled': sendTxState.amount > 0,
      },
    );
    if (_step > 0) {
      TrackingService.moneyFlowStep('send', _sendStepName(_step),
          props: _sendFlowInputs());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The PSBT is built from the send wallet's own BDK state, so that
      // state has to be loaded before the user can draft one. Sync it
      // here and keep it fresh for as long as the flow is open.
      _startSendWalletSync();
    });
  }

  @override
  void dispose() {
    _rateDebounce?.cancel();
    _sendWalletSyncTimer?.cancel();
    _dropSendGrant();
    // Phase 3 send funnel: log abandonment when the user got as far as
    // the Review step but left before reaching Sign (step 3) and never
    // completed a broadcast. Gating on "reached Review, didn't reach
    // Sign" avoids false positives from hardware sends that broadcast
    // from the embedded Sign screen (which doesn't flip _sendCompleted
    // here). Fired from dispose, not build — safe per the one-shot rule.
    if (_sendCompleted) {
      TrackingService.moneyFlowFinished('send');
    } else {
      TrackingService.moneyFlowAbandoned('send', props: _lastSendInputs);
    }
    // Restore the scope that opened Send so later actions stay on that wallet.
    // Reads go through the captured root container, never `ref`:
    // the element's ref is already torn down inside dispose (the
    // 1.3.8 prod fatal class) — the old swallowed ref.read meant
    // this restore silently never ran on teardown.
    try {
      _container?.read(bdkScopeWalletIdProvider.notifier).state =
          _entryBdkScopeWalletId;
    } catch (_) {}
    _pageCtrl.dispose();
    controller.dispose();
    addressController.dispose();
    _amountPulse.dispose();
    super.dispose();
  }

  /// How often the flow re-syncs the wallet it spends FROM while the
  /// user is still inside it. Slow on purpose: BDK Electrum scans are
  /// the app's known crash mode under continuous polling, and a tick
  /// that would contend for the wallet's single native slot is skipped
  /// rather than queued.
  static const Duration _sendWalletSyncInterval = Duration(seconds: 30);

  Timer? _sendWalletSyncTimer;
  String? _sendWalletSyncId;

  /// Sync the wallet the send spends FROM, for as long as the flow is open.
  ///
  /// The transaction is built from that wallet's own BDK state, so a
  /// wallet whose coins are not loaded cannot build one: `drainWallet` +
  /// `drainTo` over an empty coin set fails, and both native plugins
  /// report every build failure that is not InsufficientFunds as one
  /// generic code — which this flow could only word as "Couldn't prepare
  /// this payment". Opening Send used to scan only when the user came
  /// from a wallet-detail surface, which is why sending everything from a
  /// Bitcoin wallet needed a manual refresh first.
  ///
  /// The BDK scope is pointed at the send's OWN wallet id rather than the
  /// carousel's active wallet, so the scan, the coin list and the coin
  /// labels all target the wallet being spent. `dispose` restores the
  /// scope that opened Send.
  void _startSendWalletSync() {
    if (!mounted) return;
    final wallet = _resolveSourceWallet();
    if (wallet == null || !wallet.usesBdk) return;
    _sendWalletSyncId = wallet.id;
    if (ref.read(bdkScopeWalletIdProvider) != wallet.id) {
      ref.read(bdkScopeWalletIdProvider.notifier).state = wallet.id;
    }
    _syncSendWallet();
    _sendWalletSyncTimer?.cancel();
    _sendWalletSyncTimer =
        Timer.periodic(_sendWalletSyncInterval, (_) => _syncSendWallet());
  }

  /// One incremental scan of the send wallet. Concurrent calls are
  /// coalesced by the service, and a tick is dropped while a build holds
  /// the wallet's slot reservation — a scan admitted against one takes
  /// the slot back the instant the build's wait resolves.
  void _syncSendWallet() {
    final walletId = _sendWalletSyncId;
    if (walletId == null || !mounted) return;
    if (isProcessing || _paymentAuthInFlight || _signerBusy) return;
    if (NativeOnchainService.instance.isSlotReserved(walletId)) return;
    final hadCoins = _bdkHasSpendableCoins(walletId);
    unawaited(BackgroundSyncService().scanBdkScope(source: 'send_open').then(
      (_) {
        if (!mounted ||
            isProcessing ||
            _paymentAuthInFlight ||
            _resolveSourceWallet()?.id != walletId) {
          return;
        }
        // A draft refused while the wallet had no loaded coins is not
        // retried by itself: the model object never changes, so the
        // preview never re-runs. Now that the coins are there, rebuild
        // it so Review recovers without the user backing out.
        if (!hadCoins && _bdkHasSpendableCoins(walletId)) {
          ref.invalidate(bitcoinSoftwareSendPreviewProvider);
        }
        // MAX was sized from the coins known at the time; keep the
        // displayed amount in step with the ones just synced.
        _refreshDrainAmount();
      },
    ).catchError((Object _) {}));
  }

  /// Analytics rail of a resolved hot-wallet destination.
  static String _resolvedSendNetwork(AnalyzedPaymentType type) {
    switch (type) {
      case AnalyzedPaymentType.lightning:
      case AnalyzedPaymentType.lnurl:
        return 'lightning';
      case AnalyzedPaymentType.spark:
        return 'spark';
      case AnalyzedPaymentType.bip21:
      case AnalyzedPaymentType.bitcoin:
        return 'bitcoin';
      case AnalyzedPaymentType.unknown:
        return 'unknown';
    }
  }

  /// Map the internal PaymentType enum to the network-name enum the
  /// analytics layer expects (`lightning`, `bitcoin`, `spark`, etc.).
  String _networkLabel(PaymentType type) {
    switch (type) {
      case PaymentType.Lightning:
        return 'lightning';
      case PaymentType.Bitcoin:
        return 'bitcoin';
      case PaymentType.Spark:
        return 'spark';
      case PaymentType.NonNative:
        return 'cross_chain';
      case PaymentType.Unknown:
        return 'unknown';
    }
  }

  void updateControllerText(int satsAmount) {
    if (satsAmount == 0) {
      controller.text = '';
      _syncAtmDigitsFromSats(0);
      return;
    }

    // REFACTOR: Use Conversion Providers to format input text correctly
    final selectedCurrency = ref.read(inputCurrencyProvider);

    String newText;
    if (selectedCurrency == 'Sats') {
      newText = satsAmount.toString();
    } else if (selectedCurrency == 'BTC') {
      // Use extension to get "0.00500000"
      newText = satsAmount.toRawBtcString();
    } else {
      // Fiat - Convert to the selected input currency (not the settings
      // default). The formatter uses the currency's own separators (a
      // euro amount reads "1,00"), so only the digits are trusted and the
      // decimal point is put back by count: the controller text is the
      // plain value the in-app keypad edits and `inputToSatsProvider`
      // parses, never "100" for €1.
      newText = canonicalDecimalText(ref.read(satsToTargetCurrencyProvider(
          (sats: satsAmount, currency: selectedCurrency))));
    }

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );

    // Keep the ATM accumulator aligned for sats/BTC mode, so that
    // external amount updates (Max, invoice prefill, route refresh)
    // appear correctly in the ATM-style hero. Fiat mode ignores
    // this path entirely.
    _syncAtmDigitsFromSats(satsAmount);
  }

  /// Sync `_atmDigits` from an explicit sats amount (e.g. Max button,
  /// invoice prefill). The accumulator becomes the raw integer string,
  /// capped at `_atmMaxDigits` so the display formatter never overflows
  /// the 8-decimal BTC layout.
  void _syncAtmDigitsFromSats(int sats) {
    String digits = sats <= 0 ? '' : sats.toString();
    if (digits.length > _atmMaxDigits) {
      digits = digits.substring(digits.length - _atmMaxDigits);
    }
    if (_atmDigits == digits) return;
    // Avoid setState during build / initState — those call paths
    // mutate state before the first frame is committed, so a plain
    // assignment is enough; subsequent calls (Max, invoice prefill)
    // happen post-mount and need a rebuild to refresh the Text.rich.
    if (mounted) {
      setState(() => _atmDigits = digits);
    } else {
      _atmDigits = digits;
    }
  }

  /// Apply a new raw-digit accumulator coming from the in-app keypad.
  /// Strips leading zeros, clamps length, then pushes the derived sats
  /// amount into `sendTxProvider` so the rest of the flow (Continue
  /// gating, fiat conversion line, summary chips) sees the live value.
  void _applyAtmDigits(String raw) {
    // Filter to digits only — defensive even though the keypad is
    // wired with `maxDecimals: 0` in Bitcoin units.
    String digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    // Strip leading zeros so "5" + "0" = "50", and a lone "0" stays
    // as the empty accumulator (no amount).
    digits = digits.replaceAll(RegExp(r'^0+'), '');
    if (digits.length > _atmMaxDigits) {
      digits = digits.substring(digits.length - _atmMaxDigits);
    }
    if (_atmDigits == digits) return;
    setState(() => _atmDigits = digits);
    final sats = digits.isEmpty ? 0 : int.tryParse(digits) ?? 0;
    ref.read(inputAmountProvider.notifier).state =
        sats == 0 ? '0.0' : sats.toString();
    ref
        .read(sendTxProvider.notifier)
        .updateAmountFromInput(sats.toString(), 'sats');
    _setDraining(false);
  }

  /// Format the ATM accumulator for display. In 'Sats' mode the
  /// amount renders as the bare integer ("550"). In 'BTC' mode the
  /// sats value is rendered with the standard 8-decimal layout
  /// ("0.00 000 550") so the user's keystrokes flow in from the
  /// right.
  String _formatAtmAmount(String digits, String inputCurrency) {
    final sats = digits.isEmpty ? 0 : int.tryParse(digits) ?? 0;
    if (inputCurrency == 'Sats') {
      return sats.toString();
    }
    // BTC mode: render the spaced 8-decimal form via the shared
    // formatter so the gap pattern matches the rest of the app.
    return sats.toFormattedString('BTC');
  }

  /// Split a formatted BTC display string at the boundary between
  /// the "user-typed" trailing digits and the leading-zero padding,
  /// so the padding can be drawn in tertiary color and the typed
  /// digits in primary. `userDigitCount` counts digit characters
  /// (not spaces/decimal) from the right.
  (String leading, String trailing) _splitAtmDisplay(
      String formatted, int userDigitCount) {
    if (userDigitCount <= 0) return (formatted, '');
    int counted = 0;
    int splitIdx = 0;
    for (int i = formatted.length - 1; i >= 0; i--) {
      final ch = formatted.codeUnitAt(i);
      // ASCII '0'..'9'
      if (ch >= 0x30 && ch <= 0x39) {
        counted++;
        if (counted >= userDigitCount) {
          splitIdx = i;
          break;
        }
      }
    }
    return (formatted.substring(0, splitIdx), formatted.substring(splitIdx));
  }

  Future<void> _checkAndPopulateInvoiceAmount(String input) async {
    if (input.isEmpty) return;
    try {
      final parsed = await ref.read(parseInputProvider(input).future);
      // User may have popped the send screen during the parse await; don't
      // setState / touch ref on a disposed widget.
      if (!mounted) return;
      int? amountSat;
      bool shouldLock = false;

      if (parsed is InputType_SparkInvoice) {
        amountSat = parsed.field0.amount?.toInt();
        shouldLock = amountSat != null && amountSat > 0;
      } else if (parsed is InputType_Bolt11Invoice) {
        final amountMsat = parsed.field0.amountMsat;
        if (amountMsat != null) {
          amountSat = (amountMsat ~/ BigInt.from(1000)).toInt();
          shouldLock = true;
        }
      } else if (parsed is InputType_Bolt12Offer) {
        final minAmount = parsed.field0.minAmount;
        if (minAmount is Amount_Bitcoin) {
          amountSat = (minAmount.amountMsat ~/ BigInt.from(1000)).toInt();
          shouldLock = true;
        }
      } else if (parsed is InputType_LnurlPay ||
          parsed is InputType_LightningAddress) {
        BigInt min, max;
        if (parsed is InputType_LnurlPay) {
          min = parsed.field0.minSendable;
          max = parsed.field0.maxSendable;
        } else {
          final req = (parsed as InputType_LightningAddress).field0.payRequest;
          min = req.minSendable;
          max = req.maxSendable;
        }

        if (min == max) {
          amountSat = (min ~/ BigInt.from(1000)).toInt();
          shouldLock = true;
        } else {
          shouldLock = false;
        }
      }

      if (amountSat != null && amountSat > 0 && shouldLock) {
        setState(() {
          isInvoice = true;
          // The invoice dictates the amount — a stale Send-Max drain
          // flag (MAX tapped before this address arrived, e.g. via the
          // scanner route which doesn't pass through
          // `_commitPastedAddress`) must not survive. Draining into a
          // fixed-amount invoice makes prepare run with `feesIncluded`
          // + full balance, which the SDK rejects outright
          // ("FeesIncluded is not supported for invoices with a fixed
          // amount") and Review mislabels as "below network minimum".
          _setDraining(false);
        });
        ref.read(sendTxProvider.notifier).updateAmount(amountSat);
        updateControllerText(amountSat);
        // A fixed-amount Bolt11 is final — amount and destination are
        // both dictated by the invoice, so the Amount and Send-to steps
        // have nothing left to ask. Advance straight to Review. Only
        // Bolt11 gets this; other locked payloads (Spark invoice,
        // Bolt12, fixed LNURL) keep their current step behavior.
        if (parsed is InputType_Bolt11Invoice) {
          _jumpToReviewForInvoice(input);
        }
      } else {
        if (isInvoice) {
          setState(() => isInvoice = false);
        }
      }
    } catch (_) {}
  }

  /// Fixed-amount Bolt11 fast path: skip ahead to Review (internal page
  /// 2) once the invoice's amount has been populated. Reached via the
  /// shared `_checkAndPopulateInvoiceAmount` chokepoint so scan, paste,
  /// gallery and preset-address entries all behave identically. The
  /// user can still tap back into Send-to / Amount; the per-address
  /// one-shot keeps a stray re-parse from yanking them forward again.
  void _jumpToReviewForInvoice(String address) {
    if (!mounted) return;
    // Already at Review (mount-time `_skipAmountStep` path) or beyond.
    if (_step >= 2) return;
    // Cross-chain destination in play — Review for that flow carries
    // state a Bolt11 jump would sidestep.
    if (_selectedDestAsset != null) return;
    // Wallets that can't sign Lightning keep the stepwise flow — the
    // Send-to step is where the "switch to a Lightning wallet" guard
    // renders, so jumping past it would hide the only explanation.
    final w = ref.read(settingsProvider).activeWallet;
    final canUseLightning = w != null &&
        w.sparkEnabled &&
        !w.isWatchOnly &&
        !w.isHardware &&
        !w.isExternalAddress;
    if (!canUseLightning) return;
    if (_invoiceFastPathAddress == address) return;
    _invoiceFastPathAddress = address;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _completedSteps.addAll({0, 1}));
    final type = ref.read(sendTxProvider).type;
    if (!_amountEnteredTracked) {
      _amountEnteredTracked = true;
      TrackingService.sendAmountEntered(network: _networkLabel(type));
    }
    if (!_reviewShownTracked) {
      _reviewShownTracked = true;
      TrackingService.sendReviewShown(network: _networkLabel(type));
    }
    TrackingService.track('send_invoice_fastpath',
        params: {'entry': 'in_flow'});

    void moveToReview() {
      if (!mounted || !_pageCtrl.hasClients) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _pageCtrl.jumpToPage(2);
      } else {
        _pageCtrl.animateToPage(
          2,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    }

    if (_pageCtrl.hasClients) {
      moveToReview();
    } else {
      // Parse can resolve before the PageView's first frame attaches
      // the controller (initState kicks detection off pre-build).
      WidgetsBinding.instance.addPostFrameCallback((_) => moveToReview());
    }
  }

  String _getCurrencyPrefix(String code) {
    switch (code) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'BRL':
        return 'R\$';
      case 'CHF':
        return 'Fr';
      case 'BTC':
        return '₿';
      case 'Sats':
        return '₿';
      default:
        return '';
    }
  }

  Widget _currencyIcon(String code, {double? size}) {
    final s = size ?? 24.sp;
    switch (code) {
      case 'BTC':
        return ClipRRect(
            borderRadius: BorderRadius.circular(s * 0.3),
            child: SvgPicture.asset('lib/assets/bitcoin-icon.svg',
                width: s, height: s));
      case 'Sats':
        return ClipRRect(
            borderRadius: BorderRadius.circular(s * 0.3),
            child: SvgPicture.asset('lib/assets/sats-icon.svg',
                width: s, height: s));
      default:
        return Text(_getCurrencyFlag(code), style: TextStyle(fontSize: s));
    }
  }

  String _getCurrencyFlag(String code) {
    switch (code) {
      case 'USD':
        return '🇺🇸';
      case 'EUR':
        return '🇪🇺';
      case 'GBP':
        return '🇬🇧';
      case 'BRL':
        return '🇧🇷';
      case 'CHF':
        return '🇨🇭';
      default:
        return '';
    }
  }

  /// Resolve the wallet captured at entry, independently of the active
  /// spending account. A removed explicit source never falls back here.
  WalletConfig? _resolveSourceWallet() {
    final settings = ref.read(settingsProvider);
    if (_selectedWalletId == null) return settings.activeWallet;
    for (final wallet in settings.wallets) {
      if (wallet.id == _selectedWalletId) return wallet;
    }
    return null;
  }

  /// A drain's amount is not an input to the build. `drainWallet` +
  /// `drainTo` spend every coin this wallet has and the builder decides
  /// what its one output pays; the amount travels the other way, read
  /// back off that PSBT. Keying the preview on it therefore made the
  /// reviewed transaction a function of a number derived from itself:
  /// every time the figure settled, the approved PSBT was thrown away
  /// and rebuilt, and a send launched into that lost its identity check.
  /// A drain is keyed by the wallet, the recipient and the drain flag,
  /// with the fee rate and the coin selection watched by the provider.
  ///
  /// Nothing is unbound by this. The amount is still compared against
  /// the reviewed PSBT's own output in `_softwareReviewReady`, against
  /// the approved figure in `isCurrent`, and against the transaction
  /// being signed in `BitcoinSoftwareSend.send`.
  BitcoinSoftwareSendRequest _softwareSendRequest(WalletConfig wallet) => (
        walletId: wallet.id,
        address: stripBitcoinAddress(addressController.text),
        amount: _isDraining ? 0 : ref.read(sendTxProvider).amount,
        drain: _isDraining,
      );

  bool _softwareReviewReady(onchain.Psbt? psbt, int amount) {
    if (psbt == null) return false;
    try {
      psbt.fee();
      return !_isDraining ||
          BitcoinSoftwareSend.drainRecipientSats(psbt) == amount;
    } catch (_) {
      return false;
    }
  }

  /// The readiness conditions that can resolve on their own if you
  /// simply wait: the MAX netting and the software wallet's PSBT
  /// preview. These used to grey the Send button out; now they are
  /// waited on AFTER the tap instead.
  ///
  /// Nothing is relaxed here. Every fact this returns true on is
  /// re-read and re-compared inside `_handleSend` against what is
  /// about to be broadcast (the approved amount, the drain flag and
  /// the reviewed PSBT), and that check still refuses the send if it
  /// does not line up. This only moves the waiting.
  bool _sendReadyToDispatch() {
    if (isCalculatingMax) return false;
    final wallet = _resolveSourceWallet();
    if (wallet == null) return false;
    if (!wallet.isBitcoinSoftware) return true;
    final preview = ref
        .read(bitcoinSoftwareSendPreviewProvider(_softwareSendRequest(wallet)));
    if (preview.isLoading || preview.hasError) return false;
    return _softwareReviewReady(
        preview.valueOrNull, ref.read(sendTxProvider).amount);
  }

  /// Why the post-tap wait can never finish, or null while it may
  /// still land. Each branch returns a sentence the screen is already
  /// showing somewhere, so the spinner stops on the same reason the
  /// user can read rather than on silence.
  String? _sendReadinessDeadEnd() {
    final wallet = _resolveSourceWallet();
    if (wallet == null) return context.l10n.sendCouldNotPrepare;
    if (!wallet.isBitcoinSoftware) return null;
    final preview = ref
        .read(bitcoinSoftwareSendPreviewProvider(_softwareSendRequest(wallet)));
    if (!preview.hasError) return null;
    return _formatFeeError(preview.error!);
  }

  /// Send tap. The button is live as soon as the Review step itself
  /// is valid, so this is where the waiting happens: dispatch at once
  /// when the draft is ready, otherwise spin, poll, and dispatch the
  /// moment it becomes ready. A dead end stops the spinner and says
  /// why instead of failing quietly.
  Future<void> _sendPressed(BuildContext context, WidgetRef ref) async {
    // In-flight guard first, so a double tap during a send (or after it
    // finished) neither counts as `pay_review_send_pressed` nor re-enters
    // _handleSend, which would bail on the same flags anyway.
    if (_sendAwaitingReady ||
        isProcessing ||
        _paymentAuthInFlight ||
        _sendCompleted) {
      return;
    }
    if (_sendReadyToDispatch()) {
      TrackingService.track('pay_review_send_pressed',
          params: {'waited': false});
      TrackingService.moneyFlowSubmitted('send', props: _sendFlowInputs());
      await _handleSend(context, ref);
      return;
    }
    TrackingService.track('pay_review_send_pressed', params: {'waited': true});
    setState(() => _sendAwaitingReady = true);
    var ready = false;
    String? failure;
    var deadEndStreak = 0;
    // ~20 s of 120 ms polls. The draft normally lands well inside a
    // second; the ceiling only exists so a spinner can never outlive
    // the user's patience without a word.
    for (var i = 0; i < 166; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (_sendReadyToDispatch()) {
        ready = true;
        break;
      }
      final deadEnd = _sendReadinessDeadEnd();
      // Two consecutive reads, so one blink of an error state while a
      // fresh draft is being prepared does not abort a live wait.
      deadEndStreak = deadEnd == null ? 0 : deadEndStreak + 1;
      if (deadEndStreak >= 2) {
        failure = deadEnd;
        break;
      }
    }
    if (!mounted) return;
    setState(() => _sendAwaitingReady = false);
    if (!ready) {
      TrackingService.track('pay_review_send_wait_gave_up', params: {
        'reason': failure == null ? 'timeout' : 'dead_end',
      });
      if (!context.mounted) return;
      showMessageSnackBar(
        message: failure ?? context.l10n.sendWaitForFee,
        error: true,
        context: context,
      );
      return;
    }
    if (!context.mounted) return;
    TrackingService.moneyFlowSubmitted('send', props: _sendFlowInputs());
    await _handleSend(context, ref);
  }

  /// True when the resolved SOURCE is a cold wallet (hardware /
  /// watch-only / external-address). Cold sources are
  /// bitcoin-on-chain-only: cross-chain sends are Orchestra deliveries
  /// from the Spark hot wallet, so no cross-chain destination may
  /// render or be reachable from them. The picked ACCOUNT is checked
  /// too, so a cold account whose WalletConfig can't be resolved
  /// (null `_selectedWalletId`, hot active wallet) still gates.
  bool get _isColdSource {
    final w = _resolveSourceWallet();
    if (w != null && !w.isSparkWallet) {
      return true;
    }
    return _selectedAccount is BtcColdAccount;
  }

  /// The destination picker — THE SAME SHEET THE RECEIVE SIDE OPENS
  /// (coin_asset_grid.dart): a grid of coins, and the network asked
  /// second and only for a coin that lives on more than one. It used
  /// to be a chain rail with (asset, network) rows under it, which
  /// asked the network question first; nobody thinks "USDC on
  /// Arbitrum" first, in either direction.
  ///
  /// The [kOrchestraSendableChains] clip stays authoritative — it is
  /// applied where the rows are built, so only Orchestra-routable
  /// destinations are offered — and the pinned native destination row
  /// (Bitcoin Network) stays above the grid: it IS meaningful on send,
  /// unlike receive.
  ///
  /// [initialAssetCode] (USDC/USDT shortcuts, unified-search presets)
  /// opens the sheet straight on that coin's networks.
  void _showDestinationPicker(BuildContext context,
      {String? initialAssetCode}) {
    // COLD GATE: hardware / watch-only / external-address sources are
    // bitcoin-on-chain-only (Orchestra routes from Spark). Every entry point
    // funnels through here (USDC/USDT shortcuts, the other-chain
    // tile, the unified-search pending-asset bootstrap), so a cold
    // source can never reach a cross-chain destination. Any preset
    // destination resets to the plain BTC send, with a quiet notice.
    if (_isColdSource) {
      final hadPreset =
          _selectedDestAsset != null || _selectedDestNetwork != null;
      if (hadPreset) {
        setState(() {
          _selectedDestAsset = null;
          _selectedDestNetwork = null;
          _swapQuote = null;
        });
      }
      // Categorical only: which entry point tried to cross-chain from a
      // cold source, and whether a destination had to be dropped.
      TrackingService.track('send_cold_destination_reset', params: {
        'preset_asset': initialAssetCode?.toLowerCase() ?? 'none',
        'had_destination': hadPreset,
      });
      showMessageSnackBarInfo(
        context: context,
        message: context.l10n.sendThisWalletCanOnlySendBitcoin,
      );
      return;
    }

    // Rail-family clip: a positively-identified pasted address (EVM /
    // Solana / Tron / XRP) removes every chain outside its family so
    // the user can't pick an obviously-wrong destination (the `0x…` →
    // `SOL · Solana` case). 'unknown' keeps the full list and lets
    // the provider reject server-side if needed.
    final family = _addressRailFamily(addressController.text);
    final eligible = _eligibleNetworksForFamily[family];

    showAppBottomSheet(
      context: context,
      builder: (sheetCtx) => Consumer(builder: (ctx, sheetRef, _) {
        // WATCH the live Flashnet route catalog (self-initializing on
        // first read) so the rows re-derive the moment it lands: with
        // a one-shot read, the very first open of this sheet showed
        // the static stablecoin fallback until it was reopened.
        final catalog = sheetRef.watch(orchestraSupportedRoutesProvider);
        final loading = sheetRef.watch(orchestraRoutesReadyProvider).isLoading;
        final options = _sendDestOptions(catalog, sheetCtx.l10n);
        // The same clip as before: it narrows the GRID now instead of
        // the flat list, which is the only difference.
        final visible = eligible == null
            ? options
            : options.where((o) => eligible.contains(o.chain)).toList();

        final l10n = sheetCtx.l10n;

        // ── Pinned native destination row: the same-rail default,
        // Bitcoin Network (Spark / Lightning / on-chain). Cold sources
        // never reach this sheet, so the full "Bitcoin, Lightning &
        // Spark" hint is always truthful here. It sits ABOVE the coin
        // grid because it is not one of the coins the money would be
        // converted to: it is the money staying as it is.
        final Widget pinned = PickerGroupedList(
          children: [
            PickerRow(
              // Bare Bitcoin SVG — recognisable on its own, no
              // tinted halo / rounded disc.
              leading: SvgPicture.asset('lib/assets/bitcoin-icon.svg',
                  width: 36.sp, height: 36.sp),
              title: l10n.bitcoinNetwork,
              subtitle: l10n.bitcoinLightningSpark,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                if (!mounted) return;
                setState(() {
                  _selectedDestAsset = null;
                  _selectedDestNetwork = null;
                  _swapQuote = null;
                });
              },
            ),
          ],
        );

        return CoinAssetPickerSheet(
          groups: groupCoinsByAsset(visible.map(_sendDestPickerRow).toList()),
          title: l10n.sendWhereTo,
          subtitle: l10n.sendWhereShouldTheMoneyLand,
          // Still fetching is not the same as nothing to offer.
          emptyLabel: loading ? l10n.receiveCoinsLoading : l10n.noResults,
          flow: 'send',
          initialAssetCode: initialAssetCode,
          selectedOptionId: _selectedDestAsset != null &&
                  _selectedDestNetwork != null
              ? '${_selectedDestNetwork!.network}:${_selectedDestAsset!.code}'
              : null,
          pinned: pinned,
          onPicked: (row) {
            Navigator.of(sheetCtx).pop();
            TrackingService.swapAssetSelected(
                flow: 'send', asset: row.assetCode);
            if (!mounted) return;
            final isBridged = row.assetCode.toUpperCase() == 'USDC.E';
            final isDollars = isOrchestraUsdRoute(row.chain, row.assetCode);
            final normCode = isBridged ? 'USDC' : row.assetCode.toUpperCase();
            final top = kTopCoins
                .where((t) => t.code.toUpperCase() == normCode)
                .firstOrNull;
            setState(() {
              _selectedDestAsset = _DestAsset(
                // The bridged variant keeps its literal code — the
                // contract matters (see orchestraAssetCodeFor).
                code: isBridged ? 'USDC.e' : normCode,
                name: isBridged
                    ? 'USD Coin (USDC.e)'
                    // `displayName` is already the dollar label for
                    // the dollar row.
                    : (top?.name ?? row.displayName),
                color: _getCoinColor(normCode),
                // The dollar balance has a local mark; the catalogue
                // ships no artwork for it.
                svgAsset: isDollars ? kUsdMarkAsset : top?.svgAsset,
                // No local brand SVG → the same remote mark the picker
                // row showed, so the selection summary and the
                // transaction modal stay visually consistent.
                iconUrl: (top == null && !isDollars)
                    ? orchestraAssetIconUrl(row.assetCode)
                    : null,
              );
              _selectedDestNetwork = _DestNetwork(
                network: row.chain,
                name: row.chainDisplayName,
                addressHint: isDollars
                    ? context.l10n.sendDollarAccountAddressHint
                    : context.l10n.sendAssetOnNetworkAddressHint(
                        row.displaySymbol, row.chainDisplayName),
              );
              _swapQuote = null;
            });
            _fetchRate();
          },
        );
      }),
    );
  }

  void _debouncedFetchRate() {
    _rateDebounce?.cancel();
    _rateDebounce = Timer(const Duration(milliseconds: 500), () {
      _fetchRate();
    });
  }

  Future<void> _fetchRate() async {
    final asset = _selectedDestAsset;
    final network = _selectedDestNetwork;
    if (asset == null || network == null) return;
    final amount = ref.read(sendTxProvider).amount;
    if (amount <= 0) {
      setState(() {
        _swapQuote = null;
        _rateError = null;
        _loadingRate = false;
      });
      return;
    }

    setState(() {
      _loadingRate = true;
      _swapQuote = null;
      _rateError = null;
    });

    final btcAmount = _satsToBtc(amount);
    final isLightning = network.network.toLowerCase() == 'lightning';
    try {
      // On-chain to Lightning bridging is retired. Native spending-wallet
      // Lightning payments use the SDK and do not create a swap quote.
      if (isLightning) {
        if (mounted) {
          setState(() {
            _loadingRate = false;
            _rateError = context.l10n.swapRouteTemporarilyUnavailable;
          });
        }
        return;
      }
      // Orchestra is the only cross-chain route: Spark hot-wallet BTC →
      // the destination coin (see orchestra_routes.dart). The estimate
      // doubles as a live route probe (deposit_sheet.dart pattern).
      // Hardware/watch-only sources have no cross-chain route.
      if (_hasSource && _isSparkHotWalletSource()) {
        final orchChain = orchestraSendChainFor(asset.code, network.network);
        if (orchChain != null) {
          final est = await OrchestraService.getEstimate(
            sourceChain: 'spark',
            sourceAsset: 'BTC',
            destinationChain: orchChain,
            destinationAsset: orchestraAssetCodeFor(asset.code),
            amount: amount.toString(), // sats — source smallest units
          );
          final grossOut = est.data == null
              ? 0.0
              : orchestraAmountToDouble(est.data!.estimatedOut, asset.code,
                  chain: orchChain);
          // The estimate leaves the Kute fee out; the quote that is paid
          // takes it. Under a provider-default plan the rate is unknown
          // and the provider's own figure is the closest one there is.
          final estOut = est.data == null
              ? 0.0
              : orchestraOutNetOfKuteFee(est.data!, grossOut) ?? grossOut;
          if (estOut > 0) {
            if (mounted) {
              setState(() {
                _loadingRate = false;
                _swapQuote = SwapQuote(
                  provider: 'Orchestra',
                  fromCcy: 'BTC', toCcy: asset.code,
                  rexmoFrom: 'BTC:SPARK',
                  rexmoTo: '${asset.code}:${network.network}',
                  networkFrom: 'BTC', networkTo: network.network,
                  fromAmount: btcAmount, toAmount: estOut,
                  // Orchestra publishes no min/max band; a true limit
                  // surfaces as a quote error at Send time, before any
                  // funds move.
                );
                _rateError = null;
              });
            }
            return;
          }
          // Estimate failed / zero — Orchestra doesn't serve this
          // route right now.
        }
      }
      // Any route Orchestra didn't serve above is unavailable.
      if (mounted) {
        setState(() {
          _loadingRate = false;
          _rateError = context.l10n.swapRouteTemporarilyUnavailable;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRate = false;
          _rateError = context.l10n.receiveNetworkErrorTapToRetry;
        });
      }
    }
  }

  // ── Step-up binding (Wallet Hardening Phase 1b.2) ─────────────────

  void _dropSendGrant() {
    _sendGrant?.revoke();
    _sendGrant = null;
  }

  String _btcAmountLabel(int sats) {
    final btcFormat = ref.read(settingsProvider).btcFormat;
    return '${sats.toFormattedString(btcFormat)} $btcFormat';
  }

  static String _sendStepName(int page) => switch (page) {
        0 => 'amount',
        1 => 'send_to',
        2 => 'review',
        3 => 'sign',
        _ => 'page_$page',
      };

  static String _utxoCountBucket(int n) => n <= 1
      ? '$n'
      : n <= 3
          ? '2-3'
          : n <= 10
              ? '4-10'
              : '10+';

  /// What the user has entered so far (send funnel props). Never the
  /// address, invoice or balance.
  Map<String, Object> _sendFlowInputs() {
    try {
      final tx = ref.read(sendTxProvider);
      final sats = tx.amount;
      final usd = sats > 0 ? _usdForSats(sats) : null;
      final customFee = ref.read(customFeeRateProvider);
      final blocks = ref.read(sendBlocksProvider);
      final utxos = ref.read(selectedUtxosProvider).length;
      final address = addressController.text.trim();
      final dest = _selectedDestAsset;
      final inputs = <String, Object>{
        'network': _networkLabel(tx.type),
        'source_asset': 'btc',
        if (_sendWalletKind() case final kind?) 'wallet_kind': kind,
        if (_addressEntryMethod != null)
          'address_entry_method': _addressEntryMethod!,
        if (address.isNotEmpty)
          'address_type': _trackingAddressType(_detectAddressType(address)),
        'amount_unit': ref.read(inputCurrencyProvider).toLowerCase(),
        if (_amountMethod != null) 'amount_method': _amountMethod!,
        'max_used': _isDraining,
        if (dest != null)
          ...TrackingService.routeParams(
            fromAsset: 'btc',
            fromNetwork: _networkLabel(tx.type),
            toAsset: dest.code,
            toNetwork: _selectedDestNetwork?.network,
          ),
        ...TrackingService.moneyParams(
          amountUsd: usd,
          amount: sats <= 0 ? null : sats / 1e8,
          asset: 'btc',
          amountSats: sats <= 0 ? null : sats,
        ),
        'fee_tier': customFee != null
            ? 'custom'
            : switch (blocks) {
                1 => 'fast',
                2 => 'standard',
                3 => 'slow',
                _ => 'custom',
              },
        'custom_fee': customFee != null,
        'coin_control': utxos > 0,
        if (utxos > 0) 'utxo_count_bucket': _utxoCountBucket(utxos),
      };
      _lastSendInputs = inputs;
      return inputs;
    } catch (_) {
      return _lastSendInputs;
    }
  }

  /// `wallet_kind` of the send source ([wallet], else the resolved
  /// source) for `send_completed` / `send_failed`.
  String? _sendWalletKind([WalletConfig? wallet]) {
    final w = wallet ?? _resolveSourceWallet();
    if (w == null) return null;
    return TrackingService.walletKind(
      isLedger: w.isLedger,
      isHardware: w.isHardware,
      isWatchOnly: w.isWatchOnly,
      isSigner: w.isSigner,
      isExternalAddress: w.isExternalAddress,
    );
  }

  /// Display currency for send outcome events, and the fiat amount when
  /// the user typed the amount in fiat (null when typed in sats / BTC).
  /// Read before the send's first await: the unit provider is autoDispose.
  ({String currency, double? amountFiat}) _sendFiatContext() {
    try {
      final unit = ref.read(inputCurrencyProvider);
      if (unit != 'Sats' && unit != 'BTC') {
        return (
          currency: unit,
          amountFiat: double.tryParse(controller.text.trim()),
        );
      }
    } catch (_) {}
    return (currency: currency, amountFiat: null);
  }

  /// Approximate USD value, only ever bucketed for events.
  double? _usdForSats(int sats) {
    try {
      final usdPerBtc = ref.read(selectedCurrencyProvider('usd')).toDouble();
      return usdPerBtc > 0 ? sats / 1e8 * usdPerBtc : null;
    } catch (_) {
      return null;
    }
  }

  /// Fee of a prepared Spark SDK payment, in sats, for the chosen speed:
  /// the whole on-chain exit fee (service plus L1 broadcast), or the
  /// Spark transfer fee. Null for any other method.
  static int? _preparedFeeSats(
      PrepareSendPaymentResponse resp, OnchainConfirmationSpeed speed) {
    final method = resp.paymentMethod;
    if (method is SendPaymentMethod_BitcoinAddress ||
        method is SendPaymentMethod_SparkAddress ||
        method is SendPaymentMethod_SparkInvoice) {
      return sparkPreparedFeeSats(resp, speed);
    }
    return null;
  }

  /// The key a Spark (on-chain / Spark address) prepare is read and
  /// watched under. While draining the SDK sends the whole balance and
  /// ignores the entered amount, so the key carries 0: the Review writer
  /// then replaces the amount with the one this very preparation
  /// resolves to without re-keying (and re-quoting) the preparation it
  /// was read from. Same one-writer rule as `_softwareSendRequest`.
  ({String destination, int amountSats, bool isDraining}) _sparkPrepareKey(
          String address, int amountSats) =>
      (
        destination: address,
        amountSats: _isDraining ? 0 : amountSats,
        isDraining: _isDraining,
      );

  /// Lightning twin of [_sparkPrepareKey].
  ({String address, int amount, String? comment, bool isDraining})
      _lightningPrepareKey(String address, int amountSats) => (
            address: address,
            amount: _isDraining ? 0 : amountSats,
            comment: null,
            isDraining: _isDraining,
          );

  /// The amount a prepared Spark SDK send resolves a 100% to on Review.
  ///
  /// Spark on-chain and Spark address drains show what the recipient
  /// gets: the whole balance less the fee the SDK takes for the selected
  /// speed. Lightning keeps the SDK's own gross figure (the balance, or
  /// an LNURL recipient's cap), the amount the payment debits, because
  /// the routing fee is only settled at send time; Review then totals it
  /// without adding the fee on top. Null for a send that is not a drain.
  int? _sparkDrainResolvedSats(Object prepared) {
    if (prepared is PrepareSendPaymentResponse) {
      if (prepared.feePolicy != FeePolicy.feesIncluded) return null;
      if (prepared.paymentMethod is SendPaymentMethod_Bolt11Invoice) {
        return prepared.amount.toInt();
      }
      return sparkPreparedRecipientSats(prepared, _sparkOnchainSpeed);
    }
    if (prepared is PrepareLnurlPayResponse) {
      if (prepared.feePolicy != FeePolicy.feesIncluded) return null;
      return prepared.amountSats.toInt();
    }
    return null;
  }

  /// The send intent for one route. [feeCap] is the reviewed fee in the
  /// source asset's base units; an actual fee above it re-auths.
  SensitiveIntent _sendIntent({
    required String venue,
    required String destination,
    required BigInt amountMax,
    required String provider,
    required String sourcePool,
    String asset = 'BTC',
    String? account,
    String? walletId,
    Object? feeCap,
    Map<String, Object?> extra = const {},
  }) {
    return SensitiveIntent(
      action: SensitiveAction.send,
      walletId: walletId ?? _resolveSourceWallet()?.id ?? '',
      venue: venue,
      account: account,
      destination: destination.trim(),
      asset: asset,
      amountMax: amountMax,
      limits: {
        IntentLimit.provider: provider,
        IntentLimit.maxMode: _isDraining,
        'sourcePool': sourcePool,
        if (feeCap != null) IntentLimit.maxFee: feeCap,
        ...extra,
      },
    );
  }

  /// Orchestra-funded send: binds the final recipient and the route, never
  /// the per-quote deposit address (the quote gate checks that). The fee
  /// cap is the quote's fee in basis points.
  SensitiveIntent _orchestraSendIntent(
    SettlementAuthorizationIntent auth, {
    required String destAsset,
  }) {
    final sep = auth.destination.lastIndexOf('|');
    final recipient =
        sep < 0 ? auth.destination : auth.destination.substring(0, sep);
    final version = sep < 0 ? '' : auth.destination.substring(sep + 1);
    return SensitiveIntent.orchestraFunded(
      action: SensitiveAction.send,
      walletId: auth.walletId,
      finalRecipient: recipient.trim(),
      routeVersion:
          version.isEmpty ? auth.routeLabel : '${auth.routeLabel}|$version',
      asset: 'BTC',
      amountMax: auth.amountIn,
      limits: {
        IntentLimit.minReceive: auth.minReceive,
        IntentLimit.maxFee: auth.maxFeeBps,
        IntentLimit.maxMode: _isDraining,
        'sourcePool': 'btc',
        'destAsset': destAsset,
      },
    );
  }

  /// Fixed invoices and send-max preparations determine the amount that will
  /// actually be sent. Show any adjustment before asking for authorization.
  Future<bool> _reviewPreparedAmount(
      BuildContext context, int reviewedAmount, int preparedAmount) async {
    if (preparedAmount <= 0) {
      throw StateError('The prepared payment amount must be positive.');
    }
    if (!mounted || !context.mounted) return false;
    final changed = _sendReviewDrift?.call() ?? const <DriftField>{};
    if (changed.isNotEmpty) {
      _dropSendGrant();
      await showStepUpReviewAgain(context,
          action: SensitiveAction.send, field: changed.first);
      return false;
    }
    if (preparedAmount == reviewedAmount) return true;
    _dropSendGrant();
    ref.read(sendTxProvider.notifier).updateAmount(preparedAmount);
    updateControllerText(preparedAmount);
    await showStepUpReviewAgain(context,
        action: SensitiveAction.send, field: DriftField.amount);
    return false;
  }

  /// Prompts for [intent] when this attempt holds no grant yet; otherwise
  /// checks the held grant still covers it (a laddered retry, a requote or
  /// a provider fallback). Returns false when the user declined, the review
  /// changed during the prompt, or the intent drifted (C8 shown).
  Future<bool> _approveSend(
    BuildContext context,
    SensitiveIntent intent, {
    required String amountLabel,
    double? amountUsd,
  }) async {
    final held = _sendGrant;
    if (held != null) {
      try {
        AuthGrants.check(held, intent);
        return true;
      } on ReauthRequired catch (e) {
        _dropSendGrant();
        await showStepUpReviewAgain(context,
            action: intent.action, field: e.primaryFieldClass);
        return false;
      } on AuthGrantException {
        // Expired or already used: ask again for what is about to be sent.
        _dropSendGrant();
      }
    }
    if (!mounted || !context.mounted) return false;
    TrackingService.moneyFlowStep('send', 'approval');
    setState(() => _paymentAuthInFlight = true);
    final AuthGrant? grant;
    try {
      grant = await requireFreshAuthGrant(
        context,
        ref,
        intent: intent,
        reason: context.l10n.stepUpReasonSend(amountLabel),
        amountUsd: amountUsd,
      );
    } finally {
      if (mounted) {
        setState(() => _paymentAuthInFlight = false);
      } else {
        _paymentAuthInFlight = false;
      }
    }
    if (grant == null) {
      TrackingService.track('send_approval_result',
          params: {'outcome': 'declined'});
      TrackingService.moneyFlowError('send', 'user_cancelled');
      return false;
    }
    if (!mounted || !context.mounted) {
      grant.revoke();
      return false;
    }
    final changed = _sendReviewDrift?.call() ?? const <DriftField>{};
    if (changed.isNotEmpty) {
      TrackingService.track('send_approval_result',
          params: {'outcome': 'review_again'});
      grant.revoke();
      await showStepUpReviewAgain(context,
          action: intent.action, field: changed.first);
      return false;
    }
    _sendGrant = grant;
    TrackingService.track('send_approval_result',
        params: {'outcome': 'approved'});
    return true;
  }

  /// Consumes the held grant against what is about to be paid. Call right
  /// before the provider call that moves funds.
  Future<bool> _consumeSend(
      BuildContext context, SensitiveIntent actual) async {
    final held = _sendGrant;
    if (held == null) return false;
    try {
      AuthGrants.consume(held, actual);
      return true;
    } on ReauthRequired catch (e) {
      _dropSendGrant();
      if (context.mounted) {
        await showStepUpReviewAgain(context,
            action: actual.action, field: e.primaryFieldClass);
      }
      return false;
    } on AuthGrantException {
      _dropSendGrant();
      return false;
    }
  }

  /// [_approveSend] for the reviewed intent, then [_consumeSend] for the
  /// actual one (for example a max-mode amount clamped down by the SDK).
  Future<bool> _approveAndConsumeSend(
    BuildContext context, {
    required SensitiveIntent reviewed,
    required SensitiveIntent actual,
    required String amountLabel,
    double? amountUsd,
  }) async {
    if (!await _approveSend(context, reviewed,
        amountLabel: amountLabel, amountUsd: amountUsd)) {
      return false;
    }
    if (!context.mounted) return false;
    return _consumeSend(context, actual);
  }

  /// Marks the Sign-step grant used once the signed PSBT comes back. The
  /// device approved the payment and the PSBT was bound when it was built,
  /// so an expired grant here is bookkeeping only.
  void _consumeSignedPsbtGrant() {
    final held = _sendGrant;
    final approved = _signApprovedIntent;
    if (held == null || approved == null) return;
    try {
      AuthGrants.consume(held, approved);
    } on AuthGrantException {
      // The PSBT is already signed by the device.
    }
  }

  Future<void> _handleSwapSend(BuildContext context, WidgetRef ref) async {
    final asset = _selectedDestAsset!;
    final network = _selectedDestNetwork!;
    final withdrawalAddress = addressController.text.trim();
    final amount = ref.read(sendTxProvider).amount;

    if (withdrawalAddress.isEmpty) {
      showMessageSnackBar(
          message: context.l10n.enterAAssetCodeAddress(asset.code),
          error: true,
          context: context);
      return;
    }

    // Cross-chain sends have exactly one route: Orchestra, from bitcoin
    // on the Spark hot wallet (BTC on Spark → the destination coin per
    // orchestra_routes.dart). On-chain wallets cannot bridge to
    // Lightning (spending wallets pay Lightning through the native
    // payment flow), cold sources are bitcoin-on-chain-only, and a
    // null/stale quote (user raced the debounce) or a route Orchestra
    // does not list never moves funds: each reads as route unavailable.
    if (network.network.toLowerCase() == 'lightning' ||
        !_isSparkHotWalletSource() ||
        _swapQuote?.provider != 'Orchestra' ||
        orchestraSendChainFor(asset.code, network.network) == null) {
      showMessageSnackBar(
        message: context.l10n.swapRouteTemporarilyUnavailable,
        error: true,
        context: context,
      );
      return;
    }
    // Spark hot wallet with a live Orchestra quote. 100% resolves
    // here, when the quote is requested: the freshly synced Spark
    // balance, not the figure the chip seeded on the Amount step. A
    // Spark-to-Spark deposit has no fee on top, so the whole balance
    // is what the quote asks for and the SDK sends.
    var orchestraSats = amount;
    if (_isDraining) {
      try {
        final wrapper = await ref.read(breezSDKProvider.future);
        final sdk = wrapper.instance;
        if (sdk != null) orchestraSats = await sparkDrainBalanceSats(sdk);
      } catch (_) {
        // Keep the reviewed figure; the SDK refuses an overdraft.
      }
      if (!context.mounted) return;
    }
    await _handleOrchestraFromBtc(
      context: context,
      ref: ref,
      toAddress: withdrawalAddress,
      amountSats: orchestraSats,
      asset: asset,
      network: network,
    );
  }

  /// True when the wallet funding this send is a Spark hot wallet (the
  /// SDK can sign it). Resolves from `_selectedWalletId` first — the
  /// active wallet is pinned to spending and would misclassify a
  /// hardware/watch-only source.
  bool _isSparkHotWalletSource() {
    final settings = ref.read(settingsProvider);
    final WalletConfig? sourceWallet = _selectedWalletId != null
        ? settings.wallets.firstWhere(
            (w) => w.id == _selectedWalletId,
            orElse: () => settings.activeWallet ?? settings.wallets.first,
          )
        : settings.activeWallet;
    return sourceWallet?.isSparkWallet ?? false;
  }

  /// Hardware / watch-only on-chain BTC signing flow. Mirrors
  /// `confirm_bitcoin_payment._handleWatchOnlySigning`:
  ///   1. Build an unsigned PSBT via BDK using the user's chosen
  ///      fee rate + UTXOs (advanced sheet feeds these providers).
  ///   2. Push the watchOnlySigning route — the screen renders a
  ///      QR / copy interface for the user to sign on their
  ///      hardware device, then comes back with the broadcast
  ///      txid (or null if the user cancels).
  ///   3. On success log the L1 fee + show the same fullscreen
  ///      transaction-sent modal hot-wallet sends use.
  Future<void> _handleHardwareSigning(
      BuildContext context, WidgetRef ref, String toAddress, int amountSats,
      {String provider = 'psbt', String? recipient}) async {
    final generation = ++_hardwareBuildGeneration;
    // Capture the Reduce Motion preference synchronously (before any
    // await) so the post-build page transition can honour it without
    // touching MediaQuery across an async gap.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Stash params before we touch anything else — the Sign-step
    // "Try again" CTA + the speed/UTXO picker's post-close rebuild
    // both replay the build against these.
    _signLastToAddress = toAddress;
    _signLastAmountSats = amountSats;
    _signLastProvider = provider;
    _signLastRecipient = recipient;
    setState(() {
      isProcessing = true;
      _signPageError = null;
    });
    try {
      final walletAtStart = _resolveSourceWallet();
      if (walletAtStart == null) {
        throw const OnchainException('wallet_mismatch');
      }
      final walletIdAtStart = walletAtStart.id;
      final drain = _isDraining;
      final customFee = ref.read(customFeeRateProvider);
      final blocks = ref.read(sendBlocksProvider);
      final reviewAddress = addressController.text;
      final reviewAmount = ref.read(sendTxProvider).amount;
      final utxos =
          List<onchain.OutPoint>.unmodifiable(ref.read(selectedUtxosProvider));
      void checkCurrent() {
        if (!mounted ||
            generation != _hardwareBuildGeneration ||
            _resolveSourceWallet()?.id != walletIdAtStart ||
            _resolveSourceWallet()?.scriptType != walletAtStart.scriptType ||
            _isDraining != drain ||
            addressController.text != reviewAddress ||
            ref.read(sendTxProvider).amount != reviewAmount ||
            ref.read(customFeeRateProvider) != customFee ||
            ref.read(sendBlocksProvider) != blocks ||
            !listEquals(ref.read(selectedUtxosProvider), utxos)) {
          throw const OnchainException('review_changed');
        }
      }

      // Every await on this path is bounded. The Sign step renders a
      // loader for as long as it has neither a PSBT nor an error, so an
      // await that can hang has no terminal state at all — it is the
      // stuck "fee never arrives, Sign never enables" report. A
      // TimeoutException here reads as "fee estimate unavailable"
      // through `_humanizeSignError`, with the inline Try again.
      final feeRate = await ref
          .read(getCustomFeeRateProvider.future)
          .timeout(const Duration(seconds: 20));
      checkCurrent();
      final model = await ref
          .read(bitcoinModelForWalletProvider(walletIdAtStart).future)
          .timeout(const Duration(seconds: 20));
      checkCurrent();
      final builder = TransactionBuilder(
          amountSats, stripBitcoinAddress(toAddress), feeRate,
          selectedUtxos: utxos.isNotEmpty ? utxos : null);
      // A scan in flight holds the wallet's native slot. Wait for it
      // instead of failing the Sign step as busy; the PSBT is still
      // built from this wallet's own state. The wait is capped as a
      // whole and holds a slot reservation, so a scan cannot keep
      // re-taking the slot ahead of this build.
      final psbt = await buildPsbtWhenIdle(model, builder,
          drain: drain, budget: kSignStepSlotBudget);
      checkCurrent();
      final recipientSats = reviewedBitcoinRecipientSats(
        psbt,
        stripBitcoinAddress(toAddress),
        mainnet: model.config.network == onchain.Network.bitcoin,
      );
      if (drain) {
        BitcoinSoftwareSend.drainRecipientSats(psbt);
      } else if (recipientSats != amountSats) {
        throw const OnchainException('review_changed');
      }

      if (!mounted ||
          !context.mounted ||
          generation != _hardwareBuildGeneration) {
        return;
      }
      int? feeSats;
      try {
        feeSats = psbt.fee();
      } catch (_) {
        feeSats = null;
      }
      // Phase 1b.2: the PSBT and its fee exist before the prompt. A rebuild
      // on the Sign step checks the held grant instead, so a fee within the
      // approved cap does not prompt again and a higher one shows C8.
      final signIntent = _sendIntent(
        walletId: walletIdAtStart,
        venue: 'bitcoin',
        destination: stripBitcoinAddress(toAddress),
        amountMax: BigInt.from(recipientSats),
        provider: provider,
        sourcePool: 'btc',
        feeCap: feeSats,
        extra: {if (recipient != null) 'recipient': recipient},
      );
      final approved = await _approveSend(
        context,
        signIntent,
        amountLabel: _btcAmountLabel(recipientSats),
        amountUsd: _usdForSats(recipientSats),
      );
      if (!mounted ||
          !context.mounted ||
          generation != _hardwareBuildGeneration) {
        return;
      }
      if (!approved) {
        setState(() {
          isProcessing = false;
          if (_step == 3) {
            _signPageError =
                context.l10n.stepUpReasonSend(_btcAmountLabel(amountSats));
          }
        });
        return;
      }
      checkCurrent();
      _signApprovedIntent = signIntent;
      // The review is over: the PSBT is what the device signs.
      _sendReviewDrift = null;
      // Mirror the address into sendTxProvider so the embedded
      // signing screen's transaction-summary + post-broadcast
      // success modal read the right destination (swap deposit
      // address for Lightning hardware sends, or the user's chosen
      // address for plain on-chain sends).
      ref.read(sendTxProvider.notifier).updateAddress(toAddress);
      ref.read(sendTxProvider.notifier).updateAmount(amountSats);
      setState(() {
        _builtPsbt = psbt.serialize();
        _builtPsbtRecipientAddress = stripBitcoinAddress(toAddress);
        _builtPsbtWallet = walletAtStart;
        _builtPsbtFeeSats = feeSats;
        _builtPsbtRecipientSats = recipientSats;
        _completedSteps.add(2);
        isProcessing = false;
        _signPageError = null;
      });
      if (reduceMotion) {
        _pageCtrl.jumpToPage(3);
      } else {
        _pageCtrl.animateToPage(
          3,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      if (!mounted || generation != _hardwareBuildGeneration) return;
      // Inline-error path. The Sign page renders an error card with a
      // "Try again" CTA so the user can change network speed / coin
      // selection / amount and retry without backing out of the
      // stepper. The previous snackbar dismissed itself and left the
      // user with a blank Sign screen and no recovery affordance.
      if (mounted) {
        setState(() {
          isProcessing = false;
          _signPageError = _humanizeSignError(e);
          _signPageErrorDetail = errorDetailText(e);
        });
        // Still animate the user onto the Sign page so the error is
        // visible alongside the inline retry CTA — staying on Review
        // would just dump a snackbar on a screen with no visible
        // change. The page knows how to render the error state when
        // `_builtPsbt` is null AND `_signPageError` is non-null.
        if (_pageCtrl.hasClients) {
          if (reduceMotion) {
            _pageCtrl.jumpToPage(3);
          } else {
            _pageCtrl.animateToPage(
              3,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
          }
        }
      }
    } finally {
      // The Sign step shows its loader for exactly "no PSBT and no
      // error", and several guards above leave the build by a bare
      // return — a context that unmounted across an await, or a
      // generation bump. Any of those used to strand the step on that
      // loader with `isProcessing` still true and no way back. End on a
      // state the user can act on: Review re-enables its button, Sign
      // shows its error card with Try again. A build superseded by a
      // newer generation is left alone — that one owns the state now.
      if (mounted &&
          generation == _hardwareBuildGeneration &&
          _builtPsbt == null &&
          isProcessing) {
        setState(() {
          isProcessing = false;
          if (_step == 3 && _signPageError == null) {
            _signPageError = context.l10n.sendCouldNotPrepare;
          }
        });
      }
    }
  }

  /// Translate a raw BDK / SDK error into a Sign-step actionable
  /// message. "Output below dust", "Amount is too small", "Amount is
  /// below minimum", "Insufficient funds" all map to a single
  /// user-facing copy so the inline error card stays predictable
  /// regardless of which engine threw.
  String _humanizeSignError(Object e) {
    if (_isFeeUnavailable(e)) return context.l10n.feeEstimateUnavailable;
    // A refused native build carries a code, not a sentence — its
    // `toString` is the same generic line for every cause, so the raw-text
    // checks below can never reach it. Read the code first so the Sign
    // step names the input to correct instead of parking on one sentence.
    if (e is OnchainException) return _onchainCodeCopy(e);
    final raw = e.toString().toLowerCase();
    if (raw.contains('amount is too small') ||
        raw.contains('below dust') ||
        raw.contains('below minimum') ||
        raw.contains('below the minimum') ||
        raw.contains('minimal non dust') ||
        raw.contains('below the minimal')) {
      return context.l10n.sendAmountBelowNetworkMinimumOnChain;
    }
    if (raw.contains('insufficient')) {
      return context.l10n.sendNotEnoughBalanceCoverFee;
    }
    if (raw.contains('address') && raw.contains('invalid')) {
      return context.l10n.sendTheDestinationAddressIsInvalid;
    }
    return userErrorCopy(context, e,
        fallback: context.l10n.sendCouldNotPrepare);
  }

  /// One sentence for a refused on-chain build, keyed off the exception's
  /// code. Every argument the native builder can reject has its own code,
  /// so the user is pointed at the amount, the address or the fee rather
  /// than at "what you entered" with nothing on screen to change.
  String _onchainCodeCopy(OnchainException e) => switch (e.code) {
        'invalid_address' => context.l10n.sendTheDestinationAddressIsInvalid,
        'invalid_amount' => context.l10n.sendAmountBelowNetworkMinimumOnChain,
        'invalid_fee_rate' => context.l10n.feeEstimateUnavailable,
        'insufficient_funds' => context.l10n.sendNotEnoughBalanceCoverFee,
        _ =>
          userErrorCopy(context, e, fallback: context.l10n.sendCouldNotPrepare),
      };

  /// Definitive outcome page for a send that failed after the user
  /// tapped Send: the shared confirmation overlay in its non-success
  /// form with the plain sentence and Try again, which drops back to
  /// Review. A failure the app recognises (not enough balance, a fee
  /// that moved, an amount under the network minimum, a bad address) is
  /// said in full by that sentence; only an unrecognised one adds a
  /// Details disclosure holding the raw engine message. Nothing is
  /// retried from here; the user re-reviews and taps Send again.
  void _showSendFailed(Object error, {String? message}) {
    if (!mounted) return;
    final known = message == null ? _knownSendErrorCopy(error) : null;
    final copy = message ??
        known ??
        userErrorCopy(context, error, fallback: context.l10n.sendCouldNotSend);
    final raw = error.toString().trim();
    final nav = Navigator.of(context);
    pushKuteSuccessOverlay(
      navigator: nav,
      overlay: KuteConfirmation(
        success: false,
        message: context.l10n.sendFailedTitle,
        detail: copy,
        receipt: known != null || raw.isEmpty || raw == copy
            ? null
            : _SendFailureDetails(raw: raw),
        buttonText: context.l10n.walletsTryAgain,
        onDone: () {
          if (nav.canPop()) nav.pop();
        },
      ),
    );
  }

  /// The plain sentence for a send failure the app recognises, or null
  /// for one it does not (which then reads as "Couldn't send" with the
  /// raw text under Details). Not enough balance is matched by type
  /// first: an LNURL or Lightning address payment the balance cannot
  /// cover with its routing fee is refused by the SDK as
  /// [SdkError_InsufficientFunds], which [handlePaymentException] turns
  /// into a [SparkInsufficientFundsException]; the text match stays for
  /// engines that only say it in words.
  String? _knownSendErrorCopy(Object e) {
    if (isSparkInsufficientFunds(e)) {
      return context.l10n.sendNotEnoughBalanceCoverFee;
    }
    final raw = e.toString().toLowerCase();
    // The SDK re-checks a fees-included send's fee at dispatch and
    // refuses one that moved since Review; nothing left the wallet. An
    // on-chain send re-quotes an expired fee itself (breez 0.26) and
    // refuses only when even the slowest speed costs more than Review
    // showed ("The onchain fee rose to ...").
    if (raw.contains('fee increased') ||
        raw.contains('fee overpayment') ||
        raw.contains('fee rose')) {
      return context.l10n.sendFeeChangedTryAgain;
    }
    if (raw.contains('insufficient')) {
      return context.l10n.sendNotEnoughBalanceCoverFee;
    }
    if (raw.contains('amount is too small') ||
        raw.contains('below dust') ||
        raw.contains('below minimum') ||
        raw.contains('below the minimum') ||
        raw.contains('minimal non dust') ||
        raw.contains('below the minimal')) {
      return context.l10n.sendAmountBelowNetworkMinimumOnChain;
    }
    if (raw.contains('address') && raw.contains('invalid')) {
      return context.l10n.sendTheDestinationAddressIsInvalid;
    }
    return null;
  }

  /// Direct BTC-on-Spark → stablecoin send via Flashnet Orchestra.
  /// Mirrors move_sheet's convert pattern: createQuote (spark/BTC →
  /// destChain/destAsset, recipient = the user's address) → pay the
  /// quote's Spark deposit address via the SDK → submitDeposit with
  /// the Spark tx hash → record a SwapOrder(provider:
  /// 'Orchestra') row so history + background sync track it (including
  /// the q_ → ord_ id swap when /submit hasn't returned the real order
  /// id yet).
  ///
  /// Quote failures happen BEFORE any funds move, so they end the send
  /// with the route-unavailable notice. Once the Spark send is
  /// dispatched, errors only surface — never re-send.
  Future<void> _handleOrchestraFromBtc({
    required BuildContext context,
    required WidgetRef ref,
    required String toAddress,
    required int amountSats,
    required _DestAsset asset,
    required _DestNetwork network,
  }) async {
    final chain = orchestraSendChainFor(asset.code, network.network);
    if (chain == null) {
      // Shouldn't happen — the dispatch gate checks the table — but a
      // missing route must never dead-end a send silently.
      showMessageSnackBar(
        message: context.l10n.swapRouteTemporarilyUnavailable,
        error: true,
        context: context,
      );
      return;
    }
    final btcAmount = _satsToBtc(amountSats);
    setState(() => isProcessing = true);
    TrackingService.swapInitiated(
        fromCoin: 'BTC', toCoin: asset.code, provider: 'orchestra');

    // 1. Create Flashnet quote + one-time deposit address. Amount is
    //    in source smallest units (sats). No funds have moved yet, so
    //    any failure here ends the send with the route-unavailable
    //    notice — Orchestra's quote is also the definitive route/limit
    //    check (there's no min/max band to pre-validate against).
    //    Refund target: the wallet's own Spark address, like every other
    //    Spark-source Orchestra quote (Move, Predictions). A failed
    //    resolution lands in the same nothing-moved notice below rather
    //    than quoting refund-less and stranding funds. A quote that
    //    arrives but fails verification shows its own error and stops.
    final route = RouteKey(
      fromChain: 'spark',
      fromAsset: 'BTC',
      toChain: chain,
      toAsset: orchestraAssetCodeFor(asset.code),
    );
    SettlementRunner? runner;
    SettlementPlan? plan;
    SettlementPrepared? prepared;
    String? quoteError;
    // The intent the step-up hook last approved (Phase 1b.2).
    SensitiveIntent? approvedIntent;
    final destAsset = '${asset.code}:${network.network}';
    final orchFiat = _sendFiatContext();
    // One `send_failed` per user send that stops on this route. The
    // amount is the BTC that was to be sent (the source leg).
    void failOrchestraSend(Object? error, String stage) {
      TrackingService.sendFailed(
        flow: 'pay',
        network: network.network.toLowerCase(),
        asset: asset.code.toLowerCase(),
        error: error,
        walletKind: _sendWalletKind(),
        provider: 'orchestra',
        amountUsd: _usdForSats(amountSats),
        amountSats: amountSats,
        currency: orchFiat.currency,
        amountFiat: orchFiat.amountFiat,
        stage: stage,
      );
      TrackingService.moneyFlowError('send', error);
    }

    try {
      runner = await HotSettlement.runner();
      plan = HotSettlement.plan(
        ref.read,
        flow: SettlementFlow.sendExternal,
        route: route,
        source: SettlementAccountKind.sparkHot,
        destination: null,
        externalRecipient: toAddress,
        requestQuote: (key) async {
          final refundAddress = await ref.read(sparkSelfAddressProvider.future);
          final quoteRequest = OrchestraQuoteRequest(
            sourceChain: 'spark',
            sourceAsset: 'BTC',
            destinationChain: chain,
            destinationAsset: orchestraAssetCodeFor(asset.code),
            amountBaseUnits: BigInt.from(amountSats),
            recipientAddress: toAddress,
            refundAddress: refundAddress,
            recipientKind: RecipientKind.external,
          );
          return HotSettlement.quote(ref.read, quoteRequest,
              flow: 'send_stablecoin', idempotencyKey: key);
        },
        prepareFunding: (quote, _) =>
            HotSettlement.prepareSpark(ref.read, quote),
        fund: (quote, preparedPayment) async {
          // 2. Send the sats via Spark to the quote's deposit address. Hide
          //    the raw Spark send from the home Activity feed; the exchange
          //    row below tells the "BTC → ${asset.code}" story.
          final paymentId =
              await HotSettlement.sendSpark(ref.read, preparedPayment);
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
        // Phase 1b.2. Runs inside confirm, after the quote and its deposit
        // address exist and before the margin check and payment. The first
        // call prompts; a silent requote checks the held grant, so a lower
        // fee or a higher output does not prompt again, while a worse
        // quote, another recipient or another route shows C8 and pays
        // nothing.
        stepUp: (auth) async {
          // No quote review sheet before the prompt: the person
          // decided on the amount step and the prompt is the
          // confirmation. The drift check below still refuses a worse
          // quote, another recipient or another route.
          if (!mounted || !context.mounted) return false;
          final intent = _orchestraSendIntent(auth, destAsset: destAsset);
          final ok = await _approveSend(
            context,
            intent,
            amountLabel: _btcAmountLabel(amountSats),
            amountUsd: _usdForSats(amountSats),
          );
          if (ok) approvedIntent = intent;
          return ok;
        },
      );
      prepared = await runner.prepare(plan);
    } on WalletGuardException catch (e) {
      TrackingService.swapFailed(
          fromCoin: 'BTC',
          toCoin: asset.code,
          provider: 'orchestra',
          fromNetwork: 'spark',
          toNetwork: network.network.toLowerCase(),
          venue: 'orchestra',
          fromAmount: _satsToBtc(amountSats),
          amountUsd: _usdForSats(amountSats),
          reason: 'quote_rejected: ${e.reason.code}');
      TrackingService.moneyFlowError('send', e);
      failOrchestraSend('quote_rejected', 'quote');
      if (!mounted || !context.mounted) return;
      setState(() => isProcessing = false);
      showMessageSnackBar(
        message: e.messageFor(context.l10n),
        error: true,
        context: context,
      );
      return;
    } on SettlementStopped catch (e) {
      // An earlier transfer on this route may have moved funds and is
      // still being checked: never fall back to another rail meanwhile.
      if (e.reason == SettlementStopReason.blockedPending) {
        TrackingService.swapFailed(
            fromCoin: 'BTC',
            toCoin: asset.code,
            provider: 'orchestra',
            fromNetwork: 'spark',
            toNetwork: network.network.toLowerCase(),
            venue: 'orchestra',
            fromAmount: _satsToBtc(amountSats),
            amountUsd: _usdForSats(amountSats),
            reason: 'settlement_blocked_pending');
        failOrchestraSend('settlement_blocked_pending', 'quote');
        if (!mounted || !context.mounted) return;
        setState(() => isProcessing = false);
        showMessageSnackBar(
          message: context.l10n.settlementBlockedPending,
          error: true,
          context: context,
        );
        return;
      }
      quoteError = 'settlement_${e.reason.name}';
    } catch (e) {
      quoteError = TrackingService.errorCategory(e);
    }
    if (runner == null || plan == null || prepared == null) {
      TrackingService.swapFailed(
          fromCoin: 'BTC',
          toCoin: asset.code,
          provider: 'orchestra',
          fromNetwork: 'spark',
          toNetwork: network.network.toLowerCase(),
          venue: 'orchestra',
          fromAmount: _satsToBtc(amountSats),
          amountUsd: _usdForSats(amountSats),
          reason: 'quote_failed: ${quoteError ?? 'no quote'}');
      TrackingService.moneyFlowError('send', quoteError ?? 'quote_rejected');
      // There is no other route: the quote failure is this send's
      // outcome and reads as "route unavailable". A declined prompt is
      // not a send the user confirmed.
      if (quoteError != 'settlement_declined') {
        failOrchestraSend(quoteError ?? 'no_route', 'quote');
      }
      // Screen torn down mid-quote → nothing to show. Nothing has
      // moved, so bailing is safe.
      if (!mounted || !context.mounted) return;
      setState(() => isProcessing = false);
      showMessageSnackBar(
        message: context.l10n.swapRouteTemporarilyUnavailable,
        error: true,
        context: context,
      );
      return;
    }

    try {
      // Pays the prepared quote after the margin check. A replaced quote is
      // never paid: the send goes back to review for another confirm tap.
      final confirmed = await runner.confirm(
        plan,
        operationId: prepared.operationId,
        reviewedQuoteId: prepared.quote.quoteId,
        amountBaseUnits: BigInt.from(amountSats),
      );
      final rereview = confirmed.rereview;
      if (rereview != null) throw await runner.returnToReview(plan, rereview);
      final settled = confirmed.result!;
      final orchQuote = settled.quote.quote;
      // Funds moved against the last approved quote: mark the grant used.
      final approved = approvedIntent;
      final held = _sendGrant;
      if (approved != null && held != null) {
        try {
          AuthGrants.consume(held, approved);
        } on AuthGrantException {
          // Bookkeeping only; the hook checked the grant before paying.
        }
      }
      _sendGrant = null;

      // 3. The runner submitted the deposit with a persisted key. Without
      //    an order id yet the reconciler keeps registering it, and
      //    background sync swaps the q_ row for the real ord_ id.
      final orderId = settled.orderId ?? orchQuote.quoteId;

      // 4. Record the exchange so the user can track it.
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, asset.code,
          chain: chain);

      // The deposit is submitted: this user send is done (delivery is
      // tracked by the swap lifecycle). Flag it so dispose() does not
      // log a false `send_flow_abandoned`. `amount` is the quoted
      // stablecoin output; for a stablecoin destination the whole cost
      // of the route is the USD value sent less that output.
      _sendCompleted = true;
      final orchAmountUsd = _usdForSats(amountSats);
      final orchStable = asset.code.toUpperCase().startsWith('USD');
      final orchFeeUsd = orchStable && orchAmountUsd != null && estOut > 0
          ? orchAmountUsd - estOut
          : null;
      TrackingService.sendCompleted(
        flow: 'pay',
        network: network.network.toLowerCase(),
        asset: asset.code.toLowerCase(),
        walletKind: _sendWalletKind(),
        provider: 'orchestra',
        amountUsd: orchAmountUsd,
        amount: estOut > 0 ? estOut : null,
        amountSats: amountSats,
        currency: orchFiat.currency,
        amountFiat: orchFiat.amountFiat,
        feeUsd: orchFeeUsd != null && orchFeeUsd >= 0 ? orchFeeUsd : null,
        dedupeKey: settled.operation.operationId,
      );
      TrackingService.moneyFlowFinished('send');
      final exchange = SwapOrder(
        activityDirection: 'send',
        id: orderId,
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: asset.code,
        networkTo: network.network,
        depositAddress: orchQuote.depositAddress,
        depositAmount: btcAmount.toStringAsFixed(8),
        withdrawalAmount: estOut.toStringAsFixed(2),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: toAddress,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: settled.operation.refund?.address ?? '',
        provider: 'Orchestra',
        walletId: ref.read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      ref.read(swapOrdersProvider.notifier).addExchange(exchange);
      ref
          .read(walletTransactionCacheProvider.notifier)
          .mergeSwapOrder(exchange);

      // Backend provider_events row for revenue attribution. Only the
      // REAL order (ord_…) — never the quote (q_…), which would create
      // a second row the ord_… completion can never reconcile with.
      // Background sync registers it on the q_→ord_ swap otherwise.
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'BTC',
          sourceAmount: btcAmount,
          destinationAsset: asset.code,
          destinationAmount: estOut,
        );
      }
      BackgroundSyncService().syncNow();

      // NOTE: don't fire swapCompleted here — the deposit was only
      // just submitted, so the order is still pending (no terminal
      // amounts, sometimes no ord_ id yet), and swapCompleted also
      // fans out the AppsFlyer purchase signal + backend completion
      // upsert. Background sync fires it exactly once when the
      // Orchestra status flips to terminal success
      // (background_sync_provider.dart) — same rule as move_sheet's
      // convert path. Firing here too double-counted every send.

      if (mounted) {
        showFullscreenTransactionSendModal(
          context: context,
          asset: 'BTC → ${asset.code}',
          amount:
              '${_formatSmartDecimals(estOut > 0 ? estOut : btcAmount)} ${asset.code}',
          fiat: false,
          receiveAddress: toAddress,
          isSwap: true,
          swapIconUrl: asset.iconUrl,
          swapIconSvg: asset.svgAsset,
          swapIconColor: asset.color,
          swapCoinCode: asset.code,
        );
        ref.read(sendTxProvider.notifier).resetToDefault();
      }
    } catch (e) {
      if (e is SettlementStopped && e.reason == SettlementStopReason.declined) {
        // The step-up was declined or showed C8. Nothing was sent.
        TrackingService.swapFailed(
            fromCoin: 'BTC',
            toCoin: asset.code,
            provider: 'orchestra',
            fromNetwork: 'spark',
            toNetwork: network.network.toLowerCase(),
            venue: 'orchestra',
            fromAmount: _satsToBtc(amountSats),
            amountUsd: _usdForSats(amountSats),
            reason: 'step_up_declined');
        TrackingService.moneyFlowError('send', 'user_cancelled');
        return;
      }
      // Funds may already sit with Orchestra at this point (the Spark
      // send is step 2) — surface the error, never re-dispatch, or the
      // user could pay twice.
      TrackingService.swapFailed(
          fromCoin: 'BTC',
          toCoin: asset.code,
          provider: 'orchestra',
          fromNetwork: 'spark',
          toNetwork: network.network.toLowerCase(),
          venue: 'orchestra',
          fromAmount: _satsToBtc(amountSats),
          amountUsd: _usdForSats(amountSats),
          reason: e is WalletGuardException
              ? 'quote_rejected: ${e.reason.code}'
              : TrackingService.errorCategory(e));
      TrackingService.moneyFlowError('send', e);
      // A replaced quote goes back to review for another confirm tap
      // (nothing moved), so it is not this send's outcome.
      if (!_sendCompleted &&
          !(e is SettlementStopped &&
              e.reason == SettlementStopReason.quoteReplaced)) {
        failOrchestraSend(
            e is WalletGuardException
                ? 'quote_rejected'
                : e is SettlementStopped
                    ? 'settlement_${e.reason.name}'
                    : e,
            'settle');
      }
      if (mounted && context.mounted) {
        _showSendFailed(e,
            message: HotSettlement.messageFor(e, context.l10n) ??
                userErrorCopy(context, e,
                    fallback: context.l10n.sendCouldNotComplete));
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  static double _satsToBtc(int sats) {
    final str = sats.toString().padLeft(9, '0');
    final whole = str.substring(0, str.length - 8);
    final frac = str.substring(str.length - 8);
    return double.parse('$whole.$frac');
  }

  static String _formatSmartDecimals(double v) {
    final s = v.toStringAsFixed(8);
    final parts = s.split('.');
    if (parts.length < 2) return s;
    var dec = parts[1].replaceAll(RegExp(r'0+$'), '');
    if (dec.length < 2) dec = dec.padRight(2, '0');
    return '${parts[0]}.$dec';
  }

  /// Pushes the full-screen confirmation page and returns the
  /// controller so the orchestrator can drive step states + lifecycle
  /// after the user confirms. Caller awaits `controller.awaitConfirmation()`
  /// to know whether to proceed.

  /// The shared Send / Receive unit sheet; picking a unit restarts the
  /// entry so the digits never belong to the old unit's decimals.
  void _showCurrencyPicker(BuildContext context, WidgetRef ref) {
    showAmountUnitPicker(
      context,
      selected: ref.read(inputCurrencyProvider),
      iconBuilder: (code, size) => _currencyIcon(code, size: size),
      onSelected: (code) {
        ref.read(inputCurrencyProvider.notifier).state = code;
        if (code != 'Sats' && code != 'BTC') {
          _lastFiatUnit = code;
        }
        if (isInvoice) {
          updateControllerText(ref.read(sendTxProvider).amount);
        } else {
          controller.text = "";
          // Also reset the ATM accumulator so the Bitcoin hero starts
          // from an empty entry when the user switches units mid-flow.
          _syncAtmDigitsFromSats(0);
          ref.read(sendTxProvider.notifier).updateAmountFromInput('0', 'sats');
        }
      },
    );
  }

  /// Spendable balance (in sats) for the wallet the user is sending
  /// FROM, regardless of which wallet is currently active globally.
  ///
  /// Resolution:
  ///   * Spending (hot/Spark) wallet → live
  ///     `balanceNotifierProvider.sparkBitcoinbalance`. Active-wallet
  ///     scoped notifier is correct here because the spending wallet
  ///     IS the active wallet whenever Send is opened from the hot
  ///     path; we don't fork that.
  ///   * Anything else (hardware / watch-only / tracked) → the
  ///     per-wallet `walletBalanceCacheProvider` entry for that
  ///     wallet's on-chain BTC balance. The cache is populated by
  ///     the BDK scope-scan loop kicked off in `initState`, so the
  ///     value reflects the wallet the user actually drilled into,
  ///     not the spending wallet's Spark balance.
  int _selectedSpendableSats(WidgetRef ref) {
    // Decide which balance source applies based on the
    // SELECTED wallet, not the active one — sending from a cold
    // wallet detail screen leaves the active wallet pinned to the
    // spending wallet, so a naive `balanceNotifierProvider` read
    // would show Spark sats here.
    final selectedId = _selectedWalletId;
    if (selectedId != null) {
      final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
      WalletConfig? selectedWallet;
      for (final w in wallets) {
        if (w.id == selectedId) {
          selectedWallet = w;
          break;
        }
      }
      if (selectedWallet == null) return 0;
      if (!selectedWallet.isSparkWallet) {
        final cache = ref.watch(walletBalanceCacheProvider);
        return cache[selectedId]?.onChainBtcBalance ?? 0;
      }
    }
    // Spending (hot) wallet — Spark Bitcoin balance is the truth.
    return ref.watch(balanceNotifierProvider).sparkBitcoinbalance;
  }

  /// `ref.read` variant for action callbacks (Max, send-time checks).
  /// Same resolution as [_selectedSpendableSats] but reads providers
  /// without subscribing — avoids "use of ref.watch in an action
  /// callback" Riverpod errors.
  int _readSelectedSpendableSats(WidgetRef ref) {
    final selectedId = _selectedWalletId;
    if (selectedId != null) {
      final wallets = ref.read(settingsProvider).wallets;
      WalletConfig? selectedWallet;
      for (final w in wallets) {
        if (w.id == selectedId) {
          selectedWallet = w;
          break;
        }
      }
      if (selectedWallet == null) return 0;
      if (!selectedWallet.isSparkWallet) {
        final cache = ref.read(walletBalanceCacheProvider);
        return cache[selectedId]?.onChainBtcBalance ?? 0;
      }
    }
    return ref.read(balanceNotifierProvider).sparkBitcoinbalance;
  }

  /// Spendable sats of a BDK wallet, read from that wallet's OWN coins —
  /// the set the transaction builder will spend — and narrowed to the
  /// manual coin selection when the user made one.
  ///
  /// Null means "this wallet's coins are not loaded": the model is still
  /// resolving, or its coin set is empty while the wallet is known to
  /// hold a balance. Seeding MAX from the cached total in that state is
  /// what produced a drain `finish` could not build.
  int? _bdkSpendableSats(WidgetRef ref, String walletId) {
    final model = ref.read(bitcoinModelForWalletProvider(walletId)).valueOrNull;
    if (model == null) return null;
    final selected = ref.read(selectedUtxosProvider);
    var total = 0;
    var coins = 0;
    for (final coin in model.listUnspent()) {
      if (coin.isSpent) continue;
      if (selected.isNotEmpty && !selected.contains(coin.outpoint)) continue;
      coins++;
      total += coin.txout.value.toSat();
    }
    if (coins > 0) return total;
    final cached =
        ref.read(walletBalanceCacheProvider)[walletId]?.onChainBtcBalance ?? 0;
    return cached > 0 ? null : 0;
  }

  /// True once [walletId]'s BDK state holds at least one spendable coin.
  bool _bdkHasSpendableCoins(String walletId) {
    final model = ref.read(bitcoinModelForWalletProvider(walletId)).valueOrNull;
    if (model == null) return false;
    return model.listUnspent().any((coin) => !coin.isSpent);
  }

  /// A MAX tap that lands before the wallet's BDK state has loaded its
  /// coins is a WAIT, not a failure.
  ///
  /// `_bdkSpendableSats` returns null exactly in that state: no coins
  /// in the model, but a cached balance saying the wallet does hold
  /// money. That used to clear the drain and throw "wallet is still
  /// syncing" at the user, which on a cold open is most taps, and the
  /// 100 % chip simply did not work. The model object never changes
  /// by itself either, so waiting without kicking a scan would wait
  /// forever.
  ///
  /// So: arm the drain, kick the wallet's own scan, poll until the
  /// coins show up, and hand the caller the spendable total. Returns
  /// null only when it genuinely cannot resolve.
  ///
  /// This does NOT compute or write a drain amount. The probe in
  /// `_recomputeMaxForAddress`, reached through `_netDrainAgainstFee`,
  /// is still the single writer of that figure; all this does is get
  /// the coins loaded so the probe has something to build against.
  Future<int?> _awaitBdkSpendableSats(String walletId) async {
    // Arm the drain first so the chip reads as taken while the coins
    // load, instead of looking like the tap was swallowed.
    if (!_isDraining) setState(() => _setDraining(true));
    // Points the BDK scope at the wallet being spent and kicks a scan,
    // so this works even when the user switched source after Send
    // opened.
    _startSendWalletSync();
    // ~15 s of 250 ms polls. A scan that has not produced a coin by
    // then is not going to inside the user's attention span, and the
    // caller stops the spinner and says so.
    for (var i = 0; i < 60; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return null;
      // The same guards the drain probe honours: a send in flight, an
      // auth prompt up, or an invoice that locked the amount all end
      // the wait rather than writing into a moving target.
      if (isProcessing || _paymentAuthInFlight || isInvoice) return null;
      if (!_isDraining) return null;
      if (_resolveSourceWallet()?.id != walletId) return null;
      final sats = _bdkSpendableSats(ref, walletId);
      if (sats != null) return sats;
    }
    return null;
  }

  /// Brings a draining amount down to what can actually leave: the coins
  /// the builder will spend, less the fee to spend them.
  ///
  /// The fee comes from the same draft estimator the Review fee row
  /// shows, sized with `drain: true`, so the number on screen and the
  /// number in the build always agree. Nothing here is a fixed haircut:
  /// change the speed or the coin selection and the figure follows.
  void _netDrainAgainstFee(WalletConfig? wallet) {
    if (!_isDraining ||
        wallet == null ||
        !wallet.usesBdk ||
        isProcessing ||
        _paymentAuthInFlight ||
        isInvoice ||
        !_hasSource) {
      return;
    }
    final address = stripBitcoinAddress(addressController.text);
    if (address.isEmpty) return;
    // Refresh the real max in the background BEFORE trusting any local
    // arithmetic. The probe builds an actual drain PSBT against this
    // wallet's own coins at the selected rate and reports what the
    // builder will really pay, which is the only number the send can be
    // prepared with. Keyed so it runs once per wallet, address and rate
    // rather than on every frame.
    final rate = ref.watch(getCustomFeeRateProvider).valueOrNull;
    final probeKey = '${wallet.id}|$address|$rate|'
        '${ref.watch(selectedUtxosProvider).length}';
    if (rate != null && _drainProbeKey != probeKey) {
      _drainProbeKey = probeKey;
      // ignore: unawaited_futures
      _recomputeMaxForAddress(address);
    }
    // The probe is the ONLY writer of a draining amount.
    //
    // A second, estimate-based netting used to run here to hold the
    // screen steady until the probe answered. The two disagreed by a few
    // sats, because one reads a size estimate and the other builds the
    // real transaction, so each kept correcting the other and the amount
    // oscillated. A send launched into that lost its race with the
    // rebuild and came back as "payment not sent". One writer, one
    // number, and the figure the screen shows is the figure that was
    // actually built.
  }

  /// The coins or the fee just moved under a draining send. Re-size it.
  ///
  /// A BDK drain's amount belongs to the builder: `_netDrainAgainstFee`
  /// runs `_recomputeMaxForAddress`, which builds the real drain and
  /// writes what its single output pays. Calling `_setMaxAmount` here
  /// instead put the GROSS balance back on the screen, because that is
  /// what MAX seeds while there is no recipient to size a fee against,
  /// and the probe would not correct it: the probe is keyed by the
  /// wallet, the recipient, the fee rate and the coin selection, and a
  /// finished scan changes none of them. Review was then left asking to
  /// send every sat AND pay the fee out of it, which is not the
  /// transaction the builder had prepared, so 100% could never settle
  /// while every smaller amount, which nothing re-seeds, went through.
  ///
  /// Invalidating the probe keeps one writer and one number. Before a
  /// recipient exists there is no drain to net, so the gross seed is
  /// still the right answer and `_setMaxAmount` still gives it.
  ///
  /// The spending account (Spark) has no fee rate or coin selection to
  /// follow: once there is a recipient, Review's SDK preparation owns
  /// its drained amount (`_resolveSparkDrainAmount`), and re-seeding the
  /// gross balance here would be a second writer. Only without a
  /// recipient does it go back through `_setMaxAmount` for the seed.
  void _refreshDrainAmount() {
    if (!_isDraining || !mounted) return;
    final wallet = _resolveSourceWallet();
    final address = stripBitcoinAddress(addressController.text);
    if (address.isNotEmpty) {
      if (wallet?.usesBdk == true) setState(() => _drainProbeKey = null);
      return;
    }
    unawaited(_setMaxAmount(ref));
  }

  Future<void> _setMaxAmount(WidgetRef ref) async {
    // Invoice-locked amounts are not MAX-able. The button is disabled
    // once `isInvoice` is set, but the async invoice parse can land
    // AFTER a MAX tap slipped in — bail instead of re-arming the drain
    // flag against a fixed-amount invoice.
    if (isInvoice || isProcessing || _paymentAuthInFlight) return;
    // A MAX already parked on the coin wait owns the spinner. The scan
    // that wait kicks calls back in here when it finishes; let the
    // parked one pick the coins up on its next poll instead of
    // starting a second pass that would clear `isCalculatingMax` out
    // from under it.
    if (_maxAwaitingCoins) return;
    final maxWalletId = _resolveSourceWallet()?.id;
    if (maxWalletId == null) return;
    setState(() => isCalculatingMax = true);
    try {
      // Max means "all of the bitcoin balance this send draws from".
      int maxSats;
      // Hardware / watch-only branch — drain calculation needs a
      // valid destination address to estimate the network fee
      // (BDK's TxBuilder validates `recipient` first). Before the
      // user reaches the Send-to step the address is empty, which
      // would crash with "Address is invalid". Fall back to the
      // raw balance and let the actual on-chain fee come out of
      // the principal at signing time — the user has already opted
      // into "send everything" by tapping MAX.
      //
      // "External signer" here means the SELECTED source wallet is
      // cold (hardware / watch-only / tracked / paired signer) —
      // not the active wallet. When Send is opened from a hardware
      // wallet detail screen, `bdkScopeWalletIdProvider` is set but
      // `activeWalletId` stays pinned to the spending wallet, so
      // gating on `activeWallet.isHardware` would route through the
      // Spark hot path and drain the wrong balance.
      final selectedId = _selectedWalletId;
      WalletConfig? selectedWallet;
      if (selectedId != null) {
        for (final w in ref.read(settingsProvider).wallets) {
          if (w.id == selectedId) {
            selectedWallet = w;
            break;
          }
        }
      }
      // Every non-Spark source is a BDK wallet — a hot Bitcoin wallet
      // as much as a hardware, watch-only or tracked one — and they
      // all drain through the same builder, so MAX is sized from the
      // coins that builder will actually spend.
      final usesBdkSource =
          selectedWallet != null && (!selectedWallet.isSparkWallet);
      if (usesBdkSource) {
        // The SELECTED wallet's own coins. The active-wallet
        // `getBitcoinBalanceProvider` would return the spending
        // wallet's BDK balance, and the shared balance-cache slot can
        // name a total whose coins this wallet's BDK state does not
        // hold yet — a drain sized from that cannot be built.
        var spendable = _bdkSpendableSats(ref, selectedWallet.id);
        if (spendable == null) {
          // Not loaded yet, not broken. Hold the spinner, kick the
          // scan and fill the amount in when the coins arrive.
          _maxAwaitingCoins = true;
          try {
            spendable = await _awaitBdkSpendableSats(selectedWallet.id);
          } finally {
            _maxAwaitingCoins = false;
          }
          if (!mounted || _resolveSourceWallet()?.id != maxWalletId) return;
          TrackingService.track('pay_max_waited_for_coins', params: {
            'resolved': spendable != null,
          });
          if (spendable == null) {
            // Genuinely could not size a max: the scan never handed
            // over a coin. Drop the drain flag so the screen is not
            // left claiming 100 %, and say why. `isCalculatingMax`
            // is cleared by this method's own finally.
            setState(() => _setDraining(false));
            if (!context.mounted) return;
            showMessageSnackBar(
                message: context.l10n.errorCopyBusy,
                error: true,
                context: context);
            return;
          }
        }
        maxSats = spendable;
        setState(() => _setDraining(maxSats > 0));
      } else {
        // Spending wallet (Spark). The chip arms the drain and shows
        // the balance as a placeholder; nothing is sized here, with
        // or without a destination. Review resolves it from the SDK's
        // own send-all for the rail the destination turns out to be
        // (`_resolveSparkDrainAmount`), and the send reads that same
        // preparation. Sizing it here as well gave a second writer
        // whose fee quote was not the one the send was prepared on.
        maxSats = _readSelectedSpendableSats(ref);
        setState(() => _setDraining(maxSats > 0));
      }

      if (!mounted || _resolveSourceWallet()?.id != maxWalletId) return;
      // The invoice parse may have locked the amount while we were
      // computing — the lock wins; discard the MAX result so it can't
      // overwrite the invoice amount or leave a stale drain flag.
      if (isInvoice) {
        setState(() => _setDraining(false));
        return;
      }

      if (maxSats <= 0) {
        showMessageSnackBar(
            message: context.l10n.insufficientBalanceForFees,
            error: true,
            context: context);
      } else {
        ref.read(sendTxProvider.notifier).updateAmount(maxSats);
        updateControllerText(maxSats);
        if (_selectedDestAsset != null) _fetchRate();
      }
    } catch (e) {
      showMessageSnackBar(
          message: userErrorCopy(context, e,
              fallback: context.l10n.sendCouldNotEstimateFee),
          error: true,
          context: context);
    } finally {
      if (mounted) setState(() => isCalculatingMax = false);
    }
  }

  /// Pick the right portion of a pasted payment string based on the
  /// *paying* wallet's Lightning capability.
  ///
  /// Returns the value to commit to the address field, or `null` when
  /// the input is Lightning-only and the active wallet can't pay
  /// Lightning (caller should show a "switch wallet" message).
  ///
  /// Mirrors the unified-QR routing in `camera.dart` so paste and
  /// scan behave identically.
  String? _resolveUnifiedPasteForActiveWallet(String input) {
    final canUseLightning = _resolveSourceWallet()?.isSparkWallet ?? false;

    final lower = input.toLowerCase();
    final isBip21 = lower.startsWith('bitcoin:');
    final hasLightningParam = lower.contains('lightning=');

    if (isBip21 && hasLightningParam) {
      final uri = Uri.tryParse(input);
      final ln = uri?.queryParameters['lightning'];
      if (canUseLightning && ln != null && ln.isNotEmpty) {
        // Spending wallet + unified QR → use the Lightning rail.
        return ln;
      }
      // Hardware / watch-only → use the BARE on-chain address (strip the
      // bitcoin: scheme + the whole BIP21 query). Returning the prefixed
      // `bitcoin:bc1…` form here is what made the on-chain fee calc reject
      // the destination as invalid.
      return stripBitcoinAddress(input);
    }

    // Plain on-chain BIP21 (`bitcoin:bc1…?amount=…`, no lightning rail) —
    // commit the bare address so the BDK fee calc / TransactionBuilder
    // gets a valid destination instead of the scheme-prefixed string.
    if (isBip21) {
      return stripBitcoinAddress(input);
    }

    // Lightning-only payload (raw BOLT11 / LNURL / `lightning:`):
    // surface the "switch wallet" error when the active wallet
    // can't sign Lightning. Otherwise commit as-is.
    final isLightningOnly = lower.startsWith('lnbc') ||
        lower.startsWith('lntb') ||
        lower.startsWith('lnurl') ||
        lower.startsWith('lightning:');
    if (isLightningOnly && !canUseLightning) {
      return null;
    }

    return input;
  }

  /// Send tap → the route that pays it, with the button busy from the
  /// tap itself. Each route used to raise `isProcessing` only once it
  /// reached its own work, after whatever it awaited first: a 100%
  /// cross-chain send synced the Spark balance (up to 20 s), and a cold
  /// source parsed the address, with the button idle all along. Busy
  /// now goes up here, before any await, and comes down when the route
  /// returns by any path — unless the route already cleared it, or a
  /// newer hardware build (the Sign step's Try again) owns it now.
  Future<void> _handleSend(BuildContext context, WidgetRef ref) async {
    if (isProcessing ||
        _paymentAuthInFlight ||
        _sendCompleted ||
        isCalculatingMax) {
      return;
    }
    final hardwareGeneration = _hardwareBuildGeneration;
    await runSendTapBusy(
      setBusy: (busy) => setState(() => isProcessing = busy),
      releaseBusy: () =>
          mounted &&
          isProcessing &&
          _hardwareBuildGeneration <= hardwareGeneration + 1,
      dispatch: () => _dispatchSend(context, ref),
    );
  }

  /// The body of [_handleSend], entered with `isProcessing` already up.
  /// Routes still raise and clear it themselves; raising it again is a
  /// no-op and their clears stay authoritative.
  Future<void> _dispatchSend(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    // Captured before the first await so the fee labels below never
    // read the context across an async gap.
    final confirmedWallet = _resolveSourceWallet();
    if (confirmedWallet == null) {
      showMessageSnackBar(
          message: context.l10n.sendChooseAccountFirst,
          error: true,
          context: context);
      return;
    }
    final sendTxState = ref.read(sendTxProvider);
    final address = addressController.text;
    final amount = sendTxState.amount;
    final confirmedWalletId = _resolveSourceWallet()?.id;
    final confirmedDestination = _selectedDestNetwork;

    if (address.isEmpty || amount <= 0) {
      showMessageSnackBar(
          message: context.l10n.invalidAddressOrAmount,
          error: true,
          context: context);
      return;
    }

    // Step-up gate (Phase 1b.2): sending funds ALWAYS demands a fresh
    // biometric or PIN approval, even seconds after an app unlock. Each
    // route below prompts once its route, SDK prepare, quote and provider
    // deposit address exist, and binds the grant to what it will pay.
    // Browsing rides the session, spending never does.
    _dropSendGrant();
    _sendReviewDrift = null;

    if (confirmedWallet.isBitcoinSoftware) {
      await _handleBitcoinSoftwareSend(
          context, ref, confirmedWallet, address, amount);
      return;
    }

    _sendReviewDrift = () => <DriftField>{
          if (_resolveSourceWallet()?.id != confirmedWalletId)
            DriftField.wallet,
          if (addressController.text != address ||
              _selectedDestNetwork != confirmedDestination)
            DriftField.destination,
          if (ref.read(sendTxProvider).amount != amount) DriftField.amount,
        };

    // Hardware / watch-only — branch by destination:
    //   - On-chain BTC → `_handleHardwareSigning` (PSBT signing)
    //   - Cross-chain → `_handleSwapSend`, which has no route for a
    //     cold source and says so (Orchestra routes from Spark only)
    //
    // Source-of-truth is the *user-picked* source from the Pay-with
    // step, not the carousel-active wallet. The two diverge when the
    // user is parked on the spending wallet and selects a savings
    // tile — without this, the hardware branch was silently skipped
    // and the SDK tried to spend Spark sats from the savings wallet's
    // xpub.
    final sourceWallet = _resolveSourceWallet();
    if (sourceWallet == null) return;
    if (sourceWallet.isHardware || sourceWallet.isWatchOnly) {
      if (_selectedDestAsset != null && _selectedDestNetwork != null) {
        await _handleSwapSend(context, ref);
        return;
      }
      // Hardware wallets can't sign Lightning natively. If the user
      // pasted a raw LN invoice / address into the address field
      // without picking the "Lightning Bitcoin" destination first,
      // bail with an actionable message instead of falling through
      // to PSBT signing (which would attempt to send sats to a
      // non-Bitcoin payload and fail at the BDK address-validation
      // stage with a confusing error).
      final hwInputType =
          await ref.read(identifyInputTypeProvider(address).future);
      if (hwInputType == AnalyzedPaymentType.lightning ||
          hwInputType == AnalyzedPaymentType.lnurl) {
        if (mounted) {
          showMessageSnackBar(
            message: context.l10n.sendWalletCantSignLightningDestinationPicker,
            error: true,
            context: context,
          );
        }
        return;
      }
      await _handleHardwareSigning(context, ref, address, amount);
      return;
    }

    // Route to cross-chain swap flow if destination is non-Bitcoin
    if (_selectedDestAsset != null && _selectedDestNetwork != null) {
      await _handleSwapSend(context, ref);
      return;
    }

    setState(() => isProcessing = true);

    // Outcome analytics (`send_completed` / `send_failed`): the rail is
    // refined once the destination resolves, the stage once the user
    // approved and the SDK call is in flight.
    var sendNetwork = _networkLabel(sendTxState.type);
    var sendStage = 'quote';
    String? sentPaymentId;
    int? sentFeeSats;
    int? sentNetworkFeeSats;
    String? sentFeeTier;
    final sendFiat = _sendFiatContext();
    int actualSentAmount =
        amount; // Track the actual amount sent (may differ when draining)
    try {
      final inputType =
          await ref.read(identifyInputTypeProvider(address).future);

      // If the address is a BIP-21 URI, extract the lightning param for
      // Spark wallets so it goes through the Lightning/LNURL payment path.
      String resolvedAddress = address;
      AnalyzedPaymentType resolvedType = inputType;
      if (inputType == AnalyzedPaymentType.bip21) {
        final uri = Uri.tryParse(address);
        final lnParam = uri?.queryParameters['lightning'];
        if (lnParam != null && lnParam.isNotEmpty) {
          resolvedAddress = lnParam;
          resolvedType = AnalyzedPaymentType.lightning;
        }
      }
      sendNetwork = _resolvedSendNetwork(resolvedType);

      switch (resolvedType) {
        case AnalyzedPaymentType.bip21:
        case AnalyzedPaymentType.bitcoin:
        case AnalyzedPaymentType.spark:
          // The SDK prepares against the invoice's authoritative amount and
          // checks amount plus fees. A stale entered amount must not reject a
          // valid fixed-amount invoice before it can override Review.

          // The same preparation Review watched (a drain is keyed
          // without the amount), so the fee quote and the amount it
          // resolved to are the ones the user saw.
          final prepareParams = _sparkPrepareKey(address, amount);
          final prepareResp = await ref
              .read(prepareGenericPaymentProvider(prepareParams).future);
          // What the recipient gets. For a 100% send the SDK takes the
          // fee for the selected speed out of the whole balance, so this
          // is balance less that fee, the figure Review shows.
          final confirmAmount =
              sparkPreparedRecipientSats(prepareResp, _sparkOnchainSpeed);
          if (!context.mounted ||
              !await _reviewPreparedAmount(context, amount, confirmAmount)) {
            return;
          }
          final method = prepareResp.paymentMethod;

          if (method is SendPaymentMethod_BitcoinAddress) {
            final feeQuote = method.feeQuote;
            // Speed was already chosen on Review (defaulted to Standard,
            // changeable via the "Network speed" tap target). No
            // mid-send picker — the user already saw the fee for
            // their selected speed before tapping Send.
            final selectedSpeed = _sparkOnchainSpeed;

            SendOnchainSpeedFeeQuote speedQuote;
            if (selectedSpeed == OnchainConfirmationSpeed.fast) {
              speedQuote = feeQuote.speedFast;
            } else if (selectedSpeed == OnchainConfirmationSpeed.medium)
              speedQuote = feeQuote.speedMedium;
            else
              speedQuote = feeQuote.speedSlow;

            // The SDK charges the operator's fee AND the L1 broadcast
            // fee (`user_fee_sat + l1_broadcast_fee_sat`); the first is
            // not a total that already contains the second.
            final totalFee = sparkOnchainFeeSats(feeQuote, selectedSpeed);
            final networkFee = speedQuote.l1BroadcastFeeSat.toInt();
            final serviceFee = speedQuote.userFeeSat.toInt();
            sentFeeSats = totalFee;
            sentNetworkFeeSats = networkFee;
            sentFeeTier =
                selectedSpeed.toString().split('.').last.toLowerCase();

            List<FeeDetail> feeList = [];
            if (networkFee > 0) {
              feeList.add(
                  FeeDetail(label: l10n.networkFee, amountSats: networkFee));
            }
            if (serviceFee > 0) {
              feeList.add(
                  FeeDetail(label: l10n.serviceFee, amountSats: serviceFee));
            } else if (feeList.isEmpty)
              feeList
                  .add(FeeDetail(label: l10n.networkFee, amountSats: totalFee));

            // When draining, the actual receive amount = prepareResp.amount (fees already deducted)
            actualSentAmount = confirmAmount;

            // No second confirmation modal — the user already
            // confirmed once via the send screen's primary button
            // (and the SwapConfirmationPage if a top-up was needed).
            // For BTC on-chain we still defer to the fee-speed picker
            // above (that's choosing speed, not re-confirming).
            actualSentAmount = confirmAmount;
            // ignore: unused_local_variable
            final _feeListUnused =
                feeList; // retained for future inline-fee display

            if (!context.mounted) return;
            if (!await _approveAndConsumeSend(
              context,
              reviewed: _sendIntent(
                venue: 'bitcoin',
                destination: address,
                amountMax: BigInt.from(amount),
                provider: 'breez',
                sourcePool: 'btc',
                feeCap: totalFee,
                extra: {'speed': selectedSpeed.toString()},
              ),
              // Max mode: the SDK may clamp the amount down, never up.
              actual: _sendIntent(
                venue: 'bitcoin',
                destination: address,
                amountMax: BigInt.from(confirmAmount),
                provider: 'breez',
                sourcePool: 'btc',
                feeCap: totalFee,
                extra: {'speed': selectedSpeed.toString()},
              ),
              amountLabel: _btcAmountLabel(amount),
              amountUsd: _usdForSats(amount),
            )) {
              return;
            }

            sendStage = 'broadcast';
            final onchainResp = await ref.read(
                executeOnchainTransactionProvider(
                        (prepareResponse: prepareResp, speed: selectedSpeed))
                    .future);
            sentPaymentId = onchainResp.payment.id;

            // Phase 9 — log the BTC on-chain fee (network + service)
            // we just paid. `totalFee` is in sats; convert to USD via
            // the live BTC→USD baseline. Synthetic id keyed on time
            // since we don't have a tx hash here without re-querying.
            try {
              final usdPerBtc =
                  ref.read(selectedCurrencyProvider('usd')).toDouble();
              final feeUsd = (totalFee / 1e8) * usdPerBtc;
              if (feeUsd > 0) {
                FeeHistoryService.log(
                  id: 'btc-onchain-${DateTime.now().millisecondsSinceEpoch}',
                  kind: FeeKind.btcOnchain,
                  microUsd: (feeUsd * 1000000).round(),
                  nativeAmount: totalFee.toString(),
                  nativeUnit: 'sats',
                  source: 'Spark',
                  walletId: ref.read(settingsProvider).activeWalletId,
                );
              }
            } catch (_) {}
          } else {
            List<FeeDetail> feeList = [];
            if (method is SendPaymentMethod_SparkAddress) {
              if (method.fee > BigInt.zero) {
                feeList.add(FeeDetail(
                    label: l10n.serviceFee, amountSats: method.fee.toInt()));
              }
            } else if (method is SendPaymentMethod_SparkInvoice) {
              if (method.fee > BigInt.zero) {
                feeList.add(FeeDetail(
                    label: l10n.serviceFee, amountSats: method.fee.toInt()));
              }
            }

            // When draining, use actual amount from prepare (fees deducted)
            actualSentAmount = confirmAmount;

            // A raw Spark address is shortened so the review stays readable;
            // the asset label beside it already says Spark.
            final displayAddress = address.contains('@')
                ? address
                : (address.length > 16 ? "${address.substring(0, 8)}…${address.substring(address.length - 6)}" : address);

            // No second confirmation modal — the user already
            // confirmed once via the send screen's primary button
            // (and the SwapConfirmationPage if a top-up was needed).
            actualSentAmount = confirmAmount;
            // ignore: unused_local_variable
            final _displayUnused = displayAddress;
            // ignore: unused_local_variable
            final _feeListUnused = feeList;

            final sparkFeeSats =
                _preparedFeeSats(prepareResp, _sparkOnchainSpeed);
            sentFeeSats = sparkFeeSats;
            if (!context.mounted) return;
            if (!await _approveAndConsumeSend(
              context,
              reviewed: _sendIntent(
                venue: 'spark',
                destination: address,
                amountMax: BigInt.from(amount),
                provider: 'breez',
                sourcePool: 'btc',
                feeCap: sparkFeeSats,
              ),
              actual: _sendIntent(
                venue: 'spark',
                destination: address,
                amountMax: BigInt.from(confirmAmount),
                provider: 'breez',
                sourcePool: 'btc',
                feeCap: sparkFeeSats,
              ),
              amountLabel: _btcAmountLabel(amount),
              amountUsd: _usdForSats(amount),
            )) {
              return;
            }

            sendStage = 'broadcast';
            final sparkResp = await ref
                .read(executeSparkTransactionProvider(prepareResp).future);
            sentPaymentId = sparkResp.payment.id;

            // Phase 9 — log Spark internal transfer fee. Spark→Spark
            // sends carry a small service fee exposed on the prepared
            // method; logged so the Fees tab attributes it correctly
            // even on free-feeling internal transfers.
            try {
              int sparkFeeSats = 0;
              if (method is SendPaymentMethod_SparkAddress &&
                  method.fee > BigInt.zero) {
                sparkFeeSats = method.fee.toInt();
              } else if (method is SendPaymentMethod_SparkInvoice &&
                  method.fee > BigInt.zero) {
                sparkFeeSats = method.fee.toInt();
              }
              if (sparkFeeSats > 0) {
                final usdPerBtc =
                    ref.read(selectedCurrencyProvider('usd')).toDouble();
                final feeUsd = (sparkFeeSats / 1e8) * usdPerBtc;
                if (feeUsd > 0) {
                  FeeHistoryService.log(
                    id: 'spark-${DateTime.now().microsecondsSinceEpoch}',
                    kind: FeeKind.btcOnchain,
                    microUsd: (feeUsd * 1000000).round(),
                    nativeAmount: sparkFeeSats.toString(),
                    nativeUnit: 'sats',
                    source: 'Spark',
                    walletId: ref.read(settingsProvider).activeWalletId,
                  );
                }
              }
            } catch (_) {}
          }
          break;

        case AnalyzedPaymentType.lightning:
        case AnalyzedPaymentType.lnurl:
          // Spark hot wallet pays Lightning natively. No Orchestra
          // top-up.
          // The SDK prepares against the invoice's authoritative amount and
          // checks amount plus fees. A stale entered amount must not reject a
          // valid fixed-amount invoice before it can override Review.

          final paymentArgs = _lightningPrepareKey(resolvedAddress, amount);

          final prepWrapper = await ref
              .read(prepareLightningPaymentProvider(paymentArgs).future);
          final dynamic rawPrepareResp = prepWrapper.prepareResponse;
          final int confirmAmount;
          if (rawPrepareResp is PrepareSendPaymentResponse) {
            confirmAmount = rawPrepareResp.amount.toInt();
          } else if (rawPrepareResp is PrepareLnurlPayResponse) {
            confirmAmount = rawPrepareResp.amountSats.toInt();
          } else {
            throw StateError('Invalid prepared Lightning payment.');
          }
          if (!context.mounted ||
              !await _reviewPreparedAmount(context, amount, confirmAmount)) {
            return;
          }
          actualSentAmount = confirmAmount;

          List<FeeDetail> feeList = [];

          if (rawPrepareResp is PrepareSendPaymentResponse) {
            final method = rawPrepareResp.paymentMethod;
            if (method is SendPaymentMethod_Bolt11Invoice) {
              if (method.lightningFeeSats > BigInt.zero) {
                feeList.add(FeeDetail(
                    label: l10n.sendRoutingFee,
                    amountSats: method.lightningFeeSats.toInt()));
              }
              if (method.sparkTransferFeeSats != null &&
                  method.sparkTransferFeeSats! > BigInt.zero) {
                feeList.add(FeeDetail(
                    label: l10n.serviceFee,
                    amountSats: method.sparkTransferFeeSats!.toInt()));
              }
            }
          } else if (rawPrepareResp is PrepareLnurlPayResponse) {
            if (rawPrepareResp.feeSats > BigInt.zero) {
              feeList.add(FeeDetail(
                  label: l10n.networkFee,
                  amountSats: rawPrepareResp.feeSats.toInt()));
            }
          } else if (prepWrapper.networkFee > 0 && feeList.isEmpty) {
            feeList.add(FeeDetail(
                label: l10n.networkFee, amountSats: prepWrapper.networkFee));
          }

          // No second confirmation modal — the user already
          // confirmed once via the send screen's primary button
          // (and the SwapConfirmationPage if a top-up was needed).
          // ignore: unused_local_variable
          final _feeListUnused = feeList;

          var lightningFeeCapSats = 0;
          for (final fd in feeList) {
            lightningFeeCapSats += fd.amountSats;
          }
          sentFeeSats = lightningFeeCapSats;
          final lightningIntent = _sendIntent(
            venue: 'lightning',
            destination: resolvedAddress,
            amountMax: BigInt.from(confirmAmount),
            provider: 'breez',
            sourcePool: 'btc',
            feeCap: lightningFeeCapSats,
          );
          if (!context.mounted) return;
          if (!await _approveAndConsumeSend(
            context,
            reviewed: lightningIntent,
            actual: lightningIntent,
            amountLabel: _btcAmountLabel(confirmAmount),
            amountUsd: _usdForSats(confirmAmount),
          )) {
            return;
          }

          sendStage = 'broadcast';
          await ref
              .read(executeLightningPaymentProvider(rawPrepareResp).future);

          // A Lightning address is a reusable destination: keep it as
          // an SDK contact (or mark it the most recently used) for
          // "Recent recipients". Best effort, never part of the send.
          if (rawPrepareResp is PrepareLnurlPayResponse) {
            final lnAddress = rawPrepareResp.payRequest.address?.trim() ?? '';
            if (lnAddress.isNotEmpty) {
              unawaited(ref
                  .read(sparkContactsProvider.notifier)
                  .recordSent(lnAddress));
            }
          }

          // Phase 9 — log Lightning routing fee. Breez exposes the
          // fee on the prepared payment method; sum any L1/L2
          // components (Bolt11 routing + Spark-transfer side-fee)
          // and convert sats → USD for the ledger.
          try {
            int totalLightningFeeSats = 0;
            for (final fd in feeList) {
              totalLightningFeeSats += fd.amountSats;
            }
            if (totalLightningFeeSats > 0) {
              final usdPerBtc =
                  ref.read(selectedCurrencyProvider('usd')).toDouble();
              final feeUsd = (totalLightningFeeSats / 1e8) * usdPerBtc;
              if (feeUsd > 0) {
                FeeHistoryService.log(
                  id: 'ln-${DateTime.now().millisecondsSinceEpoch}',
                  kind: FeeKind.lightningRouting,
                  microUsd: (feeUsd * 1000000).round(),
                  nativeAmount: totalLightningFeeSats.toString(),
                  nativeUnit: 'sats',
                  source: 'Lightning',
                  walletId: ref.read(settingsProvider).activeWalletId,
                );
              }
            }
          } catch (_) {}
          break;

        case AnalyzedPaymentType.unknown:
          sendStage = 'validate';
          throw LocalizedError.from(
              l10n, (l) => l.sendUnsupportedAddressFormat);
      }

      // The payment went out: one outcome event and the abandonment
      // guard, whether or not the screen is still mounted. Lightning
      // execution returns no payment id; the in-flight guard in
      // _handleSend already keeps it to one per confirmed send.
      _sendCompleted = true;
      TrackingService.sendCompleted(
        flow: 'pay',
        network: sendNetwork,
        asset: 'btc',
        walletKind: _sendWalletKind(confirmedWallet),
        provider: 'breez',
        amountUsd: _usdForSats(actualSentAmount),
        amountSats: actualSentAmount,
        currency: sendFiat.currency,
        amountFiat: sendFiat.amountFiat,
        feeSats: sentFeeSats,
        feeUsd: sentFeeSats == null ? null : _usdForSats(sentFeeSats),
        networkFeeUsd:
            sentNetworkFeeSats == null ? null : _usdForSats(sentNetworkFeeSats),
        feeTier: sentFeeTier,
        dedupeKey: sentPaymentId,
      );
      TrackingService.moneyFlowFinished('send');

      if (mounted) {
        SoundService.playSend();
        BackgroundSyncService().syncNow();
        // Asset label reflects the *resolved* rail (bip21 → lightning
        // unwrapping is handled above), so a BIP-21 LN payment shows
        // "Lightning" and not "Bitcoin". Spark internal sends show the
        // raw Spark address shortened, so the modal doesn't print all
        // 65 characters.
        final String successAsset;
        switch (resolvedType) {
          case AnalyzedPaymentType.lightning:
          case AnalyzedPaymentType.lnurl:
            successAsset = 'Lightning';
            break;
          case AnalyzedPaymentType.spark:
            successAsset = 'Spark';
            break;
          default:
            successAsset = 'Bitcoin';
        }
        final String successReceiveAddress;
        if (resolvedType == AnalyzedPaymentType.spark &&
            !resolvedAddress.contains('@')) {
          successReceiveAddress = resolvedAddress.length >= 10
              ? '${resolvedAddress.substring(0, 6)}…${resolvedAddress.substring(resolvedAddress.length - 4)}'
              : resolvedAddress;
        } else if (resolvedType == AnalyzedPaymentType.lightning ||
            resolvedType == AnalyzedPaymentType.lnurl) {
          // Prefer the human-readable lightning address the user typed
          // (user@domain) over the raw bolt11 the resolver produced.
          // Raw invoices that do get through are truncated to
          // head…tail by the overlay itself, never shown in full.
          final typed = address.trim();
          successReceiveAddress =
              typed.contains('@') && !typed.toLowerCase().startsWith('ln')
                  ? typed
                  : resolvedAddress;
        } else {
          successReceiveAddress = resolvedAddress;
        }
        // Fiat companion for the success overlay — same converter the
        // review hero uses. Never block success on a rate hiccup.
        String? successFiat;
        try {
          successFiat = ref.read(conversionToFiatProvider(actualSentAmount));
        } catch (_) {}
        showFullscreenTransactionSendModal(
          context: context,
          asset: successAsset,
          amount: '${actualSentAmount.toFormattedString(btcFormat)} $btcFormat',
          fiat: false,
          fiatAmount: successFiat,
          receiveAddress: successReceiveAddress,
        );

        final network = sendNetwork;
        // NOTE: `transaction_sent` is NOT emitted here anymore. It's
        // fired once, centrally, from `transactions_provider`'s
        // `_reportNewSends` when the sent tx appears in the canonical
        // snapshot — so every send (this hot-wallet path AND the
        // hardware PSBT path) is counted exactly once with no dupes.
        // `_handleSend` runs only the Spark hot-wallet path — hardware
        // signers (Ledger / Jade / watch-only PSBT) live in their own
        // success handlers in `watch_only_screen.dart` and the
        // device-picker callbacks. So `signer_type` here is always
        // `spark_hot`.
        TrackingService.track('pay_transaction_signed', params: {
          'payment_type': network,
          'signer_type': 'spark_hot',
        });
        // Phase 3: `_sendCompleted` (set above) tells dispose() this
        // flow reached a successful broadcast — not an abandonment.

        // Lightning sends aren't a qualifying or milestone event in the
        // wallet-native affiliate program (Telegram-era `send_tx` milestone
        // was retired). Tracking still fires via PostHog for
        // engagement analytics; no backend ping required.

        ref.read(sendTxProvider.notifier).resetToDefault();
        // Removed context.replace('/home') — it was tearing down the success overlay before mount. Overlay's Done button takes the user home now.
      }
    } catch (e) {
      TrackingService.paymentFailed(
          network: sendNetwork, reason: TrackingService.errorCategory(e));
      TrackingService.moneyFlowError('send', e);
      // `_sendCompleted` here means only the post-broadcast UI threw:
      // the send itself already reported send_completed.
      if (!_sendCompleted) {
        TrackingService.sendFailed(
          flow: 'pay',
          network: sendNetwork,
          asset: 'btc',
          error: e,
          walletKind: _sendWalletKind(confirmedWallet),
          provider: 'breez',
          amountUsd: _usdForSats(actualSentAmount),
          amountSats: actualSentAmount,
          currency: sendFiat.currency,
          amountFiat: sendFiat.amountFiat,
          feeSats: sentFeeSats,
          feeUsd: sentFeeSats == null ? null : _usdForSats(sentFeeSats),
          feeTier: sentFeeTier,
          stage: sendStage,
        );
        TrackingService.moneyFlowError('send', e);
        // Try again re-prepares from scratch: a fresh balance for a
        // 100% send and a fresh fee quote, rather than the preparation
        // the SDK just refused (an expired quote, a fee that moved).
        ref.invalidate(prepareGenericPaymentProvider);
        ref.invalidate(prepareLightningPaymentProvider);
      }
      if (mounted) _showSendFailed(e);
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _handleBitcoinSoftwareSend(BuildContext context, WidgetRef ref,
      WalletConfig wallet, String address, int amount) async {
    if (_selectedDestAsset != null ||
        _selectedDestNetwork != null ||
        _detectAddressType(address).label != 'Bitcoin on-chain') {
      showMessageSnackBar(
        message: context.l10n.sendThisWalletCanOnlySendBitcoin,
        error: true,
        context: context,
      );
      return;
    }
    final request = _softwareSendRequest(wallet);
    final previewProvider = bitcoinSoftwareSendPreviewProvider(request);
    final previewState = ref.read(previewProvider);
    final reviewedPsbt = previewState.isLoading || previewState.hasError
        ? null
        : previewState.valueOrNull;
    final feeRate = ref.read(getCustomFeeRateProvider).valueOrNull;
    if (!_softwareReviewReady(reviewedPsbt, amount) || feeRate == null) {
      showMessageSnackBar(
          message: context.l10n.sendWaitForFee, error: true, context: context);
      return;
    }
    final drain = _isDraining;
    final customFee = ref.read(customFeeRateProvider);
    final blocks = ref.read(sendBlocksProvider);
    final utxos =
        List<onchain.OutPoint>.unmodifiable(ref.read(selectedUtxosProvider));
    bool isCurrent() {
      if (!mounted) return false;
      final currentWallet = _resolveSourceWallet();
      return currentWallet?.id == wallet.id &&
          currentWallet?.isBitcoinSoftware == true &&
          currentWallet?.scriptType == wallet.scriptType &&
          addressController.text == address &&
          ref.read(sendTxProvider).amount == amount &&
          _isDraining == drain &&
          _selectedDestAsset == null &&
          _selectedDestNetwork == null &&
          ref.read(customFeeRateProvider) == customFee &&
          ref.read(sendBlocksProvider) == blocks &&
          ref.read(getCustomFeeRateProvider).valueOrNull == feeRate &&
          listEquals(ref.read(selectedUtxosProvider), utxos) &&
          !ref.read(previewProvider).isLoading &&
          !ref.read(previewProvider).hasError &&
          identical(ref.read(previewProvider).valueOrNull, reviewedPsbt);
    }

    setState(() {
      isProcessing = true;
      _paymentAuthInFlight = true;
    });
    var softwareStage = 'sign';
    final softwareFiat = _sendFiatContext();
    int? softwareFeeSats;
    // Same tiers as the advanced sheet: 1 = fast, 2 = standard, 3 = slow.
    final softwareFeeTier = customFee != null
        ? 'custom'
        : switch (blocks) {
            1 => 'fast',
            2 => 'standard',
            3 => 'slow',
            _ => 'custom',
          };
    try {
      // Phase 1b.2: the reviewed PSBT and its fee exist before the prompt.
      Object? reviewedFeeSats;
      try {
        reviewedFeeSats = reviewedPsbt?.fee();
      } catch (_) {}
      final feeValue = reviewedFeeSats;
      if (feeValue is int) {
        softwareFeeSats = feeValue;
      } else if (feeValue is BigInt) {
        softwareFeeSats = feeValue.toInt();
      }
      final sendIntent = _sendIntent(
        walletId: wallet.id,
        venue: 'bitcoin',
        destination: request.address,
        amountMax: BigInt.from(amount),
        provider: 'bdk',
        sourcePool: 'btc',
        feeCap: reviewedFeeSats,
        extra: {'feeRate': feeRate.toString()},
      );
      final approved = await _approveSend(
        context,
        sendIntent,
        amountLabel: _btcAmountLabel(amount),
        amountUsd: _usdForSats(amount),
      );
      if (!approved || !mounted || !context.mounted) return;
      if (!isCurrent()) {
        _dropSendGrant();
        await showStepUpReviewAgain(context,
            action: SensitiveAction.send, field: DriftField.other);
        return;
      }
      if (!await _consumeSend(context, sendIntent)) return;
      softwareStage = 'broadcast';
      final model =
          await ref.read(bitcoinModelForWalletProvider(wallet.id).future);
      final result = await BitcoinSoftwareSend.send(
        model: model,
        transaction: TransactionBuilder(amount, request.address, feeRate,
            selectedUtxos: utxos.isEmpty ? null : utxos),
        drain: drain,
        reviewedPsbt: reviewedPsbt,
        isCurrent: isCurrent,
      );
      _sendCompleted = true;
      TrackingService.sendCompleted(
        flow: 'bitcoin_software',
        network: 'bitcoin',
        asset: 'btc',
        walletKind: _sendWalletKind(wallet),
        provider: 'bdk',
        amountUsd: _usdForSats(result.recipientSats),
        amountSats: result.recipientSats,
        currency: softwareFiat.currency,
        amountFiat: softwareFiat.amountFiat,
        feeSats: result.feeSats,
        feeUsd: _usdForSats(result.feeSats),
        networkFeeUsd: _usdForSats(result.feeSats),
        feeTier: softwareFeeTier,
        dedupeKey: result.txid,
      );
      TrackingService.moneyFlowFinished('send');
      unawaited(BackgroundSyncService()
          .scanBdkScope(source: 'bitcoin_send')
          .catchError((_) {}));
      if (!context.mounted) return;
      final btcFormat = ref.read(settingsProvider).btcFormat;
      showFullscreenTransactionSendModal(
        context: context,
        asset: 'Bitcoin',
        amount:
            '${result.recipientSats.toFormattedString(btcFormat)} $btcFormat',
        fiat: false,
        receiveAddress: request.address,
      );
      ref.read(sendTxProvider.notifier).resetToDefault();
    } catch (error) {
      final stoppedForReview = error is OnchainException &&
          (error.code == 'wallet_mismatch' || error.code == 'review_changed');
      // A send stopped for re-review broadcast nothing and goes back to
      // Review for another confirm tap, so it is not this send's outcome.
      // `_sendCompleted` here means only the post-broadcast UI threw.
      if (!stoppedForReview && !_sendCompleted) {
        TrackingService.sendFailed(
          flow: 'bitcoin_software',
          network: 'bitcoin',
          asset: 'btc',
          error: error,
          walletKind: _sendWalletKind(wallet),
          provider: 'bdk',
          amountUsd: _usdForSats(amount),
          amountSats: amount,
          currency: softwareFiat.currency,
          amountFiat: softwareFiat.amountFiat,
          feeSats: softwareFeeSats,
          feeUsd: softwareFeeSats == null ? null : _usdForSats(softwareFeeSats),
          feeTier: softwareFeeTier,
          stage: softwareStage,
        );
        TrackingService.moneyFlowError('send', error);
      }
      if (context.mounted) {
        if (stoppedForReview) {
          // Stopped before broadcast, so nothing was sent (C8).
          await showStepUpReviewAgain(context,
              action: SensitiveAction.send, field: DriftField.other);
        } else {
          _showSendFailed(error);
        }
      }
    } finally {
      _paymentAuthInFlight = false;
      if (mounted) setState(() => isProcessing = false);
    }
  }

  void _resetSendState() {
    ref.read(sendTxProvider.notifier).resetToDefault();
  }

  /// AppBar leading-icon handler. On step 0 we close the whole
  /// screen; on every later step we step the stepper back one page
  /// so the user can edit a prior choice without losing what they've
  /// already typed in subsequent steps.
  ///
  /// Stepping back also drops the *current* step from
  /// `_completedSteps` — otherwise hitting back, then changing the
  /// previous answer, would leave the now-stale "current" step
  /// pre-marked done and the user would skip past it on the next
  /// auto-advance.
  void _onLeadingTap() {
    if (_signerBusy) return;
    if (_step <= 0) {
      _closeAndReset();
      return;
    }
    final target = _step - 1;
    HapticFeedback.selectionClick();
    setState(() {
      _completedSteps.remove(_step);
    });
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _pageCtrl.jumpToPage(target);
    } else {
      _pageCtrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _closeAndReset() {
    _resetSendState();
    // Just pop — context.replace('/home') was causing the home screen to
    // fully rebuild/reload. A pop returns to whatever opened confirm (usually
    // /pay or directly /home in deep-link cases), preserving state.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Re-detect invoice locking on every address change, regardless of
    // entry path (typed, pasted, scanned, picked from wallets sheet).
    // Without this, a Bolt11/Bolt12/SparkInvoice/fixed-LNURL pasted
    // straight into the field never gets checked, and the amount field
    // stays editable for a fixed-amount invoice.
    ref.listen<String>(sendTxProvider.select((s) => s.address), (prev, next) {
      if (prev == next) return;
      _checkAndPopulateInvoiceAmount(next);
    });

    // Recompute the 100% amount whenever the user adjusts the fee
    // (custom rate or speed bucket). A BDK drain (hot, hardware or
    // watch-only) takes its fee out of the principal, so changing the
    // fee while 100% is armed re-sizes the displayed amount. The
    // spending wallet's Spark speed is not this rate; its amount
    // follows `_sparkOnchainSpeed` on Review.
    ref.listen<double?>(customFeeRateProvider, (prev, next) {
      if (prev == next) return;
      _refreshDrainAmount();
      // Sign step: rebuild the PSBT against the new fee rate so the
      // hardware device sees the user's actual selection. The check
      // for `_step == 3` keeps us from re-building while the user is
      // still on Amount/Send-to/Review — they get the speed change
      // applied at the natural Continue-to-Sign moment instead.
      if (_step == 3 && mounted) unawaited(_rebuildSignPagePsbt());
    });
    ref.listen<int>(sendBlocksProvider, (prev, next) {
      if (prev == next) return;
      _refreshDrainAmount();
      if (_step == 3 && mounted) unawaited(_rebuildSignPagePsbt());
    });
    ref.listen(selectedUtxosProvider, (prev, next) {
      if (_step != 3 || !mounted || _signedPsbtAccepted || _signerBusy) return;
      final previousCoins = {
        for (final coin in prev ?? <onchain.OutPoint>[])
          '${coin.txid}:${coin.vout}'
      };
      final nextCoins = {for (final coin in next) '${coin.txid}:${coin.vout}'};
      if (previousCoins.length == nextCoins.length &&
          previousCoins.containsAll(nextCoins)) {
        return;
      }
      unawaited(_rebuildSignPagePsbt());
    });

    // Sync address and amount when returning from camera or provider changes
    final providerState = ref.watch(sendTxProvider);
    if (providerState.address != addressController.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && providerState.address != addressController.text) {
          addressController.text = providerState.address;
          if (providerState.amount > 0) {
            updateControllerText(providerState.amount);
          }
          // Re-run invoice detection on every camera/wallet-picker
          // round-trip. The `ref.listen` above only fires on changes
          // observed AFTER its registration; if the camera scan
          // landed while we were navigated off this screen, the
          // value is already current at first build and the listener
          // never sees a transition. Driving detection from the
          // post-frame callback here covers the "I scanned, came
          // back, the field isn't recognized as an invoice yet" UX
          // bug — without this the user has to tap the input to
          // re-trigger detection manually.
          _checkAndPopulateInvoiceAmount(providerState.address);
        }
      });
    }
    final c = context.colors;
    final currentInputCurrency = ref.watch(inputCurrencyProvider);
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    // Bitcoin balance of the send source. The displayed number must
    // reflect the SELECTED source wallet —
    // sending from a hardware-wallet detail screen leaves the active
    // wallet pinned to the spending wallet, so a raw
    // `balanceNotifierProvider.sparkBitcoinbalance` read would show
    // the wrong balance everywhere downstream (header, Max, Review,
    // "Available" line).
    final btcSats = _selectedSpendableSats(ref);
    // Rebuild on BTC/USD moves: Review's quote fee note reads it.
    ref.watch(selectedCurrencyProvider('USD')).toDouble();

    return PopScope(
      canPop: !isProcessing && !_signerBusy,
      // Reset send-tx state when this route is popped — but DO NOT
      // call context.pop() again here. onPopInvoked fires *during*
      // the pop already in progress; calling pop again from inside
      // it trips the navigator's `_debugLocked` assertion. The
      // close-button branch still calls _closeAndReset (which
      // triggers the pop that lands here), so resetting once is
      // enough.
      onPopInvoked: (bool didPop) {
        // Defer the provider mutation. `onPopInvoked` runs
        // inside the navigator's build/route-update phase —
        // when the resume handler routes to `/home` and pops
        // this confirm_send route as part of the stack reset,
        // mutating sendTxProvider here trips Riverpod's
        // "modify-during-build" guard and crashes.
        if (didPop) {
          Future.microtask(() {
            if (!mounted) return;
            _resetSendState();
          });
        }
      },
      child: KeyboardDismissOnTap(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: c.background,
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            // Material-3's tonal AppBar adds a faint surface
            // tint band when scrolled — explicit transparent
            // here kills the white sliver shown above the
            // progress bar at the top of the screen.
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            centerTitle: true,
            // Identify the entry wallet without allowing a mid-send switch.
            title: AccountSwitcherPill(
              pickerTitle: context.l10n.sendFromPickerTitle,
              account: _selectedAccount,
              readOnly: true,
            ),
            // First tap on a sub-step rewinds the stepper one
            // page (and unlocks future steps so the user can
            // re-edit). Only when we're already on step 0
            // does X actually close the screen — keeps the
            // gesture cheap to undo a mis-click without
            // losing the whole address/amount they typed.
            // Back uses the same thin chevron as KuteBackButton
            // everywhere else; step 0 keeps a close glyph since
            // there's nothing to go back to.
            leading: _step == 0
                ? KuteBareCloseButton(
                    onPressed: () {
                      if (!isProcessing) _onLeadingTap();
                    },
                  )
                : KuteBackButton(
                    onPressed: () {
                      if (!isProcessing) _onLeadingTap();
                    },
                  ),
          ),
          body: _buildStepperBody(
            context: context,
            c: c,
            btcSats: btcSats,
            btcFormat: btcFormat,
            currentInputCurrency: currentInputCurrency,
          ),
          bottomNavigationBar: null,
        ),
      ),
    );
  }

  // ─── Step body builder + helpers ────────────────────────────
  // Old single-screen body kept below as `_legacyBody` purely to
  // preserve the inline subcomponents we still reuse (currency picker
  // chip, MAX chip, network picker, address input). The new
  // `_buildStepperBody` wires them into the four-step progressive
  // disclosure flow:  Pay with  →  Amount  →  Send to  →  Review.

  Widget _buildStepperBody({
    required BuildContext context,
    required AppColorsExtension c,
    required int btcSats,
    required String btcFormat,
    required String currentInputCurrency,
  }) {
    return SendStepperFrame(
      progress:
          // Hardware / watch-only wallets sign the PSBT *outside*
          // the app (USB / scan-and-paste), so the flow has
          // an extra explicit "Sign" step at the end that hot
          // wallets don't need. Total steps + page list adapt
          // accordingly.
          () {
        // Source wallet from `_selectedWalletId` first — active
        // is pinned to spending so a hardware-source flow would
        // otherwise report 3 steps and miss the Sign page.
        final settings = ref.read(settingsProvider);
        final WalletConfig? w = _selectedWalletId != null
            ? settings.wallets.firstWhere(
                (x) => x.id == _selectedWalletId,
                orElse: () => settings.activeWallet ?? settings.wallets.first,
              )
            : settings.activeWallet;
        final isExternalSigner = w != null && (w.isHardware || w.isWatchOnly);
        // Internal PageView indices: 0=Amount, 1=Send-to,
        // 2=Review, (3=Sign for hardware). Translate to a
        // visible step bar so pages we're *skipping* don't
        // render as mysteriously-completed segments (the
        // green chunk reported on the screenshot was Send-to
        // being auto-marked complete before the user got
        // there). Hidden pages drop entirely; current /
        // completed get re-indexed to the visible positions.
        final internalTotal = isExternalSigner ? 4 : 3;
        final hidden = <int>{};
        if (_skipAmountStep) hidden.add(0);
        if (_skipSendToStep) hidden.add(1);
        final visiblePages = <int>[
          for (var i = 0; i < internalTotal; i++)
            if (!hidden.contains(i)) i
        ];
        // Find the visible position of the active internal
        // step. If somehow it's hidden (shouldn't happen),
        // pin to the last visible.
        int currentVisible = visiblePages.indexOf(_step);
        if (currentVisible < 0) {
          currentVisible = visiblePages.length - 1;
        }
        final completedVisible = <int>{
          for (var i = 0; i < visiblePages.length; i++)
            if (_completedSteps.contains(visiblePages[i])) i,
        };
        if (visiblePages.length <= 1) {
          // Single-step flows don't need a bar — it would
          // render as one fixed-length pill that conveys
          // nothing. Just collapse the row.
          return const SizedBox.shrink();
        }
        return StepperProgress(
          totalSteps: visiblePages.length,
          currentStep: currentVisible,
          completedSteps: completedVisible,
          colors: c,
        );
      }(),
      // Steps advance only via the Continue/Next buttons
      // (`_confirmStep` → `animateToPage`); the frame turns
      // swiping off.
      controller: _pageCtrl,
      onPageChanged: (i) {
        setState(() => _step = i);
        // Arriving on Send to: offer a recognisable address
        // or invoice already sitting in the clipboard.
        if (i == 1) _checkClipboardForAddress();
      },
      pages: [
        StepPageWrapper(
          title: context.l10n.amount,
          subtitle: _hasSource
              ? context.l10n.sendHowMuchBitcoin
              : context.l10n.sendHowMuch,
          colors: c,
          child: _amountPage(c, currentInputCurrency, btcFormat, btcSats),
        ),
        StepPageWrapper(
          title: context.l10n.sendTo,
          subtitle: context.l10n.sendWhereShouldItLand,
          colors: c,
          child: _sendToPage(c),
        ),
        StepPageWrapper(
          title: context.l10n.sendReview,
          subtitle: context.l10n.sendConfirmTheDetails,
          trailing: const AskSalChip(
            advisorContext: AdvisorContext(surface: 'send_review'),
          ),
          colors: c,
          child: _reviewPage(c, btcFormat),
        ),
        // Step 3 (Sign) — only meaningful for hardware /
        // watch-only wallets; hot wallets reach broadcast
        // straight from Review and never see this page.
        // Source is the SELECTED wallet (active is pinned
        // to spending so checking it would skip the Sign
        // page on hardware sends opened from wallet detail).
        if ((() {
          final settings = ref.read(settingsProvider);
          final WalletConfig? w = _selectedWalletId != null
              ? settings.wallets.firstWhere(
                  (x) => x.id == _selectedWalletId,
                  orElse: () => settings.activeWallet ?? settings.wallets.first,
                )
              : settings.activeWallet;
          return w != null && (w.isHardware || w.isWatchOnly);
        })())
          StepPageWrapper(
            title: context.l10n.sendSign,
            subtitle: context.l10n.sendSignTheTransactionOnYourDevice,
            colors: c,
            // Keep the same display typography as the
            // earlier steps so the user doesn't jump from
            // 32sp titles on Amount / Send to / Review
            // into a noticeably smaller Sign step. The
            // padding inside `_SignPageContainer` is
            // already trimmed enough to fit the device
            // picker without making the title small.
            child: _signPage(c, btcFormat),
          ),
      ],
      // Shared bottom CTA — single Continue button that
      // adapts per step. Hidden on Step 0 (auto-advance on
      // tile tap) and Step 3 (slide-to-send lives in the
      // page itself).
      cta: SharedStepCta(
        step: _step,
        colors: c,
        visibleSteps: const {0, 1},
        enabled: () {
          if (_step == 0) {
            final amount = ref.watch(sendTxProvider).amount;
            return amount > 0 &&
                !_amountExceedsPool(amount, _selectedPoolSats(btcSats));
          }
          if (_step == 1) {
            final addr = addressController.text;
            if (addr.isEmpty) return false;
            final detected = _detectAddressType(addr);
            // Non-native addresses (EVM / Solana / anything we
            // can't identify) MUST go through a destination
            // pick — the on-chain delivery rail can't be
            // inferred from address shape alone (a 0x… address
            // is valid on Polygon, Ethereum, BSC, Arbitrum…).
            // Without an explicit network the Orchestra quote
            // in Review fires against the wrong chain. Gate
            // Continue until the user picks.
            final isNativeBtcRail = detected.label == 'Bitcoin on-chain' ||
                detected.label == 'Lightning invoice' ||
                detected.label == 'Lightning address' ||
                detected.label == 'LNURL' ||
                detected.label == 'Spark address';
            if (!isNativeBtcRail) {
              if (_selectedDestAsset == null || _selectedDestNetwork == null) {
                return false;
              }
            }
            // Phase 19 — hardware / watch-only wallets can't
            // sign Lightning natively. Only accept LN-shaped
            // addresses when the user has explicitly picked
            // the Lightning option in the Other Network sheet
            // (`_selectedDestNetwork.network == 'lightning'`).
            // Otherwise the address fails validation here so
            // they get a clear "no" before reaching Review.
            // Source wallet from _selectedWalletId, not active.
            final settingsLocal = ref.read(settingsProvider);
            final WalletConfig? sourceLocal = _selectedWalletId != null
                ? settingsLocal.wallets.firstWhere(
                    (w) => w.id == _selectedWalletId,
                    orElse: () =>
                        settingsLocal.activeWallet ??
                        settingsLocal.wallets.first,
                  )
                : settingsLocal.activeWallet;
            final isExternalSigner = sourceLocal?.usesBdk ?? false;
            if (sourceLocal?.isBitcoinSoftware == true) {
              return detected.label == 'Bitcoin on-chain';
            }
            if (!isExternalSigner) return true;
            final isLnLike = detected.label == 'Lightning invoice' ||
                detected.label == 'Lightning address' ||
                detected.label == 'LNURL';
            if (!isLnLike) return true;
            final dstIsLightning =
                _selectedDestNetwork?.network.toLowerCase() == 'lightning';
            return dstIsLightning;
          }
          return false;
        }(),
        onContinue: () {
          if (_step == 0) _confirmStep(0);
          if (_step == 1) _confirmStep(1);
        },
      ),
    );
  }

  // ─── Step 1: Pay with ───────────────────────────────────────

  // ─── Step 2: Amount ─────────────────────────────────────────

  /// Sats the send source can cover. 0 when there is no source or the
  /// balance is unknown or not loaded yet, which callers treat as
  /// "don't judge" rather than "nothing available".
  int _selectedPoolSats(int btcSats) => _hasSource ? btcSats : 0;

  /// True when the typed amount is more than the selected pool holds.
  /// Only judged once a balance is known; a 0 pool (cold wallet cache
  /// still scanning) must not paint every amount red.
  bool _amountExceedsPool(int amountSats, int poolSats) =>
      poolSats > 0 && amountSats > poolSats;

  /// ATM-style Bitcoin amount display. Renders the formatted amount
  /// via `Text.rich` so the leading-zero padding (in BTC mode) draws in
  /// tertiary color while the user's actual keystrokes land in primary.
  /// Digits come from the in-app keypad through `_atmDigits`; there is
  /// no TextField here, so the OS keyboard never opens on this step.
  Widget _buildAtmAmountInput(AppColorsExtension c, String currentInputCurrency,
      {bool overBalance = false}) {
    final isSatsUnit = currentInputCurrency == 'Sats';
    final hasDigits = _atmDigits.isNotEmpty;
    final typedColor = overBalance ? AppColors.marketDown : c.textPrimary;
    final formatted = _formatAtmAmount(_atmDigits, currentInputCurrency);
    // Split the formatted display into (greyed-leading) + (typed-trailing).
    // In sats mode there's no leading padding — everything the user
    // typed is the whole string.
    final (leading, trailing) = isSatsUnit || !hasDigits
        ? (hasDigits ? '' : formatted, hasDigits ? formatted : '')
        : _splitAtmDisplay(formatted, _atmDigits.length);
    final amountTextStyle = TextStyle(
      fontSize: 56.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_getCurrencyPrefix(currentInputCurrency),
            style: amountTextStyle.copyWith(
                color: hasDigits ? typedColor : c.textTertiary)),
        SizedBox(width: 6.w),
        // The amount itself — Text.rich so leading-zero padding (BTC
        // mode) can fade to tertiary while the typed digits land in
        // primary, making the right-to-left growth feel like an ATM
        // keypad.
        Text.rich(
          TextSpan(
            children: [
              if (leading.isNotEmpty)
                TextSpan(
                  text: leading,
                  style: amountTextStyle.copyWith(color: c.textTertiary),
                ),
              if (trailing.isNotEmpty)
                TextSpan(
                  text: trailing,
                  style: amountTextStyle.copyWith(color: typedColor),
                ),
            ],
          ),
          maxLines: 1,
        ),
        // Sats mode no longer trails a "sats" label — the ₿
        // prefix (BIP-177) already denotes the unit, matching the
        // activity feed and balance headline.
      ],
    );
  }

  /// Fiat twin of [_buildAtmAmountInput]: the typed fiat amount as one
  /// big static number. The raw string lives in `controller` (no
  /// thousands separators) and is grouped only for display, so the
  /// keypad can read it straight back.
  Widget _fiatAmountHero(AppColorsExtension c, String currentInputCurrency,
      {bool overBalance = false}) {
    return SendTypedAmountHero(
      prefix: _getCurrencyPrefix(currentInputCurrency),
      typed: controller.text,
      overBalance: overBalance,
    );
  }

  /// Apply a fiat amount typed on the in-app keypad. Mirrors the write
  /// path the old fiat TextField used: raw string into `controller`
  /// (and `inputAmountProvider`), parsed sats into `sendTxProvider`.
  void _applyFiatTyped(String raw, String currentInputCurrency) {
    if (controller.text == raw) return;
    setState(() {
      controller.value = TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      );
    });
    _setDraining(false);
    ref.read(inputAmountProvider.notifier).state = raw.isEmpty ? '0.0' : raw;
    final amountInSats = ref.read(
        inputToSatsProvider((amount: raw, currency: currentInputCurrency)));
    ref
        .read(sendTxProvider.notifier)
        .updateAmountFromInput(amountInSats.toString(), 'sats');
  }

  /// Fiat unit the swap icon flips to from a Bitcoin unit: the one the
  /// user last typed in, else the settings currency when the unit
  /// sheet offers it, else USD.
  String _fiatFlipUnit() {
    const supported = {'USD', 'EUR', 'GBP', 'BRL', 'CHF'};
    final last = _lastFiatUnit;
    if (last != null && supported.contains(last)) return last;
    final settingsCode = currency.toUpperCase();
    return supported.contains(settingsCode) ? settingsCode : 'USD';
  }

  /// Flip the Amount entry unit between Bitcoin (sats / BTC per the
  /// display setting) and fiat, keeping the typed amount. The amount
  /// is held in sats by `sendTxProvider`, so only the text shown in
  /// the hero is re-rendered; nothing is re-parsed.
  void _flipAmountUnit(String currentUnit) {
    final isBtcUnit = currentUnit == 'Sats' || currentUnit == 'BTC';
    final String target;
    if (isBtcUnit) {
      target = _fiatFlipUnit();
    } else {
      _lastFiatUnit = currentUnit;
      target = btcFormat == 'BTC' ? 'BTC' : 'Sats';
    }
    HapticFeedback.selectionClick();
    ref.read(inputCurrencyProvider.notifier).state = target;
    final sats = ref.read(sendTxProvider).amount;
    if (sats > 0) {
      updateControllerText(sats);
    } else {
      controller.text = '';
      _syncAtmDigitsFromSats(0);
    }
    TrackingService.track('pay_amount_unit_flipped', params: {
      'unit': isBtcUnit ? 'fiat' : 'bitcoin',
    });
    setState(() {});
  }

  /// "$105.40" under a Bitcoin amount, "₿45,120" under a fiat one, plus
  /// the swap icon that calls [_flipAmountUnit]. The value carries no
  /// approximation mark: it reads as a second price tag, not a hedge.
  Widget _amountConversionLine(
      AppColorsExtension c, String unit, String btcFormat, int amountSats) {
    final isBtcUnit = unit == 'Sats' || unit == 'BTC';
    final String secondary;
    if (isBtcUnit) {
      final fiatCode = _fiatFlipUnit();
      final fiat = ref.watch(
          satsToTargetCurrencyProvider((sats: amountSats, currency: fiatCode)));
      secondary = '${_getCurrencyPrefix(fiatCode)}$fiat';
    } else {
      secondary = '₿${amountSats.toFormattedString(btcFormat)}';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          secondary,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 17.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(width: 4.w),
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _flipAmountUnit(unit),
            child: Padding(
              padding: EdgeInsets.all(6.w),
              child: Icon(Icons.swap_vert_rounded,
                  size: 20.sp, color: c.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _amountBody(AppColorsExtension c, String currentInputCurrency,
      String btcFormat, int btcSats) {
    // `btcSats` is already resolved by `_selectedSpendableSats` against
    // the SELECTED source wallet — hot wallets read Spark, cold
    // wallets read their per-id `walletBalanceCacheProvider` entry.
    // No need to fall back to the active wallet's
    // `onChainBtcBalance` anymore; that branch read the spending
    // wallet's BDK balance whenever the user opened Send from a
    // hardware detail screen (active wallet stays pinned to
    // spending), so the "X sats available" line was wrong.
    final selectedPoolFiat = ref.watch(conversionToFiatProvider(btcSats));
    final amountSats = ref.watch(sendTxProvider).amount;
    // Over-balance is judged here, at typing time, so the user is not
    // sent two steps on to fail in a Review fee row.
    final overBalance =
        _amountExceedsPool(amountSats, _selectedPoolSats(btcSats));
    final isBtcUnit =
        currentInputCurrency == 'Sats' || currentInputCurrency == 'BTC';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero ───────────────────────────────────
        // The one big number with its unit pill, the live
        // equivalent in the other unit (and the swap icon that flips
        // the entry unit) and the available balance. Scrolls so the
        // pinned keypad below always fits, even at 320 wide with the
        // largest text sizes.
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AnimatedBuilder(
                        // Pulse driven by the state-owned `_amountPulse`
                        // controller; the child is built once per frame
                        // and reused across the animation.
                        animation: _amountPulse,
                        builder: (context, child) {
                          final t = _amountPulse.value;
                          // Quick scale-up + ease back: starts at 0.94,
                          // lands at 1.0 with easeOutBack overshoot.
                          // Reads as a soft "digit lands" pop.
                          final scale =
                              0.94 + Curves.easeOutBack.transform(t) * 0.06;
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: FittedBox(
                          // Auto-shrinks long inputs (a ten-digit sat
                          // amount on a small phone) without manual
                          // size juggling; the default is the 56sp hero.
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: isBtcUnit
                              ? _buildAtmAmountInput(c, currentInputCurrency,
                                  overBalance: overBalance)
                              : _fiatAmountHero(c, currentInputCurrency,
                                  overBalance: overBalance),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    _AmountUnitPill(
                      code: currentInputCurrency,
                      icon: _currencyIcon(currentInputCurrency, size: 20.sp),
                      onTap: () => _showCurrencyPicker(context, ref),
                    ),
                  ],
                ),
                // Live equivalent of the typed amount in the other unit,
                // with the swap icon that flips the entry unit in place
                // (the amount stays, only the unit changes).
                if (_hasSource) ...[
                  SizedBox(height: 10.h),
                  _amountConversionLine(
                      c, currentInputCurrency, btcFormat, amountSats),
                ],
                if (overBalance) ...[
                  SizedBox(height: 8.h),
                  Text(
                    context.l10n.sendMoreThanAvailable,
                    style: TextStyle(
                      color: AppColors.marketDown,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
                SizedBox(height: 10.h),
                Text(
                  context.l10n.sendAmountUnitAvailableWithFiat(
                      btcSats.toFormattedString(btcFormat),
                      btcFormat,
                      selectedPoolFiat),
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Bottom, pinned: percent chips + keypad ─────────────
        // Percent-of-balance chips (Move sheet language): 25/50 set a
        // bounded amount through the normal write path; 100% routes
        // through the existing MAX logic so drain semantics, the LNURL
        // clamp and the cold-wallet branch stay intact.
        AmountPercentChips(
          enabled: !isInvoice && !isCalculatingMax,
          onPercent: (r) {
            if (isInvoice) return;
            _amountMethod = 'percent_${(r * 100).round()}';
            TrackingService.track('send_amount_percent_tapped', params: {
              'percent': (r * 100).round(),
              'source_asset': 'btc',
            });
            if (r >= 1.0) {
              _amountMethod = 'max';
              TrackingService.sendMaxTapped(
                  network: _networkLabel(ref.read(sendTxProvider).type));
              _setMaxAmount(ref);
              return;
            }
            HapticFeedback.selectionClick();
            _setDraining(false);
            final int poolSats = _selectedPoolSats(btcSats);
            final target = (poolSats * r).floor();
            if (target <= 0) return;
            ref.read(sendTxProvider.notifier).updateAmount(target);
            updateControllerText(target);
            if (_selectedDestAsset != null) _debouncedFetchRate();
          },
        ),
        SizedBox(height: 12.h),
        // The app's own keypad, same as the deposit / withdraw and
        // portfolio-builder amount sheets. Bitcoin units accumulate
        // whole sats (no decimal key); fiat types cents. Clamped text
        // scaling keeps the key rows from overflowing their 72.h boxes
        // at the largest accessibility sizes.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: AmountKeypad(
            value: isBtcUnit ? _atmDigits : controller.text,
            maxDecimals: isBtcUnit ? 0 : 2,
            // Invoice-locked amounts stay non-editable; everything else
            // (including while MAX is still resolving) can be typed
            // over, exactly as the old field allowed.
            enabled: !isInvoice,
            onChanged: (v) {
              if (isInvoice) return;
              _amountMethod = 'keypad';
              if (isBtcUnit) {
                _applyAtmDigits(v);
              } else {
                _applyFiatTyped(v, currentInputCurrency);
              }
              if (_selectedDestAsset != null) _debouncedFetchRate();
              // Decorative per-keystroke "digit lands" bounce — skipped
              // when the OS Reduce Motion preference is on.
              if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
                _amountPulse.forward(from: 0.0);
              }
            },
          ),
        ),
      ],
    );
  }

  // ─── Step 3: Send to ────────────────────────────────────────

  // ─── Step 4: Review ─────────────────────────────────────────

  /// Fee row content for a bitcoin Review that has no fee row of its
  /// own (a send not routed through the Spark, hardware or software fee
  /// rows below). Cross-chain sends use [_crossChainQuote] instead.
  ({String label, String value, String? eta, String? note, String? error})
      _estimateFees() {
    return (
      label: context.l10n.networkFee2,
      value: '—',
      eta: context.l10n.instant,
      note: null,
      error: null,
    );
  }

  /// The cross-chain Review's quote card, from the live Orchestra
  /// estimate in `_swapQuote` (fetched whenever the destination or the
  /// amount changes). Presentation only: the quote that is paid is
  /// requested again at Send and the step-up binds that one.
  ///
  /// `receive` is what arrives (`Calculating…` while the estimate
  /// loads); `error` is the live route error, or our local network-error
  /// catch, shown in red in its place. `rate` is the quote's own rate.
  /// `fee` is the route's whole cost in fiat — the fair value of the
  /// bitcoin sent less the value of what arrives — and only when both
  /// legs can be priced. No hardcoded percentage: if the provider's
  /// pricing or the rate moves, Review reflects it directly.
  ({String receive, bool quoted, String? rate, String? fee, String? error})
      _crossChainQuote() {
    if (_loadingRate) {
      return (
        receive: context.l10n.sendCalculatingEllipsis,
        quoted: false,
        rate: null,
        fee: null,
        error: null,
      );
    }
    final q = _swapQuote;
    final providerErr = (q != null && q.errors.isNotEmpty)
        ? userErrorCopy(context, q.errors.first,
            fallback: context.l10n.receiveFailedToGetRate)
        : null;
    final firstErr = _rateError ?? providerErr;
    if (firstErr != null) {
      return (
        receive: '',
        quoted: false,
        rate: null,
        fee: null,
        error: firstErr,
      );
    }
    if (q == null || q.toAmount <= 0) {
      return (
        receive: '—',
        quoted: false,
        rate: null,
        fee: null,
        error: null,
      );
    }
    final code = _selectedDestAsset?.code ?? q.toCcy;
    final rate = q.fromAmount > 0
        ? '1 ${q.fromCcy} ≈ ${_formatQuoteRate(q.toAmount / q.fromAmount)} $code'
        : null;
    String? fee;
    try {
      final usdPerBtc = ref.read(selectedCurrencyProvider('usd')).toDouble();
      final fiatPerUsd =
          ref.read(selectedCurrencyProviderFromUSD(currency)).toDouble();
      final usdPerToCcy = q.toCcy.toUpperCase().contains('USD') ? 1.0 : 0.0;
      final fromFiat = q.fromCcy.toUpperCase() == 'BTC'
          ? q.fromAmount * usdPerBtc * fiatPerUsd
          : q.fromCcy.toUpperCase().contains('USD')
              ? q.fromAmount * fiatPerUsd
              : 0.0;
      final toFiat = q.toCcy.toUpperCase() == 'BTC'
          ? q.toAmount * usdPerBtc * fiatPerUsd
          : usdPerToCcy > 0
              ? q.toAmount * fiatPerUsd
              : 0.0;
      if (fromFiat > 0 && toFiat > 0) {
        final feeFiat = fromFiat - toFiat;
        if (feeFiat > 0) {
          fee = NumberFormat.simpleCurrency(name: currency, decimalDigits: 2)
              .format(feeFiat);
        }
      }
    } catch (_) {}
    return (
      receive: '≈ ${_formatSmartDecimals(q.toAmount)} $code',
      quoted: true,
      rate: rate,
      fee: fee,
      error: null,
    );
  }

  /// A quote rate at a precision that reads: cents for a big figure
  /// (1 BTC ≈ 58,760.12 USDC), four places around one, and the coin's own
  /// significant digits below one.
  static String _formatQuoteRate(double r) {
    if (r >= 100) return NumberFormat('#,##0.00').format(r);
    if (r >= 1) return NumberFormat('#,##0.####').format(r);
    return _formatSmartDecimals(r);
  }

  /// The cross-chain Review's quote rows: what arrives first, then the
  /// rate and the fee in the quiet fee language, then the route one tap
  /// away — the same tap row the bitcoin Review uses for network speed.
  List<Widget> _crossChainQuoteRows(AppColorsExtension c) {
    final quote = _crossChainQuote();
    final error = quote.error;
    if (error != null) {
      return [
        // The error says "tap to retry" when it is ours; any route error
        // re-probes the same way.
        GestureDetector(
          onTap: _fetchRate,
          child:
              SendReviewErrorRow(label: context.l10n.youReceive, error: error),
        ),
      ];
    }
    return [
      _reviewKVRow(
          c: c,
          label: context.l10n.youReceive,
          value: quote.receive,
          muted: !quote.quoted),
      if (quote.rate != null) ...[
        SizedBox(height: 10.h),
        _reviewKVRow(
            c: c, label: context.l10n.rate, value: quote.rate!, muted: true),
      ],
      if (quote.fee != null) ...[
        SizedBox(height: 10.h),
        _reviewKVRow(
            c: c, label: context.l10n.fee, value: quote.fee!, muted: true),
      ],
      SizedBox(height: 12.h),
      Divider(height: 1, color: c.borderSubtle),
      SizedBox(height: 8.h),
      _reviewTapRow(
        c: c,
        icon: Icons.bolt_rounded,
        label: context.l10n.sendRouteDetails,
        value: 'Orchestra',
        onTap: () => _showSendRouteDetails(
            context, _selectedDestAsset, _selectedDestNetwork),
      ),
    ];
  }

  /// A tappable line at the foot of the Review fee card: icon, label,
  /// the current value and a chevron (network speed, route details).
  Widget _reviewTapRow({
    required AppColorsExtension c,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Row(
          children: [
            Icon(icon, size: 16.sp, color: c.textSecondary),
            SizedBox(width: 8.w),
            Text(
              label,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: 4.w),
            Icon(Icons.chevron_right_rounded,
                size: 18.sp, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _reviewBody(AppColorsExtension c, String btcFormat) {
    final addr = addressController.text;
    final shortAddr = addr.length > 22
        ? '${addr.substring(0, 10)}…${addr.substring(addr.length - 8)}'
        : addr;
    // Review's "From · Available" subtitle reflects the SELECTED
    // source wallet's pool. See `_selectedSpendableSats` for the
    // hot-vs-cold routing — bypassing this here showed the spending
    // wallet's Spark balance under a cold-wallet send.
    final btcSats = _selectedSpendableSats(ref);
    final amountSats = ref.watch(sendTxProvider).amount;

    // Hero amount in bitcoin, with the fiat equivalent underneath.
    final heroPrimary = '${amountSats.toFormattedString(btcFormat)} $btcFormat';
    final heroSecondary = ref.watch(conversionToFiatProvider(amountSats));

    // Hardware / watch-only Bitcoin sends: compute the real on-chain fee
    // from a draft PSBT (sat/vB × vbytes via BDK).
    //
    // Spark hot wallet → on-chain Bitcoin: pull the live SendOnchainFeeQuote
    // from the Breez SDK so the Review reflects the actual sats fee for
    // the chosen confirmation speed (Fast/Medium/Slow), not a hardcode.
    //
    // Everything else (Spark→Spark, Spark→Lightning, cross-chain) still
    // falls through to `_estimateFees()` for now.
    //
    // Source the wallet from `_selectedWalletId` FIRST — `activeWallet`
    // is pinned to the spending hot wallet whenever Home keeps the
    // carousel parked there, so a hardware-wallet send opened from a
    // wallet-detail surface previously fell through to the Spark
    // fee-row path. The Spark SDK then probed against the HW address
    // and returned `invalidInput` → "Invalid input to calculate the
    // fee" on the Review's Network fee row. Resolving the wallet via
    // `_selectedWalletId` first routes the row through `_hwNetworkFeeRow`
    // (BDK draft PSBT) for hardware sends as intended.
    final activeWalletForFee = _resolveSourceWallet();
    final isSoftwareWallet = activeWalletForFee?.isBitcoinSoftware == true;
    final softwareRequest =
        isSoftwareWallet ? _softwareSendRequest(activeWalletForFee!) : null;
    final softwarePreview = softwareRequest == null
        ? null
        : ref.watch(bitcoinSoftwareSendPreviewProvider(softwareRequest));
    if (_isDraining &&
        softwarePreview?.hasValue == true &&
        softwarePreview?.isLoading == false &&
        !softwarePreview!.hasError &&
        !isProcessing &&
        !_paymentAuthInFlight) {
      try {
        final netAmount = BitcoinSoftwareSend.drainRecipientSats(
            softwarePreview.requireValue);
        if (netAmount != amountSats) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                isProcessing ||
                _paymentAuthInFlight ||
                !_isDraining ||
                _resolveSourceWallet()?.id != softwareRequest!.walletId ||
                _softwareSendRequest(activeWalletForFee!) != softwareRequest) {
              return;
            }
            ref.read(sendTxProvider.notifier).updateAmount(netAmount);
            updateControllerText(netAmount);
          });
        }
      } catch (_) {
        // Invalid previews remain visible as an error and cannot be sent.
      }
    }
    final isHwWallet = activeWalletForFee != null && activeWalletForFee.usesBdk;
    // Hardware on-chain BTC fee row is only meaningful when the PSBT
    // we'd build targets the address in the textfield. For
    // cross-chain hardware sends the actual deposit address only
    // resolves at execute time inside the cross-chain
    // handler, so we let the cross-chain "You receive" row from
    // `_estimateFees()` cover Review here and surface the on-chain
    // fee on the Sign step instead.
    final isHwBtcSend = _hasSource && isHwWallet && _selectedDestAsset == null;
    // Advanced (network speed + coin selection) card. Every BDK source
    // gets it — a hot Bitcoin wallet as much as a hardware or
    // watch-only one — and for any BTC source send, so the broadcast
    // fee of a cross-chain deposit leg is dialable too. Hardware keeps
    // its own copy of these controls on the Sign step, where the exact
    // fee of the built PSBT is the one the device signs.
    final showBitcoinAdvanced = _hasSource && isHwWallet;
    // Spark hot wallet → Bitcoin destination (no cross-chain). The
    // exact fee shape (on-chain vs Lightning routing vs Spark internal)
    // depends on the parsed input type, so resolve it asynchronously
    // and re-render when ready. Empty address / unknown type → no fee
    // block at all (matches the prior `isNotEmpty` short-circuit).
    final addrText = addressController.text;
    final isSparkBtcDestSend = _hasSource &&
        activeWalletForFee != null &&
        !isHwWallet &&
        _selectedDestAsset == null &&
        addrText.isNotEmpty &&
        amountSats > 0;
    final sparkInputTypeAsync = isSparkBtcDestSend
        ? ref.watch(identifyInputTypeProvider(addrText))
        : null;
    final sparkResolvedType =
        sparkInputTypeAsync?.maybeWhen(data: (t) => t, orElse: () => null);
    final isSparkOnchainSend = isSparkBtcDestSend &&
        (sparkResolvedType == AnalyzedPaymentType.bitcoin ||
            sparkResolvedType == AnalyzedPaymentType.bip21);
    final isSparkLightningSend = isSparkBtcDestSend &&
        (sparkResolvedType == AnalyzedPaymentType.lightning ||
            sparkResolvedType == AnalyzedPaymentType.lnurl);
    final isSparkInternalSend =
        isSparkBtcDestSend && sparkResolvedType == AnalyzedPaymentType.spark;
    // While the input type is still resolving (or unknown) we render
    // a placeholder loading row so the user sees the surface — but we
    // still hide it entirely for empty addresses.
    final isSparkBtcDestLoading =
        isSparkBtcDestSend && sparkResolvedType == null;
    final hasSparkBtcDestRow = isSparkOnchainSend ||
        isSparkLightningSend ||
        isSparkInternalSend ||
        isSparkBtcDestLoading;
    // A cross-chain send gets the quote card instead of a fee row.
    final isCrossChainSend = _selectedDestAsset != null;
    final fees = (isHwBtcSend || hasSparkBtcDestRow || isCrossChainSend)
        ? null
        : _estimateFees();
    final knownFeeSats = _reviewKnownFeeSats(
      isSoftwareWallet: isSoftwareWallet,
      softwarePreview: softwarePreview,
      isSparkOnchainSend: isSparkOnchainSend,
      isSparkInternalSend: isSparkInternalSend,
      isSparkLightningSend: isSparkLightningSend,
      address: addrText,
      amountSats: amountSats,
    );
    _resolveSparkDrainAmount(
      address: addrText,
      amountSats: amountSats,
      lightning: isSparkLightningSend,
      enabled:
          isSparkOnchainSend || isSparkInternalSend || isSparkLightningSend,
    );
    // Icons sized at 24.sp: the bare SVG sits in a 28.sp slot on the
    // compact From / To rows, so anything larger crowds the row and
    // pushes the card back to the height this pass took out of it.
    final assetIcon = _selectedDestAsset != null
        ? _selectedDestAsset!.iconWidget(size: 24.sp)
        : SvgPicture.asset('lib/assets/bitcoin-icon.svg',
            width: 24.sp, height: 24.sp);
    final assetIconBg = (_selectedDestAsset?.color ?? const Color(0xFFF7931A))
        .withValues(alpha: 0.18);
    const sourceLabel = 'Bitcoin';
    final sourceBalance = '${btcSats.toFormattedString(btcFormat)} $btcFormat';
    // Source icon: prefer the wallet's brand SVG (Ledger /
    // Jade / Passport / Kute-dog spending) over the generic
    // Bitcoin glyph so the Review "From" row reads as the actual
    // wallet identity.
    final sourceWalletForIcon = _selectedWalletId != null
        ? ref.read(settingsProvider).wallets.firstWhere(
              (w) => w.id == _selectedWalletId,
              orElse: () =>
                  ref.read(settingsProvider).activeWallet ??
                  ref.read(settingsProvider).wallets.first,
            )
        : ref.read(settingsProvider).activeWallet;
    final visual = sourceWalletForIcon != null
        ? WalletVisual.fromWallet(
            walletType: sourceWalletForIcon.walletType,
            isHardware: sourceWalletForIcon.isHardware,
            isWatchOnly: sourceWalletForIcon.isWatchOnly,
            isSigner: sourceWalletForIcon.isSigner,
            isDark: context.isDark,
          )
        : null;
    final sourceIcon = visual?.svgAsset ?? 'lib/assets/bitcoin-icon.svg';
    final sourceIconBg =
        (visual?.color ?? const Color(0xFFF7931A)).withValues(alpha: 0.18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero amount — chromeless, matches the home / portfolio /
        // wallet-detail balance card hierarchy. No "Sending" caption:
        // the step is titled Review and the big figure is obviously
        // the amount, so the label was a wasted line.
        Padding(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: _hasSource
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          BtcAmountText(
                            text: '${amountSats.toFormattedString(btcFormat)}',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 56.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.4,
                              height: 1.0,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          Text(
                            ' $btcFormat',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 56.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.4,
                              height: 1.0,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      )
                    : Text(
                        heroPrimary,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 56.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.4,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              if (heroSecondary.isNotEmpty) ...[
                SizedBox(height: 6.h),
                Text(
                  heroSecondary,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 20.h),
        // ─── From → To card ──────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: c.borderSubtle, width: 1.0),
          ),
          child: Column(
            children: [
              _reviewSummaryRow(
                c: c,
                label: context.l10n.from,
                title: sourceLabel,
                subtitle:
                    context.l10n.sendAvailableBalanceSubtitle(sourceBalance),
                iconChild:
                    SvgPicture.asset(sourceIcon, width: 24.sp, height: 24.sp),
                iconBg: sourceIconBg,
              ),
              Divider(
                  height: 1, thickness: 1, color: c.borderSubtle, indent: 14.w),
              // Tap to reveal the full destination string with a copy
              // action; the shortened form alone gives a hardware user
              // nothing to compare against the device screen.
              InkWell(
                onTap: addr.isEmpty
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        setState(() => _reviewToExpanded = !_reviewToExpanded);
                      },
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(18.r)),
                child: _reviewSummaryRow(
                  c: c,
                  label: context.l10n.to,
                  title: shortAddr.isNotEmpty ? shortAddr : '…',
                  subtitle: _selectedDestAsset != null
                      ? '${_selectedDestAsset!.name} · ${_selectedDestNetwork?.name ?? ''}'
                      : context.l10n.bitcoinNetwork,
                  iconChild: assetIcon,
                  iconBg: assetIconBg,
                  trailing: addr.isEmpty
                      ? null
                      : Icon(
                          _reviewToExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18.sp,
                          color: c.textTertiary),
                ),
              ),
              if (_reviewToExpanded && addr.isNotEmpty)
                _reviewFullAddressBlock(c, addr),
            ],
          ),
        ),
        if (isSoftwareWallet ||
            hasSparkBtcDestRow ||
            fees != null ||
            isCrossChainSend ||
            isHwBtcSend) ...[
          SizedBox(height: 14.h),
        ],
        // ─── Fee + ETA breakdown ────────────────────────────────
        //
        // Hardware / watch-only sends show one "Estimated network fee"
        // row here, sized from the selected sat/vB rate, so Review is
        // never fee-less. The speed / UTXO controls stay on the Sign
        // step (Bug 44), where the exact fee of the built PSBT is the
        // one the user signs on-device.
        if (isSoftwareWallet ||
            hasSparkBtcDestRow ||
            fees != null ||
            isCrossChainSend ||
            isHwBtcSend)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(color: c.borderSubtle, width: 1.0),
            ),
            child: Column(
              children: [
                if (isSoftwareWallet) ...[
                  _softwareNetworkFeeRow(c, softwarePreview!),
                ] else if (isSparkOnchainSend) ...[
                  _sparkOnchainFeeRow(c, addressController.text, amountSats),
                  SizedBox(height: 10.h),
                  _reviewKVRow(
                      c: c,
                      label: context.l10n.sendEstimatedTime,
                      value: _sparkEtaLabel(_sparkOnchainSpeed),
                      muted: true),
                ] else if (isSparkLightningSend) ...[
                  _lightningFeeRow(c, addressController.text, amountSats),
                  SizedBox(height: 10.h),
                  _reviewKVRow(
                      c: c,
                      label: context.l10n.sendEstimatedTime,
                      value: context.l10n.instant,
                      muted: true),
                ] else if (isSparkInternalSend) ...[
                  _sparkInternalFeeRow(c, addressController.text, amountSats),
                  SizedBox(height: 10.h),
                  _reviewKVRow(
                      c: c,
                      label: context.l10n.sendEstimatedTime,
                      value: context.l10n.instant,
                      muted: true),
                ] else if (isHwBtcSend) ...[
                  _hwEstimatedFeeRow(c),
                ] else if (isSparkBtcDestLoading) ...[
                  Row(
                    children: [
                      Text(context.l10n.networkFee2,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                          )),
                      const Spacer(),
                      KuteSkeleton(
                        child: SkeletonBar(70.w, 12.h),
                      ),
                    ],
                  ),
                ] else if (isCrossChainSend) ...[
                  ..._crossChainQuoteRows(c),
                ] else if (fees != null) ...[
                  if (fees.error != null)
                    SendReviewErrorRow(label: fees.label, error: fees.error!)
                  else
                    _reviewKVRow(
                        c: c,
                        label: fees.label,
                        value: fees.value,
                        muted: true),
                  if (fees.eta != null) ...[
                    SizedBox(height: 10.h),
                    _reviewKVRow(
                        c: c,
                        label: context.l10n.sendEstimatedTime,
                        value: fees.eta!),
                  ],
                  if (fees.note != null) ...[
                    SizedBox(height: 10.h),
                    SendReviewNote(text: fees.note!),
                  ],
                ],
                // The Bitcoin speed + coin controls used to live here as
                // a third control stacked under the fee rows. They are
                // their own card below the fee block now, so this one
                // stays what it says it is: what this send costs.
                if (() {
                  // Network speed picker. Always show for Spark hot
                  // wallet BTC sends as long as the destination isn't
                  // Lightning (LN routing fees aren't a per-block speed
                  // dial) or another chain (a cross-chain send funds its
                  // Orchestra quote with a Spark transfer, which has no
                  // on-chain speed). Note: on the current
                  // pinned Breez Spark SDK, on-chain user_fee_sat tends
                  // to round to the same total across fast/medium/slow
                  // because the withdraw-service flat fee dominates the
                  // L1 broadcast delta — but the picker is left visible
                  // because we've seen scenarios where they DO diverge
                  // and we'd rather show the user the choice than make
                  // it for them silently.
                  if (!_hasSource) return false;
                  if (_selectedDestAsset != null) return false;
                  if (activeWalletForFee == null) return false;
                  if (isHwWallet) return false;
                  final isLnDest =
                      _selectedDestNetwork?.network.toLowerCase() ==
                          'lightning';
                  if (isLnDest) return false;
                  // LN sends settled via the Breez SDK don't expose a
                  // per-block speed dial — routing fees are derived from
                  // pathfinding, not from a fast/medium/slow tier. Hide
                  // the row whenever the destination IS a Lightning rail,
                  // whether that's a scanned/pasted Bolt11 / LNURL / LN
                  // address (PaymentType.Lightning), or just an address
                  // we recognized as LN-shaped. Bitcoin on-chain keeps
                  // the speed knob.
                  final sendType = ref.read(sendTxProvider).type;
                  if (sendType == PaymentType.Lightning) return false;
                  final detected = _detectAddressType(addressController.text);
                  if (detected.label == 'Lightning invoice' ||
                      detected.label == 'Lightning address' ||
                      detected.label == 'LNURL') {
                    return false;
                  }
                  // Same-rail Spark address sends carry no speed knob.
                  if (isSparkInternalSend) return false;
                  return true;
                }()) ...[
                  SizedBox(height: 12.h),
                  Divider(height: 1, color: c.borderSubtle),
                  SizedBox(height: 8.h),
                  _reviewTapRow(
                    c: c,
                    icon: Icons.speed_rounded,
                    label: context.l10n.sendNetworkSpeed,
                    value: _sparkSpeedLabel(_sparkOnchainSpeed),
                    onTap: () => isSparkOnchainSend
                        ? _openSparkSpeedPicker(
                            context, addressController.text, amountSats)
                        : _openSimpleSparkSpeedPicker(context),
                  ),
                ],
                // Amount plus fee, only once the fee is actually known.
                if (knownFeeSats != null && amountSats > 0)
                  _reviewTotalRow(c, amountSats, knownFeeSats, btcFormat,
                      feeInAmount: isSparkLightningSend &&
                          _lightningDrainPrepared(addrText, amountSats)),
              ],
            ),
          ),
        if (showBitcoinAdvanced) ...[
          SizedBox(height: 14.h),
          _reviewAdvancedCard(c),
        ],
        // A cross-chain send has no separate route card: the To row
        // already names the coin and network, and the quote card ends
        // on the Route details line, where the settling provider is
        // named instead of a badge on the page.
        //
        // The Nerd data row that used to sit here (address class) is
        // gone: Review is the last screen before money moves and the
        // address class is not something a payer acts on. The Sign
        // step's error card keeps its Nerd data, because that is how
        // support reads a real failure.
      ],
    );
  }

  /// Full destination string under the Review "To" row, wrapped so
  /// every character is readable, with a Copy action.
  Widget _reviewFullAddressBlock(AppColorsExtension c, String addr) {
    return SendReviewFullAddress(
      address: addr,
      onCopied: () =>
          TrackingService.track('pay_review_address_copied', params: {
        'address_type': _trackingAddressType(_detectAddressType(addr)),
      }),
    );
  }

  Widget _reviewSummaryRow({
    required AppColorsExtension c,
    required String label,
    required String title,
    required String subtitle,
    required Widget iconChild,
    required Color iconBg,
    Widget? trailing,
  }) {
    // `iconBg` stays on the signature so old callers compile; the
    // tinted disc it fed is gone (the brand SVG is the identity).
    return SendReviewSummaryRow(
      label: label,
      title: title,
      subtitle: subtitle,
      icon: iconChild,
      trailing: trailing,
    );
  }

  /// Fee in sats for a prepared Spark payment: the selected speed's
  /// total for an on-chain withdrawal, the transfer fee for a Spark
  /// address / invoice. Shared by the fee rows and the Total row so
  /// both show the same number.
  int _sparkPreparedFeeSats(PrepareSendPaymentResponse resp) =>
      sparkPreparedFeeSats(resp, _sparkOnchainSpeed);

  /// 100% from the spending wallet, resolved on Review.
  ///
  /// The 100% chip only arms the drain and shows the balance as a
  /// placeholder. Here the destination is known, and the preparation
  /// Review watches is the SDK's own send-all (the whole, freshly synced
  /// balance with fees included). That preparation is the ONE writer of
  /// the drained amount: the figure it resolves to (see
  /// [_sparkDrainResolvedSats]) replaces the placeholder, and the send
  /// reads the very same preparation, so what Review shows is what the
  /// SDK sends. Keyed without the amount, so writing the amount does
  /// not re-quote; changing the speed re-resolves from the same quote.
  void _resolveSparkDrainAmount({
    required String address,
    required int amountSats,
    required bool lightning,
    required bool enabled,
  }) {
    if (!enabled ||
        !_isDraining ||
        isProcessing ||
        _paymentAuthInFlight ||
        isInvoice) {
      return;
    }
    Object? prepared;
    try {
      prepared = lightning
          ? ref
              .watch(prepareLightningPaymentProvider(
                  _lightningPrepareKey(address, amountSats)))
              .valueOrNull
              ?.prepareResponse
          : ref
              .watch(prepareGenericPaymentProvider(
                  _sparkPrepareKey(address, amountSats)))
              .valueOrNull;
    } catch (_) {
      return;
    }
    final resolved =
        prepared == null ? null : _sparkDrainResolvedSats(prepared);
    if (resolved == null || resolved <= 0 || resolved == amountSats) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          isProcessing ||
          _paymentAuthInFlight ||
          isInvoice ||
          !_isDraining ||
          addressController.text != address) {
        return;
      }
      ref.read(sendTxProvider.notifier).updateAmount(resolved);
      updateControllerText(resolved);
    });
  }

  /// True when Review's Lightning preparation is a fees-included drain,
  /// so its amount already carries the routing fee.
  bool _lightningDrainPrepared(String address, int amountSats) {
    if (!_isDraining) return false;
    try {
      final raw = ref
          .watch(prepareLightningPaymentProvider(
              _lightningPrepareKey(address, amountSats)))
          .valueOrNull
          ?.prepareResponse;
      if (raw is PrepareSendPaymentResponse) {
        return raw.feePolicy == FeePolicy.feesIncluded;
      }
      if (raw is PrepareLnurlPayResponse) {
        return raw.feePolicy == FeePolicy.feesIncluded;
      }
    } catch (_) {}
    return false;
  }

  /// Fee in sats for a prepared Lightning payment (routing plus any
  /// Spark transfer fee), same source the executor charges from.
  int _lightningPreparedFeeSats(PrepareLightningPaymentResponse resp) {
    final raw = resp.prepareResponse;
    if (raw is PrepareSendPaymentResponse) {
      final method = raw.paymentMethod;
      if (method is SendPaymentMethod_Bolt11Invoice) {
        var feeSats = method.lightningFeeSats.toInt();
        if (method.sparkTransferFeeSats != null) {
          feeSats += method.sparkTransferFeeSats!.toInt();
        }
        return feeSats;
      }
      return 0;
    }
    if (raw is PrepareLnurlPayResponse) return raw.feeSats.toInt();
    return resp.networkFee;
  }

  /// The fee the Review fee rows currently show, in sats, or null while
  /// it is loading, failed, or the route has no sats fee (cross-chain,
  /// hardware estimate). The Total row renders only from a known fee.
  int? _reviewKnownFeeSats({
    required bool isSoftwareWallet,
    required AsyncValue<onchain.Psbt>? softwarePreview,
    required bool isSparkOnchainSend,
    required bool isSparkInternalSend,
    required bool isSparkLightningSend,
    required String address,
    required int amountSats,
  }) {
    try {
      if (isSoftwareWallet) {
        final psbt = softwarePreview?.valueOrNull;
        if (psbt == null ||
            softwarePreview!.isLoading ||
            softwarePreview.hasError) {
          return null;
        }
        return psbt.fee();
      }
      if (isSparkOnchainSend || isSparkInternalSend) {
        final resp = ref
            .watch(prepareGenericPaymentProvider(
                _sparkPrepareKey(address, amountSats)))
            .valueOrNull;
        return resp == null ? null : _sparkPreparedFeeSats(resp);
      }
      if (isSparkLightningSend) {
        final resp = ref
            .watch(prepareLightningPaymentProvider(
                _lightningPrepareKey(address, amountSats)))
            .valueOrNull;
        return resp == null ? null : _lightningPreparedFeeSats(resp);
      }
    } catch (_) {
      // A fee we cannot read is a fee we do not total.
    }
    return null;
  }

  /// "Total" at the bottom of the fee card: amount plus fee, in the
  /// unit the user typed in with the other unit beside it. This is
  /// what leaves the wallet, which matters most in MAX mode where the
  /// fee comes out of the principal.
  Widget _reviewTotalRow(
      AppColorsExtension c, int amountSats, int feeSats, String btcFormat,
      {bool feeInAmount = false}) {
    // A 100% Lightning send shows the gross amount the SDK debits; its
    // routing fee comes out of that amount, not on top of it.
    final total = feeInAmount ? amountSats : amountSats + feeSats;
    final unit = ref.watch(inputCurrencyProvider);
    final isBtcUnit = unit == 'Sats' || unit == 'BTC';
    final btcText = '${total.toFormattedString(btcFormat)} $btcFormat';
    final String value;
    if (isBtcUnit) {
      final fiat = ref.watch(conversionToFiatProvider(total));
      value = fiat.isNotEmpty ? '$btcText · $fiat' : btcText;
    } else {
      final fiat = ref
          .watch(satsToTargetCurrencyProvider((sats: total, currency: unit)));
      value = '${_getCurrencyPrefix(unit)}$fiat · $btcText';
    }
    return Column(
      children: [
        SizedBox(height: 12.h),
        Divider(height: 1, color: c.borderSubtle),
        SizedBox(height: 12.h),
        _reviewKVRow(c: c, label: context.l10n.total, value: value),
      ],
    );
  }

  Widget _reviewKVRow({
    required AppColorsExtension c,
    required String label,
    required String value,
    bool muted = false,
  }) {
    return SendReviewKVRow(label: label, value: value, muted: muted);
  }

  /// Hardware / watch-only Bitcoin send — render the actual on-chain
  /// fee from a draft PSBT (rebuilt by `feeProvider` whenever the user
  /// changes sat/vB or UTXO selection). Shows sats + fiat. Loading
  /// state while BDK is computing; the actual error string on failure
  /// (insufficient funds is the common one) so the user knows why.

  /// Convert a raw BDK / draft-PSBT error into something the user can
  /// act on. Insufficient-funds is the common one — surface needed
  /// vs available so they can drop the amount or pick more UTXOs.
  /// A fee estimate that could not be fetched: the typed service error,
  /// or a raw transport failure (TLS handshake, socket, timeout, client)
  /// from any other network path. Never shown as an exception string.
  bool _isFeeUnavailable(Object err) {
    if (err is BitcoinFeeUnavailableException ||
        err is HandshakeException ||
        err is SocketException ||
        err is TimeoutException ||
        err is ClientException) {
      return true;
    }
    final lower = err.toString().toLowerCase();
    return lower.contains('handshakeexception') ||
        lower.contains('socketexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('clientexception') ||
        lower.contains('feeunavailable');
  }

  String _formatFeeError(Object err) {
    if (_isFeeUnavailable(err)) return context.l10n.feeEstimateUnavailable;
    // Same reason as `_humanizeSignError`: a native refusal carries a code
    // whose text is generic, so the fee row would otherwise show one
    // sentence about the user's input for every possible cause.
    if (err is OnchainException) return _onchainCodeCopy(err);
    if (isSparkInsufficientFunds(err)) return context.l10n.insufficientBalance;
    final s = err.toString();
    final lower = s.toLowerCase();
    // Spark prepare-payment "InsufficientFunds" with explicit needed /
    // available sats — pull the numbers out for an actionable message.
    final m = RegExp(
            r'InsufficientFunds[^)]*?needed[^0-9]*(\d+)[^0-9]*available[^0-9]*(\d+)',
            caseSensitive: false)
        .firstMatch(s);
    if (m != null) {
      return context.l10n.sendNeedHaveBalance(m.group(1)!, m.group(2)!);
    }
    // BDK + Spark dust / minimum failures — surface as a single
    // user-friendly line instead of the raw exception. Mirrors
    // `_humanizeSignError` for the Sign step so the same wording
    // appears whether the fee row trips on Review or the PSBT trips
    // on Sign.
    if (lower.contains('amount is too small') ||
        lower.contains('below dust') ||
        lower.contains('below minimum') ||
        lower.contains('below the minimum') ||
        lower.contains('minimal non dust') ||
        lower.contains('below the minimal')) {
      return context.l10n.sendAmountTooSmallForOnChainSend;
    }
    // Fee-policy conflicts (e.g. "FeesIncluded is not supported for
    // invoices with a fixed amount") are app bugs, not amount
    // problems — surface the real message instead of mislabeling it
    // as a network minimum and sending the user to change the amount.
    if (lower.contains('feesincluded')) {
      return userErrorCopy(context, err,
          fallback: context.l10n.sendCouldNotPrepare);
    }
    // Spark SDK invalidInput — typically the BTC destination address
    // hasn't fully parsed yet OR the amount is below the network
    // floor. Either way, "Invalid input" leaks the raw SDK shape;
    // the user just needs to know they should adjust the amount or
    // wait for the address to validate.
    if (lower.contains('invalidinput') || lower.contains('invalid input')) {
      return context.l10n.sendAmountBelowNetworkMinimum;
    }
    if (lower.contains('insufficient')) {
      return context.l10n.insufficientBalance;
    }
    if (lower.contains('address') && lower.contains('invalid')) {
      return context.l10n.sendDestinationAddressIsInvalid;
    }
    return userErrorCopy(context, err,
        fallback: context.l10n.sendCouldNotEstimateFee);
  }

  /// Map `sendBlocksProvider` (1 / 2 / 3) to a human ETA string for
  /// the Review fee block. Mirrors the speed picker labels in
  /// `bitcoin_advanced_settings_sheet.dart`.

  /// Spark hot wallet → on-chain Bitcoin: render the live SDK fee for
  /// the user-selected speed. The Breez SDK returns userFeeSat per
  /// speed in `SendOnchainFeeQuote`; we just pick the one matching
  /// `_sparkOnchainSpeed`. Loading/error states match the hardware row.
  /// Speed and coin control for a Bitcoin send, in the card vocabulary of
  /// the fee block above it: two full rows with one hairline between
  /// them, each naming what it is set to right now instead of hiding
  /// behind the word Advanced.
  ///
  /// Both rows write the providers the builders read
  /// (`sendBlocksProvider`, `customFeeRateProvider`,
  /// `selectedUtxosProvider`), so a change here re-draws the review and
  /// rebuilds the draft PSBT through the listeners already registered in
  /// `build` — the reviewed amount, fee, inputs, outputs, network and
  /// wallet stay bound to whatever is signed.
  ///
  /// Shown for every BDK source, hot or hardware. A hardware send keeps
  /// its own copy of these controls on the Sign step, where the exact
  /// fee of the built PSBT is the one the device signs.
  Widget _reviewAdvancedCard(AppColorsExtension c) {
    final customRate = ref.watch(customFeeRateProvider);
    final blocks = ref.watch(sendBlocksProvider);
    final speed = customRate != null
        ? '${customRate.toStringAsFixed(customRate == customRate.roundToDouble() ? 0 : 1)} ${context.l10n.satVb}'
        : switch (blocks) {
            1 => context.l10n.fast,
            3 => context.l10n.slow,
            _ => context.l10n.standard,
          };
    return AbsorbPointer(
      absorbing: isProcessing || _paymentAuthInFlight,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: c.borderSubtle, width: 1.0),
        ),
        child: Column(
          children: [
            SheetDetailRow(
              label: context.l10n.sendNetworkSpeed,
              value: speed,
              trailingIcon: Icons.chevron_right_rounded,
              onTap: () => showBitcoinAdvancedSettings(context, ref),
            ),
            // The coin row draws nothing when the wallet has no coin
            // list of its own, so the hairline is tied to it — a rule
            // with nothing under it is worse than no rule.
            if (ref.watch(bitcoinLabelsWalletIdProvider) != null) ...[
              Divider(height: 1, color: c.borderSubtle),
              const CoinSelectionTile(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _softwareNetworkFeeRow(
      AppColorsExtension c, AsyncValue<onchain.Psbt> preview) {
    String value = '—';
    if (preview.hasError && _isFeeUnavailable(preview.error!)) {
      // No fee rate, so no preview and no Continue. One sentence plus a
      // Retry; the custom sat/vB rate in Network speed is the manual way
      // out and the provider retries by itself as well.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.networkFee2,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              )),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  context.l10n.feeEstimateUnavailable,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 4.h),
                InkWell(
                  onTap: () => ref.invalidate(bitcoinFeeRatePerBlockProvider),
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 14.sp, color: c.textPrimary),
                        SizedBox(width: 4.w),
                        Text(
                          context.l10n.retry,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (preview.hasError) {
      value = _formatFeeError(preview.error!);
    } else if (preview.hasValue) {
      try {
        final fee = preview.requireValue.fee();
        value = context.l10n.feeAmountSats(fee.toString());
      } catch (_) {
        value = context.l10n.sendFeeEstimateFailed;
      }
    } else {
      // The draft is waiting, usually on a scan that holds the wallet's
      // native slot. Size the fee from the last synced coins meanwhile,
      // labelled as an estimate; Continue still waits for the real PSBT.
      final estimate = _draftFeeEstimateSats();
      if (estimate != null) {
        return _reviewKVRow(
            c: c,
            label: context.l10n.feeUiEstimatedFee,
            value: context.l10n.feeAmountSats(estimate.toString()),
            muted: true);
      }
    }
    return _reviewKVRow(
        c: c, label: context.l10n.networkFee2, value: value, muted: true);
  }

  /// Hardware / watch-only Review: the network fee the selected sat/vB
  /// rate implies for this amount, sized from the wallet's last synced
  /// coins and labelled as an estimate. The exact fee of the built
  /// PSBT still shows on the Sign step before anything is signed.
  Widget _hwEstimatedFeeRow(AppColorsExtension c) {
    final estimate = _draftFeeEstimateSats();
    if (estimate == null) {
      final rateLoading = ref.watch(getCustomFeeRateProvider).isLoading;
      if (!rateLoading) {
        return _reviewKVRow(
            c: c,
            label: context.l10n.sendEstimatedNetworkFee,
            value: '—',
            muted: true);
      }
      return Row(
        children: [
          Text(context.l10n.sendEstimatedNetworkFee,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
              )),
          const Spacer(),
          KuteSkeleton(child: SkeletonBar(70.w, 12.h)),
        ],
      );
    }
    final fiat = ref.watch(conversionToFiatProvider(estimate));
    final value = fiat.isNotEmpty
        ? context.l10n.sendFeeSatsWithFiat(estimate.toString(), fiat)
        : context.l10n.feeAmountSats(estimate.toString());
    return _reviewKVRow(
        c: c,
        label: context.l10n.sendEstimatedNetworkFee,
        value: value,
        muted: true);
  }

  /// Fee for the typed amount sized from the source wallet's last synced
  /// coins at the selected rate. Null until both are known. Display only.
  int? _draftFeeEstimateSats() {
    final wallet = _resolveSourceWallet();
    if (wallet == null || !wallet.usesBdk) return null;
    final feeRate = ref.watch(getCustomFeeRateProvider).valueOrNull;
    final model =
        ref.watch(bitcoinModelForWalletProvider(wallet.id)).valueOrNull;
    if (feeRate == null || model == null) return null;
    return estimateDraftFeeSats(
      utxos: model.listUnspent(),
      amountSats: ref.watch(sendTxProvider).amount,
      toAddress: stripBitcoinAddress(addressController.text),
      feeRateSatVb: feeRate,
      drain: _isDraining,
      selectedUtxos: ref.watch(selectedUtxosProvider),
      scriptType: wallet.scriptType,
    );
  }

  Widget _sparkOnchainFeeRow(
      AppColorsExtension c, String address, int amountSats) {
    final params = _sparkPrepareKey(address, amountSats);
    final prepareAsync = ref.watch(prepareGenericPaymentProvider(params));
    return prepareAsync.when(
      data: (resp) {
        final method = resp.paymentMethod;
        final totalSats = _sparkPreparedFeeSats(resp);
        if (method is! SendPaymentMethod_BitcoinAddress) {
          // Spark→Spark or other — fall back to the method's own fee.
          return _reviewKVRow(
              c: c,
              label: context.l10n.networkFee2,
              value: context.l10n.feeAmountSats(totalSats.toString()),
              muted: true);
        }
        final fiat = ref.watch(conversionToFiatProvider(totalSats));
        final value = fiat.isNotEmpty
            ? context.l10n.sendFeeSatsWithFiat(totalSats.toString(), fiat)
            : context.l10n.feeAmountSats(totalSats.toString());
        return _reviewKVRow(
            c: c, label: context.l10n.networkFee2, value: value, muted: true);
      },
      loading: () => Row(
        children: [
          Text(context.l10n.networkFee2,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          const Spacer(),
          SizedBox(
            width: 14.sp,
            height: 14.sp,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              valueColor: AlwaysStoppedAnimation(c.textTertiary),
            ),
          ),
        ],
      ),
      error: (err, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.networkFee2,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              _formatFeeError(err),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sparkEtaLabel(OnchainConfirmationSpeed speed) {
    switch (speed) {
      case OnchainConfirmationSpeed.fast:
        return context.l10n.k10Min;
      case OnchainConfirmationSpeed.medium:
        return context.l10n.k30Min;
      case OnchainConfirmationSpeed.slow:
        return context.l10n.k60Min;
    }
  }

  /// Spark hot wallet → Lightning destination. Pulls the routing fee
  /// from `prepareLightningPaymentProvider` (Bolt11 / LNURL) so the
  /// number matches what Breez will charge at execute time. Shows
  /// "Routing fee · X sats · $0.0Y" when ready, the formatted error on
  /// failure, and "—" while loading.
  Widget _lightningFeeRow(
      AppColorsExtension c, String address, int amountSats) {
    final params = _lightningPrepareKey(address, amountSats);
    final prepareAsync = ref.watch(prepareLightningPaymentProvider(params));
    return prepareAsync.when(
      data: (resp) {
        final feeSats = _lightningPreparedFeeSats(resp);
        final fiat = ref.watch(conversionToFiatProvider(feeSats));
        final value = fiat.isNotEmpty
            ? context.l10n.sendFeeSatsWithFiat(feeSats.toString(), fiat)
            : context.l10n.feeAmountSats(feeSats.toString());
        return _reviewKVRow(
            c: c,
            label: context.l10n.sendRoutingFee,
            value: value,
            muted: true);
      },
      loading: () => Row(
        children: [
          Text(context.l10n.sendRoutingFee,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          const Spacer(),
          Text('—',
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
      error: (err, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.sendRoutingFee,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              _formatFeeError(err),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Spark hot wallet → Spark address (internal transfer). Renders the
  /// service fee from `prepareGenericPaymentProvider` for SparkAddress
  /// / SparkInvoice methods. ETA is "Instant" — handled at the call
  /// site to keep this widget focused on the fee row itself.
  Widget _sparkInternalFeeRow(
      AppColorsExtension c, String address, int amountSats) {
    final params = _sparkPrepareKey(address, amountSats);
    final prepareAsync = ref.watch(prepareGenericPaymentProvider(params));
    return prepareAsync.when(
      data: (resp) {
        final feeSats = _sparkPreparedFeeSats(resp);
        final fiat = ref.watch(conversionToFiatProvider(feeSats));
        final value = fiat.isNotEmpty
            ? context.l10n.sendFeeSatsWithFiat(feeSats.toString(), fiat)
            : context.l10n.feeAmountSats(feeSats.toString());
        return _reviewKVRow(
            c: c, label: context.l10n.serviceFee2, value: value, muted: true);
      },
      loading: () => Row(
        children: [
          Text(context.l10n.serviceFee2,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          const Spacer(),
          Text('—',
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
      error: (err, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.serviceFee2,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
              )),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              _formatFeeError(err),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.error,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sparkSpeedLabel(OnchainConfirmationSpeed speed) {
    switch (speed) {
      case OnchainConfirmationSpeed.fast:
        return context.l10n.fast;
      case OnchainConfirmationSpeed.medium:
        return context.l10n.standard;
      case OnchainConfirmationSpeed.slow:
        return context.l10n.slow;
    }
  }

  /// Spark on-chain speed picker — opens a sheet listing Fast / Standard
  /// / Slow with the live fee for each. Persists choice into
  /// `_sparkOnchainSpeed` so the fee row + send executor pick it up.
  Future<void> _openSparkSpeedPicker(
      BuildContext context, String address, int amountSats) async {
    final params = _sparkPrepareKey(address, amountSats);
    PrepareSendPaymentResponse resp;
    try {
      resp = await ref.read(prepareGenericPaymentProvider(params).future);
    } catch (e) {
      if (mounted) {
        showMessageSnackBar(
            message: _formatFeeError(e), error: true, context: context);
      }
      return;
    }
    final method = resp.paymentMethod;
    if (method is! SendPaymentMethod_BitcoinAddress) return;
    final picked = await _showFeePicker(context, method.feeQuote);
    if (picked != null && mounted) {
      TrackingService.track('pay_fee_tier_selected', params: {
        'fee_tier': picked.toString().split('.').last.toLowerCase(),
        'payment_type': 'bitcoin',
      });
      setState(() => _sparkOnchainSpeed = picked);
    }
  }

  /// Spark hot wallet BTC send whose on-chain fee quote isn't known
  /// yet (the destination type is still resolving) — opens the simple
  /// Fast/Standard/Slow picker (no fee numbers), since we can't yet
  /// query `prepareGenericPaymentProvider` for a SendOnchainFeeQuote.
  /// The execute path picks up `_sparkOnchainSpeed` directly.
  Future<void> _openSimpleSparkSpeedPicker(BuildContext context) async {
    final picked = await _showSimpleSpeedPicker(context, _sparkOnchainSpeed);
    if (picked != null && mounted) {
      setState(() => _sparkOnchainSpeed = picked);
    }
  }

  // ─── Stepper helpers ────────────────────────────────────────

  /// Clears a previously-picked cross-chain destination when it's no
  /// longer compatible with the entered address. Guards the
  /// "picked Liquid / Lightning first, then pasted a 0x… address"
  /// path that the per-asset filter can't catch (the selection was
  /// made before the address existed). Network-family rules mirror
  /// the picker: a positively-identified rail (EVM / Solana / Tron /
  /// XRP) must match `_eligibleNetworksForFamily`; 'unknown' addresses
  /// keep whatever was picked (the provider rejects server-side if wrong).
  void _revalidateDestForAddress(String address) {
    final network = _selectedDestNetwork;
    if (network == null) return;
    final family = _addressRailFamily(address);
    if (family == 'unknown') return;
    final eligible = _eligibleNetworksForFamily[family];
    if (eligible == null) return;
    if (!eligible.contains(network.network.toLowerCase())) {
      setState(() {
        _selectedDestAsset = null;
        _selectedDestNetwork = null;
        _swapQuote = null;
      });
    }
  }

  /// Shared commit path for an address obtained via Scan / Paste /
  /// Gallery. Runs the unified-QR split (so a BIP21-with-lightning is
  /// routed by the paying wallet's capability), writes the address
  /// into the field + provider, re-runs invoice-amount detection, and
  /// drops any now-incompatible cross-chain destination. Returns
  /// silently after surfacing a snackbar when the payload can't be
  /// used by the active wallet (e.g. Lightning-only on a cold wallet).
  ///
  /// `method` is the PostHog `pay_address_entry_method` enum carrier —
  /// `'scanned'` / `'pasted'` / `'contacts'` / `'invoice'`. Defaults
  /// to `'pasted'` since the field-level paste path lands here too.
  void _commitPastedAddress(String raw, {String method = 'pasted'}) {
    // A cross-chain payment URI (`ethereum:0x…@8453`, an ERC-20
    // `…/transfer?address=…`, `solana:`, `tron:` …) becomes its bare
    // recipient here. `bitcoin:`, `spark:`, `lightning:` and bare
    // payloads pass through untouched, so the BIP21 / Lightning / Spark
    // handling below is exactly what it was.
    final trimmed = bareCrossChainRecipient(raw);
    if (trimmed.isEmpty) return;
    final committed = _resolveUnifiedPasteForActiveWallet(trimmed);
    if (committed == null) {
      showMessageSnackBar(
        context: context,
        message: context.l10n.sendPaymentRequestOnlySupportsLightning,
        error: true,
      );
      return;
    }
    addressController.text = committed;
    ref.read(sendTxProvider.notifier).updateAddress(committed);
    _checkAndPopulateInvoiceAmount(committed);
    _revalidateDestForAddress(committed);
    // Max/drain IS per-destination, but what goes stale is the amount,
    // not the intent. This used to clear the drain flag outright, which
    // broke the ordinary order of this wizard: tap 100%, then enter the
    // recipient. The intent was dropped on the way in, so Review asked
    // to send the whole balance AND pay a fee from it, the draft could
    // not be built, and the send was impossible to complete.
    //
    // The flag is kept and the probe is invalidated instead, so the max
    // is re-sized against the new recipient's own fee.
    //
    // The spending account keeps it too. Clearing it here was the Spark
    // half of the same bug: 100% then a bitcoin address left the gross
    // balance on screen with the drain off, so the send asked for every
    // sat plus the exit fee on top and came back as "not enough
    // balance". Review now resolves a Spark drain against whatever
    // recipient is entered (`_resolveSparkDrainAmount`), so the intent
    // survives a new recipient exactly as a BDK drain's does.
    if (_resolveSourceWallet()?.usesBdk == true) {
      _drainProbeKey = null;
    }
    HapticFeedback.selectionClick();
    setState(() {});
    // PostHog `pay_address_entry_method` — fires on user-initiated
    // entry points only (scan return, gallery decode, wallet picker
    // tap). Programmatic re-population (PSBT mirror, post-prepare
    // address echo) doesn't pass through here.
    _addressEntryMethod = method;
    TrackingService.track('pay_address_entry_method', params: {
      'method': method,
      'payment_type': _trackingPaymentType(),
    });
    // PostHog `pay_destination_resolved` — central chokepoint for
    // `_detectAddressType()` classification across all entry paths
    // that flow through `_commitPastedAddress`. The field-level
    // onChanged (which fires per-keystroke) doesn't emit this.
    final detected = _detectAddressType(committed);
    TrackingService.track('pay_destination_resolved', params: {
      'address_type': _trackingAddressType(detected),
      'payment_type': _trackingPaymentType(),
    });
  }

  /// Map `sendTxProvider.type` → the PostHog `payment_type` enum.
  /// Falls back to `'bitcoin'` for unrecognised values.
  String _trackingPaymentType() {
    try {
      final t = ref.read(sendTxProvider).type.toString().toLowerCase();
      if (t.contains('lightning')) return 'lightning';
      if (t.contains('spark')) return 'spark';
      if (t.contains('usdc')) return 'usdc';
      return 'bitcoin';
    } catch (_) {
      return 'bitcoin';
    }
  }

  /// Map a [_DetectedAddressInfo] to the PostHog `address_type` enum.
  String _trackingAddressType(_DetectedAddressInfo d) {
    switch (d.label) {
      case 'Bitcoin on-chain':
        return 'bitcoin_address';
      case 'Lightning invoice':
        return 'ln_invoice';
      case 'Lightning address':
        return 'ln_address';
      case 'LNURL':
        return 'lnurl';
      case 'Spark address':
        return 'spark_address';
      case 'EVM address':
      case 'Solana address':
        return 'cross_chain_address';
      default:
        return 'unknown';
    }
  }

  void _confirmStep(int step, {VoidCallback? then}) {
    // Dismiss the keyboard when advancing a step — the address / amount
    // fields keep focus otherwise, so the keyboard stayed up over the
    // next page (e.g. after tapping Next on the Send-to step).
    FocusManager.instance.primaryFocus?.unfocus();
    _completedSteps.add(step);
    if (then != null) then();
    // Phase 3 send funnel: confirming the Amount step (index 0) is the
    // amount-entered milestone. One-shot via a State flag.
    if (step == 0 && !_amountEnteredTracked) {
      _amountEnteredTracked = true;
      final type = ref.read(sendTxProvider).type;
      TrackingService.sendAmountEntered(network: _networkLabel(type));
    }
    if (_step == step && step < 2) {
      // Address-preset shortcut: when the user landed on Amount
      // with the address already filled by the scanner / contact
      // entry AND the address is a native BTC rail, the Send-to
      // step has nothing to ask. Jump straight to Review. Non-native
      // rails still need Send-to so the user picks a chain.
      int targetPage = step + 1;
      if (step == 0 && _skipSendToStep) {
        targetPage = 2;
        // The Send-to step is hidden for address-preset native BTC rails
        // (scanner / contact entry), so the user never taps Continue on
        // it. Mark it complete anyway — the Review "Send" button gates on
        // `_completedSteps.containsAll({0, 1})`, and without this the
        // button stays disabled forever on the LNURL-via-scanner path.
        _completedSteps.add(1);
      }
      // Phase 3 send funnel: arriving at the Review page (index 2).
      // One-shot via a State flag so swiping back/forward doesn't dupe.
      if (targetPage == 2 && !_reviewShownTracked) {
        _reviewShownTracked = true;
        final type = ref.read(sendTxProvider).type;
        TrackingService.sendReviewShown(network: _networkLabel(type));
      }
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _pageCtrl.jumpToPage(targetPage);
      } else {
        _pageCtrl.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
      // Entering Review for a cross-chain send — flush any pending
      // debounce and force a fresh quote so the user doesn't sit on
      // a perpetual "Calculating…" if they advanced before the
      // debounce timer fired.
      if (step == 1 && _selectedDestAsset != null) {
        _rateDebounce?.cancel();
        _fetchRate();
      }
      // Send-to → Review transition: if the user tapped MAX before
      // we knew the destination address, the value we stored was the
      // raw balance (no fee deduction). Now that the address is set,
      // recompute the real sendable amount so Review/Sign show what
      // will actually hit the recipient (balance − network fee at the
      // currently-selected fee rate). Without this, on small balances
      // the displayed MAX exceeds the drainable amount and broadcast
      // fails as "insufficient balance" deeper in the flow.
      //
      // Hot Spark BTC: nothing to probe; Review resolves the drain
      // from the SDK's own send-all preparation.
      // BDK (hot, hardware, watch-only): build a probe drain PSBT and
      // read what its single output pays.
      if (step == 1 &&
          _isDraining &&
          _hasSource &&
          _selectedDestAsset == null) {
        final address = addressController.text;
        if (address.isNotEmpty) {
          // ignore: unawaited_futures
          _recomputeMaxForAddress(address);
        }
      }
    } else {
      setState(() {});
    }
  }

  /// Re-asks the SDK for the actual max sendable to [address] and
  /// updates the on-screen amount. Used after the Send-to step when
  /// MAX was tapped earlier without an address in scope. Branches by
  /// wallet kind: hot Spark wallets use the Breez SDK probe; hardware /
  /// watch-only wallets construct a BDK drain PSBT to read the real
  /// fee and derive `balance − fee` as the sendable principal.
  Future<void> _recomputeMaxForAddress(String address) async {
    // Resolve the actual source wallet from `_selectedWalletId` first;
    // `settings.activeWallet` is pinned to the spending wallet even
    // when the user is sending from a hardware wallet (the wallet-
    // detail screen sets `bdkScopeWalletIdProvider`, not the active
    // id). Falling back to `activeWallet` only when no source is
    // explicitly selected.
    final settings = ref.read(settingsProvider);
    final WalletConfig? sourceWallet = _selectedWalletId != null
        ? settings.wallets.firstWhere(
            (w) => w.id == _selectedWalletId,
            orElse: () => settings.activeWallet ?? settings.wallets.first,
          )
        : settings.activeWallet;
    // Every BDK wallet runs the probe, not just the cold ones. A hot
    // Bitcoin wallet used to return here and keep the gross balance as
    // the amount, so 100% asked to send the whole balance AND pay a fee
    // out of it. The draft then failed to build and Review showed
    // "Couldn't prepare this payment" with the Send button dead.
    final usesBdkSource = sourceWallet?.usesBdk ?? false;
    try {
      int updated;
      if (usesBdkSource) {
        // Hardware/watch-only path. The drain calculation needs a
        // valid destination because BDK's TxBuilder validates it
        // first; we now have one. Fee rate comes from the user's
        // current selection so changing priority recomputes max next
        // time the user transitions through Send-to.
        //
        // The probe builds on the SOURCE wallet's own native session and
        // reads that wallet's balance. `bitcoinModelProvider` /
        // `getBitcoinBalanceProvider` are pinned to the active spending
        // wallet, so a cold send probed the wrong wallet's coins: with no
        // BDK coins there it bailed out silently and left MAX on the gross
        // balance, and with coins there it sized the fee from a coin set
        // the hardware wallet cannot spend.
        final sourceId = sourceWallet!.id;
        final feeRate = await ref.read(getCustomFeeRateProvider.future);
        final model =
            await ref.read(bitcoinModelForWalletProvider(sourceId).future);
        // Size the drain from the coins the builder will actually
        // spend. With a manual coin selection that is the chosen
        // subset, not the wallet total, so the probe and the real
        // build agree on both the input set and the fee.
        final selectedUtxos = List<onchain.OutPoint>.unmodifiable(
            ref.read(selectedUtxosProvider));
        final balanceSats = _bdkSpendableSats(ref, sourceId) ??
            model.getBalance().total.toSat();
        if (balanceSats <= 0) return;
        final probeBuilder = TransactionBuilder(
            balanceSats, stripBitcoinAddress(address), feeRate,
            selectedUtxos: selectedUtxos.isEmpty ? null : selectedUtxos);
        final psbt = await buildPsbtWhenIdle(model, probeBuilder, drain: true);
        // The builder's own number, never `balance - fee`. A drain build
        // has exactly one output and its value IS what leaves: the coins
        // the builder chose to spend, less the fee it chose to pay.
        // Subtracting a fee from a balance reproduces that figure only
        // while both sides agree on the coin set, and at dispatch the
        // two are compared sat for sat, so a single sat of disagreement
        // stops the send with nothing broadcast. Reading the output
        // removes the second opinion. A build that is not a single
        // output drain throws, and the catch below keeps the previous
        // amount rather than writing a figure no builder produced.
        updated = BitcoinSoftwareSend.drainRecipientSats(psbt);
      } else {
        // Spending wallet: Review resolves its 100% from the SDK's own
        // send-all preparation (`_resolveSparkDrainAmount`), the same
        // one the send reads. Nothing to probe here.
        return;
      }
      if (!mounted) return;
      if (updated <= 0) return;
      // The probe awaits a real transaction build, so it can land after
      // the user has already tapped Send. Writing the amount then moves
      // the ground under a payment in flight: the pre-broadcast check
      // compares the amount, the drain flag and the reviewed transaction
      // against what was approved, sees one of them changed, and aborts
      // with "payment not sent". That is why a 100% send failed while
      // every smaller one, which never runs this probe, went through.
      if (isProcessing || _paymentAuthInFlight || isInvoice) return;
      // The drain may also have been cleared while the probe was out,
      // in which case this figure is no longer what the user asked for.
      if (!_isDraining) return;
      ref.read(sendTxProvider.notifier).updateAmount(updated);
      updateControllerText(updated);
    } catch (_) {
      // Best effort — stay with the previously-set amount, the actual
      // send-time prepare will surface a precise error if it overflows.
    }
  }

  // ─── Page wrappers ──────────────────────────────────────────

  // ─── Amount page ────────────────────────────────────────────

  Widget _amountPage(AppColorsExtension c, String currentInputCurrency,
      String btcFormat, int btcSats) {
    // `_amountBody` owns the full height: hero on top, chips + keypad
    // pinned to the bottom. No outer centering Column — it would
    // unbound the keypad's share of the page.
    return _amountBody(c, currentInputCurrency, btcFormat, btcSats);
  }

  // ─── Send-to page (focused redesign) ────────────────────────

  /// Read the clipboard on entering the Send to step and keep a
  /// recognisable address or invoice as [_clipboardCandidate]. Only
  /// payloads the selected source can actually pay are offered; a
  /// cold wallet is offered on-chain addresses only.
  Future<void> _checkClipboardForAddress() async {
    if (addressController.text.isNotEmpty) return;
    try {
      if (!await Clipboard.hasStrings()) return;
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty || raw.length > 2048) return;
      if (raw == _clipboardDismissed || raw == _clipboardCandidate) return;
      // Recognise a cross-chain URI by its bare address; the commit
      // path reduces it the same way when Use is tapped.
      final bare = bareCrossChainRecipient(raw);
      final detected = _detectAddressType(bare);
      if (!detected.valid || detected.label == 'Unknown') return;
      if (_isColdSource && detected.label != 'Bitcoin on-chain') return;
      if (_resolveUnifiedPasteForActiveWallet(bare) == null) return;
      TrackingService.track('pay_clipboard_nudge_shown', params: {
        'address_type': _trackingAddressType(detected),
      });
      setState(() => _clipboardCandidate = raw);
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  /// Inline Paste on the recipient field: read the clipboard and run
  /// the shared commit path. An empty clipboard is a no-op.
  Future<void> _pasteAddressFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (!mounted || raw.isEmpty) return;
      _clipboardCandidate = null;
      _commitPastedAddress(raw, method: 'pasted');
    } catch (_) {
      // No clipboard access is the same as an empty clipboard.
    }
  }

  /// Inline Scan on the recipient field. Unified on the smart scanner
  /// (camera, Gallery and Paste live there, plus cross-chain
  /// detection) in return-value mode so it hands the raw payload back
  /// here instead of pushing a fresh confirm_send.
  Future<void> _scanAddress() async {
    final result = await context.pushNamed<String>(
      'smartScanner',
      extra: const {'returnRaw': true},
    );
    if (!mounted) return;
    final scanned = result?.trim() ?? '';
    if (scanned.isEmpty) return;
    _commitPastedAddress(scanned, method: 'scanned');
  }

  /// Quiet one-line card under the recipient field while the clipboard
  /// holds something payable: Use fills the field, the cross dismisses.
  Widget _clipboardNudgeChip(AppColorsExtension c, String candidate) {
    return SendClipboardNudge(
      onUse: () {
        _clipboardCandidate = null;
        _commitPastedAddress(candidate, method: 'pasted');
      },
      onDismiss: () => setState(() {
        _clipboardDismissed = candidate;
        _clipboardCandidate = null;
      }),
    );
  }

  /// "Recent recipients" for the picked source: the spending wallet's
  /// Breez SDK contacts, newest use first, up to five, with the amount
  /// and date of the last payment to each from the live Spark rows. Until
  /// contacts load, or when the SDK is not ready or fails, it is the
  /// list derived from the payment history (the last Lightning addresses
  /// paid), so the section never disappears. One-time invoices and
  /// on-chain outputs are not reusable destinations, so they are never
  /// offered; a cold source (on-chain only) gets no list.
  List<RecentRecipient> _recentRecipients() {
    final sparkSource =
        !_isColdSource && (_resolveSourceWallet()?.isSparkWallet ?? false);
    return recentRecipientsFor(
      sparkSource: sparkSource,
      contacts: sparkSource ? ref.watch(sparkContactsProvider) : null,
      txs: sparkSource
          ? ref.watch(mergedTransactionsProvider).sparkTransactions
          : const <SparkTransaction>[],
    );
  }

  /// Section label above a list card on the Send to step.
  Widget _sendToSectionHeader(AppColorsExtension c, String title) =>
      SendToSectionHeader(title: title);

  Widget _recentRecipientsList(
      AppColorsExtension c, List<RecentRecipient> recents) {
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sendToSectionHeader(c, context.l10n.sendRecentRecipients),
        _SendToListCard(
          colors: c,
          rows: [
            for (final r in recents)
              _SendToListRow(
                colors: c,
                leading: Icon(
                  r.address.contains('@')
                      ? Icons.person_rounded
                      : Icons.bolt_rounded,
                  color: c.textPrimary,
                  size: 20.sp,
                ),
                title: r.address,
                trailingTitle: r.sats == null
                    ? null
                    : ref.watch(conversionProvider(r.sats!)),
                trailingSubtitle: DateFormat.MMMd(locale).format(r.when),
                onTap: () =>
                    _commitPastedAddress(r.address, method: 'contacts'),
              ),
          ],
        ),
      ],
    );
  }

  /// Cross-chain destinations as one quiet row in one card: it opens
  /// the picker and also carries the pasted-address network pick plus
  /// the current selection summary once a destination is chosen. No
  /// coin is pinned in front of it (user decision): pinned USDC and
  /// USDT rows read as the offer, when the offer is the whole catalog
  /// and the user picks inside the sheet.
  ///
  /// AT REST IT IS A STATEMENT, not a mode. It says what this money
  /// can be sent to and shows the coins, exactly as the receive screen
  /// says what its address accepts, because "Other crypto" read as a
  /// switch a person had to flip before they could pay someone. The
  /// three working states are untouched: an address we cannot
  /// identify, an address that still needs a network, and a
  /// destination already chosen, all of which have something specific
  /// to say and say it in the row.
  ///
  /// Hardware / watch-only sources get none of this: cross-chain sends
  /// are Orchestra deliveries from the Spark hot wallet, so cold
  /// wallets are bitcoin-on-chain-only. Mirrors the account model's
  /// `canSwap` capability (models/account.dart).
  Widget _crossChainDestinations(AppColorsExtension c, String addr) {
    final detected = _detectAddressType(addr);
    final isNativeBtcRail = detected.label == 'Bitcoin on-chain' ||
        detected.label == 'Lightning invoice' ||
        detected.label == 'Lightning address' ||
        detected.label == 'LNURL' ||
        detected.label == 'Spark address';
    final needsPick = addr.isNotEmpty &&
        !isNativeBtcRail &&
        (_selectedDestAsset == null || _selectedDestNetwork == null);
    final addressUnrecognized =
        addr.isNotEmpty && (detected.label == 'Unknown' || !detected.valid);
    final hasSelection = _selectedDestAsset != null;
    final String otherTitle;
    final String otherSubtitle;
    if (hasSelection) {
      otherTitle =
          '${_selectedDestAsset!.code} · ${_selectedDestNetwork?.name ?? ''}';
      otherSubtitle = context.l10n.sendAutoSwapFromBitcoin;
    } else if (addressUnrecognized && needsPick) {
      otherTitle = context.l10n.sendAddressNotIdentified;
      otherSubtitle = context.l10n.sendChooseANetworkFromTheSheetToContinue;
    } else if (needsPick) {
      otherTitle = context.l10n.sendWhichNetworkIsThisAddressOn;
      otherSubtitle = context.l10n.sendTapToChoose;
    } else {
      otherTitle = context.l10n.sendOtherCrypto;
      otherSubtitle = '';
    }
    void open() {
      TrackingService.sendAssetShortcutTapped('other');
      _showDestinationPicker(context);
    }

    // The coins this send can land as, folded one per coin — the same
    // fold, the same marks and the same clip the sheet itself uses, so
    // the line and the grid can never be a different set.
    final catalog = ref.watch(orchestraSupportedRoutesProvider);
    final eligible =
        _eligibleNetworksForFamily[_addressRailFamily(addressController.text)];
    final all = _sendDestOptions(catalog, context.l10n);
    final groups = groupCoinsByAsset([
      for (final o in all)
        if (eligible == null || eligible.contains(o.chain))
          _sendDestPickerRow(o),
    ]);
    final atRest = !hasSelection && !needsPick;
    return _SendToListCard(
      colors: c,
      // Attention reads through the border weight and copy, never an
      // accent wash. The Continue gate is inactive while a pick is
      // pending, so this card is the only forward path.
      emphasized: needsPick && !hasSelection,
      rows: [
        if (atRest && groups.isNotEmpty)
          CoinMarksLine(
            label: context.l10n.sendAlsoSendsTo,
            groups: groups,
            moreLabel: context.l10n.receiveAlsoAcceptsMore,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            onTap: open,
          )
        else
          _SendToListRow(
            colors: c,
            leading: hasSelection
                ? _selectedDestAsset!.iconWidget(size: 28.sp)
                : Icon(Icons.swap_horiz_rounded,
                    color: c.textSecondary, size: 20.sp),
            title: otherTitle,
            subtitle: otherSubtitle,
            onTap: open,
          ),
      ],
    );
  }

  Widget _sendToPage(AppColorsExtension c) {
    final addr = addressController.text;
    // Hardware/watch-only wallets accept on-chain Bitcoin addresses.
    // Lightning payments require the spending wallet.
    // Source wallet for hint-text branching must resolve from
    // `_selectedWalletId` first — active is pinned to spending.
    final settings = ref.read(settingsProvider);
    final WalletConfig? sourceWallet = _selectedWalletId != null
        ? settings.wallets.firstWhere(
            (w) => w.id == _selectedWalletId,
            orElse: () => settings.activeWallet ?? settings.wallets.first,
          )
        : settings.activeWallet;
    final isExternalSigner = sourceWallet != null &&
        (sourceWallet.isHardware || sourceWallet.isWatchOnly);
    final String hintText;
    if (_selectedDestAsset != null && _selectedDestNetwork != null) {
      hintText = context.l10n.sendAssetOnNetworkAddressHint(
          _selectedDestAsset!.code, _selectedDestNetwork!.name);
    } else if (isExternalSigner) {
      hintText = context.l10n.sendPasteBitcoinAddress;
    } else {
      hintText = context.l10n.sendPasteAddressOrLightning;
    }
    final detected = _detectAddressType(addr);
    // Hardware / watch-only + Lightning address: explain the
    // spending-wallet requirement before they hit Review (Continue is
    // also disabled in this state so they can't advance silently).
    final bool showSignerWarning;
    if (!isExternalSigner || addr.isEmpty) {
      showSignerWarning = false;
    } else {
      final isLnLike = detected.label == 'Lightning invoice' ||
          detected.label == 'Lightning address' ||
          detected.label == 'LNURL';
      final dstIsLightning =
          _selectedDestNetwork?.network.toLowerCase() == 'lightning';
      showSignerWarning = isLnLike && !dstIsLightning;
    }
    final recents = addr.isEmpty
        ? _recentRecipients()
        : const <RecentRecipient>[];
    // The spending wallet gets it too (owner decision). What was taken
    // off that wallet was the old "Other crypto" row, a mode to switch
    // on; at rest this is the marks line, the same statement of what
    // the address can send to that Receive makes about what it takes.
    // A bitcoin destination has nothing to pick: the coin and the rail
    // are the address. The card only helps when an address could land as
    // several coins (an EVM address as USDC, USDT or ETH), so it hides as
    // soon as a bitcoin, Lightning or Spark destination is recognised.
    final detectedForCard = _detectAddressType(addr);
    final bitcoinDestination = addr.isNotEmpty &&
        detectedForCard.valid &&
        (detectedForCard.label == 'Bitcoin on-chain' ||
            detectedForCard.label == 'Lightning invoice' ||
            detectedForCard.label == 'Lightning address' ||
            detectedForCard.label == 'LNURL' ||
            detectedForCard.label == 'Spark address');
    // Cross-chain is only offered where Orchestra can route it: from
    // the Spark hot wallet, never from a cold source.
    final showCrossChain = !_isColdSource && !bitcoinDestination;
    // Scrollable so five recents plus the cross-chain rows never
    // overflow on a short screen or at a large text scale.
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SendRecipientField(
            controller: addressController,
            colors: c,
            hintText: hintText,
            isValid: detected.valid,
            onPaste: _pasteAddressFromClipboard,
            onScan: _scanAddress,
            onChanged: (val) {
              // A pasted `bitcoin:bc1…?amount=…` URI must be reduced to
              // the bare address — it's both what we show here and what
              // feeds the on-chain fee calc (the prefixed form is
              // rejected).
              final norm = val.toLowerCase().startsWith('bitcoin:')
                  ? stripBitcoinAddress(val)
                  : val;
              if (norm != val) {
                addressController.value = TextEditingValue(
                  text: norm,
                  selection: TextSelection.collapsed(offset: norm.length),
                );
              }
              ref.read(sendTxProvider.notifier).updateAddress(norm);
              _revalidateDestForAddress(norm);
              if (norm.isNotEmpty && _addressEntryMethod == null) {
                _addressEntryMethod = 'typed';
              }
              setState(() {});
            },
          ),
          // Detected-network badge: only once the address identifies
          // as something parseable, so an empty field has no gap.
          if (detected.valid && detected.label == 'Bitcoin on-chain') ...[
            // A bitcoin address needs no badge, check or mark: one quiet
            // line under the field says what it is (owner decision).
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.only(left: 4.w),
              child: Text(
                context.l10n.sendDetectedBitcoinAddress,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else if (detected.valid) ...[
            SizedBox(height: 10.h),
            _DetectedNetworkBadge(address: addr, colors: c),
          ],
          if (showSignerWarning) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12.r),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 16.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      context.l10n.sendWalletCantSignLightningOtherNetwork,
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Clipboard nudge: only while the field is empty, so it never
          // competes with a typed address.
          if (_clipboardCandidate != null && addr.isEmpty) ...[
            SizedBox(height: 12.h),
            _clipboardNudgeChip(c, _clipboardCandidate!),
          ],
          // Recent recipients: the last few Lightning addresses this
          // wallet paid, one tap to fill the field. Hidden once an
          // address is in the field so it never competes with it.
          if (recents.isNotEmpty) ...[
            SizedBox(height: 24.h),
            _recentRecipientsList(c, recents),
          ],
          if (showCrossChain) ...[
            SizedBox(height: 24.h),
            _crossChainDestinations(c, addr),
          ],
        ],
      ),
    );
  }

  // ─── Review page (slide-to-send) ────────────────────────────

  Widget _reviewPage(AppColorsExtension c, String btcFormat) {
    final sourceWallet = _resolveSourceWallet();
    // MAX is the whole balance MINUS the fee, and the fee is only known
    // once there is an address and a rate to size it with. Review is the
    // first place both are true, so the figure is netted here every time
    // it is wrong, rather than once on the way in. Without this the
    // amount stays at the gross balance, the draft cannot be built at
    // all, and the fee row reports a payment it could not prepare.
    _netDrainAgainstFee(sourceWallet);
    final softwarePreview = sourceWallet?.isBitcoinSoftware == true
        ? ref.watch(bitcoinSoftwareSendPreviewProvider(
            _softwareSendRequest(sourceWallet!)))
        : null;
    final softwareReady = sourceWallet?.isBitcoinSoftware != true ||
        (softwarePreview?.isLoading == false &&
            softwarePreview?.hasError == false &&
            _softwareReviewReady(softwarePreview?.valueOrNull,
                ref.watch(sendTxProvider).amount));
    // Two tiers now, where there used to be one.
    //
    // `canTapSend` decides whether the control is LIVE. It holds the
    // conditions a wait can never fix: no source wallet, the earlier
    // steps not done, a send or an auth prompt already running. Each
    // of those is a state the user has to leave,
    // and each already says so on the page, so a dead button is the
    // honest reading of them.
    //
    // `sendReadyNow` is the rest: the MAX netting and the software
    // PSBT preview, which resolve by themselves in a moment. Those no
    // longer grey the button out. Tapping while they are outstanding
    // spins the button and `_sendPressed` waits for them, then
    // dispatches. Nothing is skipped: `_handleSend` re-checks the
    // approved amount, the drain flag and the reviewed PSBT before a
    // single sat moves.
    final canTapSend = sourceWallet != null &&
        _completedSteps.containsAll({0, 1}) &&
        !isProcessing &&
        !_paymentAuthInFlight &&
        !_sendAwaitingReady;
    final sendReadyNow = softwareReady && !isCalculatingMax;
    // Source wallet must come from `_selectedWalletId` — active is
    // pinned to spending so the CTA label / dispatch would otherwise
    // say "Send" (Spark) even when the user is sending from a
    // hardware wallet that needs the PSBT/Continue flow.
    final isExternalSigner = sourceWallet != null &&
        (sourceWallet.isHardware || sourceWallet.isWatchOnly);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: _reviewBody(c, btcFormat),
          ),
        ),
        SizedBox(height: 16.h),
        // Hardware / watch-only — primary action says "Continue"
        // and advances to the Sign step. Hot wallets dispatch
        // straight away, so the button reads "Send".
        SendReviewAction(
          // Hardware → "Continue" builds the PSBT and advances to the
          // Sign step (handled inside `_handleSend` →
          // `_handleHardwareSigning`). Hot wallets dispatch directly.
          label: (isProcessing || _sendAwaitingReady)
              ? (isExternalSigner
                  ? context.l10n.sendBuildingUnsignedTransaction
                  : context.l10n.sendSendingEllipsis)
              : (isExternalSigner
                  ? context.l10n.continueLabel
                  : context.l10n.send),
          // Spins for the whole send, as the dollar send's button does —
          // not only for the post-tap readiness wait. A send in flight
          // used to read as a greyed-out button with nothing moving.
          loading: isProcessing || _sendAwaitingReady,
          onPressed: canTapSend ? () => _sendPressed(context, ref) : null,
          // While the draft is still resolving the footnote says the
          // fee is being worked out rather than promising an instant
          // debit the tap cannot yet honour.
          footnote: !sendReadyNow
              ? context.l10n.sendWaitForFee
              : isExternalSigner
                  ? context.l10n.sendApproveOnYourDeviceNext
                  : context.l10n.sendFundsLeaveYourWalletImmediately,
        ),
      ],
    );
  }

  /// Step 5 — explicit Sign page for hardware / watch-only sends.
  /// The PSBT is built lazily here (once, the first time the page
  /// is reached) and the user kicks off external signing via the
  /// Sign button — opens the same `watchOnlySigning` route that the
  /// hot send used to push to. The page shows what's about to be
  /// signed (amount + recipient summary) so the user has one final
  /// look before scanning into their hardware wallet.
  Widget _signPage(AppColorsExtension c, String btcFormat) {
    final selectedWallet = _builtPsbtWallet;

    // 1. Inline error state — PSBT build threw. Render a non-blocking
    //    error card with a Try-again CTA so the user can adjust speed
    //    / UTXOs / amount and rebuild without leaving the stepper.
    if (_builtPsbt == null && _signPageError != null) {
      return _SignPageContainer(
        c: c,
        body: _signErrorCard(c),
      );
    }

    // 2. Building / preparing — loader while `_handleHardwareSigning`
    //    finishes building the PSBT.
    if (_builtPsbt == null) {
      return _SignPageContainer(
        c: c,
        body: Padding(
          padding: EdgeInsets.symmetric(vertical: 48.h),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingAnimationWidget.staggeredDotsWave(
                    color: c.textSecondary, size: 28.sp),
                SizedBox(height: 12.h),
                Text(
                  isProcessing
                      ? context.l10n.sendBuildingUnsignedTransaction
                      : context.l10n.sendPreparingTransaction,
                  style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // 3. Built — render the embedded signing screen below the
    //    settings row.
    return _SignPageContainer(
      c: c,
      hideNetworkControls: _signedPsbtAccepted || _signerBusy,
      body: WatchOnlySigningScreen(
        psbtBase64: _builtPsbt!,
        walletType: selectedWallet?.walletType ?? 'generic',
        scriptType: selectedWallet?.scriptType,
        walletId: selectedWallet?.id,
        embedded: true,
        // Stepper body already pads horizontally; suppress the inner
        // default to avoid double padding.
        horizontalPadding: 0,
        recipientSatsOverride: _builtPsbtRecipientSats,
        recipientAddressOverride: _builtPsbtRecipientAddress,
        feeSatsOverride: _builtPsbtFeeSats,
        onBusyChanged: (busy) {
          if (mounted && _signerBusy != busy) {
            setState(() => _signerBusy = busy);
          }
        },
        onSignedChange: (signed) {
          if (!mounted) return;
          if (signed) _consumeSignedPsbtGrant();
          if (_signedPsbtAccepted != signed) {
            setState(() => _signedPsbtAccepted = signed);
          }
        },
      ),
    );
  }

  /// Inline error card rendered inside the Sign step when the PSBT
  /// build threw. Mirrors the Review fee-row error style: small icon
  /// + body + a Try-again CTA pinned at the bottom. Tighter padding
  /// than the prior snackbar-only flow so the error reads as part of
  /// the page, not chrome that's about to disappear.
  Widget _signErrorCard(AppColorsExtension c) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
            color: AppColors.error.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                context.l10n.sendCouldntPrepareTheTransaction,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            _signPageError ?? context.l10n.sendUnknownError,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              height: 1.4,
            ),
          ),
          // The raw engine text stays one tap away for support.
          if (_signPageErrorDetail != null && _signPageErrorDetail!.isNotEmpty)
            SheetNerdDataSection(children: [
              SheetDetailRow(
                label: context.l10n.details,
                value: _signPageErrorDetail!,
                copiable: true,
              ),
            ]),
          SizedBox(height: 14.h),
          // Merge: nav's AppButton + main's l10n label.
          AppButton(
            text: context.l10n.walletsTryAgain,
            onPressed: isProcessing ? null : _retrySignPagePsbt,
            icon: Icons.refresh_rounded,
            compact: true,
          ),
        ],
      ),
    );
  }

  /// Re-run the PSBT build using the last `_handleHardwareSigning`
  /// params. Used by both the inline "Try again" CTA after a failed
  /// build, and the post-Advanced-sheet rebuild (so changing speed
  /// or UTXOs while sitting on the Sign step regenerates the PSBT
  /// against the new selection without backing out to Review).
  Future<void> _rebuildSignPagePsbt() async {
    if (_signedPsbtAccepted || _signerBusy) return;
    final addr = _signLastToAddress;
    final amt = _signLastAmountSats;
    if (addr == null || amt == null) return;
    // Drop the prior PSBT so the page swaps back to the loader while
    // the new one builds — otherwise the stale "Sign with device"
    // body would stay on screen with the wrong fee/UTXOs.
    setState(() {
      _builtPsbt = null;
      _builtPsbtRecipientAddress = null;
      _builtPsbtWallet = null;
      _builtPsbtFeeSats = null;
      _builtPsbtRecipientSats = null;
      _signedPsbtAccepted = false;
      _signerBusy = false;
    });
    await _handleHardwareSigning(context, ref, addr, amt,
        provider: _signLastProvider, recipient: _signLastRecipient);
  }

  Future<void> _retrySignPagePsbt() async {
    setState(() {
      _signPageError = null;
      _signPageErrorDetail = null;
    });
    await _rebuildSignPagePsbt();
  }
}

/// Shared chrome for the Sign step — the network-speed / coin-control
/// affordance row sits on top, the supplied `body` (loader, error
/// card, or embedded `WatchOnlySigningScreen`) fills the rest. The
/// row is the same control surface Review exposes for hot wallets,
/// surfaced inline here so hardware users can re-dial speed + UTXOs
/// after landing on Sign without paddling back through the stepper.
/// The PSBT rebuild is driven by the parent screen's `ref.listen`
/// on the speed / utxo / custom-rate providers (registered in
/// `build`), so we don't need to await the sheet on tap.
class _SignPageContainer extends ConsumerWidget {
  final AppColorsExtension c;
  final Widget body;

  /// Kept for the call site; nothing is gated on it any more.
  final bool hideNetworkControls;

  const _SignPageContainer({
    required this.c,
    required this.body,
    this.hideNetworkControls = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // Coin selection and network speed are settled on Review, on
      // every hardware wallet, not only a Ledger. Offering them again
      // here invited a change to the very transaction the device is
      // about to be handed, and a change after signing would silently
      // invalidate the signature. This step is only about the device.
      children: [
        Expanded(child: body),
      ],
    );
  }
}

/// State of a single step in the swap-execution progress.
enum _StepState { pending, inProgress, done, failed }

class _SwapStep {
  final String label;
  final String detail;
  _StepState state = _StepState.pending;
  String? error;
  _SwapStep({required this.label, required this.detail});
}

/// Drives the [_SwapConfirmationPage] from outside — orchestrator
/// updates step states + lifecycle (confirmed / completed / failed),
/// page rebuilds when the controller notifies. Lets us keep the same
/// page mounted across the confirmation → execution → success
/// transition (no navigation churn mid-send).
class _SwapExecutionController extends ChangeNotifier {
  final List<_SwapStep> steps;
  bool confirmed = false;
  bool completed = false;
  String? topLevelError;

  /// Set to true between intermediate steps when the page should
  /// pause and show a "Send" CTA — used after the top-up step lands
  /// so the user explicitly initiates the actual Spark/LN/on-chain
  /// send rather than us silently chaining into it.
  bool awaitingNextStep = false;

  /// Completer the orchestrator awaits to know whether the user
  /// hit Confirm or Cancel on the review screen.
  final Completer<bool> _confirmation = Completer<bool>();

  /// Completer for the second-stage "Send" tap, after the top-up
  /// landed. We can only build it lazily because the orchestrator
  /// may call [awaitNextStep] more than once if the page is reused;
  /// by storing it here we keep callbacks deterministic.
  Completer<bool>? _nextStep;

  _SwapExecutionController(this.steps);

  Future<bool> awaitConfirmation() => _confirmation.future;

  /// Pauses the page between steps until the user taps the Send CTA.
  /// Returns `true` once tapped, `false` if the user dismissed the page
  /// (PopScope blocks this during executing, so cancellation is rare).
  Future<bool> awaitNextStep() {
    awaitingNextStep = true;
    _nextStep ??= Completer<bool>();
    notifyListeners();
    return _nextStep!.future;
  }

  void confirm() {
    if (confirmed) return;
    confirmed = true;
    if (!_confirmation.isCompleted) _confirmation.complete(true);
    notifyListeners();
  }

  void cancel() {
    if (!_confirmation.isCompleted) _confirmation.complete(false);
    if (_nextStep != null && !_nextStep!.isCompleted) {
      _nextStep!.complete(false);
    }
  }

  void confirmNext() {
    if (!awaitingNextStep) return;
    awaitingNextStep = false;
    if (_nextStep != null && !_nextStep!.isCompleted) {
      _nextStep!.complete(true);
    }
    notifyListeners();
  }

  void markStep(int i, _StepState state, {String? error}) {
    if (i < 0 || i >= steps.length) return;
    steps[i].state = state;
    steps[i].error = error;
    notifyListeners();
  }

  void complete() {
    completed = true;
    notifyListeners();
  }

  void fail(String err) {
    topLevelError = err;
    notifyListeners();
  }
}

/// Full-screen confirmation + live execution view. Three lifecycle
/// states drive the visible chrome:
///   - `confirmed == false`           → "review" mode (Cancel + Confirm)
///   - `confirmed == true && !completed && topLevelError == null`
///                                    → "executing" mode (no buttons,
///                                       step badges animate)
///   - `completed == true`            → "success" mode (single Done)
///   - `topLevelError != null`        → "failed" mode (Close + Retry-N/A)
class _SwapConfirmationPage extends StatefulWidget {
  final String amountStr;
  final String unit;
  final String fiatStr;
  final String withdrawalAddress;
  final String networkName;
  final String receivedAmount;
  final _SwapExecutionController controller;

  const _SwapConfirmationPage({
    required this.amountStr,
    required this.unit,
    required this.fiatStr,
    required this.withdrawalAddress,
    required this.networkName,
    required this.receivedAmount,
    required this.controller,
  });

  @override
  State<_SwapConfirmationPage> createState() => _SwapConfirmationPageState();
}

class _SwapConfirmationPageState extends State<_SwapConfirmationPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  String _shortAddr(String a) {
    if (a.length <= 20) return a;
    return '${a.substring(0, 10)}…${a.substring(a.length - 10)}';
  }

  /// Overall completion fraction for the page-level progress bar:
  /// each step contributes 0.5 in-progress / 1.0 done so the bar moves
  /// in two beats per step. Smooth fractional value drives the animated
  /// fill in [_OverallProgressBar].
  double _overallProgress(_SwapExecutionController ctrl) {
    if (ctrl.steps.isEmpty) return 0.0;
    double sum = 0;
    for (final s in ctrl.steps) {
      switch (s.state) {
        case _StepState.pending:
          sum += 0.0;
          break;
        case _StepState.inProgress:
          sum += 0.5;
          break;
        case _StepState.done:
        case _StepState.failed:
          sum += 1.0;
          break;
      }
    }
    return (sum / ctrl.steps.length).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctrl = widget.controller;
    final isReview = !ctrl.confirmed && ctrl.topLevelError == null;
    final isExecuting =
        ctrl.confirmed && !ctrl.completed && ctrl.topLevelError == null;
    final isDone = ctrl.completed;
    final isFailed = ctrl.topLevelError != null;
    // Mid-flight pause: top-up landed and we're waiting for the user
    // to tap Send to fire the second leg. Re-enables back-nav and
    // shows a primary "Send" CTA.
    final isAwaitingNext = isExecuting && ctrl.awaitingNextStep;
    return PopScope(
        // Block back navigation while the orchestrator is mid-flight
        // — once we've sent funds out of Spark we can't undo it. Allow
        // back when we're paused between steps (awaitingNext) so the
        // user can bail before triggering the send leg.
        canPop: !isExecuting || isAwaitingNext,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Container(
            decoration: AppDecorations.screenGradient(context),
            child: PlatformSafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                child: Column(
                  children: [
                    // Close chip — only shown in review/done/failed,
                    // hidden during execution to prevent a tap-to-cancel
                    // race.
                    Row(
                      children: [
                        if (!isExecuting || isAwaitingNext)
                          KuteCloseButton(
                            onPressed: () {
                              if (isReview) ctrl.cancel();
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: 12.h),
                            _HeadlineIcon(
                              state: isFailed
                                  ? _HeadlineState.failed
                                  : isDone
                                      ? _HeadlineState.done
                                      : isExecuting
                                          ? _HeadlineState.executing
                                          : _HeadlineState.review,
                              colors: c,
                            ),
                            SizedBox(height: 20.h),
                            Text(
                              isFailed
                                  ? context.l10n.sendSendFailed
                                  : isDone
                                      ? context.l10n.sent
                                      : isAwaitingNext
                                          ? context.l10n.sendReadyToSend
                                          : isExecuting
                                              ? context.l10n.sendSendingEllipsis
                                              : context.l10n.confirmTransaction,
                              style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ),
                            ),
                            SizedBox(height: 12.h),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  BtcAmountText(
                                    text: widget.amountStr,
                                    style: TextStyle(
                                      fontSize: 52.sp,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                      letterSpacing: -1.2,
                                      height: 1.0,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  Text(
                                    ' ${widget.unit}',
                                    style: TextStyle(
                                      fontSize: 52.sp,
                                      fontWeight: FontWeight.w800,
                                      color: c.textPrimary,
                                      letterSpacing: -1.2,
                                      height: 1.0,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              widget.fiatStr,
                              style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]),
                            ),
                            SizedBox(height: 28.h),
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(16.r),
                                border: Border.all(
                                    color: c.borderSubtle, width: 0.5),
                              ),
                              child: Column(
                                children: [
                                  _detailRow(c,
                                      icon: Icons.alternate_email_rounded,
                                      label: context.l10n.to,
                                      value:
                                          _shortAddr(widget.withdrawalAddress)),
                                  _detailRow(c,
                                      icon: Icons.public_rounded,
                                      label: context.l10n.network,
                                      value: widget.networkName),
                                  _detailRow(c,
                                      icon: Icons.south_west_rounded,
                                      label: context.l10n.youReceive,
                                      value: widget.receivedAmount),
                                ],
                              ),
                            ),
                            if (ctrl.steps.isNotEmpty) ...[
                              SizedBox(height: 18.h),
                              Container(
                                width: double.infinity,
                                padding:
                                    EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 14.h),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(16.r),
                                  border: Border.all(
                                      color: c.borderSubtle, width: 0.5),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            isReview
                                                ? context.l10n.sendSteps
                                                : isDone
                                                    ? context.l10n.completed
                                                    : context.l10n.sendProgress,
                                            style: TextStyle(
                                              color: c.textTertiary,
                                              fontSize: 13.sp,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                            )),
                                        if (!isReview)
                                          Text(
                                            '${(_overallProgress(ctrl) * 100).round()}%',
                                            style: TextStyle(
                                              color: c.textSecondary,
                                              fontSize: 13.sp,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                      ],
                                    ),
                                    SizedBox(height: 10.h),
                                    // Top-of-card overall progress bar — moves
                                    // in two beats per step (pending=0,
                                    // in-progress=½, done=1) so the user sees
                                    // a literal needle of forward motion that
                                    // crosses the full track once both legs
                                    // land. Shown for both review preview and
                                    // the executing/done states.
                                    _OverallProgressBar(
                                      progress: _overallProgress(ctrl),
                                      isFailed: isFailed,
                                      // Shimmer runs while we're actively
                                      // executing AND not paused mid-flight
                                      // (awaiting Send tap), and not in the
                                      // celebratory done state — those are
                                      // calm moments, the bar should rest.
                                      isActive: isExecuting &&
                                          !isAwaitingNext &&
                                          !isDone &&
                                          !isFailed,
                                      trackColor: c.surfaceLight,
                                      accent: c.accent,
                                    ),
                                    SizedBox(height: 14.h),
                                    for (var i = 0; i < ctrl.steps.length; i++)
                                      _stepRow(c, ctrl.steps[i],
                                          isLast: i == ctrl.steps.length - 1),
                                  ],
                                ),
                              ),
                            ],
                            if (isFailed) ...[
                              SizedBox(height: 14.h),
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 16.w, vertical: 12.h),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6565)
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(
                                      color: const Color(0xFFFF6565)
                                          .withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  ctrl.topLevelError ??
                                      context.l10n.sendUnknownError,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 14.sp,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    if (isReview) ...[
                      // Polymarket pattern — full-width primary above, text
                      // Cancel below — same as `pending_bet_overlay.dart`.
                      CustomButton(
                        text: context.l10n.confirm,
                        onPressed: () => ctrl.confirm(),
                        primaryColor: context.ctaFill,
                        // textColor omitted → AppButton picks contrasting per WCAG.
                      ),
                      SizedBox(height: 6.h),
                      AppTextButton(
                        text: context.l10n.cancel,
                        onPressed: () {
                          ctrl.cancel();
                          Navigator.of(context).pop();
                        },
                      ),
                    ] else if (isAwaitingNext) ...[
                      // Mid-flight pause — top-up landed, prompt the user
                      // to fire the actual send leg. One tap, no second
                      // confirmation modal layered on top of this page.
                      CustomButton(
                        text: context.l10n.send,
                        onPressed: () => ctrl.confirmNext(),
                        primaryColor: context.ctaFill,
                        // textColor omitted → AppButton picks contrasting per WCAG.
                      ),
                      SizedBox(height: 6.h),
                      AppTextButton(
                        text: context.l10n.cancel,
                        onPressed: () {
                          ctrl.cancel();
                          Navigator.of(context).pop();
                        },
                      ),
                    ] else if (isExecuting)
                      // Active execution — no buttons; close-chip hidden
                      // and back-nav blocked via PopScope. The progress
                      // bar + animated step rows convey "we're working".
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        child: Text(
                          context.l10n.sendDontCloseTheAppWhileThisFinishes,
                          style:
                              TextStyle(color: c.textTertiary, fontSize: 13.sp),
                        ),
                      )
                    else
                      CustomButton(
                        text: context.l10n.done,
                        onPressed: () => Navigator.of(context).pop(),
                        primaryColor: context.ctaFill,
                        // textColor omitted → AppButton picks contrasting per WCAG.
                      ),
                    SizedBox(height: 8.h),
                  ],
                ),
              ),
            ),
          ),
        ));
  }

  Widget _stepRow(AppColorsExtension c, _SwapStep step,
      {required bool isLast}) {
    return _AnimatedStepRow(step: step, isLast: isLast, colors: c);
  }

  Widget _detailRow(AppColorsExtension c,
      {required IconData icon, required String label, required String value}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: c.textPrimary.withValues(alpha: 0.6), size: 20.sp),
          SizedBox(width: 16.w),
          Text(label,
              style: TextStyle(
                  color: c.textPrimary.withValues(alpha: 0.6),
                  fontSize: 15.sp)),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Square action button used inside the address-input field's suffix.
/// Wraps the icon in a slightly larger tinted slot so the wallet/QR
/// glyphs sit visually balanced against the input height — and uses
/// `qr_code_scanner_rounded` instead of the camera glyph (the action
/// is "scan a QR", not "take a photo").

/// Full-screen confirmation for the standard transaction flow (BTC /
/// Lightning / Spark sends). Pops `true` on confirm, `false` on cancel.
/// Mirrors the swap-confirmation layout so the whole app shares one
/// confirm-tx pattern.
class _StandardConfirmationPage extends ConsumerWidget {
  final String amountString;
  final String unit;
  final String amountFiat;
  final String address;
  final List<FeeDetail> fees;

  const _StandardConfirmationPage({
    required this.amountString,
    required this.unit,
    required this.amountFiat,
    required this.address,
    required this.fees,
  });

  String _shortAddr(String a) {
    if (a.length <= 20) return a;
    return '${a.substring(0, 10)}…${a.substring(a.length - 10)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final totalFeeSats = fees.fold(0, (sum, item) => sum + item.amountSats);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
            child: Column(
              children: [
                Row(
                  children: [
                    KuteCloseButton(
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: 12.h),
                        Container(
                          padding: EdgeInsets.all(22.w),
                          decoration: BoxDecoration(
                              color: c.textPrimary.withValues(alpha: 0.06),
                              shape: BoxShape.circle),
                          child: Icon(Icons.arrow_upward_rounded,
                              color: c.textPrimary, size: 40.sp),
                        ),
                        SizedBox(height: 20.h),
                        Text(
                          context.l10n.confirmTransaction,
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            BtcAmountText(
                              text: amountString,
                              style: TextStyle(
                                fontSize: 52.sp,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                letterSpacing: -1.2,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              ' $unit',
                              style: TextStyle(
                                fontSize: 52.sp,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                letterSpacing: -1.2,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6.h),
                        Text(
                          amountFiat,
                          style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 17.sp,
                              fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 28.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(16.r),
                            border:
                                Border.all(color: c.borderSubtle, width: 0.5),
                          ),
                          child: Column(
                            children: [
                              _detailRow(c,
                                  icon: Icons.logout_rounded,
                                  label: context.l10n.to,
                                  value: _shortAddr(address)),
                              MoneyFeeSummary(
                                  label: context.l10n.totalFee,
                                  sats: fees.isEmpty
                                      ? null
                                      : totalFeeSats.toDouble(),
                                  state: fees.isEmpty ? 'Unavailable' : null,
                                  details: fees.length > 1
                                      ? [
                                          for (final fee in fees)
                                            MoneyFeeSummary(
                                                label: fee.label,
                                                sats:
                                                    fee.amountSats.toDouble()),
                                        ]
                                      : const []),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                // Polymarket pattern — full-width primary above, text
                // Cancel below — same as `pending_bet_overlay.dart` so
                // every confirm-tx surface in the app uses one shape.
                CustomButton(
                  text: context.l10n.confirm,
                  onPressed: () => Navigator.of(context).pop(true),
                  primaryColor: context.ctaFill,
                ),
                SizedBox(height: 6.h),
                AppTextButton(
                  text: context.l10n.cancel,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(AppColorsExtension c,
      {required IconData icon,
      required String label,
      required String value,
      bool emphasised = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon,
              color: c.textPrimary.withValues(alpha: emphasised ? 0.8 : 0.6),
              size: 20.sp),
          SizedBox(width: 16.w),
          Text(label,
              style: TextStyle(
                color: c.textPrimary.withValues(alpha: emphasised ? 0.85 : 0.6),
                fontSize: 15.sp,
                fontWeight: emphasised ? FontWeight.w700 : FontWeight.w500,
              )),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: emphasised ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _HeadlineState { review, executing, done, failed }

/// Headline icon for the confirmation page. Static during review, gets
/// concentric pulsing rings while executing (so the page feels alive
/// during the multi-second wait), morphs to a green check on done /
/// red x on failed.
class _HeadlineIcon extends StatefulWidget {
  final _HeadlineState state;
  final AppColorsExtension colors;
  const _HeadlineIcon({required this.state, required this.colors});

  @override
  State<_HeadlineIcon> createState() => _HeadlineIconState();
}

class _HeadlineIconState extends State<_HeadlineIcon>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;

  /// One-shot celebration when the page transitions to done — drives an
  /// expanding ring + a check-icon scale so the success lands with a
  /// visible beat instead of a silent swap.
  late AnimationController _burstCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _burstCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.state == _HeadlineState.done ||
        widget.state == _HeadlineState.failed) {
      _burstCtrl.value = 1.0;
    }
    // Defer the motion-starting `_sync` to didChangeDependencies so it
    // can read MediaQuery (Reduce Motion). initState only sets the
    // burst's resting value above.
  }

  bool _syncedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First post-initState sync — MediaQuery is available here, so the
    // pulse/burst respect the OS Reduce Motion preference.
    if (!_syncedOnce) {
      _syncedOnce = true;
      _sync(prev: null);
    }
  }

  @override
  void didUpdateWidget(covariant _HeadlineIcon old) {
    super.didUpdateWidget(old);
    if (widget.state != old.state) _sync(prev: old.state);
  }

  void _sync({_HeadlineState? prev}) {
    // Both the executing-state ring pulse and the done/failed
    // celebration burst are decorative. Honour Reduce Motion: don't run
    // the repeating pulse, and snap the burst to its finished value
    // instead of animating it.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.state == _HeadlineState.executing && !reduceMotion) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
    final endsWithBurst = widget.state == _HeadlineState.done ||
        widget.state == _HeadlineState.failed;
    if (endsWithBurst && prev != widget.state) {
      if (reduceMotion) {
        _burstCtrl.value = 1.0;
      } else {
        _burstCtrl.forward(from: 0.0);
      }
    } else if (!endsWithBurst) {
      _burstCtrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _burstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final isFailed = widget.state == _HeadlineState.failed;
    final isDone = widget.state == _HeadlineState.done;
    final isExecuting = widget.state == _HeadlineState.executing;

    final accent = isFailed
        ? const Color(0xFFFF6565)
        : isDone
            ? const Color(0xFF47C97A)
            : c.accent;

    final fg = isFailed
        ? const Color(0xFFFF6565)
        : isDone
            ? const Color(0xFF47C97A)
            : c.textPrimary;
    final iconData = isFailed
        ? Icons.error_outline_rounded
        : isDone
            ? Icons.check_rounded
            : Icons.arrow_upward_rounded;

    final core = AnimatedContainer(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: isFailed || isDone
            ? accent.withValues(alpha: 0.10)
            : c.surfaceLight,
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: fg, size: 36.sp),
    );

    if (!isExecuting) {
      // Done / failed — one-shot expanding ring + icon scale-in so the
      // final state lands with a visible beat. Settles to the static
      // core once the burst finishes.
      if (!isDone && !isFailed) return core;
      return SizedBox(
        width: 140.sp,
        height: 140.sp,
        child: AnimatedBuilder(
          animation: _burstCtrl,
          builder: (_, child) {
            final t = _burstCtrl.value;
            // Two staggered ring expansions during the burst.
            final t1 = (t * 1.6).clamp(0.0, 1.0);
            final t2 = ((t - 0.18) * 1.8).clamp(0.0, 1.0);
            // Icon scale-in: pinch then settle (1.0 by ~60 % through).
            final iconScale = t < 0.6
                ? 0.6 + Curves.easeOutBack.transform(t / 0.6) * 0.4
                : 1.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                if (t1 < 1.0) _burstRing(t1, accent),
                if (t2 > 0 && t2 < 1.0) _burstRing(t2, accent),
                Transform.scale(scale: iconScale, child: child),
              ],
            );
          },
          child: core,
        ),
      );
    }

    // Two staggered ring pulses so motion never feels like a single
    // beat — gives the appearance of a continuous broadcast.
    return SizedBox(
      width: 120.sp,
      height: 120.sp,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) {
          final t1 = _ctrl.value;
          final t2 = (_ctrl.value + 0.5) % 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              _pulseRing(t1, accent),
              _pulseRing(t2, accent),
              child!,
            ],
          );
        },
        child: core,
      ),
    );
  }

  Widget _pulseRing(double t, Color accent) {
    final eased = Curves.easeOut.transform(t);
    final size = 70.sp + (40.sp * eased);
    final alpha = (1.0 - eased) * 0.35;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accent.withValues(alpha: alpha),
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _burstRing(double t, Color accent) {
    final eased = Curves.easeOutCubic.transform(t);
    final size = 80.sp + (60.sp * eased);
    final alpha = (1.0 - eased) * 0.55;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accent.withValues(alpha: alpha),
            width: 2.2,
          ),
        ),
      ),
    );
  }
}

/// Animated progress row used in the swap confirmation page. Three
/// pieces of motion:
///   1. Icon badge pulses softly while in-progress (scale + alpha).
///   2. Indeterminate progress bar slides L→R until the step lands.
///   3. Bar snaps to 100 % full and stays green when the step is done.
/// Failed states freeze the bar mid-progress and tint everything red.
class _AnimatedStepRow extends StatefulWidget {
  final _SwapStep step;
  final bool isLast;
  final AppColorsExtension colors;

  const _AnimatedStepRow({
    required this.step,
    required this.isLast,
    required this.colors,
  });

  @override
  State<_AnimatedStepRow> createState() => _AnimatedStepRowState();
}

class _AnimatedStepRowState extends State<_AnimatedStepRow>
    with TickerProviderStateMixin {
  /// Continuous soft pulse on the badge while in-progress.
  late AnimationController _pulseCtrl;

  /// Continuous slide for the indeterminate progress bar.
  late AnimationController _barCtrl;

  /// Faster overlay shimmer that runs alongside the slide.
  late AnimationController _shimmerCtrl;

  /// One-shot "wake" pop when a step transitions pending → inProgress —
  /// the badge pinches down then springs up so the eye lands on it.
  late AnimationController _wakeCtrl;

  /// One-shot "fill" when a step transitions inProgress → done — drives
  /// the connector line drawing top-to-bottom AND the bar collapsing
  /// into its final solid green state.
  late AnimationController _fillCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _wakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    // If we mount already in done state (e.g. rebuild), skip the
    // animation so the connector renders fully drawn immediately.
    if (widget.step.state == _StepState.done) {
      _fillCtrl.value = 1.0;
    }
    // Defer the motion-starting sync to didChangeDependencies so it can
    // read MediaQuery (Reduce Motion).
  }

  bool _syncedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_syncedOnce) {
      _syncedOnce = true;
      _syncAnimations(prev: null);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedStepRow old) {
    super.didUpdateWidget(old);
    if (widget.step.state != old.step.state) {
      _syncAnimations(prev: old.step.state);
    }
  }

  void _syncAnimations({_StepState? prev}) {
    final state = widget.step.state;
    // Reduce Motion: the badge pulse, overlay shimmer, "wake" pop and
    // connector "fill" are decorative — suppress them. The bar slide
    // (`_barCtrl`) is the indeterminate PROGRESS indicator for an
    // in-flight step, so it's essential motion and stays running.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (state == _StepState.inProgress) {
      if (!reduceMotion) {
        _pulseCtrl.repeat(reverse: true);
        _shimmerCtrl.repeat();
      } else {
        _pulseCtrl.stop();
        _shimmerCtrl.stop();
      }
      _barCtrl.repeat(); // essential: indeterminate progress
      if ((prev == null || prev == _StepState.pending) && !reduceMotion) {
        _wakeCtrl.forward(from: 0.0);
      }
    } else {
      _pulseCtrl.stop();
      _barCtrl.stop();
      _shimmerCtrl.stop();
    }
    if (state == _StepState.done) {
      if (prev != _StepState.done) {
        if (reduceMotion) {
          _fillCtrl.value = 1.0;
        } else {
          _fillCtrl.forward(from: 0.0);
        }
      }
    } else {
      _fillCtrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _barCtrl.dispose();
    _shimmerCtrl.dispose();
    _wakeCtrl.dispose();
    _fillCtrl.dispose();
    super.dispose();
  }

  Color get _accent {
    switch (widget.step.state) {
      case _StepState.done:
        return const Color(0xFF47C97A);
      case _StepState.failed:
        return const Color(0xFFFF6565);
      case _StepState.inProgress:
        return widget.colors.accent;
      case _StepState.pending:
        return widget.colors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final state = widget.step.state;
    final accent = _accent;

    Widget badgeContent;
    switch (state) {
      case _StepState.pending:
        badgeContent =
            Icon(Icons.bolt_rounded, size: 14.sp, color: c.textTertiary);
        break;
      case _StepState.inProgress:
        badgeContent = Icon(Icons.bolt_rounded, size: 14.sp, color: accent);
        break;
      case _StepState.done:
        badgeContent = Icon(Icons.check_rounded, size: 14.sp, color: accent);
        break;
      case _StepState.failed:
        badgeContent = Icon(Icons.close_rounded, size: 14.sp, color: accent);
        break;
    }

    final badge = AnimatedBuilder(
      animation: Listenable.merge([_pulseCtrl, _wakeCtrl, _fillCtrl]),
      builder: (_, child) {
        // Continuous breathing pulse while in-progress.
        final pulseT = state == _StepState.inProgress
            ? Curves.easeInOut.transform(_pulseCtrl.value)
            : 0.0;
        // One-shot wake-pop when the step starts: 0.86 → 1.18 → 1.0,
        // split into two halves so the springy attack reads clearly
        // before the gentle settle.
        double wakeScale = 1.0;
        if (_wakeCtrl.isAnimating || _wakeCtrl.value > 0) {
          final wt = _wakeCtrl.value;
          if (wt < 0.45) {
            final s = Curves.easeOutBack.transform(wt / 0.45);
            wakeScale = 0.86 + (1.18 - 0.86) * s;
          } else {
            final s = Curves.easeOutCubic.transform((wt - 0.45) / 0.55);
            wakeScale = 1.18 + (1.0 - 1.18) * s;
          }
        }
        // Brief swell when transitioning to done.
        final fillBump = state == _StepState.done && _fillCtrl.value < 1.0
            ? 0.12 * Curves.easeOut.transform(_fillCtrl.value)
            : 0.0;
        final scale = wakeScale * (1.0 + 0.10 * pulseT + fillBump);
        final glowAlpha =
            state == _StepState.pending ? 0.0 : 0.20 + 0.22 * pulseT;
        return Transform.scale(
          scale: scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (state == _StepState.done && _fillCtrl.value < 1.0)
                _DoneBurst(progress: _fillCtrl.value, accent: accent),
              Container(
                width: 26.sp,
                height: 26.sp,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state == _StepState.pending
                      ? c.surfaceLight
                      : accent.withValues(alpha: glowAlpha),
                ),
                child: child,
              ),
            ],
          ),
        );
      },
      child: badgeContent,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26.sp,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge,
                if (!widget.isLast)
                  _AnimatedConnector(
                    height: 28.h,
                    fill: _fillCtrl,
                    activeColor: const Color(0xFF47C97A),
                    idleColor: c.borderSubtle,
                    isDone: state == _StepState.done,
                  ),
              ],
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.step.label,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    if (state == _StepState.inProgress)
                      _LiveDots(controller: _barCtrl, accent: accent)
                    else if (state == _StepState.done)
                      Text(
                        context.l10n.done,
                        style: TextStyle(
                          color: accent,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  widget.step.error ?? widget.step.detail,
                  style: TextStyle(
                    color: widget.step.error != null
                        ? const Color(0xFFFF6565)
                        : c.textTertiary,
                    fontSize: 13.sp,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 8.h),
                _StepProgressBar(
                  state: state,
                  controller: _barCtrl,
                  shimmerController: _shimmerCtrl,
                  fillController: _fillCtrl,
                  accent: accent,
                  trackColor: c.surfaceLight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical connector between two steps. While the upper step is
/// pending/in-progress it renders as a flat idle line; when that step
/// transitions to done we drive a top-to-bottom fill animation in the
/// active color (driven by the row's `_fillCtrl`) with a soft glow head
/// so it reads as "drawing" rather than just growing.
class _AnimatedConnector extends StatelessWidget {
  final double height;
  final AnimationController fill;
  final Color activeColor;
  final Color idleColor;
  final bool isDone;

  const _AnimatedConnector({
    required this.height,
    required this.fill,
    required this.activeColor,
    required this.idleColor,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: fill,
      builder: (_, __) {
        final t = isDone ? Curves.easeOutCubic.transform(fill.value) : 0.0;
        return SizedBox(
          width: 2,
          height: height,
          child: Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: CustomPaint(
              painter: _ConnectorPainter(
                progress: t,
                idle: idleColor,
                active: activeColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  final double progress;
  final Color idle;
  final Color active;

  _ConnectorPainter({
    required this.progress,
    required this.idle,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final idlePaint = Paint()..color = idle;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(1),
      ),
      idlePaint,
    );
    if (progress <= 0) return;
    final fillHeight = size.height * progress;
    final activePaint = Paint()..color = active;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, fillHeight),
        const Radius.circular(1),
      ),
      activePaint,
    );
    if (progress < 1.0) {
      final headRect = Rect.fromLTWH(
        -1.5,
        (fillHeight - 3).clamp(0.0, size.height),
        size.width + 3,
        6,
      );
      final headPaint = Paint()
        ..color = active.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(headRect, const Radius.circular(2)),
        headPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.progress != progress || old.idle != idle || old.active != active;
}

/// Three-dot bouncing indicator that replaces the static "Working…"
/// label during in-progress. Each dot rises on a staggered phase off
/// the same controller so motion reads as continuous rather than
/// repetitive.
class _LiveDots extends StatelessWidget {
  final AnimationController controller;
  final Color accent;
  const _LiveDots({required this.controller, required this.accent});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (controller.value + i * 0.18) % 1.0;
            final eased = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0);
            final alpha = 0.30 + 0.70 * eased;
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : 4.w),
              child: Transform.translate(
                offset: Offset(0, -2 * eased),
                child: Container(
                  width: 5.sp,
                  height: 5.sp,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: alpha),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// One-shot ring that expands outward when a step lands in done so the
/// completion gets a visible "tap" rather than a silent state swap.
class _DoneBurst extends StatelessWidget {
  final double progress;
  final Color accent;
  const _DoneBurst({required this.progress, required this.accent});

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    final size = 26.sp + 22.sp * eased;
    final alpha = (1.0 - eased) * 0.55;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accent.withValues(alpha: alpha),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

class _StepProgressBar extends StatelessWidget {
  final _StepState state;
  final AnimationController controller;
  final AnimationController shimmerController;
  final AnimationController fillController;
  final Color accent;
  final Color trackColor;

  const _StepProgressBar({
    required this.state,
    required this.controller,
    required this.shimmerController,
    required this.fillController,
    required this.accent,
    required this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final h = 6.h;
    if (state == _StepState.pending) {
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(3.r),
        ),
      );
    }
    if (state == _StepState.done) {
      // Animate the done bar in: sweep a 100 %-fill across the track
      // L→R using fillController, then settle into the solid green.
      return ClipRRect(
        borderRadius: BorderRadius.circular(3.r),
        child: SizedBox(
          height: h,
          child: AnimatedBuilder(
            animation: fillController,
            builder: (_, __) {
              final t = Curves.easeOutCubic.transform(fillController.value);
              return CustomPaint(
                painter: _DoneBarPainter(
                  progress: t,
                  trackColor: trackColor,
                  accent: accent,
                ),
              );
            },
          ),
        ),
      );
    }
    if (state == _StepState.failed) {
      return Container(
        height: h,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(3.r),
        ),
      );
    }
    // In-progress — two layered slides + a faster shimmer overlay so the
    // bar reads as actively working rather than a single repeating beat.
    return ClipRRect(
      borderRadius: BorderRadius.circular(3.r),
      child: SizedBox(
        height: h,
        child: AnimatedBuilder(
          animation: Listenable.merge([controller, shimmerController]),
          builder: (_, __) => CustomPaint(
            painter: _SlidingBarPainter(
              progress: controller.value,
              shimmerProgress: shimmerController.value,
              trackColor: trackColor,
              accent: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlidingBarPainter extends CustomPainter {
  final double progress;
  final double shimmerProgress;
  final Color trackColor;
  final Color accent;

  _SlidingBarPainter({
    required this.progress,
    required this.shimmerProgress,
    required this.trackColor,
    required this.accent,
  });

  void _drawSlide(Canvas canvas, Size size, double t, double widthFraction,
      double maxAlpha) {
    final segWidth = size.width * widthFraction;
    final travel = size.width + segWidth;
    final x = -segWidth + (t * travel);
    final rect = Rect.fromLTWH(x, 0, segWidth, size.height);
    final shader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        accent.withValues(alpha: 0.0),
        accent.withValues(alpha: maxAlpha),
        accent.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = trackColor;
    canvas.drawRect(Offset.zero & size, trackPaint);

    // Soft underlying tint so the track doesn't sit dead between slides.
    final basePaint = Paint()..color = accent.withValues(alpha: 0.10);
    canvas.drawRect(Offset.zero & size, basePaint);

    // Primary sliding lozenge — wide and bright.
    _drawSlide(canvas, size, progress, 0.42, 1.0);

    // Trailing companion slide — narrower, half-phase offset, dimmer —
    // so two lights chase across the track instead of one.
    final t2 = (progress + 0.55) % 1.0;
    _drawSlide(canvas, size, t2, 0.22, 0.55);

    // Faster shimmer slice on its own controller — adds a third
    // rhythm so the motion reads as layered rather than mechanical.
    _drawSlide(canvas, size, shimmerProgress, 0.12, 0.85);
  }

  @override
  bool shouldRepaint(covariant _SlidingBarPainter old) =>
      old.progress != progress ||
      old.shimmerProgress != shimmerProgress ||
      old.accent != accent ||
      old.trackColor != trackColor;
}

/// Bar painter for the done state — animates a bright accent fill
/// sweeping L→R across the track, leaving solid green behind. Used
/// once per step transition into done, then settles to the solid bar.
class _DoneBarPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color accent;

  _DoneBarPainter({
    required this.progress,
    required this.trackColor,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
    final filled = Rect.fromLTWH(0, 0, size.width * progress, size.height);
    canvas.drawRect(filled, Paint()..color = accent);
    // Bright leading-edge highlight while the sweep is still in motion.
    if (progress > 0 && progress < 1.0) {
      final headWidth = (size.width * 0.18).clamp(8.0, 40.0);
      final headX = (size.width * progress) - headWidth;
      final rect = Rect.fromLTWH(headX, 0, headWidth, size.height);
      final shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accent.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.65),
        ],
      ).createShader(rect);
      canvas.drawRect(rect, Paint()..shader = shader);
    }
    // Settled state — solid accent at slightly reduced alpha to match
    // the "completed" calmness of the rest of the row.
    if (progress >= 1.0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = accent.withValues(alpha: 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DoneBarPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.trackColor != trackColor;
}

/// Top-of-card overall progress bar that animates between fractional
/// values as steps land AND runs a continuous shimmer along the filled
/// portion while the orchestrator is mid-flight. Two concurrent
/// motions:
///   - **Fill**: `TweenAnimationBuilder` glides between fractional
///     values (e.g. step 0 done → 0.5 → step 1 in-progress → 0.75)
///     over 600ms easeOutCubic so the bar morphs smoothly between
///     beats.
///   - **Shimmer**: while `isActive` is true, an `AnimationController`
///     drives a moving highlight across the filled segment so the
///     bar reads as actively working rather than a static slab.
class _OverallProgressBar extends StatefulWidget {
  final double progress;
  final bool isFailed;
  final bool isActive;
  final Color trackColor;
  final Color accent;

  const _OverallProgressBar({
    required this.progress,
    required this.isFailed,
    required this.isActive,
    required this.trackColor,
    required this.accent,
  });

  @override
  State<_OverallProgressBar> createState() => _OverallProgressBarState();
}

class _OverallProgressBarState extends State<_OverallProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      // ~1100 ms feels lively without strobing; the stripes phase by a
      // single period per loop so the motion is continuous rather than
      // jumpy at the wrap.
      duration: const Duration(milliseconds: 1100),
    );
    // The shimmer is a decorative "actively working" highlight on top
    // of the progress fill; start it in didChangeDependencies so it can
    // honour Reduce Motion (MediaQuery isn't ready here).
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncShimmer();
  }

  /// Start/stop the decorative shimmer based on `isActive` AND the OS
  /// Reduce Motion preference. The bar's fill fraction (the actual
  /// progress data) is unaffected.
  void _syncShimmer() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.isActive && !reduceMotion) {
      if (!_shimmerCtrl.isAnimating) _shimmerCtrl.repeat();
    } else if (_shimmerCtrl.isAnimating) {
      _shimmerCtrl.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _OverallProgressBar old) {
    super.didUpdateWidget(old);
    _syncShimmer();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isFailed ? const Color(0xFFFF6565) : widget.accent;
    // Bumped from 8 → 12 px so the barber-pole stripes have room to
    // read; the bar still looks restrained inside the steps card.
    return ClipRRect(
      borderRadius: BorderRadius.circular(6.r),
      child: SizedBox(
        height: 12.h,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: widget.progress),
          // Snap to the new fill instantly under Reduce Motion — the
          // bar still shows the correct progress fraction, just without
          // the gliding transition between beats.
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, fillT, __) {
            return AnimatedBuilder(
              animation: _shimmerCtrl,
              builder: (_, __) {
                return CustomPaint(
                  painter: _OverallProgressPainter(
                    fill: fillT.clamp(0.0, 1.0),
                    shimmerProgress: _shimmerCtrl.value,
                    isActive: widget.isActive,
                    trackColor: widget.trackColor,
                    accent: color,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _OverallProgressPainter extends CustomPainter {
  final double fill;
  final double shimmerProgress;
  final bool isActive;
  final Color trackColor;
  final Color accent;

  _OverallProgressPainter({
    required this.fill,
    required this.shimmerProgress,
    required this.isActive,
    required this.trackColor,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Track.
    canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);

    if (fill <= 0) return;
    final filledWidth = size.width * fill;
    final filledRect = Rect.fromLTWH(0, 0, filledWidth, size.height);

    // Base fill — soft gradient so the bar has a hint of depth.
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          accent.withValues(alpha: 0.75),
          accent,
        ],
      ).createShader(filledRect);
    canvas.drawRect(filledRect, basePaint);

    // Skip overlays when the filled segment is too narrow to render
    // them — also dodges clamp's `min <= max` precondition during the
    // fill tween's brief 0 → target interpolation.
    if (!isActive || filledWidth < 8.0) return;

    canvas.save();
    canvas.clipRect(filledRect);

    // Layer 1 — barber-pole stripes. Diagonal white slashes that slide
    // left-to-right at a constant rate. The classic "this is doing
    // something" affordance: impossible to read as static.
    _drawStripes(canvas, filledWidth, size.height);

    // Layer 2 — bright sweeping highlight. Wider, brighter than before
    // (alpha 0.75 vs the previous 0.55) so the bar reads as actively
    // working even at a glance.
    final segWidth = (filledWidth * 0.42).clamp(8.0, filledWidth);
    final travel = filledWidth + segWidth;
    final x = -segWidth + (shimmerProgress * travel);
    final shimmerRect = Rect.fromLTWH(x, 0, segWidth, size.height);
    final shimmerShader = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.75),
        Colors.white.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.5, 1.0],
    ).createShader(shimmerRect);
    canvas.drawRect(shimmerRect, Paint()..shader = shimmerShader);

    canvas.restore();
  }

  /// Draws diagonal white slashes that slide L→R across the filled
  /// portion. Stripe period = ~22 px, angle = ~30°, alpha 0.22 so the
  /// motion reads as texture rather than a competing pattern. We use
  /// `shimmerProgress` to phase-shift the entire pattern each frame.
  void _drawStripes(Canvas canvas, double width, double height) {
    const stripePeriod = 22.0;
    const stripeWidth = 8.0;
    // Skew Y for the diagonal — moving up-right as we go right.
    const skew = 0.55;
    final phaseShift = shimmerProgress * stripePeriod;
    final stripePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    // Start a bit before the visible region so the leading stripe
    // enters cleanly; iterate until well past the right edge.
    var x = -stripePeriod * 2 + phaseShift;
    while (x < width + stripePeriod) {
      final path = Path()
        ..moveTo(x, height)
        ..lineTo(x + stripeWidth, height)
        ..lineTo(x + stripeWidth + height * skew, 0)
        ..lineTo(x + height * skew, 0)
        ..close();
      canvas.drawPath(path, stripePaint);
      x += stripePeriod;
    }
  }

  @override
  bool shouldRepaint(covariant _OverallProgressPainter old) =>
      old.fill != fill ||
      old.shimmerProgress != shimmerProgress ||
      old.isActive != isActive ||
      old.accent != accent ||
      old.trackColor != trackColor;
}

/// The unit selector beside the send amount, in the Move sheet's currency
/// pill chrome: surface fill, hairline border, 48 minimum height, icon and
/// code, a chevron when it can be changed.
/// "Details" disclosure on the failed-send overlay: closed by default,
/// opens to the raw engine message with a copy action for support.
class _SendFailureDetails extends StatefulWidget {
  final String raw;
  const _SendFailureDetails({required this.raw});

  @override
  State<_SendFailureDetails> createState() => _SendFailureDetailsState();
}

class _SendFailureDetailsState extends State<_SendFailureDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _expanded = !_expanded);
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 10.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.details,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
                SizedBox(width: 2.w),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18.sp,
                  color: c.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(top: 6.h),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // In full: the confirmation scrolls, so a long engine
                  // message is never cut off before the part that matters.
                  Text(
                    widget.raw,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () async {
                        await Clipboard.setData(
                            ClipboardData(text: widget.raw));
                        if (!context.mounted) return;
                        showMessageSnackBarInfo(
                            context: context, message: context.l10n.copied);
                      },
                      borderRadius: BorderRadius.circular(8.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 6.w, vertical: 4.h),
                        child: Text(
                          context.l10n.copy,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The unit pill beside the amount hero, shared with the dollar send.
typedef _AmountUnitPill = SendAmountUnitPill;
