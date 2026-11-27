import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app: the system browser on a phone or desktop,
/// a new tab on web. Used where a platform has no in-app web view
/// (`PlatformCaps.hasWebView`) or no in-app review sheet. Never throws.
Future<bool> openExternally(Uri uri) async {
  try {
    return await launchUrl(uri,
        mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  } catch (_) {
    return false;
  }
}

/// The App Store listing for [appStoreId] (with or without the `id`
/// prefix), or null when it is unknown.
Uri? appStoreListingUri(String? appStoreId) {
  final id = (appStoreId ?? '').trim().replaceFirst(RegExp(r'^id'), '');
  if (id.isEmpty) return null;
  return Uri.parse('https://apps.apple.com/app/id$id');
}

/// The app's Android package (android/app/build.gradle's applicationId).
const String kAndroidPackage = 'com.kutewallet.app';

/// The Google Play listing for the app: a plain store link, no tracking
/// parameters.
Uri playStoreListingUri() => Uri.https(
    'play.google.com', '/store/apps/details', {'id': kAndroidPackage});
