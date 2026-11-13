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

A coloured mark is never recoloured. The few that melt into one theme's
surface sit on the other theme's logo plate there (`kPolyLightPlateOnDark`,
`kPolyDarkPlateOnLight` in `poly_sport_icon.dart`): in dark mode on the
light plate `ucl.svg` (navy), `cricket.dark.svg` (#bf0000), `darts.dark.svg`
(#62646a) and `esports/overwatch.svg` (its #4a4c4e ring); in light mode on
the dark plate `darts.svg` (#bfc3ca).

The side list's pinned leagues are PNGs from Gamma `/sports`, not SVGs. NFL,
UFC and the Champions League have a vector that draws the same mark, above.
NBA, MLB, College Football and the Nations League do not (the logoman, the
NCAA disc; the config's SVGs are a generic ball and helmet, the Nations League
has only a PNG), so those rows, like every other league, draw their Gamma
`image`.

## Esports (`esports/`)

One per game of the Esports screen, drawn as they are, through the same
resolver (`poly_sport_icon.dart`). Read on 9 November 2026 from the esports
entries of the league config in chunk `15qc9kr-52q-9.js` (`icon`,
`iconClassName`): either a file the site serves under
`polymarket.com/images/sports/leagues/`, as served, or a component of that
chunk (module number below), whose `currentColor` takes the entry's colour.
No game has a `dark:` colour on the site, so none has a dark file.

| File | Polymarket source | Colour |
| --- | --- | --- |
| cs2.svg | module 115893 | #C89B3B |
| dota-2.svg | images/sports/leagues/dota2.svg | its own fills |
| league-of-legends.svg | images/sports/leagues/league-of-legends.svg | its own fills |
| call-of-duty.svg | module 465666 | `currentColor` (`text-grey` on the site): the text colour |
| rainbow-six-siege.svg | module 771781 | #C89B3B |
| valorant.svg | images/sports/leagues/valorant.svg | its own fills |
| starcraft-2.svg | images/sports/leagues/starcraft.svg | its own fills |
| mobile-legends-bang-bang.svg | module 690610 | #F25D23 |
| honor-of-kings.svg | module 156188 | #C89B3B |
| overwatch.svg | images/sports/leagues/overwatch.svg | its own fills |
| rocket-league.svg | module 75107 | #C89B3B |

StarCraft: Brood War has no file here: the site's
`starcraft-brood-war.svg` is a 176 x 24 wordmark in #414141, unreadable at
20 pt and invisible on the dark plate. The row draws its card image from
polymarket.com/esports (`starcraftbroodwar-77405089c8.jpg`) instead; Gamma's
`league-icons/sc.png` for the game is the StarCraft II logo.

## Side-list glyphs (`rows/`)

Monochrome, `currentColor`, drawn in the text colour: the icons
polymarket.com's own side lists draw in `text-pk-content-primary` for the
Crypto, Finance and Weather rows, as served in the pages' HTML on 9
November 2026 (`class` attributes dropped), and four marks of the site's
set for topic rows.

| File | Polymarket row |
| --- | --- |
| 5m, 15m, 1h, 4h, daily, weekly, monthly | /crypto/5M … /crypto/monthly (Finance's Daily, Weekly and Monthly are the same icons) |
| calendar | /earnings (the calendar with a dot), for Crypto's Yearly: the site draws Daily's calendar for Yearly too |
| targets, pre-market, institutions, industry, protocol-metrics | /crypto/… |
| privates, acquisitions, ipo, fed-rates, prediction-markets, treasuries, kpis | /finance/… |
| temperature, precipitation, drought, global, tornadoes, hurricanes, earthquakes, volcanoes, pandemics | /weather/… |
| apple | chunk module 353467, the site's Apple mark (Tech › Apple) |
| tiktok | the site footer's TikTok mark (Tech › TikTok) |
| x | the site footer's X mark (Culture › Tweet Markets) |
| taxes | the site's 18 px coin-in-hand icon (Economy › Taxes) |

Economy's Fed Rates and Treasuries, Tech's Prediction Markets and Economy's
Macro Indicators (`kpis`) draw the Finance side list's glyph of the same
subject.

## Hosted images (no file here)

The resolver's other rows draw Polymarket's hosted images: a league's, a
game's or a coin's own; Finance's Stocks, Earnings, Indices, Commodities and
Forex as the Finance side list draws them; and for the Politics,
Geopolitics, Tech, Culture and Economy rows, which the site draws without an
icon, the image of one of that row's top markets on
`/internal/view/category/<slug>`, picked on 9 November 2026 for showing the
row's subject (`kPolyTopicRowImages`). A row the site adds later, or an
image that fails, draws its topic's glyph.
