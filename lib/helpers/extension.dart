
export 'package:kute/helpers/formatters/currency_formatter.dart';

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

extension DateTimeExtension on DateTime {
  DateTime dateOnly() => DateTime(year, month, day);
}
