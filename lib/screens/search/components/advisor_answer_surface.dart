// lib/screens/search/components/advisor_answer_surface.dart
//
// Renders the assistant conversation inside Sal's sheet and the search
// sheet: the user's question, the market card the backend sends ahead of
// the answer, live request progress and streaming text, then the answer as
// plain text on the sheet with verified market cards, sources and actions.
// Native action callbacks delegate confirmation and navigation to the
// current screen.
//
// Every piece is one the app already draws elsewhere: the venue tabs' own
// market cards, the review plate and its lines (USD flows) for a market the
// venue does not list, the transaction sheet's detail rows and nerd data
// toggle, AppButton for actions and the flow note for the one disclaimer.
// Nothing here is a web view: the backend's typed card is drawn natively.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/models/kute_state.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show
        hyperliquidBrowseUniverseProvider,
        hyperliquidPerpMarketsProvider,
        hyperliquidSpotMarketsProvider;
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider;
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/investment_market_browser.dart'
    show PredictionBrowseCard;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/kute_mascot.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart'
    show UsdFlowNote, UsdReviewLine, UsdReviewPlate;
import 'package:url_launcher/url_launcher.dart';

import 'advisor_presentation.dart';

import 'package:kute/services/advisor/advisor_service.dart'
    show AdvisorProgress;
import 'package:kute/services/advisor/action_dispatcher.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart'
    show polymarketEventOffered;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

typedef AdvisorActionCallback = void Function(
  String actionId,
  Map<String, dynamic> params,
);

/// The quiet section label the slips use ("Margin mode"), shared by the
/// conversation's own labels so every surface reads the same.
TextStyle advisorSectionLabelStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
    );

/// Sal's conversation: each question and its answer, then the one
/// disclaimer. No next-question rows under an answer (owner decision
/// October 2026: "Ask Sal next" took too much room): a follow-up is typed in
/// the composer.
class AdvisorAnswerSurface extends ConsumerStatefulWidget {
  final AdvisorActionCallback? onAction;
  const AdvisorAnswerSurface({
    super.key,
    this.onAction,
  });

  @override
  ConsumerState<AdvisorAnswerSurface> createState() =>
      _AdvisorAnswerSurfaceState();
}

class _AdvisorAnswerSurfaceState extends ConsumerState<AdvisorAnswerSurface> {
  final _scroll = ScrollController();

  /// The reader is at (or near) the bottom: growing text keeps them there.
  /// A drag away from the bottom lets go; scrolling back picks it up again.
  bool _pinned = true;

  /// The finger is on the list. Nothing moves the list under it: a jump
  /// would end the drag (the scroll position goes idle), which is what made
  /// the sheet snap back to the bottom on every attempt to read upwards.
  bool _dragging = false;
  bool _followScheduled = false;
  int _turnCount = 0;

