import 'package:kute/models/settings_model.dart';

/// The connected Jade reports a different master fingerprint than the one
/// stored for this wallet: it is not the Jade paired with it (or it is
/// unlocked with another passphrase). Nothing is signed and nothing stored
/// is changed.
class JadeWrongDeviceException implements Exception {
  const JadeWrongDeviceException();

  @override
  String toString() => 'This Jade is not the one paired with this wallet.';
}

/// Lower-case 8-hex fingerprint, or null when [value] is missing, malformed
/// or the all-zero placeholder, none of which identify a device.
String? _pairedFingerprint(String? value) {
  final fp = value?.trim().toLowerCase() ?? '';
  if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(fp) || fp == '00000000') return null;
  return fp;
}

/// Checks the connected Jade against the wallet it is about to sign for.
///
/// * No stored fingerprint: first pairing, so [actualFingerprint] is saved
///   through [save].
/// * Stored fingerprint equal to the device's: nothing to do.
/// * Stored fingerprint different from the device's: throws
///   [JadeWrongDeviceException] and never overwrites the stored value.
///
/// A device that cannot report a fingerprint ([actualFingerprint] null)
/// leaves everything as is; the Jade itself refuses keys it does not hold.
Future<void> verifyJadePairing({
  required WalletConfig? wallet,
  required String? actualFingerprint,
  required Future<void> Function(WalletConfig updated) save,
}) async {
  final actual = _pairedFingerprint(actualFingerprint);
  if (actual == null || wallet == null) return;
  final stored = _pairedFingerprint(wallet.masterFingerprint);
  if (stored == null) {
    await save(wallet.copyWith(masterFingerprint: actual));
    return;
  }
  if (stored != actual) throw const JadeWrongDeviceException();
}
