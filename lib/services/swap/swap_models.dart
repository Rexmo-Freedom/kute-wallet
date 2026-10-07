/// Lightweight swap quote model used by the UI.
/// Orchestra is the only exchange provider.
library;

class SwapQuote {
  final String provider;
  final String fromCcy;
  final String toCcy;
  final String rexmoFrom;
  final String rexmoTo;
  final String networkFrom;
  final String networkTo;
  final double fromAmount;
  final double toAmount;
  final double fromMin;
  final double fromMax;
  final List<String> errors;
  final DateTime expiresAt;

  SwapQuote({
    required this.provider,
    required this.fromCcy,
    required this.toCcy,
    required this.rexmoFrom,
    required this.rexmoTo,
    required this.networkFrom,
    required this.networkTo,
    required this.fromAmount,
    required this.toAmount,
    this.fromMin = 0,
    this.fromMax = 0,
    this.errors = const [],
    DateTime? expiresAt,
  }) : expiresAt = expiresAt ?? DateTime.now().add(const Duration(minutes: 10));

  bool get isValid => errors.isEmpty && toAmount > 0;

  double get rate => fromAmount > 0 ? toAmount / fromAmount : 0;
}
