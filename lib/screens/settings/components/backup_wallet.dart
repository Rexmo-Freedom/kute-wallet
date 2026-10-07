import 'package:kute/helpers/backup_quiz.dart';
import 'package:kute/models/words_model.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/helpers/seed_clipboard.dart';
import 'package:kute/helpers/stored_seed_reveal.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/seed_word_tile.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/services/tracking_service.dart';

class BackupWallet extends ConsumerStatefulWidget {
  /// Optional explicit wallet to back up. When non-null we load that
  /// wallet's mnemonic regardless of the active carousel page. A null id
  /// only resolves a spending wallet; separate Bitcoin wallets are explicit.
  final String? walletId;

  const BackupWallet({super.key, this.walletId});

  @override
  ConsumerState<BackupWallet> createState() => _BackupWalletState();
}

enum _BackupStep { reveal, verify }

/// Coarse time-in-flow bucket for `backup_abandoned` (no raw duration).
String _flowTimeBucket(Duration d) {
  final s = d.inSeconds;
  if (s < 10) return '<10s';
  if (s < 30) return '10-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  return '10m+';
}

class _BackupWalletState extends ConsumerState<BackupWallet> {
  List<String>? mnemonicWords;
  List<int> selectedIndices = [];
  Map<int, List<String>> quizOptions = {};
  Map<int, String> userSelections = {};
  bool _isLoading = true;
  _BackupStep _step = _BackupStep.reveal;
  bool _revealAcknowledged = false;
  bool _isSaving = false;

  /// Set once the flow reached an outcome (verified, or a terminal
  /// `backup_failed`), so dispose reports only true abandonment.
  bool _ended = false;

  /// The wallet whose mnemonic was actually revealed. Quiz completion
  /// must flip `backedUp` on THIS wallet — not on the carousel-active
  /// one, which can be a hardware/watch-only page while the words shown
  /// belong to the spending wallet. Flipping the active wallet there
  /// falsely marked a cold wallet backed up and left the real wallet's
  /// banner showing forever.
  String? _targetWalletId;

  /// The seed reveal grant this screen issued, revoked on dispose. A live
  /// grant reused from the seed words screen is left to that screen.
  AuthGrant? _ownedGrant;

  /// Copies the phrase; clears it after 60 s, or when this screen closes,
  /// only if the clipboard still holds it.
  final SeedClipboard _clipboard = SeedClipboard();

  /// Flow timing and abandon context (categorical only; nothing here is
  /// derived from the phrase).
  final Stopwatch _flowTimer = Stopwatch()..start();
  String? _abandonReason;
  bool _quizFailed = false;
  String? _walletKind;