  /// The content height last seen; only growth (a new question, streaming
  /// text, the answer easing in) is followed, never the reader's own scroll.
  double? _maxExtent;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the bottom at most once per frame, only while pinned and only
  /// with no finger on the list. The answer grows through animated sizes,
  /// so following the scroll metrics (not the provider) keeps the newest
  /// line in view frame by frame.
  void _follow() {
    if (_followScheduled || !_pinned || _dragging) return;
    _followScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followScheduled = false;
      if (!mounted || !_pinned || _dragging || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        _scroll.jumpTo(position.maxScrollExtent);
      }
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _dragging = true;
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        _dragging = true;
        _pinned = notification.metrics.extentAfter < 100;
      }
    } else if (notification is ScrollEndNotification) {
      _dragging = false;
      _pinned = notification.metrics.extentAfter < 100;
    }
    return false;
  }

  /// The list's metrics change on every scrolled frame as well as when the
  /// content grows; only growth brings the bottom back into view.
  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;
    final max = notification.metrics.maxScrollExtent;
    final last = _maxExtent;
    _maxExtent = max;
    if (last == null || max > last) _follow();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(advisorSessionProvider);
    final children = <Widget>[];
    for (final (index, turn) in s.turns.indexed) {
      if (children.isNotEmpty) children.add(SizedBox(height: 24.h));
      children.add(_UserQuestion(text: turn.query));
      children.add(SizedBox(height: 12.h));
      // The market in context leads the turn as soon as the backend sends
      // it, before the answer is written. It sits outside the cross-fade
      // below, so the answer landing never redraws it, and the answer's own
      // copy of the same market is left out.
      final lead = turn.card;
      children.add(SheetAnimatedSize(
        key: ValueKey('turn-$index-card'),
        child: lead == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: AdvisorBlockCard(block: lead, onAction: widget.onAction),
              ),
      ));
      children.add(
        // Progress and the streaming text give way to the finished answer
        // with one cross-fade, and the height eases between the two.
        ArrivalSwitcher(
          key: ValueKey('turn-$index'),
          state: turn.loading ? 'streaming' : 'done',
          child: turn.loading
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SalProgress(progress: turn.progress),
                    if (turn.partialText.isNotEmpty) ...[
                      SizedBox(height: 10.h),
                      SheetAnimatedSize(
                        child: _StreamingText(text: _cleanMd(turn.partialText)),
                      ),
                    ],
                  ],
                )
              : AdvisorBlocks(
                  blocks: turn.blocksAfterCard, onAction: widget.onAction),
        ),
      );
    }
    if (s.turns.isNotEmpty) {
      // The one disclaimer, under the answers.
      children
        ..add(SizedBox(height: 24.h))
        ..add(UsdFlowNote(lines: [context.l10n.salDisclaimer]));
    }
    // A new question (typed or a chip) brings the
    // bottom back into view: the question lengthens the list, and that
    // growth is followed.
    if (s.turns.length > _turnCount) _pinned = true;
    _turnCount = s.turns.length;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: ListView(
          controller: _scroll,
          // Manual (not onDrag) — scrolling the chat must NOT dismiss the
          // keyboard.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 16.h),
          children: children,
        ),
      ),
    );
  }
}

/// The question as asked: plain, right-aligned, in the primary colour, on
/// the sheet itself (no bubble, never the accent).
class _UserQuestion extends StatelessWidget {
  final String text;
  const _UserQuestion({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 0.82.sw),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 16.5.sp,
            fontWeight: FontWeight.w600,
            height: 1.35,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

TextStyle _answerBodyStyle(BuildContext context) => TextStyle(
      color: context.colors.textPrimary,
      fontSize: 16.5.sp,
      fontWeight: FontWeight.w500,
      height: 1.45,
      letterSpacing: -0.2,
    );

/// Sal's text as it streams: what was already shown stays put and only the
/// newly arrived words fade in (the list fade's 170 ms), so the answer
/// reads as one growing paragraph instead of popping on every delta.
class _StreamingText extends StatefulWidget {
  final String text;
  const _StreamingText({required this.text});

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kSelectionFadeDuration,
    value: 1,
  );

  /// The part already settled; the rest of [widget.text] is fading in.
  String _settled = '';

  @override
  void initState() {
    super.initState();
    _start('');
  }

  // Reduce Motion draws the whole text at once (see build).

  @override
  void didUpdateWidget(_StreamingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _start(oldWidget.text);
  }

  void _start(String previous) {
    // Only an append fades; any other change (the cleanup of a marker)
    // simply redraws.
    _settled = widget.text.startsWith(previous) ? previous : widget.text;
    if (_settled == widget.text) {
      _fade.value = 1;
    } else {
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _answerBodyStyle(context);
    final still = kuteReduceMotion(context);
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        final tail = still ? '' : widget.text.substring(_settled.length);
        final settled = still ? widget.text : _settled;
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: settled),
            if (tail.isNotEmpty)
              TextSpan(
                text: tail,
                style: style.copyWith(
                  color: style.color!.withValues(
                      alpha: style.color!.a *
                          Curves.easeOut.transform(_fade.value)),
                ),
              ),
          ]),
          style: style,
        );
      },
    );
  }
}

