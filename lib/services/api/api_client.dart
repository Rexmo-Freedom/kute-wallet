import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ApiResponse<T> {
  final T? data;
  final String? error;
  final int statusCode;

  ApiResponse({this.data, this.error, required this.statusCode});

  bool get isSuccess => error == null && data != null;
}

class ApiClient {
  final String baseUrl;
  final http.Client _http;
  final Map<String, String> _defaultHeaders;

  ApiClient(this.baseUrl, {http.Client? client, Map<String, String>? headers})
      : _http = client ?? http.Client(),
        _defaultHeaders = {'Content-Type': 'application/json', ...?headers};

  /// Headers for a GET. In a browser a GET carrying `Content-Type:
  /// application/json` is not a "simple" request, so the browser first sends
  /// an OPTIONS preflight, and public Esplora hosts (blockstream.info) answer
  /// that with a 404: the GET is then blocked by CORS. A GET has no body, so
  /// the web build leaves the default Content-Type off; a header the caller
  /// passes for this request is still sent.
  Map<String, String> _getHeaders(Map<String, String>? headers) {
    if (!kIsWeb) return {..._defaultHeaders, ...?headers};
    return {
      for (final e in _defaultHeaders.entries)
        if (e.key.toLowerCase() != 'content-type') e.key: e.value,
      ...?headers,
    };
  }

  Future<ApiResponse<T>> get<T>(
    String path,
    T Function(dynamic) parser, {
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: _getHeaders(headers),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse(data: parser(jsonDecode(res.body)), statusCode: res.statusCode);
      }
      return ApiResponse(error: res.body, statusCode: res.statusCode);
    } catch (e) {
      return ApiResponse(error: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<String>> getRaw(
    String path, {
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: _getHeaders(headers),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse(data: res.body, statusCode: res.statusCode);
      }
      return ApiResponse(error: res.body, statusCode: res.statusCode);
    } catch (e) {
      return ApiResponse(error: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<T>> post<T>(
    String path,
    dynamic body,
    T Function(dynamic) parser, {
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {..._defaultHeaders, ...?headers},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse(data: parser(jsonDecode(res.body)), statusCode: res.statusCode);
      }
      return ApiResponse(error: res.body, statusCode: res.statusCode);
    } catch (e) {
      return ApiResponse(error: e.toString(), statusCode: 0);
    }
  }

  Future<ApiResponse<T>> patch<T>(
    String path,
    dynamic body,
    T Function(dynamic) parser, {
    Map<String, String>? headers,
  }) async {
    try {
      final res = await _http
          .patch(
            Uri.parse('$baseUrl$path'),
            headers: {..._defaultHeaders, ...?headers},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse(data: parser(jsonDecode(res.body)), statusCode: res.statusCode);
      }
      return ApiResponse(error: res.body, statusCode: res.statusCode);
    } catch (e) {
      return ApiResponse(error: e.toString(), statusCode: 0);
    }
  }
}
