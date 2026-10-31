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
