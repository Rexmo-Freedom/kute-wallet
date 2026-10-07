// lib/screens/shared/coin_asset_grid.dart
//
// THE COIN QUESTION, asked asset first.
//
// The shape this replaced was a searchable flat list, one row per
// (asset, network) pair. That is the right shape when the pairing
// itself is the thing being chosen, but it is the wrong shape for
// "what are they sending you": the catalogue runs to fifty pairs made
// of twenty-odd assets, USDC alone spanning a dozen chains, so a flat
// list makes a person read the same coin name a dozen times before
// they find the line that also names their network. Nobody thinks
// "USDC on Arbitrum" first. Their sender says "I have USDC".
//
// So the assets come first, as a grid of marks small enough to take in
// at a glance and short enough to need no search field. A coin that
// lives on one network goes straight through. A coin that lives on
// several asks that one short question next.
//
// AND THE SAME QUESTION IN BOTH DIRECTIONS. Receiving asks what is
// being sent to you, sending asks what should land, and the dollar
// balance asks both of its own row. None of those is a question about
// a network, so all of them live here: the grouping, the sheet that
// shows it, and the quiet line that opens the sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/providers/asset_icon_provider.dart' show AssetIcon;
import 'package:kute/screens/receive/dollars_row_labels.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/asset_network_picker.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart';
import 'package:kute/services/orchestra_routes.dart' show isVenueInternalRoute;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// One coin, with every network it can arrive on.
class CoinAssetGroup {
  const CoinAssetGroup({
    required this.key,
    required this.displayName,
    required this.displaySymbol,
    required this.options,
  });

  /// Stable grouping key: the ticker, normalized.
  final String key;

  /// What the coin is called ("USD Coin").
  final String displayName;

  /// The ticker as it is shown ("USDC").
  final String displaySymbol;

  /// The networks it arrives on, one option each, already deduped by
  /// chain and sorted by network name.
  final List<OrchestraReceiveOption> options;

  /// An asset on exactly one network needs no second question.
  bool get isSingleNetwork => options.length == 1;

  /// The artwork key. Every option in a group shares a ticker but not
  /// always its exact spelling ('USDC.e'), and the icon provider keys
  /// off the code, so the first option's is the representative one.
  String get assetCode => options.first.assetCode;
}

/// 'USDC.E' rides the USDC vocabulary, matching the route tables'
/// normalization, so bridged and native dollars are one coin here.
///
/// Tether's omnichain spelling does the same: 'USD₮0' is Tether, at par
/// with 'USDT', and two tiles wearing the same mark and the same name
/// only asked the person to tell apart two things that are not
/// different. It folds in as another network under USDT instead.
String _groupKey(String symbol) {
  final s = symbol.trim().toUpperCase().replaceAll('₮', 'T');
  if (s == 'USDT0') return 'USDT';
  return s.endsWith('.E') ? s.substring(0, s.length - 2) : s;
}

/// Folds receive options into one entry per coin.
///
/// Ordering is by reach, widest first, then alphabetical: the coins
/// that span the most networks are the ones a sender is most likely to
/// be holding, and with no search field the order is the only thing
/// doing the finding. Networks inside a group are deduped by chain
/// (bridged and native dollars on the same chain are one row) and
/// sorted by name.
List<CoinAssetGroup> groupCoinsByAsset(List<OrchestraReceiveOption> options) {
  final byKey = <String, List<OrchestraReceiveOption>>{};
  for (final option in options) {
    byKey.putIfAbsent(_groupKey(option.displaySymbol), () => []).add(option);
  }
  final groups = <CoinAssetGroup>[];
  byKey.forEach((key, rows) {
    // One row per chain, and where a chain carries both spellings the
    // plainest one wins. First-wins let a bridged 'USDC.e' represent a
    // chain that also has native USDC, so the network row and the tile's
    // artwork keyed off a name the person should never be shown.
    final byChain = <String, OrchestraReceiveOption>{};
    for (final row in rows) {
      final chain = row.chain.toLowerCase();
      final held = byChain[chain];
      if (held == null ||
          row.displaySymbol.length < held.displaySymbol.length) {
        byChain[chain] = row;
      }
    }
    final networks = byChain.values.toList();
    networks.sort((a, b) => a.chainDisplayName
        .toLowerCase()
        .compareTo(b.chainDisplayName.toLowerCase()));
    // The plainest spelling in the group wears the label: 'USDC', not
    // whichever chain's bridged 'USDC.e' happened to sort first.
    final label = rows.reduce(
        (a, b) => a.displaySymbol.length <= b.displaySymbol.length ? a : b);
    groups.add(CoinAssetGroup(
      key: key,
      displayName: label.displayName,
      displaySymbol: label.displaySymbol,
      options: networks,
    ));
  });
  groups.sort((a, b) {
    final byReach = b.options.length.compareTo(a.options.length);
    if (byReach != 0) return byReach;
    return a.displaySymbol
        .toLowerCase()
        .compareTo(b.displaySymbol.toLowerCase());
  });
  return groups;
}

