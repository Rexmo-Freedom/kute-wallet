import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

Uint8List _k(List<int> data) =>
    KeccakDigest(256).process(Uint8List.fromList(data));

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _word(int v) {
  final out = Uint8List(32);
  var x = BigInt.from(v);
  for (var i = 31; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  return out;
}

const _domainType = [
  Eip712Field('name', 'string'),
  Eip712Field('version', 'string'),
  Eip712Field('chainId', 'uint256'),
  Eip712Field('verifyingContract', 'address'),
];

Eip712TypedData _mail() => Eip712TypedData(
      types: const {
        'EIP712Domain': _domainType,
        'Person': [
          Eip712Field('name', 'string'),
          Eip712Field('wallet', 'address'),
        ],
        'Mail': [
          Eip712Field('from', 'Person'),
          Eip712Field('to', 'Person'),
          Eip712Field('contents', 'string'),
        ],
      },
      primaryType: 'Mail',
      domain: {
        'name': 'Ether Mail',
        'version': '1',
        'chainId': 1,
        'verifyingContract': '0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC',
      },
      message: {
        'from': {
          'name': 'Cow',
          'wallet': '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826',
        },
        'to': {
          'name': 'Bob',
          'wallet': '0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB',
        },
        'contents': 'Hello, Bob!',
      },
    );

void main() {
  group('EIP-712 specification "Mail" vectors', () {
    final mail = _mail();

    test('encodeType and typeHash', () {
      expect(mail.encodeType('Mail'),
          'Mail(Person from,Person to,string contents)Person(string name,address wallet)');
      expect(_hex(mail.typeHash('Mail')),
          'a0cedeb2dc280ba39b857546d74f5549c3a1d7bdc2dd96bf881f76108e23dac2');
    });

    test('domain separator, struct hash and digest', () {
      expect(_hex(mail.domainSeparator),
          'f2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f');
      expect(_hex(mail.structHash),
          'c52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e');
      expect(_hex(mail.digest),
          'be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2');
    });

    test('the specification signature recovers to Cow', () {
      final sig = EthSignature(
        BigInt.parse(
            '4355c47d63924e8a72e509b65029052eb6c299d53a04e167c5775fd466751c9d',
            radix: 16),
        BigInt.parse(
            '07299936d304c153f6443dfa05f40ff007d72911b6f72307f996231605b91562',
            radix: 16),
        28,
      );
      expect(recoverSignerAddress(mail.digest, sig),
          '0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826');
    });

    test('a signature by the cow key recovers to Cow', () async {
      final key = EthPrivateKey.fromHex(_hex(_k(utf8.encode('cow'))));
      expect(key.address.hexEip55, '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826'); // gitleaks:allow (public test-vector address)
      final sig = await key.signToSignature(mail.digest);
      expect(
          sameEvmAddress(recoverSignerAddress(mail.digest, sig)!,
              '0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826'),
          isTrue);
    });
  });

  group('arrays', () {
    test('arrays of structs hash the concatenated struct hashes', () {
      final td = Eip712TypedData(
        types: const {
          'EIP712Domain': [Eip712Field('name', 'string')],
          'Person': [
            Eip712Field('name', 'string'),
            Eip712Field('wallet', 'address'),
          ],
          'Group': [Eip712Field('members', 'Person[]')],
        },
        primaryType: 'Group',
        domain: {'name': 'x'},
        message: {
          'members': [
            {'name': 'A', 'wallet': '0x${'11' * 20}'},
            {'name': 'B', 'wallet': '0x${'22' * 20}'},
          ],
        },
      );
      final a = td.hashStruct('Person', {'name': 'A', 'wallet': '0x${'11' * 20}'});
      final b = td.hashStruct('Person', {'name': 'B', 'wallet': '0x${'22' * 20}'});
      final expected = _k([
        ...td.typeHash('Group'),
        ..._k([...a, ...b]),
      ]);
      expect(td.encodeType('Group'),
          'Group(Person[] members)Person(string name,address wallet)');
      expect(_hex(td.structHash), _hex(expected));
    });

    test('nested, fixed and dynamic-element arrays', () {
      final b1 = Uint8List.fromList([1, 2, 3]);
      final b2 = Uint8List(0);
      final td = Eip712TypedData(
        types: const {
          'EIP712Domain': [Eip712Field('name', 'string')],
          'Grid': [
            Eip712Field('rows', 'uint256[][]'),
            Eip712Field('tags', 'bytes[]'),
            Eip712Field('pair', 'uint8[2]'),
          ],
        },
        primaryType: 'Grid',
        domain: {'name': 'x'},
        message: {
          'rows': [
            [1, 2],
            [3],
          ],
          'tags': [b1, b2],
          'pair': [7, 8],
        },
      );
      final expected = _k([
        ..._k(utf8.encode('Grid(uint256[][] rows,bytes[] tags,uint8[2] pair)')),
        ..._k([
          ..._k([..._word(1), ..._word(2)]),
          ..._k(_word(3)),
        ]),
        ..._k([..._k(b1), ..._k(b2)]),
        ..._k([..._word(7), ..._word(8)]),
      ]);
      expect(_hex(td.structHash), _hex(expected));
      expect(
          () => td.hashStruct('Grid', {
                'rows': const [],
                'tags': const [],
                'pair': [1],
              }),
          throwsArgumentError);
    });
  });

  group('primitive encoding', () {
    Eip712TypedData one(String type, Object value) => Eip712TypedData(
          types: {
            'EIP712Domain': const [Eip712Field('name', 'string')],
            'T': [Eip712Field('v', type)],
          },
          primaryType: 'T',
          domain: const {'name': 'x'},
          message: {'v': value},
        );

    test('bytes hash the raw bytes; empty bytes hash to keccak("")', () {
      final td = one('bytes', '0x');
      expect(_hex(td.encodeValue('bytes', '0x')),
          'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470');
      expect(_hex(td.encodeValue('bytes', '0xdeadbeef')),
          _hex(_k([0xde, 0xad, 0xbe, 0xef])));
    });

    test('bytesN is right padded and must be exactly N bytes', () {
      final td = one('bytes4', '0xdeadbeef');
      expect(_hex(td.encodeValue('bytes4', '0xdeadbeef')),
          'deadbeef${'00' * 28}');
      expect(() => td.encodeValue('bytes4', '0xdead'), throwsArgumentError);
    });

    test('intN uses two\'s complement and uintN rejects out of range', () {
      final td = one('int8', -1);
      expect(_hex(td.encodeValue('int8', -1)), 'ff' * 32);
      expect(() => td.encodeValue('uint8', 256), throwsArgumentError);
      expect(() => td.encodeValue('uint256', -1), throwsArgumentError);
      expect(_hex(td.encodeValue('uint256', '0x10')), _hex(_word(16)));
      expect(_hex(td.encodeValue('uint256', '16')), _hex(_word(16)));
    });

    test('bool and address', () {
      final td = one('bool', true);
      expect(_hex(td.encodeValue('bool', true)), _hex(_word(1)));
      expect(_hex(td.encodeValue('address', '0x${'ab' * 20}')),
          '${'00' * 12}${'ab' * 20}');
      expect(() => td.encodeValue('address', '0x1234'), throwsArgumentError);
    });
  });

  group('strictness', () {
    test('missing and extra fields throw instead of encoding zero', () {
      final mail = _mail();
      expect(() => mail.hashStruct('Person', {'name': 'Cow'}),
          throwsArgumentError);
      expect(
          () => mail.hashStruct('Person', {
                'name': 'Cow',
                'wallet': '0x${'11' * 20}',
                'extra': 1,
              }),
          throwsArgumentError);
    });

    test('unknown types and a missing domain type are rejected', () {
      expect(
          () => Eip712TypedData(
                types: const {
                  'EIP712Domain': [Eip712Field('name', 'string')],
                  'T': [Eip712Field('v', 'Missing')],
                },
                primaryType: 'T',
                domain: const {'name': 'x'},
                message: const {'v': 1},
              ),
          throwsArgumentError);
      expect(
          () => Eip712TypedData(
                types: const {
                  'T': [Eip712Field('v', 'uint256')],
                },
                primaryType: 'T',
                domain: const {},
                message: const {'v': 1},
              ),
          throwsArgumentError);
    });

    test('dependencies are ordered by name after the primary type', () {
      final td = Eip712TypedData(
        types: const {
          'EIP712Domain': [Eip712Field('name', 'string')],
          'A': [Eip712Field('z', 'Zed'), Eip712Field('b', 'Bee')],
          'Zed': [Eip712Field('v', 'uint8')],
          'Bee': [Eip712Field('v', 'uint8')],
        },
        primaryType: 'A',
        domain: const {'name': 'x'},
        message: const {
          'z': {'v': 1},
          'b': {'v': 2},
        },
      );
      expect(td.encodeType('A'), 'A(Zed z,Bee b)Bee(uint8 v)Zed(uint8 v)');
    });
  });
}