/// A finished answer: plain text on the sheet. The block title in the slip
/// sections' 17sp and the body in the reading size.
class _AnswerText extends StatelessWidget {
  final String text;
  final String? title;
  const _AnswerText({required this.text, this.title});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null && title!.trim().isNotEmpty) ...[
          Text(
            title!,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              height: 1.3,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: 6.h),
        ],
        if (text.isNotEmpty) Text(text, style: _answerBodyStyle(context)),
      ],
    );
  }
}

/// Status comes from request events, not a timer or the model's private
/// trace: one line, the loading dog and what Sal is doing.
class _SalProgress extends StatelessWidget {
  const _SalProgress({required this.progress});

  final AdvisorProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final label = switch (progress) {
      AdvisorProgress.preparing => l10n.salProgressPreparing,
      AdvisorProgress.reading => l10n.salProgressReading,
      AdvisorProgress.connecting => l10n.salProgressConnecting,
      AdvisorProgress.writing => l10n.salProgressWriting,
      AdvisorProgress.checking => l10n.salProgressChecking,
    };
    return Semantics(
      liveRegion: true,
      label: context.l10n.salSemanticsLabel(label),
      child: ExcludeSemantics(
        child: Row(
          children: [
            KuteMascot(state: KuteState.loading, size: 28.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: AnimatedSwitcher(
                duration:
                    kuteMotion(context, const Duration(milliseconds: 220)),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  label,
                  key: ValueKey(progress),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Group public activity and available products without filling empty sections
/// with unrelated markets. Reused by the compact Ask Sal sheet and full chat.
class AdvisorBlocks extends StatelessWidget {
  final List<AdvisorBlock> blocks;
  final AdvisorActionCallback? onAction;
  const AdvisorBlocks({super.key, required this.blocks, this.onAction});

  @override
  Widget build(BuildContext context) {
    // Section keys come from the backend; the headers are product words.
    final sections = <String, String>{
      'activity': context.l10n.salSectionPublicActivity,
      'stocks': context.l10n.investingStocks,
      'crypto_perps': context.l10n.searchCryptoMarkets,
      'predictions': context.l10n.predictions,
    };
    final grouped = <String, List<AdvisorBlock>>{'': []};
    for (final block in blocks) {
      final section = sections.containsKey(block.section) ? block.section! : '';
      (grouped[section] ??= []).add(block);
    }
    final children = <Widget>[];
    for (final section in ['', ...sections.keys]) {
      final list = grouped[section];
      if (list == null || list.isEmpty) continue;
      if (section.isNotEmpty) {
        children.add(Padding(
          padding:
              EdgeInsets.only(top: children.isEmpty ? 4.h : 24.h, bottom: 2.h),
          child: Semantics(
            header: true,
            child: Text(sections[section]!,
                style: advisorSectionLabelStyle(context)),
          ),
        ));
      }
      for (final block in list) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 12.h),
          child: AdvisorBlockCard(block: block, onAction: onAction),
        ));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

const _stayOpenActions = {'open_market_by_slug', 'open_hl_market'};

void _dispatchAction(
  BuildContext context,
  String actionId,
  Map<String, dynamic> params,
  AdvisorActionCallback? onAction, {
  required String card,
  String? section,
}) {
  // One tap event for the compact sheet and full chat alike; the result of
  // the action is reported where it resolves (dispatcher / sheet).
  TrackingService.salCardTapped(
    action: AdvisorActionDispatcher.analyticsAction(actionId),
    card: card,
    venue: switch (actionId) {
      'open_market_by_slug' => 'polymarket',
      'open_hl_market' => 'hyperliquid',
      _ => null,
    },
    section: section,
  );
  if (onAction != null) {
    onAction(actionId, params);
    return;
  }
  final container = ProviderScope.containerOf(context, listen: false);
  if (_stayOpenActions.contains(actionId)) {
    AdvisorActionDispatcher.dispatch(context, container, actionId, params);
    return;
  }
  final nav = Navigator.of(context, rootNavigator: true);
  final rootCtx = nav.context;
  nav.pop();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (rootCtx.mounted) {
      AdvisorActionDispatcher.dispatch(rootCtx, container, actionId, params);
    }
  });
}

String _cleanMd(String md) => md
    .replaceAll('**', '')
    .replaceAll('__', '')
    .replaceAll(RegExp(r'\s*[—–]\s*'), ', ')
    .replaceAll(RegExp(r'\s+--\s+'), ', ')
    .replaceAll(RegExp(r'  +'), ' ')
    .trim();

/// One answer block: its text, the dates and sources it rests on, and the
/// actions it offers; or, for a market block, the market's card.
class AdvisorBlockCard extends StatelessWidget {
  final AdvisorBlock block;
  final AdvisorActionCallback? onAction;
  const AdvisorBlockCard({super.key, required this.block, this.onAction});

  @override
  Widget build(BuildContext context) {
    final card = block.card;
    if (card != null) {
      // A market the policy withdraws in this region is not offered, even
      // when the backend answered with it: the card simply does not render.
      final gate = advisorMarketGateCapability(card, block.section);
      if (gate != null && !RuntimeCapabilitiesService.instance.allows(gate)) {
        return const SizedBox.shrink();
      }
      return _VenueMarketCard(
          block: block,
          action: advisorMarketAction(block, context.l10n),
          onAction: onAction);
    }
    const navigation = {
      'open_money_tab',
      'open_predictions_tab',
      'open_trading_tab',
      'open_support',
      'open_settings',
    };
    final actions = block.actions
        .where((action) {
          if (action.params.isNotEmpty) return false;
          if (navigation.contains(action.actionId)) return true;
          return onAction != null &&
              {
                'switch_to_limit',
                'open_leverage_settings',
              }.contains(action.actionId);
        })
        .take(3)
        .toList();
    final hasEvidence = block.transactionDate != null ||
        block.disclosureDate != null ||
        block.sources.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (block.markdown.trim().isNotEmpty || block.title != null)
          _AnswerText(title: block.title, text: _cleanMd(block.markdown)),
        if (hasEvidence) ...[
          SizedBox(height: 10.h),
          _Evidence(block: block),
        ],
        for (final action in actions) ...[
          SizedBox(height: 10.h),
          _ActionButton(
            button: action,
            onAction: onAction,
            card: 'action_button',
            section: block.section,
          ),
        ],
      ],
    );
  }
}

/// A market the answer names, drawn with the venue tab's own card: the
/// Predictions list's [PredictionBrowseCard] for a Polymarket event, the
/// Investing list's [HlMarketCard] for a Hyperliquid market. The card is the
/// door: a tap opens the market detail the way the tabs do (through the
/// verified open action, so `sal_card_tapped` reports it as before). While
/// the venue's market loads the card's silhouette holds its place; a market
/// the venue no longer lists (unknown, closed, delisted) falls back to a
/// compact plate of the backend's typed card.
class _VenueMarketCard extends ConsumerWidget {
  final AdvisorBlock block;
  final AdvisorActionButton? action;
  final AdvisorActionCallback? onAction;
  const _VenueMarketCard({required this.block, this.action, this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = block.card!;
    final action = this.action;
    final (String, Widget) shown = action == null
        ? ('plate', _MarketPlate(block: block))
        : card.venue == 'polymarket'
            ? _prediction(context, ref, action)
            : card.venue == 'hyperliquid'
                ? _investing(context, ref, action)
                : ('plate', _MarketPlate(block: block));
    final (state, view) = shown;
    final stocks = block.section == 'stocks' && state == 'card';
    return Column(
      key: ValueKey('advisor-market-${card.venue}-${card.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArrivalSwitcher(state: state, child: RepaintBoundary(child: view)),
        if (stocks)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(context.l10n.salStockLinkedDisclaimer,
                style: _quietStyle(context)),
          ),
      ],
    );
  }

  void _open(BuildContext context, AdvisorActionButton a) =>
      _dispatchAction(context, a.actionId, a.params, onAction,
          card: 'market', section: block.section);

  (String, Widget) _prediction(
      BuildContext context, WidgetRef ref, AdvisorActionButton a) {
    final slug = a.params['slug'] as String;
    final async = ref.watch(polymarketEventDetailsProvider(slug));
    if (async.isLoading && !async.hasValue) {
      return ('loading', const _PredictionCardSkeleton());
    }
    final event = async.valueOrNull;
    if (event == null || event.slug != slug || event.closed || !event.active) {
      return ('plate', _MarketPlate(block: block));
    }
    if (!polymarketEventOffered(event, RuntimeCapabilitiesService.instance)) {
      return ('hidden', const SizedBox.shrink());
    }
    return (
      'card',
      PredictionBrowseCard(
        event: event,
        followLiveGame: true,
        onTap: () {
          HapticFeedback.lightImpact();
          _open(context, a);
        },
      ),
    );
  }

  (String, Widget) _investing(
      BuildContext context, WidgetRef ref, AdvisorActionButton a) {
    final coin = (a.params['coin'] as String).toUpperCase();
    final kind = switch (a.params['kind']) {
      'spot' => HlMarketKind.spot,
      'perp' => HlMarketKind.perp,
      _ => null,
    };
    final universe = ref.watch(hyperliquidBrowseUniverseProvider);
    HlMarket? found;
    for (final m in universe.valueOrNull ?? const <HlMarket>[]) {
      if (m.wireCoin.toUpperCase() == coin &&
          (kind == null || m.kind == kind)) {
        found = m;
        break;
      }
    }
    if (found == null) {
      // Until the full lists land the universe paints the main dex (or the
      // last lists seen) alone: a builder-dex market is not missing yet.
      final pending = universe.isLoading ||
          (universe.hasValue &&
              (ref.watch(hyperliquidPerpMarketsProvider).isLoading ||
                  ref.watch(hyperliquidSpotMarketsProvider).isLoading));
      return pending
          ? ('loading', const _InvestingCardSkeleton())
          : ('plate', _MarketPlate(block: block));
    }
    return (
      'card',
      HlMarketCard(market: found, onTap: () => _open(context, a))
    );
  }
}

/// The Predictions list card's silhouette, its height (as search shows it).
class _PredictionCardSkeleton extends StatelessWidget {
  const _PredictionCardSkeleton();

  @override
  Widget build(BuildContext context) =>
      SkeletonCardList(count: 1, height: 140.h, padding: EdgeInsets.zero);
}

/// The Investing card's one-row silhouette: logo, name over caption, price.
class _InvestingCardSkeleton extends StatelessWidget {
  const _InvestingCardSkeleton();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        child: SkeletonCard(
          height: 72.h,
          radius: AppRadius.lg,
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: [
              SkeletonCircle(36.w),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(110.w, 14.h),
                    SizedBox(height: 6.h),
                    SkeletonBar(70.w, 12.h),
                  ],
                ),
              ),
              SkeletonBar(64.w, 14.h),
            ],
          ),
        ),
      );
}

