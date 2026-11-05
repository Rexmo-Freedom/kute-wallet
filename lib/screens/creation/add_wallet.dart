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
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
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
        'time_in_flow_ms': _flowClock.elapsed.inMilliseconds,
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
      // Predictions builds again for the spending wallet as it is now.
      ref
        ..invalidate(polymarketTradingProvider)
        ..invalidate(polymarketBalanceProvider);

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

  /// One option as a card: its mark, its name and one line under it.
  /// Disabled while the spending wallet is being created.
  _OptionCard _optionCard(
    WalletDeviceConfig config, {
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final l10n = context.l10n;
    final title = config.titleIn(l10n);
    return _OptionCard(
      key: ValueKey('add-wallet-option-${config.id}'),
      visual: _OptionMark(
        svgAsset: config.svgAsset,
        icon: config.icon,
        color: config.color,
        venueBadges: config.venueBadges,
      ),
      title: title,
      subtitle: subtitle,
      // The card reads as one node, so it names the venue logos itself.
      semanticsLabel: config.venueBadges.isEmpty
          ? null
          : [title, subtitle, l10n.ledgerVenueIconsLabel].join(', '),
      onTap: _isCreating
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap();
            },
    );
  }

  /// A preview of what is coming, with the "Soon" pill: a tap counts the
  /// interest and says it is coming; it never navigates.
  _OptionCard _comingSoonCard({
    required String feature,
    required String title,
    required IconData icon,
    required String message,
  }) =>
      _OptionCard(
        key: ValueKey('add-wallet-soon-$feature'),
        visual: _OptionMark(icon: icon),
        title: title,
        badge: context.l10n.walletsSoon.toUpperCase(),
        onTap: () {
          HapticFeedback.lightImpact();
          TrackingService.comingSoonViewed(feature: feature);
          TrackingService.track('add_wallet_coming_soon_tapped',
              params: {'feature': feature});
          showMessageSnackBar(context: context, message: message, error: false);
        },
      );

  /// A hardware option (a Bluetooth device or "Other wallet"): once the
  /// policy allows it, the xpub import screen for [option].
  Future<void> _openXpubImport(WalletDeviceConfig option) async {
    if (!await _offered(option.type)) return;
    if (!mounted) return;
    _pick(option.id);
    ref.read(addWalletProvider.notifier).selectWallet(option.id, option.type);
    context.pushNamed('importXpub');
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
    // lib/services/add_wallet_capabilities.dart. Hardware names only the
    // devices that pair natively over Bluetooth; every other signer comes
    // in through "Other wallet" after them.
    final hardwareWallets = state.bluetoothWallets;
    final otherWallet = state.otherWallet;
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

                      // Every option is a card, two side by side, under its
                      // section's header (founder, 4 November 2026: every
                      // option on Add wallet as the square cards, not list
                      // rows), as tall as what it holds ([_OptionCard]).
                      if (!hasHotWallet) ...[
                        _SectionHeader(title: context.l10n.walletsSpendingAccountSection),
                        _OptionGrid(cards: [
                          for (final wallet in state.hotWallets)
                            _optionCard(
                              wallet,
                              subtitle: wallet.subtitleIn(context.l10n),
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
                                notifier.selectWallet(wallet.id, wallet.type);
                                if (wallet.id == 'create_spark') {
                                  _createWalletDirectly();
                                } else if (wallet.id == 'recover_spark') {
                                  context.push('/recover_wallet');
                                }
                              },
                            ),
                        ]),
                        SizedBox(height: 20.h),
                      ],

                      // Hardware = "I have a device": the ones the app
                      // pairs with natively over Bluetooth side by side
                      // (AddWalletState.bluetoothWallets), then "Other
                      // wallet" full width under them, any other signer's
                      // public key by QR code, file or paste.
                      if (hardwareWallets.isNotEmpty || otherWallet != null) ...[
                        _SectionHeader(title: context.l10n.walletsHardwareWalletsSection),
                        _OptionGrid(cards: [
                          for (final option in hardwareWallets)
                            _optionCard(
                              option,
                              subtitle: context.l10n.bluetooth,
                              onTap: () => _openXpubImport(option),
                            ),
                          if (otherWallet != null)
                            _optionCard(
                              otherWallet,
                              subtitle: context.l10n.addWalletOtherSubtitle,
                              onTap: () => _openXpubImport(otherWallet),
                            ),
                        ]),
                        SizedBox(height: 20.h),
                      ],

                      // Bitcoin: another 12-word wallet, and one address
                      // watched (view only), side by side.
                      _SectionHeader(title: context.l10n.bitcoin),
                      _OptionGrid(cards: [
                        _optionCard(
                          _kBitcoinWalletOption,
                          subtitle: _kBitcoinWalletOption.subtitleIn(context.l10n),
                          onTap: () async {
                            if (!await _offered('bitcoin')) return;
                            if (!context.mounted) return;
                            _pick('bitcoin');
                            Navigator.of(context).push(MaterialPageRoute<void>(
                                builder: (_) => const BitcoinWalletSetup()));
                          },
                        ),
                        for (final wallet in trackingWallets)
                          _optionCard(
                            wallet,
                            subtitle: wallet.subtitleIn(context.l10n),
                            onTap: () async {
                              if (!await _offered(wallet.type)) return;
                              if (!context.mounted) return;
                              _pick(wallet.id);
                              notifier.selectWallet(wallet.id, wallet.type);
                              context.pushNamed('importExternalAddress');
                            },
                          ),
                      ]),
                      SizedBox(height: 20.h),
                      _SectionHeader(title: context.l10n.comingSoon2),
                      _OptionGrid(cards: [
                        _comingSoonCard(
                          feature: 'open_banking',
                          title: context.l10n.walletsBank,
                          icon: BootstrapIcons.bank2,
                          message: context.l10n.walletsBankConnectionsComingSoon,
                        ),
                        _comingSoonCard(
                          feature: 'exchange_import',
                          title: context.l10n.walletsExchange,
                          icon: BootstrapIcons.currency_exchange,
                          message: context.l10n.walletsExchangeImportComingSoon,
                        ),
                        _comingSoonCard(
                          feature: 'wallet_connect',
                          title: context.l10n.walletsWalletConnect,
                          icon: Icons.wifi_rounded,
                          message: context.l10n.walletsWalletConnectComingSoon,
                        ),
                        _comingSoonCard(
                          feature: 'nostr_wallet_connect',
                          title: context.l10n.walletsNostrWalletConnect,
                          icon: Icons.bolt_rounded,
                          message:
                              context.l10n.walletsNostrWalletConnectComingSoon,
                        ),
                      ]),
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

