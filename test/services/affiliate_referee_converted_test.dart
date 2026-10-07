// `affiliate_referee_converted` counts only referred accounts: the backend's
// referral flag in the runtime capabilities decides, and without it the
// once-per-device flag stays unclaimed so a later event can still fire.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

const _flag = 'affiliate_referee_converted';

class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy(this.snapshot);

  @override
  final RuntimeCapabilities? snapshot;
}

RuntimeCapabilities _policy({required bool referred}) {
  final now = DateTime.now().toUtc();
  return RuntimeCapabilities.fromJson(<String, dynamic>{
    'schemaVersion': 1,
    'revision': 1,
    'evaluatedAt': now.toIso8601String(),
    'expiresAt': now.add(const Duration(minutes: 2)).toIso8601String(),
    'capabilities': <String, dynamic>{},
    'referral': <String, dynamic>{'isReferred': referred},
  });
}

void main() {
  late Directory dir;
  late List<String> events;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('referee_converted_test');
    Hive.init(dir.path);
    await Hive.openBox<bool>(OnceFlagsService.boxName);
    TrackingService.setDisabled(true);
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('no policy loaded: nothing is sent and the flag stays unclaimed', () {
    RuntimeCapabilitiesService.debugInstance = _Policy(null);
    TrackingService.affiliateRefereeConverted(provider: 'orchestra');
    expect(events, isEmpty);
    expect(OnceFlagsService.isClaimed(_flag), isFalse);
  });

  test('not referred: nothing is sent and the flag stays unclaimed', () {
    RuntimeCapabilitiesService.debugInstance =
        _Policy(_policy(referred: false));
    TrackingService.affiliateRefereeConverted(
        provider: 'orchestra', amountUsd: 25);
    expect(events, isEmpty);
    expect(OnceFlagsService.isClaimed(_flag), isFalse);
  });

  test('referred: one event, and a second call sends nothing', () {
    // A call before the policy loaded must not use up the flag.
    RuntimeCapabilitiesService.debugInstance = _Policy(null);
    TrackingService.affiliateRefereeConverted(provider: 'orchestra');
    RuntimeCapabilitiesService.debugInstance = _Policy(_policy(referred: true));
    TrackingService.affiliateRefereeConverted(
        provider: 'orchestra', amountUsd: 25);
    TrackingService.affiliateRefereeConverted(provider: 'polymarket');
    expect(events, [_flag]);
    expect(OnceFlagsService.isClaimed(_flag), isTrue);
  });
}
