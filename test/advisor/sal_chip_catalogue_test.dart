// Sal's opening questions: public facts trigger them, local private signals
// only reorder them, and no chip ever says anything about the person.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidHeldPositionsProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidPerpMarketsProvider;
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/sal_chip_signals.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';

const _btc = AdvisorContext(
  surface: 'hl_market_detail',
  marketVenue: 'hyperliquid',
  marketId: 'BTC',
  marketDisplayName: 'BTC',
);
const _game = AdvisorContext(
  surface: 'polymarket_market_detail',
  marketVenue: 'polymarket',
  marketId: 'nfl-sf-den',
);
final _now = DateTime.utc(2026, 10, 6, 12);

class _Starred extends HlWatchlistNotifier {
  _Starred(this.keys);
  final List<String> keys;
  @override
  List<String> build() => keys;
}

HlMarket _perp(String coin, double mark, {double volume = 5e6}) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: mark,
      midPx: mark,
      prevDayPx: 100,
      dayNtlVlm: volume,
      funding: 0.00001,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = l10nForLanguage('en');

  List<String?> ids(AdvisorContext c,
          [SalChipSignals s = const SalChipSignals()]) =>
      [
        for (final chip
            in SalChipCatalogue.select(c, en, signals: s, now: _now))
          chip.template
      ];

  group('Hyperliquid', () {
    test('a quiet market: drivers, funding, liquidation, protection', () {
      expect(
          ids(_btc,
              const SalChipSignals(dayChangePct: 0.01, funding: 0.0000125)),
          [
            'hl.what_drives',
            'hl.funding_explain',
            'hl.liquidation_explain',
            'hl.protect_position',
          ]);
    });

    test('a big 24h move leads with why it is moving', () {
      expect(ids(_btc, const SalChipSignals(dayChangePct: -0.062)).first,
          'hl.moving_today');
      expect(ids(_btc, const SalChipSignals(dayChangePct: 0.029)),
          isNot(contains('hl.moving_today')));
    });

    test('negative funding asks why; extreme funding raises the explainer', () {
      expect(ids(_btc, const SalChipSignals(funding: -0.00002)),
          contains('hl.funding_flip'));
      expect(ids(_btc, const SalChipSignals(funding: 0.00002)),
          isNot(contains('hl.funding_flip')));
      expect(ids(_btc, const SalChipSignals(funding: 0.0002)).first,
          'hl.funding_explain');
    });

    test('a held position raises protection and liquidation to the top', () {
      final held = ids(_btc, const SalChipSignals(holdsPosition: true));
      expect(held.take(2), ['hl.protect_position', 'hl.liquidation_explain']);
    });

    test('a starred market raises drivers above the funding explainer', () {
      final starred =
          ids(_btc, const SalChipSignals(funding: 0.0002, onWatchlist: true));
      expect(starred.first, 'hl.what_drives');
    });

    test('an order slip leads with the order type', () {
      const slip = AdvisorContext(
          surface: 'hl_order_slip',
          marketVenue: 'hyperliquid',
          marketId: 'xyz:XYZ100',
          orderType: 'twap');
      final chips = SalChipCatalogue.select(slip, en, now: _now);
      expect(chips.first.template, 'edu.limit_order');
      expect(chips.first.text, 'How does a TWAP order work for XYZ100?');
      expect(SalChipCatalogue.introduction(slip, en),
          'Learn how TWAP orders work.');
    });

    test('spot has no perp-only questions', () {
      const spot = AdvisorContext(
          surface: 'hl_market_detail',
          marketVenue: 'hyperliquid',
          marketId: '@142',
          marketDisplayName: 'HYPE');
      final got =
          ids(spot, const SalChipSignals(holdsPosition: true, funding: -1));
      expect(got, isNot(contains('hl.funding_flip')));
      expect(got, isNot(contains('hl.protect_position')));
      expect(got, isNot(contains('edu.leverage')));
    });

    test('a screen without a market falls back to mechanics', () {
      expect(ids(const AdvisorContext(surface: 'hyperliquid_position_detail')),
          ['edu.leverage', 'edu.limit_order', 'edu.funding']);
    });
  });

  group('Polymarket', () {
    test('a live game leads, then a close within hours, then the odds', () {
      expect(
          ids(
              _game,
              SalChipSignals(
                liveGame: true,
                closesAt: _now.add(const Duration(hours: 3)),
                oddsChange1d: 0.12,
              )),
          [
            'pm.live_game',
            'pm.closing_soon',
            'pm.odds_moving',
            'pm.resolution_rules'
          ]);
    });

    test('a close a few days out or already past is not closing soon', () {
      expect(
          ids(_game,
              SalChipSignals(closesAt: _now.add(const Duration(days: 3)))),
          isNot(contains('pm.closing_soon')));
      expect(
          ids(
              _game,
              SalChipSignals(
                  closesAt: _now.subtract(const Duration(hours: 1)))),
          isNot(contains('pm.closing_soon')));
    });

    test('a held position raises what could move the odds', () {
      expect(ids(_game, const SalChipSignals(holdsPosition: true)).first,
          'pm.what_moves_it');
      expect(ids(_game).first, 'pm.resolution_rules');
    });
  });

  group('search', () {
    const search = AdvisorContext(surface: 'search');
    test('a moving starred market, then the biggest mover, then help', () {
      final chips = SalChipCatalogue.select(search, en,
          signals: const SalChipSignals(
            movers: [
              SalMarketRef(wireCoin: 'SOL', label: 'SOL', dayChangePct: 0.11),
              SalMarketRef(wireCoin: 'ETH', label: 'ETH', dayChangePct: -0.07),
            ],
            watchlist: [
              SalMarketRef(
                  wireCoin: 'xyz:TSLA', label: 'TSLA', dayChangePct: 0.001),
              SalMarketRef(wireCoin: 'ETH', label: 'ETH', dayChangePct: -0.07),
            ],
          ),
          now: _now);
      expect([
        for (final c in chips) c.template
      ], [
        'search.watchlist_news',
        'search.top_movers',
        'wallet.receive',
        'wallet.send'
      ]);
      expect(chips[0].text, "What's the latest news on ETH?");
      expect(chips[1].text, 'Why is SOL moving today?');
      // Each market chip carries only that public market.
      expect(chips[0].context!.toRequestMarket,
          {'venue': 'hyperliquid', 'id': 'ETH'});
      expect(chips[1].context!.toRequestMarket,
          {'venue': 'hyperliquid', 'id': 'SOL'});
      expect(chips[2].context, isNull);
    });

    test('nothing loaded: the general questions', () {
      expect(ids(search),
          ['wallet.receive', 'wallet.send', null, 'edu.prediction_basics']);
    });
  });

  test('every template is on the shared allowlist; at most four chips', () {
    final contexts = [
      _btc,
      _game,
      const AdvisorContext(surface: 'search'),
      const AdvisorContext(surface: 'chat'),
      const AdvisorContext(surface: 'backup_reveal'),
      const AdvisorContext(surface: 'send_review'),
      const AdvisorContext(
          surface: 'bet_slip',
          marketVenue: 'polymarket',
          marketId: 'nfl-sf-den',
          orderType: 'limit'),
    ];
    for (final c in contexts) {
      for (final s in _signalMatrix()) {
        final chips = SalChipCatalogue.select(c, en, signals: s, now: _now);
        expect(chips.length, lessThanOrEqualTo(kSalMaxChips));
        for (final chip in chips) {
          if (chip.template != null) {
            expect(kSalChipTemplates, contains(chip.template), reason: '$chip');
          }
        }
      }
    }
    expect(kSalChipTemplates, hasLength(21));
  });

  test(
      'chip text is side-neutral and never carries private state, in every '
      'language', () {
    final sideWords = RegExp(
        r'\b(long|short|your|size|p&l|pnl|profit|loss|liquidat(es|ed) at)\b',
        caseSensitive: false);
    for (final code in languageNativeNames.keys) {
      final l10n = l10nForLanguage(code);
      for (final c in [_btc, _game]) {
        for (final s in _signalMatrix()) {
          final texts = [
            SalChipCatalogue.introduction(c, l10n),
            for (final chip
                in SalChipCatalogue.select(c, l10n, signals: s, now: _now))
              chip.text,
          ];
          for (final text in texts) {
            // The public label is BTC: any digit would come from elsewhere.
            expect(RegExp(r'[0-9%$]').hasMatch(text), isFalse,
                reason: '$code: $text');
            if (code == 'en') {
              expect(sideWords.hasMatch(text), isFalse, reason: text);
            }
          }
        }
      }
    }
  });

  group('device signals', () {
    test('a held or starred market is read from local state, by public id', () {
      final container = ProviderContainer(overrides: [
        hyperliquidHeldPositionsProvider.overrideWith((_) => const [
              HlPerpPosition(
                coin: 'BTC',
                szi: -0.4231,
                entryPx: 64000,
                positionValue: 27000,
                unrealizedPnl: -1234.56,
                returnOnEquity: -0.2,
                liquidationPx: 71000,
                marginUsed: 1600,
                leverageType: 'cross',
                leverageValue: 17,
                maxLeverage: 40,
              ),
            ]),
        hlWatchlistProvider.overrideWith(() => _Starred(['perp:BTC'])),
      ]);
      addTearDown(container.dispose);
      final btc = withLocalSalSignals(container, _btc, const SalChipSignals());
      expect(btc.holdsPosition, isTrue);
      expect(btc.onWatchlist, isTrue);
      const eth = AdvisorContext(
          surface: 'hl_market_detail',
          marketVenue: 'hyperliquid',
          marketId: 'ETH');
      final other = withLocalSalSignals(container, eth, const SalChipSignals());
      expect(other.holdsPosition, isFalse);
      expect(other.onWatchlist, isFalse);
      // The short, its size, leverage and loss never reach the text.
      for (final chip
          in SalChipCatalogue.select(_btc, en, signals: btc, now: _now)) {
        expect(chip.text,
            isNot(matches(RegExp(r'[0-9]|short', caseSensitive: false))));
      }
    });

    test('search reads the market list only when it is already loaded',
        () async {
      final container = ProviderContainer(overrides: [
        hyperliquidPerpMarketsProvider.overrideWith((_) async => [
              _perp('SOL', 112),
              _perp('DOGE', 130, volume: 10),
              _perp('BTC', 100.5),
            ]),
        hlWatchlistProvider
            .overrideWith(() => _Starred(['perp:BTC', 'spot:@142'])),
      ]);
      addTearDown(container.dispose);
      expect(searchSalSignals(container).movers, isEmpty,
          reason: 'never starts a fetch of its own');
      final sub = container.listen(hyperliquidPerpMarketsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(hyperliquidPerpMarketsProvider.future);
      final signals = searchSalSignals(container);
      // DOGE moved more but trades too thinly; BTC moved too little.
      expect([for (final m in signals.movers) m.label], ['SOL']);
      expect([for (final m in signals.watchlist) m.label], ['BTC']);
    });
  });

  group('request', () {
    test('a chip sends its source, template and locale and nothing private',
        () async {
      final chip = SalChipCatalogue.select(_btc, en,
              signals:
                  const SalChipSignals(holdsPosition: true, onWatchlist: true),
              now: _now)
          .first;
      final body = await AdvisorRequest(
        query: chip.text,
        context: _btc,
        locale: 'pt',
        prompt: AdvisorPrompt.chip(chip.template),
      ).toJson();
      expect(body, {
        'schemaVersion': '3',
        'query': 'How can I protect a position on BTC?',
        'market': {'venue': 'hyperliquid', 'id': 'BTC'},
        'locale': 'pt',
        'prompt': {'source': 'chip', 'template': 'hl.protect_position'},
      });
      final wire = jsonEncode(body);
      for (final word in ['holds', 'watch', 'size', 'side', 'balance', 'pnl']) {
        expect(wire, isNot(contains(word)));
      }
    });

    test('typed and follow-up questions carry no template', () async {
      for (final (prompt, source) in [
        (const AdvisorPrompt.typed(), 'typed'),
        (AdvisorPrompt.fromInput('followup'), 'typed'),
        (AdvisorPrompt.fromInput('typed', template: 'hl.what_drives'), 'typed'),
      ]) {
        final body =
            await AdvisorRequest(query: 'Explain funding', prompt: prompt)
                .toJson();
        expect(body['prompt'], {'source': source});
      }
    });

    test('an unknown template or locale never leaves the device', () async {
      final body = await const AdvisorRequest(
        query: 'Explain funding',
        locale: 'zz',
        prompt: AdvisorPrompt.chip('my.private.template'),
      ).toJson();
      expect(body.containsKey('locale'), isFalse);
      expect(body['prompt'], {'source': 'chip'});
      expect(AdvisorRequest.requestLocale('DE'), 'de');
      expect(AdvisorRequest.requestLocale('pt-BR'), isNull);
    });
  });
}

List<SalChipSignals> _signalMatrix() => [
      for (final holds in [false, true])
        for (final watched in [false, true])
          for (final live in [false, true])
            SalChipSignals(
              dayChangePct: live ? 0.08 : 0.0,
              funding: live ? -0.0003 : 0.0000125,
              oddsChange1d: live ? 0.2 : 0.0,
              closesAt: live ? DateTime.utc(2026, 10, 6, 14) : null,
              liveGame: live,
              holdsPosition: holds,
              onWatchlist: watched,
            ),
    ];
