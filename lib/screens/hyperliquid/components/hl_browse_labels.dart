import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';

/// Presentation labels only: analytics keys stay stable. The names are
/// the ones Hyperliquid's own market selector uses (Trending, Perps,
/// Spot, Crypto, Tradfi, Pre-launch).
extension HlBrowsePresentation on HlBrowseTab {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        // The Predictions watchlist's own label, star included.
        HlBrowseTab.watchlist => '★ ${l10n.polyPillWatchlist}',
        HlBrowseTab.trending => l10n.hlPillTrending,
        HlBrowseTab.perps => l10n.investingPerps,
        HlBrowseTab.spot => l10n.investingSpot,
        HlBrowseTab.crypto => l10n.investingCrypto,
        // The site's own word, written the same in every language.
        HlBrowseTab.tradfi => 'Tradfi',
        HlBrowseTab.prelaunch => l10n.investingPrelaunch,
      };
}

extension HlBrowseSubPresentation on HlBrowseSub {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
        HlBrowseSub.all => l10n.hlKindAll,
        // Sector names: terms of the trade, in the site's spelling.
        HlBrowseSub.ai => 'AI',
        HlBrowseSub.defi => 'Defi',
        HlBrowseSub.gaming => 'Gaming',
        HlBrowseSub.layer1 => 'Layer 1',
        HlBrowseSub.layer2 => 'Layer 2',
        HlBrowseSub.meme => 'Meme',
        HlBrowseSub.stocks => l10n.investingStocks,
        HlBrowseSub.indices => l10n.investingIndices,
        HlBrowseSub.commodities => l10n.investingCommodities,
        // Terms of the trade, written the same in every language.
        HlBrowseSub.fx => 'FX',
        HlBrowseSub.preipo => 'Pre-IPO',
        HlBrowseSub.other => l10n.betGroupOther,
      };
}