/// The grid of coins. Four across on a phone, each cell a mark over its
/// ticker. No search field: the whole point of folding the pairs away
/// is that what is left fits on a screen or two.
class CoinAssetGrid extends StatelessWidget {
  const CoinAssetGrid({
    super.key,
    required this.groups,
    required this.markBuilder,
    required this.onPick,
    required this.emptyLabel,
    this.selectedKey,
  });

  final List<CoinAssetGroup> groups;

  /// The owning screen builds the artwork: the catalogues it reads ship
  /// different marks. [size] is already `.sp` scaled.
  final Widget Function(CoinAssetGroup group, double size) markBuilder;
  final ValueChanged<CoinAssetGroup> onPick;
  final String emptyLabel;
  final String? selectedKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.only(bottom: 8.h),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 10.h,
        crossAxisSpacing: 10.w,
        childAspectRatio: 0.86,
      ),
      itemCount: groups.length,
      itemBuilder: (_, index) {
        final group = groups[index];
        // Its own widget so it reads the live theme (a Theme lookup
        // inside an itemBuilder closure does not rebuild on a theme
        // change).
        return CoinAssetTile(
          label: group.displaySymbol,
          mark: markBuilder(group, 34.sp),
          selected: group.key == selectedKey,
          onTap: () => onPick(group),
        );
      },
    );
  }
}

