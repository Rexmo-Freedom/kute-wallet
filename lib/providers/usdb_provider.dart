// lib/providers/usdb_provider.dart
//
// What survives of USDB after the Flashnet Earn product was removed
// (user decision, the same way Morpho went): the token identifier, and
// the one lookup that turns an Orchestra (chain, asset) pair into it.
//
// The identifier is load bearing for history: the Breez SDK re-emits
// every past USDB token transfer from its on-device DB forever, and
// push_pipeline / background_sync use this identifier to route those
// payments into token rows instead of the BTC bucket. Without the guard a
// $50 USDB transfer (50,000,000 base units at 6 decimals) would render as
// 50,000,000 sats.
//
// It is now load bearing for SENDING too: it is what the SDK is handed so
// a Spark payment spends the dollar balance instead of the bitcoin one.

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:kute/services/orchestra_routes.dart'
    show isOrchestraUsdRoute, kOrchestraUsdAssetCode;

const String usdbTokenIdentifier =
    'btkn1xgrvjwey5ngcagvap2dzzvsy4uk8ua9x69k82dwvt5e7ef9drm9qztux87';

/// True for a Spark token payment that moved dollars: a token payment
/// whose metadata names the dollar token, by identifier or by ticker.
/// A token payment of any other token is not dollars and never enters
/// the dollar ledger (the periodic sync already asks the SDK for this
/// token only; the push path must agree, or the ledger fallback would
/// count another token as dollars). A token payment without details is
/// kept: nothing says it is another token.
bool isUsdbTokenPayment(breez.Payment payment) {
  if (payment.method != breez.PaymentMethod.token) return false;
  final details = payment.details;
  if (details is! breez.PaymentDetails_Token) return true;
  final meta = details.metadata;
  return meta.identifier == usdbTokenIdentifier ||
      meta.ticker.trim().toUpperCase() == kOrchestraUsdAssetCode;
}

/// The Spark token identifier that funds a payment whose source is the
/// Orchestra asset ([chain], [assetCode]), or null when that source is
/// plain bitcoin on Spark.
///
/// Null is not "unknown" — it is the positive statement that this send is
/// paid in satoshis. Every caller must branch on it, because the two
/// balances share no unit: token amounts are in the token's own base
/// units (six decimals for dollars), sats are sats.
String? sparkTokenIdentifierFor(String chain, String assetCode) =>
    isOrchestraUsdRoute(chain, assetCode) ? usdbTokenIdentifier : null;
