import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/services/polymarket/livestream_source.dart';

PolymarketEvent _event({
  String? stream,
  bool live = false,
  List<String> tags = const [],
  bool ended = false,
}) =>
    PolymarketEvent(
      id: '1',
      slug: 'e',
      title: 'E',
      volume: 0,
      liquidity: 0,
      category: 'other',
      conditionId: '',
      outcomes: const [],
      streamUrl: PolymarketEvent.streamUrlFrom(stream),
      isLive: live,
      tags: tags,
      ended: ended,
    );

void main() {
  group('LivestreamSource.parse', () {
    test('Twitch channel, lower-cased; Twitch pages are not channels', () {
      final s = LivestreamSource.parse('https://www.twitch.tv/ESLCSb')!;
      expect(s.host, LivestreamHost.twitch);
      expect(s.id, 'eslcsb');
      expect(LivestreamSource.parse('https://www.twitch.tv/directory'), isNull);
      expect(
          LivestreamSource.parse('https://player.twitch.tv/?channel=foxcs')!.id,
          'foxcs');
    });

    test('Kick channel from kick.com and player.kick.com', () {
      expect(LivestreamSource.parse('https://kick.com/xqc')!.host,
          LivestreamHost.kick);
      final p = LivestreamSource.parse('https://player.kick.com/Some_Chan')!;
      expect(p.host, LivestreamHost.kick);
      expect(p.id, 'some_chan');
    });

    test('YouTube video ids from watch, youtu.be, live and embed links', () {
      for (final url in [
        'https://www.youtube.com/watch?v=Pz92eEbzndM',
        'https://youtu.be/Pz92eEbzndM',
        'https://www.youtube.com/live/Pz92eEbzndM?si=x',
        'https://www.youtube.com/embed/Pz92eEbzndM',
      ]) {
        final s = LivestreamSource.parse(url)!;
        expect(s.host, LivestreamHost.youtube, reason: url);
        expect(s.id, 'Pz92eEbzndM', reason: url);
      }
    });

    test('a YouTube channel id embeds its live stream; a handle does not', () {
      final s = LivestreamSource.parse(
          'https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv/live')!;
      expect(s.youtubeChannelLive, isTrue);
      expect(LivestreamSource.parse('https://www.youtube.com/@somebody'),
          isNull);
    });

    test('score sites and news are not streams', () {
      expect(
          LivestreamSource.parse('https://www.atptour.com/en/scores/current'),
          isNull);
      expect(LivestreamSource.parse('https://www.espncricinfo.com/'), isNull);
      expect(LivestreamSource.parse(null), isNull);
    });
  });

  group('embed', () {
    test('YouTube embeds the player, never the watch page, from kute.app', () {
      final html = LivestreamSource.parse(
              'https://www.youtube.com/watch?v=Pz92eEbzndM')!
          .embedHtml(boxWidth: 350);
      expect(html, contains('https://www.youtube.com/embed/Pz92eEbzndM'));
      expect(html, isNot(contains('watch?v=')));
      expect(html, contains('playsinline=1'));
    });

    test('Twitch passes parent=kute.app and lays out at 400 CSS px', () {
      final twitch = LivestreamSource.parse('https://www.twitch.tv/valorant')!;
      final narrow = twitch.embedHtml(boxWidth: 350);
      expect(narrow, contains('parent=kute.app'));
      expect(narrow, contains('content="width=400"'));
      expect(twitch.embedHtml(boxWidth: 600),
          contains('width=device-width'));
    });

    test('player boxes meet each host minimum', () {
      final twitch = LivestreamSource.parse('https://www.twitch.tv/valorant')!;
      // 4:3 at any width -> a 400x300 CSS page once scaled to 400 wide.
      expect(twitch.playerHeightFor(350) / 350, closeTo(0.75, 1e-9));
      final yt =
          LivestreamSource.parse('https://youtu.be/Pz92eEbzndM')!;
      expect(yt.playerHeightFor(300), kYouTubeMinPlayerSide);
      expect(yt.playerHeightFor(480), 270);
    });
  });

  group('PolymarketEvent.hasLivestream', () {
    test('a live event with a Kick stream shows it', () {
      expect(_event(stream: 'https://kick.com/xqc', live: true).hasLivestream,
          isTrue);
    });

    test('a Mentions market with a YouTube video shows it without live', () {
      final e = _event(
          stream: 'https://www.youtube.com/watch?v=VMWEHk4qH6I',
          tags: const ['trump', 'mention-markets']);
      expect(e.isMentionMarket, isTrue);
      expect(e.hasLivestream, isTrue);
      expect(
          _event(
                  stream: 'https://www.youtube.com/watch?v=VMWEHk4qH6I',
                  tags: const ['mention-markets'],
                  ended: true)
              .hasLivestream,
          isFalse);
    });

    test('a non-live non-Mentions event does not', () {
      expect(_event(stream: 'https://www.twitch.tv/valorant').hasLivestream,
          isFalse);
    });
  });

  group('cricket live join', () {
    test('the WS metadataGameId joins Gamma eventMetadata.gameId', () {
      final event = PolymarketModel().parseEventsRaw([
        {
          'id': '9',
          'slug': 'crint-afg-lka-2026-03-13',
          'title': 'Afghanistan vs Sri Lanka',
          'eventMetadata': {'gameId': 'id2705074469517978', 'league': 'T20'},
          'markets': const [],
        }
      ]).single;
      expect(event.gameId, isNull);
      expect(event.metadataGameId, 'id2705074469517978');

      final update = SportsMatchUpdate.fromJson({
        'metadataGameId': 'id2705074469517978',
        'score': '145/3',
        'period': '2nd Inn',
        'live': true,
        'ended': false,
        'status': 'InProgress',
      });
      final map = {'meta:${update.metadataGameId}': update};
      expect(
          sportsUpdateFor(map,
              slug: event.slug,
              gameId: event.gameId,
              metadataGameId: event.metadataGameId),
          same(update));
    });

    test('NFL possession and status ride on the update', () {
      final u = SportsMatchUpdate.fromJson({
        'gameId': 19502,
        'leagueAbbreviation': 'nfl',
        'homeTeam': 'WAS',
        'awayTeam': 'IND',
        'status': 'InProgress',
        'score': '7-3',
        'period': 'Q2',
        'turn': 'IND',
        'live': true,
        'ended': false,
      });
      expect(u.turn, 'IND');
      expect(u.leagueAbbreviation, 'nfl');
      expect(u.status, 'InProgress');
    });
  });
}
