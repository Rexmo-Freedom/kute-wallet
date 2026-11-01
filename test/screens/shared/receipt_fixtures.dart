// The receipts the layout test and the on-demand render open: a Lightning
// send, an on-chain receive, a prediction sold at a loss, an Investing
// position reduced and a Dollars deposit, each with the figures a real
// one carries, and the app around them (settings, the spending wallet's
// history, the venues offline).

import 'dart:io';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show Activity;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usdb_provider.dart' show usdbTokenIdentifier;
import 'package:kute/services/tx_fiat_snapshot_service.dart';

import '../../helpers/offline_venue_overrides.dart';

final receiptAt = DateTime(2026, 11, 1, 20, 32);
const receiptDescription = 'Coffee and a croissant at the corner bakery';
const receiptMarket =
    'Will Alexandria Ocasio-Cortez win the 2028 Democratic presidential '
    'nomination?';
const receiptLightningId = 'ln-send-receipt';
const receiptOnChainTxid =
    '7d1f0c2b9e4a5d6c8b3a2f1e0d9c8b7a6f5e4d3c2b1a0f9e8d7c6b5a4f3e2d1c';
const receiptPolygonHash =
    '0x5b0e6a1c2d3f4e5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a';

int get _seconds => receiptAt.millisecondsSinceEpoch ~/ 1000;

/// A Lightning payment of ₿2,100 with a ₿3 fee and a description.
SparkTransaction receiptLightningSend() => SparkTransaction(
      id: receiptLightningId,
      timestamp: receiptAt,
      isConfirmed: true,
      details: breez.Payment(
        id: receiptLightningId,
        paymentType: breez.PaymentType.send,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from(2100),
        fees: BigInt.from(3),
        timestamp: BigInt.from(_seconds),
        method: breez.PaymentMethod.lightning,
        details: breez.PaymentDetails.lightning(
          description: receiptDescription,
          invoice: 'lnbc21u1receiptinvoice',
          destinationPubkey: '02pubkey',
          htlcDetails: breez.SparkHtlcDetails(
            paymentHash: 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f6',
            preimage: 'f0e1d2c3b4a5968778695a4b3c2d1e0ff0e1d2c3b4a5',
            expiryTime: BigInt.zero,
            status: breez.SparkHtlcStatus.preimageShared,
          ),
        ),
      ),
    );

/// ₿150,000 received on chain, confirmed (a cached row: no live details).
BitcoinTransaction receiptOnChainReceive() => BitcoinTransaction.fromCache(
      id: receiptOnChainTxid,
      timestamp: receiptAt,
      isConfirmed: true,
      receivedSats: 150000,
      sentSats: 0,
    );

Activity _trade(String side,
        {required double usdc, required double price, required int at}) =>
    Activity(
      proxyWallet: '0xme',
      timestamp: at,
      conditionId: '0xaoc',
      type: 'TRADE',
      size: 12.5,
      usdcSize: usdc,
      price: price,
      transactionHash: side == 'SELL' ? receiptPolygonHash : '0xbuy',
      side: side,
      asset: 'no-token',
      outcomeIndex: 1,
      title: receiptMarket,
      outcome: 'No',
      eventSlug: '',
    );

/// 12.50 No shares bought for $4.46.
PolymarketTransaction receiptPredictionBuy() => PolymarketTransaction(
      id: 'pm-buy',
      timestamp: receiptAt.subtract(const Duration(days: 3)),
      activity:
          _trade('BUY', usdc: 4.46, price: 0.357, at: _seconds - 3 * 86400),
    );

/// The same 12.50 No shares sold for $4.37: a $0.09 loss.
PolymarketTransaction receiptPredictionSell() => PolymarketTransaction(
      id: 'pm-sell',
      timestamp: receiptAt,
      activity: _trade('SELL', usdc: 4.37, price: 0.35, at: _seconds),
    );

