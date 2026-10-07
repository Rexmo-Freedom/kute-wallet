import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_model.dart' show disclosedKuteFeeBps;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraReceiveAddressCapabilities;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_guard.dart';

/// References and immutable terms are persisted before registration. Flashnet
/// has no reference-list endpoint; forgetting an old ref loses deposit
/// visibility, so Kute's backend keeps a recovery list of the labels this
/// wallet registered (no recipient, no address) and [StandingDepositStore.restore]
/// rebuilds the local records from it on another install.
class StandingDepositRecord {
  const StandingDepositRecord(
      {required this.walletId,
      required this.label,
      required this.recipient,
      required this.asset,
      required this.revision,
      this.response = const {},
      this.refunds = const {}});
  final String walletId, label, recipient, asset;
  final int revision;
  final Map<String, dynamic> response, refunds;
  bool get enabled => response['enabled'] == true;
  String? addressFor(String chain) =>
      (response['addresses'] as Map?)?[chain] as String?;

  /// The Kute fee these standing terms charge on what arrives. See
  /// [disclosedKuteFeeBps].
  int? get kuteFeeBps => disclosedKuteFeeBps(response['kuteFeePolicy']);
  Map<String, dynamic> toJson() => {
        'walletId': walletId,
        'label': label,
        'recipient': recipient,
        'asset': asset,
        'revision': revision,
        'response': response,
        'refunds': refunds
      };
  factory StandingDepositRecord.fromJson(Map<String, dynamic> v) =>
      StandingDepositRecord(
          walletId: v['walletId'] as String,
          label: v['label'] as String,
          recipient: v['recipient'] as String,
          asset: v['asset'] as String,
          revision: v['revision'] as int,
          response: Map<String, dynamic>.from(v['response'] as Map),
          refunds: Map<String, dynamic>.from(v['refunds'] as Map? ?? {}));
  StandingDepositRecord copy(
          {Map<String, dynamic>? response, Map<String, dynamic>? refunds}) =>
      StandingDepositRecord(
          walletId: walletId,
          label: label,
          recipient: recipient,
          asset: asset,
          revision: revision,
          response: response ?? this.response,
          refunds: refunds ?? this.refunds);
}

class StandingDepositScope {
  const StandingDepositScope(
      this.walletId, this.generation, this.walletGeneration);
  final String walletId;
  final int generation, walletGeneration;
}

abstract final class StandingDepositStore {
  static const boxName = 'standing_deposits_v1';
  static int _generation = 0;
  static final _walletGeneration = <String, int>{};
  static Future<void> _tail = Future.value();
  static Future<Box<String>>? _opening;
  static StandingDepositScope capture(String wallet) =>
      StandingDepositScope(wallet, _generation, _walletGeneration[wallet] ?? 0);
  static bool current(StandingDepositScope scope) =>
      scope.generation == _generation &&
      scope.walletGeneration == (_walletGeneration[scope.walletId] ?? 0);
  static Future<Box<String>> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box<String>(boxName)
      : await (_opening ??=
          Hive.openBox<String>(boxName).whenComplete(() => _opening = null));
  static Future<void> _mutate(Future<void> Function() f) {
    final result = _tail.then((_) => f());
    _tail = result.catchError((Object _) {});
    return result;
  }

  static String _key(StandingDepositRecord r) => '${r.walletId}:${r.label}';
  static Future<void> save(
          StandingDepositRecord r, StandingDepositScope scope) =>
      _mutate(() async {
        if (!current(scope) || r.walletId != scope.walletId) {
          throw StateError('Wallet cleared');
        }
        final box = await _box();
        if (!current(scope)) throw StateError('Wallet cleared');
        await box.put(_key(r), jsonEncode(r.toJson()));
        await box.flush();
        if (!current(scope)) throw StateError('Wallet cleared');
      });

  /// Registration may race a refund or a refresh; create only if absent.
  static Future<void> ensureRecord(
          StandingDepositRecord record, StandingDepositScope scope) =>
      _mutate(() async {
        if (!current(scope) || record.walletId != scope.walletId) {
          throw StateError('Wallet cleared');
        }
        final box = await _box();
        if (!current(scope)) throw StateError('Wallet cleared');
        if (!box.containsKey(_key(record))) {
          await box.put(_key(record), jsonEncode(record.toJson()));
          await box.flush();
        }
      });

