// Settings across the window (round three; founder, 25 November 2026:
// "lots of screens are vertical only. It must be all occupying full screen
// when we can"): the four cards in one row, Security | Preferences |
// Advanced side by side; the Wallets and Referral sub-pages as the detail
// beside Settings. Checked for stretch at every EXPANDED size; shot when
// asked: DESK_FULL_RENDER=<dir>.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart' as settings_model;
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/settings/settings.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

import 'desk_full_support.dart';

RuntimeCapabilitiesService _policy() => RuntimeCapabilitiesService.forTesting(
      client: MockClient((request) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                'affiliate.program': {'allowed': true, 'reason': ''},
                'export.transactions': {'allowed': true, 'reason': ''},
                'settings.advanced': {'allowed': true, 'reason': ''},
              },
            }),
            200);
      }),
      baseUrl: () => 'https://backend.test',
      sessionToken: () => AffiliateService.sessionToken,
      appVersion: () async => '2.1.0',
    );

List<Override> _overrides() {
  final never = Completer<settings_model.Settings>();
  return [
    initialSettingsProvider.overrideWith((ref) => never.future),
    biometricsAvailableProvider.overrideWith((ref) async => true),
    appVersionLabelProvider.overrideWith((ref) async => '2.1.2 (90)'),
  ];
}

RuntimeCapabilitiesService? _live;

Future<void> _policyUp(WidgetTester tester) async {
  final policy = _live = _policy();
  RuntimeCapabilitiesService.debugInstance = policy;
  await tester.runAsync(policy.refresh);
}

Future<void> _end(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  _live?.dispose();
  _live = null;
  await deskFullEnd(tester);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final (label, size) in deskFullExpanded) {
    testWidgets(
        'settings at $label: four cards in a row, sections side by '
        'side, nothing stretched', (tester) async {
      await _policyUp(tester);
      await pumpDeskPage(tester,
          size: size,
          dark: false,
          page: const Settings(),
          overrides: _overrides());
      expect(tester.takeException(), isNull);
      final cards = [
        for (final id in ['backup', 'pin', 'referral', 'support'])
          tester.getRect(find.byKey(ValueKey('settings-card-$id')))
      ];
      // One row where every label fits a quarter (from about 1100 wide);
      // else the phone's two by two.
      if (size.width >= 1100) {
        for (final r in cards.skip(1)) {
          expect(r.top, closeTo(cards.first.top, 0.5));
        }
      }
      final security = tester.getRect(find.text('Security'));
      final preferences = tester.getRect(find.text('Preferences'));
      expect(preferences.top, closeTo(security.top, 0.5));
      expect(preferences.left, greaterThan(security.right));
      if (size.width >= 1200) {
        final advanced = tester.getRect(find.text('Advanced'));
        expect(advanced.top, closeTo(security.top, 0.5));
      }
      expectDeskNothingStretched(tester,
          maxCard: kuteWideColumnMax,
          // The four big cards are one row across the page.
          allow: [find.byType(KuteActionCard)]);
      await _end(tester);
    });
  }

  for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: settings $label $mode', skip: deskFullDir == null,
          (tester) async {
        await deskFullAssets(tester);
        await _policyUp(tester);
        await pumpDeskPage(tester,
            size: size,
            dark: dark,
            page: const Settings(),
            overrides: _overrides());
        await deskFullShoot(tester, 'settings_${label}_$mode');
        await _end(tester);
      });
      testWidgets('render: settings detail $label $mode',
          skip: deskFullDir == null, (tester) async {
        await deskFullAssets(tester);
        await _policyUp(tester);
        await pumpDeskPage(tester,
            size: size,
            dark: dark,
            // The master beside a stand-in detail: the column, the detail's
            // room (the real sub-pages have their own renders).
            page: KuteMasterDetail(
              master: const Settings(),
              detail: Scaffold(
                  body: Center(
                      child: Text('Detail', style: TextStyle(fontSize: 32)))),
            ),
            overrides: _overrides());
        await deskFullShoot(tester, 'settings_master_${label}_$mode');
        await _end(tester);
      });
    }
  }
}