/// A market the venue could not resolve, on the review plate, drawn from
/// the backend's typed card: its logo and name, the mark price with its
/// 24h change the way the trade receipt leads with its figure, then review
/// lines (a prediction's game state, outcomes by their own names with the
/// day's move, and close; a perpetual's funding, open interest, volume and
/// leverage limit) and the rules behind a toggle. No door: the venue does
/// not list it.
class _MarketPlate extends StatelessWidget {
  final AdvisorBlock block;
  const _MarketPlate({required this.block});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = block.card!;
    final prediction = card.venue == 'polymarket';
    final price = advisorCardPrice(card);
    final rows = advisorCardRows(card, context.l10n);
    final rules = card.resolutionRules ?? '';
    return UsdReviewPlate(children: [
      Padding(
        padding: EdgeInsets.only(top: 10.h, bottom: 4.h),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _MarketArtwork(card: card, title: block.title),
          SizedBox(width: 12.w),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(block.title ?? card.slug ?? card.id,
                  style: AppTextStyles.settingsTitle(context)
                      .copyWith(height: 1.3)),
              SizedBox(height: 2.h),
              Text(advisorInstrumentLabel(card, block.section, context.l10n),
                  style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1)),
            ],
          )),
        ]),
      ),
      if (price != null)
        Padding(
          padding: EdgeInsets.only(top: 12.h, bottom: 6.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.salMarkPrice,
                  style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
              SizedBox(height: 5.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(price.price,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 30.sp,
                            height: 1.15,
                            letterSpacing: -.8,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                  if (price.change != null) ...[
                    SizedBox(width: 8.w),
                    Text(price.change!,
                        style: TextStyle(
                            color: _moveColor(c, price.up),
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ],
                ],
              ),
            ],
          ),
        ),
      if (rows.isNotEmpty)
        _FactRows(rows: rows, initialLimit: prediction ? 5 : 4),
      if (rules.isNotEmpty)
        SheetNerdDataSection(
          title: context.l10n.salResolutionRules,
          onToggle: (open) {
            if (open) _trackSalAnswerExpanded('resolution_rules');
          },
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text(rules, style: _detailTextStyle(context)),
            ),
          ],
        ),
      if (block.section == 'stocks')
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Text(context.l10n.salStockLinkedDisclaimer,
              style: _quietStyle(context)),
        ),
      if (card.asOf != null)
        Padding(
          padding: EdgeInsets.only(top: 4.h, bottom: 8.h),
          child: Text(
              context.l10n
                  .salAsOf(advisorDisplayDate(card.asOf!, includeTime: true)),
              style: _quietStyle(context)),
        ),
    ]);
  }
}

