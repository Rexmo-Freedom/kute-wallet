import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/helpers/seed_clipboard.dart';
import 'package:kute/helpers/stored_seed_reveal.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/screens/ledger/ledger_investment_gate.dart'
    show ledgerAnyVenueAllowed;
import 'package:kute/providers/ledger/ledger_identity_provider.dart'
    show ledgerVenueDescriptorStoreProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketDepositWalletAddressProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/evm_wallet_derivation.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/theme/app_theme.dart';

/// Per-wallet key material reveal — replaces the home card's old
/// tap-to-flip back side. Lists every wallet on device; tapping a row
/// opens the right reveal for its type:
///   - Spark / hot wallet → existing `/backup_wallet` seed-reveal flow.
///   - Hardware / watch-only → inline xpub view.
///   - External address → inline address view.
///
/// Below the list, "Investing and Predictions" shows the EVM account for
/// the spending wallet (Hyperliquid address, Polymarket deposit wallet,
/// the Polymarket signer, which is the same EOA, and that EOA's private
/// key behind the same seed reveal grant as the recovery phrase) and, for
/// a Ledger with a device-verified EVM address, the addresses only.
///
/// Each recovery phrase reveal needs that wallet's seed reveal grant
/// (biometric first, Kute PIN fallback), kept until the screen closes
/// (spec 4.1 Keys). Xpubs and tracked addresses are public data and ride
/// the unlocked session.
class WalletsScreen extends ConsumerStatefulWidget {
  const WalletsScreen({super.key});

  @override
  ConsumerState<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends ConsumerState<WalletsScreen> {
  /// Seed reveal grants this screen issued, revoked on dispose. A live
  /// grant reused from another open screen is left to that screen.
  final List<AuthGrant> _ownedGrants = [];

  /// Holds a copied recovery phrase or private key; clears it after 60 s or
  /// when the screen closes, only if the clipboard still holds it.
  final SeedClipboard _keyClipboard = SeedClipboard();

  @override
  void dispose() {
    for (final grant in _ownedGrants) {
      AuthGrantRegistry.instance.revokeSeedReveal(grant);
    }
    _keyClipboard.dispose();
    super.dispose();
  }

  /// Asks for, or reuses, the seed reveal grant for [wallet]. False when
  /// the user declined.
  Future<bool> _ensureRevealGrant(WalletConfig wallet) async {
    final existing = AuthGrantRegistry.instance.seedRevealGrantFor(wallet.id);
    final grant =
        await requireSeedRevealGrant(context, ref, walletId: wallet.id);
    if (grant == null) return false;
    if (!mounted) {
      if (!identical(grant, existing)) {
        AuthGrantRegistry.instance.revokeSeedReveal(grant);
      }
      return false;
    }
    if (!identical(grant, existing)) _ownedGrants.add(grant);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Signers ARE included — they hold a mnemonic and the user
    // needs to be able to back it up the same way they do for the
    // spending wallet.
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
    final spendingId =
        ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
    // The spending wallet's EOA is the Investing and Predictions account.
    // A Ledger shows its device-verified EVM address. Watch-only and
    // other wallets have no EVM account the app knows about.
    final evmWallets = [
      for (final w in wallets)
        // A Ledger's venue addresses only while a Ledger venue is on.
        if (w.id == spendingId || (w.hasVerifiedEvm && ledgerAnyVenueAllowed()))
          w,
    ];
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        leading: const KuteBackButton(),
        title: Text(context.l10n.settingsBackupAndRecovery,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            )),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
        children: [
          if (wallets.isNotEmpty)
            _WalletGroup(
              children: [
                for (final w in wallets)
                  _WalletTile(
                    wallet: w,
                    ensureRevealGrant: _ensureRevealGrant,
                    keyClipboard: _keyClipboard,
                  ),
              ],
            ),
          if (evmWallets.isNotEmpty) ...[
            SizedBox(height: 24.h),
            _SectionTitle(context.l10n.walletsInvestingAndPredictions),
            for (final w in evmWallets) ...[
              if (evmWallets.length > 1)
                _GroupCaption(
                    w.name.isNotEmpty ? w.name : context.l10n.accountWallet),
              _EvmAccountGroup(
                wallet: w,
                isSpending: w.id == spendingId,
                ensureRevealGrant: _ensureRevealGrant,
                keyClipboard: _keyClipboard,
              ),
              if (w != evmWallets.last) SizedBox(height: 16.h),
            ],
          ],
        ],
      ),
    );
  }
}

