// The order of polymarket.com's own lists, which the Predictions categories
// follow at every level (founder, 9 November 2026: "please rank categories
// properly as they are in the website").
//
// Read live, from what the site's own pages read (no key, not a documented
// API; the app keeps working on the last copy, then on these constants):
//
//   * The sports' league lists and which sports have markets: the `sidebar`
//     of `{kPolySiteGateway}/internal/view/sports/<any league>`.
//   * Politics, Geopolitics, Tech, Culture and Economy's rows: the `sidebar`
//     of `{kPolySiteGateway}/internal/view/category/<slug>`.
//   * Trending's themes (the "All markets" chip row of the home page: 2028
//     Election, Midterms, Anthropic IPO, Iran …, the site's second kind of
//     category beside its topic nav; founder, 9 November 2026: "there are 2
//     categories on Polymarket, find a way to integrate both"): the
//     `categories` section of `{kPolySiteGateway}/internal/view/home`, the
//     view Trending's list already reads. The site composes it every 30 s
//     (`meta.maxAgeSeconds`); the set is editorial (a tag added or dropped
//     every few days) and its order moves within the day.
//
// Within a topic's side list the site draws dividers between groups of
// rows; where they fall is mirrored beside the lists
// (polymarket_browse_provider.dart, [kPolySubGroupTails]).
//
// Fixed in the site's own code, mirrored as constants beside the lists they
// order (polymarket_browse_provider.dart; read 9 November 2026): the top
// row, the pinned leagues, the sports' order, and Crypto, Finance, Weather
// and Breaking's rows. The snapshots here are the live lists as they read
// on 9 November 2026: the fallback before the first read.

/// The host polymarket.com's own pages read their views from.
const String kPolySiteGateway = 'https://api.defi.polymarket.com';

/// The league whose view carries the sidebar at the smallest read (the
/// sidebar is the same on every league's; Chess has the fewest events).
const String kPolySiteSidebarLeague = 'chess';

/// The site's league scopes whose Gamma `/sports` code differs. Every other
/// scope is the code itself.
const Map<String, String> kPolySiteScopeCodes = {
  'laliga': 'lal',
  'bundesliga': 'bun',
  'fifa-friendlies': 'fif',
  'ligue-1': 'fl1',
  'fa-cup': 'efa',
  'csl': 'chi',
  'pickleball': 'mlp',
  'dota-2': 'dota2',
  'league-of-legends': 'lol',
  'call-of-duty': 'codmw',
  'rainbow-six-siege': 'r6siege',
  'valorant': 'val',
  'starcraft-2': 'sc2',
  'mobile-legends-bang-bang': 'mlbb',
  'honor-of-kings': 'hok',
  'overwatch': 'ow',
};

/// The sports side list as the site reads it: each sport's leagues in the
/// site's order, the leagues it lists on their own (esports' games, College
/// Basketball), and how many markets each sport has.
class PolySiteSports {
  final Map<String, List<String>> leagues;
  final List<String> flat;
  final Map<String, int> counts;

  const PolySiteSports({
    required this.leagues,
    required this.flat,
    required this.counts,
  });

  /// The side list of a site view's JSON (`sidebar`), or null if it has none.
  static PolySiteSports? fromView(Map<String, dynamic> view) {
    final sidebar = view['sidebar'];
    final sections = sidebar is Map ? sidebar['sections'] : null;
    if (sections is! List) return null;
    final leagues = <String, List<String>>{};
    final flat = <String>[];
    final counts = <String, int>{};
    for (final section in sections.whereType<Map>()) {
      final items = section['items'];
      if (items is! List) continue;
      for (final item in items.whereType<Map>()) {
        final scope = item['scope'];
        if (scope is! String || scope.isEmpty) continue;
        counts[scope] = (item['count'] as num?)?.toInt() ?? 0;
        final children = item['children'];
        if (children is List && children.isNotEmpty) {
          leagues[scope] = [
            for (final c in children.whereType<Map>())
              if (c['scope'] is String) c['scope'] as String,
          ];
        } else {
          flat.add(scope);
        }
      }
    }
    return leagues.isEmpty
        ? null
        : PolySiteSports(leagues: leagues, flat: flat, counts: counts);
  }

