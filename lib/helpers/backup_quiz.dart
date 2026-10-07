import 'dart:math';

/// Quiz randomness only: this never generates or changes wallet entropy.
/// Sampling from the dictionary also supports phrases with repeated words.
Map<int, List<String>> buildBackupQuiz(
    List<String> phrase, Iterable<String> wordList,
    {Random? random}) {
  if (phrase.length < 4) throw const FormatException('Invalid recovery phrase');
  final dictionary = wordList.where((word) => word.isNotEmpty).toSet();
  if (dictionary.length < 3 || !phrase.every(dictionary.contains)) {
    throw const FormatException('Recovery word list unavailable');
  }
  final rng = random ?? Random.secure();
  final indices = List<int>.generate(phrase.length, (index) => index)
    ..shuffle(rng);
  return {
    for (final index in indices.take(4))
      index: _options(phrase[index], dictionary, rng),
  };
}

List<String> _options(String correct, Set<String> dictionary, Random random) {
  final distractors = dictionary.where((word) => word != correct).toList()
    ..shuffle(random);
  return [correct, ...distractors.take(2)]..shuffle(random);
}
