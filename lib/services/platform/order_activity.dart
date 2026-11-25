// lib/services/platform/order_activity.dart
//
// Shows the progress of a bet or trade that is being placed OUTSIDE the
// app, so the person can leave and still see where it is. We say the bet
// is placed instantly; this is the honest trail behind that sentence.
//
// `start(id, title, venue, amountUsd)`, `update(id, stage, progress, line)`,
// `end(id, success, line)` and `cancel(id)`:
//
//   * Android: an ongoing notification with a progress bar on the
//     `kute_order_progress` channel, posted at `start`, redrawn on each
//     `update`, and at `end` either replaced by a final notification on
//     the `kute_order_result` channel (the app is in the background) or
//     taken down (the app is in front: the slip already says it).
//     `cancel` takes it down. Tapping any of them opens the app on the
//     home's Activity list (payload [LocalOrderNotices.payloadActivity]).
//   * iOS: nothing while the order runs (no Live Activity, by decision of
//     9 November 2026: "just use grace period"). At `end`, if the app is
//     in the background and the order finished inside the grace window
//     (lib/services/platform/background_grace.dart), one local
//     notification with the result. After iOS suspends the app no
//     notification can be posted until it comes back; the slip then says
//     what happened.
//   * Elsewhere (web, desktop, tests): a no-op.
//
// Both platforms post through flutter_local_notifications, which the app
// already carried as a dependency (its receivers in the Android manifest,
// its registrant callback in AppDelegate) with no Dart caller; this is the
// first. Notification permission is never asked here: the push ask
// (lib/notifications/push_permission.dart) is the same OS grant, and a
// person who declined it sees nothing from here either.
//
// What the text may say: the venue's kind of order (bet / trade), the
// stage, the market as the person saw it on the slip. Never the amount
// (even the one they typed: a lock screen is read by other people, and
// the app covers its own balances in the app switcher for the same
// reason), never an id. [amountUsd] is accepted for the facade's shape
// and dropped here.
//
// Every call is fire-and-forget and never throws.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kute/l10n/l10n.dart';

/// Which product the order belongs to; decides "bet" or "trade" wording.
enum OrderVenue { predictions, investing }

/// Where a running order is, as the notification says it.
enum OrderStage { waitingMoney, converting, settingUp, sending, confirming }

/// How a finished order ended.
enum OrderOutcome { placed, failed, unconfirmed }

/// One notification as the facade wants it shown, before any platform
/// detail. What tests check.
@immutable
class OrderNotice {
  const OrderNotice({
    required this.id,
    required this.title,
    required this.body,
    this.detail,
    this.progress,
    required this.ongoing,
    this.outcome,
  });

  /// The platform notification id (see [OrderActivity.noticeIdFor]).
  final int id;
  final String title;
  final String body;

  /// A second, smaller line (Android `subText`, iOS subtitle).
  final String? detail;

  /// 0..100 while placing; null for an indeterminate bar or a final notice.
  final int? progress;

  /// A running order: cannot be swiped away, quiet, with a progress bar.
  final bool ongoing;

  /// Set on a final notice only.
  final OrderOutcome? outcome;

  @override
  String toString() => 'OrderNotice($id, "$title" / "$body"'
      '${detail == null ? '' : ' / "$detail"'}'
      '${progress == null ? '' : ', $progress%'}'
      '${ongoing ? ', ongoing' : ''}'
      '${outcome == null ? '' : ', ${outcome!.name}'})';
}

/// Where notices go. The real one is [LocalOrderNotices]; tests install a
/// recorder through [OrderActivity.debugSink].
abstract class OrderNoticeSink {
  Future<void> show(OrderNotice notice);
  Future<void> dismiss(int id);
}

abstract final class OrderActivity {
  /// Test seam: while set, every notice goes here instead of the platform,
  /// on every platform.
  @visibleForTesting
  static OrderNoticeSink? debugSink;

  /// Localizations for text without a BuildContext; the app's language.
  static AppLocalizations Function() strings = appL10n;

  /// Whether the app has left the screen (paused, hidden or detached; a
  /// biometric prompt's `inactive` is still the app). Decides whether an
  /// `end` is told as a notification or left to the slip.
  static bool Function() isBackgrounded = _lifecycleBackgrounded;

