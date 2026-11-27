// A protective trigger the price crossed since it was checked is refused
// right before signing, with the same line the sheet shows for it.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/hyperliquid_error_message.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/screens/hyperliquid/components/hl_protect_rules.dart';
import 'package:kute/services/hyperliquid/hl_trigger_guard.dart';

void main() {
  const mark = 66000.0;

  test('the side rule matches the sheets\' (hlProtectIssue)', () {
    for (final closeIsBuy in [false, true]) {
      for (final tpsl in ['sl', 'tp']) {
        for (final trigger in [60000.0, 66000.0, 70000.0]) {
          expect(
              hlTriggerCrossed(
                  closeIsBuy: closeIsBuy,
                  tpsl: tpsl,
                  trigger: trigger,
                  mark: mark),
              hlProtectIssue(
                      closeIsBuy: closeIsBuy,
                      tpsl: tpsl,
                      trigger: trigger,
                      mark: mark) !=
                  HlProtectIssue.none,
              reason: '$closeIsBuy $tpsl $trigger');
        }
      }
    }
  });

  test('no price, no check', () {
    expect(
        hlTriggerCrossed(
            closeIsBuy: false, tpsl: 'sl', trigger: 70000, mark: 0),
        isFalse);
  });

  test('the refusal reads as the sheet\'s own line', () {
    final l10n = l10nForLanguage('en');
    String line(bool closeIsBuy, String tpsl, double trigger) =>
        hlProtectIssueText(
            l10n,
            hlProtectIssue(
                closeIsBuy: closeIsBuy,
                tpsl: tpsl,
                trigger: trigger,
                mark: mark))!;
    expect(
        hlTradeErrorMessage(
            l10n,
            const HlTriggerCrossedException(
                closeIsBuy: false, tpsl: 'sl', mark: mark)),
        line(false, 'sl', 70000));
    expect(
        hlTradeErrorMessage(
            l10n,
            const HlTriggerCrossedException(
                closeIsBuy: true, tpsl: 'sl', mark: mark)),
        line(true, 'sl', 60000));
    expect(
        hlTradeErrorMessage(
            l10n,
            const HlTriggerCrossedException(
                closeIsBuy: false, tpsl: 'tp', mark: mark)),
        line(false, 'tp', 60000));
    expect(
        hlTradeErrorMessage(
            l10n,
            const HlTriggerCrossedException(
                closeIsBuy: true, tpsl: 'tp', mark: mark)),
        line(true, 'tp', 70000));
  });
}