/// Up / down in the markets' colours, neutral when flat or unknown.
Color _moveColor(AppColorsExtension c, bool? up) => up == null
    ? c.textSecondary
    : up
        ? AppColors.marketUp
        : AppColors.marketDown;

TextStyle _quietStyle(BuildContext context) => TextStyle(
      color: context.colors.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );

TextStyle _detailTextStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 13.sp,
      height: 1.6,
      fontWeight: FontWeight.w400,
    );

class _MarketArtwork extends StatelessWidget {
  final AdvisorCard card;
  final String? title;
  const _MarketArtwork({required this.card, this.title});

  @override
  Widget build(BuildContext context) {
    final image = advisorMarketImageUrl(card);
    final size = 40.w;
    if (card.venue == 'hyperliquid') {
      return ClipOval(
        child: HlCoinIcon(
            coin: advisorMarketSymbol(card, title),
            wireCoin: card.id,
            iconUrl: image,
            category: card.category,
            size: 40),
      );
    }
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: context.colors.surfaceLight,
          borderRadius: BorderRadius.circular(11.r)),
      alignment: Alignment.center,
      child: Icon(Icons.bar_chart_rounded,
          color: context.colors.textSecondary, size: 22.sp),
    );
    return image == null
        ? fallback
        : PolyCrestImage(
            url: image, size: size, radius: 11.r, fallback: fallback);
  }
}