/// One cell of [CoinAssetGrid].
class CoinAssetTile extends StatelessWidget {
  const CoinAssetTile({
    super.key,
    required this.label,
    required this.mark,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final Widget mark;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            decoration: BoxDecoration(
              color: selected ? c.surfaceElevated : c.surface,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: selected ? c.border : c.borderSubtle,
                width: selected ? 1.0 : 0.5,
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                mark,
                SizedBox(height: 8.h),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
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

/// Every coin a balance can be funded with, folded to one entry per
/// coin. Shared by the quiet line that states what a destination takes
/// and by the sheet it opens, so the marks on the line and the marks in
/// the grid can never be a different set.
///
/// The destination defaults to the wallet's bitcoin pool. The dollar
/// balance asks the same question of its own row by naming it, rather
/// than through a second function that could drift from this one.
///
/// One-time rows (a fresh quoted address per payment) are offered only
/// while `orchestra.onetime_addresses` allows them; with the switch off,
/// or no readable policy, only the reusable-address rows remain.
List<CoinAssetGroup> receiveCoinGroups(
  OrchestraRoutesCatalog catalog,
  AppLocalizations l10n, {
  String destinationChain = 'spark',
  String destinationAsset = 'BTC',
  RuntimeCapabilitiesService? policy,
}) {
  final oneTime =
      oneTimeReceiveAllowed(policy ?? RuntimeCapabilitiesService.instance);
  return groupCoinsByAsset(
    catalog
        .receiveOptions(
          destinationChain: destinationChain,
          destinationAsset: destinationAsset,
        )
        // HyperCore and Polygon USDC.e are Investing's and Predictions'
        // own rails: open to the venue flows, never a network offered
        // to a payer.
        .where((o) => !isVenueInternalRoute(o.chain, o.assetCode))
        .where((o) => o.reusableAddress || oneTime)
        // The dollar row is an ordinary source here, and it wears plain
        // dollars rather than the catalogue's spelling of the token.
        .map((o) => dollarsRowLabels(o, l10n))
        .toList(),
  );
}

/// What a row of a coin's network pane says under the network name, or
/// null when there is nothing worth saying.
///
/// A standing address is the unremarkable case and says nothing. A
/// ONE-OFF address is the one that behaves differently — fresh every
/// time, bound to one amount, expiring in about two minutes — so the
/// row names it before the tap rather than after it.
///
/// THE ONE PLACE THAT EXPLAINS A ONE-OFF. Every direction's network
/// pane reads this, so the fuller wording (what non-reusable,
/// amount-bound and expiring actually mean for the person) belongs
/// here and nowhere else.
String? coinNetworkRowNote(
        OrchestraReceiveOption option, AppLocalizations l10n) =>
    option.reusableAddress ? null : l10n.receiveOneOffTag;

/// The coins a balance can be funded with, or sent to.
///
/// ASSET FIRST, NETWORK SECOND, and that ordering is the whole point.
/// The catalogue is about fifty (asset, network) pairs made of only
/// twenty-odd assets, dollars alone spanning a dozen chains. A flat
/// list of the pairs made a person read the same coin name a dozen
/// times, and asked them to classify their money before they could be
/// paid. Nobody thinks "USDC on Arbitrum" first. Their sender says
/// "I have USDC", so that is the first and often the only question.
///
/// A coin that lives on one network goes straight through. A coin that
/// lives on several asks which one, plainly, and nothing else.
///
/// BOTH DIRECTIONS USE THIS ONE SHEET. Receiving asks what is being
/// sent to you; sending asks what should land. Neither question is
/// about a network, so both are asked the same way. The send
/// directions hand their own rows over as [OrchestraReceiveOption]s:
/// the type carries exactly the facts a picker row needs — the coin,
/// the chain, and the artwork for each — and the caller maps the
/// picked row back to its own table by `chain:assetCode`.
class CoinAssetPickerSheet extends StatefulWidget {
  /// One entry per coin, widest reach first.
  final List<CoinAssetGroup> groups;

  /// The sheet's own heading and the line under it, because what the
  /// question means differs by direction even though its shape does
  /// not.
  final String title;
  final String subtitle;

  /// Said in the middle of the grid when there is nothing to show. The
  /// caller owns the wording: a catalogue still loading is not the same
  /// as a catalogue with nothing to offer.
  final String emptyLabel;

  /// Open straight on this coin's networks (the pending-asset deep
  /// link hands one over).
  final String? initialAssetCode;

  /// `chain:assetCode` id of the currently active pick, if any — its
  /// coin and its network wear the check.
  final String? selectedOptionId;

  /// Pinned above the grid: the same-rail destination a send already
  /// has (the plain bitcoin send), which is meaningful on send and
  /// meaningless on receive.
  final Widget? pinned;

  /// Which flow this is, for the analytics event only.
  final String flow;

  /// The asset on the person's own rail that every row is moved against
  /// (bitcoin, or the dollar balance on the dollar screens), so each row
  /// can be checked against the runtime policy's swap gates before it is
  /// offered. Rows the policy withdraws are not shown, and the sheet says
  /// why once.
  final String otherLegAsset;

  /// True on the receive pickers: a row served by a reusable deposit
  /// address also needs `crypto.deposit`, the gate the backend asks of
  /// every deposit address it mints. Sends leave it false.
  final bool depositAddress;

  final ValueChanged<OrchestraReceiveOption> onPicked;

  const CoinAssetPickerSheet({
    super.key,
    required this.groups,
    required this.title,
    required this.subtitle,
    required this.emptyLabel,
    required this.flow,
    required this.onPicked,
    this.initialAssetCode,
    this.selectedOptionId,
    this.pinned,
    this.otherLegAsset = 'BTC',
    this.depositAddress = false,
  });

  @override
  State<CoinAssetPickerSheet> createState() => _CoinAssetPickerSheetState();
}

class _CoinAssetPickerSheetState extends State<CoinAssetPickerSheet> {
  /// Null is the coin grid; set is that coin's networks.
  String? _openGroupKey;

  /// [CoinAssetPickerSheet.groups] minus the networks the runtime policy
  /// withdraws for this region, regrouped so a coin left with no network
  /// disappears with them; and the reason the first hidden row gave.
  ({List<CoinAssetGroup> groups, String? hiddenReason}) _offered() {
    final policy = RuntimeCapabilitiesService.instance;
    final groups = <CoinAssetGroup>[];
    String? reason;
    for (final group in widget.groups) {
      final result = orchestraOptionsOfferedUnderPolicy(group.options, policy,
          otherLegAsset: widget.otherLegAsset,
          depositAddress: widget.depositAddress);
      reason ??= result.hiddenReason;
      if (result.offered.isEmpty) continue;
      groups.add(result.offered.length == group.options.length
          ? group
          : CoinAssetGroup(
              key: group.key,
              displayName: group.displayName,
              displaySymbol: group.displaySymbol,
              options: result.offered,
            ));
    }
    return (groups: groups, hiddenReason: reason);
  }

  @override
  void initState() {
    super.initState();
    final wanted = widget.initialAssetCode?.trim().toUpperCase();
    if (wanted == null || wanted.isEmpty) return;
    for (final group in widget.groups) {
      if (group.key == wanted ||
          group.options.any((o) => o.assetCode.toUpperCase() == wanted)) {
        if (!group.isSingleNetwork) _openGroupKey = group.key;
        return;
      }
    }
  }

  CoinAssetGroup? get _openGroup {
    final key = _openGroupKey;
    if (key == null) return null;
    for (final group in _offered().groups) {
      if (group.key == key) return group;
    }
    return null;
  }

  void _pickGroup(CoinAssetGroup group) {
    // The receive line's event keeps its name: it has history behind
    // it. Every other direction shares one event and says which it is.
    TrackingService.track(
      widget.flow == 'receive'
          ? 'receive_also_accepts_coin_picked'
          : 'coin_picker_coin_picked',
      params: {
        'flow': widget.flow,
        'asset': group.assetCode,
        'networks': group.options.length,
      },
    );
    // One network is not a question worth asking.
    if (group.isSingleNetwork) {
      widget.onPicked(group.options.first);
      return;
    }
    setState(() => _openGroupKey = group.key);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final offered = _offered();
    final group = _openGroup;
    final selected = widget.selectedOptionId;
    final pinned = widget.pinned;
    final hiddenReason = offered.hiddenReason;

    return AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: AppDecorations.dragHandle(context)),
            SizedBox(height: 14.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (group != null) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: _SheetBackButton(
                      onTap: () => setState(() => _openGroupKey = null),
                    ),
                  ),
                  SizedBox(width: 10.w),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group?.displayName ?? widget.title,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        group == null
                            ? widget.subtitle
                            : l10n.receivePickNetwork,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (group == null && hiddenReason != null) ...[
                        SizedBox(height: 6.h),
                        // Some coins are not offered here: the policy's
                        // own words for why, said once above the grid.
                        Text(
                          hiddenReason,
                          style: TextStyle(
                            color: c.textTertiary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                KuteCloseButton(
                  size: 36,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            if (group == null && pinned != null) ...[
              pinned,
              SizedBox(height: 14.h),
            ],
            Expanded(
              child: group == null
                  ? CoinAssetGrid(
                      groups: offered.groups,
                      emptyLabel: widget.emptyLabel,
                      selectedKey: _selectedGroupKey(),
                      markBuilder: (g, size) =>
                          AssetIcon(assetCode: g.assetCode, size: size),
                      onPick: _pickGroup,
                    )
                  // Never more than a dozen rows, so no lazy list is
                  // needed; every row is still its own widget.
                  : SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: PickerGroupedList(
                        children: [
                          for (final option in group.options)
                            PickerRow(
                              leading: ChainAvatarIcon(
                                chainId: option.chain,
                                label: option.chainDisplayName,
                                iconUrl: option.chainIconUrl,
                                size: 40,
                              ),
                              title: option.chainDisplayName,
                              // A row that takes one payment and
                              // expires behaves differently enough to
                              // say so before the tap, not after it.
                              subtitle: coinNetworkRowNote(option, l10n),
                              selected: '${option.chain}:${option.assetCode}' ==
                                  selected,
                              onTap: () => widget.onPicked(option),
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

  /// The grid cell to check: the coin the active pick belongs to.
  String? _selectedGroupKey() {
    final selected = widget.selectedOptionId;
    if (selected == null) return null;
    for (final group in widget.groups) {
      for (final option in group.options) {
        if ('${option.chain}:${option.assetCode}' == selected) return group.key;
      }
    }
    return null;
  }
}

/// The back arrow on the sheet's network pane. Its own class so it
/// reads the live theme.
class _SheetBackButton extends StatelessWidget {
  const _SheetBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.back,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            width: 36.sp,
            height: 36.sp,
            decoration: BoxDecoration(
              color: c.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(Icons.arrow_back_rounded,
                size: 18.sp, color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// The quiet line that opens [CoinAssetPickerSheet]: the words, a few
/// coin marks and a count of the rest.
///
/// It is deliberately NOT a mode button and NOT a card with a slogan.
/// A door labelled "get paid in any coin" or "swap" asks a person to
/// enter a mode before they can move money. This states a property of
/// the thing already on screen — what this address takes, what this
/// balance can be sent to. Tapping it is how you find out more, not
/// how you switch something on.
class CoinMarksLine extends StatelessWidget {
  const CoinMarksLine({
    super.key,
    required this.label,
    required this.groups,
    required this.moreLabel,
    required this.onTap,
    this.padding,
  });

  /// The statement itself ("Also accepts", "Also sends to").
  final String label;
  final List<CoinAssetGroup> groups;

  /// "+3" for the coins the marks did not fit.
  final String Function(int count) moreLabel;
  final VoidCallback onTap;
  final EdgeInsetsGeometry? padding;

  /// Six marks is what fits beside the words at the narrowest phone
  /// width without any of them shrinking to a smudge.
  static const int _maxMarks = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = groups.take(_maxMarks).toList();
    final rest = groups.length - shown.length;
    return Semantics(
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding:
                padding ?? EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                SizedBox(width: 10.w),
                for (final group in shown) ...[
                  AssetIcon(assetCode: group.assetCode, size: 20.sp),
                  SizedBox(width: 5.w),
                ],
                if (rest > 0) ...[
                  SizedBox(width: 1.w),
                  Text(
                    moreLabel(rest),
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
