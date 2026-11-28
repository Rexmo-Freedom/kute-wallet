// The backup and recovery pages across the window (round three; founder,
// 25 November 2026: "it must be all occupying full screen when we can"):
// on EXPANDED the words are a grid that uses the width (4 across) beside
// the explanation and the actions, the seed entry fields the same, and
// the restore list's wallets a grid beside its explanation. Checked for
// stretch at every EXPANDED size; shot when asked: DESK_FULL_RENDER=<dir>.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/words_model.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/words_provider.dart';
import 'package:kute/screens/creation/recover_wallet.dart';
import 'package:kute/screens/recovery/restore_secrets_screen.dart';
import 'package:kute/screens/recovery/storage_unavailable_screen.dart';
import 'package:kute/screens/settings/components/backup_wallet.dart';
import 'package:kute/screens/settings/components/seed_words.dart';
import 'package:kute/screens/shared/seed_word_tile.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/secure/storage_bootstrap.dart';
import 'package:kute/services/tracking_service.dart';

import '../helpers/kute_bar_test_support.dart';
import '../services/support/fake_secret_store.dart';
import 'desk_full_support.dart';

// Public synthetic vector. Never fund it.
const _phrase = 'abandon ability able about above absent absorb abstract '
    'absurd abuse access accident';

final _l10n = AppLocalizationsEn();

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'default',
      reviewDone: true,
      activeWalletId: wallets.first.id,
      wallets: wallets,
    );

class _Auth extends AuthModel {
  _Auth([FakeKeychain? keychain])
      : super(store: keychain?.local, syncedStore: keychain?.synced);
  @override
  Future<SeedRead> readMnemonic(
    String walletId, {
    required SeedAccess access,
    SeedSession session = SeedSession.locked,
  }) async =>
      const SeedOk(_phrase, SeedSource.v2Local);
}

class _Words extends MnemonicWords {
  @override
  Future<List<String>> loadWordList() async => _phrase.split(' ');
}

final _spending = WalletConfig(id: 'a', name: 'Spending');
final _savings = WalletConfig(id: 'b', name: 'Savings', sparkEnabled: false);

List<Override> _seedOverrides(List<WalletConfig> wallets) => [
      settingsProvider.overrideWith((ref) => SettingsModel(_settings(wallets))),
      authModelProvider.overrideWith((ref) => _Auth()),
      sessionAuthProvider.overrideWith((ref) =>
          SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime.now())),
      mnemonicWordsProvider.overrideWithValue(_Words()),
    ];

/// One page of the group: its widget, its route mode, its providers and
/// what to do once it is up (reveal, move to a step).
class _Page {
  const _Page(this.name, this.build,
      {this.mode = KuteWideMode.full,
      this.overrides = _none,
      this.after,
      this.grid = false});
  final String name;
  final Widget Function() build;
  final KuteWideMode mode;
  final List<Override> Function() overrides;
  final Future<void> Function(WidgetTester tester)? after;

  /// Whether the page shows the words as tiles (checked 4 across).
  final bool grid;
}

List<Override> _none() => const [];

/// Lets real async work (the word list, the reads) land.
Future<void> _settle(WidgetTester tester, {Finder? until}) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
    if (until != null && until.evaluate().isNotEmpty) break;
  }
}

