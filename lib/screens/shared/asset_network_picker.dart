// lib/screens/shared/asset_network_picker.dart
//
// Shared building blocks for the coin / network picker sheets used by
// the Receive, Send, Predictions and Deposit-crypto flows. Every flow
// keeps its own selection logic, route wiring and analytics — this
// file only owns the shared look:
//
//   * [PickerSearchField]   — the app-input styled search field
//                             (surfaceLight fill, 12.r, hairline border).
//   * [PickerGroupedList]   — rows inside one rounded surface card with
//                             hairline dividers indented past the icon
//                             (same chrome as the add-wallet grouped
//                             card).
//   * [PickerRow]           — 44 icon + display name, optional
//                             informative subtitle, optional selected
//                             check. No chevron: tapping selects.
//   * [ChainAvatarIcon]     — network avatar: local brand asset, then
//                             an optional remote icon URL, then a
//                             lettered fallback disc. Its own class so
//                             lazy lists can read the theme safely.
//   * [NetworkChipAssetPicker] — the Receive-other-assets / Send-
//                             destination body: search field, a
//                             one-row strip of network chips (All
//                             selected by default, "More" opens the
//                             full network sheet), then the asset rows.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/providers/asset_icon_provider.dart' show SafeSvgNetwork;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Local brand asset for a network id/name, or null when we only have
/// the remote icon. Shared by every picker (previously duplicated in
/// confirm_receive.dart and confirm_send.dart).
String? networkLocalAsset(String network) {
  final n = network.toLowerCase().trim();
  const exact = <String, String>{
    'ethereum': 'lib/assets/eth.svg',
    'tron': 'lib/assets/trx.svg',
    'solana': 'lib/assets/sol.svg',
    'bsc': 'lib/assets/bnb.svg',
    'binance': 'lib/assets/bnb.svg',
    'binance-smart-chain': 'lib/assets/bnb.svg',
    'polygon': 'lib/assets/pol.svg',
    'liquid': 'lib/assets/liquid-btc.svg',
    'near': 'lib/assets/near-protocol-near-logo.svg',
    'sui': 'lib/assets/sui-sui-logo.svg',
    'xrp': 'lib/assets/xrp-xrp-logo.svg',
    'ripple': 'lib/assets/xrp-xrp-logo.svg',
    'cardano': 'lib/assets/cardano-ada-logo.svg',
    'litecoin': 'lib/assets/litecoin-ltc-logo.svg',
    'polkadot': 'lib/assets/polkadot-new-dot-logo.svg',
    'arbitrum': 'lib/assets/arbitrum-logo.png',
    'bitcoin': 'lib/assets/bitcoin-icon.svg',
    'spark': 'lib/assets/spark-logo.svg',
    'lightning': 'lib/assets/sats-icon.svg',
    // Hyperliquid's two rails share the brand mark.
    'hyperevm': 'lib/assets/hyperliquid-logo.svg',
    'hypercore': 'lib/assets/hyperliquid-logo.svg',
  };
  final direct = exact[n];
  if (direct != null) return direct;
  // Common multi-word / aliased forms (e.g. 'binance smart chain').
  if (n.contains('binance') || n.contains('bsc')) return 'lib/assets/bnb.svg';
  if (n.contains('ethereum')) return 'lib/assets/eth.svg';
  if (n.contains('tron')) return 'lib/assets/trx.svg';
  if (n.contains('solana')) return 'lib/assets/sol.svg';
  if (n.contains('polygon')) return 'lib/assets/pol.svg';
  if (n.contains('liquid')) return 'lib/assets/liquid-btc.svg';
  if (n.contains('near')) return 'lib/assets/near-protocol-near-logo.svg';
  if (n.contains('sui')) return 'lib/assets/sui-sui-logo.svg';
  if (n.contains('xrp') || n.contains('ripple')) {
    return 'lib/assets/xrp-xrp-logo.svg';
  }
  if (n.contains('cardano')) return 'lib/assets/cardano-ada-logo.svg';
  if (n.contains('litecoin')) return 'lib/assets/litecoin-ltc-logo.svg';
  if (n.contains('polkadot')) return 'lib/assets/polkadot-new-dot-logo.svg';
  if (n.contains('arbitrum')) return 'lib/assets/arbitrum-logo.png';
  if (n.contains('bitcoin')) return 'lib/assets/bitcoin-icon.svg';
  return null;
}