/// Review lines for a card's figures; past [initialLimit] the rest wait
/// behind the nerd data toggle ("Show 3 more").
class _FactRows extends StatelessWidget {
  final List<AdvisorPlateRow> rows;
  final int initialLimit;
  const _FactRows({required this.rows, required this.initialLimit});

  @override
  Widget build(BuildContext context) {
    final shown = rows.take(initialLimit).toList();
    final rest = rows.skip(initialLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in shown) _FactLine(row: row),
        if (rest.isNotEmpty)
          SheetNerdDataSection(
            title: context.l10n.salShowMore(rest.length),
            expandedTitle: context.l10n.salShowLess,
            onToggle: (open) {
              if (open) _trackSalAnswerExpanded('more_facts');
            },
            children: [for (final row in rest) _FactLine(row: row)],
          ),
      ],
    );
  }
}

/// One figure: a review line when label and value share a row, the label
/// over its value when either is long. A move (an outcome's day) follows
/// the value in the markets' up / down colour.
class _FactLine extends StatelessWidget {
  final AdvisorPlateRow row;
  const _FactLine({required this.row});
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = row.label;
    final value = row.value;
    final move = row.move;
    final figures = const [FontFeature.tabularFigures()];
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = label.length > 24 ||
          value.length > 24 ||
          constraints.maxWidth < 230 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      if (!stacked && move == null) {
        return UsdReviewLine(label: label, value: value);
      }
      final valueText = Text.rich(
        TextSpan(children: [
          TextSpan(text: value),
          if (move != null)
            TextSpan(
              text: '  $move',
              style: TextStyle(
                  color: _moveColor(c, row.up), fontWeight: FontWeight.w600),
            ),
        ]),
        textAlign: stacked ? TextAlign.start : TextAlign.end,
        style: TextStyle(
            color: c.textPrimary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            fontFeatures: figures),
      );
      final labelText = Text(label,
          style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500));
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 9.h),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, SizedBox(height: 3.h), valueText],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelText,
                  SizedBox(width: 16.w),
                  Expanded(child: valueText),
                ],
              ),
      );
    });
  }
}