  /// What a tap on any order notice does: the app opens the home's
  /// Activity list. Set by the app root.
  static void Function()? onOpenActivity;

  static LocalOrderNotices? _local;
  static final Map<String, _LiveOrder> _live = {};

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether a running notice exists for this platform at all (Android
  /// only; iOS says nothing until the end).
  static bool get showsProgress => _android;

  static OrderNoticeSink? get _sink {
    if (debugSink != null) return debugSink;
    if (!isSupported) return null;
    return _local ??= LocalOrderNotices();
  }

  /// The real sink, for the app root's cold-start tap check.
  static LocalOrderNotices? get local =>
      isSupported ? (_local ??= LocalOrderNotices()) : null;

  /// A stable platform notification id for an order id, so an update
  /// redraws the same notification and the final one replaces it. One
  /// order per venue is live at a time, so the venues get fixed ids.
  static int noticeIdFor(String id) => switch (id) {
        'predictions' => 0x4B01,
        'investing' => 0x4B02,
        _ => 0x4B10 + (id.hashCode & 0xFFFF),
      };

  /// An order left the slip and is on its way. [title] is the market as
  /// the person saw it. [amountUsd] is never shown (see the file header).
  static Future<void> start(String id,
      {required String title,
      required OrderVenue venue,
      double? amountUsd}) async {
    final sink = _sink;
    if (sink == null) return;
    _live[id] = _LiveOrder(title, venue);
    if (!showsProgress) return;
    final l10n = strings();
    await _show(
        sink,
        OrderNotice(
          id: noticeIdFor(id),
          title: _placing(l10n, venue),
          body: title,
          progress: null,
          ongoing: true,
        ));
  }

  /// The order moved on. [progress] is 0..1; [line] replaces the stage's
  /// own sentence when given.
  static Future<void> update(String id,
      {required OrderStage stage,
      required double progress,
      String? line}) async {
    final sink = _sink;
    final live = _live[id];
    if (sink == null || live == null || !showsProgress) return;
    final l10n = strings();
    await _show(
        sink,
        OrderNotice(
          id: noticeIdFor(id),
          title: _placing(l10n, live.venue),
          body: line ?? stageLine(l10n, stage),
          detail: live.title,
          progress: (progress.clamp(0.0, 1.0) * 100).round(),
          ongoing: true,
        ));
  }

  /// The order finished. In the background: a final notification (the
  /// market on a success, "open Kute" on anything else). In front: the
  /// running notice comes down and the slip says the rest. [outcome]
  /// refines [success] (an unconfirmed order is neither).
  static Future<void> end(String id,
      {required bool success, String? line, OrderOutcome? outcome}) async {
    final sink = _sink;
    final live = _live.remove(id);
    if (sink == null) return;
    if (!isBackgrounded()) {
      if (showsProgress) await _dismiss(sink, noticeIdFor(id));
      return;
    }
    if (live == null) return;
    final result =
        outcome ?? (success ? OrderOutcome.placed : OrderOutcome.failed);
    final l10n = strings();
    final placed = result == OrderOutcome.placed;
    await _show(
        sink,
        OrderNotice(
          id: noticeIdFor(id),
          title: resultTitle(l10n, live.venue, result),
          body: line ?? (placed ? live.title : l10n.orderNoticeOpenToSee),
          detail: placed ? null : live.title,
          ongoing: false,
          outcome: result,
        ));
  }

  /// The order went away without an answer (the person cancelled, the
  /// slip was reset): nothing stays in the shade.
  static Future<void> cancel(String id) async {
    final sink = _sink;
    _live.remove(id);
    if (sink == null || !showsProgress) return;
    await _dismiss(sink, noticeIdFor(id));
  }

  static String _placing(AppLocalizations l10n, OrderVenue venue) =>
      switch (venue) {
        OrderVenue.predictions => l10n.orderNoticePlacingPrediction,
        OrderVenue.investing => l10n.orderNoticePlacingOrder,
      };

  /// The sentence for a stage.
  static String stageLine(AppLocalizations l10n, OrderStage stage) =>
      switch (stage) {
        OrderStage.waitingMoney => l10n.orderNoticeWaitingMoney,
        OrderStage.converting => l10n.orderNoticeConverting,
        OrderStage.settingUp => l10n.orderNoticeSettingUp,
        OrderStage.sending => l10n.orderNoticeSending,
        OrderStage.confirming => l10n.orderNoticeConfirming,
      };

  /// The title of a final notice.
  static String resultTitle(
          AppLocalizations l10n, OrderVenue venue, OrderOutcome outcome) =>
      switch ((venue, outcome)) {
        (OrderVenue.predictions, OrderOutcome.placed) =>
          l10n.orderNoticePredictionPlaced,
        (OrderVenue.investing, OrderOutcome.placed) =>
          l10n.orderNoticeOrderPlaced,
        (OrderVenue.predictions, OrderOutcome.failed) =>
          l10n.orderNoticePredictionNotPlaced,
        (OrderVenue.investing, OrderOutcome.failed) =>
          l10n.orderNoticeOrderNotPlaced,
        (_, OrderOutcome.unconfirmed) => l10n.orderNoticeNotConfirmed,
      };

  static Future<void> _show(OrderNoticeSink sink, OrderNotice notice) async {
    try {
      await sink.show(notice);
    } catch (e) {
      debugPrint('[OrderActivity] show failed: $e');
    }
  }

  static Future<void> _dismiss(OrderNoticeSink sink, int id) async {
    try {
      await sink.dismiss(id);
    } catch (e) {
      debugPrint('[OrderActivity] dismiss failed: $e');
    }
  }

  static bool _lifecycleBackgrounded() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
  }

