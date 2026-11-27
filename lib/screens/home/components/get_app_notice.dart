// lib/screens/home/components/get_app_notice.dart
//
// THE WEB HOME'S "GET THE APP" NOTICE (founder, 27 November 2026: "Allow
// user on the web version to download the app on Android and on iOS. Make
// it clear on top with a banner (user can dismiss), with download for
// Android or iOS, or dismiss.").
//
// The Bitcoin home's notice card (kute_notice_card.dart, the backup
// reminder's), at the top of the Bitcoin and the Dollars home: Sal, a
// title, one line, the store button(s) and a close control.
//   * An iPhone or iPad browser: the App Store only; Android: Google Play
//     only; a laptop: both. Plain store links (the App Store listing from
//     the env's APP_STORE_ID, the Play listing for com.kutewallet.app), in
//     a new tab, no attribution parameters (founder: AppsFlyer leaves the
//     product).
//   * Closed, it stays away for 30 days in this browser (plain
//     localStorage, plain_web_storage.dart).
//   * Never off the web, never when the page runs as an installed app
//     (`display-mode: standalone`), and never while the backup reminder is
//     up: that one wins and this one waits, so two notices never stack.
//     It is placed only on the two home tabs, so onboarding, market pages,
//     sub-pages and sheets never show it.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/browser_signals.dart';
import 'package:kute/platform/open_external.dart';
import 'package:kute/platform/plain_web_storage.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/shared/kute_notice_card.dart';
import 'package:kute/services/tracking_service.dart';

enum AppStoreKind {
  appStore('app_store', 'App Store'),
  googlePlay('google_play', 'Google Play');

  const AppStoreKind(this.eventName, this.label);

  /// Its analytics value.
  final String eventName;

  /// The store's own name, which every locale writes as it is.
  final String label;
}

abstract final class GetAppNoticeRules {
  /// How long a close keeps the notice away.
  static const Duration snooze = Duration(days: 30);

  /// Where the close is remembered (plain, per browser).
  static const String storageKey = 'kute.get_app_notice.dismissed_at';

  /// Tests: the clock.
  @visibleForTesting
  static DateTime Function()? debugNow;

  static DateTime now() => (debugNow ?? DateTime.now)();

  /// The stores this browser is offered, in order.
  static List<AppStoreKind> storesFor(BrowserPlatform platform) =>
      switch (platform) {
        BrowserPlatform.ios => const [AppStoreKind.appStore],
        BrowserPlatform.android => const [AppStoreKind.googlePlay],
        BrowserPlatform.laptop => const [
            AppStoreKind.appStore,
            AppStoreKind.googlePlay
          ],
      };

  /// Whether the notice may show (see the file header). [signals] null is
  /// off the web.
  static bool shouldShow({
    required BrowserSignals? signals,
    required bool backupShowing,
    required DateTime? dismissedAt,
    required DateTime now,
  }) {
    if (signals == null || signals.standalone) return false;
    if (backupShowing) return false;
    if (dismissedAt != null && now.difference(dismissedAt) < snooze) {
      return false;
    }
    return true;
  }

  static DateTime? readDismissedAt() {
    final raw = PlainWebStorage.read(storageKey);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static void writeDismissedAt(DateTime at) => PlainWebStorage.write(
      storageKey, at.millisecondsSinceEpoch.toString());

  /// The store's page, or null when unknown (no APP_STORE_ID).
  static Uri? storeUri(AppStoreKind store) {
    switch (store) {
      case AppStoreKind.appStore:
        String? id;
        try {
          id = dotenv.env['APP_STORE_ID'];
        } catch (_) {
          // The env is not loaded (a test, an early start).
        }
        return appStoreListingUri(id);
      case AppStoreKind.googlePlay:
        return playStoreListingUri();
    }
  }
}

/// When this browser last closed the notice; shared by both homes, so a
/// close on one hides it on the other at once.
final getAppNoticeDismissedAtProvider =
    StateProvider<DateTime?>((ref) => GetAppNoticeRules.readDismissedAt());

/// Tests: the store links open here instead of in a new tab.
@visibleForTesting
Future<bool> Function(Uri uri)? debugGetAppNoticeOpen;

class GetAppNotice extends ConsumerStatefulWidget {
  const GetAppNotice({
    super.key,
    required this.surface,
    this.padding = EdgeInsets.zero,
  });

  /// `bitcoin` or `dollars`, for analytics.
  final String surface;

  /// Around the card, only when it shows.
  final EdgeInsets padding;

  @override
  ConsumerState<GetAppNotice> createState() => _GetAppNoticeState();
}

/// Surfaces that reported `get_app_banner_shown` this session.
final Set<String> _shownThisSession = {};

/// Tests: a new session.
@visibleForTesting
void debugResetGetAppNoticeSession() => _shownThisSession.clear();

class _GetAppNoticeState extends ConsumerState<GetAppNotice> {
  void _reportShown(String platform) {
    if (_shownThisSession.contains(widget.surface)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownThisSession.contains(widget.surface)) return;
      // On screen: its tab is the one shown and nothing is pushed over it.
      if (!TickerMode.valuesOf(context).enabled) return;
      if (ModalRoute.of(context)?.isCurrent == false) return;
      _shownThisSession.add(widget.surface);
      TrackingService.getAppBannerShown(
          surface: widget.surface, platform: platform);
    });
  }

  @override
  Widget build(BuildContext context) {
    final signals = readBrowserSignals();
    final show = GetAppNoticeRules.shouldShow(
      signals: signals,
      backupShowing: ref.watch(pendingSpendingWalletBackupProvider) != null,
      dismissedAt: ref.watch(getAppNoticeDismissedAtProvider),
      now: GetAppNoticeRules.now(),
    );
    if (!show) return const SizedBox.shrink();
    final platform = signals!.platform;
    final stores = [
      for (final store in GetAppNoticeRules.storesFor(platform))
        if (GetAppNoticeRules.storeUri(store) != null) store,
    ];
    if (stores.isEmpty) return const SizedBox.shrink();
    _reportShown(platform.name);
    final l10n = context.l10n;
    return Padding(
      padding: widget.padding,
      child: KuteNoticeCard(
        key: const ValueKey('get-app-notice'),
        title: l10n.getAppBannerTitle,
        subtitle: l10n.getAppBannerSubtitle,
        actions: [
          for (final store in stores)
            KuteNoticeAction(
              key: ValueKey('get-app-${store.eventName}'),
              label: store.label,
              onTap: () {
                TrackingService.getAppBannerStoreTapped(
                    store: store.eventName,
                    surface: widget.surface,
                    platform: platform.name);
                final uri = GetAppNoticeRules.storeUri(store)!;
                (debugGetAppNoticeOpen ?? openExternally)(uri);
              },
            ),
        ],
        closeLabel: l10n.close,
        closeKey: const ValueKey('get-app-close'),
        onClose: () {
          TrackingService.getAppBannerDismissed(
              surface: widget.surface, platform: platform.name);
          final now = GetAppNoticeRules.now();
          GetAppNoticeRules.writeDismissedAt(now);
          ref.read(getAppNoticeDismissedAtProvider.notifier).state = now;
        },
      ),
    );
  }
}
