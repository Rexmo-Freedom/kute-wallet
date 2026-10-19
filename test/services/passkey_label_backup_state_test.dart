// A passkey wallet is backed up once its label is on the relay. Creation
// flags the label pending BEFORE the record exists and saves the wallet
// unbacked; the publish landing flips it; a kill between the save and the
// publish leaves the flag for the next launch; and a retry on resume or
// unlock sends it without a prompt once a ceremony primed the identity.

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/tracking_service.dart';

import 'support/fake_secret_store.dart';

const phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

class _Labels implements PasskeyLabels {
  final stored = <String>[];
  final failFor = <String>{};

  @override
  Future<void> store({required String label}) async {
    if (failFor.contains(label)) throw Exception('relay down');
    stored.add(label);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Client implements PasskeyClient {
  _Client(this.labelsFake);
  final _Labels labelsFake;

  @override
  PasskeyLabels labels() => labelsFake;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: phrase, passphrase: null),
        label: request.label ?? 'Default',
      ),
      labels: const [],
      credential:
          PasskeyCredential(credentialId: Uint8List.fromList([1, 2, 3])),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Settings _settings(List<WalletConfig> wallets) => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      balancePrivacy: 0,
      biometricsEnabled: true,
      bitcoinElectrumNode: 'bitcoin-mainnet.blockstream.info:50002',
      nodeType: 'Blockstream',
      reviewDone: false,
      themeMode: 'dark',
      wallets: wallets,
      activeWalletId: wallets.firstOrNull?.id,
    );

WalletConfig _passkey(String id, String label, {bool backedUp = false}) =>
    WalletConfig(
      id: id,
      name: id,
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: label,
      passkeyProvider: 'breez-0.17',
      backedUp: backedUp,
    );

Wallet _wallet(String label) => Wallet(
    seed: Seed.mnemonic(mnemonic: phrase, passphrase: null), label: label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeKeychain keychain;
  late Directory hiveDir;
  late _Labels labels;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('passkey_backup_state');
    Hive.init(hiveDir.path);
    await Hive.openBox('settings');
    labels = _Labels();
    PasskeyService.debugSetClient(_Client(labels));
    PasskeyService.debugResetPendingLabels();
    PasskeyService.labelPublishBackoff = Duration.zero;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PasskeyService.debugSetClient(null);
    PasskeyService.debugResetPendingLabels();
    PasskeyPrfService.clearMemory();
    SecretStores.debugReset();
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  /// A settings model over the Hive record list, wired as the app wires it.
  Future<SettingsModel> modelWith(List<WalletConfig> wallets) async {
    final box = Hive.box('settings');
    await box.put('wallets', wallets.map((w) => w.toMap()).toList());
    final model = SettingsModel(_settings(wallets));
    PasskeyService.labelPublishedHandler = model.markPasskeyLabelPublished;
    return model;
  }

  Future<List<Map>> storedRecords() async =>
      ((Hive.box('settings').get('wallets')) as List).cast<Map>();

  test('creating offline: pending is stored before the record, reminder shown',
      () async {
    labels.failFor.add('L · 1');
    final model = await modelWith([]);
    var pendingAtSave = false;
    final creation = PasskeyWalletCreation(
      ceremonies: PasskeyCeremonies(
        signIn: (label) async => _wallet(label),
        hasLegacyCredential: () async => false,
        hasKnownCredential: () async => false,
        cacheLabel: (_) async {},
        // markPending and publishLabel: the real ones.
      ),
      addWallet: (config) async {
        pendingAtSave = await PasskeyService.hasPendingLabel('L · 1');
        await model.addWallet(config);
      },
      primeSpark: () {},
    );
    final result =
        await creation.create(walletId: 'w1', label: 'L · 1', name: 'L');
    expect(pendingAtSave, isTrue);
    expect(result.pendingFlagged, isTrue);
    expect(result.config.backedUp, isFalse);
    // The publish runs in the background and fails: the flag stays and
    // the wallet keeps its reminder.
    await _until(() async =>
        events.any((e) => e.$1 == 'passkey_label_published'));
    expect(await PasskeyService.hasPendingLabel('L · 1'), isTrue);
    final saved = model.state.wallets.single;
    expect(saved.backedUp, isFalse);
    expect(needsWalletBackup(saved), isTrue);
    expect((await storedRecords()).single['backedUp'], false);
  });

  test('a kill between the save and the publish leaves the flag for the '
      'next launch', () async {
    await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
    await modelWith([_passkey('w1', 'L · 1')]);
    // The process dies here: nothing published, nothing cleared.

    // Next launch: the pending set hydrates from storage and the record
    // is still unbacked, so the reminder shows.
    PasskeyService.debugResetPendingLabels();
    await PasskeyService.loadPendingLabels();
    expect(PasskeyService.pendingLabels.value, {'L · 1'});
    final record = WalletConfig.fromMap((await storedRecords()).single);
    expect(record.backedUp, isFalse);
    expect(needsWalletBackup(record), isTrue);
  });

  test('a retry on resume with the identity primed publishes and clears',
      () async {
    final model = await modelWith([_passkey('w1', 'L · 1')]);
    await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');

    // The link was down when a ceremony (connect) primed the identity.
    labels.failFor.add('L · 1');
    await PasskeyService.getWallet(label: 'L · 1', legacy: false);
    await _until(() async => events.any((e) =>
        e.$1 == 'passkey_label_published' && e.$2?['trigger'] == 'retry'));
    expect(await PasskeyService.hasPendingLabel('L · 1'), isTrue);
    expect(model.state.wallets.single.backedUp, isFalse);

    // Link back; the app resumes (or unlocks): no ceremony, no prompt.
    labels.failFor.clear();
    await PasskeyService.retryPendingLabels();
    await _until(() async => !await PasskeyService.hasPendingLabel('L · 1'));
    await _until(() async => model.state.wallets.single.backedUp);
    expect(labels.stored, ['L · 1']);
    expect((await storedRecords()).single['backedUp'], true);
    expect(needsWalletBackup(model.state.wallets.single), isFalse);
  });

  test('with no ceremony in this process a resume retry sends nothing',
      () async {
    final model = await modelWith([_passkey('w1', 'L · 1')]);
    await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
    await PasskeyService.retryPendingLabels();
    await pumpEventQueue();
    expect(labels.stored, isEmpty);
    expect(await PasskeyService.hasPendingLabel('L · 1'), isTrue);
    expect(model.state.wallets.single.backedUp, isFalse);
  });

  test('a landed publish flips only the wallet carrying that label',
      () async {
    final model = await modelWith([
      _passkey('w1', 'L · 1'),
      _passkey('w2', 'M · 2'),
      _passkey('w3', 'N · 3', backedUp: true),
      WalletConfig(id: 'words', name: 'Words'),
    ]);
    expect(
        await PasskeyService.publishLabelInBackground('L · 1',
            trigger: 'create'),
        isTrue);
    await _until(() async => model.state.wallets.first.backedUp);
    final byId = {for (final w in model.state.wallets) w.id: w};
    expect(byId['w1']!.backedUp, isTrue);
    expect(byId['w2']!.backedUp, isFalse);
    expect(byId['w3']!.backedUp, isTrue);
    expect(byId['words']!.backedUp, isFalse);
  });

}

/// Poll [condition] (real storage I/O completes on its own schedule) for
/// up to two seconds.
Future<void> _until(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
