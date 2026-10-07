import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:http/http.dart' as http;
import 'package:kute/l10n/l10n.dart' show languageNativeNames;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/sal_chip_templates.dart';

class AdvisorRateLimitedException implements Exception {
  final Duration retryAfter;
  const AdvisorRateLimitedException(this.retryAfter,
      {this.resetAt, this.daily = false});
  final DateTime? resetAt;
  final bool daily;
}

class AdvisorPrivateInputException implements Exception {
  const AdvisorPrivateInputException();
}

class AdvisorUnavailableException implements Exception {
  const AdvisorUnavailableException();
}

/// The Sal contract this build speaks.
const kAdvisorSchemaVersion = '3';

class AdvisorAlreadyAcceptedException implements Exception {
  const AdvisorAlreadyAcceptedException();
}

/// The backend's `error` event: one of its fixed categories
/// (`upstream_unavailable`, `timeout`, `quota_unavailable`), never upstream
/// text. An unknown category reads as `upstream_unavailable`.
class AdvisorServerErrorException extends AdvisorUnavailableException {
  final String category;
  const AdvisorServerErrorException._(this.category);
  factory AdvisorServerErrorException(Object? category) =>
      AdvisorServerErrorException._(const {
        'upstream_unavailable',
        'timeout',
        'quota_unavailable'
      }.contains(category)
          ? category as String
          : 'upstream_unavailable');
}

/// Owns request cancellation separately from StreamSubscription cancellation,
/// so closing a sheet also aborts a request still waiting for response headers.
class AdvisorCancellation {
  bool _cancelled = false;
  void Function()? _close;
  bool get isCancelled => _cancelled;

  void attach(void Function() close) {
    if (_cancelled) {
      close();
    } else {
      _close = close;
    }
  }

  void cancel() {
    _cancelled = true;
    _close?.call();
    _close = null;
  }

  void detach() => _close = null;
}

/// Public request stages, never model reasoning or arbitrary upstream text.
enum AdvisorProgress { preparing, reading, connecting, writing, checking }

class AdvisorStreamEvent {
  final String? text;
  final AdvisorResponse? response;
  final AdvisorProgress? progress;

  /// The verified market block for the market in context, sent before
  /// inference so it can be drawn while the answer is still being written.
  final AdvisorBlock? card;
  const AdvisorStreamEvent.delta(String this.text)
      : response = null,
        progress = null,
        card = null;
  const AdvisorStreamEvent.done(AdvisorResponse this.response)
      : text = null,
        progress = null,
        card = null;
  const AdvisorStreamEvent.status(AdvisorProgress this.progress)
      : text = null,
        response = null,
        card = null;
  const AdvisorStreamEvent.card(AdvisorBlock this.card)
      : text = null,
        response = null,
        progress = null;
}

/// How a question was asked: a chip (with its allowlisted template id) or
/// typed. Never the chip's ranking signals.
@immutable
class AdvisorPrompt {
  final String source;
  final String? template;
  const AdvisorPrompt._(this.source, this.template);
  const AdvisorPrompt.typed() : this._('typed', null);
  const AdvisorPrompt.chip([String? template]) : this._('chip', template);

  /// The analytics `input` as a source: a 'suggested' chip is `chip`,
  /// anything else (a typed question or follow-up) is `typed`.
  factory AdvisorPrompt.fromInput(String input, {String? template}) =>
      input == 'suggested'
          ? AdvisorPrompt.chip(template)
          : const AdvisorPrompt.typed();

  /// A template outside the shared allowlist is dropped, never sent.
  Map<String, String> toJson() => {
        'source': source,
        if (source == 'chip' && kSalChipTemplates.contains(template))
          'template': template!,
      };

  @override
  bool operator ==(Object other) =>
      other is AdvisorPrompt &&
      other.source == source &&
      other.template == template;

  @override
  int get hashCode => Object.hash(source, template);
}

/// Encodes the v3 allowlist. No arbitrary account context, client metadata,
/// analytics identifier or capability manifest can enter this body. [locale]
/// is the app's resolved language (a shipped ISO 639-1 code) and [prompt]
/// how the question was asked; both are optional.
class AdvisorRequest {
  final String query;
  final AdvisorContext? context;
  final List<Map<String, String>> history;
  final String? locale;
  final AdvisorPrompt? prompt;
  const AdvisorRequest({
    required this.query,
    this.context,
    this.history = const [],
    this.locale,
    this.prompt,
  });

  /// A shipped language code, or null.
  static String? requestLocale(String? value) {
    final code = value?.trim().toLowerCase();
    return code != null && languageNativeNames.containsKey(code) ? code : null;
  }

