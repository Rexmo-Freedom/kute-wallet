import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';

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

  ProviderContainer containerFor(Settings settings) {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => _MemorySettings(settings)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  for (final passkeyProvider in [null, 'breez-0.17']) {
    test('new Bitcoin wallet never prompts a $passkeyProvider passkey account',
        () {
      final passkey =
          spending.copyWith(isPasskey: true, passkeyProvider: passkeyProvider);
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
