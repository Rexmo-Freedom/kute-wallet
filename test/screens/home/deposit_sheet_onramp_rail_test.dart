// An onramp the runtime policy does not offer is not shown anywhere
// (founder decision, October 2026). In the Move sheet that means: no
// Cash App row in the source picker, no bank row, and no door opening on
// a hidden rail. A Cash App door with Cash App withheld opens on its
// natural non-fiat source instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';

import '../../helpers/source_scan.dart';

MoveOpeningRail _rail({
  required bool seededRail,
  bool cashAppDefault = false,
  bool cashAppOverBitcoin = false,
  bool cashAppVisible = false,
  bool bankVisible = false,
}) =>
    moveOpeningRail(
      seededRail: seededRail,
      cashAppDefault: cashAppDefault,
      cashAppOverBitcoin: cashAppOverBitcoin,
      cashAppVisible: cashAppVisible,
      bankVisible: bankVisible,
    );

String _moveSheetSource() => stripComments(
      File('lib/screens/home/components/deposit_sheet.dart').readAsStringSync(),
    );

void main() {
  group('moveOpeningRail', () {
    test('Cash App offered: a Cash App door opens on Cash App', () {
      expect(
        _rail(seededRail: true, cashAppDefault: true, cashAppVisible: true),
        MoveOpeningRail.cashApp,
      );
      expect(
        _rail(
          seededRail: true,
          cashAppDefault: true,
          cashAppVisible: true,
          bankVisible: true,
        ),
        MoveOpeningRail.cashApp,
      );
    });

    test('Cash App withheld, bank hidden: the natural source, never a rail',
        () {
      // Buy bitcoin, the venue buys, "Deposit more", Activity's purchase.
      expect(
        _rail(seededRail: true, cashAppDefault: true),
        MoveOpeningRail.natural,
      );
      // The unlocked bank entry with no rail on offer.
      expect(_rail(seededRail: true), MoveOpeningRail.natural);
    });

    test('bank offered by the policy: a bank-seeded door keeps it', () {
      expect(_rail(seededRail: true, bankVisible: true), MoveOpeningRail.bank);
      expect(
        _rail(seededRail: true, cashAppDefault: true, bankVisible: true),
        MoveOpeningRail.bank,
      );
    });

    test('bank hidden, Cash App offered: the plain bank entry takes Cash App',
        () {
      expect(
        _rail(seededRail: true, cashAppVisible: true),
        MoveOpeningRail.cashApp,
      );
    });

    test('a door not seeded on a rail keeps its own source', () {
      for (final cashAppVisible in [false, true]) {
        for (final bankVisible in [false, true]) {
          expect(
            _rail(
              seededRail: false,
              cashAppDefault: true,
              cashAppVisible: cashAppVisible,
              bankVisible: bankVisible,
            ),
            MoveOpeningRail.none,
          );
        }
      }
    });

    test(
        'dollars door: an explicit Cash App request takes over Bitcoin '
        'only while Cash App is offered', () {
      expect(
        _rail(
          seededRail: false,
          cashAppDefault: true,
          cashAppOverBitcoin: true,
          cashAppVisible: true,
        ),
        MoveOpeningRail.cashApp,
      );
      // Withheld: the door stays on spending Bitcoin.
      expect(
        _rail(
            seededRail: false, cashAppDefault: true, cashAppOverBitcoin: true),
        MoveOpeningRail.none,
      );
      expect(
        _rail(
          seededRail: false,
          cashAppDefault: true,
          cashAppOverBitcoin: true,
          bankVisible: true,
        ),
        MoveOpeningRail.none,
      );
    });
  });

  group('source picker', () {
    test('the Cash App row and hint both go through that one answer', () {
      final source = _moveSheetSource();
      // Exactly one Cash App row in the picker, behind the policy check.
      expect(
        RegExp(r"asset: 'lib/assets/cashapp-logo\.svg',\s*title: 'Cash App'")
            .allMatches(source)
            .length,
        1,
      );
      expect(
        RegExp(
          r"if \(cashAppOffered\(policy\)\)\s*_PickerRow\(\s*"
          r"asset: 'lib/assets/cashapp-logo\.svg',",
        ).hasMatch(source),
        isTrue,
      );
      expect(source,
          contains('hint: (policy) => pickerHint(cashAppOffered(policy))'));
      // The one answer is the policy helper: no bank row, and no other
      // condition can list a withheld Cash App.
      expect(
        RegExp(r'bool cashAppOffered\(RuntimeCapabilitiesService policy\) =>\s*'
                r'onrampVisible\(policy, kOnrampCashApp\);')
            .hasMatch(source),
        isTrue,
      );
      expect(source, isNot(contains('onrampVisible(policy, kOnrampBank)')));
      // The open picker watches the policy, so it follows it live.
      expect(
        source,
        contains('final policy = sheetRef.watch(runtimeCapabilitiesProvider);'),
      );
      // No disabled "UNAVAILABLE" Cash App tile, no reason caption.
      expect(source, isNot(contains("'UNAVAILABLE'")));
      expect(source, isNot(contains("blockReason('onramp.")));
    });
  });

  test('every rail pick in the Move sheet checks the onramp helper', () {
    final source = _moveSheetSource();
    expect(
      source,
      contains(
        'onrampVisible(ref.read(runtimeCapabilitiesProvider), kOnrampBank)',
      ),
    );
    expect(
      source,
      contains(
        'onrampVisible(ref.read(runtimeCapabilitiesProvider), kOnrampCashApp)',
      ),
    );
    // The build watches the policy so those reads follow it live.
    expect(source, contains('ref.watch(runtimeCapabilitiesProvider);'));
    // The Cash App pick, the fiat flip and the Ledger switch all refuse
    // a hidden rail. No picker row selects the bank at all.
    expect(source, isNot(contains('onPickFiat')));
    expect(
      RegExp(r'onPickCashApp: \(\) \{\s*if \(!_cashAppVisible\) return;')
          .hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(r'if \(_isFiatMode\) \{\s*if \(!_bankRailAllowed\) return;')
          .hasMatch(source),
      isTrue,
    );
    expect(
      source,
      contains(
        'if (source == LedgerDepositSource.bank && '
        '!_bankRailAllowed) return;',
      ),
    );
    expect(
      source,
      contains(
        'if (source == LedgerDepositSource.cashApp && '
        '!_cashAppVisible) return;',
      ),
    );
  });

  test('no screen reads an onramp capability except through the helper', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('onramp_visibility.dart')) continue;
      final source = stripComments(entity.readAsStringSync());
      if (RegExp(r"(allows|blockReason|decision)\('onramp\.")
          .hasMatch(source)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