/// One card for the whole wallet list with hairline dividers between
/// rows — the grouped-card pattern from add_wallet's `_GroupedCard`,
/// instead of a stack of separate cards.
class _WalletGroup extends StatelessWidget {
  final List<Widget> children;
  const _WalletGroup({required this.children});

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

class _WalletTile extends ConsumerWidget {
  final WalletConfig wallet;

  /// Asks for, or reuses, the seed reveal grant for a wallet.
  final Future<bool> Function(WalletConfig wallet) ensureRevealGrant;
  final SeedClipboard keyClipboard;

  const _WalletTile({
    required this.wallet,
    required this.ensureRevealGrant,
    required this.keyClipboard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No subtitle: the leading mark already says what kind of wallet it is.
    return _KeyRow(
      key: ValueKey('wallets-wallet-${wallet.id}'),
      leading: _WalletTypeTile(wallet: wallet),
      title: wallet.name.isNotEmpty ? wallet.name : context.l10n.accountWallet,
      onTap: () {
        HapticFeedback.lightImpact();
        // Which kind of row and which reveal it leads to. Never the
        // wallet's name, id or any key material.
        TrackingService.track('wallets_wallet_row_tapped', params: {
          'wallet_kind': TrackingService.walletKind(
            isLedger: wallet.isLedger,
            isHardware: wallet.isHardware,
            isWatchOnly: wallet.isWatchOnly,
            isSigner: wallet.isSigner,
            isExternalAddress: wallet.isExternalAddress,
          ),
          'material_type': wallet.isExternalAddress
              ? 'tracked_address'
              : (wallet.isHardware || wallet.isWatchOnly)
                  ? 'xpub'
                  : 'recovery_phrase',
        });
        if (wallet.isExternalAddress) {
          _showExternalAddress(context, wallet);
        } else if (wallet.isHardware || wallet.isWatchOnly) {
          _showXpub(context, wallet);
        } else {
          // Spending wallet (or signer): show the raw recovery phrase
          // after the seed reveal step-up for this wallet.
          _showRecoveryPhrase(
              context, ref, wallet, ensureRevealGrant, keyClipboard);
        }
      },
    );
  }
}

/// One row of a grouped card on this screen: 44sp leading mark, title,
/// optional secondary subtitle and a chevron. Shared by the wallet list and
/// the Investing and Predictions rows so both read as one list. A null
/// [onTap] drops the chevron (nothing to open yet). A subtitle never
/// carries an address or any other key material.
class _KeyRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _KeyRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              leading,
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle case final subtitle?) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                SizedBox(width: 8.w),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 20.sp),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The wallet's own mark in a 44sp leading slot: vendor logo, Bitcoin
/// mark or the mascot, bare with no tile behind it (user decision).
class _WalletTypeTile extends StatelessWidget {
  final WalletConfig wallet;
  const _WalletTypeTile({required this.wallet});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visual = WalletVisual.fromWallet(
      walletType: wallet.walletType,
      isHardware: wallet.isHardware,
      isWatchOnly: wallet.isWatchOnly || wallet.isExternalAddress,
      isSigner: wallet.isSigner,
      isDark: context.isDark,
    );
    final svg = visual.svgAsset;
    final mono =
        visual.color == Colors.white || visual.color == const Color(0xFF333333);
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Center(
        child: svg != null
            ? SvgPicture.asset(
                svg,
                width: 32.sp,
                height: 32.sp,
                fit: BoxFit.contain,
                colorFilter: mono
                    ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
                    : null,
              )
            : Icon(visual.icon, color: visual.color, size: 28.sp),
      ),
    );
  }
}

Future<void> _showRecoveryPhrase(
  BuildContext context,
  WidgetRef ref,
  WalletConfig w,
  Future<bool> Function(WalletConfig wallet) ensureRevealGrant,
  SeedClipboard keyClipboard,
) async {
  final read = await _revealMnemonic(context, ref, w, ensureRevealGrant,
      materialType: 'recovery_phrase');
  if (read == null || !context.mounted) return;
  showAppBottomSheet(
    context: context,
    builder: (ctx) => RecoveryPhraseSheet(
      phrase: read.mnemonic,
      onCopy: keyClipboard.copy,
    ),
  );
}

