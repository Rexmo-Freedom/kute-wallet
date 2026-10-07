import 'package:kute/models/breez/lnurl_model.dart';
import 'package:kute/models/breez/sdk_instance.dart'; // Imports the BreezSdkSpark singleton
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:kute/services/tracking_service.dart';

class LnUrlPayService {

  /// Retrieves the currently registered Lightning Address from the SDK.
  /// Returns null if no address is registered for this seed.
  Future<Lnurl?> getExistingAddress() async {
    final sdk = BreezSdkSpark().instance;
    if (sdk == null) return null;
    try {
      final info = await sdk.getLightningAddress();
      if (info == null) return null;
      return Lnurl.fromSdk(info);
    } catch (_) {
      return null;
    }
  }

  /// Registers a Lightning Address using the Hosted Domain feature via the SDK.
  ///
  /// The SDK communicates with the configured 'lnurlDomain' in your Config.
  Future<Lnurl> register({
    required String username,
    String? description,
  }) async {
    try {
      final sdk = BreezSdkSpark().instance;
      if (sdk == null) {
        throw RegisterWebhookException("SDK not initialized");
      }

      final req = RegisterLightningAddressRequest(
        username: username,
        description: description,
      );

      final result = await sdk.registerLightningAddress(request: req);

      return Lnurl.fromSdk(result);
    } on RegisterWebhookException {
      rethrow;
    } catch (e) {
      // Map SDK errors to domain exceptions. Neither message carries the
      // username or the SDK text: both can reach Crashlytics.
      final text = e.toString().toLowerCase();
      if (text.contains("conflict") || text.contains("taken")) {
        throw UsernameConflictException('Username already taken');
      }
      throw RegisterWebhookException(
          'register_failed: ${TrackingService.errorCategory(e)}');
    }
  }
}