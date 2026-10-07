import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a secure storage failure means for the data behind it.
///
/// Temporary classes may succeed on retry and must never lead to a wipe.
/// Definitive classes mean the stored item cannot be decrypted on this
/// device any more.
enum SecretErrorClass {
  cancelled,
  authFailed,
  interactionNotAllowed,
  unavailable,
  noSecureLock,
  keyInvalidated,
  decode,
  unknown;

  bool get isDefinitive =>
      this == SecretErrorClass.keyInvalidated ||
      this == SecretErrorClass.decode;
}

/// Classifies an error thrown by flutter_secure_storage or the
/// `com.kutewallet.app/security` channel.
///
/// iOS reports the OSStatus in `details`. Android reports the Java exception
/// message in `message` and its stack trace in `details`.
SecretErrorClass classifySecretError(Object error, {TargetPlatform? platform}) {
  if (error is! PlatformException) return SecretErrorClass.unknown;
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return _classifyDarwin(error);
    case TargetPlatform.android:
      return _classifyAndroid(error);
    default:
      return SecretErrorClass.unknown;
  }
}

SecretErrorClass _classifyDarwin(PlatformException error) {
  final details = error.details;
  final status = details is int ? details : int.tryParse('$details');
  switch (status) {
    case -128:
      return SecretErrorClass.cancelled;
    case -25293:
      return SecretErrorClass.authFailed;
    case -25308:
      return SecretErrorClass.interactionNotAllowed;
    case -34018:
      return SecretErrorClass.unavailable;
    case -26275:
      return SecretErrorClass.decode;
    default:
      return SecretErrorClass.unknown;
  }
}

final _androidPromptCancel =
    RegExp(r'Biometric authentication error \[(5|10|13)\]');

SecretErrorClass _classifyAndroid(PlatformException error) {
  final message = error.message ?? '';
  final details = error.details is String ? error.details as String : '';
  if (message.contains('Key mismatch') ||
      message.contains('Invalid key') ||
      message.contains('KeyPermanentlyInvalidated') ||
      message.contains('Migration failed') ||
      details.contains('KeyPermanentlyInvalidatedException')) {
    return SecretErrorClass.keyInvalidated;
  }
  if (message.contains('BIOMETRIC_UNAVAILABLE')) {
    return SecretErrorClass.noSecureLock;
  }
  if (error.code == 'INIT_FAILED' || message.contains('INIT_FAILED')) {
    return SecretErrorClass.unavailable;
  }
  if (_androidPromptCancel.hasMatch(message) ||
      message.contains('Migration cancelled')) {
    return SecretErrorClass.cancelled;
  }
  return SecretErrorClass.unknown;
}
