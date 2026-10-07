class RecoveryPhraseInput {
  const RecoveryPhraseInput(this.words, this.startIndex, this.wordCount);

  final List<String> words;
  final int startIndex;
  final int wordCount;

  /// A pasted phrase as plain words: lowercase, numbering ("1.", "2)"),
  /// commas and line breaks dropped, single spaces. Recovery words hold
  /// letters only, so anything else is a separator.
  static String normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}]+', unicode: true), ' ')
      .trim();

  /// Complete phrases use the supported 12/24-word layouts. Partial pastes
  /// must fit the visible slots; never discard words or fill hidden slots.
  static RecoveryPhraseInput parse(
    String input, {
    int startIndex = 0,
    int wordCount = 12,
    bool bitcoinOnly = false,
    bool allowPartial = false,
  }) {
    final words = input.trim().toLowerCase().split(RegExp(r'\s+'));
    final allowed = bitcoinOnly ? const {12} : const {12, 24};
    if (allowed.contains(words.length)) {
      return RecoveryPhraseInput(List.unmodifiable(words), 0, words.length);
    }
    if (!allowPartial ||
        words.length >= 12 ||
        words.any((word) => word.isEmpty) ||
        !allowed.contains(wordCount) ||
        startIndex < 0 ||
        startIndex + words.length > wordCount) {
      throw const FormatException('Unsupported recovery phrase length');
    }
    return RecoveryPhraseInput(List.unmodifiable(words), startIndex, wordCount);
  }
}