/// The picker's search input — app input language: surfaceLight fill,
/// 12.r corners, hairline border, accent focus ring.
class PickerSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const PickerSearchField({
    super.key,
    this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(
        color: c.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: c.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: c.textTertiary,
          fontSize: 16.sp,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon:
            Icon(Icons.search_rounded, size: 22.sp, color: c.textTertiary),
        filled: true,
        fillColor: c.surfaceLight,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: c.borderSubtle, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
      ),
    );
  }
}

/// One rounded surface card wrapping the picker rows, with hairline
/// dividers indented past the 44 icon — the add-wallet grouped-card
/// chrome, so every grouped picker reads as the same surface.
class PickerGroupedList extends StatelessWidget {
  final List<Widget> children;
  const PickerGroupedList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          children: [
            // No hairline between rows (user decision).
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A single selectable picker row: 44 icon, display name, optional
/// INFORMATIVE subtitle (never a lowercase slug duplicate), optional
/// selected check. Tap selects (selectionClick haptic) — no chevron.
/// Its own class so lazy/grouped lists re-skin on live theme change.
class PickerRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  const PickerRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              SizedBox(
                  width: 44.sp, height: 44.sp, child: Center(child: leading)),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16.5.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 13.5.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                SizedBox(width: 8.w),
                Icon(Icons.check_circle_rounded, size: 20.sp, color: c.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Generic chain avatar for catalog-driven chains: local brand asset
/// when we ship one, else an optional remote icon URL (SVG-safe), else
/// the lettered disc. Own class so lazy lists re-skin on live theme
/// change.
class ChainAvatarIcon extends StatelessWidget {
  final String chainId;
  final String label;
  final String? iconUrl;

  /// Logical size (pre-`.sp`).
  final double size;

  const ChainAvatarIcon({
    super.key,
    required this.chainId,
    required this.label,
    this.iconUrl,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = size.sp;
    final source = label.isNotEmpty ? label : chainId;
    final initials =
        source.substring(0, source.length.clamp(0, 3)).toUpperCase();
    Widget fallback() => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Center(
            child: Text(
              initials,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: (size * 0.32).sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );

    final localAsset = networkLocalAsset(chainId);
    if (localAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: localAsset.endsWith('.svg')
            ? SvgPicture.asset(localAsset, width: s, height: s)
            : Image.asset(localAsset,
                width: s,
                height: s,
                cacheWidth:
                    (s * MediaQuery.devicePixelRatioOf(context)).round()),
      );
    }
    final url = iconUrl;
    if (url != null && url.isNotEmpty) {
      // Raster chain artwork (e.g. Flashnet's '/chain-tempo.png') goes
      // through CachedNetworkImage; everything else is treated as SVG
      // (SafeSvgNetwork sniffs the body and falls back on non-SVG).
      final isRaster = url.endsWith('.png') ||
          url.endsWith('.jpg') ||
          url.endsWith('.jpeg') ||
          url.endsWith('.webp');
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: isRaster
            ? CachedNetworkImage(
                imageUrl: url,
                width: s,
                height: s,
                memCacheWidth: (size * 4).round(),
                placeholder: (ctx, u) => SizedBox(width: s, height: s),
                errorWidget: (ctx, u, err) => fallback(),
              )
            : SafeSvgNetwork(
                url: url, width: s, height: s, fallback: fallback()),
      );
    }
    return fallback();
  }
}

/// Coin avatar with a small chain badge overlaid bottom-right — the
/// two-pane picker's row icon (Flashnet-style "asset on chain" glyph).
/// Own class so the badge ring reads the live theme surface color.
class PickerCoinBadgeIcon extends StatelessWidget {
  final Widget coinIcon;
  final Widget? badge;

  /// Logical size of the coin icon (pre-`.sp`).
  final double size;

  const PickerCoinBadgeIcon({
    super.key,
    required this.coinIcon,
    this.badge,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = size.sp;
    if (badge == null) {
      return SizedBox(width: s, height: s, child: coinIcon);
    }
    final badgeSize = (size * 0.5).sp;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: coinIcon),
          Positioned(
            right: -2.sp,
            bottom: -2.sp,
            child: Container(
              padding: EdgeInsets.all(1.5.sp),
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: SizedBox(
                  width: badgeSize,
                  height: badgeSize,
                  child: badge,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chip-filtered asset picker ─────────────────────────────────────
//
// The Receive-other-assets and Send-destination sheets: a full-width
// searchable asset list with a compact network filter above it. The
// filter is a single-row strip of small chips: "All" (selected by
// default, so the sheet opens as the plain asset list), the busiest
// networks by asset count, the active network when it sits outside
// that head, and a trailing "More" chip that opens the full network
// list in a small sheet. The picker only owns filtering and layout;
// every row carries its own icon, labels and tap handler, so consumers
// keep their selection logic, gating and analytics.

/// One network the picker can filter by. [id] is the scope key asset
/// rows are matched against ('bitcoin', 'lightning', or a catalog chain
/// slug). [iconBuilder] renders the network mark at a logical size
/// (pre-`.sp`) so one entry serves both the small chip and the larger
/// row in the full network sheet.
class PickerChainEntry {
  final String id;
  final String name;
  final Widget Function(double size) iconBuilder;

  const PickerChainEntry({
    required this.id,
    required this.name,
    required this.iconBuilder,
  });
}

/// One asset row. [chainId] scopes it under a network; [pinned] rows
/// (our native rails) sort first within their scope.
class PickerAssetEntry {
  final String id;
  final String title;
  final String subtitle;
  final String chainId;

  /// Extra haystack for search (code, chain name, …). Title and
  /// subtitle are always matched too.
  final String searchText;
  final Widget icon;
  final bool pinned;
  final VoidCallback onTap;

  const PickerAssetEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.chainId,
    required this.icon,
    required this.onTap,
    this.searchText = '',
    this.pinned = false,
  });
}

/// Scope key for the "All" network chip and sheet row.
const String kPickerAllChainsId = 'all';

/// Chip label for a network: long multi-word names keep their first
/// word ('Robinhood Chain' reads 'Robinhood') so the strip stays one
/// row of short chips; the full name still shows in the network sheet.
String _chipLabel(String name) {
  final trimmed = name.trim();
  if (trimmed.length <= 12) return trimmed;
  final first = trimmed.split(RegExp(r'\s+')).first;
  return first.isEmpty ? trimmed : first;
}

/// The picker body: search field, the network chip strip, then the
/// asset rows. Network selection and the search query live in
/// ValueNotifiers so a chip tap rebuilds ONLY the strip and the row
/// list, never the surrounding sheet.
class NetworkChipAssetPicker extends StatefulWidget {
  final List<PickerChainEntry> chains;
  final List<PickerAssetEntry> assets;

  /// Localized label for the "All" chip / sheet row.
  final String allLabel;

  /// Localized label for the trailing chip that opens the full list.
  final String moreLabel;

  /// Title and search hint of the full network sheet.
  final String networksTitle;
  final String networksSearchHint;
  final String searchHint;
  final String emptyLabel;
  final String? initialQuery;

  /// How many networks (ranked by asset count) the strip shows inline
  /// before the "More" chip.
  final int maxInlineChips;

  /// Fired on every network selection (analytics), with the chain id;
  /// [kPickerAllChainsId] for All. Fires for chip taps and for picks
  /// made in the full network sheet alike.
  final ValueChanged<String>? onChainSelected;

  /// Fired when the "More" chip opens the full network sheet.
  final VoidCallback? onMoreOpened;

  const NetworkChipAssetPicker({
    super.key,
    required this.chains,
    required this.assets,
    required this.allLabel,
    required this.moreLabel,
    required this.networksTitle,
    required this.networksSearchHint,
    required this.searchHint,
    required this.emptyLabel,
    this.initialQuery,
    this.maxInlineChips = 6,
    this.onChainSelected,
    this.onMoreOpened,
  });

  @override
  State<NetworkChipAssetPicker> createState() => _NetworkChipAssetPickerState();
}

class _NetworkChipAssetPickerState extends State<NetworkChipAssetPicker> {
  final ValueNotifier<String> _chain = ValueNotifier(kPickerAllChainsId);
  late final ValueNotifier<String> _query;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialQuery?.trim() ?? '';
    _query = ValueNotifier(seed);
    _searchController = TextEditingController(text: seed);
  }

  @override
  void didUpdateWidget(covariant NetworkChipAssetPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The consumers watch the live catalog, so the data can change
    // after the sheet opened; a network that vanished must not leave
    // the list scoped to nothing.
    final selected = _chain.value;
    if (selected != kPickerAllChainsId &&
        !widget.chains.any((c) => c.id == selected)) {
      _chain.value = kPickerAllChainsId;
    }
  }

  @override
  void dispose() {
    _chain.dispose();
    _query.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onChainTap(String id) {
    if (_chain.value == id) return;
    _chain.value = id;
    widget.onChainSelected?.call(id);
  }

  Future<void> _openNetworkSheet() async {
    widget.onMoreOpened?.call();
    final picked = await showAppBottomSheet<String>(
      context: context,
      builder: (ctx) => _NetworkListSheet(
        title: widget.networksTitle,
        searchHint: widget.networksSearchHint,
        allLabel: widget.allLabel,
        emptyLabel: widget.emptyLabel,
        chains: widget.chains,
        selectedId: _chain.value,
      ),
    );
    if (picked == null || !mounted) return;
    _onChainTap(picked);
  }

  /// Networks ranked by how many rows they scope (most first); ties
  /// keep the caller's order, which already pins the majors.
  List<PickerChainEntry> _rankedChains() {
    final counts = <String, int>{};
    for (final a in widget.assets) {
      counts[a.chainId] = (counts[a.chainId] ?? 0) + 1;
    }
    final indexed = widget.chains.asMap().entries.toList()
      ..sort((a, b) {
        final byCount =
            (counts[b.value.id] ?? 0).compareTo(counts[a.value.id] ?? 0);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  /// The chips shown inline: the ranked head, plus the active network
  /// when it lives past the head, so the user can see (and clear) the
  /// filter without reopening the sheet.
  List<PickerChainEntry> _inlineChains(String selected) {
    final head = _rankedChains().take(widget.maxInlineChips).toList();
    if (selected != kPickerAllChainsId && !head.any((c) => c.id == selected)) {
      for (final c in widget.chains) {
        if (c.id == selected) {
          head.add(c);
          break;
        }
      }
    }
    return head;
  }

  List<PickerAssetEntry> _visibleAssets(String chain, String query) {
    final q = query.trim().toLowerCase();
    final scoped = widget.assets.where((a) {
      if (chain != kPickerAllChainsId && a.chainId != chain) return false;
      if (q.isEmpty) return true;
      return a.title.toLowerCase().contains(q) ||
          a.subtitle.toLowerCase().contains(q) ||
          a.searchText.toLowerCase().contains(q);
    }).toList();
    // Stable pinned-first ordering (native rails on top).
    final pinned = scoped.where((a) => a.pinned).toList();
    final rest = scoped.where((a) => !a.pinned).toList();
    return [...pinned, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickerSearchField(
          controller: _searchController,
          hint: widget.searchHint,
          onChanged: (v) => _query.value = v,
        ),
        if (widget.chains.isNotEmpty) ...[
          SizedBox(height: 10.h),
          ValueListenableBuilder<String>(
            valueListenable: _chain,
            builder: (context, selected, _) => _NetworkChipStrip(
              allLabel: widget.allLabel,
              moreLabel: widget.moreLabel,
              chains: _inlineChains(selected),
              showMore: widget.chains.length > widget.maxInlineChips,
              selectedId: selected,
              onTap: _onChainTap,
              onMore: _openNetworkSheet,
            ),
          ),
        ],
        SizedBox(height: 10.h),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge([_chain, _query]),
            builder: (context, _) {
              final rows = _visibleAssets(_chain.value, _query.value);
              if (rows.isEmpty) {
                return _PickerEmptyLabel(text: widget.emptyLabel);
              }
              return ListView.builder(
                padding: EdgeInsets.only(bottom: 8.h),
                itemCount: rows.length,
                // Keyed by asset id so a filter change never hands a
                // row's icon State (network SVG) a different entry.
                itemBuilder: (context, i) => _PickerAssetRow(
                  key: ValueKey(rows[i].id),
                  entry: rows[i],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The one-row network filter: "All" first, the inline networks, then
/// the "More" chip. Horizontal scroll so a long head never wraps.
class _NetworkChipStrip extends StatelessWidget {
  final String allLabel;
  final String moreLabel;
  final List<PickerChainEntry> chains;
  final bool showMore;
  final String selectedId;
  final ValueChanged<String> onTap;
  final VoidCallback onMore;

  const _NetworkChipStrip({
    required this.allLabel,
    required this.moreLabel,
    required this.chains,
    required this.showMore,
    required this.selectedId,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _NetworkChip(
            label: allLabel,
            selected: selectedId == kPickerAllChainsId,
            onTap: () => onTap(kPickerAllChainsId),
          ),
          for (final chain in chains)
            _NetworkChip(
              label: _chipLabel(chain.name),
              icon: chain.iconBuilder(18),
              selected: selectedId == chain.id,
              onTap: () => onTap(chain.id),
            ),
          if (showMore)
            _NetworkChip(
              label: moreLabel,
              glyph: Icons.more_horiz_rounded,
              selected: false,
              onTap: onMore,
            ),
        ],
      ),
    );
  }
}

/// A single network chip: neutral surface at rest, the solid CTA fill
/// when selected (no tinted fills). Own class so it re-skins on live
/// theme change inside the strip.
class _NetworkChip extends StatelessWidget {
  final String label;
  final Widget? icon;
  final IconData? glyph;
  final bool selected;
  final VoidCallback onTap;

  const _NetworkChip({
    required this.label,
    this.icon,
    this.glyph,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = selected ? context.ctaFill : c.surfaceLight;
    final fg = selected ? context.ctaOnColor : c.textPrimary;
    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.buttonBorder,
          side: selected
              ? BorderSide.none
              : BorderSide(color: c.borderSubtle, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadius.buttonBorder,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  SizedBox(
                    width: 18.sp,
                    height: 18.sp,
                    child: Center(child: icon),
                  ),
                  SizedBox(width: 6.w),
                ] else if (glyph != null) ...[
                  Icon(glyph, size: 16.sp, color: fg),
                  SizedBox(width: 4.w),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.sp,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full network list behind the "More" chip: a small sheet with a
/// search field and one grouped card of rows ("All" first). Pops with
/// the picked id; the picker applies it and fires its analytics.
class _NetworkListSheet extends StatefulWidget {
  final String title;
  final String searchHint;
  final String allLabel;
  final String emptyLabel;
  final List<PickerChainEntry> chains;
  final String selectedId;

  const _NetworkListSheet({
    required this.title,
    required this.searchHint,
    required this.allLabel,
    required this.emptyLabel,
    required this.chains,
    required this.selectedId,
  });

  @override
  State<_NetworkListSheet> createState() => _NetworkListSheetState();
}

class _NetworkListSheetState extends State<_NetworkListSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty
        ? widget.chains
        : widget.chains
            .where((ch) =>
                ch.name.toLowerCase().contains(q) ||
                ch.id.toLowerCase().contains(q))
            .toList();
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: AppDecorations.dragHandle(context)),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                KuteCloseButton(
                  size: 36,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            PickerSearchField(
              hint: widget.searchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
            SizedBox(height: 12.h),
            Flexible(
              child: rows.isEmpty && q.isNotEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 28.h),
                      child: _PickerEmptyLabel(text: widget.emptyLabel),
                    )
                  : SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: PickerGroupedList(
                        children: [
                          if (q.isEmpty)
                            PickerRow(
                              leading: const _AllNetworksGlyph(),
                              title: widget.allLabel,
                              selected: widget.selectedId == kPickerAllChainsId,
                              onTap: () =>
                                  Navigator.of(context).pop(kPickerAllChainsId),
                            ),
                          for (final ch in rows)
                            PickerRow(
                              leading: ch.iconBuilder(36),
                              title: ch.name,
                              selected: widget.selectedId == ch.id,
                              onTap: () => Navigator.of(context).pop(ch.id),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "All" row's leading disc in the network sheet. Own class so the
/// grouped list re-skins on live theme change.
class _AllNetworksGlyph extends StatelessWidget {
  const _AllNetworksGlyph();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 36.sp,
      height: 36.sp,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(36 * 0.28),
      ),
      child: Icon(Icons.apps_rounded, size: 18.sp, color: c.textSecondary),
    );
  }
}

/// One asset row in the list. Own class so lazy-list items read the
/// theme inside their own build (live theme change safety).
class _PickerAssetRow extends StatelessWidget {
  final PickerAssetEntry entry;

  const _PickerAssetRow({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.buttonBorder,
        onTap: () {
          HapticFeedback.selectionClick();
          entry.onTap();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 9.h),
          child: Row(
            children: [
              SizedBox(
                width: 40.sp,
                height: 40.sp,
                child: Center(child: entry.icon),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15.5.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.5.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered empty-state label for the asset list and the network
/// sheet. Own class so it re-skins on live theme change.
class _PickerEmptyLabel extends StatelessWidget {
  final String text;

  const _PickerEmptyLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Text(
        text,
        style: TextStyle(color: c.textTertiary, fontSize: 15.sp),
      ),
    );
  }
}
