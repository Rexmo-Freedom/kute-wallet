import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/bbqr.dart';

Uint8List _makeDummyPsbt({int size = 200}) {
  final magic = [0x70, 0x73, 0x62, 0x74, 0xff];
  final filler = List<int>.generate(size - magic.length, (i) => i % 256);
  return Uint8List.fromList(magic + filler);
}

void main() {
  group('BBQr Encoder', () {
    test('Single part for small data', () {
      final data = _makeDummyPsbt(size: 50);
      final split = BbqrSplit.encode(data: data, tryZlib: false);

      expect(split.parts.length, 1);
      expect(split.parts.first, startsWith('B\$HP01'));
      expect(split.fileType, BbqrFileType.psbt);
      expect(split.encoding, BbqrEncoding.hex);
    });

    test('Header format is correct', () {
      final data = _makeDummyPsbt(size: 50);
      final split = BbqrSplit.encode(data: data, tryZlib: false);
      final part = split.parts.first;

      expect(part.substring(0, 2), 'B\$'); // magic
      expect(part[2], 'H'); // hex encoding
      expect(part[3], 'P'); // PSBT file type
      expect(part.substring(4, 6), '01'); // total parts = 1
      expect(part.substring(6, 8), '00'); // index = 0
    });

    test('Multiple parts for large data', () {
      final data = _makeDummyPsbt(size: 5000);
      final split = BbqrSplit.encode(data: data, maxVersion: 27, tryZlib: false);

      expect(split.parts.length, greaterThan(1));
      // All parts start with same prefix (encoding + type + total)
      final prefix = split.parts.first.substring(0, 6);
      for (final part in split.parts) {
        expect(part.substring(0, 6), prefix);
      }
    });

    test('Parts use sequential indices', () {
      final data = _makeDummyPsbt(size: 5000);
      final split = BbqrSplit.encode(data: data, maxVersion: 20, tryZlib: false);

      for (int i = 0; i < split.parts.length; i++) {
        final indexStr = split.parts[i].substring(6, 8);
        // Parse base36
        int idx = 0;
        for (int j = 0; j < indexStr.length; j++) {
          idx = idx * 36 + '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'.indexOf(indexStr[j]);
        }
        expect(idx, i);
      }
    });

    test('All content is uppercase alphanumeric', () {
      final data = _makeDummyPsbt(size: 500);
      final split = BbqrSplit.encode(data: data, tryZlib: false);

      final validChars = RegExp(r'^[0-9A-Z\$%*+\-./:]+$');
      for (final part in split.parts) {
        expect(validChars.hasMatch(part), isTrue,
            reason: 'BBQr must use only QR alphanumeric chars');
      }
    });

    test('Zlib encoding produces smaller or equal output', () {
      final data = _makeDummyPsbt(size: 3000);
      final splitHex = BbqrSplit.encode(data: data, tryZlib: false);
      final splitZlib = BbqrSplit.encode(data: data, tryZlib: true);

      // Zlib should use fewer or equal parts
      expect(splitZlib.parts.length, lessThanOrEqualTo(splitHex.parts.length));
    });
  });

  group('BBQr Decoder', () {
    test('Single part round-trip', () {
      final data = _makeDummyPsbt(size: 100);
      final split = BbqrSplit.encode(data: data, tryZlib: false);

      final joiner = BbqrJoiner();
      for (final part in split.parts) {
        joiner.addPart(part);
      }

      expect(joiner.isComplete, isTrue);
      expect(joiner.finish(), data);
    });

    test('Multi-part round-trip', () {
      final data = _makeDummyPsbt(size: 5000);
      final split = BbqrSplit.encode(data: data, maxVersion: 20, tryZlib: false);

      expect(split.parts.length, greaterThan(1));

      final joiner = BbqrJoiner();
      for (final part in split.parts) {
        joiner.addPart(part);
      }

      expect(joiner.isComplete, isTrue);
      expect(joiner.finish(), data);
    });

    test('Parts can be received in any order', () {
      final data = _makeDummyPsbt(size: 3000);
      final split = BbqrSplit.encode(data: data, maxVersion: 20, tryZlib: false);

      final joiner = BbqrJoiner();
      // Feed in reverse order
      for (final part in split.parts.reversed) {
        joiner.addPart(part);
      }

      expect(joiner.isComplete, isTrue);
      expect(joiner.finish(), data);
    });

    test('Zlib round-trip', () {
      final data = _makeDummyPsbt(size: 3000);
      final split = BbqrSplit.encode(data: data, tryZlib: true);

      final joiner = BbqrJoiner();
      for (final part in split.parts) {
        joiner.addPart(part);
      }

      expect(joiner.isComplete, isTrue);
      expect(joiner.finish(), data);
    });

    test('Progress tracking works', () {
      final data = _makeDummyPsbt(size: 5000);
      final split = BbqrSplit.encode(data: data, maxVersion: 20, tryZlib: false);

      final joiner = BbqrJoiner();
      expect(joiner.progress, 0.0);

      joiner.addPart(split.parts.first);
      expect(joiner.progress, greaterThan(0.0));
      expect(joiner.progress, lessThan(1.0));

      for (final part in split.parts.skip(1)) {
        joiner.addPart(part);
      }
      expect(joiner.progress, 1.0);
    });

    test('Rejects invalid frames', () {
      final joiner = BbqrJoiner();
      expect(joiner.addPart('hello'), isFalse);
      expect(joiner.addPart('B\$XX0100'), isFalse); // invalid encoding
      expect(joiner.addPart(''), isFalse);
    });

    test('Detects BBQr prefix correctly', () {
      final data = _makeDummyPsbt(size: 50);
      final split = BbqrSplit.encode(data: data, tryZlib: false);

      // All BBQr parts start with B$
      for (final part in split.parts) {
        expect(part.startsWith('B\$'), isTrue);
      }
    });

    test('File type is detected', () {
      final data = _makeDummyPsbt(size: 100);

      final splitPsbt = BbqrSplit.encode(data: data, fileType: BbqrFileType.psbt, tryZlib: false);
      final joiner = BbqrJoiner();
      joiner.addPart(splitPsbt.parts.first);
      expect(joiner.fileType, BbqrFileType.psbt);

      final splitTx = BbqrSplit.encode(data: data, fileType: BbqrFileType.transaction, tryZlib: false);
      final joiner2 = BbqrJoiner();
      joiner2.addPart(splitTx.parts.first);
      expect(joiner2.fileType, BbqrFileType.transaction);
    });
  });
}
