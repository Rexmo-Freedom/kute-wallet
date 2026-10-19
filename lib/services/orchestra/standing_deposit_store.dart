import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_model.dart' show disclosedKuteFeeBps;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/venue_owner_link_service.dart'
    show VenueOwnerLinkService;

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
      this.chain = 'spark',
      this.response = const {},
      this.refunds = const {}});
  final String walletId, label, recipient, asset;

  /// The destination's chain: `spark` for every Receive address and the
  /// Investing withdrawals home, `polygon` for an Investing → Predictions
  /// instruction. Additive: older records read back as `spark`.
  final String chain;
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
        if (chain != 'spark') 'chain': chain,
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
          chain: v['chain'] as String? ?? 'spark',
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
          chain: chain,
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

/// Where an Investing withdrawal by CCTP lands, and the fee rules Kute's
/// backend may pin on its instruction (`kuteRoute: investing_withdrawal`):
/// `venue_withdrawal` home to Spark, `investments_internal` (0 bps) for a
/// move between the wallet's own linked venue accounts. Polygon USDC.e for
/// Predictions: the asset the Polymarket deposit path already takes
/// (Dollars → Predictions lands USDC.e and wraps it).
enum InvestingWithdrawalDestination {
  dollars('spark', 'USDB',
      {kVenueWithdrawalFeePurpose, kInvestmentsInternalFeePurpose}),
  bitcoin('spark', 'BTC',
      {kVenueWithdrawalFeePurpose, kInvestmentsInternalFeePurpose}),
  predictions('polygon', 'USDC.e',
      {kInvestmentsInternalFeePurpose, kVenueWithdrawalFeePurpose});

  const InvestingWithdrawalDestination(
      this.chain, this.asset, this.feePurposes);

  final String chain;
  final String asset;

  /// The `kuteFeePolicy.purpose` values the instruction may carry; any
  /// other rule and nothing is sent to it.
  final Set<String> feePurposes;

  /// `chain:ASSET`, as the backend keys it.
  String get key => '$chain:$asset';

  /// What the label hashes: the asset alone for the Spark destinations
  /// (Dollars keeps the label it always had), chain and asset otherwise.
  String get labelKey => chain == 'spark' ? asset : key;
}

/// The rule Kute's backend pins on money leaving a venue.
const String kVenueWithdrawalFeePurpose = 'venue_withdrawal';

