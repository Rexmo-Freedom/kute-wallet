// A passkey wallet is backed up once its label is on the relay. Creation
// flags the label pending BEFORE the record exists and saves the wallet
// unbacked; the publish landing flips it; a kill between the save and the
// publish leaves the flag for the next launch; and a retry on resume or
// unlock sends it without a prompt once a ceremony primed the identity.
// A warm device runs no ceremony, so the backup reminder stays up and its
// action (one passkey confirmation) is what guarantees the publish; every
// ceremony also checks the relay list and republishes a label it lacks.

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

  /// What the relay already lists besides [stored]; null while the relay
  /// cannot be listed.
  Set<String>? relay;
  int lists = 0;

  @override
  Future<void> store({required String label}) async {
    if (failFor.contains(label)) throw Exception('relay down');
    stored.add(label);
  }

  @override
  Future<List<String>> list() async {
    lists++;
    final listed = relay;
    if (listed == null) throw Exception('relay down');
    return [...listed, ...stored];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Client implements PasskeyClient {
  _Client(this.labelsFake);
  final _Labels labelsFake;
  final signIns = <SignInRequest>[];

  /// Thrown by the next ceremonies (a dismissed OS sheet, say).
  Object? signInError;

  /// The phrase the ceremony derives (another credential derives another).
  String derived = phrase;

  @override
  PasskeyLabels labels() => labelsFake;

  @override
  Future<SignInResponse> signIn({required SignInRequest request}) async {
    signIns.add(request);
    final error = signInError;
    if (error != null) throw error;
    return SignInResponse(
      wallet: Wallet(
        seed: Seed.mnemonic(mnemonic: derived, passphrase: null),
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
  late _Client client;
  late List<(String, Map<String, Object>?)> events;

  setUp(() async {
    keychain = FakeKeychain();
    SecretStores.debugOverride(local: keychain.local, synced: keychain.synced);
    PasskeyPrfService.clearMemory();
    hiveDir = await Directory.systemTemp.createTemp('passkey_backup_state');
    Hive.init(hiveDir.path);
    await Hive.openBox('settings');
    labels = _Labels();
    client = _Client(labels);
    PasskeyService.debugSetClient(client);
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
    // The silent retry still needs a primed identity; the reminder below
    // is what guarantees the publish on a device that runs no ceremony.
    final model = await modelWith([_passkey('w1', 'L · 1')]);
    await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
    await PasskeyService.retryPendingLabels();
    await pumpEventQueue();
    expect(labels.stored, isEmpty);
    expect(await PasskeyService.hasPendingLabel('L · 1'), isTrue);
    expect(model.state.wallets.single.backedUp, isFalse);
    expect(needsWalletBackup(model.state.wallets.single), isTrue);
  });

  /// A device that derived 'L · 1' in an earlier process: pin and seed
  /// cache stored, nothing primed in this one.
  Future<void> warmDevice() async {
    await PasskeyService.getWallet(label: 'L · 1', legacy: false);
    await pumpEventQueue();
    PasskeyService.clearSession();
    client.signIns.clear();
  }

  group('the backup reminder on a warm device', () {
    test('a pending label shows the reminder; one confirmation publishes it',
        () async {
      await warmDevice();
      final model = await modelWith([_passkey('w1', 'L · 1')]);
      // The first publish failed in an earlier process.
      await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
      PasskeyService.debugResetPendingLabels();
      PasskeyService.labelPublishedHandler = model.markPasskeyLabelPublished;
      await PasskeyService.loadPendingLabels();

      // Warm: the seed comes from the device cache, no ceremony, so the
      // silent retry cannot publish and the reminder stays.
      await PasskeyService.getWallet(label: 'L · 1', legacy: false);
      await PasskeyService.retryPendingLabels();
      await pumpEventQueue();
      expect(client.signIns, isEmpty);
      expect(labels.stored, isEmpty);
      expect(needsWalletBackup(model.state.wallets.single), isTrue);
      expect(needsPasskeyLabelPublish(model.state.wallets.single), isTrue);

      labels.relay = {};
      final result =
          await PasskeyService.finishLabelBackup('L · 1', surface: 'home');
      expect(result.succeeded, isTrue);
      expect(result.republished, 1);
      // Exactly one ceremony, for this wallet's label, pinned.
      expect(client.signIns, hasLength(1));
      expect(client.signIns.single.label, 'L · 1');
      expect(client.signIns.single.allowCredentials?.single,
          Uint8List.fromList([1, 2, 3]));
      expect(labels.stored, ['L · 1']);
      expect(await PasskeyService.hasPendingLabel('L · 1'), isFalse);
      await _until(() async => model.state.wallets.single.backedUp);
      expect((await storedRecords()).single['backedUp'], true);
      expect(
          needsWalletBackup(model.state.wallets.single,
              pendingLabels: PasskeyService.pendingLabels.value),
          isFalse);

      expect(events.map((e) => e.$1),
          containsAllInOrder(['passkey_label_backup_started',
              'passkey_label_published', 'passkey_label_backup_succeeded']));
      final published =
          events.singleWhere((e) => e.$1 == 'passkey_label_published');
      expect(published.$2, containsPair('trigger', 'reminder'));
      final succeeded =
          events.singleWhere((e) => e.$1 == 'passkey_label_backup_succeeded');
      expect(succeeded.$2, containsPair('surface', 'home'));
      expect(succeeded.$2, containsPair('labels_republished', 1));
      expect(succeeded.$2!.values, isNot(contains('L · 1')));
    });

    test('labels missing from the relay list are republished; listed ones '
        'are only confirmed', () async {
      await warmDevice();
      // The pending list was lost: w1 is unbacked with no flag, w2 is
      // backed up but its label is gone from the relay, w3 is listed but
      // still unbacked, and w4 (legacy) never publishes through this
      // identity.
      final model = await modelWith([
        _passkey('w1', 'L · 1'),
        _passkey('w2', 'M · 2', backedUp: true),
        _passkey('w3', 'N · 3'),
        WalletConfig(
            id: 'w4',
            name: 'w4',
            isPasskey: true,
            passkeyLabel: 'Default',
            backedUp: false),
      ]);
      labels.relay = {'N · 3'};

      final result =
          await PasskeyService.finishLabelBackup('L · 1', surface: 'home');
      expect(result.succeeded, isTrue);
      expect(result.republished, 2);
      expect(client.signIns, hasLength(1));
      expect(labels.stored, unorderedEquals(['L · 1', 'M · 2']));
      await _until(() async => model.state.wallets[2].backedUp);
      final byId = {for (final w in model.state.wallets) w.id: w};
      expect(byId['w1']!.backedUp, isTrue);
      expect(byId['w2']!.backedUp, isTrue);
      expect(byId['w3']!.backedUp, isTrue);
      // The legacy wallet keeps its recovery-phrase reminder.
      expect(byId['w4']!.backedUp, isFalse);
      expect(needsWalletBackup(byId['w4']!), isTrue);
      expect(
          events
              .where((e) => e.$1 == 'passkey_label_published')
              .map((e) => e.$2?['trigger']),
          everyElement('relay_check'));
    });

    test('offline: the reminder stays and nothing is marked', () async {
      await warmDevice();
      final model = await modelWith([_passkey('w1', 'L · 1')]);
      await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
      labels.failFor.add('L · 1');

      final result =
          await PasskeyService.finishLabelBackup('L · 1', surface: 'home');
      expect(result.succeeded, isFalse);
      expect(result.cancelled, isFalse);
      expect(client.signIns, hasLength(1));
      expect(await PasskeyService.hasPendingLabel('L · 1'), isTrue);
      expect(model.state.wallets.single.backedUp, isFalse);
      expect(needsWalletBackup(model.state.wallets.single), isTrue);
      final failed =
          events.singleWhere((e) => e.$1 == 'passkey_label_backup_failed');
      expect(failed.$2, containsPair('error_category', 'publish_failed'));
      expect(failed.$2, containsPair('labels_republished', 0));
    });

    test('a dismissed passkey sheet publishes nothing', () async {
      await warmDevice();
      final model = await modelWith([_passkey('w1', 'L · 1')]);
      await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
      client.signInError =
          const PasskeyError.prf(PrfProviderError.userCancelled());

      final result =
          await PasskeyService.finishLabelBackup('L · 1', surface: 'home');
      expect(result.succeeded, isFalse);
      expect(result.cancelled, isTrue);
      expect(labels.stored, isEmpty);
      expect(model.state.wallets.single.backedUp, isFalse);
      final failed =
          events.singleWhere((e) => e.$1 == 'passkey_label_backup_failed');
      expect(failed.$2, containsPair('error_category', 'user_cancelled'));
    });

    test('a ceremony that derives another seed never publishes the label',
        () async {
      await warmDevice();
      final model = await modelWith([_passkey('w1', 'L · 1')]);
      await PasskeyService.markLabelPending('L · 1', credentialHex: '010203');
      client.derived = 'zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong';

      final result =
          await PasskeyService.finishLabelBackup('L · 1', surface: 'home');
      expect(result.succeeded, isFalse);
      expect(labels.stored, isEmpty);
      expect(model.state.wallets.single.backedUp, isFalse);
    });

    test('a double tap shares one ceremony', () async {
      await warmDevice();
      await modelWith([_passkey('w1', 'L · 1')]);
      labels.relay = {};
      final results = await Future.wait([
        PasskeyService.finishLabelBackup('L · 1', surface: 'home'),
        PasskeyService.finishLabelBackup('L · 1', surface: 'home'),
      ]);
      expect(results.every((r) => r.succeeded), isTrue);
      expect(client.signIns, hasLength(1));
      expect(labels.stored, ['L · 1']);
    });
  });

  test('any ceremony also republishes a local label the relay lacks',
      () async {
    // backedUp but missing from the relay, and no pending flag left.
    final model = await modelWith([_passkey('w1', 'L · 1', backedUp: true)]);
    labels.relay = {};
    await PasskeyService.getWallet(label: 'Other · 9', legacy: false);
    await _until(() async => labels.stored.contains('L · 1'));
    expect(client.signIns, hasLength(1));
    expect(model.state.wallets.single.backedUp, isTrue);
    await _until(() async => events.any((e) =>
        e.$1 == 'passkey_label_published' &&
        e.$2?['trigger'] == 'relay_check'));
  });

  test('a silent relay check that cannot list writes nothing extra',
      () async {
    await modelWith([_passkey('w1', 'L · 1', backedUp: true)]);
    // relay stays null: the list fails.
    await PasskeyService.getWallet(label: 'Other · 9', legacy: false);
    await _until(() async => labels.lists > 0);
    await pumpEventQueue();
    expect(labels.stored, isEmpty);
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
