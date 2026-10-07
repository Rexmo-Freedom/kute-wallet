import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_activity.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/polymarket_backend_service.dart'
    show GeoBlockException;
import 'package:kute/services/runtime_capabilities_service.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _pt = lookupAppLocalizations(const Locale('pt'));

void main() {
  group('capability block reasons', () {
    const reasons = {
      'country_blocked': 'capabilityRegionRestricted',
      'country_not_allowed': 'capabilityRegionRestricted',
      'app_update_required': 'capabilityUpdateRequired',
      'device_blocked': 'capabilityDeviceRestricted',
      'affiliate_blocked': 'capabilityAccountRestricted',
      'country_unknown': 'capabilityCountryUnknown',
      'policy_unavailable': 'capabilityPolicyUnavailable',
      'switched_off': 'capabilityUnavailable',
    };

    test('every reason code has Kute copy in both languages', () {
      for (final reason in reasons.keys) {
        final decision = CapabilityDecision(allowed: false, reason: reason);
        final en = decision.messageIn(_en);
        final pt = decision.messageIn(_pt);
        expect(en, isNotEmpty, reason: reason);
        expect(pt, isNotEmpty, reason: reason);
        expect(pt, isNot(en), reason: '$reason is untranslated');
        expect(pt.contains('—'), isFalse, reason: reason);
      }
      expect(
          const CapabilityDecision(allowed: false, reason: 'country_blocked')
              .messageIn(_pt),
          _pt.capabilityRegionRestricted);
    });

    test('the operator message wins over the reason code', () {
      const decision = CapabilityDecision(
          allowed: false,
          reason: 'country_blocked',
          serverMessage: ' Paused for maintenance. ');
      expect(decision.messageIn(_pt), 'Paused for maintenance.');
    });

    test('exception text stays English for error categories', () {
      const blocked = CapabilityUnavailableException('polymarket.trade',
          CapabilityDecision(allowed: false, reason: 'country_blocked'));
      expect(blocked.toString(), _en.capabilityRegionRestricted);
      expect(const LeverageCapExceededException(3).toString(), contains('3x'));
      expect(const LeverageCapExceededException(3).messageIn(_pt),
          _pt.leverageCapExceeded(3));
      const venue = ProviderAvailabilityException(ProviderAvailability(
          InvestmentProvider.polymarket,
          ProviderAvailabilityStatus.restricted));
      expect(venue.toString(), _en.providerRegionRestricted('Polymarket'));
      expect(venue.availability.messageIn(_pt),
          _pt.providerRegionRestricted('Polymarket'));
    });
  });

  test('LocalizedError shows the app language and keeps English text', () {
    final error = LocalizedError.from(
        _pt, (l) => l.providerRegionRestricted('Polymarket'));
    expect(error.message, _pt.providerRegionRestricted('Polymarket'));
    expect(error.toString(), _en.providerRegionRestricted('Polymarket'));
    expect(error.toString(), isNot(_pt.providerRegionRestricted('Polymarket')));
  });

  testWidgets('userErrorCopy translates typed and fixed service errors',
      (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('pt'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        captured = context;
        return const SizedBox();
      }),
    ));
    expect(userErrorCopy(captured, 'Network error. Please try again.'),
        _pt.errorCopyOffline);
    expect(
        userErrorCopy(
            captured, 'Jade disconnected. Please reconnect and try again.'),
        _pt.jadeDisconnected);
    expect(userErrorCopy(captured, GeoBlockException()),
        _pt.tradingNotAvailableInRegion);
    expect(userErrorCopy(captured, const LeverageCapExceededException(5)),
        _pt.leverageCapExceeded(5));
    expect(
        userErrorCopy(
            captured,
            const CapabilityUnavailableException('hyperliquid.trade',
                CapabilityDecision(allowed: false, reason: 'device_blocked'))),
        _pt.capabilityDeviceRestricted);
    expect(
        userErrorCopy(captured,
            LocalizedError.from(_pt, (l) => l.moveWalletNotReady)),
        _pt.moveWalletNotReady);
  });

  test('fill actions follow the language they are given', () {
    final fill = HlFill.fromJson({
      'coin': 'BTC',
      'tid': '1',
      'oid': 10,
      'hash': 'h',
      'time': 0,
      'startPosition': '0',
      'sz': '1',
      'px': '60000',
      'side': 'B',
      'closedPnl': '0',
      'fee': '0',
    });
    expect(hlFillAction(fill), 'Opened position');
    expect(hlFillAction(fill, _pt), _pt.hlFillOpened);
  });
}
