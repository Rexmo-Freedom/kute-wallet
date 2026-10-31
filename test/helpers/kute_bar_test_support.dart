// test/helpers/kute_bar_test_support.dart
//
// The floating Sal bar in a widget test. Since 31 October 2026 every
// pinned primary button is the shell bar in primary-action mode
// (kute_bar_context.dart, KuteBarContext.primary): a screen draws no
// button of its own, so a test that taps "Continue" or "Send" mounts the
// bar over the harness the way app_widget.dart does ([withKuteShellBar]
// as the MaterialApp's builder) and taps [kuteBarPrimary].

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';

/// A MaterialApp `builder`: the app under the shell bar.
Widget withKuteShellBar(BuildContext context, Widget? child) =>
    Stack(children: [child!, const KuteShellBar()]);

/// The bar as the primary button.
final Finder kuteBarPrimary =
    find.byKey(const ValueKey('kute-bar-primary-button'));

/// The bar's primary button carrying [text].
Finder kuteBarPrimaryWithText(String text) =>
    find.descendant(of: kuteBarPrimary, matching: find.text(text));

/// The primary context the page declares now: the last primary
/// [KuteBarContextScope] in the tree, which the page's build keeps current
/// (the bar itself redraws a frame later). The bar's own, when the scope
/// is gone.
KuteBarContext kuteBarPrimaryContext(WidgetTester tester) {
  final scopes = find
      .byWidgetPredicate(
          (w) => w is KuteBarContextScope && w.barContext.isPrimary)
      .evaluate()
      .where((e) => ModalRoute.of(e)?.isCurrent ?? true)
      .toList();
  if (scopes.isNotEmpty) {
    return (scopes.last.widget as KuteBarContextScope).barContext;
  }
  return tester
      .widget<KuteBarPrimaryButton>(find.byType(KuteBarPrimaryButton))
      .barContext;
}

/// Whether the bar's primary button takes a tap.
bool kuteBarPrimaryEnabled(WidgetTester tester) {
  final ctx = kuteBarPrimaryContext(tester);
  return ctx.enabled && !ctx.busy && ctx.onPrimary != null;
}

/// The bar's primary button read the way a test read the drawn AppButton
/// it replaced: [text] the label, [isLoading] the busy state, [onPressed]
/// the handler while the button takes a tap, else null.
class KuteBarPrimaryProbe {
  const KuteBarPrimaryProbe(this.context);

  final KuteBarContext context;

  String get text => context.label;
  bool get isLoading => context.busy;
  VoidCallback? get onPressed =>
      context.enabled && !context.busy ? context.onPrimary : null;
}

KuteBarPrimaryProbe kuteBarPrimaryProbe(WidgetTester tester) =>
    KuteBarPrimaryProbe(kuteBarPrimaryContext(tester));