/// 0.5 OAI sold out of a 2 OAI long: Reduced OAI, a $0.03 loss.
const receiptInvestingReduce = HlFill(
  coin: 'xyz:OAI',
  px: 142.18,
  sz: 0.5,
  side: 'A',
  time: 1793565120000,
  closedPnl: -0.03,
  fee: 0.04,
  feeToken: 'USDC',
  oid: 41234567890,
  hash: '0xhash',
  dir: 'Close Long',
  cloid: null,
  tradeId: '987654321',
  startPosition: 2,
);

/// $25.00 deposited into Dollars.
UsdbTokenTransaction receiptDollarsDeposit() {
  final payment = breez.Payment(
    id: 'usd-deposit',
    paymentType: breez.PaymentType.receive,
    status: breez.PaymentStatus.completed,
    amount: BigInt.from(25000000),
    fees: BigInt.zero,
    timestamp: BigInt.from(_seconds),
    method: breez.PaymentMethod.token,
    details: breez.PaymentDetails.token(
      metadata: breez.TokenMetadata(
        identifier: usdbTokenIdentifier,
        issuerPublicKey: 'issuer',
        name: 'USDB',
        ticker: 'USDB',
        decimals: 6,
        maxSupply: BigInt.zero,
        isFreezable: false,
      ),
      txHash: 'tx-usd-deposit',
      txType: breez.TokenTransactionType.transfer,
    ),
  );
  return UsdbTokenTransaction(
      id: payment.id, timestamp: receiptAt, details: payment, isConfirmed: true);
}

class _Cache extends WalletTransactionCacheNotifier {
  _Cache(Map<String, Transaction> seed) {
    state = seed;
  }
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(isAuthenticated: true);
}

/// Opens the fiat snapshot box in a temp directory and records what the
/// Lightning send and the on-chain receive were worth when they appeared
/// (Value then; Change since against [receiptBtcUsd]). Call from setUpAll;
/// the returned directory is deleted in tearDownAll ([closeReceiptHive]).
Future<Directory> openReceiptHive() async {
  final dir = await Directory.systemTemp.createTemp('receipt_hive');
  Hive.init(dir.path);
  await Hive.openBox<String>(TxFiatSnapshotService.boxName);
  TxFiatSnapshotService.recordUsd(receiptLightningId, 2.27, 2100);
  TxFiatSnapshotService.recordUsd(receiptOnChainTxid, 130.5, 150000);
  return dir;
}

Future<void> closeReceiptHive(Directory dir) async {
  await Hive.close();
  await dir.delete(recursive: true);
}

/// Bitcoin's dollar price now, for Change since.
const double receiptBtcUsd = 97000;

/// The overrides every receipt needs: settings in English and dollars, the
/// spending wallet's Predictions history (the buy and the sale), the
/// venues offline.
List<Override> receiptOverrides() => [
      ...offlineVenueOverrides,
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            balancePrivacy: 0,
            biometricsEnabled: false,
            bitcoinElectrumNode: 'localhost',
            nodeType: 'Blockstream',
            reviewDone: false,
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
            activeWalletId: 'spending',
          ))),
      walletTransactionCacheProvider.overrideWith((_) => _Cache({
            'spending': Transaction(
              bitcoinTransactions: const [],
              sparkTransactions: const [],
              sparkUnclaimedDeposits: const [],
              polymarketTransactions: [
                receiptPredictionBuy(),
                receiptPredictionSell()
              ],
            ),
          })),
      polymarketTradingProvider.overrideWith(_Trading.new),
      currentBtcUsdProvider.overrideWith((_) => receiptBtcUsd),
    ];

/// The app around a receipt: [home] under [theme], with [builder] (the
/// shell bar, for the render).
Widget receiptApp(
  Widget home, {
  required ThemeData theme,
  TransitionBuilder? builder,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: [...receiptOverrides(), ...overrides],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          builder: builder,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: home),
        ),
      ),
    );
