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
    RegExp(r'\b[a-fA-F0-9]{64}\b'),
    RegExp(r'\b(?:bc1|tb1|bcrt1)[a-zA-Z0-9]{20,90}\b', caseSensitive: false),
    RegExp(r'\b[13][a-km-zA-HJ-NP-Z1-9]{25,34}\b'),
    RegExp(r'\b[5KL][1-9A-HJ-NP-Za-km-z]{50,51}\b'),
    RegExp(r'\b(?:lnbc|lntb|lnurl)[a-z0-9]{20,}\b', caseSensitive: false),
    RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
    RegExp(r'\b(?:xprv|tprv)[a-z0-9]{30,}\b|\b(?:sk-|xai-)[a-z0-9_-]{12,}',
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

  static bool hasObviousPrivateDetails(String value) =>
      _privatePatterns.any((pattern) => pattern.hasMatch(value));

  static Future<bool> isSafe(String value) async {
    if (utf8.encode(value).length > 4000 || hasObviousPrivateDetails(value)) {
      return false;
    }
    // This is a bundled public dictionary, not any user's wallet or backup.
    final words = await (_wordList ??= rootBundle
        .loadString('lib/assets/bip39_english.txt')
        .then((text) => text.split(RegExp(r'\s+')).toSet()));
    var consecutiveSeedWords = 0;
    for (final word in value.toLowerCase().split(RegExp(r'[^a-z]+'))) {
      consecutiveSeedWords =
          words.contains(word) ? consecutiveSeedWords + 1 : 0;
      if (consecutiveSeedWords >= 12) return false;
    }
    return true;
  }
}
