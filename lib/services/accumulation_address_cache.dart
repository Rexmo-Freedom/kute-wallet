import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraReceiveAddressCapabilities;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/orchestra_routes.dart';
import 'package:kute/services/security/address_guard.dart';
import 'package:kute/services/security/address_history.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/handlers/response_handlers.dart';

/// Developer-facing error when a route fell off Orchestra's catalog.
/// Screens show their own localized copy.
const String kRouteNoLongerAvailableError =
    'This swap route is no longer available. Please use a supported asset.';

/// Local cache for Orchestra accumulation addresses.
/// Addresses are persistent and reusable — we only call the API once per
/// unique (sourceChain, sourceAsset, destinationAsset, sparkAddress) tuple.
///
/// RAIL NOTE: every entry in this box was minted through
/// `OrchestraService.createAccumulationAddress` — the box has never
/// stored addresses from any other (retired) rail, so entries
/// carry no per-rail marker. Staleness here means "the (chain, asset)
/// pair fell out of Orchestra's live catalog", which [init] handles by
/// retiring the entry (see [_retiredPrefix]).
class AccumulationAddressCache {
  static const _boxName = 'accumulation_addresses';

  /// Version 3 binds reusable deposit terms to the published fee policy.
  static const int _schemaVersion = 3;

  /// Spark on this app always runs on mainnet (lib/models/breez/init.dart).
  static const bool _sparkMainnet = true;

  /// SUNSET hygiene (see lib/constants/swap_sunset.dart): keys with
  /// this prefix are entries whose (sourceChain, sourceAsset) pair is
  /// no longer on Orchestra's receive catalog. They are never returned
  /// by [getOrCreate] — handing the address out again would render the
  /// "reusable, converts automatically" promise for a route that can
  /// no longer convert, stranding the deposit — but they DO remain
  /// visible to [getAll], so background sync's sweep keeps watching
  /// them: the address was already given out and a late deposit must
  /// still be discovered and credited. To restore an entry, strip the
  /// prefix from its key.
  static const _retiredPrefix = 'retired:';

  /// Key format: "sourceChain:sourceAsset:destinationAsset:sparkAddress"
  static String _key(String sourceChain, String sourceAsset,
      String destinationAsset, String sparkAddress) {
    return '$sourceChain:$sourceAsset:$destinationAsset:$sparkAddress';
  }