  /// Atomically changes one deposit's journal, preserving concurrent deposits.
  /// A refusal can only release the exact request that was refused.
  static Future<void> recordRefund({
    required StandingDepositRecord record,
    required StandingDepositScope scope,
    required String depositId,
    required String requestKey,
    required String address,
    bool refused = false,
  }) =>
      _mutate(() async {
        if (!current(scope) || record.walletId != scope.walletId) {
          throw StateError('Wallet cleared');
        }
        final box = await _box();
        if (!current(scope)) throw StateError('Wallet cleared');
        final raw = box.get(_key(record));
        if (raw == null) throw StateError('Deposit reference missing');
        final latest = StandingDepositRecord.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        final previous = latest.refunds[depositId];
        if (refused) {
          if (previous is! Map || previous['key'] != requestKey) return;
        } else if (previous != null &&
            (previous is! Map || previous['state'] != 'refused')) {
          throw StateError('Refund already requested');
        }
        await box.put(
            _key(record),
            jsonEncode(latest.copy(refunds: {
              ...latest.refunds,
              depositId: {
                'key': requestKey,
                'address': address,
                'state': refused ? 'refused' : 'requested'
              },
            }).toJson()));
        await box.flush();
        if (!current(scope)) throw StateError('Wallet cleared');
      });

  static Future<void> saveResponse(StandingDepositRecord record,
          Map<String, dynamic> response, StandingDepositScope scope) =>
      _mutate(() async {
        if (!current(scope) || record.walletId != scope.walletId) {
          throw StateError('Wallet cleared');
        }
        final box = await _box();
        if (!current(scope)) throw StateError('Wallet cleared');
        final raw = box.get(_key(record));
        if (raw == null) return;
        final latest = StandingDepositRecord.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        await box.put(
            _key(record), jsonEncode(latest.copy(response: response).toJson()));
        await box.flush();
      });

  static Future<List<StandingDepositRecord>> records(String wallet) async {
    await _tail;
    final box = await _box();
    return box.values
        .map((v) => StandingDepositRecord.fromJson(
            jsonDecode(v) as Map<String, dynamic>))
        .where((r) => r.walletId == wallet)
        .toList();
  }

  static Future<void> deleteWallet(String wallet) {
    _walletGeneration[wallet] = (_walletGeneration[wallet] ?? 0) + 1;
    return _mutate(() async {
      final box = await _box();
      await box.deleteAll(
          box.keys.where((k) => k.toString().startsWith('$wallet:')).toList());
      await box.flush();
    });
  }

  static Future<void> clear() {
    _generation++;
    return _mutate(() async {
      if (_opening != null) await _opening;
      await Hive.deleteBoxFromDisk(boxName);
    });
  }

  /// Label changes with the instruction's recipient AND policy revision. Old
  /// instructions remain readable; registration never mutates their fee terms.
  static String labelFor(String recipient, String asset, int revision) =>
      's${sha256.convert(utf8.encode('spark|$asset|$recipient|$revision|50')).toString().substring(0, 30)}';

  /// Funding restrictions documented separately from general swap routes.
  static bool supportsSource(String chain, String asset) =>
      kEvmAddressChains.contains(chain) ||
      chain == 'solana' ||
      chain == 'bitcoin' ||
      (chain == 'tron' && asset.toUpperCase() == 'USDT');

  /// Runs one standing-address operation. Injectable so registration,
  /// reuse, restore and the deposit listing can be exercised without the
  /// network; production goes through OrchestraService.
  static Future<Map<String, dynamic>> Function(
      {required String operation,
      String? label,
      required bool Function() current,
      Map<String, dynamic>? body,
      String? idempotencyKey,
      int offset}) standingRequest = (
          {required operation,
          label,
          required current,
          body,
          idempotencyKey,
          offset = 0}) =>
      OrchestraService.standingRequest(
          operation: operation,
          label: label,
          current: current,
          body: body,
          idempotencyKey: idempotencyKey,
          offset: offset);

