import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/lnurl_service.dart';
import 'package:kute/models/breez/username_utilities.dart';
import 'package:hive_ce/hive.dart';

class LnUrlRegistrationManager {
  final LnUrlPayService lnAddressService;
  final BreezPreferences breezPreferences;
  final UsernameResolver usernameResolver;

  LnUrlRegistrationManager({
    required this.lnAddressService,
    required this.breezPreferences,
    required this.usernameResolver,
  });

  /// Recovers an existing Lightning Address for a restored wallet,
  /// falling back to registering a new one if none is found.
  Future<Lnurl> registerOrRecover({
    required String walletId,
    String? baseUsername,
    String? description,
  }) async {
    final existing = await lnAddressService.getExistingAddress();
    if (existing != null && existing.lightningAddress != null) {
      await breezPreferences.setLnAddressUsername(
        walletId,
        existing.username ?? existing.lightningAddress!.split('@').first,
      );
      await breezPreferences.setLnAddress(walletId, existing.lightningAddress);
      await breezPreferences.setLnUrlBech32(walletId, existing.lnurl);
      await breezPreferences.setLnUrlWebhookRegistered(walletId);
      return existing;
    }

    return register(
      walletId: walletId,
      registrationType: RegistrationType.newRegistration,
      baseUsername: baseUsername,
      description: description,
    );
  }

  Future<Lnurl> register({
    required String walletId,
    required String registrationType,
    String? baseUsername,
    String? description,
  }) async {
    final username = await usernameResolver.resolveUsername(
        walletId: walletId,
        baseUsername: baseUsername
    );

    final result = await lnAddressService.register(
      username: username,
      description: description,
    );

    await breezPreferences.setLnAddressUsername(walletId, result.username ?? username);
    await breezPreferences.setLnAddress(walletId, result.lightningAddress);
    await breezPreferences.setLnUrlBech32(walletId, result.lnurl);
    await breezPreferences.setLnUrlWebhookRegistered(walletId);

    return result;
  }
}

class BreezPreferences {
  static const _boxName = 'breez_prefs';

  static const _lnAddressKey = 'ln_address';
  static const _lnUsernameKey = 'ln_username';
  static const _lnBech32Key = 'ln_bech32';
  static const _isRegisteredKey = 'is_webhook_registered';

  Future<Box> get _box async => await Hive.openBox(_boxName);

  Future<String?> getLnAddress(String walletId) async {
    return (await _box).get('${_lnAddressKey}_$walletId');
  }

  Future<void> setLnAddress(String walletId, String? address) async {
    await (await _box).put('${_lnAddressKey}_$walletId', address);
  }

  Future<String?> getLnAddressUsername(String walletId) async {
    return (await _box).get('${_lnUsernameKey}_$walletId');
  }

  Future<void> setLnAddressUsername(String walletId, String name) async {
    await (await _box).put('${_lnUsernameKey}_$walletId', name);
  }

  Future<String?> getLnUrlBech32(String walletId) async {
    return (await _box).get('${_lnBech32Key}_$walletId');
  }

  Future<void> setLnUrlBech32(String walletId, String? bech32) async {
    await (await _box).put('${_lnBech32Key}_$walletId', bech32);
  }

  Future<bool> isLnUrlWebhookRegistered(String walletId) async {
    return (await _box).get('${_isRegisteredKey}_$walletId') ?? false;
  }

  Future<void> setLnUrlWebhookRegistered(String walletId) async {
    await (await _box).put('${_isRegisteredKey}_$walletId', true);
  }
}
