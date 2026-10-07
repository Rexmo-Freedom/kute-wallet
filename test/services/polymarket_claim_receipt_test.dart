import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket_claim_receipt.dart';

void main() {
  const owner = '0x1111111111111111111111111111111111111111';
  const other = '0x2222222222222222222222222222222222222222';
  Map<String, dynamic> transfer(
          String token, String from, String to, int amount) =>
      {
        'address': token,
        'topics': [
          '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
          '0x${from.substring(2).padLeft(64, '0')}',
          '0x${to.substring(2).padLeft(64, '0')}'
        ],
        'data': '0x${amount.toRadixString(16).padLeft(64, '0')}'
      };
  test('receipt isolates actual payout and cancels wrapping intermediary', () {
    final logs = [
      transfer(PolymarketConstants.usdcEAddress, other, owner, 7500000),
      transfer(PolymarketConstants.usdcEAddress, owner, other, 7500000),
      transfer(PolymarketConstants.pusdAddress, other, owner, 7500000),
      transfer(other, other, owner, 999999999),
      transfer(PolymarketConstants.pusdAddress, other, other, 1000000),
    ];
    expect(claimCreditFromReceipt({'status': '0x1', 'logs': logs}, owner),
        BigInt.from(7500000));
  });
  test('zero credit is distinct from unverifiable receipt', () {
    expect(claimCreditFromReceipt({'status': '0x1', 'logs': []}, owner),
        BigInt.zero);
    expect(
        claimCreditFromReceipt({'status': '0x0', 'logs': []}, owner), isNull);
    expect(claimCreditFromReceipt({'status': '0x1'}, owner), isNull);
    final bad = transfer(PolymarketConstants.pusdAddress, other, owner, 1)
      ..['data'] = 'bad';
    expect(
        claimCreditFromReceipt({
          'status': '0x1',
          'logs': [bad]
        }, owner),
        isNull);
  });
}
