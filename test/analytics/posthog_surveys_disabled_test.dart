import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Surveys are never shown in Kute (founder decision, 2026-09-30).
///
/// posthog_flutter renders surveys itself once `PostHogConfig.surveys` is
/// on, so the config in `lib/main.dart` must pin it off explicitly (an SDK
/// default flip must not be able to turn it on), and nothing in `lib/` may
/// bring the survey-trigger plumbing back.
void main() {
  test('PostHog config in lib/main.dart pins surveys off', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('PostHogConfig('),
        reason: 'the PostHog config moved; update this test');
    expect(RegExp(r'\.\.surveys\s*=\s*false').hasMatch(source), isTrue,
        reason: 'the PostHog config must set `..surveys = false` explicitly');
    expect(RegExp(r'\.\.surveys\s*=\s*true').hasMatch(source), isFalse);
  });

  test('no survey-trigger plumbing in lib/', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('SurveyTriggers') ||
          source.contains('survey_trigger_flow_ended')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
