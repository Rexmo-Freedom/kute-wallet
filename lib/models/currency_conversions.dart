import 'package:money2/money2.dart';

class AppCurrencies {
  static final Currency usd = CommonCurrencies().usd;
  static final Currency eur = CommonCurrencies().euro;
  static final Currency gbp = CommonCurrencies().gbp;
  static final Currency chf = CommonCurrencies().chf;
  static final Currency brl = CommonCurrencies().brl;
  // money2's own SEK uses a comma for both separators, so a thousand kronor
  // would read "1,000,00". Swedish groups with a space.
  static final Currency sek = Currency.create('SEK', 2,
      symbol: 'kr',
      groupSeparator: ' ',
      decimalSeparator: ',',
      country: 'Sweden',
      unit: 'Krona',
      name: 'Swedish Krona');
  static final Currency nok = CommonCurrencies().nok;
  static final Currency dkk = CommonCurrencies().dkk;
  static final Currency pln = CommonCurrencies().pln;
  static final Currency czk = CommonCurrencies().czk;
  static final Currency huf = CommonCurrencies().huf;
  static final Currency ron = CommonCurrencies().ron;

  static final Currency btc = CommonCurrencies().btc;
  static final Currency sats = Currency.create('SATS', 0, symbol: '⚡', pattern: 'S0');

  static final List<Currency> supportedFiats = [
    usd,
    eur,
    gbp,
    chf,
    brl,
    sek,
    nok,
    dkk,
    pln,
    czk,
    huf,
    ron,
  ];

  static void registerCustomCurrencies() {
    if (Currencies().find('SATS') == null) {
      Currencies().register(sats);
    }
    if (Currencies().find('BTC') == null) {
      Currencies().register(btc);
    }
    for (final c in supportedFiats) {
      if (Currencies().find(c.isoCode) == null) {
        Currencies().register(c);
      }
    }
    // The directory ships a SEK of its own, which the check above keeps.
    if (!identical(Currencies().find('SEK'), sek)) {
      Currencies().register(sek);
    }
  }

  static String get apiSymbols {
    return supportedFiats
        .where((c) => c.isoCode != 'USD')
        .map((c) => c.isoCode)
        .join(',');
  }
}

class CurrencyState {
  final Map<String, Fixed> rates;

  CurrencyState(this.rates);

  /// Whether [code] has a real rate. [convert] reads a missing one as one
  /// to one with the dollar, so a figure labelled in [code] is only true
  /// when this holds.
  bool hasRate(String code) => code == 'USD' || rates.containsKey(code);

  Money convert(Money source, Currency targetCurrency) {
    AppCurrencies.registerCustomCurrencies();

    final sourceCode = source.currency.isoCode;
    final targetCode = targetCurrency.isoCode;

    final Fixed one = Fixed.fromInt(100);
    final Fixed sourceRateToUsd = sourceCode == 'USD' ? one : (rates[sourceCode] ?? one);
    final Fixed targetRateToUsd = targetCode == 'USD' ? one : (rates[targetCode] ?? one);

    final amountInUsd = source.amount / sourceRateToUsd;
    final convertedAmount = amountInUsd * targetRateToUsd;

    return Money.fromFixed(convertedAmount, isoCode: targetCode);
  }
}