/// Lays out Add wallet's [cards] two side by side, the two of a row
/// equally tall. An odd last card (a section's third, "Other wallet" under
/// Ledger and Jade) takes the full width as a compact band
/// ([_OptionCard.wide]), never a square alone in half the width.
class _OptionGrid extends StatelessWidget {
  final List<_OptionCard> cards;
  const _OptionGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    final gap = kKuteActionCardGap.w;
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) children.add(SizedBox(height: gap));
      children.add(i + 1 < cards.length
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  SizedBox(width: gap),
                  Expanded(child: cards[i + 1]),
                ],
              ),
            )
          : cards[i].asWide());
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// One option on Add wallet: the action cards' square
/// (kute_action_cards.dart) with the same surface-1, hairline, radius 20
/// and 16 padding, the 40 mark at the top left, the title (16, w600, two
/// lines), its line (13, textSecondary, two lines), the "Soon" pill and
/// the press spring, but as tall as what it holds rather than the sheets'
/// 170 (founder, 5 November 2026: the squares read tall and empty here).
/// [wide]: the full-width card under a pair, the mark at the left of the
/// title and its line, a chevron at the right, one compact band.
class _OptionCard extends StatelessWidget {
  final Widget visual;
  final String title;
  final String? subtitle;

  /// A pill at the top right ("SOON").
  final String? badge;

  /// The label read out; defaults to the title, its line and the pill.
  final String? semanticsLabel;
  final bool wide;

  /// Null: disabled (0.6 opacity, no press).
  final VoidCallback? onTap;