  /// The mint's idempotency key: STABLE across retries of the same
  /// mint, and different for every mint that is genuinely a different
  /// request.
  ///
  /// It used to be omitted, which made `orchestra_api.dart` invent a
  /// fresh UUIDv4 per attempt, so the partner's dedup never engaged on
  /// exactly the retry it exists for: a POST that timed out or 5xx'd
  /// after the address was already created. Retrying with a new key
  /// mints a second standing address for the same tuple, and the first
  /// one is then live and unwatched.
  ///
  /// A changed fee revision uses a new retry identity. This does not establish
  /// that the provider issued new terms: its immutable configuration may replay
  /// an old address. Both the backend fee echo and prior-address check below
  /// must pass before the result can be displayed.
  ///
  /// Hashed rather than sent raw: the recipient Spark address is part
  /// of the tuple and an idempotency header is not the place for it.
  /// SHA-256 of the tuple, first 16 bytes shaped into a v4-looking
  /// UUID so it is indistinguishable from the generated ones on the
  /// wire.
  @visibleForTesting
  static String mintIdempotencyKey({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
    required String sparkAddress,
    required int? revision,
  }) {
    final tuple =
        _key(sourceChain, sourceAsset, destinationAsset, sparkAddress);
    final digest = sha256.convert(utf8.encode('$tuple:${revision ?? 'none'}'));
    final v = digest.bytes.sublist(0, 16);
    v[6] = (v[6] & 0x0f) | 0x40; // version 4 shape
    v[8] = (v[8] & 0x3f) | 0x80; // RFC 4122 variant
    String h(int i) => v[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
        '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  /// FUND-SAFETY destination lock. Accumulation addresses exist for
  /// exactly two purposes in this app: convert an inbound deposit to
  /// BITCOIN, or to DOLLARS, either way delivered ON SPARK to the
  /// USER'S OWN spark address. The recipient is a free string at the
  /// API and a bug upstream (wrong provider address, a Lightning
  /// invoice, an EVM address) would silently route every deposit
  /// somewhere else — so the single mint choke point refuses any
  /// destination outside [kAccumulationDestinationAssets] and any
  /// recipient that is not a checksummed Spark address.
  ///
  /// The dollar balance earned its place here in September 2026: it is
  /// a first-class Orchestra asset the live catalog routes to and from
  /// nearly everything, and both destinations land in the same wallet,
  /// so the safety property the lock exists for is unchanged.
  static const Set<String> kAccumulationDestinationAssets = {
    'BTC',
    kOrchestraUsdAssetCode,
  };

  static const String kInvalidDestinationError =
      'Refused: accumulation destination must be bitcoin or dollars on '
      'Spark to the user\'s own spark address';

  @visibleForTesting
  static bool sameFrozenFeeTerms(
      OrchestraAccumulationAddress a, OrchestraAccumulationAddress b) {
    if (a.feePolicyRevision != null &&
        a.feePolicyRevision == b.feePolicyRevision) {
      return true;
    }
    final left = a.kuteFeePolicy;
    final right = b.kuteFeePolicy;
    if (left == null || right == null) return false;
    // Provider-default pricing has no complete local snapshot of frozen fees.
    if (left['providerDefault'] == true ||
        right['providerDefault'] == true ||
        left['appFeeBps'] is! int ||
        right['appFeeBps'] is! int) {
      return false;
    }
    return left['appFeeBps'] == right['appFeeBps'] &&
        left['affiliateId'] == right['affiliateId'] &&
        left['purpose'] == right['purpose'];
  }

  /// Full bech32m Spark address check (`sp1…` and `spark1…` spellings).
  static bool isSparkFormatAddress(String address) =>
      isSparkAddress(address.trim(), mainnet: _sparkMainnet);

  /// Live reusable-route helpers preserve the exact source token. A remaining
  /// USDC row cannot authorize a cached USDC.e address on the same chain.
  /// Before the first usable catalog, the existing static fallback applies.
  static bool _isCurrentlySupported(String sourceChain, String sourceAsset,
      {String destinationAsset = 'BTC'}) {
    return orchestraReceiveChainForDestination(sourceAsset, sourceChain,
            destinationAsset: destinationAsset) !=
        null;
  }

  /// Why a cached [addr] must not be served for [sourceChain] and
  /// [recipientSparkAddress], or null when it verifies. A deposit
  /// address on a chain without a local format rule is left as is.
  @visibleForTesting
  static String? reverifyFailure(
    OrchestraAccumulationAddress addr, {
    required String sourceChain,
    required String sourceAsset,
    required String recipientSparkAddress,
    String destinationAsset = 'BTC',
  }) {
    if (addr.sourceChain.trim().toLowerCase() !=
        sourceChain.trim().toLowerCase()) {
      return 'source_chain';
    }
    // USDC and USDC.e are different assets even on the same network.
    if (addr.sourceAsset.trim().toLowerCase() !=
        sourceAsset.trim().toLowerCase()) {
      return 'source_asset';
    }
    if (!addr.enabled) return 'disabled';
    if (addr.destinationAsset != destinationAsset) return 'destination_asset';
    if (!isSparkAddress(addr.recipientSparkAddress, mainnet: _sparkMainnet)) {
      return 'recipient_format';
    }
    if (!sameSparkAddress(addr.recipientSparkAddress, recipientSparkAddress)) {
      return 'recipient';
    }
    if (formatMatchesChain(sourceChain, addr.depositAddress ?? '',
            mainnet: _sparkMainnet) ==
        AddressFormatMatch.mismatch) {
      return 'deposit_format';
    }
    return null;
  }

  /// Moves [key] under [_retiredPrefix] (never overwriting an earlier
  /// retirement of the same tuple) and records the address history row.
  static Future<void> _retire(
    Box<String> box,
    String key,
    String raw,
    AddressRetireReason reason, {
    bool removeActive = true,
  }) async {
    var retiredKey = '$_retiredPrefix$key';
    if (box.containsKey(retiredKey)) {
      retiredKey =
          '$_retiredPrefix${DateTime.now().millisecondsSinceEpoch}:$key';
    }
    await box.put(retiredKey, raw);
    // A concurrent mint may have replaced the active record while the
    // retired copy was written. Retire only the record we inspected.
    if (removeActive && box.get(key) == raw) await box.delete(key);
    try {
      final addr = OrchestraAccumulationAddress.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      await AddressHistory.record(AddressHistoryEntry(
        venue: 'orchestra',
        role: 'accumulation_deposit',
        chain: addr.sourceChain,
        asset: addr.sourceAsset,
        address: addr.depositAddress ?? '',
        createdAt: addr.createdAt,
        retiredAt: DateTime.now(),
        reason: reason,
      ));
    } catch (_) {
      // Corrupt payload: the entry is still retired, only the row is lost.
    }
  }

  /// Get or create an accumulation address for the given pair.
  /// Returns cached address if available, otherwise creates a new one via API.
  ///
  /// [refundAddresses] (source-chain slug → user-controlled address on
  /// that chain) is forwarded on CREATION only — cached addresses keep
  /// whatever refund mapping they were created with. Pass it whenever
  /// the depositing wallet is the user's own; receive flows watching
  /// external senders have nothing truthful to put here and omit it.
  static Future<Result<OrchestraAccumulationAddress>> getOrCreate({
    required String sourceChain,
    required String sourceAsset,
    required String destinationAsset,
    required String recipientSparkAddress,
    Map<String, String>? refundAddresses,
  }) async {
    // Destination lock FIRST — before cache reads, before any network.
    // Every receive/move pick must land as spark bitcoin or spark
    // dollars in the user's own spark wallet; anything else is refused
    // outright (see [kInvalidDestinationError]).
    if (!kAccumulationDestinationAssets.contains(destinationAsset) ||
        !isSparkFormatAddress(recipientSparkAddress)) {
      return Result(error: kInvalidDestinationError);
    }

    // A reusable address is still a new-deposit entrypoint when displayed,
    // so it answers to the gates the backend asks of minting one:
    // `crypto.deposit` and the route itself. Background monitoring uses
    // getAll and keeps existing deposits visible.
    try {
      await RuntimeCapabilitiesService.instance.ensureAllAllowed(
          orchestraReceiveAddressCapabilities(
              sourceChain: sourceChain,
              sourceAsset: sourceAsset,
              destinationAsset: destinationAsset));
    } on CapabilityUnavailableException catch (error) {
      return Result(error: error.decision.message);
    }

    final key =
        _key(sourceChain, sourceAsset, destinationAsset, recipientSparkAddress);
    final box = Hive.box<String>(_boxName);
    final revision = RuntimeCapabilitiesService.instance.snapshot?.revision;

    // FUND-SAFETY gate: never hand out (or mint) an address for a pair
    // Orchestra's current receive catalog doesn't carry. Call sites
    // already filter through orchestraReceiveChainFor before getting
    // here, but the catalog can change between mint and reuse — and a
    // cached address rendered under the "reusable, converts
    // automatically" promise for a dead route would strand deposits.
    if (!_isCurrentlySupported(sourceChain, sourceAsset,
        destinationAsset: destinationAsset)) {
      final cached = box.get(key);
      if (cached != null) {
        await _retire(box, key, cached, AddressRetireReason.catalog);
        TrackingService.reusableDepositAddressRetired(
          sourceChain: sourceChain,
          sourceAsset: sourceAsset,
        );
      }
      return Result(error: kRouteNoLongerAvailableError);
    }

    // Check cache. A hit is re-verified before reuse: an entry whose
    // recorded terms no longer match (wrong recipient, wrong deposit
    // format for the chain) is retired and a fresh address is minted.
    var cached = box.get(key);
    if (cached != null) {
      final previous = cached;
      try {
        final addr = OrchestraAccumulationAddress.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
        if (revision == null || addr.feePolicyRevision != revision) {
          // Never reinterpret an issued address under new fees. Keep watching
          // it with its original terms, while the new POST verifies new terms.
          await _retire(box, key, cached, AddressRetireReason.policy);
          cached = null;
        }
      } catch (_) {
        await _retire(box, key, previous, AddressRetireReason.reverify);
        cached = null;
      }
    }
    if (cached != null) {
      try {
        final addr = OrchestraAccumulationAddress.fromJson(
            jsonDecode(cached) as Map<String, dynamic>);
        if (addr.depositAddress != null && addr.depositAddress!.isNotEmpty) {
          final failure = reverifyFailure(
            addr,
            sourceChain: sourceChain,
            sourceAsset: sourceAsset,
            recipientSparkAddress: recipientSparkAddress,
            destinationAsset: destinationAsset,
          );
          if (failure == null) {
            TrackingService.reusableDepositAddressReused(
              sourceChain: sourceChain,
              sourceAsset: sourceAsset,
            );
            return Result(data: addr);
          }
          await _retire(box, key, cached, AddressRetireReason.reverify);
          TrackingService.accumulationAddressReverifyFailed(reason: failure);
        }
      } catch (_) {
        // Corrupt cache entry — recreate
      }
    }

    // Not cached — create via API
    final result = await OrchestraService.createAccumulationAddress(
      sourceChain: sourceChain,
      sourceAsset: sourceAsset,
      destinationAsset: destinationAsset,
      recipientSparkAddress: recipientSparkAddress,
      refundAddresses: refundAddresses,
      idempotencyKey: mintIdempotencyKey(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationAsset: destinationAsset,
        sparkAddress: recipientSparkAddress,
        revision: revision,
      ),
    );

    // Echo check: the server must confirm the exact destination we
    // asked for (the backend may respell sp1… as spark1…). A response
    // claiming a different destinationAsset or recipient, or a deposit
    // address in the wrong format for the chain, is never surfaced (the
    // QR/copy row would collect deposits routed elsewhere) and never
    // cached.
    final minted = result.data;
    if (minted != null &&
        (minted.destinationAsset != destinationAsset ||
            reverifyFailure(
                  minted,
                  sourceChain: sourceChain,
                  sourceAsset: sourceAsset,
                  recipientSparkAddress: recipientSparkAddress,
                  destinationAsset: destinationAsset,
                ) !=
                null)) {
      return Result(error: kInvalidDestinationError);
    }

    if (minted != null) {
      for (final raw in box.values) {
        final prior = OrchestraAccumulationAddress.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        if (prior.sourceChain != sourceChain ||
            prior.sourceAsset != sourceAsset ||
            prior.destinationAsset != destinationAsset ||
            !sameSparkAddress(
                prior.recipientSparkAddress, recipientSparkAddress) ||
            prior.depositAddress != minted.depositAddress) {
          continue;
        }
        // The provider freezes legacy terms at creation. Never reinterpret an
        // existing physical address under changed or unknown fee terms, even
        // if a new request/idempotency key was used. Keep its old record watched.
        if (!sameFrozenFeeTerms(prior, minted)) {
          return Result(
              error:
                  'Reusable deposit terms changed. Use a one-time deposit address.');
        }
      }
    }

    if (result.data != null) {
      TrackingService.reusableDepositAddressCreated(
        sourceChain: sourceChain,
        sourceAsset: sourceAsset,
        destinationAsset: destinationAsset,
      );
      // Cache the result
      final json = {
        'schema': _schemaVersion,
        'accumulationAddressId': result.data!.id,
        'sourceChain': result.data!.sourceChain,
        'sourceAsset': result.data!.sourceAsset,
        'destinationAsset': result.data!.destinationAsset,
        'recipientSparkAddress': result.data!.recipientSparkAddress,
        'depositAddress': result.data!.depositAddress,
        'label': result.data!.label,
        'enabled': result.data!.enabled,
        'createdAt': result.data!.createdAt,
        'kuteFeePolicy': result.data!.kuteFeePolicy,
        if (refundAddresses != null) 'refundAddresses': refundAddresses,
      };
      final raw = jsonEncode(json);
      // The catalog may change during the mint. Keep the issued address
      // monitored for late deposits, but never advertise withdrawn terms.
      if (!_isCurrentlySupported(sourceChain, sourceAsset,
          destinationAsset: destinationAsset)) {
        await _retire(box, key, raw, AddressRetireReason.catalog,
            removeActive: false);
        return Result(error: kRouteNoLongerAvailableError);
      }
      await box.put(key, raw);
      // Re-check after the asynchronous storage write as well.
      if (!_isCurrentlySupported(sourceChain, sourceAsset,
          destinationAsset: destinationAsset)) {
        await _retire(box, key, raw, AddressRetireReason.catalog);
        return Result(error: kRouteNoLongerAvailableError);
      }
    }

    return result;
  }

  /// Stops advertising every entry delivering to [sparkAddress] (for
  /// rotation or a suspected compromise). Retired entries stay in
  /// [getAll], so background sync keeps watching them for late
  /// deposits; the addresses are not deleted at Orchestra. Returns how
  /// many entries were retired.
  static Future<int> retireForRecipient(
    String sparkAddress,
    AddressRetireReason reason,
  ) async {
    if (!Hive.isBoxOpen(_boxName)) return 0;
    final box = Hive.box<String>(_boxName);
    var retired = 0;
    for (final key in box.keys.whereType<String>().toList()) {
      if (key.startsWith(_retiredPrefix)) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      String recipient;
      try {
        recipient = OrchestraAccumulationAddress.fromJson(
                jsonDecode(raw) as Map<String, dynamic>)
            .recipientSparkAddress;
      } catch (_) {
        continue;
      }
      if (!sameSparkAddress(recipient, sparkAddress)) continue;
      await _retire(box, key, raw, reason);
      retired++;
    }
    return retired;
  }

  /// Every cached accumulation address with a usable deposit address.
  /// Powers background sync's off-screen deposit sweep: the receive
  /// screen's history poller dies with the screen, but the addresses it
  /// hands out are reusable forever, so deposits keep arriving after it
  /// closes and someone has to keep watching. Corrupt entries are
  /// skipped (getOrCreate recreates them on next use). RETIRED entries
  /// (see [_retiredPrefix]) are deliberately INCLUDED: the UI must never
  /// offer them again, but the sweep must keep watching addresses that
  /// were already handed out in case a late deposit lands.
  static List<OrchestraAccumulationAddress> getAll() {
    // Box opens in main.dart via [init]; the guard covers early callers
    // racing startup — returning empty just delays the sweep one tick.
    if (!Hive.isBoxOpen(_boxName)) return const [];
    final box = Hive.box<String>(_boxName);
    final out = <OrchestraAccumulationAddress>[];
    for (final raw in box.values) {
      try {
        final addr = OrchestraAccumulationAddress.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        if (addr.depositAddress != null && addr.depositAddress!.isNotEmpty) {
          out.add(addr);
        }
      } catch (_) {
        // Corrupt cache entry — skip
      }
    }
    return out;
  }

  /// Initialize the Hive boxes. Call once at app startup.
  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    await AddressHistory.open();
    await _retireUnsupportedEntries();
  }

  /// SUNSET hygiene, run once per startup: move entries whose
  /// (sourceChain, sourceAsset) pair is off Orchestra's receive catalog
  /// under [_retiredPrefix] so [getOrCreate] can never serve them
  /// again. Runs before the live Flashnet catalog is fetched, so the
  /// deliberately conservative static tables (orchestra_routes.dart)
  /// decide — an entry retired here that the live catalog still
  /// carries just gets re-minted through the API on next use, which is
  /// safe (accumulation addresses are keyed server-side by the same
  /// tuple). Nothing is deleted; restoring an entry is one key rename.
  static Future<void> _retireUnsupportedEntries() async {
    final box = Hive.box<String>(_boxName);
    for (final key in box.keys.whereType<String>().toList()) {
      if (key.startsWith(_retiredPrefix)) continue;
      final raw = box.get(key);
      if (raw == null) continue;
      String? chain;
      String? asset;
      String? destination;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        chain = json['sourceChain'] as String?;
        asset = json['sourceAsset'] as String?;
        destination = json['destinationAsset'] as String?;
      } catch (_) {
        // Corrupt entry — leave it; getOrCreate's parse guard owns it.
        continue;
      }
      if (chain == null || asset == null) continue;
      // Dollar-destination entries have no static table to be judged
      // against — this sweep runs before the live catalog lands, so
      // judging them here would retire every one of them on every
      // launch. getOrCreate's own gate decides at use time, when the
      // catalog is in hand.
      if (destination != null && destination != 'BTC') continue;
      if (_isCurrentlySupported(chain, asset)) continue;
      await _retire(box, key, raw, AddressRetireReason.catalog);
      TrackingService.reusableDepositAddressRetired(
        sourceChain: chain,
        sourceAsset: asset,
      );
    }
  }
}
