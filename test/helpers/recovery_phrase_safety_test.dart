import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/backup_quiz.dart';
import 'package:kute/helpers/recovery_phrase_input.dart';
import 'package:kute/models/words_model.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show HdWallet;

// Public synthetic vectors. These wallets must never be funded.
const _twelve = 'abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon about';
const _fifteen = '$_twelve abandon abandon achieve';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('valid low-diversity mnemonic produces a bounded backup quiz', () async {
    expect(HdWallet.validateMnemonic(_twelve), isTrue);
    final words = _twelve.split(' ');
    expect(words.toSet(), hasLength(2));
    final dictionary = await MnemonicWords().loadWordList();
    final quiz = buildBackupQuiz(words, dictionary, random: Random(7));
    expect(quiz, hasLength(4));
    for (final entry in quiz.entries) {
      expect(entry.key, inInclusiveRange(0, 11));
      expect(entry.value, hasLength(3));
      expect(entry.value.toSet(), hasLength(3));
      expect(entry.value, contains(words[entry.key]));
      expect(entry.value.every(dictionary.contains), isTrue);
    }
  });

  test('quiz dictionary failure rejects immediately without a sampling loop',
      () {
    expect(() => buildBackupQuiz(_twelve.split(' '), ['abandon', 'about']),
        throwsFormatException);
  });

  test('15-word phrase with a valid 12-word prefix is never truncated', () {
    expect(HdWallet.validateMnemonic(_fifteen), isTrue);
    expect(HdWallet.validateMnemonic(_fifteen.split(' ').take(12).join(' ')),
        isTrue);
    for (final allowPartial in [false, true]) {
      expect(
          () => RecoveryPhraseInput.parse(_fifteen, allowPartial: allowPartial),
          throwsFormatException);
    }
  });

  for (final count in [13, 15, 18, 21, 25, 27]) {
    test('rejects unsupported $count-word paste and scan', () {
      final input = List.filled(count, 'abandon').join(' ');
      for (final allowPartial in [false, true]) {
        expect(
            () => RecoveryPhraseInput.parse(input, allowPartial: allowPartial),
            throwsFormatException);
      }
    });
  }

  test('full supported phrase normalizes whitespace and preserves every word',
      () {
    final input = RecoveryPhraseInput.parse(
        '  ${_twelve.toUpperCase().replaceAll(' ', '\n\t')}  ',
        startIndex: 9,
        wordCount: 24,
        allowPartial: true);
    expect(input.words.join(' '), _twelve);
    expect(input.startIndex, 0);
    expect(input.wordCount, 12);
  });

  test('24-word full phrase resizes the general recovery form', () {
    final words = [...List.filled(23, 'abandon'), 'art'];
    expect(HdWallet.validateMnemonic(words.join(' ')), isTrue);
    final input =
        RecoveryPhraseInput.parse(words.join(' '), allowPartial: true);
    expect(input.words, words);
    expect(input.wordCount, 24);
    expect(input.startIndex, 0);
    expect(
        () => RecoveryPhraseInput.parse(words.join(' '),
            bitcoinOnly: true, allowPartial: true),
        throwsFormatException);
  });

  test('partial paste fits visible slots or fails without dropping words', () {
    final input = RecoveryPhraseInput.parse('about abandon',
        startIndex: 10, allowPartial: true);
    expect(input.startIndex, 10);
    expect(input.wordCount, 12);
    expect(input.words, ['about', 'abandon']);
    expect(
        () => RecoveryPhraseInput.parse('about abandon',
            startIndex: 11, allowPartial: true),
        throwsFormatException);
    expect(
        () => RecoveryPhraseInput.parse('about abandon', allowPartial: false),
        throwsFormatException);
  });

  test('normalize turns a messy paste into plain words', () {
    final messy = _twelve
        .split(' ')
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value.toUpperCase()}')
        .join(',\n');
    expect(RecoveryPhraseInput.normalize(messy), _twelve);
    expect(RecoveryPhraseInput.normalize('  1) abandon;  2)\tabout  '),
        'abandon about');
    expect(RecoveryPhraseInput.parse(RecoveryPhraseInput.normalize(messy))
        .words, _twelve.split(' '));
  });
}
