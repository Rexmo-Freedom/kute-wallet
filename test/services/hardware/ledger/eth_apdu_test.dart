// Byte-exact APDU frames for the Ethereum app (app-ethereum
// doc/ethapp.adoc) and the Ledger OS dashboard commands.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/ledger/eth/eth_address_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/eth/eth_app_config_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_eip712_operations.dart';
import 'package:kute/services/hardware/ledger/eth/eth_personal_sign_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_signature.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _ascii(String s) => _hex(utf8.encode(s));

const _path = '058000002c8000003c800000000000000000000000';

void main() {
  group('BIP32 path packing', () {
    test("m/44'/60'/0'/0/0", () {
      expect(_hex(packBip32Path(kLedgerEvmDerivationPath)), _path);
    });

    test('rejects malformed paths', () {
      expect(() => packBip32Path("44'/60'"), throwsArgumentError);
      expect(() => packBip32Path("m/x'"), throwsArgumentError);
      expect(() => packBip32Path('m'), throwsArgumentError);
    });
  });

  group('dashboard commands', () {
    test('GET_APP_AND_VERSION, QUIT_APP and OPEN_APP frames', () {
      expect(getAppAndVersionApdu().toHex(), 'b001000000');
      expect(quitAppApdu().toHex(), 'b0a7000000');
      expect(openAppApdu('Ethereum').toHex(), 'e0d8000008${_ascii('Ethereum')}');
      expect(openAppApdu('Bitcoin').toHex(), 'e0d8000007${_ascii('Bitcoin')}');
    });

    test('GET_APP_AND_VERSION response parsing', () {
      final payload = Uint8List.fromList([
        0x01, 7, ...utf8.encode('Bitcoin'), 5, ...utf8.encode('2.1.3'), 1, 2, //
      ]);
      final app = parseAppAndVersion(payload);
      expect(app.name, 'Bitcoin');
      expect(app.version, '2.1.3');
      expect(app.isApp(LedgerAppId.bitcoin), isTrue);
      expect(
          parseAppAndVersion(Uint8List.fromList(
                  [0x01, 5, ...utf8.encode('BOLOS'), 5, ...utf8.encode('2.2.4')]))
              .isDashboard,
          isTrue);
      expect(() => parseAppAndVersion(Uint8List.fromList([0x02, 1])),
          throwsFormatException);
    });

    test('status words are checked on every response', () {
      expect(ledgerResponsePayload(Uint8List.fromList([1, 2, 0x90, 0x00])),
          [1, 2]);
      expect(
          () => ledgerResponsePayload(Uint8List.fromList([0x69, 0x85])),
          throwsA(isA<LedgerStatusException>()
              .having((e) => e.statusWord, 'sw', 0x6985)));
      expect(() => ledgerResponsePayload(Uint8List.fromList([0x90])),
          throwsA(isA<LedgerStatusException>()));
    });

    test('APDU data over 255 bytes is refused', () {
      expect(() => LedgerApdu(0xE0, 0x02, 0, 0, List.filled(256, 0)),
          throwsArgumentError);
    });
  });

  group('address and configuration', () {
    test('GET_ETH_PUBLIC_ADDRESS with and without display', () {
      expect(ethGetAddressApdu(display: true).toHex(), 'e002010015$_path');
      expect(ethGetAddressApdu(display: false).toHex(), 'e002000015$_path');
    });

    test('address response parsing', () {
      final addr = 'Ab' * 20;
      final payload = Uint8List.fromList(
          [65, ...List.filled(65, 4), 40, ...ascii.encode(addr)]);
      final parsed = parseEthAddressResponse(payload);
      expect(parsed.address, '0x$addr');
      expect(parsed.publicKey.length, 65);
      expect(
          () => parseEthAddressResponse(
              Uint8List.fromList([65, ...List.filled(65, 4), 39])),
          throwsFormatException);
    });

    test('GET_APP_CONFIGURATION and the 1.9.19 floor', () {
      expect(ethAppConfigApdu().toHex(), 'e006000000');
      final ok = parseEthAppConfig(Uint8List.fromList([0x01, 1, 10, 3]));
      expect(ok.version, const LedgerSemver(1, 10, 3));
      expect(ok.supports(kLedgerEthMinimumAppVersion), isTrue);
      final old = parseEthAppConfig(Uint8List.fromList([0x00, 1, 9, 18]));
      expect(old.supports(kLedgerEthMinimumAppVersion), isFalse);
      expect(
          parseEthAppConfig(Uint8List.fromList([0, 1, 9, 19]))
              .supports(kLedgerEthMinimumAppVersion),
          isTrue);
    });
  });

  group('personal message', () {
    test('a short message fits one frame', () {
      final frames = ethPersonalSignApdus(
          message: Uint8List.fromList(utf8.encode('hello')));
      expect(frames.map((f) => f.toHex()),
          ['e00800001e${_path}00000005${_ascii('hello')}']);
    });

    test('messages over one frame are chunked with P1 0x80', () {
      final message = Uint8List.fromList(List.generate(300, (i) => i & 0xff));
      final frames = ethPersonalSignApdus(message: message);
      expect(frames.length, 2);
      expect(frames[0].p1, 0x00);
      expect(frames[0].data.length, 255);
      expect(_hex(frames[0].data.sublist(0, 25)), '${_path}0000012c');
      expect(frames[1].p1, 0x80);
      expect(frames[1].data.length, 300 - 230);
      expect([...frames[0].data.sublist(25), ...frames[1].data], message);
    });
  });

  group('EIP-712 frames', () {
    Eip712TypedData typed(Map<String, List<Eip712Field>> types,
            Map<String, Object?> message) =>
        Eip712TypedData(
          types: {
            'EIP712Domain': const [Eip712Field('name', 'string')],
            ...types,
          },
          primaryType: types.keys.first,
          domain: const {'name': 'x'},
          message: message,
        );

    test('field definitions for every type family', () {
      final td = typed(const {
        'T': [
          Eip712Field('a', 'uint256'),
          Eip712Field('b', 'int8'),
          Eip712Field('c', 'address'),
          Eip712Field('d', 'bool'),
          Eip712Field('e', 'string'),
          Eip712Field('f', 'bytes32'),
          Eip712Field('g', 'bytes'),
          Eip712Field('h', 'Call[]'),
          Eip712Field('i', 'uint8[2]'),
        ],
        'Call': [Eip712Field('v', 'uint256')],
      }, const {});
      String def(int i) =>
          _hex(eip712FieldDefinition(td, td.types['T']![i]));
      expect(def(0), '4220${_ascii('\x01a')}');
      expect(def(1), '4101${_ascii('\x01b')}');
      expect(def(2), '03${_ascii('\x01c')}');
      expect(def(3), '04${_ascii('\x01d')}');
      expect(def(4), '05${_ascii('\x01e')}');
      expect(def(5), '4620${_ascii('\x01f')}');
      expect(def(6), '07${_ascii('\x01g')}');
      expect(def(7), '8004${_ascii('Call')}0100${_ascii('\x01h')}');
      expect(def(8), 'c201010102${_ascii('\x01i')}');
    });

    test('field values: minimal integers, one-byte bool, 20-byte address', () {
      expect(_hex(eip712FieldValue('uint256', 0)), '00');
      expect(_hex(eip712FieldValue('uint64', 1700000000000)), '018bcfe56800');
      expect(_hex(eip712FieldValue('int8', -1)), 'ff');
      expect(_hex(eip712FieldValue('bool', true)), '01');
      expect(_hex(eip712FieldValue('address', '0x${'Ab' * 20}')), 'ab' * 20);
      expect(_hex(eip712FieldValue('string', 'hi')), '6869');
      expect(() => eip712FieldValue('uint8', -1), throwsArgumentError);
    });

    test('values over 255 bytes are chunked with P1 0x01 then 0x00', () {
      final long = 'a' * 300;
      final td = typed(const {
        'T': [Eip712Field('s', 'string')],
      }, {
        's': long,
      });
      final frames = eip712ImplementationApdus(td);
      // domain root, domain name field, primary root, then two chunks.
      final chunks = frames.sublist(3);
      expect(chunks.length, 2);
      expect(chunks[0].toHex().substring(0, 10), 'e01c01ffff');
      expect(chunks[0].data.length, 255);
      expect(_hex(chunks[0].data.sublist(0, 2)), '012c');
      expect(chunks[1].toHex().substring(0, 10), 'e01c00ff2f');
      expect(chunks[1].data.length, 47);
    });

    test('arrays send their length before each element', () {
      final td = typed(const {
        'T': [Eip712Field('calls', 'Call[]')],
        'Call': [Eip712Field('v', 'uint256')],
      }, {
        'calls': [
          {'v': 1},
          {'v': 2},
        ],
      });
      final frames =
          eip712ImplementationApdus(td).sublist(3).map((f) => f.toHex());
      expect(frames, ['e01c000f0102', 'e01c00ff03000101', 'e01c00ff03000102']);
    });

    test('multi-dimensional arrays are not sent to the device', () {
      final td = typed(const {
        'T': [Eip712Field('m', 'uint8[][]')],
      }, const {});
      expect(() => eip712DefinitionApdus(td), throwsUnsupportedError);
    });

    test('recorded full sequence for Hyperliquid usdClassTransfer (0xa4b1)',
        () {
      final action = {
        'hyperliquidChain': 'Mainnet',
        'amount': '10.5',
        'toPerp': true,
        'nonce': 1700000000000,
      };
      final td = userSignedActionTypedData(
        primaryType: usdClassTransferPrimaryType,
        fields: usdClassTransferSignTypes,
        message: action,
        signatureChainId: 42161,
      );
      final frames = [
        ...eip712PayloadApdus(td),
        eip712SignFullApdu(),
      ].map((f) => f.toHex()).toList();
      const primary = 'HyperliquidTransaction:UsdClassTransfer';
      expect(frames, [
        // struct definitions
        'e01a00000c${_ascii('EIP712Domain')}',
        'e01a00ff060504${_ascii('name')}',
        'e01a00ff090507${_ascii('version')}',
        'e01a00ff0a422007${_ascii('chainId')}',
        'e01a00ff130311${_ascii('verifyingContract')}',
        'e01a000027${_ascii(primary)}',
        'e01a00ff120510${_ascii('hyperliquidChain')}',
        'e01a00ff080506${_ascii('amount')}',
        'e01a00ff080406${_ascii('toPerp')}',
        'e01a00ff08420805${_ascii('nonce')}',
        // domain implementation
        'e01c00000c${_ascii('EIP712Domain')}',
        'e01c00ff1c001a${_ascii('HyperliquidSignTransaction')}',
        'e01c00ff03000131',
        'e01c00ff040002a4b1',
        'e01c00ff160014${'00' * 20}',
        // message implementation
        'e01c000027${_ascii(primary)}',
        'e01c00ff090007${_ascii('Mainnet')}',
        'e01c00ff060004${_ascii('10.5')}',
        'e01c00ff03000101',
        'e01c00ff080006018bcfe56800',
        // full-implementation sign, never hash mode (P2 0x00)
        'e00c000115$_path',
      ]);
    });

    test('no frame in a full sequence uses hash-only mode', () {
      final td = l1ActionTypedData(
          connectionId: Uint8List(32), isMainnet: true);
      final all = [...eip712PayloadApdus(td), eip712SignFullApdu()];
      expect(all.where((f) => f.ins == kEthInsSignEip712 && f.p2 == 0x00),
          isEmpty);
    });
  });

  group('signature responses', () {
    test('v | r | s parsing and v normalization', () {
      final payload = Uint8List.fromList(
          [0x1c, ...List.filled(31, 0), 0x05, ...List.filled(31, 0), 0x07]);
      final sig = parseEthSignatureResponse(payload);
      expect(sig.v, 28);
      expect(sig.r, BigInt.from(5));
      expect(sig.s, BigInt.from(7));
      payload[0] = 0x00;
      expect(parseEthSignatureResponse(payload).v, 27);
      payload[0] = 0x25;
      expect(() => parseEthSignatureResponse(payload), throwsFormatException);
      expect(() => parseEthSignatureResponse(Uint8List(64)),
          throwsFormatException);
    });
  });
}
