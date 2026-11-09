# Polymarket topic glyphs

Monochrome SVGs for the Predictions topic tiles (the Investments category
sheet, `lib/screens/usd/investments_category_sheet.dart`), one per
`PolyPill` key, drawn at 20 px in `textPrimary` through a colour filter.

Source: polymarket.com's own icon components (its `polykit` `*Icon20`
set and its Nucleo-based `Icon*18` set), read from the site's Next.js
chunks on 31 October 2026 and written out as plain SVG (`fill`/`stroke`
`currentColor` replaced by black; the colour filter paints them). The
paths are Polymarket's; this folder only carries them so the app can draw
the topics the way polymarket.com does.

| File | Polymarket component | Note |
| --- | --- | --- |
| politics.svg | PoliticsIcon20 | the capitol |
| sports.svg | TrophyIcon20 | |
| crypto.svg | BitcoinIcon20 | |
| finance.svg | BankIcon20 | |
| geopolitics.svg | GlobeIcon20 | |
| breaking.svg | LightningIcon20 | |
| watchlist.svg | StarIcon20 | |
| economy.svg | IconChartLineOutline18 | |
| tech.svg | IconGridOutline18 | closest glyph: no Tech icon on the site |
| culture.svg | IconPopOutline18 | the pop-culture burst |
| elections.svg | IconBadgeCheckFill18 | closest glyph: no ballot on the site |
| mentions.svg | IconDotsFill18 | closest glyph: no quote on the site |
| weather.svg | IconSunFill18 | |
| esports.svg | Esports | the sports set's controller |
| new.svg | IconSparkle4Fill12 | |
| live.svg | IconRadioOutline18 | |
| trending.svg | IconArrowTrendUpOutline18 | the nav's Trending glyph |
| instant.svg | none | no Polymarket glyph for it: our stopwatch, in the set's 18 px outline style (breaking.svg already is the lightning) |
| art.svg | — | drawn here (a palette); the site has no Art icon |

## Sports (`sports/`)

Coloured, drawn as they are (no colour filter), one per row of the Sports
screen (`lib/screens/polymarket/components/poly_sport_icon.dart`). Read on 9
November 2026 from polymarket.com/sports: its server-rendered side list and
chunk `15qc9kr-52q-9.js`, whose sports set is one module of `f` components
(numbered below) and whose league config names each row's `icon` and
`iconClassName`. The side list colours each glyph with a Tailwind class over
`currentColor`; that colour is written into the file. `<key>.dark.svg` is the
class's `dark:` value, or the `pk-*` token's `[data-theme=dark]` value, and
exists only where it differs.

| File | Polymarket source | Colour (light / dark) |
| --- | --- | --- |
| soccer.svg | sports set 100796 | #16a34a |
| tennis.svg | sports set 704089 | #9ACD32 / #CCFF00 |
| cricket.svg | sports set 753330 | pk-red-400: #fe3d33 / #bf0000 |
| basketball.svg | sports set 825942 | #FA4E00 |
| football.svg | sports set 537655 | #00457B / #60a5fa |
| hockey.svg | sports set 667432 | #15803d / #16a34a |
| rugby.svg | sports set 998639 | #C45911 |
| table-tennis.svg | sports set 303877 | #E10600 / #FF1E00 |
| darts.svg | sports set 278222 | pk-gray-400: #bfc3ca / #62646a |
| volleyball.svg | module 115522 | #0AA1DD |
| golf.svg | sports set 649692 | #16a34a |
| mma.svg | sports set 184310 (Combat) | pk-red-500: #df0c10 |
| baseball.svg | sports set 784650 | #B90E3B / #ef4444 |
| handball.svg | sports set 180446 | #2563EB / #60A5FA |
| motorsports.svg | sports set 885795 | #E10600 / #FF1E00 |
| cycling.svg | sports set 695902 | #0284c7 / #38bdf8 |
| chess.svg | sports set 479758 | #B58863 / #D4A574 |
| live.svg | module 318003 (IconRadioOutline18), the config's Live icon | #EF4444. The side list's own Live row draws a pinging CSS dot, not an icon |
| futures.svg | module 679617 | none: `currentColor`, the text colour, as on the site |
| nfl.svg | sports set 353665, the site's helmet | #2e5cff, the blue of the PNG the side list draws (`league-icons/nfl-helmet-blue-a1188621.png`). The config's own NFL icon, 529691, is a football |
| ufc.svg | polymarket.com/images/sports/leagues/ufc.svg, as served | its own fills |
| ucl.svg | polymarket.com/images/sports/leagues/ucl.svg, as served | its own fills |

The side list's pinned leagues are PNGs from Gamma `/sports`, not SVGs. NFL,
UFC and the Champions League have a vector that draws the same mark, above.
NBA, MLB, College Football and the Nations League do not (the logoman, the
NCAA disc; the config's SVGs are a generic ball and helmet, the Nations League
has only a PNG), so those rows, like every other league, draw their Gamma
`image`.
