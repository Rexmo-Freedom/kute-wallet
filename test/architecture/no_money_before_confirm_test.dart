// Money moves ONLY after the person accepts (Confirm, then the step-up
// approval). Founder rule of 9 November 2026, restated 11 November 2026
// after 2.2.0 (106) started a swap into Predictions on a 5-minute round
// the moment an amount was tapped ("Don't do this automatically ... never
// ever"): pre-funding (`BetPrefund`, the one-second hold on an amount)
// was removed for good.
//
// This scans lib/ so it cannot come back:
//  1. nothing names the removed pre-funding API;
//  2. on the three tickets (the prediction slip, the Investing order
//     ticket, the margin sheet) the code that runs with no tap on the
//     ticket's button (open, rebuild, an amount typed or tapped, a draft
//     change, close) reaches no approval, funding move, queue or order;
//  3. on the prediction slip the approval is asked only on the Confirm
//     path, and the step-up prompt only inside that approval.
// Comments are stripped first. Free warm-ups (quotes, prefetch, sockets,
// address derivation) are not money and are not looked at here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

const _betSlip = 'lib/screens/polymarket/components/bet_slip_sheet.dart';
const _orderSlip = 'lib/screens/hyperliquid/components/order_slip_sheet.dart';
const _marginSheet =
    'lib/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';

/// A member declared at class level (two spaces in): the first name on
/// the line that opens a parameter list.
final RegExp _memberLine = RegExp(r'^  (?! )[^/\n]*?\b([A-Za-z_]\w*)\(');

/// The member of [code] the character at [offset] sits in: the nearest
/// class-level declaration at or above its line (a declaration is its own
/// member).
String _enclosingMember(String code, int offset) {
  final lineEnd = code.indexOf('\n', offset);
  final upTo = code.substring(0, lineEnd < 0 ? code.length : lineEnd);
  var name = '';
  for (final line in upTo.split('\n')) {
    final m = _memberLine.firstMatch(line);
    if (m != null) name = m.group(1)!;
  }
  return name;
}

/// Every body of a class-level member named [name] in [code], each from
/// its declaration to its closing brace.
List<String> _memberBodies(String code, String name) {
  final lines = code.split('\n');
  final decl = RegExp('^  (?! )[^/\\n]*\\b${RegExp.escape(name)}\\(');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!decl.hasMatch(lines[i])) continue;
    // A call at class level is not a declaration: `name(` must be the
    // first parameter list on the line.
    if (_memberLine.firstMatch(lines[i])?.group(1) != name) continue;
    final body = StringBuffer();
    for (var j = i; j < lines.length; j++) {
      body.writeln(lines[j]);
      if (j > i && lines[j] == '  }') break;
      // An expression body ends on its own line.
      if (j == i && lines[j].trimRight().endsWith(';')) break;
    }
    out.add(body.toString());
  }
  return out;
}

String _read(String path) => stripComments(File(path).readAsStringSync());