/// The seed reveal gate every phrase-derived reveal on this screen goes
/// through: the wallet's seed reveal grant (biometric first, Kute PIN
/// fallback), then the phrase read, then a recheck that the session, the
/// grant and the wallet are all still the ones the user approved.
///
/// Null when the user declined or anything changed underneath; otherwise
/// the trimmed phrase, which is itself null when none is stored.
Future<({String? mnemonic})?> _revealMnemonic(
  BuildContext context,
  WidgetRef ref,
  WalletConfig w,
  Future<bool> Function(WalletConfig wallet) ensureRevealGrant, {
  required String materialType,
}) async {
  // Nothing is read before the grant (spec 4.1 Keys).
  if (!await ensureRevealGrant(w)) {
    TrackingService.track('secure_key_material_reveal_cancelled',
        params: {'material_type': materialType, 'stage': 'auth'});
    return null;
  }
  if (!context.mounted) return null;
  final grant = AuthGrantRegistry.instance.seedRevealGrantFor(w.id);
  TrackingService.secureKeyMaterialViewed(materialType: materialType);
  String? mnemonic;
  try {
    if (w.isPasskey) {
      // Passkey seeds may come from the device-local cache or PRF recovery.
      // This is a mnemonic-REVEAL surface, so the vintage rule
      // is absolute: a legacy (passkeyProvider == null) wallet
      // reconstructs ONLY via the 0.15.1 PRF pipeline inside
      // getMnemonic — never a new-SDK signIn, which could resolve a
      // different credential and show words that don't control the
      // funds. Pass the wallet's own label so a multi-wallet user sees
      // THIS wallet's phrase, not the last-cached one's.
      mnemonic = await PasskeyService.getMnemonic(
        label: w.passkeyLabel,
        legacy: w.passkeyProvider == null,
      );
    } else {
      final read = await readStoredSeedInteractive(context, ref, w.id,
          pinTitle: context.l10n.enterPinToViewRecoveryPhrase,
          analyticsSurface: 'wallets');
      mnemonic = read is SeedOk ? read.value : null;
    }
  } catch (_) {/* surfaced via fallback message below */}
  if (!context.mounted) return null;
  if (!ref.read(sessionUnlockedProvider) ||
      !seedRevealGrantCovers(grant, w.id) ||
      !ref.read(settingsProvider).wallets.any((wallet) =>
          wallet.id == w.id &&
          wallet.isPasskey == w.isPasskey &&
          wallet.passkeyLabel == w.passkeyLabel &&
          wallet.passkeyProvider == w.passkeyProvider &&
          wallet.evmDerivationVersion == w.evmDerivationVersion)) {
    TrackingService.track('secure_key_material_reveal_cancelled',
        params: {'material_type': materialType, 'stage': 'state_changed'});
    return null;
  }
  final phrase = mnemonic?.trim();
  if (phrase?.isEmpty ?? true) {
    // The "no recovery phrase" state. Categorical only.
    TrackingService.track('secure_key_material_unavailable',
        params: {'material_type': materialType});
  }
  return (mnemonic: (phrase?.isEmpty ?? true) ? null : phrase);
}

Future<void> _showExternalAddress(BuildContext context, WalletConfig w) async {
  TrackingService.secureKeyMaterialViewed(materialType: 'tracked_address');
  final addr = await AuthModel().getExternalAddress(w.id);
  if (!context.mounted) return;
  final l10n = context.l10n;
  showAppBottomSheet(
    context: context,
    builder: (ctx) => _RevealSheet(
      title: l10n.walletsTrackedAddress,
      data: addr ?? l10n.walletsNoAddressStored,
      warning: l10n.walletsSafeToShareViewOnly,
      materialType: 'tracked_address',
    ),
  );
}

Future<void> _showXpub(BuildContext context, WalletConfig w) async {
  TrackingService.secureKeyMaterialViewed(materialType: 'xpub');
  final xpub = await AuthModel().getExtendedPublicKey(w.id);
  if (!context.mounted) return;
  final l10n = context.l10n;
  showAppBottomSheet(
    context: context,
    builder: (ctx) => _RevealSheet(
      title: l10n.walletPublicKey,
      data: (xpub?.trim().isEmpty ?? true)
          ? l10n.walletsNoXpubStored
          : xpub!.trim(),
      warning: l10n.walletsXpubSafeToShare,
      materialType: 'xpub',
      truncate: true,
    ),
  );
}

