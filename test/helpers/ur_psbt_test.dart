import 'dart:convert';
import 'dart:typed_data';
import 'package:bc_ur_dart/bc_ur_dart.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dummy PSBT (valid BIP-174 header + minimal structure) for testing.
/// Real PSBTs are much larger; this is enough to test UR round-trips.
Uint8List _makeDummyPsbt({int size = 200}) {
  // PSBT magic: 0x70736274ff ("psbt\xff")
  final magic = [0x70, 0x73, 0x62, 0x74, 0xff];
  final filler = List<int>.generate(size - magic.length, (i) => i % 256);
  return Uint8List.fromList(magic + filler);
}

/// Wrap raw PSBT bytes in CBOR (CborBytes) as required by crypto-psbt UR type.
Uint8List _cborEncode(Uint8List psbtBytes) {
  return Uint8List.fromList(cbor.encode(CborBytes(psbtBytes)));
}

void main() {
  group('UR PSBT Encoding', () {
    test('Single-part UR encodes and decodes crypto-psbt correctly', () {
      final psbtBytes = _makeDummyPsbt(size: 50);
      final cborPayload = _cborEncode(psbtBytes);

      // Encode
      final ur = UR(type: 'crypto-psbt', payload: cborPayload);
      final encoded = ur.encode();

      // Verify format: UR:CRYPTO-PSBT/<bytewords>
      expect(encoded.toUpperCase(), startsWith('UR:CRYPTO-PSBT/'));

      // Decode
      final decoded = UR.decode(encoded);
      expect(decoded.type, 'crypto-psbt');
      expect(decoded.payload, cborPayload);

      // Extract PSBT bytes from CBOR
      final decodedCbor = cbor.decode(decoded.payload);
      expect(decodedCbor, isA<CborBytes>());
      final extractedPsbt = Uint8List.fromList((decodedCbor as CborBytes).bytes);
      expect(extractedPsbt, psbtBytes);
    });

    test('Single-part UR round-trip via read()', () {
      final psbtBytes = _makeDummyPsbt(size: 50);
      final cborPayload = _cborEncode(psbtBytes);

      final encoder = UR(type: 'crypto-psbt', payload: cborPayload);
      final encoded = encoder.encode();

      // Decode via read()
      final decoder = UR();
      final complete = decoder.read(encoded);
      expect(complete, isTrue);
      expect(decoder.isComplete, isTrue);
      expect(decoder.type, 'crypto-psbt');
      expect(decoder.payload, cborPayload);
    });

    test('Multi-part UR fountain encoding round-trips correctly', () {
      // Large enough PSBT to require multiple parts with small maxLength
      final psbtBytes = _makeDummyPsbt(size: 500);
      final cborPayload = _cborEncode(psbtBytes);

      // Encoder with small fragment size to force multi-part
      final encoder = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: 50, minLength: 10);

      // Generate frames
      final frames = <String>[];
      for (var i = 0; i < 100; i++) {
        frames.add(encoder.next());
      }

      // Verify frames are multi-part (contain seq numbers)
      expect(frames.first.toUpperCase(), startsWith('UR:CRYPTO-PSBT/'));
      // Multi-part frames should contain sequence info (N-M pattern)
      expect(frames.first, contains('-'));

      // Decode by reading frames
      final decoder = UR();
      for (final frame in frames) {
        decoder.read(frame);
        if (decoder.isComplete) break;
      }

      expect(decoder.isComplete, isTrue);
      expect(decoder.type, 'crypto-psbt');

      // Extract and verify PSBT bytes
      final decodedCbor = cbor.decode(decoder.payload);
      expect(decodedCbor, isA<CborBytes>());
      final extractedPsbt = Uint8List.fromList((decodedCbor as CborBytes).bytes);
      expect(extractedPsbt, psbtBytes);
    });

    test('UR frames are uppercase for QR alphanumeric mode efficiency', () {
      final psbtBytes = _makeDummyPsbt(size: 300);
      final cborPayload = _cborEncode(psbtBytes);

      final encoder = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: 50, minLength: 10);

      for (var i = 0; i < 5; i++) {
        final frame = encoder.next();
        expect(frame, equals(frame.toUpperCase()),
            reason: 'UR frames must be uppercase for QR alphanumeric mode');
      }
    });

    test('CBOR wrapping produces correct byte header', () {
      final psbtBytes = _makeDummyPsbt(size: 100);
      final cborPayload = _cborEncode(psbtBytes);

      // CBOR major type 2 (byte string), additional info 24 (1-byte length follows)
      // 0x58 = (2 << 5) | 24, then the length byte for sizes 24..255
      expect(cborPayload[0], 0x58); // byte string with 1-byte length
      expect(cborPayload[1], psbtBytes.length);
      expect(cborPayload.sublist(2), psbtBytes);
    });

    test('Large PSBT CBOR wrapping uses 2-byte length', () {
      final psbtBytes = _makeDummyPsbt(size: 300);
      final cborPayload = _cborEncode(psbtBytes);

      // 0x59 = byte string with 2-byte length
      expect(cborPayload[0], 0x59);
      final length = (cborPayload[1] << 8) | cborPayload[2];
      expect(length, psbtBytes.length);
    });

    test('Decoded payload contains PSBT magic bytes', () {
      final psbtBytes = _makeDummyPsbt(size: 100);
      final cborPayload = _cborEncode(psbtBytes);

      final encoder = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: 30, minLength: 10);

      final decoder = UR();
      for (var i = 0; i < 200; i++) {
        decoder.read(encoder.next());
        if (decoder.isComplete) break;
      }

      expect(decoder.isComplete, isTrue);
      final decodedCbor = cbor.decode(decoder.payload);
      final extractedPsbt = Uint8List.fromList((decodedCbor as CborBytes).bytes);

      // Verify PSBT magic
      expect(extractedPsbt[0], 0x70); // p
      expect(extractedPsbt[1], 0x73); // s
      expect(extractedPsbt[2], 0x62); // b
      expect(extractedPsbt[3], 0x74); // t
      expect(extractedPsbt[4], 0xff);
    });

    test('Base64 PSBT string round-trips through UR encoding', () {
      // Simulate the actual flow: base64 PSBT string -> UR QR -> scan -> base64 string
      final psbtBytes = _makeDummyPsbt(size: 150);
      final originalBase64 = base64Encode(psbtBytes);

      // Encode (same as animated_qr_view.dart)
      final decodedPsbt = base64Decode(originalBase64);
      final cborPayload = Uint8List.fromList(cbor.encode(CborBytes(decodedPsbt)));
      final encoder = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: 40, minLength: 10);

      // Generate and scan frames (same as qr_scanner_provider.dart)
      final decoder = UR();
      for (var i = 0; i < 200; i++) {
        decoder.read(encoder.next());
        if (decoder.isComplete) break;
      }

      // Decode (same as qr_scanner_provider.dart / sign_transaction_screen.dart)
      final decoded = cbor.decode(decoder.payload);
      final resultPsbtBytes = decoded is CborBytes
          ? Uint8List.fromList(decoded.bytes)
          : decoder.payload;
      final resultBase64 = base64Encode(resultPsbtBytes);

      expect(resultBase64, originalBase64);
    });

    test('Progress tracking works during multi-part decode', () {
      final psbtBytes = _makeDummyPsbt(size: 500);
      final cborPayload = _cborEncode(psbtBytes);

      final encoder = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: 50, minLength: 10);
      final decoder = UR();

      bool sawProgress = false;
      for (var i = 0; i < 200; i++) {
        decoder.read(encoder.next());
        if (decoder.isComplete) break;

        final expected = decoder.expectedPartIndexes.length;
        final received = decoder.receivedPartIndexes.length;
        if (expected > 0 && received > 0) {
          sawProgress = true;
          expect(received, lessThanOrEqualTo(expected));
        }
      }

      expect(decoder.isComplete, isTrue);
      expect(sawProgress, isTrue, reason: 'Should have seen intermediate progress');
    });
  });
}
