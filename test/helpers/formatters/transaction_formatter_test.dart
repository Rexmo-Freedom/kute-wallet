// transaction_formatter.dart functions require WidgetRef (Riverpod),
// so we only test the pure logic pattern used internally.
//
// We also test pure helper functions from common_operation_methods.dart
// (shortenValue, getStatusText, transactionTypeString logic, etc.)
// and formatHistoricalValue from historical_price_provider.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Core sats-extraction logic (mirrors transactionAmount / transactionAmountInFiat)
  // ---------------------------------------------------------------------------
  group('transaction amount extraction logic', () {
    int extractAmount(int received, int sent) {
      if (received == 0 && sent > 0) return sent;
      if (received > 0 && sent == 0) return received;
      return (received - sent).abs();
    }

    test('pure send', () {
      expect(extractAmount(0, 50000), 50000);
    });

    test('pure receive', () {
      expect(extractAmount(30000, 0), 30000);
    });

    test('both directions uses abs diff', () {
      expect(extractAmount(100000, 60000), 40000);
    });

    test('both directions reversed', () {
      expect(extractAmount(60000, 100000), 40000);
    });

    test('both zero', () {
      expect(extractAmount(0, 0), 0);
    });

    test('equal amounts', () {
      expect(extractAmount(50000, 50000), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases for sats extraction with large / boundary values
  // ---------------------------------------------------------------------------
  group('transaction amount extraction - edge cases', () {
    int extractAmount(int received, int sent) {
      if (received == 0 && sent > 0) return sent;
      if (received > 0 && sent == 0) return received;
      return (received - sent).abs();
    }

    test('1 sat send', () {
      expect(extractAmount(0, 1), 1);
    });

    test('1 sat receive', () {
      expect(extractAmount(1, 0), 1);
    });

    test('maximum supply (21M BTC in sats) send', () {
      const maxSats = 2100000000000000; // 21M BTC
      expect(extractAmount(0, maxSats), maxSats);
    });

    test('maximum supply receive', () {
      const maxSats = 2100000000000000;
      expect(extractAmount(maxSats, 0), maxSats);
    });

    test('large values both directions', () {
      expect(extractAmount(1000000000000, 999999999999), 1);
    });

    test('sent exceeds received by 1 sat', () {
      expect(extractAmount(99999, 100000), 1);
    });

    test('received exceeds sent by 1 sat', () {
      expect(extractAmount(100000, 99999), 1);
    });

    test('very large equal amounts yield zero', () {
      const amount = 100000000000;
      expect(extractAmount(amount, amount), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Transaction type detection logic
  // (mirrors transactionTypeString and transactionIsReceived)
  // ---------------------------------------------------------------------------
  group('transaction type detection logic', () {
    // sent.toSat() - received.toSat() > 0 => "sent", else "received"
    String typeString(int sent, int received) {
      return (sent - received > 0) ? 'sent' : 'received';
    }

    bool isReceived(int sent, int received) {
      return (sent - received) <= 0;
    }

    test('more sent than received is sent', () {
      expect(typeString(100000, 50000), 'sent');
      expect(isReceived(100000, 50000), false);
    });

    test('more received than sent is received', () {
      expect(typeString(50000, 100000), 'received');
      expect(isReceived(50000, 100000), true);
    });

    test('equal amounts is received (edge case)', () {
      expect(typeString(50000, 50000), 'received');
      expect(isReceived(50000, 50000), true);
    });

    test('zero sent zero received is received', () {
      expect(typeString(0, 0), 'received');
      expect(isReceived(0, 0), true);
    });

    test('only received is received', () {
      expect(typeString(0, 100000), 'received');
      expect(isReceived(0, 100000), true);
    });

    test('only sent is sent', () {
      expect(typeString(100000, 0), 'sent');
      expect(isReceived(100000, 0), false);
    });

    test('1 sat difference sent', () {
      expect(typeString(50001, 50000), 'sent');
    });

    test('1 sat difference received', () {
      expect(typeString(50000, 50001), 'received');
    });
  });

  // ---------------------------------------------------------------------------
  // shortenValue logic (from common_operation_methods.dart / transactions_builder)
  // ---------------------------------------------------------------------------
  group('shortenValue logic', () {
    String shortenValue(String value, [int start = 8, int end = 8]) {
      if (value.length <= start + end) {
        return value;
      }
      return '${value.substring(0, start)}...${value.substring(value.length - end)}';
    }

    test('long txid is shortened', () {
      const txid = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
      final result = shortenValue(txid);
      expect(result, 'a1b2c3d4...e9f0a1b2');
      expect(result.length, 19); // 8 + 3 + 8
    });

    test('exactly 16 chars is NOT shortened', () {
      const value = '1234567890123456';
      expect(shortenValue(value), value);
    });

    test('less than 16 chars is NOT shortened', () {
      const value = '12345';
      expect(shortenValue(value), value);
    });

    test('17 chars IS shortened', () {
      const value = '12345678901234567';
      final result = shortenValue(value);
      expect(result, '12345678...01234567');
    });

    test('empty string returns empty', () {
      expect(shortenValue(''), '');
    });

    test('custom start and end', () {
      const value = 'abcdefghijklmnopqrstuvwxyz';
      final result = shortenValue(value, 4, 4);
      expect(result, 'abcd...wxyz');
    });

    test('custom start/end where length equals start+end', () {
      const value = '12345678';
      expect(shortenValue(value, 4, 4), value);
    });
  });

  // ---------------------------------------------------------------------------
  // capitalize logic (StringExtension from extension.dart)
  // ---------------------------------------------------------------------------
  group('capitalize logic', () {
    String capitalize(String s) {
      if (s.isEmpty) return s;
      return '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';
    }

    test('lowercase word', () {
      expect(capitalize('completed'), 'Completed');
    });

    test('uppercase word', () {
      expect(capitalize('PENDING'), 'Pending');
    });

    test('mixed case', () {
      expect(capitalize('fAiLeD'), 'Failed');
    });

    test('single character', () {
      expect(capitalize('a'), 'A');
    });

    test('single uppercase character', () {
      expect(capitalize('A'), 'A');
    });

    test('empty string', () {
      expect(capitalize(''), '');
    });

    test('already capitalized', () {
      expect(capitalize('Completed'), 'Completed');
    });

    test('numeric string', () {
      expect(capitalize('123abc'), '123abc');
    });
  });

  // ---------------------------------------------------------------------------
  // getStatusText logic (from transactions_builder.dart)
  // Mirrors: status.name.capitalize()
  // ---------------------------------------------------------------------------
  group('getStatusText logic', () {
    String getStatusText(String statusName) {
      if (statusName.isEmpty) return statusName;
      return '${statusName[0].toUpperCase()}${statusName.substring(1).toLowerCase()}';
    }

    test('completed status', () {
      expect(getStatusText('completed'), 'Completed');
    });

    test('failed status', () {
      expect(getStatusText('failed'), 'Failed');
    });

    test('pending status', () {
      expect(getStatusText('pending'), 'Pending');
    });
  });

  // ---------------------------------------------------------------------------
  // Timestamp formatting logic
  // (mirrors _formatTimestamp in bitcoin_transactions_details_screen.dart)
  // ---------------------------------------------------------------------------
  group('timestamp formatting logic', () {
    String formatTimestamp(int? timestamp) {
      if (timestamp == null || timestamp == 0) return 'Pending';
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return DateFormat('d MMM yyyy, HH:mm').format(date);
    }

    test('null timestamp returns Pending', () {
      expect(formatTimestamp(null), 'Pending');
    });

    test('zero timestamp returns Pending', () {
      expect(formatTimestamp(0), 'Pending');
    });

    test('valid timestamp formats correctly', () {
      // 1704067200 = 2024-01-01 00:00:00 UTC
      final result = formatTimestamp(1704067200);
      // The exact output depends on locale, but should contain year and month
      expect(result, contains('2024'));
      expect(result, contains('Jan'));
    });

    test('Bitcoin genesis block timestamp', () {
      // 1231006505 = 2009-01-03 18:15:05 UTC
      final result = formatTimestamp(1231006505);
      expect(result, contains('2009'));
      expect(result, contains('Jan'));
    });

    test('recent timestamp formats correctly', () {
      // 1700000000 = approx 2023-11-14
      final result = formatTimestamp(1700000000);
      expect(result, contains('2023'));
      expect(result, contains('Nov'));
    });

    test('negative timestamp does not crash', () {
      // Negative timestamps represent dates before epoch
      final result = formatTimestamp(-1);
      // Should still produce a formatted date (before 1970)
      expect(result, isNotEmpty);
      expect(result, isNot('Pending'));
    });
  });

  // ---------------------------------------------------------------------------
  // formatHistoricalValue logic
  // (from historical_price_provider.dart — pure function)
  // ---------------------------------------------------------------------------
  group('formatHistoricalValue logic', () {
    String formatHistoricalValue({
      required int amountSats,
      required double btcPriceUsd,
      required String currencySymbol,
    }) {
      final btcAmount = amountSats / 100000000.0;
      final fiatValue = btcAmount * btcPriceUsd;
      return '$currencySymbol${fiatValue.toStringAsFixed(2)}';
    }

    test('1 BTC at 50000 USD', () {
      final result = formatHistoricalValue(
        amountSats: 100000000,
        btcPriceUsd: 50000.0,
        currencySymbol: '\$',
      );
      expect(result, '\$50000.00');
    });

    test('0 sats', () {
      final result = formatHistoricalValue(
        amountSats: 0,
        btcPriceUsd: 50000.0,
        currencySymbol: '\$',
      );
      expect(result, '\$0.00');
    });

    test('1 sat at 100000 USD', () {
      final result = formatHistoricalValue(
        amountSats: 1,
        btcPriceUsd: 100000.0,
        currencySymbol: '\$',
      );
      // 1 sat = 0.00000001 BTC * 100000 = 0.001
      expect(result, '\$0.00');
    });

    test('half BTC', () {
      final result = formatHistoricalValue(
        amountSats: 50000000,
        btcPriceUsd: 60000.0,
        currencySymbol: '\$',
      );
      expect(result, '\$30000.00');
    });

    test('EUR symbol', () {
      final result = formatHistoricalValue(
        amountSats: 100000000,
        btcPriceUsd: 45000.0,
        currencySymbol: '\u20ac',
      );
      expect(result, '\u20ac45000.00');
    });

    test('empty currency symbol', () {
      final result = formatHistoricalValue(
        amountSats: 100000000,
        btcPriceUsd: 50000.0,
        currencySymbol: '',
      );
      expect(result, '50000.00');
    });

    test('very small amount', () {
      final result = formatHistoricalValue(
        amountSats: 100,
        btcPriceUsd: 50000.0,
        currencySymbol: '\$',
      );
      // 100 sats = 0.000001 BTC * 50000 = 0.05
      expect(result, '\$0.05');
    });

    test('zero price', () {
      final result = formatHistoricalValue(
        amountSats: 100000000,
        btcPriceUsd: 0.0,
        currencySymbol: '\$',
      );
      expect(result, '\$0.00');
    });

    test('very high price', () {
      final result = formatHistoricalValue(
        amountSats: 100000000,
        btcPriceUsd: 1000000.0,
        currencySymbol: '\$',
      );
      expect(result, '\$1000000.00');
    });

    test('fractional sats amount at high price', () {
      final result = formatHistoricalValue(
        amountSats: 12345678,
        btcPriceUsd: 67890.12,
        currencySymbol: '\$',
      );
      // 0.12345678 BTC * 67890.12 = ~8382.54
      final expected = (12345678 / 100000000.0 * 67890.12).toStringAsFixed(2);
      expect(result, '\$$expected');
    });
  });

  // ---------------------------------------------------------------------------
  // Transaction direction icon logic
  // (mirrors transactionTypeIcon from transactions_builder.dart)
  // ---------------------------------------------------------------------------
  group('transaction direction detection', () {
    // sent - received > 0 => outgoing (sent), else incoming (received)
    String direction(int sent, int received) {
      return (sent - received > 0) ? 'outgoing' : 'incoming';
    }

    test('outgoing when sent > received', () {
      expect(direction(200000, 100000), 'outgoing');
    });

    test('incoming when received > sent', () {
      expect(direction(100000, 200000), 'incoming');
    });

    test('incoming when equal (self-transfer edge case)', () {
      expect(direction(100000, 100000), 'incoming');
    });

    test('incoming when both zero', () {
      expect(direction(0, 0), 'incoming');
    });

    test('outgoing with only sent', () {
      expect(direction(50000, 0), 'outgoing');
    });

    test('incoming with only received', () {
      expect(direction(0, 50000), 'incoming');
    });
  });

  // ---------------------------------------------------------------------------
  // BaseTransaction.amount computation logic for different transaction types
  // ---------------------------------------------------------------------------
  group('BitcoinTransaction amount logic', () {
    // Mirrors: (received.toSat() - sent.toSat()).abs()
    int bitcoinAmount(int received, int sent) {
      return (received - sent).abs();
    }

    test('standard receive', () {
      expect(bitcoinAmount(100000, 0), 100000);
    });

    test('standard send', () {
      expect(bitcoinAmount(0, 100000), 100000);
    });

    test('change transaction', () {
      // sent 200k, received 150k change => net 50k
      expect(bitcoinAmount(150000, 200000), 50000);
    });

    test('self-transfer (consolidation)', () {
      // All outputs back to self (minus fee accounted elsewhere)
      expect(bitcoinAmount(99900, 100000), 100);
    });
  });

  // ---------------------------------------------------------------------------
  // BitcoinTransaction type logic
  // ---------------------------------------------------------------------------
  group('BitcoinTransaction type logic', () {
    // Mirrors: received > sent ? received : sent
    String bitcoinTxType(int received, int sent) {
      return received > sent ? 'received' : 'sent';
    }

    test('receive transaction', () {
      expect(bitcoinTxType(100000, 0), 'received');
    });

    test('send transaction', () {
      expect(bitcoinTxType(0, 100000), 'sent');
    });

    test('change: received < sent => sent', () {
      expect(bitcoinTxType(50000, 100000), 'sent');
    });

    test('change: received > sent => received', () {
      expect(bitcoinTxType(100000, 50000), 'received');
    });

    test('equal amounts => sent (not strictly greater)', () {
      expect(bitcoinTxType(50000, 50000), 'sent');
    });
  });

  // ---------------------------------------------------------------------------
  // Fee rate calculation logic
  // (mirrors _buildTechnicalCard in bitcoin_transactions_details_screen)
  // ---------------------------------------------------------------------------
  group('fee rate calculation logic', () {
    String feeRateString(int feeSats, int vSize) {
      if (vSize <= 0 || feeSats <= 0) return 'N/A';
      final rate = feeSats.toDouble() / vSize;
      return '${rate.toStringAsFixed(1)} sat/vB';
    }

    test('standard fee rate', () {
      // 1000 sats fee, 200 vbytes = 5.0 sat/vB
      expect(feeRateString(1000, 200), '5.0 sat/vB');
    });

    test('zero fee', () {
      expect(feeRateString(0, 200), 'N/A');
    });

    test('zero vSize', () {
      expect(feeRateString(1000, 0), 'N/A');
    });

    test('both zero', () {
      expect(feeRateString(0, 0), 'N/A');
    });

    test('high fee rate', () {
      expect(feeRateString(50000, 140), '357.1 sat/vB');
    });

    test('fractional rate', () {
      // 3 sats / 2 vbytes = 1.5
      expect(feeRateString(3, 2), '1.5 sat/vB');
    });

    test('1 sat/vB', () {
      expect(feeRateString(140, 140), '1.0 sat/vB');
    });
  });

  // ---------------------------------------------------------------------------
  // Fiat amount string composition logic
  // (mirrors transactionAmountInFiat return: '$formattedFiat $currency')
  // ---------------------------------------------------------------------------
  group('fiat amount string composition', () {
    String composeFiatString(String formattedFiat, String currency) {
      return '$formattedFiat $currency';
    }

    test('USD format', () {
      expect(composeFiatString('\$50.25', 'USD'), '\$50.25 USD');
    });

    test('EUR format', () {
      expect(composeFiatString('\u20ac45.00', 'EUR'), '\u20ac45.00 EUR');
    });

    test('BRL format', () {
      expect(composeFiatString('R\$250.00', 'BRL'), 'R\$250.00 BRL');
    });

    test('empty formatted fiat', () {
      expect(composeFiatString('', 'USD'), ' USD');
    });

    test('empty currency', () {
      expect(composeFiatString('\$50.25', ''), '\$50.25 ');
    });
  });

  // ---------------------------------------------------------------------------
  // SideShift transaction status filtering logic
  // (mirrors homeTransactionsSorted filter)
  // ---------------------------------------------------------------------------
  group('SideShift transaction visibility logic', () {
    bool isVisibleOnHome(String status) {
      return status != 'wait' && status != 'expired' && status != 'overdue';
    }

    test('success is visible', () {
      expect(isVisibleOnHome('success'), true);
    });

    test('settling is visible', () {
      expect(isVisibleOnHome('settling'), true);
    });

    test('wait is hidden', () {
      expect(isVisibleOnHome('wait'), false);
    });

    test('expired is hidden', () {
      expect(isVisibleOnHome('expired'), false);
    });

    test('overdue is hidden', () {
      expect(isVisibleOnHome('overdue'), false);
    });

    test('empty status is visible', () {
      expect(isVisibleOnHome(''), true);
    });
  });

  // ---------------------------------------------------------------------------
  // DateOnly extension logic
  // ---------------------------------------------------------------------------
  group('dateOnly logic', () {
    DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

    test('strips time component', () {
      final dt = DateTime(2024, 6, 15, 14, 30, 45);
      final result = dateOnly(dt);
      expect(result, DateTime(2024, 6, 15));
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });

    test('midnight stays the same', () {
      final dt = DateTime(2024, 1, 1);
      expect(dateOnly(dt), dt);
    });

    test('end of day', () {
      final dt = DateTime(2024, 12, 31, 23, 59, 59);
      final result = dateOnly(dt);
      expect(result, DateTime(2024, 12, 31));
    });
  });

  // ---------------------------------------------------------------------------
  // MathUtils.truncateToDecimalPlaces logic
  // ---------------------------------------------------------------------------
  group('truncateToDecimalPlaces logic', () {
    double truncate(num number, int places) {
      final factor = _pow10(places);
      return ((number * factor).floor()) / factor;
    }

    test('truncate 1.23456 to 2 places', () {
      expect(truncate(1.23456, 2), 1.23);
    });

    test('truncate 1.999 to 2 places (not rounded)', () {
      expect(truncate(1.999, 2), 1.99);
    });

    test('truncate to 0 places', () {
      expect(truncate(1.999, 0), 1.0);
    });

    test('truncate negative number', () {
      // floor of -1.23 * 100 = floor(-123.0) = -123 => -1.23
      expect(truncate(-1.23, 2), -1.23);
    });

    test('truncate zero', () {
      expect(truncate(0, 5), 0.0);
    });

    test('truncate to 8 decimal places (BTC precision)', () {
      expect(truncate(0.123456789, 8), 0.12345678);
    });
  });

  // ---------------------------------------------------------------------------
  // Polymarket transaction type logic
  // ---------------------------------------------------------------------------
  group('Polymarket transaction type logic', () {
    String polymarketType(String activityType, String? side) {
      switch (activityType) {
        case 'deposit':
          return 'received';
        case 'withdraw':
          return 'sent';
        case 'trade':
          return side?.toUpperCase() == 'SELL' ? 'sent' : 'received';
        case 'redeem':
          return 'received';
        default:
          return 'received';
      }
    }

    test('deposit is received', () {
      expect(polymarketType('deposit', null), 'received');
    });

    test('withdraw is sent', () {
      expect(polymarketType('withdraw', null), 'sent');
    });

    test('trade sell is sent', () {
      expect(polymarketType('trade', 'SELL'), 'sent');
    });

    test('trade sell lowercase', () {
      expect(polymarketType('trade', 'sell'), 'sent');
    });

    test('trade buy is received', () {
      expect(polymarketType('trade', 'BUY'), 'received');
    });

    test('trade null side is received', () {
      expect(polymarketType('trade', null), 'received');
    });

    test('redeem is received', () {
      expect(polymarketType('redeem', null), 'received');
    });

    test('unknown type is received', () {
      expect(polymarketType('unknown', null), 'received');
    });
  });

  // ---------------------------------------------------------------------------
  // Polymarket USDC amount conversion logic
  // ---------------------------------------------------------------------------
  group('Polymarket USDC base unit conversion', () {
    int toBaseUnits(double usdcAmount) {
      return (usdcAmount * 1e6).toInt();
    }

    test('1 USDC', () {
      expect(toBaseUnits(1.0), 1000000);
    });

    test('0 USDC', () {
      expect(toBaseUnits(0.0), 0);
    });

    test('fractional USDC', () {
      expect(toBaseUnits(0.5), 500000);
    });

    test('large USDC amount', () {
      expect(toBaseUnits(1000.0), 1000000000);
    });
  });

  // ---------------------------------------------------------------------------
  // Outlogic transaction properties logic
  // ---------------------------------------------------------------------------
  group('Outlogic transaction logic', () {
    bool isBuy(String fromAsset) {
      return fromAsset != 'BTC' && fromAsset != 'L-BTC';
    }

    test('USD to BTC is buy', () {
      expect(isBuy('USD'), true);
    });

    test('EUR to BTC is buy', () {
      expect(isBuy('EUR'), true);
    });

    test('BTC to USD is not buy (sell)', () {
      expect(isBuy('BTC'), false);
    });

    test('L-BTC to USD is not buy (sell)', () {
      expect(isBuy('L-BTC'), false);
    });

    test('empty string is buy', () {
      expect(isBuy(''), true);
    });
  });

  // ---------------------------------------------------------------------------
  // Transaction sorting logic
  // ---------------------------------------------------------------------------
  group('transaction sorting by timestamp', () {
    test('sorts newest first', () {
      final timestamps = [
        DateTime(2024, 1, 1),
        DateTime(2024, 6, 15),
        DateTime(2024, 3, 10),
      ];
      timestamps.sort((a, b) => b.compareTo(a));
      expect(timestamps[0], DateTime(2024, 6, 15));
      expect(timestamps[1], DateTime(2024, 3, 10));
      expect(timestamps[2], DateTime(2024, 1, 1));
    });

    test('identical timestamps remain stable', () {
      final dt = DateTime(2024, 1, 1);
      final timestamps = [dt, dt, dt];
      timestamps.sort((a, b) => b.compareTo(a));
      expect(timestamps.length, 3);
    });

    test('single element', () {
      final timestamps = [DateTime(2024, 1, 1)];
      timestamps.sort((a, b) => b.compareTo(a));
      expect(timestamps.length, 1);
    });

    test('empty list', () {
      final timestamps = <DateTime>[];
      timestamps.sort((a, b) => b.compareTo(a));
      expect(timestamps, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // MempoolAddressTransaction type logic
  // ---------------------------------------------------------------------------
  group('MempoolAddressTransaction type logic', () {
    String mempoolTxType(int balanceChange) {
      return balanceChange >= 0 ? 'received' : 'sent';
    }

    test('positive balance change is received', () {
      expect(mempoolTxType(50000), 'received');
    });

    test('negative balance change is sent', () {
      expect(mempoolTxType(-50000), 'sent');
    });

    test('zero balance change is received', () {
      expect(mempoolTxType(0), 'received');
    });
  });
}

int _pow10(int exponent) {
  int result = 1;
  for (int i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
