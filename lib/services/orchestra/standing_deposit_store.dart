import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_model.dart' show disclosedKuteFeeBps;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraReceiveAddressCapabilities;
import 'package:kute/services/orchestra/receive_route_availability.dart'
    show ReceiveRouteAvailability;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/tracking_service.dart';

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

/// Kute's backend did not pin the venue-withdrawal fee on the
/// Investing-withdrawal instruction, so nothing may be sent to it.
class InvestingWithdrawalTermsUnavailable implements Exception {
  const InvestingWithdrawalTermsUnavailable();

  @override
  String toString() => 'Investing withdrawal terms unavailable';
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
    _destinations = null;
    return _mutate(() async {
      if (_opening != null) await _opening;
      await Hive.deleteBoxFromDisk(boxName);
    });
  }

  /// Label changes with the instruction's recipient AND policy revision. Old
  /// instructions remain readable; registration never mutates their fee terms.
  static String labelFor(String recipient, String asset, int revision) =>
      's${sha256.convert(utf8.encode('spark|$asset|$recipient|$revision|50')).toString().substring(0, 30)}';

  /// Funding restrictions documented separately from general swap routes
  /// (https://docs.flashnet.xyz/orchestra/deposit-addresses: Bitcoin, EVM
  /// chains, Solana, and Tron for USDT only). HyperCore is an EVM address
  /// family but never a deposit source the app asks for; see
  /// [ReceiveRouteAvailability.isHyperCoreSource].
  static bool supportsSource(String chain, String asset) =>
      !ReceiveRouteAvailability.isHyperCoreSource(chain) &&
      (kEvmAddressChains.contains(chain) ||
          chain == 'solana' ||
          chain == 'bitcoin' ||
          (chain == 'tron' && asset.toUpperCase() == 'USDT'));

  /// The provider's standing destination pairs ('chain:ASSET'), read at
  /// most every [_destinationsMaxAge]. The bitcoin receive asks this on
  /// every pick and the answer (spark:BTC absent, on 2026-09-25 and still
  /// on 2026-10-12) changes by support request, not by the minute.
  static ({DateTime at, Set<String> pairs})? _destinations;
  static const Duration _destinationsMaxAge = Duration(minutes: 15);

  /// Forgets the memoised destination list (tests).
  @visibleForTesting
  static void forgetDestinations() => _destinations = null;

  /// Whether the provider lists spark:[destinationAsset] as a standing
  /// destination. A malformed answer is false and not memoised.
  static Future<bool> destinationSupported(
      String destinationAsset, bool Function() current) async {
    final cached = _destinations;
    if (cached != null &&
        DateTime.now().difference(cached.at) <= _destinationsMaxAge) {
      return cached.pairs.contains('spark:$destinationAsset');
    }
    final destinations =
        await standingRequest(operation: 'destinations', current: current);
    final rows = destinations['destinations'];
    if (rows is! List) return false;
    final pairs = <String>{
      for (final v in rows)
        if (v is Map && v['chain'] is String && v['asset'] is String)
          '${v['chain']}:${v['asset']}',
    };
    _destinations = (at: DateTime.now(), pairs: pairs);
    return pairs.contains('spark:$destinationAsset');
  }

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
          .where((own) =>
              labelFor(own, asset, revision) == label ||
              (asset == 'USDB' &&
                  investingWithdrawalLabelFor(own, revision) == label))
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
            // The Investing-withdrawal instruction carries the withdrawal
            // fee terms: it is never the address Receive shows.
            !isInvestingWithdrawalLabel(r.label) &&
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
    void reused() =>
        TrackingService.track('reusable_deposit_address_reused', params: {
          'source_chain': sourceChain,
          'source_asset': sourceAsset,
          'model': 'standing',
        });
    final held = await _reusable(
        walletId: walletId,
        recipient: recipient,
        destinationAsset: destinationAsset,
        sourceChain: sourceChain,
        scope: scope,
        valid: valid);
    if (held != null) {
      reused();
      return held;
    }
    // A destination the provider has no standing address for (spark:BTC
    // today) is answered from the memoised list before any recovery
    // read, so the bitcoin receive's standing-first question costs one
    // request per quarter hour rather than two per pick.
    if (!await destinationSupported(destinationAsset, valid)) return null;
    if (!valid()) throw StateError('Wallet changed');
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
    if (recovered != null) {
      reused();
      return recovered;
    }
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;
    if (revision == null) throw StateError('Deposit terms unavailable');
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
    TrackingService.track('reusable_deposit_address_created', params: {
      'source_chain': sourceChain,
      'source_asset': sourceAsset,
      'destination_asset': destinationAsset,
      'model': 'standing',
    });
    return updated;
  }

  // ───────────────── Investing withdrawals by CCTP ─────────────────

  /// The Investing → Dollars fallback (Circle CCTP out of HyperCore when
  /// Orchestra refuses HyperCore-source routes) lands Arbitrum USDC on a
  /// standing `arbitrum:USDC → spark:USDB` address of its own: same
  /// recipient as the Dollars receive, but registered with
  /// `kuteRoute: investing_withdrawal` so Kute's backend pins the
  /// venue-withdrawal fee rule (`venue_withdrawal`) instead of the dollar
  /// deposit one, which a plain spark:USDB instruction gets. The fee plan
  /// is frozen at creation, so this instruction is never shared with the
  /// Receive address and is only used once its stored terms say
  /// `venue_withdrawal`.
  static String investingWithdrawalLabelFor(String recipient, int revision) =>
      'w${sha256.convert(utf8.encode('investing_withdrawal|USDB|$recipient|$revision|50')).toString().substring(0, 30)}';

  static bool isInvestingWithdrawalLabel(String label) =>
      label.length == 31 && label.startsWith('w');

  /// The backend fee purpose an Investing-withdrawal instruction must
  /// carry before anything is sent to it.
  static const String investingWithdrawalFeePurpose = 'venue_withdrawal';

  /// Whether [record] is an Investing-withdrawal instruction this wallet
  /// may send to: its label, own [recipient], dollars on Spark, enabled,
  /// a valid Arbitrum address, and Kute's venue-withdrawal fee pinned.
  static String? investingWithdrawalAddress(
      StandingDepositRecord record, String recipient) {
    final policy = record.response['kuteFeePolicy'];
    final address = record.addressFor('arbitrum');
    if (!isInvestingWithdrawalLabel(record.label) ||
        record.asset != 'USDB' ||
        !sameSparkAddress(record.recipient, recipient) ||
        record.response['standingAddressId'] is! String ||
        !record.enabled ||
        policy is! Map ||
        policy['purpose'] != investingWithdrawalFeePurpose ||
        address == null ||
        formatMatchesChain('arbitrum', address, mainnet: true) !=
            AddressFormatMatch.ok) {
      return null;
    }
    return address;
  }

  /// The Investing-withdrawal instruction for [recipient], reused when
  /// this wallet already holds one with verified terms, registered
  /// through Kute's backend otherwise. [refundAddress] is the wallet's
  /// own EVM address, where Orchestra returns a generated order's refund
  /// on Arbitrum. Throws [InvestingWithdrawalTermsUnavailable] when the
  /// backend does not pin the venue-withdrawal fee (an older backend
  /// refuses `kuteRoute` with a 400): nothing is sent then.
  static Future<StandingDepositRecord> investingWithdrawalInstruction({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required bool Function() wanted,
  }) async {
    final scope = capture(walletId);
    bool valid() => current(scope) && wanted();
    if (!isSparkAddress(recipient, mainnet: true) ||
        !isEvmAddress(refundAddress)) {
      throw StateError('Invalid receiving wallet');
    }
    final held = (await records(walletId))
        .where((r) =>
            isInvestingWithdrawalLabel(r.label) &&
            sameSparkAddress(r.recipient, recipient))
        .toList()
      ..sort((a, b) => b.revision.compareTo(a.revision));
    for (final record in held) {
      if (!valid()) throw StateError('Wallet changed');
      final Map<String, dynamic> state;
      try {
        state = await standingRequest(
            operation: 'read', label: record.label, current: valid);
      } on StandingRequestException catch (e) {
        if (e.status == 404) continue;
        rethrow;
      }
      if (state['standingAddressId'] is! String ||
          state['enabled'] is! bool ||
          state['addresses'] is! Map) {
        continue;
      }
      // A read answers without the instruction; the fee terms are the
      // ones the registration stored.
      final response = {...record.response, ...state};
      await saveResponse(record, response, scope);
      final updated = record.copy(response: response);
      if (investingWithdrawalAddress(updated, recipient) != null) {
        return updated;
      }
    }
    if (!valid()) throw StateError('Wallet changed');
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;
    if (revision == null) throw const InvestingWithdrawalTermsUnavailable();
    final label = investingWithdrawalLabelFor(recipient, revision);
    final record = held.where((r) => r.label == label).firstOrNull ??
        StandingDepositRecord(
            walletId: walletId,
            label: label,
            recipient: recipient,
            asset: 'USDB',
            revision: revision);
    await ensureRecord(record, scope);
    final Map<String, dynamic> response;
    try {
      response = await standingRequest(
          operation: 'register',
          label: label,
          current: valid,
          idempotencyKey: 'register-$label',
          body: {
            'destination': {
              'chain': 'spark',
              'asset': 'USDB',
              'address': recipient
            },
            'slippageBps': 50,
            'refundAddresses': {'arbitrum': refundAddress.toLowerCase()},
            'kuteRoute': 'investing_withdrawal',
          });
    } on StandingRequestException catch (e) {
      // 400 (a backend that does not know `kuteRoute`), 409 (terms
      // conflict) and 503 (fee configuration unavailable) all mean the
      // venue-withdrawal fee cannot be guaranteed.
      if (const {400, 409, 422, 503}.contains(e.status)) {
        throw const InvestingWithdrawalTermsUnavailable();
      }
      rethrow;
    }
    final policy = response['kuteFeePolicy'];
    if (policy is! Map || policy['revision'] != revision) {
      throw const InvestingWithdrawalTermsUnavailable();
    }
    final updated = record.copy(response: response);
    await saveResponse(record, response, scope);
    if (!valid()) throw StateError('Wallet changed');
    if (investingWithdrawalAddress(updated, recipient) == null) {
      throw const InvestingWithdrawalTermsUnavailable();
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