  /// Recovers references another install of this wallet registered.
  ///
  /// The backend lists labels with their asset and fee-policy revision, and
  /// nothing else. A listed reference is admitted only when it provably
  /// pays a recipient this wallet owns: its label reproduces from
  /// [recipient] (or from a recipient already recorded for this wallet)
  /// under those terms, or the provider's stored instruction names one of
  /// those recipients. The listing is session-scoped server side, but that
  /// alone is not taken as proof. Records already held locally, refund
  /// journals included, are never replaced: the stored instruction is
  /// read, never re-registered, so frozen terms stay frozen. Returns how
  /// many references were added.
  static Future<int> restore({
    required String walletId,
    required String? recipient,
    required bool Function() wanted,
  }) async {
    final scope = capture(walletId);
    bool valid() => current(scope) && wanted();
    final listing = await standingRequest(operation: 'mine', current: valid);
    final rows = listing['references'];
    if (rows is! List) throw const FormatException('Invalid reference list');
    final local = await records(walletId);
    final known = local.map((r) => r.label).toSet();
    final ownRecipients = {
      if (recipient != null) recipient,
      ...local.map((r) => r.recipient),
    };
    if (ownRecipients.isEmpty) return 0;
    var restored = 0;
    for (final row in rows) {
      if (!valid()) throw StateError('Wallet changed');
      if (row is! Map) continue;
      final label = row['label'];
      final asset = row['destinationAsset'];
      final revision = row['policyRevision'];
      if (label is! String ||
          asset is! String ||
          revision is! int ||
          revision <= 0 ||
          row['destinationChain'] != 'spark' ||
          !const {'BTC', 'USDB'}.contains(asset) ||
          known.contains(label)) {
        continue;
      }
      String? owner = ownRecipients
          .where((own) => labelFor(own, asset, revision) == label)
          .firstOrNull;
      final state = await standingRequest(
          operation: 'read', label: label, current: valid);
      if (state['standingAddressId'] is! String ||
          state['enabled'] is! bool ||
          state['addresses'] is! Map) {
        continue;
      }
      if (owner == null) {
        final destination = state['destination'];
        final address = destination is Map ? destination['address'] : null;
        if (address is String && ownRecipients.contains(address)) {
          owner = address;
        }
      }
      if (owner == null) continue;
      await ensureRecord(
          StandingDepositRecord(
              walletId: walletId,
              label: label,
              recipient: owner,
              asset: asset,
              revision: revision,
              response: Map<String, dynamic>.from(state)),
          scope);
      known.add(label);
      restored++;
    }
    return restored;
  }

  /// The standing instruction this wallet already holds for
  /// [destinationAsset] on [recipient] that still answers with a usable
  /// address on [sourceChain], newest first, or null.
  ///
  /// One address per coin and network: Receive shows the same address
  /// every time rather than a new one per visit or per policy revision.
  /// Each candidate's state is read (never re-registered), so an
  /// instruction the provider has paused or no longer knows is passed
  /// over. A reused instruction keeps the fee terms frozen when it was
  /// registered.
  static Future<StandingDepositRecord?> _reusable({
    required String walletId,
    required String recipient,
    required String destinationAsset,
    required String sourceChain,
    required StandingDepositScope scope,
    required bool Function() valid,
  }) async {
    final candidates = (await records(walletId))
        .where((r) =>
            r.asset == destinationAsset &&
            sameSparkAddress(r.recipient, recipient) &&
            r.response['standingAddressId'] is String)
        .toList()
      ..sort((a, b) => b.revision.compareTo(a.revision));
    for (final record in candidates) {
      if (!valid()) throw StateError('Wallet changed');
      final Map<String, dynamic> state;
      try {
        state = await standingRequest(
            operation: 'read', label: record.label, current: valid);
      } on StandingRequestException catch (e) {
        // The provider no longer holds this instruction: not reusable.
        if (e.status == 404) continue;
        rethrow;
      }
      if (state['standingAddressId'] is! String ||
          state['enabled'] is! bool ||
          state['addresses'] is! Map) {
        continue;
      }
      final response = {...record.response, ...state};
      await saveResponse(record, response, scope);
      if (!valid()) throw StateError('Wallet changed');
      final updated = record.copy(response: response);
      if (!updated.enabled) continue;
      final address = updated.addressFor(sourceChain);
      if (address == null ||
          formatMatchesChain(sourceChain, address, mainnet: true) !=
              AddressFormatMatch.ok) {
        continue;
      }
      return updated;
    }
    return null;
  }

