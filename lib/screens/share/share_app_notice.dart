// lib/screens/share/share_app_notice.dart
//
// "OPEN IN THE APP" ON A SHARED MARKET (founder decision 6, 27 November
// 2026). A shared market's guest page (share_guest_screen.dart) in a phone
// browser carries one small notice for someone who already has the phone
// app: "Have the Kute app? Open this there." with Open in the app, which
// goes to the app's store page (the App Store on iOS, Google Play on
// Android; plain store links, no AppsFlyer). It can be dismissed for this
// run, and is never shown to a visitor with a web wallet in this browser
// (the guest page only exists without one).
//
// Until app links exist for the web host the store page is the honest
// target: an installed app shows "Open" there; the market itself does not
// open in the app yet.
//
// ONE NOTICE AT A TIME: [ShareAppNotice.showing] is true while this notice
// is up. The general "get the app" banner must stay away while it is
// (this one wins on `/s/...`).
//
// Analytics: `share_app_notice_shown {platform}` once per page,
// `share_app_notice_tapped {platform}`, `share_app_notice_dismissed`.

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/in_app_browser.dart';
import 'package:kute/platform/open_external.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Android application id, for its Google Play page.
const String kAndroidApplicationId = 'com.kutewallet.app';

abstract final class ShareAppNotice {
  /// True while the notice is on screen: the "get the app" banner yields.
  static final ValueNotifier<bool> showing = ValueNotifier<bool>(false);

  /// Dismissed in this run.
  static bool _dismissed = false;

  @visibleForTesting
  static void debugReset() {
    _dismissed = false;
    showing.value = false;
  }

  /// Test seam: what the button opens instead of the store.
  @visibleForTesting
  static void Function(Uri uri)? debugOpen;

  /// The store page for this phone: the App Store (from `APP_STORE_ID`) or
  /// Google Play. Null when there is none to name.
  static Uri? storeUri() {
    if (InAppBrowser.isApple) {
      var id = '';
      try {
        id = (dotenv.env['APP_STORE_ID'] ?? '')
            .replaceFirst(RegExp(r'^id'), '');
      } catch (_) {/* not loaded */}
      if (!RegExp(r'^\d+$').hasMatch(id)) return null;
      return Uri.parse('https://apps.apple.com/app/id$id');
    }
    return Uri.parse(
        'https://play.google.com/store/apps/details?id=$kAndroidApplicationId');
  }
}

/// [child] with the notice over its top on a phone browser.
class ShareAppNoticeHost extends StatefulWidget {
  const ShareAppNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  State<ShareAppNoticeHost> createState() => _ShareAppNoticeHostState();
}

class _ShareAppNoticeHostState extends State<ShareAppNoticeHost> {
  late bool _show;
  late final Uri? _store;

  String get _platform => InAppBrowser.isApple ? 'ios' : 'android';

  @override
  void initState() {
    super.initState();
    _store = ShareAppNotice.storeUri();
    _show = !ShareAppNotice._dismissed &&
        InAppBrowser.isPhoneBrowser &&
        _store != null;
    if (_show) {
      ShareAppNotice.showing.value = true;
      TrackingService.track('share_app_notice_shown',
          params: {'platform': _platform});
    }
  }

  @override
  void dispose() {
    if (_show) ShareAppNotice.showing.value = false;
    super.dispose();
  }

  void _dismiss() {
    ShareAppNotice._dismissed = true;
    ShareAppNotice.showing.value = false;
    TrackingService.track('share_app_notice_dismissed');
    setState(() => _show = false);
  }

  void _open() {
    final uri = _store;
    if (uri == null) return;
    TrackingService.track('share_app_notice_tapped',
        params: {'platform': _platform});
    final debug = ShareAppNotice.debugOpen;
    if (debug != null) return debug(uri);
    openExternally(uri);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    final c = context.colors;
    final l10n = context.l10n;
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 12.w,
          right: 12.w,
          top: top + 8.h,
          child: Material(
            key: const ValueKey('share-app-notice'),
            color: c.surface,
            elevation: 2,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 6.h, 4.w, 6.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.shareOpenInAppBody,
                      style: TextStyle(color: c.textPrimary, fontSize: 14.sp),
                    ),
                  ),
                  TextButton(
                    onPressed: _open,
                    child: Text(l10n.shareOpenInApp),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: c.textSecondary),
                    onPressed: _dismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