  Future<Map<String, dynamic>> toJson() async {
    if (!await AdvisorInputGuard.isSafe(query)) {
      throw const AdvisorPrivateInputException();
    }
    final safeHistory = <Map<String, String>>[];
    var historyBytes = 0;
    for (final message in history.reversed.take(12)) {
      final role = message['role'];
      final content = message['content'] ?? '';
      if (!const {'user', 'assistant'}.contains(role) ||
          content.isEmpty ||
          content.length > 4000 ||
          !await AdvisorInputGuard.isSafe(content)) {
        continue;
      }
      final bytes = utf8.encode(content).length;
      if (historyBytes + bytes > 12000) break;
      safeHistory.insert(0, {'role': role!, 'content': content});
      historyBytes += bytes;
    }
    final market = context?.toRequestMarket;
    if (market != null && !await AdvisorInputGuard.isSafe(market['id']!)) {
      throw const AdvisorPrivateInputException();
    }
    return {
      'schemaVersion': kAdvisorSchemaVersion,
      'query': query,
      if (market != null) 'market': market,
      if (context?.toRequestEducation != null)
        'education': context!.toRequestEducation,
      if (safeHistory.isNotEmpty) 'history': safeHistory,
      if (requestLocale(locale) != null) 'locale': requestLocale(locale),
      if (prompt != null) 'prompt': prompt!.toJson(),
    };
  }
}

class AdvisorService {
  AdvisorService._();

  static String? get _backend {
    if (!dotenv.isInitialized) return null;
    final value = (dotenv.env['BACKEND'] ?? '').trim();
    return value.isEmpty ? null : value.replaceFirst(RegExp(r'/$'), '');
  }

  static AdvisorTransport? get _transport {
    final backend = _backend;
    // Session authentication stays at Kute's backend. It is not request context.
    final token = AffiliateService.sessionToken;
    if (backend == null || token == null || token.isEmpty) return null;
    return AdvisorTransport(baseUrl: backend, sessionToken: token);
  }

  static Future<bool> aiEnabled() async {
    final policy = RuntimeCapabilitiesService.instance;
    if (policy.snapshot == null) await policy.refresh();
    return policy.allows('ai.ask');
  }

  static Stream<AdvisorStreamEvent> stream({
    required String query,
    AdvisorContext? context,
    List<Map<String, String>> history = const [],
    required AdvisorCancellation cancellation,
    String? locale,
    AdvisorPrompt? prompt,
  }) async* {
    final transport = _transport;
    if (transport == null) throw const AdvisorUnavailableException();
    yield* transport.stream(
      request: AdvisorRequest(
          query: query,
          context: context,
          history: history,
          locale: locale,
          prompt: prompt),
      cancellation: cancellation,
    );
  }

  static Future<AdvisorResponse?> ask({
    required String query,
    AdvisorContext? context,
    List<Map<String, String>> history = const [],
  }) async {
    final cancellation = AdvisorCancellation();
    try {
      await for (final event in stream(
          query: query,
          context: context,
          history: history,
          cancellation: cancellation)) {
        if (event.response != null) return event.response;
      }
    } on AdvisorRateLimitedException {
      rethrow;
    } on AdvisorPrivateInputException {
      rethrow;
    } catch (_) {
      // No request text, URLs, response bodies or auth tokens are logged.
    } finally {
      cancellation.cancel();
    }
    return null;
  }
}

/// HTTP boundary separated from application state so its exact wire format and
/// true streaming behaviour can be verified without reading a user's account.
class AdvisorTransport {
  final String baseUrl;
  final String sessionToken;
  final http.Client Function() clientFactory;

