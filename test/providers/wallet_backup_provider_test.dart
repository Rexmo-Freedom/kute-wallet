import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/shared/wallet_removal_step_up.dart'
    show walletRemovalNeedsBackupWarning;

Settings _settings(List<WalletConfig> wallets, {String? activeWalletId}) =>
    Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: false,
      wallets: wallets,
      activeWalletId: activeWalletId ?? wallets.firstOrNull?.id,
    );

class _MemorySettings extends SettingsModel {
  _MemorySettings(super.state);

  @override
  Future<void> updateWalletConfig(WalletConfig config) async {
    state = state.copyWith(
      wallets: state.wallets
          .map((wallet) => wallet.id == config.id ? config : wallet)
          .toList(),
    );
  }
}

void main() {
  final bitcoin = WalletConfig(
      id: 'bitcoin', name: 'Separate Bitcoin', sparkEnabled: false);
  final spending = WalletConfig(id: 'spending', name: 'Spending');
  final hardware = WalletConfig(
      id: 'hardware', name: 'Hardware', sparkEnabled: false, isHardware: true);

  ProviderContainer containerFor(Settings settings,
      {Set<String> pendingLabels = const {}}) {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => _MemorySettings(settings)),
      passkeyPendingLabelsProvider.overrideWithValue(pendingLabels),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  for (final passkeyProvider in [null, 'breez-0.17']) {
    test('new Bitcoin wallet never prompts a $passkeyProvider passkey account',
        () {
      // A current-SDK passkey wallet is saved backed up once its label is
      // on the relay (restores always are); a legacy one once its words
      // were verified.
      final passkey = spending.copyWith(
          isPasskey: true,
          passkeyProvider: passkeyProvider,
          passkeyLabel: 'Spending Wallet · 1',
          backedUp: true);
      final settings = _settings([passkey, bitcoin]);
      final container = containerFor(settings);

      expect(container.read(pendingSpendingWalletBackupProvider), isNull);
      expect(needsWalletBackup(passkey), isFalse);
      expect(needsWalletBackup(bitcoin), isTrue);
      expect(resolveBackupWalletTarget(settings), isNull);
      expect(resolveBackupWalletTarget(settings, walletId: bitcoin.id),
          same(bitcoin));
    });
  }

  test('a current-SDK passkey wallet whose label is not published prompts',
      () {
    final unpublished = spending.copyWith(
        isPasskey: true,
        passkeyProvider: 'breez-0.17',
        passkeyLabel: 'Spending Wallet · 1',
        backedUp: false);
    final settings = _settings([unpublished, bitcoin]);
    final container = containerFor(settings);

    expect(needsWalletBackup(unpublished), isTrue);
    expect(needsPasskeyLabelPublish(unpublished), isTrue);
    expect(container.read(pendingSpendingWalletBackupProvider),
        same(unpublished));
    // The reminder's explicit target is the wallet itself, never another.
    expect(resolveBackupWalletTarget(settings, walletId: unpublished.id),
        same(unpublished));
    expect(walletRemovalNeedsBackupWarning(unpublished), isTrue);
    expect(walletRemovalNeedsBackupWarning(unpublished.copyWith(backedUp: true)),
        isFalse);
  });

  test('an unbacked legacy passkey wallet gets the recovery-phrase reminder '
      'until its words are verified', () async {
    // The 2026-08 migration flips pre-2.x passkey wallets to unbacked so
    // their owners write the words down.
    final legacy = spending.copyWith(isPasskey: true, backedUp: false);
    final settings = _settings([legacy, bitcoin]);
    final container = containerFor(settings);

    expect(needsWalletBackup(legacy), isTrue);
    // The words path, never the passkey label publish.
    expect(needsPasskeyLabelPublish(legacy), isFalse);
    expect(container.read(pendingSpendingWalletBackupProvider), same(legacy));
    expect(resolveBackupWalletTarget(settings, walletId: legacy.id),
        same(legacy));

    // Completing the existing verify-words step clears it.
    await container
        .read(settingsProvider.notifier)
        .setWalletBackedUp(legacy.id, true);
    final updated = container.read(settingsProvider).wallets.first;
    expect(needsWalletBackup(updated), isFalse);
    expect(container.read(pendingSpendingWalletBackupProvider), isNull);
  });

  test('a backed-up passkey wallet whose label is still pending prompts '
      'for the passkey confirmation', () {
    final wallet = spending.copyWith(
        isPasskey: true,
        passkeyProvider: 'breez-0.17',
        passkeyLabel: 'Spending Wallet · 1',
        backedUp: true);
    final settings = _settings([wallet, bitcoin]);

    expect(needsWalletBackup(wallet, pendingLabels: const {}), isFalse);
    expect(
        needsWalletBackup(wallet,
            pendingLabels: const {'Spending Wallet · 1'}),
        isTrue);
    expect(
        needsPasskeyLabelPublish(wallet,
            pendingLabels: const {'Spending Wallet · 1'}),
        isTrue);
    expect(
        containerFor(settings, pendingLabels: const {'Spending Wallet · 1'})
            .read(pendingSpendingWalletBackupProvider),
        same(wallet));
    expect(containerFor(settings).read(pendingSpendingWalletBackupProvider),
        isNull);
    // Another wallet's pending label does not concern this one.
    expect(needsWalletBackup(wallet, pendingLabels: const {'Other · 2'}),
        isFalse);
  });

  test('new Bitcoin wallet does not restore a backed-up spending reminder', () {
    final backedUpSpending = spending.copyWith(backedUp: true);
    final settings =
        _settings([bitcoin, backedUpSpending], activeWalletId: bitcoin.id);
    final container = containerFor(settings);

    expect(container.read(pendingSpendingWalletBackupProvider), isNull);
    expect(resolveBackupWalletTarget(settings), same(backedUpSpending));
    expect(needsWalletBackup(bitcoin), isTrue);
  });

  test('spending reminder still targets spending while viewing Bitcoin', () {
    final settings = _settings([bitcoin, spending], activeWalletId: bitcoin.id);
    final container = containerFor(settings);

    expect(container.read(pendingSpendingWalletBackupProvider), same(spending));
    expect(resolveBackupWalletTarget(settings), same(spending));
    expect(resolveBackupWalletTarget(settings, walletId: bitcoin.id),
        same(bitcoin));
  });

  test('explicit missing and seedless wallets cannot fall back to another seed',
      () {
    final watchOnly = WalletConfig(
        id: 'watch',
        name: 'Watch only',
        sparkEnabled: false,
        isWatchOnly: true);
    final external =
        WalletConfig(id: 'external', name: 'Address', isExternalAddress: true);
    final signer = WalletConfig(id: 'signer', name: 'Signer', isSigner: true);
    final settings =
        _settings([spending, bitcoin, hardware, watchOnly, external, signer]);

    for (final id in [
      'missing',
      hardware.id,
      watchOnly.id,
      external.id,
      signer.id
    ]) {
      expect(resolveBackupWalletTarget(settings, walletId: id), isNull,
          reason: 'The explicit $id request must never reveal spending words');
    }
    expect(needsWalletBackup(hardware), isFalse);
    expect(needsWalletBackup(watchOnly), isFalse);
  });

  test('verification updates only the wallet whose words were revealed',
      () async {
    final container = containerFor(_settings([spending, bitcoin]));
    final revealed = resolveBackupWalletTarget(container.read(settingsProvider),
        walletId: bitcoin.id)!;

    await container
        .read(settingsProvider.notifier)
        .setWalletBackedUp(revealed.id, true);

    final updated = container.read(settingsProvider);
    expect(
        updated.wallets
            .singleWhere((wallet) => wallet.id == bitcoin.id)
            .backedUp,
        isTrue);
    expect(
        updated.wallets
            .singleWhere((wallet) => wallet.id == spending.id)
            .backedUp,
        isFalse);
    expect(updated.activeWalletId, spending.id);
    expect(
        container.read(pendingSpendingWalletBackupProvider)?.id, spending.id);
  });

  test('unscoped backup never selects a lone Bitcoin wallet', () {
    final settings = _settings([bitcoin]);
    final container = containerFor(settings);
    expect(container.read(pendingSpendingWalletBackupProvider), isNull);
    expect(resolveBackupWalletTarget(settings), isNull);
    expect(resolveBackupWalletTarget(settings, walletId: bitcoin.id),
        same(bitcoin));
  });
}
