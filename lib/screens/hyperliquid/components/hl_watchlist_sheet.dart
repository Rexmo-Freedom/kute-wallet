// lib/screens/hyperliquid/components/hl_watchlist_sheet.dart
//
// THE INVESTING WATCHLIST SHEET (founder, 13 November 2026: "on
// Investing, when we click on the filters we should have 'create a
// watchlist' … Watchlist creation should be a bottom modal sheet"). The
// app's standard sheet (showAppBottomSheet, AppBottomSheetContainer at 0.9
// of the screen): the handle, the title ("Create a watchlist" with a line
// saying Investing opens on it, or "Watchlist" once one exists) and the
// close, the app's search input (PickerSearchField, "Search markets"),
// then the Investing markets as the browse list's own rows (HlMarketCard
// in one grouped card: the logo, the name, the live price over its 24h
// change) with a check at each row's end: a ticked circle on the
// watchlist, an empty "+" circle off it (the Portfolio builder's pick
// check). A tap ticks or unticks the row; nothing is written until Done.
//
// DONE IS THE BAR (kute_bar_context.dart: every pinned primary button is
// the floating Sal bar): "Done" saves the ticks as the watchlist, newest
// tick first, the ones kept in their order after them, and closes. Closing
// any other way (the close, a swipe) keeps the watchlist as it was.
//
// ONE LIST: the watchlist IS the stars of the market pages
// (hlWatchlistProvider, HlWatchStar). The sheet opens with every starred
// market ticked; a star after a save shows here the next time.
//
// THE ROWS: with no search, the watchlist's markets first (in its order),
// then every other Investing market by 24 h volume, one listing per
// underlying (hlPrimaryListings), as the browse lists show them. A search
// lists every market that answers it (hlMarketMatchesQuery: the ticker,
// the app's name for it, the venue's names and keywords), by volume, the
// ticked ones included. A market the policy keeps from being bought here
// is listed like any other (founder, 12 November 2026): its ticket says
// so.
//
// EVENTS: `watchlist_sheet_opened` {venue: hyperliquid, mode: create |
// edit, source, list_size}; on a Done that changes the list, one
// `watchlist_toggled` per market added or removed (the star's event,
// source `watchlist_sheet`, trackHlWatchlistToggled) and
// `watchlist_saved` {venue, mode, source, added, removed, list_size}.
// Exact counts, the public symbol only; never an id.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show hlFriendlyName, hlPrimaryListings;
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_watch_star.dart'
    show trackHlWatchlistToggled;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/asset_network_picker.dart'
    show PickerSearchField;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/market_groups.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Opens the watchlist sheet (see the file header) over [context];
/// [source] names where it was opened from (`category_sheet`,
/// `watchlist_view`). Completes true when Done saved a change.
Future<bool> showHlWatchlistSheet(BuildContext context,
    {required String source}) async {
  HapticFeedback.selectionClick();
  final saved = await showAppBottomSheet<bool>(
    context: context,
    builder: (_) => HlWatchlistSheet(source: source),
  );
  return saved ?? false;
}

/// The markets the sheet lists (see the file header): with an empty
/// [query], [picked]'s markets first in its order, then the rest of
/// [universe] by 24 h volume, one listing per underlying; with a query,
/// every market that answers it, by volume.
List<HlMarket> hlWatchlistSheetRows(
    List<HlMarket> universe, List<String> picked, String query) {
  final byVolume = [...universe]
    ..sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
  final q = query.trim();
  if (q.isNotEmpty) {
    return [
      for (final m in byVolume)
        if (hlMarketMatchesQuery(m, q,
            friendlyName:
                hlFriendlyName(m.underlyingTicker) ?? m.unitAssetName))
          m,
    ];
  }
  final first = hlWatchlistMarkets(picked, universe);
  final keys = {for (final m in first) hlWatchlistKey(m)};
  return [
    ...first,
    for (final m in hlPrimaryListings(byVolume))
      if (!keys.contains(hlWatchlistKey(m))) m,
  ];
}

class HlWatchlistSheet extends ConsumerStatefulWidget {
  const HlWatchlistSheet({super.key, required this.source});

  final String source;

  @override
  ConsumerState<HlWatchlistSheet> createState() => _HlWatchlistSheetState();
}

class _HlWatchlistSheetState extends ConsumerState<HlWatchlistSheet> {
  /// The watchlist as the sheet opened on it.
  late final List<String> _initial;

  /// The ticks, newest first.
  late List<String> _picked;