void main() {
  test('nothing in lib names the removed pre-funding', () {
    expect(File('lib/services/polymarket/bet_prefund.dart').existsSync(),
        isFalse);
    // Case matters: `cashAppRefundNote` and `SwapRefundAction` are not it.
    final gone = RegExp('Prefund|prefund|PreFund|preFund|pre_fund|'
        r'\bscheduleHold\b|\bholdFired\b|\bdropArmed\b|'
        r'\bstepUpReasonBetReady\b|\bgateAllowed\b');
    final found = <String>[];
    var files = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      files++;
      final code = stripComments(entity.readAsStringSync());
      for (final m in gone.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
        found.add('${entity.path}:$line ${m.group(0)}');
      }
    }
    expect(files, greaterThan(500));
    expect(found, isEmpty,
        reason: 'pre-funding is removed: money moves only after Confirm. '
            '${found.join(', ')}');
  });

  test('no ticket moves money, asks an approval or queues an order without '
      'a tap on its button', () {
    // What runs with no tap on the ticket's button.
    const untapped = [
      'initState',
      'didChangeDependencies',
      'didUpdateWidget',
      'dispose',
      '_onAmountChanged',
      '_onDraftChanged',
      '_onKeypadAmount',
      '_writeFilledAmount',
      '_fillAmount',
      '_fillAmountChip',
      '_updateDraft',
      '_updateState',
      '_loadLiveDelay',
      '_resolveCapabilityGate',
      '_resolveOpenGate',
      '_refreshFundingPlan',
      '_warmBitcoinLeg',
    ];
    // The ways a ticket asks, funds, queues or places.
    final money = RegExp(r'\brequireFreshAuthGrant\(|\bissueAutofire\(|'
        r'\b_approveBet\(|\b_approve\(|\b_handleBuy\b|\b_handleBuyInner\b|'
        r'\b_handleConfirm\b|\b_confirmInner\b|\b_confirmFunded\w*\b|'
        r'\b_confirmDirect\b|\b_confirm\(|\b_fundAndPlace\w*\b|'
        r'\b_runVenueCashFunded\b|\b_runPlacement\b|\bfundAndQueue\(|'
        r'\bfundMore\(|\bstartApproved\(|\bpullShortfall\(|\bpullTo\(|'
        r'\.setIntent\(|\bplaceOrder\(|\bplaceSpotOrder\(|\bopenPosition\(|'
        r'\badjustIsolatedMargin\(|\bUserGrantAuthorization\(|'
        r'venueCashFundedOrderRunnerProvider|bitcoinFundedOrderRunnerProvider|'
        r'marginFundingRunnerProvider|orderFundingControllerProvider');
    final reached = <String>[];
    var looked = 0;
    for (final path in [_betSlip, _orderSlip, _marginSheet]) {
      final code = _read(path);
      for (final name in untapped) {
        for (final body in _memberBodies(code, name)) {
          looked++;
          for (final m in money.allMatches(body)) {
            reached.add('$path $name -> ${m.group(0)}');
          }
        }
      }
    }
    // Each ticket has at least its initState and its amount handler.
    expect(looked, greaterThan(12));
    expect(reached, isEmpty,
        reason: 'money moves only after Confirm: ${reached.join(', ')}');
  });

  test('the prediction slip asks its approval only on the Confirm path', () {
    final code = _read(_betSlip);
    // The Confirm tap ([_handleBuyInner]), the funding it starts, and the
    // Retry button of a stopped placement.
    const confirmPath = {
      '_handleBuyInner',
      '_fundAndPlace',
      '_fundAndPlaceFromBitcoin',
      '_retryPlacement',
    };
    final askers = <String>{};
    for (final m in RegExp(r'\b_approveBet\(').allMatches(code)) {
      final member = _enclosingMember(code, m.start);
      if (member != '_approveBet') askers.add(member);
    }
    expect(askers, isNotEmpty);
    expect(askers.difference(confirmPath), isEmpty,
        reason: 'the approval is asked outside Confirm: $askers');
    // The step-up prompt (and the autofire grant it issues) only inside
    // that one approval.
    final prompts = {
      for (final m in RegExp(r'\brequireFreshAuthGrant\(|autofireIntentId:')
          .allMatches(code))
        _enclosingMember(code, m.start),
    };
    expect(prompts, {'_approveBet'});
    // A funding move is started only by the funding the Confirm path
    // runs.
    final funders = {
      for (final m in RegExp(r'\bfundAndQueue\(|'
              r'venueCashFundedOrderRunnerProvider\)\s*\.start\(|'
              r'\.startApproved\(')
          .allMatches(code))
        _enclosingMember(code, m.start),
    };
    expect(funders, isNotEmpty);
    expect(
        funders.difference(
            {'_fundAndPlace', '_runVenueCashFunded', '_fundAndPlaceFromBitcoin'}),
        isEmpty,
        reason: 'a funding move starts outside Confirm: $funders');
    // Nothing on the slip runs on a timer.
    expect(RegExp(r'\bTimer(\.periodic)?\(|Future(<\w+>)?\.delayed\(')
        .hasMatch(code), isFalse,
        reason: 'the slip holds no timer: nothing here acts on an amount '
            'held');
  });
}
