import 'package:kute/models/evm_derivation_version.dart';
import 'dart:io';
import 'dart:math';
import 'package:kute/screens/creation/bitcoin_wallet_setup.dart';
import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/add_wallet_provider.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/add_wallet_capabilities.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class AddWallet extends ConsumerStatefulWidget {
  const AddWallet({super.key});

  @override
  ConsumerState<AddWallet> createState() => _AddWalletState();
}

class _AddWalletState extends ConsumerState<AddWallet> {
  bool _isCreating = false;

  /// Hub-level funnel state. The hub owns `wallet_add_abandoned` only
  /// while nothing has been picked: once a row leads to a method screen,
  /// that screen owns its own abandon, so one drop-off never counts twice.
  final Stopwatch _flowClock = Stopwatch()..start();
  bool _optionPicked = false;
  bool _completed = false;
  String? _lastErrorCategory;

  @override
  void initState() {
    super.initState();
    TrackingService.setFlowContext(flow: 'wallet_add', step: 'choose_type');
    TrackingService.track('wallet_add_step', params: {
      'step': 'choose_type',
      'has_spending_wallet':
          ref.read(settingsProvider).wallets.any((w) => w.isSparkWallet),
    });
    // Impression analytics: we track *taps* on each coming-soon row
    // (`add_wallet_coming_soon_tapped`), but without an impression
    // event we can't compute a real interest rate (taps / views).
    // Fire once on screen entry. Run in a microtask so it doesn't
    // block the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.screenView('add_wallet');
      TrackingService.track('add_wallet_coming_soon_seen', params: {
        'features': 'open_banking,exchange_import,wallet_connect',
      });
    });
  }

  @override
  void dispose() {
    if (!_optionPicked && !_completed) {
      TrackingService.track('wallet_add_abandoned', params: {
        'step': 'choose_type',
        'time_in_flow_bucket': _timeInFlowBucket(_flowClock.elapsed),
        'reason': _lastErrorCategory != null ? 'error' : 'user_closed',
        if (_lastErrorCategory != null)
          'last_error_category': _lastErrorCategory!,
      });
      TrackingService.clearFlowContext('wallet_add');
    }
    super.dispose();
  }

  /// A row that leads somewhere (method screen or the inline create).
  void _pick(String typeId) {
    TrackingService.walletTypeSelected(typeId);
    _optionPicked = true;
  }

  Future<void> _createWalletDirectly() async {
    // Extends walletAddStarted(): this path commits on the tap.
    TrackingService.track('wallet_add_started', params: {
      'import_method': 'create',
      'wallet_kind': 'hot',
    });
    TrackingService.setFlowStep('creating');
    // Every generated spending wallet is named "Spending Wallet" —
    // no per-wallet variation, no id suffix. Matches the
    // passkey_choice path (which already used this name) and the
    // one-spending-wallet architecture: the user has at most one
    // and never needs to disambiguate it from another spending
    // wallet, so the static name is the cleanest read.
    await _handleCreateSparkWallet('Spending Wallet');
  }

  Future<void> _handleCreateSparkWallet(String walletName) async {
    setState(() => _isCreating = true);
    try {
      final authModel = ref.read(authModelProvider);

      if (!ref.read(sessionUnlockedProvider)) {
        TrackingService.track('wallet_add_failed', params: {
          'reason': 'session_locked',
          'stage': 'precheck',
          'import_method': 'create',
          'wallet_kind': 'hot',
        });
        if (mounted) {
          showMessageSnackBar(context: context, message: context.l10n.pleaseSetUpPINFirst, error: true);
          context.push('/set_pin');
        }
        return;
      }

      final walletId = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      final mnemonic = await authModel.generateMnemonic();
      await authModel.setMnemonic(walletId, mnemonic);

      final newWallet = WalletConfig(
        id: walletId,
        name: walletName,
        sparkEnabled: true,
        evmDerivationVersion: EvmDerivationVersion.standardBip39,
        backedUp: false,
      );

      await ref.read(settingsProvider.notifier).addWallet(newWallet);
      await ref.read(settingsProvider.notifier).setActiveWallet(newWallet.id);

      // Set up Polymarket account in background (Safe deploy + credentials)
      provisionPolymarketAccount(mnemonic: mnemonic, walletId: walletId, evmDerivationVersion: EvmDerivationVersion.standardBip39);

      TrackingService.walletCreated(type: 'new');
      TrackingService.walletAdded(
        walletKind: 'hot',
        importMethod: 'create',
        network: 'spark',
        source: 'add_wallet',
      );
      TrackingService.setWalletProperties(walletType: 'new', walletCount: ref.read(settingsProvider).wallets.length);
      _completed = true;
      TrackingService.clearFlowContext('wallet_add');

      if (mounted) context.go('/home');
    } catch (e) {
      // Extends walletAddFailed(): same `reason`, plus a fixed category.
      final category = TrackingService.errorCategory(e);
      _lastErrorCategory = category;
      TrackingService.track('wallet_add_failed', params: {
        'reason': e.runtimeType.toString(),
        'error_category': category,
        'stage': 'create',
        'import_method': 'create',
        'wallet_kind': 'hot',
      });
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, e,
                fallback: context.l10n.errorCopyCreateWallet),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  bool _checkingOption = false;

  /// Whether the option of [type] may start its flow. A withheld one (or
  /// one the policy cannot vouch for) starts nothing: no scan, no pairing,
  /// no import screen. It opens the shared unavailable sheet with the
  /// policy's own reason instead. The option itself is never hidden.
  Future<bool> _offered(String type) async {
    if (_checkingOption || _isCreating) return false;
    _checkingOption = true;
    try {
      final denial = await addWalletOptionDenial(
          ref.read(runtimeCapabilitiesProvider), type);
      if (denial == null) return true;
      if (mounted) await showCapabilityDecisionSheet(context, denial);
      return false;
    } finally {
      _checkingOption = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addWalletProvider);
    final notifier = ref.read(addWalletProvider.notifier);

    // Hide Spark hot wallet options when the user already has one.
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
    final hasHotWallet = wallets.any(
        (w) => w.isSparkWallet);

    // Every option is drawn whatever the policy says; a withheld one is
    // refused at the tap by [_offered]. See
    // lib/services/add_wallet_capabilities.dart.
    final coldWallets = state.coldWallets;
    final trackingWallets = state.trackingWallets;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        leading: KuteBackButton(
          onPressed: () {
            if (_isCreating) return;
            HapticFeedback.lightImpact();
            context.pop();
          },
        ),
        title: Text(
          context.l10n.addWallet,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            // Ambient Glow (dark mode only)
            if (context.isDark)
              Positioned(
                top: -100.h, left: 0, right: 0, height: 400.h,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter, radius: 1.0,
                      colors: [context.colors.surfaceLight.withValues(alpha:0.4), Colors.transparent],
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: SafeArea(
                bottom: Platform.isAndroid,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 32.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header block (title + subtitle) intentionally
                      // removed — the AppBar back button already frames the
                      // screen; sections start straight away.
                      SizedBox(height: 8.h),

                      // Each section is a grouped card: header above,
                      // one AppDecorations.card surface with hairline
                      // dividers between rows — the same floating-card
                      // chrome as recover_choice and the Investments
                      // screen.
                      if (!hasHotWallet) ...[
                        _SectionHeader(title: context.l10n.walletsSpendingAccountSection),
                        _GroupedCard(
                          children: [
                            for (final wallet in state.hotWallets)
                              _SelectionCard(
                                config: wallet,
                                isDisabled: _isCreating,
                                onTap: () {
                                  // The inline create stays on this
                                  // screen, so the hub keeps owning
                                  // its abandon.
                                  if (wallet.id == 'create_spark') {
                                    TrackingService.walletTypeSelected(
                                        wallet.id);
                                  } else {
                                    _pick(wallet.id);
                                  }
                                  notifier.selectWallet(
                                      wallet.id, wallet.type);
                                  if (wallet.id == 'create_spark') {
                                    _createWalletDirectly();
                                  } else if (wallet.id == 'recover_spark') {
                                    context.push('/recover_wallet');
                                  }
                                },
                              ),
                          ],
                        ),
                        SizedBox(height: 20.h),
                      ],

                      // Separate sections — distinct user mental
                      // models. Hardware = "I have a device".
                      // Watch = "I want read-only
                      // visibility on a public address". Each header
                      // gives the section its own meaning rather than
                      // bundling everything under a generic "connect"
                      // umbrella.
                      if (coldWallets.isNotEmpty) ...[
                      _SectionHeader(title: context.l10n.walletsHardwareWalletsSection),
                      _GroupedCard(
                        children: [
                          for (final option in coldWallets)
                            _SelectionCard(
                              config: option,
                              isDisabled: _isCreating,
                              onTap: () async {
                                if (!await _offered(option.type)) return;
                                if (!context.mounted) return;
                                _pick(option.id);
                                notifier.selectWallet(option.id, option.type);
                                context.pushNamed('importXpub');
                              },
                            ),
                        ],
                      ),
                      ],
                      if (trackingWallets.isNotEmpty) ...[
                        SizedBox(height: 20.h),
                        _SectionHeader(title: context.l10n.walletsWatchAnAddressSection),
                        _GroupedCard(
                          children: [
                            for (final wallet in trackingWallets)
                              _SelectionCard(
                                config: wallet,
                                isDisabled: _isCreating,
                                onTap: () async {
                                  if (!await _offered(wallet.type)) return;
                                  if (!context.mounted) return;
                                  _pick(wallet.id);
                                  notifier.selectWallet(
                                      wallet.id, wallet.type);
                                  context.pushNamed(
                                      'importExternalAddress');
                                },
                              ),
                          ],
                        ),
                      ],

                      SizedBox(height: 20.h),
                      _SectionHeader(title: context.l10n.walletTypeBitcoin),
                      _GroupedCard(children: [
                        _SelectionCard(
                          config: const WalletDeviceConfig(id: 'bitcoin', type: 'bitcoin',
                            title: 'Bitcoin wallet', subtitle: 'Create or recover with 12 words',
                            importTitle: 'Bitcoin wallet',
                            icon: Icons.currency_bitcoin_rounded, color: Color(0xFFF7931A),
                            svgAsset: 'lib/assets/bitcoin-icon.svg'),
                          isDisabled: _isCreating,
                          onTap: () async {
                            if (!await _offered('bitcoin')) return;
                            if (!context.mounted) return;
                            _pick('bitcoin');
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const BitcoinWalletSetup()));
                          },
                        ),
                      ]),
                      SizedBox(height: 20.h),
                      _SectionHeader(title: context.l10n.comingSoon2),
                      _GroupedCard(
                        children: [
                          _ComingSoonRow(
                            title: context.l10n.walletsBank,
                            icon: BootstrapIcons.bank2,
                            onTap: () {
                              TrackingService.comingSoonViewed(
                                  feature: 'open_banking');
                              TrackingService.track(
                                  'add_wallet_coming_soon_tapped',
                                  params: {'feature': 'open_banking'});
                              showMessageSnackBar(
                                context: context,
                                message: context.l10n.walletsBankConnectionsComingSoon,
                                error: false,
                              );
                            },
                          ),
                          _ComingSoonRow(
                            title: context.l10n.walletsExchange,
                            icon: BootstrapIcons.currency_exchange,
                            onTap: () {
                              TrackingService.comingSoonViewed(
                                  feature: 'exchange_import');
                              TrackingService.track(
                                  'add_wallet_coming_soon_tapped',
                                  params: {'feature': 'exchange_import'});
                              showMessageSnackBar(
                                context: context,
                                message: context.l10n.walletsExchangeImportComingSoon,
                                error: false,
                              );
                            },
                          ),
                          _ComingSoonRow(
                            title: context.l10n.walletsWalletConnect,
                            icon: Icons.wifi_rounded,
                            onTap: () {
                              TrackingService.comingSoonViewed(
                                  feature: 'wallet_connect');
                              TrackingService.track(
                                  'add_wallet_coming_soon_tapped',
                                  params: {'feature': 'wallet_connect'});
                              showMessageSnackBar(
                                context: context,
                                message: context.l10n.walletsWalletConnectComingSoon,
                                error: false,
                              );
                            },
                          ),
                          _ComingSoonRow(
                            title: context.l10n.walletsNostrWalletConnect,
                            icon: Icons.bolt_rounded,
                            onTap: () {
                              TrackingService.comingSoonViewed(
                                  feature: 'nostr_wallet_connect');
                              TrackingService.track(
                                  'add_wallet_coming_soon_tapped',
                                  params: {
                                    'feature': 'nostr_wallet_connect'
                                  });
                              showMessageSnackBar(
                                context: context,
                                message:
                                    context.l10n.walletsNostrWalletConnectComingSoon,
                                error: false,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_isCreating)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha:0.7),
                  child: Center(child: LoadingAnimationWidget.staggeredDotsWave(color: context.colors.accent, size: 40)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Single rounded card that wraps a list of rows with hairline
/// dividers between them. Uses the app's card language
/// (AppDecorations.card): a floating shadow card in light mode,
/// a hairline-bordered surface in dark — same chrome as the
/// recover-choice cards and the redesigned Investments screen.
class _GroupedCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupedCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          // Rows sit flush inside the one card, with no hairline
          // between them.
          children: [...children],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    // Same 22sp w800 as the home Activity / Portfolio section
    // headers, with the open_investments rhythm: 12 below the
    // header, 20 between sections (the spacers in the build).
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h, left: 4.w),
      child: Text(
        title,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 22.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          height: 1.1,
        ),
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final WalletDeviceConfig config;
  final VoidCallback onTap;
  final bool isDisabled;

  const _SelectionCard({
    required this.config,
    required this.onTap,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
        child: Opacity(
          opacity: isDisabled ? 0.4 : 1.0,
          child: Padding(
            // Single-line rows: title only, vertically centered
            // against the 44sp tile — subtitles live in the config
            // model for the connect screens, but this list reads
            // cleaner as pure product names. 8.h vertical padding
            // lands the row at ~60 tall.
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DeviceTile(
                  svgAsset: config.svgAsset,
                  icon: config.icon,
                  color: config.color,
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Text(config.titleIn(context.l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16.5.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3)),
                ),
                if (config.venueBadges.isNotEmpty) ...[
                  SizedBox(width: 8.w),
                  _VenueBadges(assets: config.venueBadges),
                ],
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Venue logos before the chevron (Ledger row only, Phase 4 P4.2). One
/// Semantics node names the venues; the images themselves are excluded.
class _VenueBadges extends StatelessWidget {
  final List<String> assets;
  const _VenueBadges({required this.assets});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.ledgerVenueIconsLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < assets.length; i++) ...[
            if (i > 0) SizedBox(width: 4.w),
            SvgPicture.asset(assets[i], width: 18.sp, height: 18.sp),
          ],
        ],
      ),
    );
  }
}

/// Neutral leading tile for the device rows: surfaceLight ground,
/// hairline border, 12 radius — no pastel/tinted fills. Brand SVGs
/// render with their own colors on the neutral ground; monochrome
/// marks (Ledger ships white/near-black) are tinted to textPrimary
/// so they read in both themes. IconData fallbacks keep the brand
/// color as the glyph tint only, never as a background.
class _DeviceTile extends StatelessWidget {
  final String? svgAsset;
  final IconData icon;
  final Color color;

  const _DeviceTile({
    required this.svgAsset,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isMonochrome =
        color == Colors.white || color == const Color(0xFF333333);
    final glyphColor = isMonochrome ? c.textPrimary : color;

    // Wide wordmarks (SeedSigner ships a pill wordmark, not a
    // square emblem) get extra width so they carry the same
    // optical weight as the square marks at 25sp.
    final isWide = svgAsset != null && svgAsset!.contains('seedsigner');

    return Container(
      width: 44.sp,
      height: 44.sp,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: svgAsset != null
          ? SvgPicture.asset(
              svgAsset!,
              width: isWide ? 34.sp : 25.sp,
              height: 25.sp,
              colorFilter: isMonochrome
                  ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
                  : null,
            )
          : Icon(icon, color: glyphColor, size: 22.sp),
    );
  }
}

/// Compact "Coming soon" row used at the bottom of the Add Wallet
/// screen. Visually quieter than `_SelectionCard` (no chevron,
/// muted text, "Soon" pill) so the user reads it as a preview, not
/// an active path. Tap fires a `coming_soon_viewed` analytic and a
/// snack message — never navigates.
class _ComingSoonRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ComingSoonRow({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          child: Row(
            children: [
              // Same neutral tile treatment as the active device
              // rows, with the glyph muted to match the quiet tone.
              Container(
                width: 44.sp,
                height: 44.sp,
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: c.borderSubtle, width: 0.5),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: c.textSecondary, size: 20.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 16.5.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3)),
              ),
              SizedBox(width: 8.w),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: c.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  context.l10n.walletsSoon,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `time_in_flow_bucket` for `wallet_add_abandoned`.
String _timeInFlowBucket(Duration d) {
  final s = d.inSeconds;
  if (s < 10) return '<10s';
  if (s < 30) return '10-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  return '10m+';
}
