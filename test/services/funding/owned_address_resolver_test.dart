import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _evm = '0x1111111111111111111111111111111111111111';
const _other = '0x2222222222222222222222222222222222222222';
const _btc = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';

class _Sources implements OwnedAddressSources {
  String activeWallet = 'hot-1';
  bool switchWhileReading = false;
  String pmWallet = _evm;

  @override
  String spendingWalletId() => activeWallet;
  @override
  Future<String> sparkSelfAddress() async => _spark;
  @override
  Future<String> hyperliquidEoa() async {
    if (switchWhileReading) activeWallet = 'hot-2';
    return _evm;
  }

  @override
  Future<String> polymarketDepositWallet() async => pmWallet;
}

void main() {
  final hotRoute = RouteKey(
      fromChain: 'spark',
      fromAsset: 'BTC',
      toChain: 'hypercore',
      toAsset: 'USDC');
  final ledgerRoute = RouteKey(
      fromChain: 'bitcoin',
      fromAsset: 'BTC',
      toChain: 'hypercore',
      toAsset: 'USDC');

  Future<SettlementOwnership> resolveHot(_Sources sources) =>
      OwnedAddressResolver(sources).resolve(
        walletId: 'hot-1',
        route: hotRoute,
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.hlHot,
      );

  test('hot ownership binds both sides to the captured wallet', () async {
    final ownership = await resolveHot(_Sources());
    verifySettlementOwnership(
      route: hotRoute,
      ownership: ownership,
      refundAddress: _spark,
      recipientAddress: _evm,
    );
    expect(
      () => verifySettlementOwnership(
        route: hotRoute,
        ownership: ownership,
        refundAddress: _spark,
        recipientAddress: _other,
      ),
      throwsA(isA<WalletGuardException>().having(
          (e) => e.reason, 'reason', WalletGuardReason.recipientNotOwn)),
    );
  });

  test('switching wallets during an address read fails closed', () async {
    await expectLater(
      resolveHot(_Sources()..switchWhileReading = true),
      throwsA(isA<WalletGuardException>()
          .having((e) => e.field, 'field', 'wallet_changed')),
    );
  });

  test('a hot source cannot fund a Ledger recipient', () async {
    await expectLater(
      OwnedAddressResolver(_Sources()).resolve(
        walletId: 'hot-1',
        route: hotRoute,
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.hlLedger,
      ),
      throwsA(isA<WalletGuardException>()
          .having((e) => e.field, 'field', 'cross_account')),
    );
  });

  test(
      'Predictions cash straight into the Investing account resolves both '
      'own accounts; the wrong chains stay refused', () async {
    final pmToHl = RouteKey(
        fromChain: 'polygon',
        fromAsset: 'USDC.e',
        toChain: 'hypercore',
        toAsset: 'USDC');
    // Refused here before (founder report 15 October 2026: the direct leg
    // went via Dollars every time, before any quote).
    final ownership = await OwnedAddressResolver(_Sources()).resolve(
      walletId: 'hot-1',
      route: pmToHl,
      source: SettlementAccountKind.pmHot,
      destination: SettlementAccountKind.hlHot,
    );
    expect(ownership.refund.address, _evm);
    expect(ownership.recipient.address, _evm);
    expect(
      () => verifySettlementOwnership(
        route: pmToHl,
        ownership: ownership,
        refundAddress: _evm,
        recipientAddress: _other,
      ),
      throwsA(isA<WalletGuardException>().having(
          (e) => e.reason, 'reason', WalletGuardReason.recipientNotOwn)),
    );
    expect(
      () => checkSettlementAccountPair(
          route: hotRoute,
          source: SettlementAccountKind.pmHot,
          destination: SettlementAccountKind.hlHot),
      throwsA(isA<WalletGuardException>()
          .having((e) => e.field, 'field', 'source_chain')),
    );
  });

  test(
      'Investing cash straight into the Predictions account (the native '
      'HyperCore route) resolves the Investing refund on HyperCore and the '
      'Predictions deposit wallet on Polygon', () async {
    final hlToPm = RouteKey(
        fromChain: 'hypercore',
        fromAsset: 'USDC',
        toChain: 'polygon',
        toAsset: 'USDC.e');
    final ownership = await OwnedAddressResolver(_Sources()..pmWallet = _other)
        .resolve(
      walletId: 'hot-1',
      route: hlToPm,
      source: SettlementAccountKind.hlHot,
      destination: SettlementAccountKind.pmHot,
    );
    expect(ownership.refund.address, _evm);
    expect(ownership.refund.kind, OwnedAddressKind.hyperliquidEoa);
    expect(ownership.recipient.address, _other);
    expect(ownership.recipient.kind, OwnedAddressKind.polymarketDepositWallet);
    verifySettlementOwnership(
      route: hlToPm,
      ownership: ownership,
      refundAddress: _evm,
      recipientAddress: _other,
    );
    expect(
      () => verifySettlementOwnership(
        route: hlToPm,
        ownership: ownership,
        refundAddress: _evm,
        recipientAddress: _evm,
      ),
      throwsA(isA<WalletGuardException>().having(
          (e) => e.reason, 'reason', WalletGuardReason.recipientNotOwn)),
    );
    // The pair only on its own chains.
    expect(
      () => checkSettlementAccountPair(
          route: RouteKey(
              fromChain: 'hypercore',
              fromAsset: 'USDC',
              toChain: 'spark',
              toAsset: 'BTC'),
          source: SettlementAccountKind.hlHot,
          destination: SettlementAccountKind.pmHot),
      throwsA(isA<WalletGuardException>()
          .having((e) => e.field, 'field', 'destination_chain')),
    );
    expect(
      () => checkSettlementAccountPair(
          route: hlToPm,
          source: SettlementAccountKind.hlHot,
          destination: SettlementAccountKind.pmLedger),
      throwsA(isA<WalletGuardException>()
          .having((e) => e.field, 'field', 'cross_account')),
    );
  });

  SettlementOwnership resolveLedger(String proofWallet) =>
      resolveLedgerSettlementOwnership(
        walletId: 'ledger-1',
        route: ledgerRoute,
        source: SettlementAccountKind.ledgerBtc,
        destination: SettlementAccountKind.hlLedger,
        verifiedEvmAddress: _evm,
        verifiedBtc: (
          walletId: proofWallet,
          address: _btc,
          index: 3,
          verifiedAt: DateTime.utc(2026, 9, 23),
        ),
      );

  test('Ledger ownership rejects a Bitcoin proof from another wallet', () {
    expect(
      () => resolveLedger('ledger-2'),
      throwsA(isA<WalletGuardException>().having(
          (e) => e.reason, 'reason', WalletGuardReason.ownAddressUnavailable)),
    );
  });

  test('Ledger proof retains device confirmation and rejects substitutions',
      () {
    final ownership = resolveLedger('ledger-1');
    expect(ownership.refund.index, 3);
    expect(ownership.refund.deviceVerifiedAt, DateTime.utc(2026, 9, 23));
    verifySettlementOwnership(
      route: ledgerRoute,
      ownership: ownership,
      refundAddress: _btc,
      recipientAddress: _evm,
    );
    expect(
      () => verifySettlementOwnership(
        route: ledgerRoute,
        ownership: ownership,
        refundAddress: _btc,
        recipientAddress: _other,
      ),
      throwsA(isA<WalletGuardException>().having(
          (e) => e.reason, 'reason', WalletGuardReason.recipientNotOwn)),
    );
  });
}
