import 'dart:async';
import 'dart:io';

import 'package:kute/services/onchain/native_onchain_service.dart' show OnchainEndpoint;
import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/helpers/auth_grant.dart' show SensitiveAction;
import 'package:kute/helpers/require_fresh_auth.dart'
    show approveLocalAction, biometricsToggleIntent;
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/constants/feature_flags.dart' show showAnalyticsOptOut;
import 'package:kute/services/secure/biometric_pin_policy.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/screens/settings/components/wallet_type_label.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_boxicons/flutter_boxicons.dart';
// ignore: implementation_imports
import 'package:icons_plus/src/flag.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kute/notifications/push_permission.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/transactions_model.dart'
    show Transaction, MempoolAddressTransaction;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidUserFillsProvider;
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/services/transaction_pdf_export.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart' show pickSpendingWallet;
import 'package:kute/services/support_service.dart';
import 'package:kute/services/mempool_address_service.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/kute_back_button.dart';

final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    return await LocalAuthentication().canCheckBiometrics;
  } catch (e) {
    return false;
  }
});

/// The runtime capabilities behind Settings surfaces. Each one withheld
/// hides its surface outright (and its search entry and deep link):
/// the referral row, the Export section, and the custom Bitcoin server
/// row inside Advanced (the Advanced section itself always shows).
const kReferralCapability = 'affiliate.program';
const kExportCapability = 'export.transactions';
const kAdvancedCapability = 'settings.advanced';

/// The app version as Settings → Advanced shows it: the exact string the
/// app sends to the backend policy request (`appVersion`, the pubspec
/// version without the build number), then the build number.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final build = info.buildNumber.trim();
  return build.isEmpty ? info.version : '${info.version} ($build)';
});

class Settings extends ConsumerStatefulWidget {
  /// When non-null, the screen auto-performs the matching setting's
  /// action right after the first frame (deep-link from unified
  /// search: `context.push('/settings', extra: '<key>')`). The bare
  /// gear tap pushes with no extra → null → no auto-open.
  final String? initialActionKey;

  const Settings({super.key, this.initialActionKey});

