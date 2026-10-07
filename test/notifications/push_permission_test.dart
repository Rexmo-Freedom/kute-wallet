// The push-permission ask: once per install from Home, wired on grant
// (topics + AppsFlyer uninstall token), silent after a denial, and the
// `push_permission_*` funnel events around the OS prompt.

import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/notifications/push_permission.dart';
import 'package:kute/services/once_flags_service.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  late Directory dir;
  late List<(String, Map<String, Object>?)> events;
  var requests = 0;
  var subscribes = 0;
  var registers = 0;

  PushPermissionPorts ports({
    AuthorizationStatus current = AuthorizationStatus.notDetermined,
    AuthorizationStatus answer = AuthorizationStatus.authorized,
    bool subscribeOk = true,
    bool requestThrows = false,
  }) =>
      PushPermissionPorts(
        currentStatus: () async => current,
        requestPermission: () async {
          requests++;
          if (requestThrows) throw StateError('no firebase app');
          return answer;
        },
        subscribeToTopics: () async {
          subscribes++;
          return subscribeOk;
        },
        registerUninstallToken: () async {
          registers++;
        },
      );

  List<String> names() => events.map((e) => e.$1).toList();
  Map<String, Object>? paramsOf(String name) =>
      events.firstWhere((e) => e.$1 == name).$2;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('push_permission_test');
    Hive.init(dir.path);
    await Hive.openBox<bool>(OnceFlagsService.boxName);
    TrackingService.setDisabled(true);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    requests = 0;
    subscribes = 0;
    registers = 0;
  });

  tearDown(() async {
    TrackingService.debugTrackObserver = null;
    PushPermission.debugPorts = null;
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('first Home: one prompt, flag set, grant subscribes and registers',
      () async {
    PushPermission.debugPorts = ports();

    final status = await PushPermission.requestOnceFromHome();

    expect(status, PushPermissionStatus.granted);
    expect(requests, 1);
    expect(subscribes, 1);
    expect(registers, 1);
    expect(OnceFlagsService.isClaimed(PushPermission.promptedFlag), isTrue);
    expect(names(), ['push_permission_requested', 'push_permission_result']);
    expect(paramsOf('push_permission_requested'),
        {'surface': 'onboarding_home'});
    expect(paramsOf('push_permission_result'),
        {'status': 'granted', 'granted': 1});
  });

  test('later Home mounts never prompt again', () async {
    PushPermission.debugPorts = ports();
    await PushPermission.requestOnceFromHome();
    events.clear();

    // Same install, next launch: the once-flag persisted.
    expect(await PushPermission.requestOnceFromHome(), isNull);
    expect(await PushPermission.requestOnceFromHome(), isNull);
    expect(requests, 1);
    expect(events, isEmpty);
  });

  test('flag already claimed by a previous version of the app: no prompt',
      () async {
    OnceFlagsService.claimOnce(PushPermission.promptedFlag);
    PushPermission.debugPorts = ports();

    expect(await PushPermission.requestOnceFromHome(), isNull);
    expect(requests, 0);
    expect(events, isEmpty);
  });

  test('denied: nothing further, and no re-prompt', () async {
    PushPermission.debugPorts = ports(answer: AuthorizationStatus.denied);

    final status = await PushPermission.requestOnceFromHome();

    expect(status, PushPermissionStatus.denied);
    expect(subscribes, 0);
    expect(registers, 0);
    expect(OnceFlagsService.isClaimed(PushPermission.promptedFlag), isTrue);
    expect(paramsOf('push_permission_result'),
        {'status': 'denied', 'granted': 0});

    expect(await PushPermission.requestOnceFromHome(), isNull);
    expect(requests, 1);
  });

  test('provisional counts as enabled', () async {
    PushPermission.debugPorts =
        ports(answer: AuthorizationStatus.provisional);

    final status = await PushPermission.request(surface: 'settings');

    expect(status, PushPermissionStatus.provisional);
    expect(status.isEnabled, isTrue);
    expect(subscribes, 1);
    expect(registers, 1);
    expect(paramsOf('push_permission_requested'), {'surface': 'settings'});
    expect(paramsOf('push_permission_result'),
        {'status': 'provisional', 'granted': 1});
  });

  test('a sheet dismissed without an answer is recorded as denied',
      () async {
    PushPermission.debugPorts =
        ports(answer: AuthorizationStatus.notDetermined);

    final status = await PushPermission.request(surface: 'settings');

    expect(status, PushPermissionStatus.notDetermined);
    expect(subscribes, 0);
    expect(paramsOf('push_permission_result'),
        {'status': 'denied', 'granted': 0});
  });

  test('a failing platform call never throws and reads as denied', () async {
    PushPermission.debugPorts = ports(requestThrows: true);

    final status = await PushPermission.request(surface: 'settings');

    expect(status, PushPermissionStatus.denied);
    expect(names(), ['push_permission_requested', 'push_permission_result']);
    expect(paramsOf('push_permission_result'),
        {'status': 'denied', 'granted': 0});
    expect(subscribes, 0);
    expect(registers, 0);
  });

  test('a platform failure on the Home ask leaves the turn for a later launch',
      () async {
    PushPermission.debugPorts = ports(requestThrows: true);
    expect(await PushPermission.requestOnceFromHome(),
        PushPermissionStatus.denied);
    expect(OnceFlagsService.isClaimed(PushPermission.promptedFlag), isFalse);

    // Next launch, Firebase is up: the prompt runs, and only now is the
    // flag kept.
    PushPermission.debugPorts = ports();
    expect(await PushPermission.requestOnceFromHome(),
        PushPermissionStatus.granted);
    expect(requests, 2);
    expect(OnceFlagsService.isClaimed(PushPermission.promptedFlag), isTrue);
    expect(await PushPermission.requestOnceFromHome(), isNull);
  });

  test('topics are subscribed once per install, retried until they succeed',
      () async {
    PushPermission.debugPorts = ports(subscribeOk: false);
    await PushPermission.request(surface: 'settings');
    expect(subscribes, 1);

    // A later grant path (say, the user toggled it on in the OS settings)
    // retries because the first subscribe did not go through...
    PushPermission.debugPorts = ports(current: AuthorizationStatus.authorized);
    await PushPermission.syncAfterExternalChange();
    expect(subscribes, 2);

    // ...and once it did, further grant paths leave it alone. The
    // uninstall token is offered each time; AppsFlyerUninstallToken
    // itself drops an unchanged token.
    await PushPermission.syncAfterExternalChange();
    expect(subscribes, 2);
    expect(registers, 3);
  });

  test('sync after an external change does nothing while still off',
      () async {
    PushPermission.debugPorts = ports(current: AuthorizationStatus.denied);

    final status = await PushPermission.syncAfterExternalChange();

    expect(status, PushPermissionStatus.denied);
    expect(subscribes, 0);
    expect(registers, 0);
    expect(events, isEmpty);
  });

  test('currentStatus buckets the platform status and never throws',
      () async {
    PushPermission.debugPorts =
        ports(current: AuthorizationStatus.deniedPermanently);
    expect(await PushPermission.currentStatus(), PushPermissionStatus.denied);

    PushPermission.debugPorts = PushPermissionPorts(
      currentStatus: () async => throw StateError('no firebase app'),
      requestPermission: () async => AuthorizationStatus.denied,
      subscribeToTopics: () async => true,
      registerUninstallToken: () async {},
    );
    expect(await PushPermission.currentStatus(),
        PushPermissionStatus.notDetermined);
  });
}
