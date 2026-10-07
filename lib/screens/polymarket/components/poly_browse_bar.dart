// lib/screens/polymarket/components/poly_browse_bar.dart
//
// The Predictions browse controls: the row of category pills and, inside
// a category that has them, a second row of its subcategories. Both rows
// are the shared KutePill (the pill every other row in the app uses), so
// they read exactly like the category strip this screen always had. Rows
// scroll sideways and bring the selected pill into view by themselves.
// "More" lists every category with its subcategories on the app's shared
// bottom sheet.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart'
    show polymarketTagOffered;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

String polyPillLabel(AppLocalizations l10n, PolyPill pill) => switch (pill) {
      PolyPill.watchlist => '★ ${l10n.polyPillWatchlist}',
      PolyPill.trending => l10n.polyPillTrending,
      PolyPill.breaking => l10n.polyPillBreaking,
      PolyPill.newest => l10n.polyPillNew,
      PolyPill.live => l10n.polyPillLive,
      PolyPill.politics => l10n.polyPillPolitics,
      PolyPill.sports => l10n.polyPillSports,
      PolyPill.crypto => l10n.polyPillCrypto,
      PolyPill.esports => l10n.polyPillEsports,
      PolyPill.finance => l10n.polySubFinance,
      PolyPill.geopolitics => l10n.polyPillGeopolitics,
      PolyPill.tech => l10n.polyPillTech,
      PolyPill.culture => l10n.polyPillCulture,
      PolyPill.economy => l10n.polyPillEconomy,
      PolyPill.weather => l10n.polyPillWeather,
      PolyPill.mentions => l10n.polyPillMentions,
      PolyPill.elections => l10n.polyPillElections,
    };

/// A subcategory chip's label: its own for a Gamma tag, a league, a game
/// or a coin (proper names), the localised name for the fixed chips.
String polySubLabel(AppLocalizations l10n, PolySub sub) {
  if (sub.label != null && sub.label!.isNotEmpty) return sub.label!;
  return switch (sub.key) {
    'all' => l10n.polySubAll,
    '5m' => l10n.polySub5m,
    '15m' => l10n.polySub15m,
    '1h' => l10n.polySub1h,
    '4h' => l10n.polySub4h,
    'daily' => l10n.polySubDaily,
    'weekly' => l10n.polySubWeekly,
    'monthly' => l10n.polySubMonthly,
    'yearly' => l10n.polySubYearly,
    'pre-market' => l10n.polySubPreMarket,
    'targets' => l10n.polySubTargets,
    'institutions' => l10n.polySubInstitutions,
    'industry' => l10n.polySubIndustry,
    'protocol-metrics' => l10n.polySubProtocolMetrics,
    'live' => l10n.polyPillLive,
    'futures' => l10n.polySubFutures,
    // Breaking's topics.
    'politics' => l10n.polyPillPolitics,
    'world' => l10n.polyPillWorld,
    'sports' => l10n.polyPillSports,
    'crypto' => l10n.polyPillCrypto,
    'finance' => l10n.polySubFinance,
    'tech' => l10n.polyPillTech,
    'culture' => l10n.polyPillCulture,
    // Finance.
    'stocks' => l10n.polySubStocks,
    'earnings' => l10n.polySubEarnings,
    'indicies' => l10n.polySubIndices,
    'commodities' => l10n.polySubCommodities,
    'forex' => l10n.polySubForex,
    'privates' => l10n.polySubPrivates,
    'acquisitions' => l10n.polySubAcquisitions,
    'ipo' => l10n.polySubIpos,
    'fed-rates' => l10n.polySubFedRates,
    'prediction-markets' => l10n.polySubPredictionMarkets,
    'treasuries' => l10n.polySubTreasuries,
    'kpis' => l10n.polySubKpis,
    // Weather.
    'temperature' => l10n.polySubTemperature,
    'precipitation' => l10n.polySubPrecipitation,
    'drought' => l10n.polySubDrought,
    'global' => l10n.polySubGlobal,
    'tornadoes' => l10n.polySubTornadoes,
    'hurricanes' => l10n.polySubHurricanes,
    'earthquakes' => l10n.polySubEarthquakes,
    'volcanoes' => l10n.polySubVolcanoes,
    'pandemics' => l10n.polySubPandemics,
    // Sports.
    'soccer' => l10n.polySportSoccer,
    'tennis' => l10n.polySportTennis,
    'cricket' => l10n.polySportCricket,
    'basketball' => l10n.polySportBasketball,
    'baseball' => l10n.polySportBaseball,
    'football' => l10n.polySportFootball,
    'hockey' => l10n.polySportHockey,
    'rugby' => l10n.polySportRugby,
    'table-tennis' => l10n.polySportTableTennis,
    'darts' => l10n.polySportDarts,
    'handball' => l10n.polySportHandball,
    'golf' => l10n.polySportGolf,
    'mma' => l10n.polySportCombat,
    'motorsports' => l10n.polySportMotorsports,
    'cycling' => l10n.polySportCycling,
    'chess' => l10n.polySportChess,
    _ => sub.key,
  };
}

