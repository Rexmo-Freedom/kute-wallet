import 'package:kute/l10n/l10n.dart' show AppLocalizations, l10nForLanguage;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';

/// Public, deterministic explanations used when the live service is unavailable.
/// Never reads accounts or pretends to know current market facts.
class AdvisorLocalStub {
  AdvisorLocalStub._();

  /// [l10n] picks the language of the explanation; English when omitted.
  /// The keyword matching reads the query and stays as it is.
  static AdvisorResponse respond(String query,
      [AdvisorContext? context, AppLocalizations? l10n]) {
    final l = l10n ?? l10nForLanguage('en');
    final q = query.toLowerCase();
    String? explanation;
    if ((q.contains('receive') || q.contains('invoice')) &&
        (q.contains('bitcoin') ||
            q.contains('btc') ||
            q.contains('lightning'))) {
      explanation = q.contains('lightning') || q.contains('invoice')
          ? l.salStubReceiveLightning
          : l.salStubReceiveBitcoin;
    } else if ((q.contains('send') || q.contains('buy')) &&
        (q.contains('bitcoin') || q.contains('btc'))) {
      explanation = l.salStubSendBuy;
    } else if (q.contains('kute') &&
        (q.contains('wallet') || q.contains('account') || q.contains('seed'))) {
      explanation = l.salStubWallets;
    } else if (q.contains('limit order')) {
      explanation = l.salStubLimitOrder;
    } else if (q.contains('leverage') || q.contains('liquidation')) {
      explanation = l.salStubLeverage;
    } else if (q.contains('funding') && !q.contains('add')) {
      explanation = l.salStubFunding;
    } else if (q.contains('recovery phrase') || q.contains('backup')) {
      explanation = l.salStubRecoveryPhrase;
    } else if (q.contains('apy')) {
      explanation = l.salStubApy;
    } else if (q.contains('yes and no') || q.contains('prediction market')) {
      explanation = l.salStubPredictionMarket;
    } else if (q.contains('perpetual contract') ||
        q.contains('stocks and perps')) {
      explanation = l.salStubStocksPerps;
    }
    return AdvisorResponse(
      blocks: [
        AdvisorBlock(
          id: 'offline_education',
          kind: AdvisorBlockKind.info,
          markdown: explanation == null
              ? l.salStubOffline
              : '${l.salStubLiveUnavailable}\n\n$explanation',
        )
      ],
    );
  }
}