  /// As the disk cache keeps it, and back.
  Map<String, dynamic> toRow() =>
      {'leagues': leagues, 'flat': flat, 'counts': counts};

  static PolySiteSports? fromRow(Map<String, dynamic> row) {
    try {
      return PolySiteSports(
        leagues: {
          for (final e in (row['leagues'] as Map).entries)
            '${e.key}': [for (final s in e.value as List) '$s'],
        },
        flat: [for (final s in row['flat'] as List) '$s'],
        counts: {
          for (final e in (row['counts'] as Map).entries)
            '${e.key}': (e.value as num).toInt(),
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// The Gamma `/sports` code of a scope of this list.
  static String codeOf(String scope) => kPolySiteScopeCodes[scope] ?? scope;

  /// Whether the site lists the league of Gamma code [code] now.
  bool listsLeague(String code) =>
      leagues.values.any((l) => l.any((s) => codeOf(s) == code)) ||
      flat.any((s) => codeOf(s) == code);

  /// Whether [sport] has markets on the site now (one with none falls off
  /// its list).
  bool hasMarkets(String sport) => (counts[sport] ?? 0) > 0;
}

/// The side list on 9 November 2026.
const PolySiteSports kPolySiteSportsSnapshot = PolySiteSports(
  leagues: {
    'football': [
      'nfl',
      'cfb',
      'cfl',
    ],
    'mma': [
      'ufc',
      'zuffa',
      'powerslap',
    ],
    'soccer': [
      'epl',
      'laliga',
      'bundesliga',
      'sea',
      'unl',
      'es2',
      'spl',
      'fifa-friendlies',
      'ucl',
      'el1',
      'ned2',
      'lva1',
      'ligue-1',
      'clf',
      'cdr',
      'tur',
      'ukr1',
      'ere',
      'scop',
      'por',
      'per1',
      'el2',
      'ecu1',
      'nor',
      'swe',
      'enl',
      'fa-cup',
      'cde',
      'nls',
      'bl2',
      'nirl1',
      'itsb',
      'fr2',
      'uwcl',
      'j2100',
      'ja2',
      'swe2',
      'bra',
      'uru1',
      'serc',
      'pol',
      'mex',
      'bra2',
      'elc',
      'csl',
      'ptc',
      'bul',
      'rou1',
      'kor',
      'argpn',
      'par1',
      'nln',
      'mls',
      'slo',
      'pt2',
      'cze1',
      'col2',
      'bol1',
      'col1',
      'rus',
      'chi2',
      'den',
      'nor2',
      'svk1',
      'afcq',
      'srb',
      'gtm',
      'conl',
      'irl1',
      'uzb1',
      'sud',
      'fpd',
      'isp',
      'nwsl',
      'wsl',
      'aus',
      'uwec',
      'chi1',
      'argcopa',
      'idn2',
      'jap',
      'jap',
      'wsl2',
      'tur2',
      'gre1',
      'uae1',
      'bel1',
      'brco',
      'fin1',
      'aze1',
      'idn1',
      'arg',
      'hun',
      'hr1',
      'aut',
      'uslc',
      'sui',
      'est1',
      'ltu1',
      'tha1',
      'bl3',
      'blr1',
      'mar1',
      'canpl',
      'bel2',
      'isr',
      'ja3',
      'kor2',
      'mex2',
      'es3',
      'qat1',
      'usl1',
      'ven1',
    ],
    'basketball': [
      'nba',
      'bkkbl',
      'cwbb',
      'bkbsl',
      'bkaba',
      'bkisrsl',
      'bkarg',
      'bkbbl',
      'bkseriea',
      'bknbb',
      'bkvtb',
      'bkligend',
      'bkkls',
      'bkeurocup',
      'bkjpn',
      'bkcl',
      'bknbl',
      'bkfr1',
      'bklkl',
      'bkplk',
    ],
    'tennis': [
      'atp',
      'itf',
      'wta',
      'atp-doubles',
      'wta-doubles',
    ],
    'cricket': [
      'crint',
      'cricwbbl',
      'cricnpl',
      'cricadt10',
      'cricmcat20',
      'csa',
      'criccsat20w',
      'cricshield',
      'cricss',
      'she',
    ],
    'hockey': [
      'nhl',
      'liiga',
      'khl',
      'ahl',
      'hockeychl',
      'cehl',
      'dehl',
      'snhl',
      'shl',
    ],
    'table-tennis': [
      'setkameua',
      'wtt',
      'setkamemd',
      'setkawoua',
      'setkamecz',
    ],
    'rugby': [
      'rutopft',
    ],
    'darts': [
      'modus',
    ],
    'golf': [
      'pga',
    ],
    'motorsports': [
      'motogp',
      'f1',
    ],
    'volleyball': [
      'vbplusliga',
      'vbvleague',
      'vb2bundesliga',
      'vbdivisao1',
      'vbsuperliga',
      'vbligueaw',
      'vbbelligaa',
      'vbefeler',
      'vbliguea',
      'vbligueb',
      'vbsuperlega',
    ],
    'chess': [
      'chess',
    ],
    'pickleball': [
      'pickleball',
    ],
    'aussie-rules': [
      'aflw',
    ],
    'baseball': [
      'kbo',
    ],
  },
  flat: [
    'cs2',
    'dota-2',
    'league-of-legends',
    'cbb',
    'call-of-duty',
    'rainbow-six-siege',
    'valorant',
    'moto3',
    'moto2',
    'euroleague',
    'starcraft-2',
    'mobile-legends-bang-bang',
    'honor-of-kings',
    'overwatch',
    'ppa-doubles',
  ],
  counts: {
    'football': 310,
    'mma': 30,
    'soccer': 848,
    'basketball': 566,
    'tennis': 516,
    'cricket': 76,
    'hockey': 300,
    'table-tennis': 265,
    'rugby': 1,
    'darts': 30,
    'golf': 1,
    'motorsports': 57,
    'volleyball': 12,
    'chess': 2,
    'pickleball': 5,
    'aussie-rules': 0,
    'baseball': 0,
  },
);

/// Each topic's row on 9 November 2026, by pill key, as `{id, slug, label}`
/// rows (polyTopicSubsFromRows); the site's All is the chip's own.
const Map<String, List<Map<String, String>>> kPolySiteTopicRowsSnapshot = {
  'politics': [
    {'id': '126', 'slug': 'trump', 'label': 'Trump'},
    {'id': '102289', 'slug': 'midterms', 'label': 'Midterms'},
    {'id': '106553', 'slug': 'competitive-races', 'label': 'Competitive Races'},
    {'id': '106552', 'slug': '2028-election', 'label': '2028 Election'},
    {'id': '101175', 'slug': 'post-election', 'label': 'Post Election'},
    {'id': '514', 'slug': 'congress', 'label': 'Congress'},
    {'id': '101542', 'slug': 'gov-shutdown', 'label': 'Gov Shutdown'},
    {'id': '104093', 'slug': 'senate-midterms', 'label': 'Senate Elections'},
    {'id': '103899', 'slug': 'house-elections', 'label': 'House Elections'},
    {
      'id': '104094',
      'slug': 'governor-midterms',
      'label': 'Governor Elections'
    },
    {'id': '100418', 'slug': 'derivatives', 'label': 'Derivatives'},
    {'id': '1597', 'slug': 'global-elections', 'label': 'Global Elections'},
    {'id': '104793', 'slug': 'israel-election', 'label': 'Israel Election'},
    {'id': '100282', 'slug': 'french-election', 'label': 'French Election'},
    {'id': '100185', 'slug': 'brazil', 'label': 'Brazil'},
    {'id': '303', 'slug': 'china', 'label': 'China'},
    {'id': '245', 'slug': 'canada', 'label': 'Canada'},
    {'id': '95', 'slug': 'russia', 'label': 'Russia'},
    {'id': '246', 'slug': 'venezuela', 'label': 'Venezuela'},
    {'id': '756', 'slug': 'epstein', 'label': 'Epstein'},
  ],
  'geopolitics': [
    {'id': '78', 'slug': 'iran', 'label': 'Iran'},
    {'id': '849', 'slug': 'lebanon', 'label': 'Lebanon'},
    {'id': '309', 'slug': 'oil', 'label': 'Oil'},
    {'id': '96', 'slug': 'ukraine', 'label': 'Ukraine'},
    {'id': '102486', 'slug': 'ukraine-map', 'label': 'Ukraine Map'},
    {'id': '102868', 'slug': 'cuba', 'label': 'Cuba'},
    {'id': '246', 'slug': 'venezuela', 'label': 'Venezuela'},
    {'id': '154', 'slug': 'middle-east', 'label': 'Middle East'},
    {'id': '61', 'slug': 'gaza', 'label': 'Gaza'},
    {'id': '180', 'slug': 'israel', 'label': 'Israel'},
    {'id': '114', 'slug': 'syria', 'label': 'Syria'},
    {'id': '738', 'slug': 'yemen', 'label': 'Yemen'},
    {'id': '101270', 'slug': 'turkey', 'label': 'Turkey'},
    {'id': '102850', 'slug': 'sudan', 'label': 'Sudan'},
    {'id': '303', 'slug': 'china', 'label': 'China'},
    {'id': '102083', 'slug': 'india-pakistan', 'label': 'India-Pakistan'},
  ],
  'tech': [
    {'id': '439', 'slug': 'ai', 'label': 'AI'},
    {'id': '282', 'slug': 'elon-musk', 'label': 'Elon Musk'},
    {'id': '970', 'slug': 'app-store', 'label': 'App Store'},
    {'id': '63', 'slug': 'spacex', 'label': 'SpaceX'},
    {'id': '1097', 'slug': 'apple', 'label': 'Apple'},
    {'id': '74', 'slug': 'science', 'label': 'Science'},
    {'id': '537', 'slug': 'openai', 'label': 'OpenAI'},
    {'id': '101473', 'slug': 'microstrategy', 'label': 'MicroStrategy'},
    {'id': '101999', 'slug': 'big-tech', 'label': 'Big Tech'},
    {'id': '530', 'slug': 'tiktok', 'label': 'TikTok'},
    {'id': '93', 'slug': 'prediction-markets', 'label': 'Prediction Markets'},
  ],
  'culture': [
    {'id': '1422', 'slug': 'art', 'label': 'Art'},
    {'id': '100', 'slug': 'music', 'label': 'Music'},
    {'id': '286', 'slug': 'celebrities', 'label': 'Celebrities'},
    {'id': '18', 'slug': 'awards', 'label': 'Awards'},
    {'id': '145', 'slug': 'mrbeast', 'label': 'MrBeast'},
    {'id': '53', 'slug': 'movies', 'label': 'Movies'},
    {'id': '51', 'slug': 'box-office', 'label': 'Box Office'},
    {'id': '595', 'slug': 'taylor-swift', 'label': 'Taylor Swift'},
    {'id': '102109', 'slug': 'gta-vi', 'label': 'GTA VI'},
    {'id': '972', 'slug': 'tweets-markets', 'label': 'Tweet Markets'},
    {'id': '146', 'slug': 'youtube', 'label': 'YouTube'},
    {'id': '100339', 'slug': 'reality-tv', 'label': 'Reality TV'},
    {'id': '71', 'slug': 'aliens', 'label': 'Aliens'},
    {'id': '1628', 'slug': 'courts', 'label': 'Courts'},
    {'id': '1369', 'slug': 'eurovision', 'label': 'Eurovision'},
  ],
  'economy': [
    {'id': '101761', 'slug': 'trade-war', 'label': 'Trade War'},
    {'id': '100196', 'slug': 'fed-rates', 'label': 'Fed Rates'},
    {'id': '702', 'slug': 'inflation', 'label': 'Inflation'},
    {'id': '102000', 'slug': 'macro-indicators', 'label': 'Macro Indicators'},
    {'id': '370', 'slug': 'gdp', 'label': 'GDP'},
    {'id': '103176', 'slug': 'global-rates', 'label': 'Global Rates'},
    {'id': '100207', 'slug': 'taxes', 'label': 'Taxes'},
    {'id': '102028', 'slug': 'treasuries', 'label': 'Treasuries'},
    {'id': '105094', 'slug': 'consumer', 'label': 'Consumer'},
    {'id': '103060', 'slug': 'housing', 'label': 'Housing'},
    {'id': '105109', 'slug': 'labor', 'label': 'Labor'},
  ],
};

/// Trending's themes on 9 November 2026 (the home page's chip row, in its
/// order), as `{id, slug, label}` rows (polyTopicSubsFromRows); the row's
/// All is the chip's own. The fallback before the first read.
const List<Map<String, String>> kPolySiteTrendingThemesSnapshot = [
  {'id': '106552', 'slug': '2028-election', 'label': '2028 Election'},
  {'id': '102289', 'slug': 'midterms', 'label': 'Midterms'},
  {'id': '105183', 'slug': 'anthropic-ipo', 'label': 'Anthropic IPO'},
  {'id': '106558', 'slug': 'cabinet-shakeup', 'label': 'Cabinet Shakeup'},
  {'id': '78', 'slug': 'iran', 'label': 'Iran'},
  {'id': '106557', 'slug': 'ai-bubble', 'label': 'AI Bubble'},
  {'id': '101175', 'slug': 'post-election', 'label': 'Post Election'},
  {'id': '106553', 'slug': 'competitive-races', 'label': 'Competitive Races'},
  {'id': '159', 'slug': 'fed', 'label': 'Fed'},
  {'id': '126', 'slug': 'trump', 'label': 'Trump'},
  {
    'id': '104799',
    'slug': 'new-zealand-election',
    'label': 'New Zealand Election'
  },
  {
    'id': '105302',
    'slug': 'south-africa-municipal-elections',
    'label': 'South Africa Municipal Elections'
  },
  {'id': '106304', 'slug': 'spain-elections', 'label': 'Spain Elections'},
  {'id': '106092', 'slug': 'astra', 'label': 'Astra'},
  {'id': '104793', 'slug': 'israel-election', 'label': 'Israel Election'},
  {'id': '439', 'slug': 'ai', 'label': 'AI'},
  {'id': '106330', 'slug': 'lol-worlds-2026', 'label': 'LoL Worlds 2026'},
  {'id': '100418', 'slug': 'derivatives', 'label': 'Derivatives'},
];

/// Trending's themes out of the home view (`/internal/view/home`): the rows
/// of its `categories` section, as `{id, slug, label, activeEventsCount}`,
/// in the site's order. Empty when the view has no such section.
List<Map<String, dynamic>> polySiteTrendingThemes(Map<String, dynamic> json) {
  final sections = json['sections'];
  if (sections is! List) return const [];
  for (final section in sections.whereType<Map>()) {
    if (section['type'] != 'categories') continue;
    final items = section['items'];
    if (items is! List) continue;
    return [
      for (final item in items.whereType<Map>())
        if (item['id'] != null && item['slug'] is String)
          {
            'id': item['id'],
            'slug': item['slug'],
            'label': item['label'] ?? item['slug'],
            'activeEventsCount': item['activeEventsCount'],
          },
    ];
  }
  return const [];
}

/// The event slugs of a Trending page in the site's order, and the cursor of
/// the next: the `feed` section of `/internal/view/home`, or a page of
/// `/internal/view/feed` (`items`).
({List<String> slugs, String? cursor}) polySiteTrendingPage(
    Map<String, dynamic> json) {
  Map<String, dynamic> page = json;
  final sections = json['sections'];
  if (sections is List) {
    page = sections.whereType<Map<String, dynamic>>().firstWhere(
          (s) => s['type'] == 'feed',
          orElse: () => const {},
        );
  }
  final rows = page['events'] ?? page['items'];
  final cursor = page['nextCursor'];
  return (
    slugs: [
      if (rows is List)
        for (final e in rows.whereType<Map>())
          if (e['slug'] is String) e['slug'] as String,
    ],
    cursor: cursor is String && cursor.isNotEmpty ? cursor : null,
  );
}

/// A topic's rows out of its site view (`sidebar`), as
/// `{id, slug, label, activeEventsCount}`, in the site's order. The site's
/// All has no scope and is the chip's own.
List<Map<String, dynamic>> polySiteTopicRows(Map<String, dynamic> view) {
  final sidebar = view['sidebar'];
  final sections = sidebar is Map ? sidebar['sections'] : null;
  if (sections is! List) return const [];
  return [
    for (final section in sections.whereType<Map>())
      if (section['items'] is List)
        for (final item in (section['items'] as List).whereType<Map>())
          if (item['id'] != null && item['scope'] is String)
            {
              'id': item['id'],
              'slug': item['scope'],
              'label': item['label'],
              'activeEventsCount': item['count'],
            },
  ];
}