/// A crypto round's window as the Crypto row names it ("15 Min",
/// "1 Hour", "4 Hours"); any other length in minutes or hours.
String polyRoundWindowLabel(AppLocalizations l10n, Duration window) =>
    switch (window.inMinutes) {
      5 => l10n.polySub5m,
      15 => l10n.polySub15m,
      60 => l10n.polySub1h,
      240 => l10n.polySub4h,
      final m when m % 60 == 0 => '${m ~/ 60}h',
      final m => '${m}m',
    };

/// The logo a chip shows before its name, at the text's height: a
/// league's, a sport's or a game's own (Gamma `/sports`) on Sports and
/// Esports, a coin's on Crypto. Null for every other chip (and for a chip
/// of those rows with no logo), which stays text only. PolyCrestImage
/// draws rasters and SVGs alike; a logo that fails to load leaves the
/// chip as text.
Widget? polySubLogo(PolyPill pill, PolySub sub) {
  if (pill != PolyPill.sports &&
      pill != PolyPill.esports &&
      pill != PolyPill.crypto) {
    return null;
  }
  final url = sub.imageUrl;
  if (url == null || url.isEmpty) return null;
  final size = 14.sp;
  return PolyCrestImage(
    url: url,
    size: size,
    radius: 3.r,
    fit: BoxFit.contain,
    fallback: SizedBox(width: size, height: size),
  );
}

/// A sideways row that keeps its selected child in view: on first layout
/// and whenever [selectedIndex] changes it scrolls that child towards the
/// middle.
class PolyAutoScrollRow extends StatefulWidget {
  final int itemCount;
  final int? selectedIndex;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double height;
  final double spacing;

  /// Inset at the two ends of the row (the screen's side margin).
  final double padding;

  const PolyAutoScrollRow({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.height,
    this.spacing = 6,
    this.padding = 16,
  });

  @override
  State<PolyAutoScrollRow> createState() => _PolyAutoScrollRowState();
}

class _PolyAutoScrollRowState extends State<PolyAutoScrollRow> {
  final Map<int, GlobalKey> _keys = {};
  final ScrollController _controller = ScrollController();

  GlobalKey _keyFor(int i) => _keys.putIfAbsent(i, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _reveal(animate: false);
  }

