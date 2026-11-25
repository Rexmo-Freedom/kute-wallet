// A new install's Settings currency comes from the device's region, written
// once; an existing install, which stored nothing and reads USD, never moves.
// These run the real boot path (openStartupHiveBoxes) against a Hive folder
// on disk, closed between "launches".

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show kSendFiatUnits;
import 'package:kute/services/device_currency.dart';
import 'package:kute/services/hive_boot.dart';
import 'package:kute/services/hive_wipe.dart';

/// What the app has after a launch on a device set to [country].
Future<String> _launch(String? country) async {
  await Hive.close();
  await openStartupHiveBoxes(region: () async => country);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final settings = await container.read(initialSettingsProvider.future);
  return settings.currency;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('country to currency', () {
    const cases = {
      // The founder's examples are the region's, whatever the language:
      // pt_BR, pt_PT, en_DE, en_GB, de_CH, sv_SE, en_US by their country.
      'BR': 'BRL',
      'PT': 'EUR',
      'DE': 'EUR',
      'GB': 'GBP',
      'CH': 'CHF',
      'SE': 'SEK',
      'US': 'USD',
      'NO': 'NOK',
      'DK': 'DKK',
      'PL': 'PLN',
      'CZ': 'CZK',
      'HU': 'HUF',
      'RO': 'RON',
      'BG': 'EUR',
      // Unmapped.
      'JP': 'USD',
      'AR': 'USD',
      'ZZ': 'USD',
      // A numeric UN region, as es_419 has.
      '419': 'USD',
    };
    cases.forEach((country, currency) {
      test('$country is $currency',
          () => expect(currencyForCountry(country), currency));
    });

    test('no region is USD', () {
      expect(currencyForCountry(null), 'USD');
      expect(currencyForCountry(''), 'USD');
    });

    test('a lower-case country still maps', () {
      expect(currencyForCountry('de'), 'EUR');
    });

    test('every eurozone member is EUR', () {
      for (final country in const [
        'AT', 'BE', 'BG', 'CY', 'DE', 'EE', 'ES', 'FI', 'FR', 'GR', 'HR',
        'IE', 'IT', 'LT', 'LU', 'LV', 'MT', 'NL', 'PT', 'SI', 'SK', //
      ]) {
        expect(currencyForCountry(country), 'EUR', reason: country);
      }
    });
  });

  group('the currency lists agree', () {
    final supported = {for (final c in AppCurrencies.supportedFiats) c.isoCode};

    test('a device only defaults to a currency Settings offers', () {
      expect(supported, containsAll(kCountryCurrency.values.toSet()));
    });

    test('the Settings list, the fetched rates and the Send are the same', () {
      final source =
          File('lib/screens/settings/settings.dart').readAsStringSync();
      final listed = RegExp(r"\('([A-Z]{3})', Flags\.")
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(listed, supported);
      expect(kSendFiatUnits, supported);
    });
  });

  group('a launch', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('device_currency_test');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a new install takes the region and stores it', () async {
      expect(await _launch('BR'), 'BRL');
      expect(Hive.box('settings').get('currency'), 'BRL');
    });

    test('a new install with no region, or an unmapped one, stores USD',
        () async {
      expect(await _launch(null), 'USD');
      expect(Hive.box('settings').get('currency'), 'USD');
    });

    test('the default is chosen once: a later region does not move it',
        () async {
      expect(await _launch('DE'), 'EUR');
      expect(await _launch('GB'), 'EUR');
      expect(await _launch('BR'), 'EUR');
    });

    test('an existing install with wallets and no stored value stays USD',
        () async {
      final box = await Hive.openBox('settings');
      await box.put('wallets', [
        {'id': 'w1', 'name': 'Spending'}
      ]);
      expect(await _launch('DE'), 'USD');
      expect(await _launch('BR'), 'USD');
      expect(Hive.box('settings').containsKey('currency'), isFalse);
    });

    test('an existing install that holds nothing at all stays USD', () async {
      // Opened by an older build and never written to: the file is there.
      await Hive.openBox('settings');
      expect(await _launch('DE'), 'USD');
    });

    test('a stored choice wins, on an existing install', () async {
      final box = await Hive.openBox('settings');
      await box.put('currency', 'SEK');
      expect(await _launch('DE'), 'SEK');
    });

    test('a person\'s pick over the default stays through later launches',
        () async {
      expect(await _launch('DE'), 'EUR');
      await Hive.box('settings').put('currency', 'USD');
      expect(await _launch('DE'), 'USD');
      expect(await _launch('BR'), 'USD');
    });

    test('a device wipe makes the next open a new install', () async {
      final box = await Hive.openBox('settings');
      await box.put('currency', 'SEK');
      await Hive.close();
      await wipeHiveBoxes();
      expect(Hive.box('settings').get('currency'), 'USD',
          reason: 'the test device reads en_US');
    });
  });

  test('deviceRegion off iOS is the locale country', () async {
    // The test host is not iOS, so the channel is never asked.
    expect(await deviceRegion(),
        TestWidgetsFlutterBinding.instance.platformDispatcher.locale.countryCode);
  });
}
