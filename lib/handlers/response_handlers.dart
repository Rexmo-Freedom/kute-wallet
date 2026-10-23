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

  /// The typed refusal behind [error], when the call knows one (a policy
  /// denial, the app's own or the backend's), so a caller can show it the
  /// way that refusal is shown everywhere else. Never a raw body.
  final Object? cause;

  Result({
    this.data,
    this.error,
    this.statusCode,
    this.headers,
    this.errorCode,
    this.cause,
  });

  bool get isSuccess => error == null;
  bool get isLoading => data == null && error == null;
}