/// The rule for a move between the wallet's own linked venue accounts
/// (0 bps), Investing → Predictions among them.
const String kInvestmentsInternalFeePurpose = 'investments_internal';

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
              investingWithdrawalLabelFor(own, revision,
                      destination: asset == 'BTC'
                          ? InvestingWithdrawalDestination.bitcoin
                          : InvestingWithdrawalDestination.dollars) ==
                  label ||
              (asset == 'USDB' &&
                  investingWithdrawalLabelFor(own, revision, legacy: true) ==
                      label))
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

  // ───────────────── Investing withdrawals by CCTP ─────────────────

  /// Money leaves Investing by Circle CCTP out of HyperCore: Arbitrum USDC
  /// lands on a standing address of the wallet's own, which Orchestra
  /// converts to the destination. Each destination
  /// ([InvestingWithdrawalDestination]: Dollars, Bitcoin, Predictions)
  /// has its own instruction, registered with
  /// `kuteRoute: investing_withdrawal` so Kute's backend pins the
  /// destination's rule (`venue_withdrawal` home to Spark,
  /// `predictions_deposit` to the Polymarket deposit wallet) instead of
  /// the plain deposit one. The fee plan is frozen at creation, so these
  /// instructions are never shared with a Receive address and are only
  /// used once their stored terms carry the destination's purpose. A
  /// label never serves another destination (the backend answers 409).
  ///
  /// Dollars has a second scheme ([legacy] false, the default): the
  /// backend keeps a label's first pin for life, and the first Dollars
  /// labels were all pinned `venue_withdrawal` before it could pin a move
  /// home to the wallet's own Spark address as `investments_internal`.
  /// A new label is the only way to the new rule. [legacy] is the old
  /// Dollars label, kept for history and as a fallback only.
  static String investingWithdrawalLabelFor(String recipient, int revision,
          {InvestingWithdrawalDestination destination =
              InvestingWithdrawalDestination.dollars,
          bool legacy = false}) =>
      'w${sha256.convert(utf8.encode('investing_withdrawal|${destination.labelKey}|$recipient|$revision|50${destination == InvestingWithdrawalDestination.dollars && !legacy ? '|internal' : ''}')).toString().substring(0, 30)}';

  /// Whether [record] is a Dollars Investing-withdrawal instruction of the
  /// current label scheme (see [investingWithdrawalLabelFor]), for its own
  /// recipient or for [recipient]. Anything else on Dollars is legacy.
  static bool _currentDollarsLabel(
          StandingDepositRecord record, String recipient) =>
      record.label ==
          investingWithdrawalLabelFor(record.recipient, record.revision) ||
      record.label == investingWithdrawalLabelFor(recipient, record.revision);

  /// Whether [record]'s stored terms carry a rule [destination] accepts.
  static bool _verifiedTerms(StandingDepositRecord record,
      InvestingWithdrawalDestination destination) {
    final policy = record.response['kuteFeePolicy'];
    return policy is Map && destination.feePurposes.contains(policy['purpose']);
  }

  /// The Kute fee an Investing-withdrawal instruction charges on what
  /// arrives, for the withdrawal's fee line: the frozen terms' disclosed
  /// rate ([StandingDepositRecord.kuteFeeBps]), or 0 when the instruction
  /// is pinned as a move inside Investments (`investments_internal`) at no
  /// rate. Null when the terms state neither.
  static int? investingWithdrawalKuteFeeBps(StandingDepositRecord record) {
    final disclosed = record.kuteFeeBps;
    if (disclosed != null) return disclosed;
    final policy = record.response['kuteFeePolicy'];
    if (policy is Map &&
        policy['providerDefault'] != true &&
        policy['purpose'] == kInvestmentsInternalFeePurpose) {
      return 0;
    }
    return null;
  }

  static bool isInvestingWithdrawalLabel(String label) =>
      label.length == 31 && label.startsWith('w');

  /// The backend fee purpose an Investing-withdrawal instruction home
  /// carries (see [InvestingWithdrawalDestination.feePurposes] for every
  /// rule a destination accepts).
  static const String investingWithdrawalFeePurpose =
      kVenueWithdrawalFeePurpose;

  /// Whether the backend knows the Polymarket wallet [address] is this
  /// user's (`VenueOwnerLinkService`). Injectable for tests.
  static Future<bool> Function(String address) polymarketLinked =
      VenueOwnerLinkService.isPolymarketLinked;

  static bool _sameRecipient(String chain, String a, String b) =>
      chain == 'spark' ? sameSparkAddress(a, b) : sameEvmAddress(a, b);

  static bool _validRecipient(String chain, String address) => chain == 'spark'
      ? isSparkAddress(address, mainnet: true)
      : isEvmAddress(address);

  /// Whether [record] is an Investing-withdrawal instruction to
  /// [destination] this wallet may send to: its label, own [recipient],
  /// the destination's chain and asset, enabled, a valid Arbitrum
  /// address, and Kute's fee rule for the destination pinned.
  static String? investingWithdrawalAddress(
      StandingDepositRecord record, String recipient,
      {InvestingWithdrawalDestination destination =
          InvestingWithdrawalDestination.dollars}) {
    final policy = record.response['kuteFeePolicy'];
    final address = record.addressFor('arbitrum');
    if (!isInvestingWithdrawalLabel(record.label) ||
        record.chain != destination.chain ||
        record.asset != destination.asset ||
        !_sameRecipient(destination.chain, record.recipient, recipient) ||
        record.response['standingAddressId'] is! String ||
        !record.enabled ||
        policy is! Map ||
        !destination.feePurposes.contains(policy['purpose']) ||
        address == null ||
        formatMatchesChain('arbitrum', address, mainnet: true) !=
            AddressFormatMatch.ok) {
      return null;
    }
    return address;
  }

  /// The Investing-withdrawal instruction to [destination] for
  /// [recipient] (the wallet's own Spark address, or its own Polymarket
  /// deposit wallet for Predictions), reused when this wallet already
  /// holds one with verified terms, registered through Kute's backend
  /// otherwise. [refundAddress] is the wallet's own EVM address, where
  /// Orchestra returns a generated order's refund on Arbitrum. Throws
  /// [InvestingWithdrawalTermsUnavailable] when the backend does not pin
  /// the destination's fee rule: an older backend refuses `kuteRoute`
  /// (400), a gate is shut (403), the label is taken (409), the terms
  /// cannot be met (422, 503), or, for any destination but Dollars, any
  /// other refusal of the backend or the provider. Nothing is sent then.
  ///
  /// Dollars registers its current-scheme label lazily, on the first
  /// withdrawal that needs it (`investments_internal` from a backend that
  /// verifies the own Spark address, `venue_withdrawal` from an older
  /// one; both accepted). If that registration fails, a legacy Dollars
  /// instruction this wallet already holds is used instead, unless a
  /// current-scheme one has ever had verified terms. One instruction per
  /// call: the withdrawal pays exactly the one returned.
  static Future<StandingDepositRecord> investingWithdrawalInstruction({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required bool Function() wanted,
    InvestingWithdrawalDestination destination =
        InvestingWithdrawalDestination.dollars,
  }) async {
    final scope = capture(walletId);
    bool valid() => current(scope) && wanted();
    final home = destination == InvestingWithdrawalDestination.dollars;
    if (!_validRecipient(destination.chain, recipient) ||
        !isEvmAddress(refundAddress)) {
      throw StateError('Invalid receiving wallet');
    }
    final held = (await records(walletId))
        .where((r) =>
            isInvestingWithdrawalLabel(r.label) &&
            r.chain == destination.chain &&
            r.asset == destination.asset &&
            _sameRecipient(destination.chain, r.recipient, recipient))
        .toList()
      ..sort((a, b) => b.revision.compareTo(a.revision));
    // Dollars: the current label scheme first; a legacy label (pinned
    // `venue_withdrawal` for life) only when the new one cannot be had.
    final scheme = home
        ? held.where((r) => _currentDollarsLabel(r, recipient)).toList()
        : held;
    final legacy = home
        ? held.where((r) => !_currentDollarsLabel(r, recipient)).toList()
        : const <StandingDepositRecord>[];
    final reused = await _usableInvestingWithdrawal(scheme,
        recipient: recipient,
        destination: destination,
        scope: scope,
        valid: valid);
    if (reused != null) return reused;
    if (!valid()) throw StateError('Wallet changed');
    try {
      return await _registerInvestingWithdrawal(
          walletId: walletId,
          recipient: recipient,
          refundAddress: refundAddress,
          destination: destination,
          held: held,
          scope: scope,
          valid: valid);
    } catch (e, stack) {
      // A legacy Dollars instruction still works (at its frozen rate): a
      // withdrawal is not failed for want of the new label. Never once a
      // current-scheme instruction has verified terms: from then on the
      // legacy one is history only.
      if (!home ||
          legacy.isEmpty ||
          !valid() ||
          scheme.any((r) => _verifiedTerms(r, destination))) {
        rethrow;
      }
      StandingDepositRecord? fallback;
      try {
        fallback = await _usableInvestingWithdrawal(legacy,
            recipient: recipient,
            destination: destination,
            scope: scope,
            valid: valid);
      } catch (_) {
        // The registration's own failure is the one to report.
      }
      if (fallback == null || !valid()) Error.throwWithStackTrace(e, stack);
      return fallback;
    }
  }

  /// The first of [candidates] (newest first) the provider still holds,
  /// enabled, with verified terms for [destination], read (never
  /// re-registered), or null.
  static Future<StandingDepositRecord?> _usableInvestingWithdrawal(
    List<StandingDepositRecord> candidates, {
    required String recipient,
    required InvestingWithdrawalDestination destination,
    required StandingDepositScope scope,
    required bool Function() valid,
  }) async {
    final home = destination == InvestingWithdrawalDestination.dollars;
    for (final record in candidates) {
      if (!valid()) throw StateError('Wallet changed');
      final Map<String, dynamic> state;
      try {
        state = await standingRequest(
            operation: 'read', label: record.label, current: valid);
      } on StandingRequestException catch (e) {
        if (e.status == 404) continue;
        if (!home) throw const InvestingWithdrawalTermsUnavailable();
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
      if (investingWithdrawalAddress(updated, recipient,
              destination: destination) !=
          null) {
        return updated;
      }
    }
    return null;
  }

  /// Registers the current-scheme instruction to [destination] (see
  /// [investingWithdrawalInstruction] for what a refusal means). Its own
  /// label, so its own idempotency key: a key never spans two labels.
  static Future<StandingDepositRecord> _registerInvestingWithdrawal({
    required String walletId,
    required String recipient,
    required String refundAddress,
    required InvestingWithdrawalDestination destination,
    required List<StandingDepositRecord> held,
    required StandingDepositScope scope,
    required bool Function() valid,
  }) async {
    final home = destination == InvestingWithdrawalDestination.dollars;
    // Predictions is the wallet's own venue only once the backend knows
    // the Polymarket wallet is this user's (the venue-owner link): only
    // then is the instruction registered, so its terms are the internal
    // move's. Until then the money goes through Dollars.
    if (destination.chain == 'polygon' && !await polymarketLinked(recipient)) {
      throw const InvestingWithdrawalTermsUnavailable();
    }
    if (!valid()) throw StateError('Wallet changed');
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;
    if (revision == null) throw const InvestingWithdrawalTermsUnavailable();
    final label = investingWithdrawalLabelFor(recipient, revision,
        destination: destination);
    final record = held.where((r) => r.label == label).firstOrNull ??
        StandingDepositRecord(
            walletId: walletId,
            label: label,
            recipient: recipient,
            asset: destination.asset,
            chain: destination.chain,
            revision: revision);
    await ensureRecord(record, scope);
    final Map<String, dynamic> response;
    try {
      response = await standingRequest(
          operation: 'register',
          label: label,
          current: valid,
          // A linked registration never shares a key with an unlinked one
          // (the backend answers 409).
          idempotencyKey: destination.chain == 'polygon'
              ? 'register-$label-linked'
              : 'register-$label',
          body: {
            'destination': {
              'chain': destination.chain,
              'asset': destination.asset,
              'address': home || destination.chain == 'spark'
                  ? recipient
                  : recipient.toLowerCase()
            },
            'slippageBps': 50,
            'refundAddresses': {'arbitrum': refundAddress.toLowerCase()},
            'kuteRoute': 'investing_withdrawal',
          });
    } on StandingRequestException catch (e) {
      // 400 (a backend that does not know `kuteRoute`, or this
      // destination for it), 403 (a gate the destination answers to is
      // shut), 409 (terms or destination conflict), 422 and 503 (fee
      // configuration unavailable) all mean the destination's fee cannot
      // be guaranteed. Past Dollars any refusal is one: the caller goes
      // through Dollars instead.
      if (!home || const {400, 403, 409, 422, 503}.contains(e.status)) {
        throw const InvestingWithdrawalTermsUnavailable();
      }
      rethrow;
    } on StateError {
      rethrow;
    } catch (_) {
      if (home) rethrow;
      throw const InvestingWithdrawalTermsUnavailable();
    }
    final policy = response['kuteFeePolicy'];
    if (policy is! Map ||
        policy['revision'] != revision ||
        !destination.feePurposes.contains(policy['purpose'])) {
      throw const InvestingWithdrawalTermsUnavailable();
    }
    final updated = record.copy(response: response);
    await saveResponse(record, response, scope);
    if (!valid()) throw StateError('Wallet changed');
    if (investingWithdrawalAddress(updated, recipient,
            destination: destination) ==
        null) {
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
