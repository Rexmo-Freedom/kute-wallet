import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

// Published BIP32 / BIP-173 / EIP-55 / BOLT11 test vectors and example
// values only; none of these control funds.
const _secrets = <String, String>{
  'xpub':
      'xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8',
  'xprv':
      'xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi',
  'zpub':
      'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtfSdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs',
  'wif': '5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ',
  'descriptor':
      "wpkh([d34db33f/84'/0'/0']xpub6DJ2dNUysrn5Vt36jH2KLBT2i1auw1tTSSomg8PhqNiUtx8QX2SvC9nrHu81fT41fvDUnhMjEzQgXnQjKEu3oaqMSzhSrHMxyyoEAmUHQbY/0/*)#cjjspncu",
  'hex_key':
      '0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318',
  'bc1': 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
  'legacy': '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
  'evm': '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
  'spark':
      'sp1pgssyxmf9ayh6fm3wj7xhwqsn5dmxz5uyycrv82j97u3mrctxunjsxdzzudm2d',
  'bolt11':
      'lnbc2500u1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpuaztrnwngzn3kdzw5hydlzf03qdgm2hdq27cqv3agm2awhz5se903vruatfhq77w3ls4evs3ch9zw97j25emudupq63nyw24cg27h2rspfj9srp',
  'lnurl':
      'LNURL1DP68GURN8GHJ7UM9WFMXJCM99E3K7MF0V9CXJ0M385EKVCENXC6R2C35XVUKXEFCV5MKVV34X5EKZD3EV56NYD3HXQURZEPEXEJXXEPNXSCRVWFNV9NXZCN9XQ6XYEFHVGCXXCMYXYMNSERXFQ5FNS',
  'lightning_address': 'satoshi@example.com',
};

const _phrase =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

void main() {
  setUp(() {
    TrackingService.debugSetSeedWordlist({
      for (final w in _phrase.split(' ')) w,
    });
  });
  tearDown(() {
    TrackingService.debugSetSeedWordlist(null);
    TrackingService.debugTrackObserver = null;
    TrackingService.debugCrashObserver = null;
  });

  group('scrubString', () {
    for (final entry in {..._secrets, 'phrase': _phrase}.entries) {
      test('redacts ${entry.key}', () {
        final out = TrackingService.scrubString(
            'upstream said: ${entry.value} (retry later)');
        expect(out, isNot(contains(entry.value)));
        expect(out, contains(TrackingService.redacted));
        expect(out, contains('upstream said:'));
      });
    }

    test('keeps ordinary product text and public market ids', () {
      const title = 'Will Bitcoin close above 120k on Friday?';
      expect(TrackingService.scrubString(title), title);
      const condition =
          '0x9b6a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b';
      expect(
          TrackingService.scrubValue(condition, key: 'market_id'), condition);
      expect(TrackingService.scrubValue(condition, key: 'reason'),
          TrackingService.redacted);
    });
  });

  test('every tracked event is scrubbed, nested maps and lists included', () {
    Map<String, Object>? sent;
    TrackingService.debugTrackObserver = (_, params) => sent = params;
    TrackingService.track('probe', params: {
      'reason': 'failed for ${_secrets['xpub']}',
      'nested': {
        'list': ['ok', _secrets['wif']!, {'d': _secrets['descriptor']!}],
      },
      'amount_usd': 12.5,
      'order_id': 'ord_123',
    });
    final flat = sent.toString();
    for (final secret in _secrets.values) {
      expect(flat, isNot(contains(secret)));
    }
    expect(sent!['amount_usd'], 12.5);
    expect(sent!['order_id'], startsWith('ref_'));
  });

  test('Crashlytics receives only redacted text', () {
    late String message;
    String? reason;
    String? stackText;
    TrackingService.debugCrashObserver = (error, stack, r, log) {
      message = error.toString();
      reason = r;
      stackText = stack?.toString();
    };
    for (final secret in [..._secrets.values, _phrase]) {
      TrackingService.recordCrash(
        StateError('broadcast failed: $secret'),
        StackTrace.fromString('#0 send ($secret)\n#1 main (package:kute/main.dart:1:1)'),
        reason: 'while paying $secret',
      );
      expect(message, isNot(contains(secret)));
      expect(message, contains(TrackingService.redacted));
      expect(reason, isNot(contains(secret)));
      expect(stackText, isNot(contains(secret)));
      expect(stackText, contains('package:kute/main.dart'));
    }
  });

  test('a PostHog \$exception keeps only its class', () {
    final event = PostHogEvent(
      event: r'$exception',
      properties: {
        r'$exception_list': [
          {
            'type': 'StateError',
            'value': 'failed for ${_secrets['bc1']}',
            'stacktrace': {'frames': []},
          }
        ],
        r'$exception_message': 'failed for ${_secrets['bolt11']}',
      },
    );
    final out = TrackingService.sanitizeExceptionEvent(event)!;
    final entry = (out.properties![r'$exception_list'] as List).first as Map;
    expect(entry['type'], 'StateError');
    expect(entry['value'], '');
    expect(entry.containsKey('stacktrace'), isFalse);
    expect(out.properties!.containsKey(r'$exception_message'), isFalse);
  });

  test('any other SDK event has its app properties scrubbed', () {
    final event = PostHogEvent(
      event: r'$screen',
      properties: {
        r'$screen_name': 'pay ${_secrets['evm']}',
        'note': _secrets['descriptor']!,
      },
    );
    final out = TrackingService.sanitizeExceptionEvent(event)!;
    expect(out.properties.toString(), isNot(contains(_secrets['evm']!)));
    expect(out.properties.toString(), isNot(contains(_secrets['descriptor']!)));
  });

  test('the Crashlytics user id can never be an address or key', () {
    expect(TrackingService.crashlyticsUserId(_secrets['bc1']!), 'redacted');
    expect(TrackingService.crashlyticsUserId('3f1c2b9e-1a2b-4c3d-9e8f-001122334455'),
        '3f1c2b9e-1a2b-4c3d-9e8f-001122334455');
  });

  test('errorCategory is idempotent and never carries text', () {
    expect(TrackingService.errorCategory('Insufficient funds for ${_secrets['bc1']}'),
        'insufficient_funds');
    expect(TrackingService.errorCategory('rate_limited'), 'rate_limited');
    expect(TrackingService.errorCategory('invalid_destination'),
        'invalid_destination');
  });
}
