// A money step's words on screen (money_steps_view.dart, the journey): a
// checkpoint listed under the map is a Text; a leg's line, or a
// sub-leg's, is the semantics label of its node on the map (over its
// road, over its waypoint). Tests that read the steps' words use these so
// they find both.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The status line on top of the map says the step at work in the same
/// words: never a step itself.
bool _isStatus(Widget w) => w.key == const ValueKey('money-steps-status');

/// The step whose words are exactly [text].
Finder findMoneyStep(String text) => find.byWidgetPredicate(
    (w) =>
        (w is Text && !_isStatus(w) && w.data == text) ||
        (w is Semantics && w.properties.label == text),
    description: 'money step "$text"');

/// The steps whose words match [pattern].
Finder findMoneyStepMatching(Pattern pattern) => find.byWidgetPredicate(
    (w) {
      final text = w is Text && !_isStatus(w)
          ? w.data
          : w is Semantics
              ? w.properties.label
              : null;
      return text != null && pattern.allMatches(text).isNotEmpty;
    },
    description: 'money step matching $pattern');

/// The steps whose words contain [part].
Finder findMoneyStepContaining(String part) => find.byWidgetPredicate(
    (w) {
      final text = w is Text && !_isStatus(w)
          ? w.data
          : w is Semantics
              ? w.properties.label
              : null;
      return text != null && text.contains(part);
    },
    description: 'money step containing "$part"');
