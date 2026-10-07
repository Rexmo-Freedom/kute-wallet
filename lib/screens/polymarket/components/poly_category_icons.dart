import 'package:flutter/material.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';

/// Single source of truth mapping a Polymarket category/tag slug (or
/// app-special surface key like `trending` / `live`) to a real icon.
///
/// Used by BOTH the category pill row and the market-card thumbnail
/// fallback so a topic always reads with the same glyph. Slugs are the
/// same ones handed to `polymarketEventsProvider` / appended from
/// `polymarketParentTagsProvider`, so dynamic Gamma tags resolve here
/// too. Anything unrecognised falls back to a neutral compass — never a
/// blank/grey placeholder.
///
/// `live` uses a Material bolt because it reads as "right now" better
/// than any Bootstrap option.
IconData polyCategoryGlyph(String? slug) {
  final s = (slug ?? '').toLowerCase().trim();
  switch (s) {
    // App-special surfaces.
    case 'trending':
      return BootstrapIcons.fire;
    case 'new':
      return BootstrapIcons.stars;
    case 'breaking':
      return BootstrapIcons.newspaper;
    case 'live':
      return Icons.bolt_rounded;
    case 'livestream':
      return BootstrapIcons.broadcast;
    case 'series':
      return BootstrapIcons.calendar_event;

    // Crypto family.
    case 'crypto':
    case 'bitcoin':
    case 'btc':
    case 'ethereum':
    case 'eth':
    case 'solana':
    case 'sol':
    case 'defi':
    case 'nft':
      return BootstrapIcons.currency_bitcoin;

    // Sports family.
    case 'sports':
    case 'nba':
    case 'nfl':
    case 'soccer':
    case 'football':
    case 'ufc':
    case 'mma':
    case 'tennis':
    case 'golf':
    case 'f1':
    case 'baseball':
    case 'hockey':
    case 'cricket':
      return BootstrapIcons.trophy_fill;

    // Esports / gaming.
    case 'esports':
    case 'gaming':
    case 'games':
    case 'cs2':
    case 'lol':
    case 'dota':
    case 'valorant':
      return BootstrapIcons.controller;

    // Politics family.
    case 'politics':
    case 'elections':
    case 'election':
    case 'trump':
    case 'congress':
    case 'supreme-court':
    case 'geopolitics':
      return BootstrapIcons.bank;

    // World / geo.
    case 'world':
    case 'ukraine':
    case 'russia':
    case 'china':
    case 'israel':
    case 'iran':
    case 'middle-east':
      return BootstrapIcons.globe_americas;

    // Business / economy.
    case 'business':
    case 'fed':
    case 'interest-rates':
    case 'economy':
    case 'finance':
    case 'stocks':
      return BootstrapIcons.cash_stack;

    // Tech / AI.
    case 'tech':
    case 'technology':
    case 'ai':
      return BootstrapIcons.cpu_fill;

    // Science / space.
    case 'science':
    case 'spacex':
    case 'nasa':
    case 'space':
    case 'climate':
    case 'weather':
      return BootstrapIcons.rocket_takeoff_fill;

    // Entertainment / media.
    case 'entertainment':
    case 'movies':
    case 'oscars':
    case 'streaming':
    case 'tv':
    case 'pop-culture':
    case 'culture':
      return BootstrapIcons.film;

    // Music.
    case 'music':
      return BootstrapIcons.music_note_beamed;

    // People.
    case 'people':
    case 'celebrities':
      return BootstrapIcons.people_fill;

    default:
      // Unknown / dynamic tag with no specific mapping — neutral
      // compass keeps the pill and card from ever rendering blank.
      return BootstrapIcons.compass;
  }
}

/// Subtle per-category accent used to tint an unselected pill / card
/// fallback glyph so the prediction types carry a light visual identity.
/// Kept low-saturation so the row never competes with the market cards.
Color polyCategoryTint(String? slug, Color fallback) {
  final s = (slug ?? '').toLowerCase().trim();
  switch (s) {
    case 'trending':
      return const Color(0xFFEF6C2B); // warm orange — "hot"
    case 'new':
      return const Color(0xFF22C55E); // fresh green — just listed
    case 'breaking':
      return const Color(0xFFD9485A); // red — news
    case 'live':
      return const Color(0xFFD9485A);
    case 'livestream':
      return const Color(0xFF8B5CF6); // violet — broadcast
    case 'series':
      return const Color(0xFF3B82F6);
    case 'crypto':
    case 'bitcoin':
    case 'btc':
    case 'ethereum':
    case 'eth':
    case 'solana':
    case 'sol':
    case 'defi':
    case 'nft':
      return const Color(0xFFF7931A); // bitcoin orange
    case 'sports':
    case 'nba':
    case 'nfl':
    case 'soccer':
    case 'football':
    case 'ufc':
    case 'mma':
    case 'tennis':
    case 'golf':
    case 'f1':
      return const Color(0xFF1FA663); // green
    case 'esports':
    case 'gaming':
    case 'games':
      return const Color(0xFF8B5CF6);
    case 'politics':
    case 'elections':
    case 'election':
    case 'trump':
    case 'congress':
    case 'supreme-court':
      return const Color(0xFF3B82F6);
    case 'world':
    case 'ukraine':
    case 'russia':
    case 'china':
    case 'israel':
    case 'iran':
    case 'middle-east':
      return const Color(0xFF0EA5E9);
    case 'business':
    case 'fed':
    case 'interest-rates':
    case 'economy':
      return const Color(0xFF1FA663);
    case 'tech':
    case 'technology':
    case 'ai':
      return const Color(0xFF6366F1);
    case 'science':
    case 'spacex':
    case 'nasa':
    case 'space':
    case 'climate':
      return const Color(0xFF06B6D4);
    case 'entertainment':
    case 'movies':
    case 'oscars':
    case 'music':
      return const Color(0xFFEC4899);
    default:
      return fallback;
  }
}
