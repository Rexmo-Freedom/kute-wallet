import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/onchain_types.dart' as bdk;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

export 'package:kute/helpers/formatters/transaction_formatter.dart';

const Color fintechGreen = Color(0xFF27D17F);
const Color fintechRed = Color(0xFFFF5252);
const Color cardColor = Color(0xFF1C1C1E);
const Color borderColor = Color(0x14FFFFFF);

Widget buildCircularIcon(IconData icon, Color color, {Color? backgroundColor}) {
  return Builder(
    builder: (context) {
      final bgColor = backgroundColor ?? context.colors.surfaceLight;
      return Container(
        width: 44.sp,
        height: 44.sp,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          color: bgColor,
        ),
        child: Center(
          child: Icon(
            icon,
            color: color,
            size: 20.sp,
          ),
        ),
      );
    },
  );
}

/// Strip a `bitcoin:` URI scheme and any BIP21 `?query` so only the bare
/// on-chain address remains. This is the address we display in the
/// "Send to" field AND the one fed to the BDK fee calc / TransactionBuilder
/// — a scheme-prefixed `bitcoin:bc1…?amount=…` is rejected as an invalid
/// address, which broke fee calculation. No-op for an already-bare address.
String stripBitcoinAddress(String input) {
  var s = input.trim();
  s = s.replaceFirst(RegExp(r'^bitcoin:(//)?', caseSensitive: false), '');
  final q = s.indexOf('?');
  if (q != -1) s = s.substring(0, q);
  return s.trim();
}

String confirmationStatus(BuildContext context, bdk.TxDetails transaction, WidgetRef ref) {
  final cp = transaction.chainPosition;
  if (cp is bdk.ConfirmedChainPosition) {
    return context.l10n.confirmed;
  } else {
    return context.l10n.unconfirmed;
  }
}

Widget transactionTypeIcon(bdk.TxDetails? transaction) {
  if (transaction == null) {
    return buildCircularIcon(Icons.south_west_rounded, fintechGreen);
  }

  if (transaction.sent.toSat() - transaction.received.toSat() > 0) {
    return buildCircularIcon(Icons.north_east_rounded, fintechRed);
  } else {
    return buildCircularIcon(Icons.south_west_rounded, fintechGreen);
  }
}

bool transactionIsReceived(bdk.TxDetails transaction, WidgetRef ref) {
  return transaction.sent.toSat() - transaction.received.toSat() <= 0;
}

String sparkTransactionAmountInFiat(SparkTransaction transaction, WidgetRef ref) {
  // `transaction.amountSats` reads through to live SDK details when
  // they're present and falls back to the cached primitive on a
  // Hive-hydrated entry — same shape the home row needs whether or
  // not the live sync has populated `details` yet.
  final amountSat = transaction.amountSats;
  final formattedFiat = ref.watch(conversionToFiatProvider(amountSat));

  return formattedFiat;
}

String sparkTransactionAmount(SparkTransaction transaction, WidgetRef ref) {
  final amountSat = transaction.amountSats;
  // `conversionProvider` now embeds the unit suffix itself —
  // appending another `$unit` here would produce "12,345 sats sats".
  return ref.watch(conversionProvider(amountSat));
}
