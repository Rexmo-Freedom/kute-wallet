import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart' show AppLocalizations, l10nForLanguage;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/providers/auth_provider.dart'
    show appLockedProvider, sessionAuthProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/advisor_local_stub.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/tracking_service.dart';

@immutable
class AdvisorTurn {
  final String query;
  final List<AdvisorBlock> blocks;

  /// The verified market block the backend sent ahead of the answer (the
  /// `card` event). It leads the turn from its arrival on and stays when
  /// the answer lands, whether or not [blocks] repeat it (same id).
  final AdvisorBlock? card;
  final String partialText;
  final bool loading;
  final bool includeInHistory;
  final AdvisorProgress progress;

  const AdvisorTurn({
    required this.query,
    this.blocks = const [],
    this.card,
    this.partialText = '',
    this.loading = false,
    this.includeInHistory = false,
    this.progress = AdvisorProgress.preparing,
  });

  /// [blocks] without the leading [card]: matched by block id, or by the
  /// market itself.
  List<AdvisorBlock> get blocksAfterCard {
    final lead = card;
    if (lead == null) return blocks;
    return [
      for (final block in blocks)
        if (block.id != lead.id &&
            (block.card == null || block.card!.key != lead.card?.key))
          block
    ];
  }

  AdvisorTurn answered(List<AdvisorBlock> blocks,
          {bool includeInHistory = true}) =>
      AdvisorTurn(
        query: query,
        blocks: blocks,
        card: card,
        includeInHistory: includeInHistory,
      );

  AdvisorTurn append(String text) => AdvisorTurn(
        query: query,
        card: card,
        partialText: partialText + text,
        loading: true,
        progress: AdvisorProgress.writing,
      );

  AdvisorTurn withProgress(AdvisorProgress value) => AdvisorTurn(
        query: query,
        blocks: blocks,
        card: card,
        partialText: partialText,
        loading: loading,
        includeInHistory: includeInHistory,
        progress: value,
      );

  AdvisorTurn withCard(AdvisorBlock value) => AdvisorTurn(
        query: query,
        blocks: blocks,
        card: value,
        partialText: partialText,
        loading: loading,
        includeInHistory: includeInHistory,
        progress: progress,
      );
}

@immutable
class AdvisorSessionState {
  final List<AdvisorTurn> turns;
  final AdvisorContext? context;
  const AdvisorSessionState({this.turns = const [], this.context});
  bool get isActive => turns.isNotEmpty;
}

typedef AdvisorStreamRequest = Stream<AdvisorStreamEvent> Function({
  required String query,
  AdvisorContext? context,
  List<Map<String, String>> history,
  required AdvisorCancellation cancellation,
  String? locale,
  AdvisorPrompt? prompt,
});

/// Injectable transport, with no dependency on balance, positions or analytics.
final advisorStreamRequestProvider =
    Provider<AdvisorStreamRequest>((ref) => AdvisorService.stream);

/// Reports the outcome of one Sal turn exactly once: an answer or a failure
/// category, never question/answer text.
class _TurnTelemetry {
  _TurnTelemetry(this.surface);
  final String? surface;
  final _watch = Stopwatch()..start();
  var _reported = false;

  void answered(AdvisorResponse response) {
    if (_reported) return;
    _reported = true;
    TrackingService.salAnswerReceived(
      surface: surface,
      blockCount: response.blocks.length,
      marketCards: response.blocks.where((b) => b.card != null).length,
      latencyMs: _watch.elapsedMilliseconds,
    );
  }

  void failed(String category) {
    if (_reported) return;
    _reported = true;
    TrackingService.salAnswerFailed(
      surface: surface,
      category: category,
      latencyMs: _watch.elapsedMilliseconds,
    );
  }
}

class AdvisorSessionNotifier extends Notifier<AdvisorSessionState> {
  /// Copy for the info blocks Kute writes itself, in the app language.
  AppLocalizations get _l10n =>
      l10nForLanguage(ref.read(settingsProvider).language);

  var _generation = 0;
  var _disposed = false;
  // Analytics-only surface for a context-less conversation; see [ask].
  String? _analyticsSurface;
  _TurnTelemetry? _telemetry;
  AdvisorCancellation? _cancellation;
  StreamSubscription<AdvisorStreamEvent>? _subscription;
  Completer<void>? _completion;

  @override
  AdvisorSessionState build() {
    // A local lock signal clears chat without reading any wallet or identity.
    // Account reset disposes the entire ProviderContainer as well.
    ref.listen(appLockedProvider, (_, locked) {
      if (locked) clear();
    });
    // The auto-relock after backgrounding drops the session instead
    // of raising the overlay; clear the chat on that path too.
    ref.listen(sessionAuthProvider, (_, auth) {
      if (auth == null) clear();
    });
    ref.onDispose(() {
      _disposed = true;
      _stopRequest();
    });
    return const AdvisorSessionState();
  }

