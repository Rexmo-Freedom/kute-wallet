import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/bitcoin_wallet_creation_service.dart';

final bitcoinWalletCreationProvider =
    Provider<BitcoinWalletCreationService>((ref) {
  return BitcoinWalletCreationService(
    auth: ref.read(authModelProvider),
    settings: ref.read(settingsProvider.notifier),
    isSessionUnlocked: () => ref.read(sessionUnlockedProvider),
  );
});
