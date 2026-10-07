import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';

const phrase12 = 'abandon ability able about above absent '
    'absorb abstract absurd abuse access accident';
const phrase24 = '$phrase12 $phrase12';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with the BIP39 wordlist loaded', () {
    setUpAll(() => TrackingService.loadSeedWordlist());
    tearDownAll(() => TrackingService.debugSetSeedWordlist(null));

    test('a recovery phrase inside an error is redacted', () {
      expect(TrackingService.safeReason('Invalid mnemonic: $phrase12'),
          'Invalid mnemonic: [redacted]');
    });

    test('a 24 word phrase is redacted before the length cap', () {
      expect(TrackingService.safeReason('Invalid mnemonic: $phrase24'),
          'Invalid mnemonic: [redacted]');
    });

    test('runs match any case and punctuation separators', () {
      expect(
          TrackingService.safeReason('failed ["Abandon", "ABILITY", "able"]'),
          'failed ["<words>"]');
      expect(TrackingService.safeReason('mnemonic=abandon,ability,able;x'),
          'mnemonic=<words>;x');
    });

    test('the last words of the list are recognised', () {
      expect(TrackingService.safeReason('zebra zero zone zoo'), '<words>');
    });

    test('fewer than 3 words survive', () {
      expect(TrackingService.safeReason('abandon ability'), 'abandon ability');
      expect(TrackingService.safeReason('Invalid mnemonic checksum'),
          'Invalid mnemonic checksum');
    });

    // A digit between words no longer ends the run: a numbered phrase
    // ("1 abandon 2 ability 3 able") would otherwise never reach three.
    test('words split by digits still form one run', () {
      expect(TrackingService.safeReason('abandon 1 ability 2 able'), '<words>');
      expect(TrackingService.safeReason('typed: 1 abandon 2 ability 3 able'),
          'typed: 1 <words>');
    });

    test('runs of 5 or more digits are redacted, shorter ones survive', () {
      expect(TrackingService.safeReason('PIN:123456 rejected'),
          'PIN:<digits> rejected');
      expect(TrackingService.safeReason('HTTP 12345 / 1234567'),
          'HTTP <digits> / <digits>');
      expect(TrackingService.safeReason('HTTP 429 after 3 tries'),
          'HTTP 429 after 3 tries');
    });

    test('decimal amounts in error text are redacted, versions survive', () {
      expect(TrackingService.safeReason('need 0.00125 BTC, have 12.5'),
          'need <amount> BTC, have <amount>');
      expect(TrackingService.safeReason('sdk v2.1.0 at 10.0.2.2'),
          'sdk v2.1.0 at 10.0.2.2');
    });

    test('addresses and hex are still redacted', () {
      final bech32 = TrackingService.safeReason(
          'pay bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq failed')!;
      expect(bech32, contains('[redacted]'));
      expect(bech32, isNot(contains('bc1q')));
      expect(
          TrackingService.safeReason(
              'owner 0x52908400098527886E0F7030069857D2E4169EE7 mismatch'),
          'owner [redacted] mismatch');
    });

    test('crash envelopes never carry the phrase', () {
      final envelope =
          TrackingService.sanitizedErrorEnvelope(Exception(phrase12));
      expect(envelope.toString(), isNot(contains('abandon')));
      expect(envelope.toString(), contains('[redacted]'));
    });
  });

  group('before the wordlist loads', () {
    setUp(() => TrackingService.debugSetSeedWordlist(null));

    // Before the wordlist loads every short word qualifies, so the bar is
    // six words, and a capitalised word counts too (fields that
    // auto-capitalise). A capitalised word next to the phrase is therefore
    // swallowed with it.
    test('runs of 6 or more short lower or capitalised words are redacted', () {
      expect(TrackingService.safeReason('Invalid: $phrase12'), '[redacted]');
      expect(TrackingService.safeReason('ERROR: $phrase12'), 'ERROR: [redacted]');
      expect(
          TrackingService.safeReason('Abandon ability able about above absent'),
          '<words>');
    });

    test('mixed case, long or runs under 6 words survive', () {
      expect(TrackingService.safeReason('zebra zero zone'), 'zebra zero zone');
      expect(TrackingService.safeReason('Could Not Reach Server'),
          'Could Not Reach Server');
      expect(TrackingService.safeReason('connection timed out'),
          'connection timed out');
      expect(
          TrackingService.safeReason('no route to host'), 'no route to host');
    });

    test('6 digit runs are still redacted', () {
      expect(TrackingService.safeReason('code 654321'), 'code <digits>');
    });
  });
}