  /// Names the surface for the Sal events of a conversation that has no
  /// screen context (the unified search asks with none). Analytics only:
  /// it never reaches the request, and [clear] drops it.
  void setAnalyticsSurface(String surface) => _analyticsSurface = surface;

  /// [input] is the analytics origin of the question:
  /// 'typed' | 'suggested'; the request carries it as the prompt source
  /// (a 'suggested' chip is source 'chip', anything else 'typed'). [template] and
  /// [chipIndex] describe a chip. [locale] is the screen's resolved
  /// language; without one the app language is used.
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    final q = query.trim();
    if (q.isEmpty || _disposed || ref.read(appLockedProvider)) return;
    if (context != null && state.turns.isNotEmpty && context != state.context) {
      clear();
    }
    cancel();
    final generation = _generation;
    final activeContext = context ?? state.context;
    final surface = activeContext?.surface ?? _analyticsSurface;
    bool safe;
    try {
      safe = await AdvisorInputGuard.isSafe(q);
    } catch (_) {
      // Fail closed if the bundled privacy dictionary could not be read.
      safe = false;
    }
    if (!_current(generation)) return;
    if (!safe) {
      TrackingService.salAnswerFailed(
          surface: surface, category: 'private_input_local');
      state = AdvisorSessionState(context: activeContext, turns: [
        ...state.turns,
        AdvisorTurn(query: _l10n.salPrivateDetailsRemoved, blocks: [
          AdvisorBlock(
            id: 'private_input',
            kind: AdvisorBlockKind.info,
            markdown: _l10n.salPrivateInputBlocked,
          )
        ]),
      ]);
      return;
    }
    final history = _history();
    final index = state.turns.length;
    state = AdvisorSessionState(context: activeContext, turns: [
      ...state.turns,
      AdvisorTurn(query: q, loading: true),
    ]);
    final venue = activeContext?.marketVenue;
    TrackingService.salQuestionAsked(
      input: input,
      surface: surface,
      queryLength: q.length,
      turnIndex: index,
      venue: const {'polymarket', 'hyperliquid'}.contains(venue) ? venue : null,
      template: template,
      chipIndex: chipIndex,
    );
    final prompt = AdvisorPrompt.fromInput(input, template: template);
    final requestLocale = locale ??
        l10nForLanguage(ref.read(settingsProvider).language).localeName;
    final telemetry = _TurnTelemetry(surface);
    _telemetry = telemetry;
    final cancellation = AdvisorCancellation();
    final completion = Completer<void>();
    _cancellation = cancellation;
    _completion = completion;
    var receivedDone = false;

    /// True only when [response] replaced this request's loading turn.
    bool completeWith(AdvisorResponse response,
        {bool includeInHistory = true}) {
      if (!_current(generation)) return false;
      final turns = [...state.turns];
      if (index >= turns.length || !turns[index].loading) return false;
      turns[index] = turns[index]
          .answered(response.blocks, includeInHistory: includeInHistory);
      state = AdvisorSessionState(turns: turns, context: activeContext);
      return true;
    }

    void failWith(String category, AdvisorResponse response) {
      if (completeWith(response, includeInHistory: false)) {
        telemetry.failed(category);
      }
    }

    void finish() {
      if (!completion.isCompleted) completion.complete();
      if (_current(generation)) {
        _cancellation = null;
        _subscription = null;
        _completion = null;
        _telemetry = null;
      }
    }

    void fail(Object error, {String? category}) {
      if (!_current(generation)) {
        finish();
        return;
      }
      if (error is AdvisorRateLimitedException) {
        failWith(error.daily ? 'quota_daily' : 'rate_limited',
            _rateLimitedResponse(error));
      } else if (error is AdvisorAlreadyAcceptedException) {
        failWith(
            'already_accepted',
            AdvisorResponse(blocks: [
              AdvisorBlock(
                id: 'already_accepted',
                kind: AdvisorBlockKind.info,
                markdown: _l10n.salAlreadyAccepted,
              )
            ]));
      } else if (error is AdvisorPrivateInputException) {
        failWith(
            'private_input',
            AdvisorResponse(blocks: [
              AdvisorBlock(
                id: 'private_input',
                kind: AdvisorBlockKind.info,
                markdown: _l10n.salPrivateInputBlocked,
              )
            ]));
      } else {
        // The backend's error categories (timeout, upstream_unavailable and
        // quota_unavailable: the question could not be recorded, so it was
        // not used) and any transport failure read as Sal unavailable.
        failWith(category ?? 'unavailable',
            AdvisorLocalStub.respond(q, activeContext, _l10n));
      }
      cancellation.cancel();
      finish();
    }