  /// The standing address Receive shows for [sourceChain]/[sourceAsset]
  /// into [destinationAsset]. An instruction this wallet already holds
  /// (locally, or registered by another install and listed by the
  /// backend) is reused; a new one is registered only when none is
  /// usable. Null when the provider offers no standing address here and
  /// the caller should use the legacy rail.
  static Future<StandingDepositRecord?> register(
      {required String walletId,
      required String recipient,
      required String destinationAsset,
      required String sourceChain,
      required String sourceAsset,
      required bool Function() wanted}) async {
    if (!supportsSource(sourceChain, sourceAsset)) return null;
    final scope = capture(walletId);
    bool valid() => current(scope) && wanted();
    if (!isSparkAddress(recipient, mainnet: true) ||
        !{'BTC', 'USDB'}.contains(destinationAsset)) {
      throw StateError('Invalid receiving wallet');
    }
    // Showing an address is a new-deposit entrypoint whether it is reused
    // or new: the same gates the backend asks of minting one.
    await RuntimeCapabilitiesService.instance.ensureAllAllowed(
        orchestraReceiveAddressCapabilities(
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            destinationAsset: destinationAsset));
    if (!valid()) throw StateError('Wallet changed');
    final held = await _reusable(
        walletId: walletId,
        recipient: recipient,
        destinationAsset: destinationAsset,
        sourceChain: sourceChain,
        scope: scope,
        valid: valid);
    if (held != null) return held;
    // Another install may have registered one. Recover those first, both
    // to reuse them and so their held deposits stay visible; a failed
    // recovery read must not stop registration, which replays
    // idempotently.
    try {
      await restore(walletId: walletId, recipient: recipient, wanted: wanted);
    } catch (_) {}
    if (!valid()) throw StateError('Wallet changed');
    final recovered = await _reusable(
        walletId: walletId,
        recipient: recipient,
        destinationAsset: destinationAsset,
        sourceChain: sourceChain,
        scope: scope,
        valid: valid);
    if (recovered != null) return recovered;
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;
    if (revision == null) throw StateError('Deposit terms unavailable');
    final destinations =
        await standingRequest(operation: 'destinations', current: valid);
    final rows = destinations['destinations'];
    if (rows is! List ||
        !rows.any((v) =>
            v is Map &&
            v['chain'] == 'spark' &&
            v['asset'] == destinationAsset)) {
      return null;
    }
    final label = labelFor(recipient, destinationAsset, revision);
    final existing = await records(walletId);
    final record = existing.where((r) => r.label == label).firstOrNull ??
        StandingDepositRecord(
            walletId: walletId,
            label: label,
            recipient: recipient,
            asset: destinationAsset,
            revision: revision);
    // Persist even before an uncertain registration response. No address is
    // displayed until this write and the verified response are both durable.
    await ensureRecord(record, scope);
    final response = await standingRequest(
        operation: 'register',
        label: label,
        current: valid,
        idempotencyKey: 'register-$label',
        body: {
          'destination': {
            'chain': 'spark',
            'asset': destinationAsset,
            'address': recipient
          },
          'slippageBps': 50
        });
    final policy = response['kuteFeePolicy'];
    if (policy is! Map ||
        policy['revision'] != revision ||
        response['standingAddressId'] is! String ||
        response['enabled'] is! bool ||
        response['addresses'] is! Map) {
      throw StateError('Deposit terms changed');
    }
    final updated = record.copy(response: response);
    await saveResponse(record, response, scope);
    if (!valid()) throw StateError('Wallet changed');
    if (!updated.enabled) throw StateError('This deposit address is paused');
    final address = updated.addressFor(sourceChain);
    if (address == null) return null; // Provider has no address on this source.
    if (formatMatchesChain(sourceChain, address, mainnet: true) !=
        AddressFormatMatch.ok) {
      throw StateError('Invalid deposit address');
    }
    return updated;
  }

  static Future<List<Map<String, dynamic>>> deposits(
      StandingDepositRecord record, bool Function() current) async {
    final deposits = <Map<String, dynamic>>[];
    var offset = 0;
    final seen = <int>{};
    while (seen.add(offset)) {
      final page = await standingRequest(
          operation: 'deposits',
          label: record.label,
          current: current,
          offset: offset);
      final rows = page['deposits'];
      if (rows is! List) throw const FormatException('Invalid deposit list');
      deposits.addAll(rows.map((v) => Map<String, dynamic>.from(v as Map)));
      final next = page['nextOffset'];
      if (next == null) break;
      if (next is! int || next <= offset) {
        throw const FormatException('Invalid deposit pagination');
      }
      offset = next;
      if (seen.length >= 100) {
        throw StateError('Deposit history pagination exceeded');
      }
    }
    return deposits;
  }
}