  const _OptionCard({
    super.key,
    required this.visual,
    required this.title,
    this.subtitle,
    this.badge,
    this.semanticsLabel,
    this.wide = false,
    required this.onTap,
  });

  /// This card laid out full width ([wide]).
  _OptionCard asWide() => _OptionCard(
        key: key,
        visual: visual,
        title: title,
        subtitle: subtitle,
        badge: badge,
        semanticsLabel: semanticsLabel,
        wide: true,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final enabled = onTap != null;
    final line = subtitle;
    final pill = badge;
    final text = <Widget>[
      Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: KuteActionCard.titleStyle(c),
      ),
      if (line != null) ...[
        const SizedBox(height: 4),
        Text(
          line,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: KuteActionCard.subtitleStyle(c),
        ),
      ],
    ];
    final card = Container(
      padding: const EdgeInsets.all(kKuteActionCardPadding),
      decoration: BoxDecoration(
        color: isLight ? c.surfaceLight : c.surface,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: isLight ? c.border : c.borderSubtle, width: 1),
      ),
      child: wide
          ? Row(
              children: [
                SizedBox(height: kKuteActionCardVisualSlot, child: visual),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: text,
                  ),
                ),
                const SizedBox(width: 12),
                if (pill != null)
                  _SoonPill(text: pill)
                else
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: c.textTertiary),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: kKuteActionCardVisualSlot,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                            alignment: Alignment.centerLeft, child: visual),
                      ),
                      if (pill != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: _SoonPill(text: pill),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...text,
              ],
            ),
    );
    return Semantics(
      button: true,
      enabled: enabled ? null : false,
      label: semanticsLabel ??
          [title, if (line != null) line, if (pill != null) pill].join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: KutePressable(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// The action cards' "Soon" pill (the Move pickers' pill).
class _SoonPill extends StatelessWidget {
  final String text;
  const _SoonPill({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 11.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The Bitcoin wallet option (another hot BDK wallet from 12 words).
const _kBitcoinWalletOption = WalletDeviceConfig(
  id: 'bitcoin',
  type: 'bitcoin',
  title: 'Bitcoin wallet',
  subtitle: 'Create or recover with 12 words',
  importTitle: 'Bitcoin wallet',
  icon: Icons.currency_bitcoin_rounded,
  color: Color(0xFFF7931A),
  svgAsset: 'lib/assets/bitcoin-icon.svg',
);

/// The card's mark at the action cards' 40: a brand SVG in its own
/// colours (a monochrome one, Ledger's, takes textPrimary so it reads in
/// both themes), else the icon on a quiet rounded ground, as the deposit
/// pickers draw theirs, the glyph in its brand colour ([color] null: the
/// muted glyph of a coming-soon card). The Ledger card carries its venue
/// logos at the right (Phase 4 P4.2).
class _OptionMark extends StatelessWidget {
  final String? svgAsset;
  final IconData icon;
  final Color? color;
  final List<String> venueBadges;

  const _OptionMark({
    this.svgAsset,
    required this.icon,
    this.color,
    this.venueBadges = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const size = kKuteActionCardVisualSize;
    final isMonochrome =
        color == Colors.white || color == const Color(0xFF333333);
    final asset = svgAsset;
    final Widget mark = asset != null
        ? SvgPicture.asset(
            asset,
            width: size,
            height: size,
            colorFilter: isMonochrome
                ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
                : null,
          )
        : Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.textPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(size * 11 / 36),
            ),
            child: Icon(
              icon,
              size: size * 20 / 36,
              color: color == null
                  ? c.textSecondary
                  : isMonochrome
                      ? c.textPrimary
                      : color,
            ),
          );
    if (venueBadges.isEmpty) return mark;
    // Spread across a square's width; side by side in a wide card's band.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        mark,
        SizedBox(width: 8.w),
        _VenueBadges(assets: venueBadges),
      ],
    );
  }
}

/// Venue logos at the top right of the Ledger card (Phase 4 P4.2). One
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
            SvgPicture.asset(assets[i], width: 20.sp, height: 20.sp),
          ],
        ],
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