    try {
      _subscription = ref
          .read(advisorStreamRequestProvider)(
            query: q,
            context: activeContext,
            history: history,
            cancellation: cancellation,
            locale: requestLocale,
            prompt: prompt,
          )
          .listen(
              (event) {
                if (!_current(generation) || receivedDone) return;
                if (event.response != null) {
                  receivedDone = true;
                  final response = event.response!;
                  // The final response only; progress and text chunks never
                  // report. The generation check above keeps a stale or
                  // replaced turn from reporting.
                  if (completeWith(response)) telemetry.answered(response);
                } else if (event.card != null && index < state.turns.length) {
                  final turns = [...state.turns];
                  if (!turns[index].loading) return;
                  turns[index] = turns[index].withCard(event.card!);
                  state =
                      AdvisorSessionState(turns: turns, context: activeContext);
                } else if (event.progress != null &&
                    index < state.turns.length) {
                  final turns = [...state.turns];
                  if (!turns[index].loading) return;
                  turns[index] = turns[index].withProgress(event.progress!);
                  state =
                      AdvisorSessionState(turns: turns, context: activeContext);
                } else if (event.text != null && index < state.turns.length) {
                  final turns = [...state.turns];
                  if (!turns[index].loading) return;
                  if (turns[index].partialText.length + event.text!.length >
                      60000) {
                    fail(const AdvisorUnavailableException(),
                        category: 'too_long');
                    return;
                  }
                  turns[index] = turns[index].append(event.text!);
                  state =
                      AdvisorSessionState(turns: turns, context: activeContext);
                }
              },
              onError: (Object error) => fail(error),
              onDone: () {
                if (!receivedDone && _current(generation)) {
                  failWith('no_response',
                      AdvisorLocalStub.respond(q, activeContext, _l10n));
                }
                finish();
              },
              cancelOnError: true);
    } catch (error) {
      fail(error);
    }
    await completion.future;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _stopRequest() {
    _generation++;
    _telemetry = null;
    _cancellation?.cancel();
    _cancellation = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) completion.complete();
  }

  /// Stop generation when a sheet closes. An interrupted response is never
  /// included in a subsequent model request or allowed to replace a newer turn.
  void cancel() {
    final telemetry = _telemetry;
    _stopRequest();
    if (_disposed || !state.turns.any((turn) => turn.loading)) return;
    telemetry?.failed('cancelled');
    state = AdvisorSessionState(context: state.context, turns: [
      for (final turn in state.turns)
        if (!turn.loading)
          turn
        else
          turn.answered([
            AdvisorBlock(
                id: 'interrupted',
                kind: AdvisorBlockKind.info,
                markdown: turn.partialText.isEmpty
                    ? _l10n.salResponseStopped
                    : '${turn.partialText}\n\n${_l10n.salResponseStoppedEarly}'),
          ], includeInHistory: false),
    ]);
  }

  void clear() {
    _stopRequest();
    _analyticsSurface = null;
    if (!_disposed) state = const AdvisorSessionState();
  }

  List<Map<String, String>> _history() {
    final answered = state.turns
        .where((turn) => !turn.loading && turn.includeInHistory)
        .toList();
    final recent =
        answered.length > 6 ? answered.sublist(answered.length - 6) : answered;
    return [
      for (final turn in recent) ...[
        {'role': 'user', 'content': turn.query},
        {
          'role': 'assistant',
          'content': turn.blocks
              .map((block) => block.markdown.trim())
              .where((text) => text.isNotEmpty)
              .join('\n\n')
        },
      ],
    ];
  }

  AdvisorResponse _rateLimitedResponse(AdvisorRateLimitedException error) {
    if (error.daily) {
      final local = error.resetAt?.toLocal();
      final reset = local == null
          ? _l10n.salResetNextDaily
          : _l10n.salResetAt(
              '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
              '${local.day}',
              '${local.month}');
      return AdvisorResponse(blocks: [
        AdvisorBlock(
          id: 'daily_limit',
          kind: AdvisorBlockKind.info,
          markdown: _l10n.salDailyLimit(reset),
        )
      ]);
    }
    final minutes = error.retryAfter.inMinutes;
    final when = minutes >= 2
        ? _l10n.salRetryInMinutes(minutes)
        : minutes == 1
            ? _l10n.salRetryInAMinute
            : _l10n.salRetryInAMoment;
    return AdvisorResponse(blocks: [
      AdvisorBlock(
        id: 'rate_limited',
        kind: AdvisorBlockKind.info,
        markdown: _l10n.salRateLimited(when),
      )
    ]);
  }
}

final advisorSessionProvider =
    NotifierProvider<AdvisorSessionNotifier, AdvisorSessionState>(
        AdvisorSessionNotifier.new);
final aiEnabledProvider = FutureProvider<bool>((ref) async {
  ref.watch(runtimeCapabilitiesProvider);
  return AdvisorService.aiEnabled();
});
