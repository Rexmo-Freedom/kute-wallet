class Result<T> {
  final T? data;
  final String? error;

  /// HTTP status of the response, or null when no response arrived
  /// (timeout, transport error) or the call is not an HTTP call.
  final int? statusCode;

  /// Response headers, when the call recorded them.
  final Map<String, String>? headers;

  /// Machine-readable provider error code (e.g. `amount_too_small`), when
  /// the call parsed one. Never a message body.
  final String? errorCode;

  Result({
    this.data,
    this.error,
    this.statusCode,
    this.headers,
    this.errorCode,
  });

  bool get isSuccess => error == null;
  bool get isLoading => data == null && error == null;
}
