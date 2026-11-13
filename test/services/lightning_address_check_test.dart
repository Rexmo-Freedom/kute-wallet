// A user@domain is a Lightning address only if its domain says so; otherwise
// it is an email. No answer says nothing and refuses nothing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/lightning_address_check.dart';

void main() {
  tearDown(LightningAddressCheck.resetForTest);

  group('statusOf', () {
    final pay = jsonEncode({'tag': 'payRequest', 'callback': 'https://x/cb'});
    test('only a real pay request is a Lightning address', () {
      expect(LightningAddressCheck.statusOf(200, pay),
          LightningAddressStatus.exists);
      expect(LightningAddressCheck.statusOf(200, '<html>Welcome</html>'),
          LightningAddressStatus.missing);
      expect(LightningAddressCheck.statusOf(200, '{"status":"ERROR"}'),
          LightningAddressStatus.missing);
      expect(LightningAddressCheck.statusOf(404, ''),
          LightningAddressStatus.missing);
    });
    test('the host\'s own trouble says nothing', () {
      for (final code in [400, 403, 429, 500, 503]) {
        expect(LightningAddressCheck.statusOf(code, ''),
            LightningAddressStatus.unknown);
      }
    });
  });

  group('keyOf', () {
    test('one form for one address', () {
      expect(LightningAddressCheck.keyOf(' Brutal@PayKute.com '),
          'brutal@paykute.com');
      expect(LightningAddressCheck.keyOf('lightning:a@b.co'), 'a@b.co');
    });
    test('anything else is not asked about', () {
      for (final s in ['bc1qabc', 'no-at.com', 'a@b', 'a b@c.com', '']) {
        expect(LightningAddressCheck.keyOf(s), isNull);
      }
    });
  });

  group('check', () {
    test('asks the LUD-16 path and remembers the answer', () async {
      final asked = <Uri>[];
      LightningAddressCheck.clientFactory = () => MockClient((r) async {
            asked.add(r.url);
            return http.Response(
                jsonEncode({'tag': 'payRequest', 'callback': 'https://x/cb'}),
                200);
          });
      expect(await LightningAddressCheck.check('brutal@paykute.com'),
          LightningAddressStatus.exists);
      expect(await LightningAddressCheck.check('brutal@paykute.com'),
          LightningAddressStatus.exists);
      expect(asked, [
        Uri.parse('https://paykute.com/.well-known/lnurlp/brutal'),
      ]);
    });

    test('an email domain that does not know the name is an email', () async {
      LightningAddressCheck.clientFactory =
          () => MockClient((_) async => http.Response('not found', 404));
      expect(await LightningAddressCheck.check('anna@gmail.com'),
          LightningAddressStatus.missing);
    });

    test('offline is unknown and not remembered', () async {
      var calls = 0;
      LightningAddressCheck.clientFactory = () => MockClient((_) async {
            calls++;
            throw http.ClientException('offline');
          });
      expect(await LightningAddressCheck.check('a@b.co'),
          LightningAddressStatus.unknown);
      expect(await LightningAddressCheck.check('a@b.co'),
          LightningAddressStatus.unknown);
      expect(calls, 2);
    });
  });
}
