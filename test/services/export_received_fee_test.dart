import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/export/export_aggregation.dart';
import 'package:kute/services/mempool_address_service.dart' as mempool;
import 'package:kute/services/transaction_pdf_export.dart';

// The export's "Fees paid" summed every on-chain row's transaction fee,
// including receives, whose fee the sender paid: receiving 100,000 sats
// with a 1,410 sat sender fee added 1,410 to what this wallet "paid".
MempoolAddressTransaction _tx(String id, int balanceChange, int fee) =>
    MempoolAddressTransaction(
      id: id,
      timestamp: DateTime(2026, 10, 1),
      isConfirmed: true,
      details: mempool.MempoolTransaction(
        txid: id,
        confirmed: true,
        fee: fee,
        balanceChange: balanceChange,
      ),
    );

void main() {
  final wallet = WalletConfig(id: 'w', name: 'Watch');

  test('a receive carries no fee; a send carries the fee it paid', () {
    final received =
        TransactionPdfExport.enrichForTest(_tx('in', 100000, 1410), wallet)!;
    final sent =
        TransactionPdfExport.enrichForTest(_tx('out', -51410, 1410), wallet)!;
    expect(received.isSent, isFalse);
    expect(received.feeSats, 0);
    expect(sent.isSent, isTrue);
    expect(sent.feeSats, 1410);

    final summary = summarizeRows([received, sent]);
    expect(summary.totalFeeSats, 1410);
    // The balance arithmetic is untouched: the send's outflow already
    // holds its fee.
    expect(summary.netSats, 100000 - 51410);
  });
}
