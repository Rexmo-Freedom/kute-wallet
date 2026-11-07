// The Who step's own rules (send_recipient_step.dart, fw50): which inputs
// only bitcoin pays (the input decides the rail), which words name an own
// account (the search's escape hatch, "Move to your Dollars"), and the
// crypto hint's line ("Send to Bitcoin, USDC, USDT, ETH and 18 more"),
// counted from the coins the send's sheet lists.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show OrchestraReceiveOption;
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/send/send_recipient_step.dart';

final _l10n = AppLocalizationsEn();

CoinAssetGroup _coin(String symbol) => CoinAssetGroup(
      key: symbol,
      displayName: symbol,
      displaySymbol: symbol,
      options: [
        OrchestraReceiveOption(
          assetCode: symbol,
          displayName: symbol,
          displaySymbol: symbol,
          chain: 'ethereum',
          chainDisplayName: 'Ethereum',
          decimals: 6,
        ),
      ],
    );

void main() {
  group('sendIsBitcoinRail', () {
    test('bitcoin, Spark and Lightning destinations are bitcoin\'s', () {
      for (final text in [
        'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.1',
        'lnbc2500u1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu',
        'lightning:lnbc2500u1pvjluezpp5qqqsyqcyq5rqwz',
        'lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhvgcxxcmyxymnserxfq5fns',
        'alice@getalby.com',
        'joana@paykute.com',
      ]) {
        expect(sendIsBitcoinRail(text), isTrue, reason: text);
      }
    });

    test('a coin address, a name, a number or nothing is not', () {
      for (final text in [
        '0x742d35cc6634c0532925a3b844bc454e4438f44e',
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        'maria',
        '+351 912 345 678',
        '',
        'two words',
      ]) {
        expect(sendIsBitcoinRail(text), isFalse, reason: text);
      }
    });
  });

  group('sendOwnAccountMatches', () {
    test('a word that starts an account\'s name finds it', () {
      expect(sendOwnAccountMatches(_l10n, 'dollars'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'my dollars'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'Dol'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'usd'), [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(_l10n, 'bitcoin'), [SendOwnAccount.bitcoin]);
      expect(sendOwnAccountMatches(_l10n, 'my btc'), [SendOwnAccount.bitcoin]);
      expect(sendOwnAccountMatches(_l10n, 'sats'), [SendOwnAccount.bitcoin]);
    });

    test('the localized names count too, accents folded', () {
      expect(sendOwnAccountMatches(l10nForLanguage('pt'), 'meus dolares'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('el'), 'δολάρια'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('bg'), 'долари'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('ja'), 'ドル'),
          [SendOwnAccount.dollars]);
      expect(sendOwnAccountMatches(l10nForLanguage('ja'), 'ビットコイン'),
          [SendOwnAccount.bitcoin]);
    });

    test('an address, a coin ticker, a name or two letters find nothing', () {
      for (final text in [
        '0x742d35cc6634c0532925a3b844bc454e4438f44e',
        'usdc',
        'maria',
        'do',
        '',
        'alice@getalby.com',
      ]) {
        expect(sendOwnAccountMatches(_l10n, text), isEmpty, reason: text);
      }
    });
  });

  group('sendCryptoHintLine', () {
    test('Bitcoin first, three coins and how many more', () {
      final groups = [
        for (final s in ['USDC', 'USDT', 'ETH', 'SOL', 'BNB']) _coin(s)
      ];
      expect(sendCryptoHintLine(_l10n, groups),
          'Send to Bitcoin, USDC, USDT, ETH and 2 more');
    });

    test('a short list names them all; bitcoin is never counted twice', () {
      expect(sendCryptoHintLine(_l10n, [_coin('BTC'), _coin('USDC')]),
          'Send to Bitcoin and USDC');
      expect(sendCryptoHintLine(_l10n, [_coin('USDC'), _coin('USDT')]),
          'Send to Bitcoin, USDC and USDT');
    });

    test('no coin: no line (the hint is not shown)', () {
      expect(sendCryptoHintLine(_l10n, const []), isEmpty);
      expect(sendCryptoHintLine(_l10n, [_coin('BTC')]), isEmpty);
    });
  });
}