  /// The order the rows were listed in for an empty search, fixed at open
  /// so a tick never moves a row.
  late final List<String> _openOrder;

  final _search = TextEditingController();
  String _query = '';

  bool get _creating => _initial.isEmpty;

  @override
  void initState() {
    super.initState();
    _initial = List.unmodifiable(ref.read(hlWatchlistProvider));
    _picked = [..._initial];
    _openOrder = List.unmodifiable(_initial);
    TrackingService.track('watchlist_sheet_opened', params: {
      'venue': 'hyperliquid',
      'mode': _creating ? 'create' : 'edit',
      'source': widget.source,
      'list_size': _initial.length,
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// A row's tap (the row gives its own haptic).
  void _toggle(HlMarket m) {
    final key = hlWatchlistKey(m);
    setState(() {
      _picked = _picked.contains(key)
          ? [
              for (final k in _picked)
                if (k != key) k
            ]
          : [key, ..._picked];
    });
  }

  void _done() {
    final added = [
      for (final k in _picked)
        if (!_initial.contains(k)) k
    ];
    final removed = [
      for (final k in _initial)
        if (!_picked.contains(k)) k
    ];
    final changed = added.isNotEmpty ||
        removed.isNotEmpty ||
        !_sameOrder(_picked, _initial);
    if (changed) {
      final universe =
          ref.read(hyperliquidBrowseUniverseProvider).valueOrNull ??
              const <HlMarket>[];
      final byKey = {for (final m in universe) hlWatchlistKey(m): m};
      ref.read(hlWatchlistProvider.notifier).replaceAll(_picked);
      final size = _picked.length;
      for (final (keys, isAdd) in [(added, true), (removed, false)]) {
        for (final k in keys) {
          final m = byKey[k];
          if (m != null) {
            trackHlWatchlistToggled(m,
                added: isAdd, source: 'watchlist_sheet', listSize: size);
          }
        }
      }
      TrackingService.track('watchlist_saved', params: {
        'venue': 'hyperliquid',
        'mode': _creating ? 'create' : 'edit',
        'source': widget.source,
        'added': added.length,
        'removed': removed.length,
        'list_size': size,
      });
    }
    Navigator.of(context).pop(changed);
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final universe = ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
        const <HlMarket>[];
    final rows = hlWatchlistSheetRows(universe, _openOrder, _query);
    final picked = _picked.toSet();

    Widget check(bool on) => Semantics(
          label: on ? l10n.polyWatchlistRemove : l10n.polyWatchlistAdd,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Icon(
              on
                  ? Icons.check_circle_rounded
                  : Icons.add_circle_outline_rounded,
              key: ValueKey<bool>(on),
              size: 22.sp,
              color: on ? context.ctaFill : c.textTertiary,
            ),
          ),
        );

    return KuteBarContextScope(
      // THE BAR IS THE BUTTON: Done saves (see the file header).
      barContext: KuteBarContext.primary(
        label: l10n.done,
        onPrimary: _done,
        source: 'hl_watchlist_sheet',
        disabledLabel: null,
      ),
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        followKeyboard: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              key: const ValueKey('hl-watchlist-sheet-header'),
              title:
                  _creating ? l10n.hlWatchlistCreate : l10n.polyPillWatchlist,
              subtitle: _creating ? l10n.hlWatchlistCreateHint : null,
              trailing: const AppBottomSheetCloseButton(),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: PickerSearchField(
                key: const ValueKey('hl-watchlist-search'),
                controller: _search,
                hint: l10n.searchMarketsHint,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: CustomScrollView(
                key: const ValueKey('hl-watchlist-sheet-list'),
                shrinkWrap: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (rows.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 24.w, vertical: 32.h),
                        child: Text(
                          l10n.builderNoMarketsFound,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                  else
                    ...marketGroupSlivers<HlMarket>(
                      context,
                      items: rows,
                      groups: (_) => true,
                      dividerIndent: hlGroupRowIndent(),
                      divider: hlGroupRowDivider,
                      build: (m, inGroup) {
                        final on = picked.contains(hlWatchlistKey(m));
                        return HlMarketCard(
                          key: ValueKey(
                              'hl-watchlist-row-${m.kind.name}-${m.wireCoin}'),
                          market: m,
                          inGroup: inGroup,
                          onTap: () => _toggle(m),
                          trailing: check(on),
                        );
                      },
                    ),
                  // The last rows scroll clear of the floating Done.
                  SliverToBoxAdapter(
                      child: SizedBox(height: kuteBarScrollClearance.h)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