/// `sal_answer_expanded`: a collapsed part of an answer was opened (never
/// on collapse). [element]: more_facts | resolution_rules.
/// The element kind only — fact labels and text come from the model.
void _trackSalAnswerExpanded(String element) =>
    TrackingService.track('sal_answer_expanded', params: {'element': element});

/// The dates an answer rests on, as quiet lines, and its sources as the
/// transaction sheet's detail rows that open the page.
class _Evidence extends StatelessWidget {
  final AdvisorBlock block;
  const _Evidence({required this.block});

  Future<void> _open(BuildContext context, Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Unsupported links keep the reader in the answer.
    }
    TrackingService.salSourceOpened(opened: opened);
    if (!opened && context.mounted) {
      showMessageSnackBarInfo(
          context: context, message: context.l10n.salCouldNotOpenSource);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = [
      if (block.transactionDate != null)
        context.l10n
            .salTransactionDate(advisorDisplayDate(block.transactionDate!)),
      if (block.disclosureDate != null)
        context.l10n
            .salDisclosedDate(advisorDisplayDate(block.disclosureDate!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final date in dates)
          Padding(
            padding: EdgeInsets.only(top: 3.h),
            child: Text(date, style: _quietStyle(context)),
          ),
        for (final source in block.sources)
          if (advisorSourceUri(source.url) case final Uri uri)
            SheetDetailRow(
              label: context.l10n.salSource,
              value: source.title.isEmpty ? uri.host : source.title,
              trailingIcon: Icons.open_in_new_rounded,
              onTap: () => _open(context, uri),
            ),
      ],
    );
  }
}

/// An action the answer offers: the app's quiet secondary button, full
/// width, one per row.
class _ActionButton extends StatelessWidget {
  final AdvisorActionButton button;
  final AdvisorActionCallback? onAction;

  /// Analytics card kind: 'action_button' (a market's card reports
  /// 'market' itself).
  final String card;
  final String? section;
  const _ActionButton({
    required this.button,
    this.onAction,
    required this.card,
    this.section,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      text: _cleanMd(button.label),
      variant: AppButtonVariant.secondary,
      compact: true,
      onPressed: () => _dispatchAction(
          context, button.actionId, button.params, onAction,
          card: card, section: section),
    );
  }
}

/// The Kute dog at the size a Settings tile holds its glyph.
class SalDogGlyph extends StatelessWidget {
  const SalDogGlyph({super.key});

  @override
  Widget build(BuildContext context) =>
      SvgPicture.asset(kuteDogAsset(context), width: 24.sp, height: 24.sp);
}
