// The shared allowlist of Sal chip template ids. The backend keeps the same
// list; request and analytics code read it from here.

/// The template ids a chip can carry to the backend. The backend keeps the
/// same allowlist; an id outside it never leaves the device.
const kSalChipTemplates = <String>{
  'hl.moving_today',
  'hl.funding_flip',
  'hl.funding_explain',
  'hl.protect_position',
  'hl.liquidation_explain',
  'hl.what_drives',
  'hl.compare_related',
  'pm.odds_moving',
  'pm.closing_soon',
  'pm.live_game',
  'pm.what_moves_it',
  'pm.resolution_rules',
  'pm.related_markets',
  'search.top_movers',
  'search.watchlist_news',
  'edu.limit_order',
  'edu.leverage',
  'edu.funding',
  'edu.prediction_basics',
  'wallet.receive',
  'wallet.send',
};