  @override
  void initState() {
    super.initState();
    // Phase 2 safety funnel: entering this screen IS the backup flow
    // start. Reveal/verify steps emit their own funnel events below.
    TrackingService.backupStarted();
    TrackingService.setFlowContext(flow: 'backup', step: 'auth');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final targetWallet = _resolveTargetWallet();
      if (targetWallet == null) {
        _trackBackupFailed('no_wallet');
        if (mounted) {
          showMessageSnackBar(
            message: context.l10n.noActiveWalletFound,
            error: true,
            context: context,
          );
          context.pop();
        }
        return;
      }
      _walletKind =
          targetWallet.isSparkWallet ? 'hot_spending' : 'hot_bitcoin';
      TrackingService.setFlowContext(
          flow: 'backup', step: 'auth', walletKind: _walletKind);
      // Step-up gate (spec 4.1 Keys): revealing the seed always demands a
      // fresh biometric or PIN proof bound to THIS wallet, even seconds
      // after an app unlock. Nothing is read before it. A live grant from
      // the seed words screen for the same wallet is reused.
      final existing =
          AuthGrantRegistry.instance.seedRevealGrantFor(targetWallet.id);
      final grant = await requireSeedRevealGrant(context, ref,
          walletId: targetWallet.id);
      if (!mounted) {
        if (grant != null && !identical(grant, existing)) {
          AuthGrantRegistry.instance.revokeSeedReveal(grant);
        }
        return;
      }
      if (grant == null) {
        _abandonReason = 'auth_declined';
        context.pop();
        return;
      }
      if (!identical(grant, existing)) _ownedGrant = grant;
      fetchMnemonic(targetWallet, grant);
    });
  }

  void _trackBackupFailed(String reason) {
    _ended = true;
    TrackingService.track('backup_failed', params: {'reason': reason});
    TrackingService.clearFlowContext('backup');
  }

  @override
  void dispose() {
    if (!_ended) {
      TrackingService.track('backup_abandoned', params: {
        'step': _step.name,
        'time_in_flow_bucket': _flowTimeBucket(_flowTimer.elapsed),
        'reason': _abandonReason ?? 'user_closed',
        'quiz_failed': _quizFailed,
        if (_walletKind != null) 'wallet_kind': _walletKind!,
      });
    }
    TrackingService.clearFlowContext('backup');
    final grant = _ownedGrant;
    if (grant != null) AuthGrantRegistry.instance.revokeSeedReveal(grant);
    _clipboard.dispose();
    super.dispose();
  }

  /// The wallet whose words this screen reveals. Reads no secret.
  WalletConfig? _resolveTargetWallet() {
    return resolveBackupWalletTarget(ref.read(settingsProvider),
        walletId: widget.walletId);
  }

  Future<void> fetchMnemonic(WalletConfig targetWallet, AuthGrant grant) async {
    if (!seedRevealGrantCovers(grant, targetWallet.id)) {
      if (mounted) context.pop();
      return;
    }
    // Remember whose words we are about to reveal so the verify quiz
    // flips `backedUp` on the right wallet.
    _targetWalletId = targetWallet.id;

    // Passkey seeds are cached in device-local secure storage and can be
    // recovered from the passkey PRF. Emergency manual
    // backup is the Breez-recommended best practice: pull the seed
    // back through `PasskeyService.getWallet`, convert the entropy
    // to BIP39 words, and show them so the user has a paper-fallback
    // if they ever lose access to the passkey.
    String? mnemonic;
    if (targetWallet.isPasskey) {
      try {
        // Use the target wallet's own label so we show ITS seed, not the
        // last-cached wallet's. Cached label is a legacy-only fallback.
        final label =
            targetWallet.passkeyLabel ?? await PasskeyService.getCachedLabel();
        // VINTAGE ROUTING — absolute rule on a mnemonic-reveal surface:
        // a legacy (passkeyProvider == null) wallet reconstructs ONLY
        // via the 0.15.1 PRF pipeline. Deriving via the new SDK could
        // resolve a different credential and show the user words that
        // don't control their funds — a paper backup of the wrong seed.
        final breez.Seed seed = targetWallet.passkeyProvider == null
            ? await PasskeyService.getLegacySeed(label: label)
            : (await PasskeyService.getWallet(label: label, legacy: false))
                .seed;
        mnemonic = await _seedToMnemonic(seed);
      } catch (_) {
        mnemonic = null;
      }
    } else {
      if (!mounted) return;
      final read = await readStoredSeedInteractive(
          context, ref, targetWallet.id,
          pinTitle: context.l10n.enterPinToViewRecoveryPhrase,
          analyticsSurface: 'backup_wallet');
      mnemonic = read is SeedOk ? read.value : null;
    }

    final words = mnemonic?.trim().split(RegExp(r'\s+'));
    Map<int, List<String>>? quiz;
    if (words != null && words.isNotEmpty) {
      try {
        quiz = buildBackupQuiz(words, await MnemonicWords().loadWordList());
      } catch (_) {
        // A missing or invalid dictionary must not freeze the backup screen.
      }
    }

    final generatedQuiz = quiz;
    if (!mounted) return;
    if (!seedRevealGrantCovers(grant, targetWallet.id) ||
        !ref.read(sessionUnlockedProvider) ||
        !ref.read(settingsProvider).wallets.any((wallet) =>
            wallet.id == targetWallet.id &&
            wallet.isPasskey == targetWallet.isPasskey &&
            wallet.passkeyLabel == targetWallet.passkeyLabel &&
            wallet.passkeyProvider == targetWallet.passkeyProvider &&
            wallet.evmDerivationVersion == targetWallet.evmDerivationVersion)) {
      _trackBackupFailed('seed_unavailable');
      setState(() {
        mnemonicWords = null;
        _isLoading = false;
      });
      return;
    }
    if (mounted) {
      if (words != null && generatedQuiz != null) {
        // No word count: the length of a revealed seed is not sent.
        TrackingService.recoveryPhraseDisplayed();
        TrackingService.recoveryQuizStarted();
        TrackingService.backupRevealViewed();
        TrackingService.setFlowStep('reveal');
        setState(() {
          mnemonicWords = words;
          selectedIndices = generatedQuiz.keys.toList();
          quizOptions = generatedQuiz;
          userSelections.clear();
          _isLoading = false;
        });
      } else {
        _trackBackupFailed('seed_unavailable');
        showMessageSnackBar(
          message: context.l10n.recoveryPhraseLoadFailedGeneric,
          error: true,
          context: context,
        );
        context.pop();
      }
    }
  }

  /// Convert a Breez SDK [Seed] into a space-separated BIP39
  /// mnemonic. Passkey wallets carry `Seed.entropy(bytes)`; BIP39
  /// imports carry `Seed.mnemonic(...)` directly. Returns null when
  /// the entropy length isn't BIP39-valid (128/160/192/224/256 bits).
  Future<String?> _seedToMnemonic(breez.Seed seed) =>
      PasskeyService.mnemonicOfSeed(seed);

  /// Copies the whole phrase as a sensitive, local-only copy that clears
  /// itself (see [SeedClipboard]).
  Future<void> _copyPhrase() async {
    final words = mnemonicWords;
    if (words == null || words.isEmpty) return;
    HapticFeedback.lightImpact();
    await _clipboard.copy(words.join(' '));
    TrackingService.seedPhraseCopied(surface: 'backup_wallet');
    if (!mounted) return;
    showMessageSnackBar(
      context: context,
      message: context.l10n.recoveryPhraseCopied,
      error: false,
    );
  }

  bool checkAnswers() {
    if (userSelections.length < selectedIndices.length) return false;
    for (var index in selectedIndices) {
      if (userSelections[index] != mnemonicWords![index]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _verifyBackup() async {
    if (_isSaving) return;
    if (!checkAnswers()) {
      TrackingService.recoveryQuizFailed();
      _quizFailed = true;
      showMessageSnackBar(
        message: context.l10n.incorrectSelectionsPleaseTryAgain,
        error: true,
        context: context,
      );
      return;
    }

    // The verified words belong only to this captured target. A removed
    // wallet must never redirect this write to the active spending account.
    final target = ref.read(settingsProvider).wallets
        .where((wallet) => wallet.id == _targetWalletId)
        .firstOrNull;
    if (target == null) {
      _trackBackupFailed('no_wallet');
      showMessageSnackBar(
        message: context.l10n.noActiveWalletFound,
        error: true,
        context: context,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(settingsProvider.notifier).setWalletBackedUp(target.id, true);
    } catch (_) {
      // Not terminal: the user can retry the save from the same step.
      TrackingService.track('backup_failed', params: {'reason': 'save_failed'});
      if (!mounted) return;
      setState(() => _isSaving = false);
      showMessageSnackBar(
        message: context.l10n.anErrorOccurredPleaseTryAgain,
        error: true,
        context: context,
      );
      return;
    }
    _ended = true;
    TrackingService.clearFlowContext('backup');
    if (!mounted) return;

    TrackingService.recoveryQuizCompleted();
    if (target.isSparkWallet) {
      TrackingService.backupCompletedFunnel();
    } else {
      // Verifying an added wallet does not imply the spending account is
      // backed up, including the account-level analytics property.
      TrackingService.track('backup_completed');
    }
    TrackingService.backupVerified();
    // The same confirmation every money moment ends on: one check, one
    // line, Done. Done tears down the routes under the overlay and lands
    // where the quiz used to navigate directly.
    final router = GoRouter.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    pushKuteSuccessOverlay(
      navigator: rootNav,
      overlay: KuteConfirmation(
        message: context.l10n.confirmationWalletBackedUp,
        onDone: () {
          while (rootNav.canPop()) {
            rootNav.pop();
          }
          if (target.isBitcoinSoftware) {
            router.goNamed('walletDetail',
                pathParameters: {'walletId': target.id});
          } else {
            router.go('/home');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return SecureScreen(
      surface: 'backup_wallet',
      child: Scaffold(
      backgroundColor: c.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        centerTitle: true,
        leading: KuteBackButton(
          onPressed: () {
            if (_step == _BackupStep.verify && !_isLoading) {
              TrackingService.setFlowStep('reveal');
              setState(() {
                _step = _BackupStep.reveal;
                userSelections = {};
              });
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _step == _BackupStep.reveal
              ? context.l10n.recoveryPhraseTitle
              : context.l10n.verifyBackup,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: const [],
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(decoration: AppDecorations.ambientGlow(context)),
            ),

            SafeArea(
              bottom: false,
              child: _isLoading
                  // Skeleton mimicking the reveal step: intro card +
                  // seed-word grid.
                  ? SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: Column(children: [
                        SizedBox(height: 8.h),
                        KuteSkeleton(
                          child: SkeletonBar(double.infinity, 68.h,
                              radius: 16.r),
                        ),
                        SizedBox(height: 16.h),
                        const SkeletonWordGrid(
                            crossAxisCount: 2, aspectRatio: 3),
                      ]),
                    )
                  : _step == _BackupStep.reveal
                      ? _buildRevealStep()
                      : _buildVerifyStep(),
            ),
          ],
        ),
      ),
    ));
  }

  /// Shared sticky-footer inset for both steps so the footer chrome does
  /// not change when the user moves from reveal to verify.
  EdgeInsets get _footerPadding => EdgeInsets.fromLTRB(
      20.w, 16.h, 20.w, MediaQuery.of(context).padding.bottom + 16.h);

  Widget get _hiddenWords => Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: const SeedHiddenNotice(),
      );

  Widget _buildRevealStep() {
    final c = context.colors;
    final words = mnemonicWords ?? const <String>[];
    return Column(
      children: [
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: _IntroCard(
            title: context.l10n.writeTheseDown,
            subtitle: context.l10n.wordsInOrderWarning(words.length),
          ),
        ),
        SizedBox(height: 10.h),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Align(
            alignment: Alignment.centerRight,
            child: AskSalChip(
              advisorContext: const AdvisorContext(surface: 'backup_reveal'),
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Expanded(
          child: SecureContent(
            hidden: _hiddenWords,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12.w,
                    mainAxisSpacing: 12.h,
                    childAspectRatio: 3,
                  ),
                  itemCount: words.length,
                  itemBuilder: (context, index) =>
                      SeedWordTile(index: index + 1, word: words[index]),
                ),
                SizedBox(height: 16.h),
                AppButton(
                  key: const ValueKey('backup-copy-phrase'),
                  text: context.l10n.copy,
                  icon: Icons.copy_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: _copyPhrase,
                ),
                SizedBox(height: 16.h),
              ]),
            ),
          ),
        ),
        Padding(
          padding: _footerPadding,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(
                      () => _revealAcknowledged = !_revealAcknowledged);
                },
                child: Row(
                  children: [
                    Icon(
                      _revealAcknowledged
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: _revealAcknowledged
                          ? context.ctaFill
                          : c.textTertiary,
                      size: 22.sp,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        context.l10n.iHaveWrittenDownMyRecoveryPhrase,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 14.h),
              AppButton(
                text: context.l10n.continueLabel,
                onPressed: _revealAcknowledged
                    ? () {
                        TrackingService.backupRevealAcknowledged();
                        TrackingService.backupVerifyViewed();
                        TrackingService.setFlowStep('verify');
                        setState(() => _step = _BackupStep.verify);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerifyStep() {
    return Column(
      children: [
        SizedBox(height: 8.h),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: _IntroCard(
            title: context.l10n.verifyYourBackup,
            subtitle: context.l10n.selectTheCorrectWordForEachPosition2,
          ),
        ),
        SizedBox(height: 12.h),
        Expanded(
          child: SecureContent(
            hidden: _hiddenWords,
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              itemCount: selectedIndices.length,
              itemBuilder: (context, index) {
                final wordIndex = selectedIndices[index];
                return _QuizItem(
                  wordIndex: wordIndex,
                  options: quizOptions[wordIndex]!,
                  selected: userSelections[wordIndex],
                  onSelect: (option) {
                    setState(() {
                      userSelections[wordIndex] = option;
                    });
                  },
                );
              },
            ),
          ),
        ),
        Padding(
          padding: _footerPadding,
          child: AppButton(
            text: context.l10n.verifyBackup,
            isLoading: _isSaving,
            onPressed: _isSaving ? null : _verifyBackup,
          ),
        ),
      ],
    );
  }
}

/// Intro card shared by the reveal and verify steps: the app card
/// (floating in light, hairline in dark) with a neutral 44 icon tile,
/// a 16sp title and the one 13sp subtitle style.
class _IntroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _IntroCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: AppDecorations.card(context),
      child: Row(
        children: [
          Container(
            width: 44.sp,
            height: 44.sp,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: c.borderSubtle, width: 0.5),
            ),
            child: Icon(Icons.shield_rounded,
                color: c.textSecondary, size: 22.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
            ),
          ),
        ],
      ),
    );
  }
}

/// One quiz question: the word position plus its answer chips. Its own
/// widget (not a builder helper) so it re-reads the theme on a live
/// theme change inside the lazy list.
class _QuizItem extends StatelessWidget {
  final int wordIndex;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _QuizItem({
    required this.wordIndex,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isAnswered = selected != null;

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: AppDecorations.card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${context.l10n.word} ${wordIndex + 1}',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (isAnswered)
                  Icon(Icons.check_circle_rounded,
                      color: context.ctaFill, size: 18.sp),
              ],
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final option in options)
                  _OptionChip(
                    label: option,
                    isSelected: selected == option,
                    onTap: () => onSelect(option),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Answer chip: neutral surfaceLight + hairline at rest, `ctaFill` fill
/// with `ctaOnColor` label when selected.
class _OptionChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? context.ctaFill : c.surfaceLight,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isSelected ? context.ctaFill : c.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? context.ctaOnColor : c.textPrimary,
            fontSize: 16.sp,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