  AdvisorTransport({
    required this.baseUrl,
    required this.sessionToken,
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  static String _questionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $sessionToken',
      };

  Stream<AdvisorStreamEvent> stream({
    required AdvisorRequest request,
    required AdvisorCancellation cancellation,
  }) async* {
    final body = await request.toJson();
    if (cancellation.isCancelled) return;
    final client = clientFactory();
    cancellation.attach(client.close);
    try {
      final device =
          await RuntimeCapabilitiesService.instance.requestContextHeaders();
      if (cancellation.isCancelled) return;
      final outgoing =
          http.Request('POST', Uri.parse('$baseUrl/api/v1/advisor/ask'))
            ..headers.addAll({
              ..._headers,
              ...device,
              'Accept': 'text/event-stream',
              'X-Idempotency-Key': _questionId()
            })
            ..body = jsonEncode(body);
      final response =
          await client.send(outgoing).timeout(const Duration(seconds: 30));
      if (cancellation.isCancelled) return;
      if (response.statusCode == 409) {
        try {
          final body = jsonDecode(await response.stream
              .bytesToString()
              .timeout(const Duration(seconds: 5)));
          if (body is Map && body['error'] == 'ai_request_already_accepted') {
            throw const AdvisorAlreadyAcceptedException();
          }
        } on AdvisorAlreadyAcceptedException {
          rethrow;
        } catch (_) {}
        throw const AdvisorUnavailableException();
      }
      if (response.statusCode == 429) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 600;
        var daily = false;
        DateTime? resetAt;
        try {
          final data = jsonDecode(await response.stream
              .bytesToString()
              .timeout(const Duration(seconds: 5)));
          if (data is Map && data['error'] == 'ai_daily_limit') {
            daily = true;
            resetAt = DateTime.tryParse(data['resetAt']?.toString() ?? '');
          }
        } catch (_) {
          // An older/empty rate-limit body still uses Retry-After.
        }
        throw AdvisorRateLimitedException(
            Duration(seconds: seconds > 0 ? seconds : 600),
            daily: daily,
            resetAt: resetAt);
      }
      if (response.statusCode != 200) {
        // 502/504/503 carry `{error: category}` without an event stream.
        if (const {502, 503, 504}.contains(response.statusCode)) {
          Object? category;
          try {
            final body = jsonDecode(await response.stream
                .bytesToString()
                .timeout(const Duration(seconds: 5)));
            if (body is Map) category = body['error'];
          } catch (_) {}
          throw AdvisorServerErrorException(category);
        }
        throw const AdvisorUnavailableException();
      }
      if (!(response.headers['content-type'] ?? '')
          .contains('text/event-stream')) {
        // Only a validated v3 server response is accepted.
        final json = jsonDecode(await response.stream
            .bytesToString()
            .timeout(const Duration(seconds: 45)));
        if (json is! Map<String, dynamic> ||
            json['schemaVersion'] != kAdvisorSchemaVersion) {
          throw const AdvisorUnavailableException();
        }
        final answer = AdvisorResponse.fromJson(json);
        if (answer.blocks.isEmpty) throw const AdvisorUnavailableException();
        yield AdvisorStreamEvent.done(answer);
        return;
      }
      var completed = false;
      await for (final event in decodeEvents(response.stream)
          .timeout(const Duration(seconds: 60))) {
        if (cancellation.isCancelled) return;
        yield event;
        if (event.response != null) {
          completed = true;
          break;
        }
      }
      if (!completed && !cancellation.isCancelled) {
        throw const AdvisorUnavailableException();
      }
    } finally {
      cancellation.detach();
      client.close();
    }
  }

  static Stream<AdvisorStreamEvent> decodeEvents(
      Stream<List<int>> bytes) async* {
    var eventName = '';
    final data = <String>[];
    var eventCharacters = 0;
    // UTF-8 and line decoders preserve split characters and network packets.
    await for (final line in bytes
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isEmpty) {
          eventName = '';
          continue;
        }
        final json = jsonDecode(data.join('\n'));
        data.clear();
        eventCharacters = 0;
        if (json is! Map<String, dynamic>) {
          throw const AdvisorUnavailableException();
        }
        if (eventName == 'status') {
          final progress = switch (json['phase']) {
            'reading' => AdvisorProgress.reading,
            'connecting' => AdvisorProgress.connecting,
            'checking' => AdvisorProgress.checking,
            _ => null,
          };
          if (progress != null) yield AdvisorStreamEvent.status(progress);
        } else if (eventName == 'card') {
          final raw = json['block'];
          final block = raw is Map
              ? AdvisorBlock.tryParse(Map<String, dynamic>.from(raw))
              : null;
          if (block?.card != null) yield AdvisorStreamEvent.card(block!);
        } else if (eventName == 'delta') {
          final text = json['text'];
          if (text is String && text.isNotEmpty) {
            yield AdvisorStreamEvent.delta(text);
          }
        } else if (eventName == 'done') {
          if (json['schemaVersion'] != kAdvisorSchemaVersion) {
            throw const AdvisorUnavailableException();
          }
          final answer = AdvisorResponse.fromJson(json);
          if (answer.blocks.isEmpty) throw const AdvisorUnavailableException();
          yield AdvisorStreamEvent.done(answer);
          return;
        } else if (eventName == 'error') {
          // Only the category is read: never an untrusted upstream body.
          throw AdvisorServerErrorException(json['category']);
        }
        eventName = '';
      } else if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        var value = line.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        eventCharacters += value.length;
        if (eventCharacters > 256000) throw const AdvisorUnavailableException();
        data.add(value);
      }
    }
  }
}
