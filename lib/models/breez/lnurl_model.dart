import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';

class Lnurl {
  final String? lightningAddress;
  final String? lnurl;
  final String? description;
  final String? username;

  Lnurl({
    this.lightningAddress,
    this.lnurl,
    this.description,
    this.username,
  });

  /// Maps the SDK's [LightningAddressInfo] to our domain model
  factory Lnurl.fromSdk(LightningAddressInfo info) {
    return Lnurl(
      lightningAddress: info.lightningAddress,
      lnurl: info.lnurl.bech32,
      description: info.description,
      username: info.username,
    );
  }
}

// lnurl_exceptions.dart

class UsernameConflictException implements Exception {
  final String message;
  UsernameConflictException(this.message);
  @override
  String toString() => 'UsernameConflictException: $message';
}

class RegisterWebhookException implements Exception {
  final String message;
  RegisterWebhookException(this.message);
  @override
  String toString() => 'RegisterWebhookException: $message';
}

class RegistrationType {
  static const String newRegistration = 'newRegistration';
  static const String update = 'update';
}