  @override
  ConsumerState<Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<Settings> {
  /// The Bitcoin server row lives behind this collapsed Advanced row at
  /// the bottom of the list, like the order slip's trading options.
  bool _showAdvanced = false;

  /// Anchors the biometrics row so a deep-link can scroll it into view
  /// (it's a plain inline toggle with no modal of its own).
  final GlobalKey _biometricsKey = GlobalKey();

  /// Anchors the theme section — also a plain inline toggle with no
  /// modal, so its deep-link scrolls the row into view.
  final GlobalKey _themeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final key = widget.initialActionKey;
    if (key == null) {
      return;
    }
    // The screen is freshly pushed — defer to after first frame so
    // context/Navigator/Scrollable are all attached before we open a
    // modal or scroll over it. Guard with `mounted` (the user could
    // pop before the frame lands).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _dispatchInitialAction(key);
    });
  }

  /// Maps a deep-link key onto the same action its settings row runs.
  void _dispatchInitialAction(String key) {
    // The row/modal event that follows is then attributable to search.
    TrackingService.track('settings_deep_link_opened', params: {'key': key});
    switch (key) {
      case 'pin':
        _openChangePin(context, ref, entrySource: 'deep_link');
        break;
      case 'biometrics':
        _revealBiometrics();
        break;
      case 'theme':
        _openThemeMode(context, ref);
        break;
      case 'language':
        _openLanguagePicker(context, ref);
        break;
      case 'currency':
        _openCurrencyPicker(context, ref);
        break;
      case 'bitcoin_unit':
        _openBitcoinUnitPicker(context, ref);
        break;
      case 'export_transactions':
        // Search already leaves these out while their capability is
        // withheld; a stale deep link must not open them either.
        if (!ref.read(runtimeCapabilitiesProvider).allows(kExportCapability)) {
          break;
        }
        _openTransactionExport(context, ref);
        break;
      case 'electrum_node':
        if (!ref.read(runtimeCapabilitiesProvider).allows(kAdvancedCapability)) {
          break;
        }
        _openElectrumNode(context, ref);
        break;
      case 'rate_app':
        // ignore: discarded_futures
        _rateApp(context, ref);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final biometricsAvailable = ref.watch(biometricsAvailableProvider);
    final c = context.colors;
    // A withheld capability hides its surface outright: never a disabled
    // row, never an unavailable message.
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final showReferral = policy.allows(kReferralCapability);
    final showExport = policy.allows(kExportCapability);
    final showElectrum = policy.allows(kAdvancedCapability);
    // Only a resolved `true` shows the row; loading and error both hide
    // it, exactly as the previous `.when` did.
    final showBiometrics = biometricsAvailable.maybeWhen(
      data: (isAvailable) => isAvailable,
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        leading: const KuteBackButton(),
        title: Text(
          context.l10n.settings,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 40.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 24.h),
                // Each section is one grouped card (AppDecorations.card)
                // with hairline dividers between its rows, the same
                // chrome as the add-wallet device list.
                if (showReferral) ...[
                  _GroupedCard(children: [_buildAffiliateSection(context)]),
                  SizedBox(height: 24.h),
                ],
                _buildSectionHeader(
                    context, context.l10n.settingsSupportAndFeedback),
                // Support lives in Settings now — the home mascot header was
                // replaced by the avatar → Settings nav. Opens live Crisp chat.
                _GroupedCard(children: [
                  _buildSupportSection(context),
                  _buildRateAppSection(context, ref),
                ]),

                SizedBox(height: 24.h),
                _buildSectionHeader(context, context.l10n.security),
                _GroupedCard(children: [
                  _buildWalletsSection(context),
                  _buildChangePinSection(context, ref),
                  if (showBiometrics)
                    KeyedSubtree(
                      key: _biometricsKey,
                      child: _buildBiometricsSection(context, ref),
                    ),
                  _buildAutoLockSection(context, ref),
                  const _NotificationsRow(),
                  // Hidden until it ships (feature_flags.dart).
                  if (showAnalyticsOptOut) _buildAnalyticsSection(context),
                ]),

                SizedBox(height: 24.h),
                _buildSectionHeader(context, context.l10n.preferences),
                _GroupedCard(children: [
                  KeyedSubtree(
                    key: _themeKey,
                    child: _buildThemeModeSection(context, ref),
                  ),
                  _buildLanguageSection(ref, context),
                  _buildCurrencyDenominationSection(ref, context),
                  _buildBitcoinUnitSection(ref, context),
                ]),

                if (showExport) ...[
                  SizedBox(height: 24.h),
                  _buildSectionHeader(context, context.l10n.export),
                  _GroupedCard(children: [
                    _buildTransactionExportSection(context, ref)
                  ]),
                ],

                SizedBox(height: 24.h),
                // Technical settings sit behind one collapsed Advanced row
                // at the bottom. The section always shows, whatever the
                // policy says, so support can always ask for the app
                // version and affiliate id at its top; `settings.advanced`
                // gates only the custom Bitcoin server row inside it.
                _GroupedCard(children: [
                  _SettingsRow(
                    title: context.l10n.advanced,
                    icon: Icons.tune_rounded,
                    subtitle: context.l10n.settingsAdvancedSubtitle,
                    trailing: Icon(
                      _showAdvanced
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: context.colors.textTertiary,
                      size: 22.sp,
                    ),
                    onTap: () {
                      final expanded = !_showAdvanced;
                      TrackingService.track('settings_advanced_toggled',
                          params: {'expanded': expanded});
                      setState(() => _showAdvanced = expanded);
                    },
                  ),
                  if (_showAdvanced) ...[
                    _buildSupportInfoCaption(context),
                    _buildAppVersionRow(context, ref),
                    _buildAffiliateIdRow(context),
                    if (showElectrum) _buildElectrumNodeSection(context, ref),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The small "Support info" caption at the top of the expanded
  /// Advanced section, over the app version and affiliate id rows.
  Widget _buildSupportInfoCaption(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 2.h),
      child: Text(
        context.l10n.settingsSupportInfo,
        style: TextStyle(
          color: context.colors.textTertiary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAppVersionRow(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionLabelProvider).valueOrNull;
    return _SettingsRow(
      title: context.l10n.settingsAppVersion,
      icon: Icons.info_outline_rounded,
      subtitle: version ?? '…',
      trailing: const SizedBox.shrink(),
    );
  }

  /// The id support uses to find this wallet's account (the backend's
  /// affiliate id, from the wallet session). Not a secret; tap to copy.
  Widget _buildAffiliateIdRow(BuildContext context) {
    final id = AffiliateService.affiliateId;
    return _SettingsRow(
      title: context.l10n.settingsAffiliateId,
      icon: Icons.badge_outlined,
      subtitle: id ?? context.l10n.settingsAffiliateIdNotRegistered,
      trailing: id == null
          ? const SizedBox.shrink()
          : Icon(Icons.copy_rounded,
              color: context.colors.textTertiary, size: 20.sp),
      onTap: id == null
          ? null
          : () async {
              await Clipboard.setData(ClipboardData(text: id));
              TrackingService.settingsActionTapped('affiliate_id_copied');
              HapticFeedback.selectionClick();
              if (context.mounted) {
                showMessageSnackBar(
                    context: context,
                    message: context.l10n.copied,
                    error: false);
              }
            },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    // Mixed-case 22sp w800 header to match the rest of the new
    // design language (Activity, Portfolio, More ways to get
    // paid, Add Wallet…). The old ALL-CAPS-letter-spaced label
    // read as a different visual system than the rest of the app.
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

  Widget _buildThemeModeSection(BuildContext context, WidgetRef ref) {
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final currentTheme = ref.watch(settingsProvider.select((s) => s.themeMode));
    final followsSystem = currentTheme == 'system';
    final isDark = currentTheme == 'dark';

    // Two rows that live inside the Preferences grouped card; the
    // divider between them is the card's own hairline so the pair
    // reads as consecutive rows, not a nested block.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsRow(
          title: context.l10n.accountFollowSystemTheme,
          icon: Icons.brightness_auto_rounded,
          subtitle: followsSystem
              ? context.l10n.accountThemeMatchesDevice
              : context.l10n.settingsPickLightOrDarkBelow,
          onTap: () {
            final next = followsSystem
                ? (Theme.of(context).brightness == Brightness.dark
                    ? 'dark'
                    : 'light')
                : 'system';
            settingsNotifier.setThemeMode(next);
            TrackingService.settingsChanged(
                setting: 'theme', value: next, previousValue: currentTheme);
          },
          trailing: _SettingsSwitch(
            value: followsSystem,
            onChanged: (value) {
              HapticFeedback.selectionClick();
              // Turning the toggle OFF needs an explicit theme. Pin to
              // whatever the device is currently showing so the UI
              // doesn't jump on switch-off — the user can then flip
              // the secondary Light/Dark row exposed below.
              final next = value
                  ? 'system'
                  : (Theme.of(context).brightness == Brightness.dark
                      ? 'dark'
                      : 'light');
              settingsNotifier.setThemeMode(next);
              TrackingService.settingsChanged(
                  setting: 'theme', value: next, previousValue: currentTheme);
            },
          ),
        ),
        if (!followsSystem) ...[
          _SettingsRow(
            title: context.l10n.appearance,
            icon: isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
            subtitle: isDark ? context.l10n.darkMode : context.l10n.lightMode,
            onTap: () {
              final newTheme = isDark ? 'light' : 'dark';
              settingsNotifier.setThemeMode(newTheme);
              TrackingService.settingsChanged(
                  setting: 'theme',
                  value: newTheme,
                  previousValue: currentTheme);
            },
            trailing: _SettingsSwitch(
              value: isDark,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                final newTheme = value ? 'dark' : 'light';
                settingsNotifier.setThemeMode(newTheme);
                TrackingService.settingsChanged(
                    setting: 'theme',
                    value: newTheme,
                    previousValue: currentTheme);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Deep-link target for the `theme` key. Theme is a plain inline
  /// toggle (no modal), so the deep-link scrolls the section into view
  /// rather than silently flipping the user's theme.
  void _openThemeMode(BuildContext context, WidgetRef ref) {
    final ctx = _themeKey.currentContext;
    if (ctx == null) {
      return;
    }
    // ignore: discarded_futures
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  Widget _buildChangePinSection(BuildContext context, WidgetRef ref) {
    return _SettingsRow(
      title: context.l10n.appPin,
      icon: Boxicons.bxs_lock_alt,
      subtitle: context.l10n.changeUnlockCode,
      onTap: () => _openChangePin(context, ref),
    );
  }

  void _openChangePin(BuildContext context, WidgetRef ref,
      {String entrySource = 'settings'}) {
    TrackingService.settingsActionTapped('change_pin');
    showAppBottomSheet(
      context: context,
      builder: (context) => ChangePinSheet(entrySource: entrySource),
    );
  }

  /// Deep-link target for the `biometrics` key. The biometrics row is a
  /// plain inline toggle with no modal of its own, so we scroll it into
  /// view rather than flipping the user's setting unexpectedly.
  void _revealBiometrics() {
    final ctx = _biometricsKey.currentContext;
    if (ctx == null) {
      return;
    }
    // ignore: discarded_futures
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  Widget _buildBiometricsSection(BuildContext context, WidgetRef ref) {
    final biometricsEnabled =
        ref.watch(settingsProvider.select((s) => s.biometricsEnabled));

    return _SettingsRow(
      title: context.l10n.biometricUnlock,
      icon: Boxicons.bx_fingerprint,
      subtitle: context.l10n.settingsUnlockWithFaceIdOrTouchId,
      onTap: () => _setBiometrics(!biometricsEnabled),
      trailing: _SettingsSwitch(
        value: biometricsEnabled,
        onChanged: (value) {
          HapticFeedback.selectionClick();
          _setBiometrics(value);
        },
      ),
    );
  }

  bool _biometricsToggleInFlight = false;

  /// The persisted analytics choice, read once; the switch flips it.
  bool _analyticsOptedIn = TrackingService.isOptedIn;
  bool _analyticsToggleInFlight = false;

  Widget _buildAnalyticsSection(BuildContext context) {
    return _SettingsRow(
      title: context.l10n.settingsShareUsageAnalytics,
      icon: Icons.insights_rounded,
      subtitle: context.l10n.settingsShareUsageAnalyticsSubtitle,
      onTap: () => _setAnalytics(!_analyticsOptedIn),
      trailing: _SettingsSwitch(
        value: _analyticsOptedIn,
        onChanged: (value) {
          HapticFeedback.selectionClick();
          _setAnalytics(value);
        },
      ),
    );
  }

  /// Usage analytics only; crash reports are unaffected. No event is sent
  /// about the choice itself.
  Future<void> _setAnalytics(bool optIn) async {
    if (_analyticsToggleInFlight || optIn == _analyticsOptedIn) {
      return;
    }
    _analyticsToggleInFlight = true;
    setState(() => _analyticsOptedIn = optIn);
    try {
      if (optIn) {
        await TrackingService.enableTracking();
      } else {
        await TrackingService.disableTracking();
      }
    } catch (_) {
      // The stored choice is what counts; show it.
      if (mounted) {
        setState(() => _analyticsOptedIn = TrackingService.isOptedIn);
      }
    } finally {
      _analyticsToggleInFlight = false;
    }
  }

  /// D-9: turning biometric unlock on or off needs a fresh approval. The
  /// prompt follows the current setting, so turning it on asks for the
  /// Kute PIN. A declined prompt leaves the setting as it was.
  Future<void> _setBiometrics(bool enable) async {
    if (_biometricsToggleInFlight) {
      return;
    }
    _biometricsToggleInFlight = true;
    try {
      final approved = await approveLocalAction(
        context,
        ref,
        intent: biometricsToggleIntent(enable: enable),
        reason: context.l10n.stepUpReasonBiometrics,
      );
      if (!approved) {
        // The step-up prompt was declined or dismissed; the setting is as
        // it was.
        TrackingService.track('biometrics_toggle_cancelled',
            params: {'enable': enable});
        return;
      }
      if (!mounted) {
        return;
      }
      await ref.read(settingsProvider.notifier).setBiometricsEnabled(enable);
      TrackingService.settingsChanged(
          setting: 'biometrics',
          value: enable.toString(),
          previousValue: (!enable).toString());
      TrackingService.track('biometrics_toggled', params: {'enabled': enable});
    } finally {
      _biometricsToggleInFlight = false;
    }
  }

  /// Auto-lock grace choices, in seconds: how long the app may sit in
  /// the background before the in-place lock overlay engages.
  /// Money-moving actions require fresh auth regardless, which is what
  /// makes the longer graces safe.
  static const List<int> _autoLockChoices = [0, 60, 300];

  String _autoLockLabel(BuildContext context, int seconds) {
    return switch (seconds) {
      0 => context.l10n.autoLockImmediately,
      60 => context.l10n.autoLockAfterOneMinute,
      _ => context.l10n.autoLockAfterFiveMinutes,
    };
  }

  Widget _buildAutoLockSection(BuildContext context, WidgetRef ref) {
    final seconds =
        ref.watch(settingsProvider.select((s) => s.autoLockSeconds));
    return _SettingsRow(
      title: context.l10n.autoLock,
      icon: Boxicons.bx_lock_alt,
      subtitle: _autoLockLabel(context, seconds),
      onTap: () => _openAutoLockPicker(context, ref),
    );
  }

  /// Picker sheet for the auto-lock grace, on the shared Settings picker
  /// chrome; the current choice is the selected row.
  void _openAutoLockPicker(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('auto_lock');
    final current = ref.read(settingsProvider).autoLockSeconds;
    showAppBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return _SettingsPickerSheet(
          title: context.l10n.autoLock,
          rows: [
            for (final seconds in _autoLockChoices)
              AppBottomSheetListTile(
                title: _autoLockLabel(context, seconds),
                isSelected: current == seconds,
                onTap: () {
                  HapticFeedback.selectionClick();
                  if (seconds != current) {
                    TrackingService.settingsChanged(
                        setting: 'auto_lock_seconds',
                        value: seconds.toString(),
                        previousValue: current.toString());
                  }
                  ref
                      .read(settingsProvider.notifier)
                      .setAutoLockSeconds(seconds);
                  context.pop();
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildSupportSection(BuildContext context) {
    return _SettingsRow(
      title: context.l10n.chatWithSupport,
      icon: Icons.support_agent_rounded,
      subtitle: context.l10n.getHelpFromKuteTeam,
      onTap: () {
        HapticFeedback.lightImpact();
        TrackingService.supportOpened(source: 'settings');
        // ignore: discarded_futures
        openSupportChat();
      },
    );
  }

  Widget _buildRateAppSection(BuildContext context, WidgetRef ref) {
    return _SettingsRow(
      title: context.l10n.settingsRateTheApp,
      icon: Boxicons.bxs_star,
      subtitle: context.l10n.settingsLeaveAReview,
      onTap: () => _rateApp(context, ref),
    );
  }

  Future<void> _rateApp(BuildContext context, WidgetRef ref) async {
    TrackingService.settingsActionTapped('rate_app');
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final inAppReview = InAppReview.instance;

    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
      settingsNotifier.setReviewDone(true);
    } else {
      await inAppReview.openStoreListing(
          appStoreId: dotenv.env['APP_STORE_ID']!);
      settingsNotifier.setReviewDone(true);
    }
  }

  Widget _buildAffiliateSection(BuildContext context) {
    // A peer of every other settings row (same row primitive inside a
    // grouped card) rather than a fuller, more pronounced card.
    return _SettingsRow(
      title: context.l10n.settingsReferralProgram,
      icon: Boxicons.bxs_group,
      subtitle: context.l10n.settingsEarnAShareOfFees,
      onTap: () {
        HapticFeedback.lightImpact();
        TrackingService.settingsActionTapped('referral_program');
        context.push('/affiliate');
      },
    );
  }

  Widget _buildTransactionExportSection(BuildContext context, WidgetRef ref) {
    return _SettingsRow(
      title: context.l10n.settingsExportTransactions,
      icon: Icons.table_chart_rounded,
      subtitle: context.l10n.exportActivitySubtitle,
      onTap: () => _openTransactionExport(context, ref),
    );
  }

  void _openTransactionExport(BuildContext context, WidgetRef ref) {
    TrackingService.settingsActionTapped('export_transactions');
    showAppBottomSheet(
      context: context,
      builder: (ctx) => _TransactionExportWalletSelector(
        onExport: (selectedWallets, format, period) {
          _runTransactionExport(context, ref, selectedWallets, format, period);
        },
      ),
    );
  }

  /// Wallets entry — replaces the home card's tap-to-flip seed reveal.
  /// Opens the per-wallet list where the user can view each wallet's
  /// recovery phrase (hot) or xpub (hardware / watch-only).
  Widget _buildWalletsSection(BuildContext context) {
    return _SettingsRow(
      title: context.l10n.settingsBackupAndRecovery,
      icon: Icons.shield_rounded,
      subtitle: context.l10n.settingsBackupAndRecoverySubtitle,
      onTap: () {
        HapticFeedback.lightImpact();
        TrackingService.settingsActionTapped('backup_and_recovery');
        // Auth happens INSIDE the wallets screen on mount — matches the
        // existing seed-words flow (biometric attempt first, falls back to
        // the PIN bottom sheet).
        context.pushNamed('wallets');
      },
    );
  }

  Future<void> _runTransactionExport(
    BuildContext context,
    WidgetRef ref,
    List<settings_model.WalletConfig> selectedWallets,
    ExportFileFormat format,
    ExportPeriodChoice period,
  ) async {
    final settings = ref.read(settingsProvider);
    final originalWalletId = settings.activeWalletId;
    // Captured up-front: status strings are assigned after awaits, where
    // reading l10n off a possibly-unmounted context would be unsafe.
    final l10n = context.l10n;

    // Get BTC price in USD
    double? btcPrice;
    try {
      final btcInUsd = ref.read(selectedCurrencyProvider('USD'));
      btcPrice = btcInUsd.minorUnits.toDouble() / 100.0;
    } catch (_) {}

    // Progress state
    final progressNotifier = ValueNotifier<double>(0.0);
    final statusNotifier = ValueNotifier<String>(l10n.accountPreparingExport);

    // Show loading dialog with progress bar. Same shell as
    // CustomAlertDialog (theme barrier, solid AppDecorations.card) so it
    // reads as the app's one dialog chrome; the bar is the monochrome
    // CTA fill, never the accent.
    if (!context.mounted) {
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: context.colors.modalBarrier,
      builder: (dialogContext) {
        final c = dialogContext.colors;
        return PopScope(
          canPop: false,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: 280.w,
                padding:
                    EdgeInsets.symmetric(horizontal: 28.sp, vertical: 32.sp),
                decoration: AppDecorations.card(dialogContext),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.table_chart_rounded,
                        color: c.textSecondary, size: 36.sp),
                    SizedBox(height: 16.h),
                    Text(
                      dialogContext.l10n.settingsGeneratingReport,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 20.h),
                    // Progress bar
                    ValueListenableBuilder<double>(
                      valueListenable: progressNotifier,
                      builder: (_, progress, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(4.r),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: c.surfaceLight,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              dialogContext.ctaFill),
                          minHeight: 6.h,
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    // Status message
                    ValueListenableBuilder<String>(
                      valueListenable: statusNotifier,
                      builder: (_, status, __) => Text(
                        status,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 14.sp,
                            decoration: TextDecoration.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final walletTransactions = <String, Transaction>{};
      final totalSteps = selectedWallets.length + 1; // wallets + PDF generation

      // Snapshot the original wallet's transactions before any wallet switching,
      // because setActiveWallet() will invalidate transactionNotifierProvider.
      final originalWalletTxData = ref.read(transactionNotifierProvider);

      for (var i = 0; i < selectedWallets.length; i++) {
        final wallet = selectedWallets[i];
        final walletName = wallet.name.isNotEmpty
            ? wallet.name
            : l10n.accountWalletNumber(i + 1);
        statusNotifier.value = l10n.accountLoadingWallet(walletName);
        progressNotifier.value = i / totalSteps;

        // Tracked addresses: fetch from Mempool API directly
        if (wallet.isExternalAddress) {
          try {
            final authModel = AuthModel();
            final address = await authModel.getExternalAddress(wallet.id);
            if (address != null && address.isNotEmpty) {
              statusNotifier.value = l10n.exportCollectingActivity;
              final mempoolTxs =
                  await MempoolAddressService.fetchAddressTransactions(address);
              final txList = mempoolTxs.map((mtx) {
                return MempoolAddressTransaction(
                  id: mtx.txid,
                  timestamp: mtx.blockTime != null
                      ? DateTime.fromMillisecondsSinceEpoch(
                          mtx.blockTime! * 1000)
                      : DateTime.now(),
                  isConfirmed: mtx.confirmed,
                  details: mtx,
                );
              }).toList();
              if (txList.isNotEmpty) {
                walletTransactions[wallet.id] = Transaction(
                  bitcoinTransactions: [],
                  sparkTransactions: [],
                  sparkUnclaimedDeposits: [],
                  mempoolTransactions: txList,
                );
              }
            }
          } catch (e) {
            // Skip tracked addresses that fail to fetch
          }
        } else if (wallet.id == originalWalletId) {
          // Use the snapshot taken before the loop — the live provider may
          // have been invalidated by switching to a different wallet above.
          walletTransactions[wallet.id] = originalWalletTxData;
        } else {
          final cache = ref.read(walletTransactionCacheProvider);
          if (cache.containsKey(wallet.id) &&
              cache[wallet.id]!.allTransactions.isNotEmpty) {
            walletTransactions[wallet.id] = cache[wallet.id]!;
          } else {
            try {
              ref.read(settingsProvider.notifier).setActiveWallet(wallet.id);
              await Future.delayed(const Duration(milliseconds: 200));
              await ref
                  .read(backgroundSyncNotifierProvider.notifier)
                  .gatherTransactionsOnly();
              final txData = ref.read(transactionNotifierProvider);
              if (txData.allTransactions.isNotEmpty) {
                walletTransactions[wallet.id] = txData;
              }
            } catch (e) {
              // Skip wallets that fail to load
            }
          }
        }
      }

      // Switch back to original wallet
      if (originalWalletId != null &&
          ref.read(settingsProvider).activeWalletId != originalWalletId) {
        statusNotifier.value = l10n.exportBuildingReport;
        ref.read(settingsProvider.notifier).setActiveWallet(originalWalletId);
        ref.read(backgroundSyncInProgressProvider.notifier).state = false;
        Future.microtask(() {
          ref.read(backgroundSyncNotifierProvider.notifier).performFullUpdate();
        });
      }

      // Hyperliquid fills — the exact list the Investing history
      // renders (hyperliquidUserFillsProvider). Empty when the user
      // never traded or the address can't resolve; never fatal.
      List<HlFill> hlFills = const [];
      final spendingId = pickSpendingWallet(settings)?.id;
      if (selectedWallets.any((wallet) => wallet.id == spendingId)) {
        try {
          hlFills = await ref.read(hyperliquidUserFillsProvider.future);
        } catch (_) {}
      }

      final (periodStart, periodEnd) = _resolveExportPeriod(period);

      // Build the report
      statusNotifier.value = l10n.exportBuildingReport;
      progressNotifier.value = selectedWallets.length / totalSteps;

      if (format == ExportFileFormat.pdf) {
        await TransactionPdfExport.exportAndShare(
          walletTransactions: walletTransactions,
          wallets: selectedWallets,
          btcFormat: settings.btcFormat,
          currency: settings.currency,
          currentBtcPrice: btcPrice,
          hlFills: hlFills,
          periodStart: periodStart,
          periodEnd: periodEnd,
          l10n: l10n,
        );
      } else {
        await TransactionPdfExport.exportCsv(
          walletTransactions: walletTransactions,
          wallets: selectedWallets,
          btcFormat: settings.btcFormat,
          currentBtcPrice: btcPrice,
          hlFills: hlFills,
          periodStart: periodStart,
          periodEnd: periodEnd,
        );
      }

      // Venue coverage + format only — never amounts.
      final venues = <String>['wallet'];
      if (hlFills.isNotEmpty) {
        venues.add('trading');
      }
      if (walletTransactions.values
          .any((t) => t.polymarketTransactions.isNotEmpty)) {
        venues.add('predictions');
      }
      TrackingService.track('transaction_export_run', params: {
        'format': format.name,
        'period': period.name,
        'venues': venues.join(','),
        'wallet_count': selectedWallets.length,
      });

      progressNotifier.value = 1.0;
      statusNotifier.value = l10n.settingsDone;
      await Future.delayed(const Duration(milliseconds: 300));

      // Dismiss loading dialog
      if (context.mounted) {
        context.pop();
      }
    } catch (e) {
      TrackingService.track('transaction_export_failed', params: {
        'format': format.name,
        'period': period.name,
        'error_category': e.toString().contains('No transactions')
            ? 'no_transactions'
            : TrackingService.errorCategory(e),
      });
      // Ensure we switch back even on error
      if (originalWalletId != null &&
          ref.read(settingsProvider).activeWalletId != originalWalletId) {
        ref.read(settingsProvider.notifier).setActiveWallet(originalWalletId);
        ref.read(backgroundSyncInProgressProvider.notifier).state = false;
        Future.microtask(() {
          ref.read(backgroundSyncNotifierProvider.notifier).performFullUpdate();
        });
      }

      // Dismiss loading dialog
      if (context.mounted) {
        try {
          context.pop();
        } catch (_) {}
      }

      if (context.mounted) {
        showMessageSnackBar(
          context: context,
          message: e.toString().contains('No transactions')
              ? context.l10n.noTransactionsToExport
              : userErrorCopy(context, e, fallback: l10n.errorCopyExport),
          error: true,
        );
      }
    } finally {
      progressNotifier.dispose();
      statusNotifier.dispose();
    }
  }

  Widget _buildLanguageSection(WidgetRef ref, BuildContext context) {
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return _SettingsRow(
      title: context.l10n.language,
      icon: Boxicons.bx_globe,
      subtitle: language.toUpperCase(),
      onTap: () => _openLanguagePicker(context, ref),
    );
  }

  void _openLanguagePicker(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('language');
    showAppBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return _buildLanguageModal(ref, context);
      },
    );
  }

  Widget _buildCurrencyDenominationSection(
      WidgetRef ref, BuildContext context) {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    return _SettingsRow(
      title: context.l10n.displayCurrency,
      icon: Boxicons.bxs_dollar_circle,
      subtitle: currency.toUpperCase(),
      onTap: () => _openCurrencyPicker(context, ref),
    );
  }

  void _openCurrencyPicker(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('currency');
    showAppBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return DenominationChangeModalBottomSheet(
          settingsNotifier: ref.read(settingsProvider.notifier),
          settings: ref.read(settingsProvider),
          initialTab: 'currency',
          showCurrencyOnly: true,
        );
      },
    );
  }

  Widget _buildBitcoinUnitSection(WidgetRef ref, BuildContext context) {
    final btcFormat = ref.watch(settingsProvider.select((s) => s.btcFormat));
    return _SettingsRow(
      title: context.l10n.bitcoinUnit,
      icon: Boxicons.bx_bitcoin,
      subtitle:
          btcFormat == 'sats' ? context.l10n.accountSats : context.l10n.bitcoin,
      onTap: () => _openBitcoinUnitPicker(context, ref),
    );
  }

  void _openBitcoinUnitPicker(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('bitcoin_unit');
    showAppBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return DenominationChangeModalBottomSheet(
          settingsNotifier: ref.read(settingsProvider.notifier),
          settings: ref.read(settingsProvider),
          initialTab: 'denomination',
          showDenominationOnly: true,
        );
      },
    );
  }

  Widget _buildElectrumNodeSection(BuildContext context, WidgetRef ref) {
    final nodeType = ref.watch(settingsProvider.select((s) => s.nodeType));
    // "Default" or "Custom" (or a preset's name), never a host:port.
    final subtitleText = nodeType == 'Custom'
        ? context.l10n.settingsServerCustom
        : nodeType == _defaultNodeType
            ? context.l10n.settingsServerDefault
            : nodeType;

    return _SettingsRow(
      title: context.l10n.electrumNode,
      icon: Boxicons.bxs_server,
      subtitle: subtitleText,
      onTap: () => _openElectrumNode(context, ref),
    );
  }

  void _openElectrumNode(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('electrum_node');
    showAppBottomSheet(
      context: context,
      builder: (_) => _BitcoinServerPicker(
        presets: _electrumNodes,
        defaultNodeType: _defaultNodeType,
        onCustom: () => _showCustomNodeModal(context, ref),
      ),
    );
  }

  void _showCustomNodeModal(BuildContext context, WidgetRef ref) {
    TrackingService.settingsModalOpened('custom_electrum_node');
    showAppBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return const _CustomNodeModalContent();
      },
    );
  }

  Widget _buildLanguageModal(WidgetRef ref, BuildContext context) {
    final currentLanguage =
        ref.watch(settingsProvider.select((s) => s.language));

    // Every shipped language by its native name, in the order of
    // languageNativeNames (alphabetical by native name).
    const flags = {
      'cs': Flags.czech_republic,
      'da': Flags.denmark,
      'de': Flags.germany,
      'et': Flags.estonia,
      'en': Flags.united_kingdom,
      'es': Flags.spain,
      'fr': Flags.france,
      'hr': Flags.croatia,
      'it': Flags.italy,
      'lv': Flags.latvia,
      'lt': Flags.lithuania,
      'hu': Flags.hungary,
      'nl': Flags.netherlands,
      'pl': Flags.poland,
      'pt': Flags.portugal,
      'ro': Flags.romania,
      'sk': Flags.slovakia,
      'sl': Flags.slovenia,
      'fi': Flags.finland,
      'sv': Flags.sweden,
      'el': Flags.greece,
      'bg': Flags.bulgaria,
      'ja': Flags.japan,
    };
    final visibleLanguages = [
      for (final e in languageNativeNames.entries)
        {'code': e.key, 'flag': flags[e.key]!, 'label': e.value},
    ];

    // The shared Settings picker chrome: header with the close X, one
    // AppBottomSheetListTile per language with its flag in the 44 leading
    // slot, the current one selected (check on the trailing side), and
    // the list opening scrolled to it when it is below the fold.
    final selectedKey = GlobalKey();
    return _SettingsPickerSheet(
      title: context.l10n.language,
      selectedKey: selectedKey,
      rows: [
        for (final lang in visibleLanguages)
          AppBottomSheetListTile(
            key: currentLanguage == lang['code'] ? selectedKey : null,
            leading: _FlagMark(lang['flag'] as String),
            title: lang['label'] as String,
            isSelected: currentLanguage == lang['code'],
            onTap: () {
              final code = lang['code'] as String;
              HapticFeedback.selectionClick();
              ref.read(settingsProvider.notifier).setLanguage(code);
              if (code != currentLanguage) {
                TrackingService.settingsChanged(
                    setting: 'language',
                    value: code,
                    previousValue: currentLanguage);
              }
              context.pop();
            },
          ),
      ],
    );
  }

  /// The preset a fresh install uses (settings_provider's default).
  static const String _defaultNodeType = 'Blockstream';

  /// Electrum servers first (they time out and fall over to the next
  /// host; the Esplora client cannot), plus Mempool's Esplora API. Every
  /// Electrum preset serves a certificate a public CA signed: the native
  /// client validates certificates, so a self-signed server (Emzy,
  /// Bitaroo, Aranguren, qtornado were) can never connect from the app.
  /// BlueWallet answers on 443, which passes networks that block the
  /// usual Electrum ports.
  static const List<(String, String, String)> _electrumNodes = [
    ('Blockstream', OnchainEndpoint.defaultMainnet, 'blockstream'),
    ('Mempool', 'https://mempool.space/api', 'mempool'),
    ('BullBitcoin', 'electrum.bullbitcoin.com:50002', 'bullbitcoin'),
    ('ACINQ', 'electrum.acinq.co:50002', 'acinq'),
    ('BlueWallet', 'electrum2.bluewallet.io:443', 'bluewallet'),
    ('Hodlister', 'electrum.hodlister.co:50002', 'hodlister'),
  ];
}

/// Bitcoin server picker: Default and Custom up front, the other presets
/// behind More servers. Every preset stays selectable, and the list opens
/// itself when one of the other presets is the current choice.
class _BitcoinServerPicker extends ConsumerStatefulWidget {
  const _BitcoinServerPicker({
    required this.presets,
    required this.defaultNodeType,
    required this.onCustom,
  });

  final List<(String, String, String)> presets;
  final String defaultNodeType;
  final VoidCallback onCustom;

  @override
  ConsumerState<_BitcoinServerPicker> createState() =>
      _BitcoinServerPickerState();
}

class _BitcoinServerPickerState extends ConsumerState<_BitcoinServerPicker> {
  bool _showMore = false;

  Future<void> _select(String name, String host, String trackingId) async {
    HapticFeedback.selectionClick();
    // Re-picking the current preset is not a change.
    if (ref.read(settingsProvider).nodeType != name) {
      TrackingService.electrumNodeSelected(trackingId);
    }
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.setBitcoinElectrumNode(host);
    await notifier.setNodeType(name);
    if (!mounted) return;
    ref.read(backgroundSyncNotifierProvider.notifier).performSync();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final nodeType = ref.watch(settingsProvider.select((s) => s.nodeType));
    final l10n = context.l10n;

    final defaultPreset = widget.presets.firstWhere(
        (p) => p.$1 == widget.defaultNodeType,
        orElse: () => widget.presets.first);
    final others =
        widget.presets.where((p) => p.$1 != defaultPreset.$1).toList();
    final otherSelected = others.any((p) => p.$1 == nodeType);

    return _SettingsPickerSheet(
      title: l10n.electrumNode,
      rows: [
        AppBottomSheetListTile(
          icon: Icons.cloud_rounded,
          title: l10n.settingsServerDefault,
          subtitle: defaultPreset.$1,
          isSelected: nodeType == defaultPreset.$1,
          onTap: () =>
              _select(defaultPreset.$1, defaultPreset.$2, defaultPreset.$3),
        ),
        AppBottomSheetListTile(
          icon: Icons.edit_rounded,
          title: l10n.settingsServerCustom,
          subtitle: l10n.settingsServerCustomSubtitle,
          isSelected: nodeType == 'Custom',
          onTap: () {
            HapticFeedback.selectionClick();
            TrackingService.electrumNodeSelected('custom');
            context.pop();
            widget.onCustom();
          },
        ),
        if (!_showMore && !otherSelected)
          AppBottomSheetListTile(
            icon: Icons.expand_more_rounded,
            title: l10n.settingsMoreServers,
            onTap: () {
              HapticFeedback.selectionClick();
              TrackingService.track('settings_more_servers_tapped');
              setState(() => _showMore = true);
            },
          )
        else
          for (final (name, host, trackingId) in others)
            AppBottomSheetListTile(
              icon: Icons.cloud_rounded,
              title: name,
              isSelected: nodeType == name,
              onTap: () => _select(name, host, trackingId),
            ),
      ],
    );
  }
}

/// Change (or first-time set) the app PIN. Three keypad steps on the
/// shared sheet container: current PIN, new PIN, confirm. Same
/// PinProgressIndicator + CustomKeypad entry as set_pin / confirm_pin,
/// with the error as plain text under the dots.
class ChangePinSheet extends ConsumerStatefulWidget {
  /// Where the sheet was opened from ('settings' row | 'deep_link').
  final String entrySource;

  const ChangePinSheet({super.key, this.entrySource = 'settings'});

  @override
  ConsumerState<ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<ChangePinSheet> {
  String _oldPin = '';
  String _newPin = '';
  String _confirmPin = '';

  // 0: Old, 1: New, 2: Confirm
  int _step = 0;
  String? _errorText;
  bool _isLoading = false;

  // J7: the counted current PIN step is the step-up for changing the PIN.
  bool _requiresStepUp = true;
  bool _stepUpPassed = false;
  bool _stepUpDeniedTracked = false;

  /// pin_change funnel: started → step → completed | failed | abandoned.
  final Stopwatch _flowTimer = Stopwatch()..start();
  bool _flowEnded = false;
  String? _lastErrorCategory;
  String _abandonReason = 'user_closed';

  static const List<String> _stepNames = ['current', 'new', 'confirm'];

  String get _stepName => _stepNames[_step];

  @override
  void initState() {
    super.initState();
    TrackingService.setFlowContext(flow: 'pin_change', step: 'current');
    _checkIfPinIsSet();
  }

  @override
  void dispose() {
    // Closing the sheet before the current PIN step passed denies.
    if (_requiresStepUp && !_stepUpPassed && !_stepUpDeniedTracked) {
      TrackingService.track('step_up_auth_denied', params: {
        'action_type': SensitiveAction.changePin.name,
        'reason': 'dismissed',
      });
    }
    if (!_flowEnded) {
      TrackingService.track('pin_change_abandoned', params: {
        'step': _stepName,
        'time_in_flow_bucket': _flowTimeBucket(_flowTimer.elapsed),
        if (_lastErrorCategory != null)
          'last_error_category': _lastErrorCategory!,
        'reason': _abandonReason,
      });
    }
    TrackingService.clearFlowContext('pin_change');
    super.dispose();
  }

  static String _flowTimeBucket(Duration d) {
    final s = d.inSeconds;
    if (s < 10) return '<10s';
    if (s < 30) return '10-30s';
    if (s < 120) return '30s-2m';
    if (s < 600) return '2-10m';
    return '10m+';
  }

  /// A real step transition (never on a retry of the same step).
  void _goToStep(int step) {
    setState(() {
      _step = step;
      _isLoading = false;
    });
    TrackingService.track('pin_change_step', params: {'step': _stepName});
    TrackingService.setFlowStep(_stepName);
  }

  void _trackFailed(String reason, {Object? error}) {
    final category =
        error == null ? reason : TrackingService.errorCategory(error);
    _lastErrorCategory = category;
    TrackingService.track('pin_change_failed', params: {
      'reason': reason,
      'stage': _stepName,
      'error_category': category,
    });
  }

  Future<void> _checkIfPinIsSet() async {
    final authModel = ref.read(authModelProvider);
    final hasPin = await authModel.hasPinSet();
    if (!mounted) return;
    TrackingService.track('pin_change_started', params: {
      'mode': hasPin ? 'change' : 'setup',
      'entry_source': widget.entrySource,
    });
    // If no pin is set (e.g. first time), skip old pin step
    if (!hasPin) {
      _requiresStepUp = false;
      _goToStep(1);
    }
  }

  String get _activePin => switch (_step) {
        0 => _oldPin,
        1 => _newPin,
        _ => _confirmPin,
      };

  void _setActivePin(String value) {
    setState(() {
      switch (_step) {
        case 0:
          _oldPin = value;
        case 1:
          _newPin = value;
        default:
          _confirmPin = value;
      }
      // Typing again clears a stale error, as the old field's onChanged did.
      _errorText = null;
    });
  }

  void _onDigitPressed(String digit) {
    if (_isLoading || _activePin.length >= 6) {
      return;
    }
    HapticFeedback.lightImpact();
    _setActivePin(_activePin + digit);
  }

  void _onBackspacePressed() {
    if (_isLoading || _activePin.isEmpty) {
      return;
    }
    HapticFeedback.lightImpact();
    _setActivePin(_activePin.substring(0, _activePin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final titleText = switch (_step) {
      0 => context.l10n.changePinEnterCurrent,
      1 => context.l10n.changePinCreateNew,
      _ => context.l10n.changePinConfirmNew,
    };
    final canContinue = _activePin.length == 6 && !_isLoading;

    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: titleText,
            trailing: const _SheetCloseButton(),
          ),
          PinProgressIndicator(currentLength: _activePin.length),
          SizedBox(height: 12.h),
          // Reserved line so the keypad doesn't jump when an error lands.
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: 18.h),
            child: _errorText == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Text(
                      _errorText!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
          ),
          SizedBox(height: 12.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: IgnorePointer(
              ignoring: _isLoading,
              child: CustomKeypad(
                onDigitPressed: _onDigitPressed,
                onBackspacePressed: _onBackspacePressed,
              ),
            ),
          ),
          SizedBox(height: 20.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: AppButton(
              text: _step == 2 ? context.l10n.save : context.l10n.next,
              onPressed: canContinue ? _handleNextStep : null,
              isLoading: _isLoading,
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  /// Counts a wrong current PIN. Returns true when the app was locked and
  /// the sheet closed.
  Future<bool> _recordWrongOldPin(PinAttemptGuard guard) async {
    final outcome = await guard.recordFailure(
      surface: PinSurface.sheet,
      analyticsSurface: 'change_pin',
    );
    if (!mounted || outcome.action != PinFailureAction.lockApp) {
      return !mounted;
    }
    if (!_stepUpPassed) {
      _stepUpDeniedTracked = true;
      TrackingService.track('step_up_auth_denied', params: {
        'action_type': SensitiveAction.changePin.name,
        'reason': 'locked',
      });
    }
    _abandonReason = 'locked';
    lockAppAfterSheetLockout(ref);
    context.pop();
    return true;
  }

  Future<void> _handleNextStep() async {
    HapticFeedback.lightImpact();
    final authModel = ref.read(authModelProvider);

    // 1. Validation
    if (_activePin.length != 6) {
      setState(() => _errorText = context.l10n.mustBe6Digits);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_step == 0) {
        // Verify Old PIN. This is the step-up for changing the PIN, so
        // wrong entries count like any confirmation sheet.
        final guard = PinAttemptGuard(authModel);
        final lockout = await guard.lockoutRemaining();
        if (!mounted) {
          return;
        }
        if (lockout > Duration.zero) {
          setState(() {
            _errorText = context.l10n.lockedForTime('${lockout.inSeconds}s');
            _oldPin = '';
            _isLoading = false;
          });
          return;
        }
        final check = await authModel.checkPin(_oldPin);
        if (!mounted) {
          return;
        }
        if (check != PinCheck.match) {
          HapticFeedback.heavyImpact();
          // pin_gate_failed {surface: change_pin} is the event; this only
          // feeds last_error_category on an abandon.
          _lastErrorCategory = 'incorrect_current_pin';
          if (check == PinCheck.mismatch && await _recordWrongOldPin(guard)) {
            return;
          }
          if (!mounted) {
            return;
          }
          setState(() {
            _errorText = context.l10n.incorrectPin;
            _oldPin = '';
            _isLoading = false;
          });
          return;
        }
        await guard.recordSuccess();
        // J7: this counted step is the step-up; there is no second prompt.
        _stepUpPassed = true;
        TrackingService.track('step_up_auth', params: {
          'method': 'pin',
          'action_type': SensitiveAction.changePin.name,
        });
        if (!mounted) {
          return;
        }
        _goToStep(1);
      } else if (_step == 1) {
        // Move to confirm
        _goToStep(2);
      } else {
        // Verify Match & Execute Change
        if (_newPin != _confirmPin) {
          _trackFailed('mismatch');
          HapticFeedback.heavyImpact();
          setState(() {
            _errorText = context.l10n.pinsDoNotMatch;
            _confirmPin = '';
            _isLoading = false;
          });
          return;
        }

        final hasPin = await authModel.hasPinSet();

        if (hasPin) {
          // Change Mode: re-encrypt all mnemonics with new PIN
          final wallets = ref.read(settingsProvider).wallets;
          try {
            await authModel.changePin(_oldPin, _newPin,
                keepBiometricPin: () async {
              final dependency = await BiometricPinPolicy().evaluate(wallets);
              return dependency.exists &&
                  dependency.biometricPin == StoredPinState.present;
            });
          } on ChangePinBlocked catch (e) {
            TrackingService.changePinBlocked(walletCount: e.count);
            _trackFailed('blocked');
            if (!mounted) {
              return;
            }
            setState(() {
              _errorText = context.l10n.changePinBlocked;
              _isLoading = false;
            });
            return;
          } on IncorrectPinException {
            HapticFeedback.heavyImpact();
            _trackFailed('incorrect_current_pin');
            if (await _recordWrongOldPin(PinAttemptGuard(authModel))) {
              return;
            }
            if (!mounted) {
              return;
            }
            setState(() {
              _errorText = context.l10n.incorrectPin;
              _oldPin = '';
              _newPin = '';
              _confirmPin = '';
            });
            _goToStep(0);
            return;
          }
        } else {
          // Setup Mode
          await authModel.setPin(_newPin);
        }
        // The PIN is changed at this point, whether or not the sheet is
        // still mounted to show the confirmation.
        _flowEnded = true;
        TrackingService.pinChangeCompleted();
        TrackingService.clearFlowContext('pin_change');

        final dependency = await evaluateV1Dependency(ref);
        if (!mounted) {
          return;
        }
        markSessionUnlocked(ref,
            method: UnlockMethod.pin,
            typedPin: _newPin,
            dependency: dependency);

        if (mounted) {
          // The same confirmation every money moment ends on: one check,
          // one line, Done. The keypad sheet closes first so Done only
          // pops the overlay and lands back on Settings.
          final message = context.l10n.confirmationPinUpdated;
          final rootNav = Navigator.of(context, rootNavigator: true);
          context.pop();
          TrackingService.track('pin_change_confirmation_shown',
              params: {'mode': hasPin ? 'change' : 'setup'});
          pushKuteSuccessOverlay(
            navigator: rootNav,
            overlay: KuteConfirmation(
              message: message,
              onDone: () => rootNav.pop(),
            ),
          );
        }
      }
    } catch (e) {
      _trackFailed(e.runtimeType.toString(), error: e);
      if (mounted) {
        setState(() {
          _errorText = userErrorCopy(context, e,
              fallback: context.l10n.errorCopyChangePin);
          _isLoading = false;
        });
      }
    }
  }
}

class DenominationChangeModalBottomSheet extends StatelessWidget {
  final settings_model.SettingsModel settingsNotifier;
  final settings_model.Settings settings;
  final String initialTab;
  final bool showCurrencyOnly;
  final bool showDenominationOnly;

  const DenominationChangeModalBottomSheet({
    super.key,
    required this.settingsNotifier,
    required this.settings,
    this.initialTab = 'currency',
    this.showCurrencyOnly = false,
    this.showDenominationOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    // The shared Settings picker chrome (header with the close X, the
    // AppBottomSheetListTile rows in one scrolling list capped at 85% of
    // the screen), like every other option picker in the app.
    return _SettingsPickerSheet(
      title: showDenominationOnly
          ? context.l10n.bitcoinUnit
          : context.l10n.displayCurrency,
      rows: [
        if (showCurrencyOnly) ..._buildCurrencyRows(context),
        if (showDenominationOnly) ..._buildBitcoinFormatRows(context),
      ],
    );
  }

  List<Widget> _buildCurrencyRows(BuildContext context) {
    const currencies = [
      ('USD', Flags.united_states_of_america),
      ('EUR', Flags.european_union),
      ('GBP', Flags.united_kingdom),
      ('CHF', Flags.switzerland),
      ('BRL', Flags.brazil),
      ('SEK', Flags.sweden),
      ('NOK', Flags.norway),
      ('DKK', Flags.denmark),
      ('PLN', Flags.poland),
      ('CZK', Flags.czech_republic),
      ('HUF', Flags.hungary),
      ('RON', Flags.romania),
    ];

    return [
      for (final (code, flag) in currencies)
        AppBottomSheetListTile(
          leading: _FlagMark(flag),
          title: code,
          isSelected: settings.currency == code,
          onTap: () {
            HapticFeedback.selectionClick();
            final previous = settings.currency;
            settingsNotifier.setCurrency(code);
            if (code != previous) {
              TrackingService.settingsChanged(
                  setting: 'currency', value: code, previousValue: previous);
            }
            context.pop();
          },
        ),
    ];
  }

  List<Widget> _buildBitcoinFormatRows(BuildContext context) {
    final c = context.colors;
    // Sats uses the BIP-177 ₿ glyph as its leading marker; BTC keeps the
    // orange Bitcoin SVG (the asset mark). Both sit in the 44 leading
    // slot every picker row uses.
    final formats = [
      ('BTC', context.l10n.bitcoin),
      ('sats', context.l10n.accountSats),
    ];

    return [
      for (final (key, label) in formats)
        AppBottomSheetListTile(
          leading: SizedBox(
            width: 44.sp,
            height: 44.sp,
            child: Center(
              child: key == 'BTC'
                  ? SvgPicture.asset('lib/assets/bitcoin-icon.svg',
                      width: 32.sp, height: 32.sp)
                  : Text(
                      '₿',
                      style: TextStyle(
                        color: settings.btcFormat == key
                            ? context.ctaOnColor
                            : c.textPrimary,
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
            ),
          ),
          title: label,
          isSelected: settings.btcFormat == key,
          onTap: () {
            HapticFeedback.selectionClick();
            final previous = settings.btcFormat;
            settingsNotifier.setBtcFormat(key);
            if (key != previous) {
              TrackingService.settingsChanged(
                  setting: 'btc_format', value: key, previousValue: previous);
            }
            context.pop();
          },
        ),
    ];
  }
}

class _CustomNodeModalContent extends ConsumerStatefulWidget {
  const _CustomNodeModalContent();

  @override
  ConsumerState<_CustomNodeModalContent> createState() =>
      _CustomNodeModalContentState();
}

class _CustomNodeModalContentState
    extends ConsumerState<_CustomNodeModalContent> {
  late final TextEditingController bitcoinController;
  bool _testing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    bitcoinController =
        TextEditingController(text: settings.bitcoinElectrumNode);
  }

  @override
  void dispose() {
    bitcoinController.dispose();
    super.dispose();
  }

  /// host:port format check. Hosts are loose (any non-empty pre-colon
  /// chunk; we don't try to validate DNS/IP shape — Electrum servers
  /// run on FQDNs, IPs, and Tor hidden services).
  bool _isValidHostPort(String s) {
    final uri = Uri.tryParse(s);
    if (uri?.scheme == 'https' &&
        uri!.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      return true;
    }
    final parts = s.split(':');
    if (parts.length != 2) {
      return false;
    }
    final host = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    if (host.isEmpty) {
      return false;
    }
    if (port == null || port <= 0 || port > 65535) {
      return false;
    }
    return true;
  }

  /// Open a TLS connection to the host:port and immediately close it.
  /// If the handshake completes inside the timeout, the server is
  /// reachable on an SSL Electrum port — good enough to commit. We
  /// don't speak the Electrum framing here on purpose: a TLS-reachable
  /// host that *isn't* Electrum will still surface as a normal sync
  /// error later (now caught gracefully in BitcoinModel.sync), but
  /// 99% of bad inputs are typos / dead hosts that fail at this layer.
  Future<void> _probeReachability(String hostPort) async {
    if (hostPort.startsWith('https://')) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final uri = Uri.parse(
            '${hostPort.replaceFirst(RegExp(r'/+$'), '')}/blocks/tip/height');
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 6));
        final response =
            await request.close().timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) {
          throw const HttpException('Node unavailable');
        }
        await response.drain<void>().timeout(const Duration(seconds: 6));
      } finally {
        client.close(force: true);
      }
      return;
    }
    final parts = hostPort.split(':');
    final host = parts[0].trim();
    final port = int.parse(parts[1].trim());
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 6),
    );
    await socket.close();
  }

  Future<void> handleSave() async {
    HapticFeedback.lightImpact();
    final input = bitcoinController.text.trim();

    if (!_isValidHostPort(input)) {
      // Outcome only — the host the user typed never leaves the device.
      TrackingService.track('custom_electrum_node_saved',
          params: {'outcome': 'format_error'});
      setState(() {
        _error = context.l10n.settingsServerFormatError;
      });
      return;
    }

    setState(() {
      _testing = true;
      _error = null;
    });

    try {
      await _probeReachability(input);
    } catch (e) {
      TrackingService.track('custom_electrum_node_saved',
          params: {'outcome': 'unreachable'});
      if (!mounted) {
        return;
      }
      setState(() {
        _testing = false;
        _error = context.l10n.accountCouldntReachNode(input);
      });
      return;
    }

    if (!mounted) {
      return;
    }
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final backgroundSync = ref.read(backgroundSyncNotifierProvider.notifier);

    await settingsNotifier.setBitcoinElectrumNode(input);
    await settingsNotifier.setNodeType('Custom');
    TrackingService.track('custom_electrum_node_saved',
        params: {'outcome': 'saved'});
    if (!mounted) {
      return;
    }
    backgroundSync.performSync();
    setState(() => _testing = false);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Shared sheet container (keyboard rise + both platforms' bottom
    // inset) with the standard header; the "make sure the node is
    // active" note is the header subtitle rather than a tinted callout.
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: context.l10n.settingsCustomElectrumNode,
            subtitle: context.l10n
                .ensureTheNodeIsActiveIncorrectNodesMayShowIncorrectBalances,
            trailing: const _SheetCloseButton(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: bitcoinController,
                  enabled: !_testing,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
                  decoration: InputDecoration(
                    labelText: context.l10n.settingsServerAddress,
                    labelStyle:
                        TextStyle(color: c.textSecondary, fontSize: 16.sp),
                    helperText: context.l10n.settingsServerAddressExample,
                    helperStyle:
                        TextStyle(color: c.textTertiary, fontSize: 13.sp),
                    filled: true,
                    fillColor: c.surfaceLight,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide(
                            color:
                                _error != null ? AppColors.error : c.border)),
                    // Neutral focus ring, like the rest of the inputs.
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide(
                            color: _error != null
                                ? AppColors.error
                                : c.textPrimary)),
                  ),
                ),
                if (_error != null) ...[
                  SizedBox(height: 8.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 16.sp),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 13.sp,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 20.h),
                AppButton(
                  text: context.l10n.save,
                  onPressed: _testing ? null : handleSave,
                  isLoading: _testing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Output format for the transaction export.
enum ExportFileFormat { pdf, csv }

/// Period presets for the transaction export.
enum ExportPeriodChoice { allTime, thisYear, lastYear, last90Days }

/// (start, end) bounds for a preset; null means unbounded on that side.
(DateTime?, DateTime?) _resolveExportPeriod(ExportPeriodChoice choice) {
  final now = DateTime.now();
  switch (choice) {
    case ExportPeriodChoice.allTime:
      return (null, null);
    case ExportPeriodChoice.thisYear:
      return (DateTime(now.year), null);
    case ExportPeriodChoice.lastYear:
      return (
        DateTime(now.year - 1),
        DateTime(now.year).subtract(const Duration(milliseconds: 1)),
      );
    case ExportPeriodChoice.last90Days:
      return (now.subtract(const Duration(days: 90)), null);
  }
}

class _TransactionExportWalletSelector extends ConsumerStatefulWidget {
  final void Function(
    List<settings_model.WalletConfig> selectedWallets,
    ExportFileFormat format,
    ExportPeriodChoice period,
  ) onExport;

  const _TransactionExportWalletSelector({required this.onExport});

  @override
  ConsumerState<_TransactionExportWalletSelector> createState() =>
      _TransactionExportWalletSelectorState();
}

class _TransactionExportWalletSelectorState
    extends ConsumerState<_TransactionExportWalletSelector> {
  /// The sheet caps at this fraction of the screen; the wallet card caps
  /// at ~40% of that so the period chips and the two CTAs always fit
  /// below it, and the body scrolls as a whole past that.
  static const double _sheetMaxFraction = 0.9;

  final Set<String> _selectedWalletIds = {};
  ExportPeriodChoice _period = ExportPeriodChoice.allTime;

  /// Which format is being kicked off. Set right before the sheet pops so
  /// the tapped button shows its loader and the other one disables, which
  /// also swallows a double tap during the close animation.
  ExportFileFormat? _exporting;

  /// File format chip beside the single Export button.
  ExportFileFormat _format = ExportFileFormat.pdf;

  /// True while the wallet card overflows its cap and is not scrolled to
  /// the end, so the bottom fade hints that more rows sit below.
  bool _walletListFades = false;

  String _periodLabel(BuildContext context, ExportPeriodChoice p) {
    switch (p) {
      case ExportPeriodChoice.allTime:
        return context.l10n.exportPeriodAllTime;
      case ExportPeriodChoice.thisYear:
        return context.l10n.exportPeriodThisYear;
      case ExportPeriodChoice.lastYear:
        return context.l10n.exportPeriodLastYear;
      case ExportPeriodChoice.last90Days:
        return context.l10n.exportPeriodLast90Days;
    }
  }

  void _startExport(
    BuildContext context,
    List<settings_model.WalletConfig> wallets,
    ExportFileFormat format,
  ) {
    if (_exporting != null) {
      return;
    }
    final selectedWallets =
        wallets.where((w) => _selectedWalletIds.contains(w.id)).toList();
    final period = _period;
    setState(() => _exporting = format);
    context.pop();
    widget.onExport(selectedWallets, format, period);
  }

  void _toggleAll(List<settings_model.WalletConfig> wallets) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedWalletIds.length == wallets.length) {
        _selectedWalletIds.clear();
      } else {
        _selectedWalletIds
          ..clear()
          ..addAll(wallets.map((w) => w.id));
      }
    });
  }

  void _toggleWallet(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedWalletIds.remove(id)) {
        _selectedWalletIds.add(id);
      }
    });
  }

  void _syncWalletListFade(ScrollMetrics metrics) {
    final fades = metrics.maxScrollExtent > 0 &&
        metrics.pixels < metrics.maxScrollExtent - 1;
    if (fades != _walletListFades && mounted) {
      setState(() => _walletListFades = fades);
    }
  }

  @override
  void initState() {
    super.initState();
    final wallets = ref.read(settingsProvider).wallets;
    for (final w in wallets) {
      _selectedWalletIds.add(w.id);
    }
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
    );
  }

  Widget _walletRow(BuildContext context, settings_model.WalletConfig wallet) {
    final c = context.colors;
    final selected = _selectedWalletIds.contains(wallet.id);
    // Plain type label shared with the wallets list; never a mechanism.
    final subtitle = walletTypeLabel(context.l10n, wallet);
    final IconData icon;
    if (wallet.isExternalAddress) {
      icon = Icons.visibility_rounded;
    } else if (wallet.isHardware) {
      icon = Icons.usb_rounded;
    } else if (wallet.isWatchOnly) {
      icon = Icons.visibility_rounded;
    } else {
      icon = Icons.bolt_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _toggleWallet(wallet.id),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              // Neutral leading tile, same chrome as the add-wallet rows:
              // surfaceLight ground, hairline border, no tinted fills.
              Container(
                width: 44.sp,
                height: 44.sp,
                decoration: BoxDecoration(
                  color: c.surfaceLight,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: c.borderSubtle, width: 0.5),
                ),
                child: Icon(icon, color: c.textSecondary, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      wallet.name.isNotEmpty
                          ? wallet.name
                          : context.l10n.accountWallet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              // Selection mark: solid ctaFill disc with the on-color check
              // when picked, an empty hairline ring otherwise. No accent.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22.sp,
                height: 22.sp,
                decoration: BoxDecoration(
                  color: selected ? context.ctaFill : Colors.transparent,
                  shape: BoxShape.circle,
                  border:
                      selected ? null : Border.all(color: c.border, width: 1),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        color: context.ctaOnColor,
                        size: 15.sp,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _walletsSection(
    BuildContext context,
    List<settings_model.WalletConfig> wallets,
  ) {
    final c = context.colors;
    final allSelected =
        wallets.isNotEmpty && _selectedWalletIds.length == wallets.length;
    final listCap =
        MediaQuery.of(context).size.height * _sheetMaxFraction * 0.4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionLabel(context, context.l10n.wallets)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleAll(wallets),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 6.h),
                child: Text(
                  allSelected
                      ? context.l10n.deselectAll
                      : context.l10n.selectAll,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        if (wallets.isNotEmpty)
          Container(
            decoration: AppDecorations.card(context),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                children: [
                  // Shrink-wraps for a few wallets; past the cap the card
                  // scrolls on its own. Clamping physics so a card with
                  // nothing to scroll hands the drag to the sheet body.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: listCap),
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: (n) {
                        _syncWalletListFade(n.metrics);
                        return false;
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          _syncWalletListFade(n.metrics);
                          return false;
                        },
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // No hairline between rows, the same as
                              // the Settings grouped cards: the card's
                              // own edge groups them.
                              for (final wallet in wallets)
                                _walletRow(context, wallet),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _walletListFades ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          height: 40.h,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                c.surface.withValues(alpha: 0),
                                c.surface,
                              ],
                            ),
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

  Widget _periodChip(BuildContext context, ExportPeriodChoice p) {
    final c = context.colors;
    final selected = _period == p;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _period = p);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
        // Selected is the solid monochrome CTA fill, never an accent tint.
        decoration: BoxDecoration(
          color: selected ? context.ctaFill : c.surfaceLight,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: selected ? context.ctaFill : c.border),
        ),
        child: Text(
          _periodLabel(context, p),
          style: TextStyle(
            color: selected ? context.ctaOnColor : c.textPrimary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Widget _periodSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, context.l10n.exportPeriod),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            for (final p in ExportPeriodChoice.values) _periodChip(context, p),
          ],
        ),
      ],
    );
  }

  Widget _formatChip(BuildContext context, ExportFileFormat f) {
    final c = context.colors;
    final selected = _format == f;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('export_format_selected',
            params: {'format': f.name});
        setState(() => _format = f);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
        // Selected is the solid monochrome CTA fill, never an accent tint.
        decoration: BoxDecoration(
          color: selected ? context.ctaFill : c.surfaceLight,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: selected ? context.ctaFill : c.border),
        ),
        child: Text(
          f == ExportFileFormat.pdf
              ? context.l10n.exportFormatPdf
              : context.l10n.exportFormatCsv,
          style: TextStyle(
            color: selected ? context.ctaOnColor : c.textPrimary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }

  Widget _actions(
    BuildContext context,
    List<settings_model.WalletConfig> wallets,
  ) {
    final canExport = _selectedWalletIds.isNotEmpty && _exporting == null;
    return Column(
      children: [
        // One Export button; the file format is a chip above it.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final f in ExportFileFormat.values) ...[
              if (f != ExportFileFormat.values.first) SizedBox(width: 8.w),
              _formatChip(context, f),
            ],
          ],
        ),
        SizedBox(height: 12.h),
        AppButton(
          text: context.l10n.export,
          isLoading: _exporting != null,
          onPressed:
              canExport ? () => _startExport(context, wallets, _format) : null,
        ),
        SizedBox(height: 12.h),
        Text(
          context.l10n.exportOrientationOnly,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 12.5.sp,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));

    return AppBottomSheetContainer(
      maxHeight: _sheetMaxFraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The standard header (handle, 28sp title, subtitle) with the
          // close X in the same slot as every other sheet.
          AppBottomSheetHeader(
            title: context.l10n.exportTransactionsSheetTitle,
            subtitle: context.l10n.chooseWhichWalletsToIncludeInTheReport,
            trailing: const _SheetCloseButton(),
          ),
          // The body scrolls as a whole once the wallet card, chips and
          // CTAs outgrow the sheet; the handle and header stay fixed so a
          // pull on them still drags the sheet closed.
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _walletsSection(context, wallets),
                  SizedBox(height: 20.h),
                  _periodSection(context),
                  SizedBox(height: 20.h),
                  _actions(context, wallets),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One settings section: the shared grouped card ([KuteListGroup]), the
/// same card as the add-wallet device list.
class _GroupedCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupedCard({required this.children});

  @override
  Widget build(BuildContext context) => KuteListGroup(children: children);
}

/// One settings row inside a [_GroupedCard]: the shared [KuteListRow]
/// (neutral 44 icon tile, 15sp w600 title, 13sp subtitle, tertiary
/// chevron, surfaceLight press wash plus the light haptic).
class _SettingsRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => KuteListRow(
        title: title,
        icon: icon,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      );
}

/// Settings > Security > Notifications: the OS push-permission status
/// (On / Off) read live from the platform, refreshed whenever the app
/// comes back to the foreground so a change made in the OS settings shows
/// up on return. Tapping asks the system prompt while the OS still allows
/// one ([PushPermissionStatus.notDetermined]); once the OS has an answer
/// the only way to change it is the app's page in the OS settings, so the
/// row opens that instead. A grant made there is wired (topics + AppsFlyer
/// uninstall token) on resume by [PushPermission.syncAfterExternalChange].
class _NotificationsRow extends StatefulWidget {
  const _NotificationsRow();

  @override
  State<_NotificationsRow> createState() => _NotificationsRowState();
}

class _NotificationsRowState extends State<_NotificationsRow>
    with WidgetsBindingObserver {
  PushPermissionStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the OS settings page (or anywhere else): re-read, and
    // finish the grant wiring if notifications were turned on out there.
    if (state == AppLifecycleState.resumed) unawaited(_refresh(sync: true));
  }

  Future<void> _refresh({bool sync = false}) async {
    final status = sync
        ? await PushPermission.syncAfterExternalChange()
        : await PushPermission.currentStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  String _subtitle(BuildContext context) {
    final l10n = context.l10n;
    switch (_status) {
      case PushPermissionStatus.granted:
      case PushPermissionStatus.provisional:
        return l10n.settingsNotificationsOn;
      case PushPermissionStatus.notDetermined:
        return l10n.settingsNotificationsOffTapToTurnOn;
      case PushPermissionStatus.denied:
      case null:
        return l10n.settingsNotificationsOffOpenSystemSettings;
    }
  }

  Future<void> _onTap() async {
    if (_busy) return;
    _busy = true;
    try {
      if (_status == PushPermissionStatus.notDetermined) {
        TrackingService.settingsActionTapped('notifications_request');
        final status = await PushPermission.request(
            surface: PushPermission.settingsSurface);
        if (mounted) setState(() => _status = status);
        return;
      }
      TrackingService.settingsActionTapped('notifications_open_settings');
      var opened = false;
      try {
        opened = await openAppSettings();
      } catch (_) {
        opened = false;
      }
      if (!opened && mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.settingsNotificationsSystemSettingsHint,
          error: false,
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      title: context.l10n.settingsNotifications,
      icon: Icons.notifications_none_rounded,
      subtitle: _subtitle(context),
      onTap: _status == null ? null : _onTap,
    );
  }
}

/// The settings toggle: ctaFill active track with the on-colour thumb,
/// surfaceLight inactive track with a hairline outline. Never the accent.
class _SettingsSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: context.ctaOnColor,
      activeTrackColor: context.ctaFill,
      inactiveThumbColor: c.textSecondary,
      inactiveTrackColor: c.surfaceLight,
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : c.borderSubtle,
      ),
    );
  }
}

/// The close X in every Settings sheet header: the same affordance, in
/// the same top-right slot, as the Predictions "Rules and resolution" and
/// the Investing "About" sheets.
class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton();

  @override
  Widget build(BuildContext context) => const AppBottomSheetCloseButton();
}

/// The chrome every Settings option picker wears (language, display
/// currency, Bitcoin unit, auto-lock, Bitcoin server), the same as the
/// app's other pickers (Predictions "More", the amount unit picker): the
/// shared container capped at 85% of the screen, the standard header with
/// its title and close X, then the [AppBottomSheetListTile] rows in one
/// scrolling list. When [selectedKey] is on a row below the fold, the list
/// opens already scrolled to it.
class _SettingsPickerSheet extends StatefulWidget {
  final String title;
  final List<Widget> rows;
  final GlobalKey? selectedKey;

  const _SettingsPickerSheet({
    required this.title,
    required this.rows,
    this.selectedKey,
  });

  @override
  State<_SettingsPickerSheet> createState() => _SettingsPickerSheetState();
}

class _SettingsPickerSheetState extends State<_SettingsPickerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = widget.selectedKey?.currentContext;
      final box = ctx?.findRenderObject();
      if (!mounted || ctx == null || box == null) {
        return;
      }
      final position = Scrollable.maybeOf(ctx)?.position;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (position == null || viewport == null) {
        return;
      }
      // Only when the row sits below the fold; a row already on screen
      // leaves the list where it is.
      final bottomEdge = viewport.getOffsetToReveal(box, 1.0).offset;
      if (bottomEdge <= position.pixels) {
        return;
      }
      // ignore: discarded_futures
      Scrollable.ensureVisible(ctx, alignment: 0.5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: widget.title,
            trailing: const _SheetCloseButton(),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A flag in the 44 leading slot every picker row uses: the flag itself
/// 32 wide at 3:2, rounded, with a hairline so the white flags (Japan,
/// Finland) keep their edge on a light row.
class _FlagMark extends StatelessWidget {
  final String asset;
  const _FlagMark(this.asset);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(4.r);
    return SizedBox(
      width: 44.sp,
      height: 44.sp,
      child: Center(
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: context.colors.borderSubtle, width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: radius,
            // The icons_plus flags are a 3:2 flag centred in a square
            // canvas; cover-fitting the square into a 3:2 box keeps just
            // the flag.
            child: SizedBox(
              width: 32.sp,
              height: 32.sp * 2 / 3,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SvgPicture.asset(
                  asset,
                  package: 'icons_plus',
                  width: 32.sp,
                  height: 32.sp,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