class _RevealSheet extends StatefulWidget {
  final String title;
  final String data;
  final String warning;
  final String materialType; // 'xpub', 'tracked_address' or 'evm_address'

  /// Replaces the generic copy event, for rows that emit their own.
  final VoidCallback? onCopied;

  /// Show the value middle-truncated with a "Show full key" affordance.
  /// The QR code and Copy always use the full value.
  final bool truncate;
  const _RevealSheet({
    required this.title,
    required this.data,
    required this.warning,
    required this.materialType,
    this.truncate = false,
    this.onCopied,
  });

  @override
  State<_RevealSheet> createState() => _RevealSheetState();
}

class _RevealSheetState extends State<_RevealSheet> {
  bool _showFull = false;

  bool get _truncated =>
      widget.truncate && !_showFull && widget.data.length > 32;

  String get _display {
    final data = widget.data;
    if (!_truncated) return data;
    return '${data.substring(0, 14)}…${data.substring(data.length - 14)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final data = widget.data;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBottomSheetHeader(title: widget.title),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: buildQrCode(data, context),
                  ),
                ),
                SizedBox(height: 14.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: c.borderSubtle, width: 0.5),
                  ),
                  child: SelectableText(
                    _display,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 14.sp,
                      height: 1.5,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                if (_truncated)
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppTextButton(
                      text: l10n.walletPublicKeyShowFull,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        TrackingService.track('wallet_public_key_full_shown');
                        setState(() => _showFull = true);
                      },
                    ),
                  ),
                SizedBox(height: 14.h),
                Text(
                  widget.warning,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 20.h),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: l10n.copy,
                        variant: AppButtonVariant.secondary,
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await Clipboard.setData(ClipboardData(text: data));
                          final onCopied = widget.onCopied;
                          if (onCopied != null) {
                            onCopied();
                          } else {
                            TrackingService.secureKeyMaterialCopied(
                              materialType: widget.materialType,
                            );
                          }
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          showMessageSnackBar(
                            context: context,
                            message: l10n.copied,
                            error: false,
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: AppButton(
                        text: l10n.done,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recovery phrase reveal (D-16). The words are plain text with no text
/// selection; the one way to the clipboard is Copy, which goes through
/// [onCopy] (a [SeedClipboard]: sensitive, local-only, cleared after 60 s).
/// The QR code appears only after an explicit tap. The sheet is a
/// [SecureScreen]. A null [phrase] shows the "no recovery phrase" note.
class RecoveryPhraseSheet extends StatefulWidget {
  const RecoveryPhraseSheet({
    super.key,
    required this.phrase,
    required this.onCopy,
  });

  final String? phrase;

  /// Puts the phrase on the clipboard, which clears itself later.
  final Future<void> Function(String phrase) onCopy;

  @override
  State<RecoveryPhraseSheet> createState() => _RecoveryPhraseSheetState();
}

class _RecoveryPhraseSheetState extends State<RecoveryPhraseSheet> {
  bool _qrRevealed = false;

  Future<void> _copy() async {
    final phrase = widget.phrase;
    if (phrase == null) return;
    HapticFeedback.lightImpact();
    await widget.onCopy(phrase);
    TrackingService.seedPhraseCopied(surface: 'wallets');
    if (!mounted) return;
    final l10n = context.l10n;
    Navigator.of(context).pop();
    showMessageSnackBar(
      context: context,
      message: l10n.recoveryPhraseCopied,
      error: false,
    );
  }

  void _revealQr() {
    HapticFeedback.lightImpact();
    TrackingService.walletsQrRevealed();
    setState(() => _qrRevealed = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final phrase = widget.phrase;
    return SecureScreen(
      surface: 'wallets',
      child: AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBottomSheetHeader(title: l10n.recoveryPhrase),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (phrase != null && _qrRevealed) ...[
                    SecureContent(
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: buildQrCode(phrase, context),
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),
                  ],
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: c.borderSubtle, width: 0.5),
                    ),
                    child: phrase == null
                        ? Text(
                            l10n.walletsNoRecoveryPhraseStored,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14.sp,
                              height: 1.5,
                            ),
                          )
                        : SecureContent(
                            child: Text(
                              phrase,
                              key: const ValueKey('wallets-recovery-phrase'),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontFamily: 'monospace',
                                fontSize: 14.sp,
                                height: 1.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(height: 14.h),
                  Text(
                    l10n.walletsNeverShareWordsPlain,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  if (phrase != null) ...[
                    AppButton(
                      key: const ValueKey('wallets-copy-phrase'),
                      text: l10n.copy,
                      icon: Icons.copy_rounded,
                      variant: AppButtonVariant.secondary,
                      onPressed: _copy,
                    ),
                    SizedBox(height: 12.h),
                  ],
                  Row(
                    children: [
                      if (phrase != null && !_qrRevealed) ...[
                        Expanded(
                          child: AppButton(
                            key: const ValueKey('wallets-show-qr'),
                            text: l10n.walletsShowQr,
                            variant: AppButtonVariant.secondary,
                            onPressed: _revealQr,
                          ),
                        ),
                        SizedBox(width: 12.w),
                      ],
                      Expanded(
                        child: AppButton(
                          text: l10n.done,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Investing and Predictions ───────────────────────

/// Section title, the same mixed-case 22sp w800 header Settings uses.
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h, left: 4.w),
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

/// Names the wallet a group belongs to when more than one wallet has an
/// EVM account (the spending wallet and a verified Ledger).
class _GroupCaption extends StatelessWidget {
  final String text;
  const _GroupCaption(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h, left: 4.w),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// The Ledger's Polymarket account as last resolved by
/// `ledgerPmAccountProvider`, read from the public descriptor cache. No
/// network; null until the Ledger's Predictions tab has resolved it once.
final _ledgerPmAddressProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, walletId) async {
  try {
    final descriptor =
        await ref.read(ledgerVenueDescriptorStoreProvider).read(walletId);
    return descriptor?.pmAddress;
  } catch (_) {
    return null;
  }
});

/// A venue logo or a mono icon in the same 44sp leading slot as
/// [_WalletTypeTile].
class _VenueMark extends StatelessWidget {
  final String? svgAsset;
  final IconData? icon;
  const _VenueMark.svg(String asset)
      : svgAsset = asset,
        icon = null;
  const _VenueMark.icon(IconData data)
      : svgAsset = null,
        icon = data;

  @override
  Widget build(BuildContext context) {
    final svg = svgAsset;
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Center(
        child: svg != null
            ? SvgPicture.asset(svg,
                width: 32.sp, height: 32.sp, fit: BoxFit.contain)
            : Icon(icon, color: context.colors.textPrimary, size: 28.sp),
      ),
    );
  }
}

/// The EVM account of one wallet, as three rows: the Investing &
/// Predictions key (the EOA at m/44'/60'/0'/0/0, derived from the
/// recovery phrase, separate from the bitcoin keys), the Investing
/// account (Hyperliquid, the same address as the key) and the Predictions
/// wallet (the Polymarket deposit wallet, a smart wallet that key owns
/// and signs for). The spending wallet's key row opens its private key
/// behind the seed reveal grant. A verified Ledger shows addresses only.
class _EvmAccountGroup extends ConsumerWidget {
  final WalletConfig wallet;
  final bool isSpending;
  final Future<bool> Function(WalletConfig wallet) ensureRevealGrant;
  final SeedClipboard keyClipboard;

  const _EvmAccountGroup({
    required this.wallet,
    required this.isSpending,
    required this.ensureRevealGrant,
    required this.keyClipboard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final String? eoa;
    final String? pmAddress;
    if (isSpending) {
      eoa = ref.watch(hyperliquidAddressProvider).valueOrNull;
      pmAddress = ref
          .watch(polymarketDepositWalletAddressProvider(wallet.id))
          .valueOrNull;
    } else {
      eoa = wallet.evmAddress;
      pmAddress = ref.watch(_ledgerPmAddressProvider(wallet.id)).valueOrNull;
    }
    final walletKind = isSpending ? 'hot' : 'ledger';

    VoidCallback? open(
            String? address, String venue, String title, String note) =>
        address == null
            ? null
            : () => _showEvmAddress(context,
                venue: venue,
                walletKind: walletKind,
                title: title,
                address: address,
                note: note);

    void showPrivateKey() {
      HapticFeedback.lightImpact();
      TrackingService.track('settings_private_key_opened');
      showAppBottomSheet(
        context: context,
        builder: (ctx) => PrivateKeySheet(
          reveal: (sheetContext) => _revealEvmPrivateKey(
            sheetContext,
            ref,
            wallet,
            ensureRevealGrant,
            expectedAddress: eoa,
          ),
          onCopy: keyClipboard.copy,
        ),
      );
    }

    return _WalletGroup(
      children: [
        // The one key behind both venues, separate from the bitcoin keys.
        // A phrase-backed wallet opens its private key behind the seed
        // reveal grant; a Ledger never has a key to show, so it opens the
        // address instead.
        _KeyRow(
          key: ValueKey('wallets-evm-key-${wallet.id}'),
          leading: const _VenueMark.icon(Icons.key_rounded),
          title: l10n.walletsEvmKey,
          // The spending wallet's row opens its private key, so it says
          // which key format the wallet uses: a standard key opens the same
          // account from the phrase in MetaMask, an older one only from the
          // private key. Never wallet-specific data, only the format line.
          subtitle: isSpending
              ? (wallet.evmDerivationVersion ==
                      EvmDerivationVersion.standardBip39
                  ? l10n.walletsEvmFormatStandard
                  : l10n.walletsEvmFormatLegacy)
              : eoa == null
                  ? l10n.walletsEvmNotSetUp
                  : null,
          onTap: isSpending
              ? showPrivateKey
              : open(eoa, 'hyperliquid', l10n.walletsInvestingAccount,
                  l10n.walletsInvestingAccountNote),
        ),
        _KeyRow(
          key: ValueKey('wallets-evm-hyperliquid-${wallet.id}'),
          leading: const _VenueMark.svg('lib/assets/hyperliquid-logo.svg'),
          title: l10n.walletsInvestingAccount,
          subtitle: eoa == null ? l10n.walletsEvmNotSetUp : null,
          onTap: open(eoa, 'hyperliquid', l10n.walletsInvestingAccount,
              l10n.walletsInvestingAccountNote),
        ),
        _KeyRow(
          key: ValueKey('wallets-evm-polymarket-${wallet.id}'),
          leading: const _VenueMark.svg('lib/assets/polymarket-logo.svg'),
          title: l10n.walletsPredictionsWallet,
          subtitle: pmAddress == null ? l10n.walletsEvmNotSetUp : null,
          onTap: open(pmAddress, 'polymarket', l10n.walletsPredictionsWallet,
              l10n.walletsPredictionsWalletNote),
        ),
      ],
    );
  }
}

void _showEvmAddress(
  BuildContext context, {
  required String venue,
  required String walletKind,
  required String title,
  required String address,
  required String note,
}) {
  HapticFeedback.lightImpact();
  // Never the address itself: only which row was used.
  final params = <String, Object>{'venue': venue, 'wallet_kind': walletKind};
  TrackingService.track('settings_evm_address_viewed', params: params);
  showAppBottomSheet(
    context: context,
    builder: (ctx) => _RevealSheet(
      title: title,
      data: address,
      warning: note,
      materialType: 'evm_address',
      onCopied: () =>
          TrackingService.track('settings_evm_address_copied', params: params),
    ),
  );
}

/// Runs the same seed reveal gate as the recovery phrase, then derives
/// account zero's key locally. Null when the user declined. Throws when
/// no phrase could be read or the derived EOA is not the account the app
/// uses ([expectedAddress]), so a key that does not control the funds is
/// never shown. Nothing here is logged, persisted or sent anywhere.
Future<String?> _revealEvmPrivateKey(
  BuildContext context,
  WidgetRef ref,
  WalletConfig w,
  Future<bool> Function(WalletConfig wallet) ensureRevealGrant, {
  String? expectedAddress,
}) async {
  final read = await _revealMnemonic(context, ref, w, ensureRevealGrant,
      materialType: 'evm_private_key');
  if (read == null) return null;
  final mnemonic = read.mnemonic;
  if (mnemonic == null) throw StateError('No recovery phrase');
  final account = await EvmWalletDerivation.accountZeroKey(
      mnemonic: mnemonic, version: w.evmDerivationVersion);
  if (expectedAddress != null &&
      account.address.toLowerCase() != expectedAddress.toLowerCase()) {
    throw StateError('EVM account mismatch');
  }
  TrackingService.track('settings_private_key_revealed');
  return account.privateKey;
}

/// Private key reveal for the spending wallet's EVM account. Hidden until
/// the user taps Show key and passes the seed reveal gate; the warning is
/// on screen before that. The key lives only in this sheet's state and is
/// dropped when the sheet closes. The sheet is a [SecureScreen] and the
/// key a [SecureContent], like the recovery phrase. Once revealed, a tap
/// on Show QR code adds the key's QR, also inside a [SecureContent].
class PrivateKeySheet extends StatefulWidget {
  const PrivateKeySheet({
    super.key,
    required this.reveal,
    required this.onCopy,
  });

  /// Runs the gate and derives the key. Null when the user declined;
  /// throws when the key could not be read.
  final Future<String?> Function(BuildContext context) reveal;

  /// Puts the key on the clipboard, which clears itself later.
  final Future<void> Function(String key) onCopy;

  @override
  State<PrivateKeySheet> createState() => _PrivateKeySheetState();
}

class _PrivateKeySheetState extends State<PrivateKeySheet> {
  String? _key;
  bool _busy = false;
  bool _failed = false;
  bool _qrRevealed = false;

  @override
  void dispose() {
    _key = null;
    _qrRevealed = false;
    super.dispose();
  }

  /// The QR of the revealed key, only after an explicit tap, like the
  /// recovery phrase's. It encodes exactly the key on screen, which
  /// MetaMask's Import account scanner accepts. No event: the reveal is
  /// already tracked and the key never goes anywhere.
  void _revealQr() {
    if (_key == null) return;
    HapticFeedback.lightImpact();
    setState(() => _qrRevealed = true);
  }

  Future<void> _reveal() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() {
      _busy = true;
      _failed = false;
    });
    String? key;
    var failed = false;
    try {
      key = await widget.reveal(context);
    } catch (e) {
      failed = true;
      // Fixed categories from _revealEvmPrivateKey, never the message.
      final msg = e is StateError ? e.message : '';
      TrackingService.track('settings_private_key_reveal_failed', params: {
        'reason': msg == 'No recovery phrase'
            ? 'no_phrase'
            : msg == 'EVM account mismatch'
                ? 'account_mismatch'
                : 'unknown',
      });
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _key = key;
      _failed = failed;
    });
  }

  Future<void> _copy() async {
    final key = _key;
    if (key == null) return;
    HapticFeedback.lightImpact();
    await widget.onCopy(key);
    TrackingService.track('settings_private_key_copied');
    if (!mounted) return;
    final l10n = context.l10n;
    Navigator.of(context).pop();
    showMessageSnackBar(
      context: context,
      message: l10n.walletsPrivateKeyCopied,
      error: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final key = _key;
    return SecureScreen(
      surface: 'wallets',
      child: AppBottomSheetContainer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBottomSheetHeader(title: l10n.walletsPrivateKey),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (key != null && _qrRevealed) ...[
                    SecureContent(
                      child: Center(
                        key: const ValueKey('wallets-private-key-qr'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          child: buildQrCode(key, context),
                        ),
                      ),
                    ),
                    SizedBox(height: 14.h),
                  ],
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: c.borderSubtle, width: 0.5),
                    ),
                    child: key == null
                        ? Text(
                            _failed
                                ? l10n.walletsPrivateKeyUnavailable
                                : '•' * 24,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 14.sp,
                              height: 1.5,
                            ),
                          )
                        : SecureContent(
                            child: Text(
                              key,
                              key: const ValueKey('wallets-private-key'),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontFamily: 'monospace',
                                fontSize: 14.sp,
                                height: 1.5,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(height: 14.h),
                  Text(
                    l10n.walletsPrivateKeyWarning,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  if (key != null && !_qrRevealed) ...[
                    AppButton(
                      key: const ValueKey('wallets-show-private-key-qr'),
                      text: l10n.walletsShowQr,
                      variant: AppButtonVariant.secondary,
                      onPressed: _revealQr,
                    ),
                    SizedBox(height: 12.h),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: key == null
                            ? AppButton(
                                key: const ValueKey('wallets-show-private-key'),
                                text: l10n.walletsShowPrivateKey,
                                variant: AppButtonVariant.secondary,
                                isLoading: _busy,
                                onPressed: _busy ? null : _reveal,
                              )
                            : AppButton(
                                key: const ValueKey('wallets-copy-private-key'),
                                text: l10n.copy,
                                variant: AppButtonVariant.secondary,
                                onPressed: _copy,
                              ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: AppButton(
                          text: l10n.done,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
