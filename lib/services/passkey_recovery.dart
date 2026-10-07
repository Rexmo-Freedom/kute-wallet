import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart';

import 'package:kute/models/breez/init.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';

/// A legacy (pre-2.x, breez-0.15.1) passkey wallet that a balance probe
/// confirmed is REAL — it holds a non-zero balance and/or has payment
/// history. Recovery only ever surfaces these; an empty, historyless
/// derivation is a phantom (the wrong credential resolved) and is never
/// offered for adoption.
@immutable
class LegacyPasskeyCandidate {
  /// The label to persist on the restored [WalletConfig] (never null —
  /// the `null`/'Default' salt is normalised to the literal 'Default' so
  /// `getMnemonic`/connect re-derive the exact same salt every time).
  final String effectiveLabel;

  /// The BIP39 mnemonic backing this wallet, extracted for downstream
  /// provisioning (Polymarket). Never shown to the user here.
  final String mnemonic;

  final int balanceSats;
  final int paymentCount;

  const LegacyPasskeyCandidate({
    required this.effectiveLabel,
    required this.mnemonic,
    required this.balanceSats,
    required this.paymentCount,
  });
}

/// Legacy passkey recovery.
///
/// Legacy wallets (breez-0.15.1) derived their seed through the app's own
/// [PasskeyPrfService]. They DID publish Nostr labels at creation, but the
/// new-SDK discovery sign-in reads them through whatever credential ITS
/// ceremony resolves, so they vanish the moment a second credential exists
/// — which is why legacy users are additionally prompted to back up their
/// recovery phrase. This class rebuilds the seed the 0.15.1 way for each
/// plausible label, then does a throwaway connect
/// ([BreezSdkSpark.probeSeed]) to read balance + history so the user can
/// confirm the wallet is theirs before adopting it.
class PasskeyRecovery {
  /// Candidate labels to probe, in priority order. Deduplicated, all
  /// normalised so the `null`/'Default' salt collapses to a single probe:
  ///   1. 'Default' — the salt EVERY early 0.15.1 passkey wallet was
  ///      created with (see `PasskeyService.getMnemonic`).
  ///   2. the locally cached label, when Hive survived and differs.
  static Future<List<String>> _candidateLabels() async {
    final labels = <String>['Default'];
    final cached = await PasskeyService.getCachedLabel();
    if (cached != null && cached.isNotEmpty && !labels.contains(cached)) {
      labels.add(cached);
    }
    return labels;
  }

  /// Derive the legacy seed for each candidate label and probe its
  /// on-chain state. Returns only REAL candidates (balance > 0 OR
  /// paymentCount > 0), most-funded first. Empty + historyless
  /// derivations are dropped — recovery must never adopt a phantom.
  ///
  /// EVERY candidate is probed (the old build listed every wallet, so a
  /// user with two funded wallets must see both). Ceremony cost stays
  /// amortised: [PasskeyPrfService] persists the PRF per salt, so an
  /// upgraded device probes its own wallet with zero prompts and each
  /// additional candidate label costs at most one pinned Face ID.
  ///
  /// PHANTOM UN-POISONING: when a label derives through a FRESH ceremony
  /// and then probes empty, the just-written seed cache is discarded (and,
  /// when that ceremony ran un-pinned, the reconciled credential pin too).
  /// Without this, one wrong pick on the OS account sheet permanently
  /// caches the wrong credential's bytes and every retry reports "no
  /// funded wallet" with no ceremony ever offered again.
  ///
  /// Throws only if the FIRST derivation throws for a non-"user
  /// cancelled" reason (PRF unavailable) — callers route that to the
  /// recovery-phrase fallback. A single label that derives but fails to
  /// probe (network) is skipped, not fatal.
  static Future<List<LegacyPasskeyCandidate>> probeLegacyCandidates() async {
    final labels = await _candidateLabels();
    final found = <LegacyPasskeyCandidate>[];
    for (final label in labels) {
      final ({Seed seed, bool fromCeremony, bool unpinned}) derived;
      try {
        // 'Default' is passed explicitly (not null) so the secure-storage
        // salt is byte-identical to what 0.15.1 wrote.
        derived = await PasskeyService.deriveLegacySeedForProbe(label);
      } catch (e) {
        // The first probe failing hard (PRF unavailable / cancelled) is
        // the whole flow failing — surface it so the caller can fall back
        // to the recovery-phrase path. A later label failing is skipped.
        if (found.isEmpty && label == labels.first) rethrow;
        continue;
      }
      final mnemonic = _mnemonicOf(derived.seed);
      if (mnemonic == null) continue;
      final probe = await _probe(derived.seed);
      if (probe == null) continue;
      if (probe.balanceSats > BigInt.zero || probe.paymentCount > 0) {
        found.add(LegacyPasskeyCandidate(
          effectiveLabel: label,
          mnemonic: mnemonic,
          balanceSats: probe.balanceSats.toInt(),
          paymentCount: probe.paymentCount,
        ));
      } else if (derived.fromCeremony) {
        // Confirmed-empty derivation from a ceremony that ran THIS call:
        // don't let it poison the persistent tiers. Trusted cache hits
        // (fromCeremony false) are never discarded.
        await PasskeyPrfService.discardDerive(label,
            dropPin: derived.unpinned);
      }
    }
    found.sort((a, b) => b.balanceSats.compareTo(a.balanceSats));
    return found;
  }

  /// Throwaway connect to an isolated storage dir to read balance +
  /// history, cleaned up afterwards. Returns null on any connect/probe
  /// failure (treated as "couldn't confirm", not "empty").
  static Future<({BigInt balanceSats, int paymentCount})?> _probe(
    Seed seed,
  ) async {
    // A dir name unique to this probe so it never collides with a real
    // wallet's `breez_<walletId>` storage. Deleted in `finally`.
    final probeId = 'recover_probe_${seed.hashCode.toUnsigned(32)}';
    ConnectRequest? req;
    try {
      req = await createConnectRequestWithSeed(seed, probeId);
      return await BreezSdkSpark().probeSeed(req);
    } catch (_) {
      return null;
    } finally {
      final dir = req?.storageDir;
      if (dir != null) {
        try {
          final d = Directory(dir);
          if (await d.exists()) await d.delete(recursive: true);
        } catch (_) {/* leftover probe dir is harmless */}
      }
    }
  }

  static String? _mnemonicOf(Seed seed) => switch (seed) {
        Seed_Mnemonic(:final mnemonic) => mnemonic,
        Seed_Entropy() => null,
      };
}