final _pages = <_Page>[
  _Page('backup_reveal', () => const BackupWallet(walletId: 'a'),
      overrides: () => _seedOverrides([_spending]),
      grid: true,
      after: (tester) => _settle(tester, until: find.text('accident'))),
  _Page('backup_verify', () => const BackupWallet(walletId: 'a'),
      overrides: () => _seedOverrides([_spending]),
      after: (tester) async {
        await _settle(tester, until: find.text('accident'));
        await tester.tap(find.text(_l10n.iHaveWrittenDownMyRecoveryPhrase));
        await deskFullFrames(tester, 3);
        await tester.tap(kuteBarPrimary);
        await deskFullFrames(tester, 6);
      }),
  _Page('seed_words', () => const SeedWords(),
      overrides: () => _seedOverrides([_spending, _savings]),
      grid: true,
      after: (tester) async {
        final reveal = find.text(_l10n.revealYourRecoveryPhrase);
        await _settle(tester, until: reveal);
        await tester.ensureVisible(reveal.first);
        await deskFullFrames(tester, 2);
        await tester.tap(reveal.first);
        await deskFullFrames(tester, 4);
        expect(find.text('accident'), findsOneWidget);
      }),
  _Page('seed_words_masked', () => const SeedWords(),
      overrides: () => _seedOverrides([_spending]),
      grid: true,
      after: (tester) =>
          _settle(tester, until: find.text(_l10n.revealYourRecoveryPhrase))),
  _Page('recover_12', () => const RecoverWallet(),
      overrides: () => _seedOverrides([_spending]),
      after: (tester) => _settle(tester)),
  _Page('recover_24', () => const RecoverWallet(),
      overrides: () => _seedOverrides([_spending]),
      after: (tester) async {
        await _settle(tester);
        await tester.tap(find.text('24'));
        await deskFullFrames(tester, 4);
      }),
  _Page(
      'restore_secrets',
      () => RestoreSecretsScreen(
            reason: RestoreSecretsReason.secretsMissing,
            deriveAddress: (_) async => '0xAAAA',
            checkBalance: (_) async => 1200,
            offerLegacyCopies: false,
          ),
      overrides: () => [
            settingsProvider.overrideWith((ref) => SettingsModel(_settings([
                  WalletConfig(
                      id: 'w1',
                      name: 'Spending',
                      recoveryCheckAddress: '0xaaaa'),
                  WalletConfig(
                      id: 'w2',
                      name: 'Savings',
                      sparkEnabled: false,
                      recoveryCheckAddress: '0xBBBB'),
                  WalletConfig(
                      id: 'w3',
                      name: 'Cold storage',
                      sparkEnabled: false,
                      isWatchOnly: true),
                ]))),
            authModelProvider.overrideWith((ref) => _Auth(_keychain)),
          ],
      after: (tester) => _settle(tester)),
  _Page(
      'storage_unavailable',
      () => const StorageUnavailableScreen(
          result: StorageBootResult(StorageBootState.storageUnavailable)),
      mode: KuteWideMode.column),
];

late FakeKeychain _keychain;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final registry = AuthGrantRegistry.instance;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // A cached asset future from an earlier test never resolves here.
    rootBundle.clear();
    TrackingService.setDisabled(true);
    registry.revokeAll(includeAutofire: true);
    for (final w in ['a', 'b']) {
      registry.issueSeedReveal(seedRevealIntent(w),
          method: AuthGrantMethod.pin);
    }
    SecureScreenController.debugOverride(
        SecureScreenController(platform: TargetPlatform.android));
    messenger.setMockMethodCallHandler(
        KeychainLocal.channel, (call) async => null);
    _keychain = FakeKeychain();
    SecretStores.debugOverride(
        local: _keychain.local, synced: _keychain.synced);
    messenger.setMockMethodCallHandler(
        NativeOnchainService.channel, (call) async => false);
  });

  tearDown(() {
    registry.revokeAll(includeAutofire: true);
    SecureScreenController.debugReset();
    SecretStores.debugReset();
    messenger.setMockMethodCallHandler(KeychainLocal.channel, null);
    messenger.setMockMethodCallHandler(NativeOnchainService.channel, null);
  });

  Future<void> pump(WidgetTester tester, _Page page, Size size, bool dark) =>
      pumpDeskPage(tester,
          size: size,
          dark: dark,
          mode: page.mode,
          page: page.build(),
          overrides: page.overrides());

  for (final (label, size) in deskFullExpanded) {
    for (final page in _pages) {
      testWidgets('${page.name} at $label: nothing stretched', (tester) async {
        await pump(tester, page, size, false);
        await page.after?.call(tester);
        expect(tester.takeException(), isNull);
        if (page.grid) {
          // The words four across (three on the narrowest EXPANDED
          // window): the first tiles on one line.
          final tiles = find.byType(SeedWordTile).evaluate().toList();
          expect(tiles.length, greaterThanOrEqualTo(12));
          final tops = [
            for (final e in tiles.take(size.width >= 1180 ? 4 : 3))
              tester.getRect(find.byWidget(e.widget)).top
          ];
          for (final t in tops) {
            expect(t, closeTo(tops.first, 0.5));
          }
        }
        expectDeskNothingStretched(tester, maxCard: kuteWideColumnMax);
        await deskFullEnd(tester);
      });
    }
  }

  for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
    for (final page in _pages) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';
        testWidgets('render: ${page.name} $label $mode',
            skip: deskFullDir == null, (tester) async {
          await deskFullAssets(tester);
          await pump(tester, page, size, dark);
          await page.after?.call(tester);
          await deskFullShoot(tester, '${page.name}_${label}_$mode');
          await deskFullEnd(tester);
        });
      }
    }
  }
}
