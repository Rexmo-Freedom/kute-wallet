import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Picks an image from the device gallery and decodes the first QR
/// code found in it, returning the raw payload string (Bitcoin
/// address, Lightning invoice, BIP21 URI, xpub QR, cross-chain
/// address, etc.). Returns `null` when the user cancels the picker or
/// no decodable QR is present.
///
/// Shared by the smart scanner screen and the Send-to action row so
/// the "open a QR screenshot from photos" path runs through exactly
/// the same downstream detection as a live camera scan. Uses
/// `file_picker` (already a project dependency) for the image pick and
/// `mobile_scanner`'s `analyzeImage` for the decode — no new packages.
class QrGalleryHelper {
  const QrGalleryHelper._();

  /// `null` return cases (all non-fatal — the caller just no-ops):
  ///   * user cancelled the picker
  ///   * picked file had no path (web / virtual file)
  ///   * no QR code detected in the image
  ///   * decode threw (corrupt image, unsupported format)
  static Future<String?> pickAndDecode() async {
    final picked = await FilePicker.pickFile(
      type: FileType.image,
    );
    final path = picked?.path;
    if (path == null || path.isEmpty) return null;

    final controller = MobileScannerController();
    try {
      final capture = await controller.analyzeImage(path);
      final code = capture?.barcodes
          .map((b) => b.rawValue)
          .firstWhere((v) => v != null && v.trim().isNotEmpty,
              orElse: () => null);
      final trimmed = code?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }
}
