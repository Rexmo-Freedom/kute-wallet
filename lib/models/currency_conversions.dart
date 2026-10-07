import 'package:money2/money2.dart';

class AppCurrencies {
  static final Currency usd = CommonCurrencies().usd;
  static final Currency eur = CommonCurrencies().euro;
  static final Currency gbp = CommonCurrencies().gbp;
  static final Currency chf = CommonCurrencies().chf;
  static final Currency brl = CommonCurrencies().brl;
  static final Currency sek = CommonCurrencies().sek;
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