  /// Tests: forget every live order.
  @visibleForTesting
  static void debugReset() {
    _live.clear();
    debugSink = null;
    strings = appL10n;
    isBackgrounded = _lifecycleBackgrounded;
  }
}

class _LiveOrder {
  const _LiveOrder(this.title, this.venue);
  final String title;
  final OrderVenue venue;
}

/// The platform sink: flutter_local_notifications, initialised on first
/// use without asking for any permission.
class LocalOrderNotices implements OrderNoticeSink {
  LocalOrderNotices([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  /// The tap payload: open the home's Activity list.
  static const String payloadActivity = 'activity';

  /// The monochrome status-bar icon android_notification_icons generates
  /// (pubspec: `android_notification_icons`).
  static const String androidIcon = 'ic_notification';

  static const String progressChannelId = 'kute_order_progress';
  static const String resultChannelId = 'kute_order_result';

  Future<bool> _init() => _ready ??= _plugin
          .initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(androidIcon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == payloadActivity) {
            OrderActivity.onOpenActivity?.call();
          }
        },
      )
          .then((ok) => ok ?? false, onError: (Object e) {
        debugPrint('[OrderActivity] notifications unavailable: $e');
        return false;
      });

  @override
  Future<void> show(OrderNotice notice) async {
    if (!await _init()) return;
    final l10n = OrderActivity.strings();
    final android = notice.ongoing
        ? AndroidNotificationDetails(
            progressChannelId,
            l10n.orderNoticeProgressChannel,
            channelDescription: l10n.orderNoticeProgressChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: false,
            showProgress: true,
            maxProgress: 100,
            progress: notice.progress ?? 0,
            indeterminate: notice.progress == null,
            subText: notice.detail,
            category: AndroidNotificationCategory.progress,
          )
        : AndroidNotificationDetails(
            resultChannelId,
            l10n.orderNoticeResultChannel,
            channelDescription: l10n.orderNoticeResultChannelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            autoCancel: true,
            subText: notice.detail,
            category: AndroidNotificationCategory.status,
          );
    final darwin = DarwinNotificationDetails(
      subtitle: notice.detail,
      interruptionLevel: InterruptionLevel.active,
    );
    await _plugin.show(
      id: notice.id,
      title: notice.title,
      body: notice.body,
      notificationDetails: NotificationDetails(android: android, iOS: darwin),
      payload: payloadActivity,
    );
  }

  @override
  Future<void> dismiss(int id) async {
    if (!await _init()) return;
    await _plugin.cancel(id: id);
  }

  /// Whether this launch came from a tap on an order notice (the app was
  /// not running), so the root can open Activity once it is up.
  Future<bool> launchedFromNotice() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp == true &&
          details?.notificationResponse?.payload == payloadActivity;
    } catch (_) {
      return false;
    }
  }
}
