import 'dart:convert';

import 'package:flutter/services.dart';

/// Blocks recognisable private text before transport. This is a precaution,
/// not a claim that arbitrary prose can be anonymised automatically.
class AdvisorInputGuard {
  AdvisorInputGuard._();

  static const message =
      'Please remove private details such as wallet addresses, recovery phrases, '
      'email addresses or personal account amounts, then ask a general question.';

  static final _privatePatterns = <RegExp>[
    RegExp(r'\b0x[a-fA-F0-9]{40,64}\b'),
    // A private key (64 hex) or a BIP39 seed (128 hex).
    RegExp(r'\b[a-fA-F0-9]{64,128}\b'),
    RegExp(r'\b(?:bc1|tb1|bcrt1)[a-zA-Z0-9]{20,90}\b', caseSensitive: false),
    RegExp(r'\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b'),
    // WIF private keys, mainnet (5, K, L) and testnet (9, c).
    RegExp(r'\b[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}\b'),
    RegExp(r'\b(?:lnbc|lntb|lnurl)[a-z0-9]{20,}\b', caseSensitive: false),
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
    // Extended private keys of every SLIP-132 flavour (xprv, yprv, zprv,
    // Yprv, Zprv, tprv, uprv, vprv, Uprv, Vprv), bare or in a descriptor.
    RegExp(r'\b[xyztuv]prv[a-z0-9]{30,}\b|\b(?:sk-|xai-)[a-z0-9_-]{12,}',
        caseSensitive: false),
    RegExp(
        r'\b(?:private key|recovery phrase|seed phrase|secret key|secret phrase|mnemonic|password|api key)\s*(?:is\s+|[:=]\s*)\S+',
        caseSensitive: false),
    RegExp(
        r'\b(?:my|our)\s+(?:\w+\s+){0,3}(?:balance|position|portfolio|holding|holdings|investment|account|wallet|pnl|income|salary|savings)\b[^.!?\n]{0,70}\d',
        caseSensitive: false),
    RegExp(
        r'\bi\s+(?:have|hold|own|invested|bought|sold|earned|lost|spent|deposited|withdrew)\s+(?:\w+\s+){0,3}[$€£]?\s*\d',
        caseSensitive: false),
  ];
  static Future<Set<String>>? _wordList;

  /// The four-letter prefixes of the list last checked against.
  static Set<String>? _prefixesOf;
  static Set<String> _prefixes = const {};

  /// Seed-like words in a row that block the text: a recovery phrase is 12
  /// or 24, and ordinary market questions stay at 5 or fewer.
  static const int seedRunLimit = 6;

  /// Seed-like words, and their share of all words, that block the text
  /// even when typos break the run: a phrase typed with a mistake every few
  /// words. Ordinary questions stay far below both.
  static const int seedCountLimit = 9;
  static const double seedShareLimit = 0.8;

  static bool hasObviousPrivateDetails(String value) =>
      _privatePatterns.any((pattern) => pattern.hasMatch(value));

  /// Whether [value] reads like (part of) a recovery phrase against the
  /// BIP39 list [words]. A word counts when it is in the list or starts
  /// with the first four letters of a listed word (BIP39 words are unique
  /// in their first four letters), so a typo at a word's end does not
  /// break the run. Pure for the tests.
  static bool looksLikeSeedPhrase(String value, Set<String> words) {
    if (!identical(words, _prefixesOf)) {
      _prefixesOf = words;
      _prefixes = {
        for (final w in words)
          if (w.length >= 4) w.substring(0, 4),
      };
    }
    final prefixes = _prefixes;
    bool seedLike(String t) =>
        words.contains(t) ||
        (t.length >= 4 && prefixes.contains(t.substring(0, 4)));
    final tokens = [
      for (final t in value.toLowerCase().split(RegExp(r'[^a-z]+')))
        if (t.isNotEmpty) t,
    ];
    var run = 0;
    var count = 0;
    for (final t in tokens) {
      if (seedLike(t)) {
        run++;
        count++;
        if (run >= seedRunLimit) return true;
      } else {
        run = 0;
      }
    }
    return count >= seedCountLimit && count >= seedShareLimit * tokens.length;
  }

  static final _secretPatterns = <RegExp>[
    RegExp(r'\b[xyztuv]prv[a-z0-9]{30,}', caseSensitive: false),
    RegExp(r'^[5KL9c][1-9A-HJ-NP-Za-km-z]{50,51}$'),
    // A bare 64-hex private key or 128-hex BIP39 seed (no 0x: never an
    // address).
    RegExp(r'^[a-fA-F0-9]{64}(?:[a-fA-F0-9]{64})?$'),
  ];

  /// Whether [value] is a recovery phrase or a private key (a scanned code,
  /// a pasted destination): narrower than [isSafe], which also refuses
  /// addresses and amounts. Never treated as somewhere to send.
  static Future<bool> holdsSecret(String value) async {
    final v = value.trim();
    if (_secretPatterns.any((p) => p.hasMatch(v))) return true;
    final words = await (_wordList ??= rootBundle
        .loadString('lib/assets/bip39_english.txt')
        .then((text) => {
              for (final w in text.split(RegExp(r'\s+')))
                if (w.isNotEmpty) w,
            }));
    return looksLikeSeedPhrase(v, words);
  }

  /// Whether [value] may leave the device (Sal, market search): nothing
  /// that reads like an address, key, phrase or personal amount. Fails
  /// closed on any doubt; never the place to anonymise free text.
  static Future<bool> isSafe(String value) async {
    if (utf8.encode(value).length > 4000 || hasObviousPrivateDetails(value)) {
      return false;
    }
    // This is a bundled public dictionary, not any user's wallet or backup.
    final words = await (_wordList ??= rootBundle
        .loadString('lib/assets/bip39_english.txt')
        .then((text) => {
              for (final w in text.split(RegExp(r'\s+')))
                if (w.isNotEmpty) w,
            }));
    return !looksLikeSeedPhrase(value, words);
  }
}