  @override
  void didUpdateWidget(covariant PolyAutoScrollRow old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex ||
        old.itemCount != widget.itemCount) {
      _reveal(animate: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Centres the selected child in this row only. (Scrollable.ensureVisible
  /// would also scroll the page around the row.)
  void _reveal({required bool animate}) {
    final i = widget.selectedIndex;
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _keys[i]?.currentContext?.findRenderObject();
      if (!mounted || box == null || !box.attached || !_controller.hasClients) {
        return;
      }
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport == null) return;
      final target = viewport
          .getOffsetToReveal(box, 0.5)
          .offset
          .clamp(0.0, _controller.position.maxScrollExtent);
      if (animate) {
        _controller.animateTo(target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic);
      } else {
        _controller.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: widget.padding.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.itemCount; i++) ...[
              if (i > 0) SizedBox(width: widget.spacing.w),
              KeyedSubtree(
                  key: _keyFor(i), child: widget.itemBuilder(context, i)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Level 1: the category pills plus "More ›".
class PolyPillRow extends StatelessWidget {
  final List<PolyPill> pills;
  final PolyPill selected;
  final ValueChanged<PolyPill> onSelect;
  final VoidCallback onMore;

  const PolyPillRow({
    super.key,
    required this.pills,
    required this.selected,
    required this.onSelect,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final index = pills.indexOf(selected);
    return PolyAutoScrollRow(
      height: 34.h,
      itemCount: pills.length + 1,
      selectedIndex: index < 0 ? null : index,
      itemBuilder: (context, i) {
        if (i == pills.length) {
          return KutePill(
            label: '${l10n.polyPillMore} ›',
            selected: false,
            onTap: onMore,
          );
        }
        final pill = pills[i];
        return KutePill(
          label: polyPillLabel(l10n, pill),
          selected: pill == selected,
          onTap: () => onSelect(pill),
        );
      },
    );
  }
}

/// Level 2: the subcategories of the category on screen, in the same
/// pills as the row above.
class PolySubRow extends StatelessWidget {
  final PolyPill pill;
  final List<PolySub> subs;
  final String selectedKey;
  final ValueChanged<PolySub> onSelect;

  const PolySubRow({
    super.key,
    required this.pill,
    required this.subs,
    required this.selectedKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final index = subs.indexWhere((s) => s.key == selectedKey);
    return PolyAutoScrollRow(
      height: 34.h,
      itemCount: subs.length,
      selectedIndex: index < 0 ? null : index,
      itemBuilder: (context, i) => KutePill(
        label: polySubLabel(l10n, subs[i]),
        leading: polySubLogo(pill, subs[i]),
        selected: subs[i].key == selectedKey,
        onTap: () => onSelect(subs[i]),
      ),
    );
  }
}

/// The subcategories under [pill], from the first frame (each source
/// draws its last copy from disk and then the live one), in
/// polymarket.com's order. A list of one or none means the pill has no
/// row of them.
List<PolySub> polySubsFor(WidgetRef ref, PolyPill pill) {
  final policy = ref.watch(runtimeCapabilitiesProvider);
  switch (pill) {
    case PolyPill.crypto:
      return ref.watch(polyCryptoSubsProvider).valueOrNull ??
          polyCryptoSubsFromCounts(null);
    case PolyPill.sports:
      return ref.watch(polySportsSubsProvider);
    case PolyPill.esports:
      return ref.watch(polyEsportsSubsProvider).valueOrNull ??
          polyEsportsSubsFrom();
    case PolyPill.breaking:
      return [
        for (final key in kPolyBreakingTopics)
          if (key == 'all' || polymarketTagOffered(key, policy)) PolySub(key),
      ];
    case PolyPill.finance:
      return [for (final key in kPolyFinanceSubs) PolySub(key)];
    case PolyPill.weather:
      return [for (final key in kPolyWeatherSubs) PolySub(key)];
    case PolyPill.politics:
    case PolyPill.geopolitics:
    case PolyPill.tech:
    case PolyPill.culture:
    case PolyPill.economy:
      return [
        const PolySub('all'),
        ...ref.watch(polyTopicSubsProvider(pill)).valueOrNull ??
            const <PolySub>[],
      ];
    case PolyPill.watchlist:
    case PolyPill.trending:
    case PolyPill.newest:
    case PolyPill.live:
    case PolyPill.mentions:
    case PolyPill.elections:
      return const [];
  }
}

/// "More ›": the categories with their subcategories in one list, on the
/// app's shared bottom sheet. Picking a row shows that list.
Future<void> showPolyMoreSheet(
  BuildContext context, {
  required List<PolyPill> pills,
  required PolyBrowseSelection selection,
  required void Function(PolyPill pill, PolySub sub) onPick,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) =>
        _PolyMoreSheet(pills: pills, selection: selection, onPick: onPick),
  );
}

class _PolyMoreSheet extends ConsumerWidget {
  final List<PolyPill> pills;
  final PolyBrowseSelection selection;
  final void Function(PolyPill pill, PolySub sub) onPick;

  const _PolyMoreSheet({
    required this.pills,
    required this.selection,
    required this.onPick,
  });

  static List<PolySub> _rowsOf(List<PolySub> subs) =>
      subs.isEmpty ? const [PolySub('all')] : subs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: l10n.polyMoreTitle),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 8.h),
              children: [
                for (final pill in pills)
                  if (pill.isTopic) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 6.h),
                      child: Text(
                        polyPillLabel(l10n, pill),
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    // A category with no subcategories is one row: all of it.
                    for (final sub in _rowsOf(polySubsFor(ref, pill)))
                      AppBottomSheetListTile(
                        title: polySubLabel(l10n, sub),
                        isSelected: selection.pill == pill &&
                            selection.subOf(pill) == sub.key,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop();
                          onPick(pill, sub);
                        },
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
