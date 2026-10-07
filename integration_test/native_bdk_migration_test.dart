import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';
import 'package:path_provider/path_provider.dart';

import '../test/fixtures/native_bdk/fixture_bundle.dart';

const _temporaryPrefix = 'bdk_temp_migration_';
const _offlineEndpoint =
    OnchainEndpoint('esplora', 'https://native-bdk-migration.invalid/api');

/// This forwards to the real platform implementation. It deliberately rejects
/// networking and spending operations, even if this harness changes later.
Future<Object?> _offlineNativeTransport(
    String method, Map<String, Object?> arguments) {
  const allowed = {'mnemonic', 'derive', 'open', 'address', 'close'};
  if (!allowed.contains(method)) {
    throw StateError('Operation is not allowed in the offline migration test');
  }
  return NativeOnchainService.channel.invokeMethod<Object?>(method, arguments);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bundle =
      Map<String, Object?>.from(jsonDecode(nativeBdkFixtureJson) as Map);
  final wallets = (bundle['wallets']! as List)
      .map((value) => _WalletFixture(Map<String, Object?>.from(value as Map)))
      .toList();
  final entropyVectors = (bundle['entropy']! as List)
      .map((value) => Map<String, Object?>.from(value as Map))
      .toList();

  final service = NativeOnchainService(transport: _offlineNativeTransport);
  final primitives = NativeBitcoinPrimitives(service: service);
  Directory? fixtureDirectory;

  setUpAll(() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
          'Run this compatibility test on Android or iOS. Native BDK is required.');
    }
    final documents = await getApplicationDocumentsDirectory();
    fixtureDirectory = await documents.createTemp(_temporaryPrefix);
  });

  tearDownAll(() async {
    // If a native owner cannot close, preserve its files instead of deleting an
    // SQLite database that may still be in use. This test never opens user files.
    await service.closeAll();
    final directory = fixtureDirectory;
    if (directory != null && await directory.exists()) {
      final basename =
          directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!basename.startsWith(_temporaryPrefix)) {
        throw StateError('Unexpected migration fixture directory');
      }
      await directory.delete(recursive: true);
    }
  });

  test('the bundle covers all existing secret and watch-only wallet types', () {
    expect(entropyVectors, hasLength(3));
    expect(wallets, hasLength(16));
    final combinations = wallets
        .map((fixture) =>
            '${fixture.network.name}/${fixture.scriptType}/${fixture.kind}')
        .toSet();
    expect(combinations, hasLength(16));
    for (final network in ['bitcoin', 'testnet']) {
      for (final script in ['bip44', 'bip49', 'bip84', 'bip86']) {
        expect(combinations, contains('$network/$script/secret'));
        expect(combinations, contains('$network/$script/watch-only'));
      }
    }
  });

  testWidgets('native mnemonic conversion matches the old BDK entropy goldens',
      (tester) async {
    await tester.runAsync(() async {
      for (final vector in entropyVectors) {
        final expected = vector['mnemonic']! as String;
        final actual = await primitives
            .mnemonicFromEntropy(_decodeHex(vector['hex']! as String));
        expect(actual, expected);
        expect(await primitives.validateMnemonic(expected), isTrue);
      }
      expect(await primitives.validateMnemonic('abandon ' * 12), isFalse);
      expect(await primitives.validateMnemonic(''), isFalse);
      final generated = await primitives.generateMnemonic();
      expect(generated.split(' '), hasLength(12));
      expect(await primitives.validateMnemonic(generated), isTrue);
    });
  });

  for (final fixture in wallets) {
    testWidgets(
        '${fixture.network.name} ${fixture.scriptType} ${fixture.kind}: '
        'old descriptors, database and revealed indices remain compatible',
        (tester) async {
      await tester.runAsync(() async {
        final descriptors = await primitives.derive(
          network: fixture.network,
          mnemonic: fixture.mnemonic,
          xpub: fixture.xpub,
          scriptType: fixture.scriptType,
          masterFingerprint: fixture.masterFingerprint,
        );
        expect(descriptors.external, fixture.external,
            reason: 'External descriptor must match the old SDK exactly');
        expect(descriptors.internal, fixture.internal,
            reason: 'Change descriptor must match the old SDK exactly');
        expect(descriptors.accountXpub, fixture.accountXpub);

        final directory = fixtureDirectory!;
        final identity =
            '${fixture.network.name}_${fixture.scriptType}_${fixture.kind}';
        final database =
            File('${directory.path}/${_temporaryPrefix}$identity.sqlite');
        expect(await database.exists(), isFalse,
            reason: 'Only a new dedicated fixture path may be written');
        final originalBytes = gzip.decode(base64Decode(fixture.databaseGzip));
        expect(
            ascii.decode(originalBytes.take(15).toList()), 'SQLite format 3');
        await database.writeAsBytes(originalBytes, flush: true);

        Future<NativeWalletSession> open(String walletId,
                {String? external, String? internal}) =>
            service.open(
              walletId: walletId,
              dbPath: database.path,
              descriptor: external ?? descriptors.external,
              changeDescriptor: internal ?? descriptors.internal,
              network: fixture.network.name,
              endpoint: _offlineEndpoint,
              temporary: true,
            );

        var session = await open(identity);
        expect(session.isNewWallet, isFalse,
            reason: 'The old SQLite database must load, not be recreated');
        for (final index in [0, 5, 20]) {
          final address = await _address(session, 'peek', index: index);
          expect(address.index, index);
          expect(address.address.toString(), fixture.addresses['$index']);
        }
        final sixth = await _address(session, 'revealNext');
        expect(sixth.index, 6,
            reason:
                'The old SDK persisted external revelation through index 5');
        await session.close();

        session = await open(identity);
        expect(session.isNewWallet, isFalse);
        final seventh = await _address(session, 'revealNext');
        expect(seventh.index, 7,
            reason: 'Revelation by the new SDK must survive close and reopen');
        expect(seventh.address.toString(), isNot(sixth.address.toString()));
        await session.close();

        // A different script descriptor forces the native SQLite load mismatch
        // path. A fresh ID prevents Dart's session identity guard short-circuiting it.
        final mismatch = wallets.firstWhere((candidate) =>
            candidate.network == fixture.network &&
            candidate.kind == fixture.kind &&
            candidate.scriptType != fixture.scriptType);
        final beforeMismatch = await database.readAsBytes();
        await expectLater(
            open('$identity-mismatch',
                external: mismatch.external, internal: mismatch.internal),
            throwsA(isA<OnchainException>()
                .having((error) => error.code, 'code', 'wallet_open_failed')));
        expect(await database.exists(), isTrue);
        expect(await database.readAsBytes(), orderedEquals(beforeMismatch),
            reason: 'A failed descriptor load must preserve database bytes');

        session = await open(identity);
        expect(session.isNewWallet, isFalse);
        expect((await _address(session, 'revealNext')).index, 8,
            reason:
                'The original wallet remains usable after rejected mismatch');
        await session.close(deleteTemporary: true);
        expect(await database.exists(), isFalse);
        for (final suffix in ['-wal', '-shm']) {
          expect(await File('${database.path}$suffix').exists(), isFalse);
        }
      });
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}

Future<AddressInfo> _address(NativeWalletSession session, String mode,
        {int? index}) async =>
    AddressInfo.fromMap(await session.call('address', {
      'mode': mode,
      'keychain': 'external',
      if (index != null) 'index': index,
    }));

Uint8List _decodeHex(String hex) => Uint8List.fromList([
      for (var offset = 0; offset < hex.length; offset += 2)
        int.parse(hex.substring(offset, offset + 2), radix: 16),
    ]);

class _WalletFixture {
  final Map<String, Object?> value;
  _WalletFixture(this.value);

  Network get network => Network.values.byName(value['network']! as String);
  String get scriptType => value['scriptType']! as String;
  String? get mnemonic => value['mnemonic'] as String?;
  String? get xpub => value['xpub'] as String?;
  String get kind => xpub == null ? 'secret' : 'watch-only';
  String get external => value['external']! as String;
  String get internal => value['internal']! as String;
  String get accountXpub => value['accountXpub']! as String;
  String get databaseGzip => value['databaseGzipBase64']! as String;
  Map<String, Object?> get addresses =>
      Map<String, Object?>.from(value['addresses']! as Map);

  String get masterFingerprint {
    final explicit = value['masterFingerprint'] as String?;
    if (explicit != null) return explicit;
    if (xpub == null) return '00000000';
    final origin = RegExp(r'\[([0-9a-fA-F]{8})(?:/|\])').firstMatch(external);
    if (origin == null) {
      throw FormatException('Watch-only fixture lacks a master fingerprint');
    }
    return origin.group(1)!;
  }
}
