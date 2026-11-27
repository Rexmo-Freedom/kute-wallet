/// Which browser the web app runs in, as far as a link opened from a social
/// app matters: an app's own in-app browser (Instagram, Facebook,
/// TikTok, Telegram, X, LinkedIn, Snapchat, a plain Android web view) often
/// has no passkeys and may drop the page's storage, so a share arrival there
/// is told to open the page in Safari or Chrome (the 12-word path stays
/// available). Read from the user agent only; never sent anywhere but as
/// the category below. Null-safe off the web (`native`).
library;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

import 'package:kute/platform/browser_agent.dart';

abstract final class InAppBrowser {
  /// Test seam: the user agent to classify instead of the browser's.
  @visibleForTesting
  static String? debugUserAgent;

  /// `native` off the web; on it `in_app`, `safari`, `chrome`, `firefox`,
  /// `edge`, `samsung` or `other`.
  static String get kind {
    final ua = debugUserAgent ?? (kIsWeb ? browserUserAgent() : null);
    if (ua == null) return kIsWeb ? 'other' : 'native';
    return classify(ua);
  }

  /// True in a social app's in-app browser.
  static bool get isInApp => kind == 'in_app';

  /// The category of the user agent [ua].
  @visibleForTesting
  static String classify(String ua) {
    final u = ua.toLowerCase();
    const inApp = [
      'instagram',
      'fban',
      'fbav',
      'fb_iab',
      'messenger',
      'tiktok',
      'musical_ly',
      'bytedancewebview',
      'telegram',
      'twitter',
      'linkedinapp',
      'snapchat',
      'line/',
      'micromessenger',
      'pinterest',
    ];
    if (inApp.any(u.contains)) return 'in_app';
    // A plain Android web view says `; wv)`.
    if (u.contains('; wv)')) return 'in_app';
    if (u.contains('edg/') || u.contains('edgios') || u.contains('edga')) {
      return 'edge';
    }
    if (u.contains('samsungbrowser')) return 'samsung';
    if (u.contains('firefox') || u.contains('fxios')) return 'firefox';
    if (u.contains('crios') || u.contains('chrome/')) return 'chrome';
    if (u.contains('safari/') && u.contains('version/')) return 'safari';
    // An iOS app's WKWebView: AppleWebKit without Safari's version tag.
    if ((u.contains('iphone') || u.contains('ipad')) &&
        u.contains('applewebkit') &&
        !u.contains('safari/')) {
      return 'in_app';
    }
    return 'other';
  }

  /// A phone or tablet browser (iOS, iPadOS, Android).
  static bool get isPhoneBrowser {
    if (!kIsWeb && debugUserAgent == null) return false;
    final u = (debugUserAgent ?? browserUserAgent() ?? '').toLowerCase();
    return u.contains('iphone') ||
        u.contains('ipad') ||
        u.contains('android') ||
        // iPadOS reports a Mac; a touch Mac does not exist.
        (u.contains('macintosh') && u.contains('mobile/'));
  }

  /// iOS or iPadOS (for "Safari" vs "Chrome" in the notice).
  static bool get isApple {
    final u = (debugUserAgent ?? browserUserAgent() ?? '').toLowerCase();
    return u.contains('iphone') || u.contains('ipad') || u.contains('mac os');
  }
}
