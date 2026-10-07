import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations.dart';

export 'package:kute/l10n/generated/app_localizations.dart';

/// Every language the app ships a full translation for (one
/// lib/l10n/app_<code>.arb each), by its native name. The order is the
/// Settings picker's: alphabetical, Latin scripts first, then Greek,
/// Cyrillic and Japanese.
const languageNativeNames = <String, String>{
  'cs': 'Čeština',
  'da': 'Dansk',
  'de': 'Deutsch',
  'et': 'Eesti',
  'en': 'English',
  'es': 'Español',
  'fr': 'Français',
  'hr': 'Hrvatski',
  'it': 'Italiano',
  'lv': 'Latviešu',
  'lt': 'Lietuvių',
  'hu': 'Magyar',
  'nl': 'Nederlands',
  'pl': 'Polski',
  'pt': 'Português',
  'ro': 'Română',
  'sk': 'Slovenčina',
  'sl': 'Slovenščina',
  'fi': 'Suomi',
  'sv': 'Svenska',
  'el': 'Ελληνικά',
  'bg': 'Български',
  'ja': '日本語',
};

/// Convenience extension to access AppLocalizations from BuildContext.
///
/// Usage: `context.l10n.totalBalance`
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Localizations for code without a BuildContext, in the app language
/// ([languageCode] from settings). Unshipped languages fall back to English.
AppLocalizations l10nForLanguage(String languageCode) {
  final supported = AppLocalizations.supportedLocales
      .any((l) => l.languageCode == languageCode);
  return lookupAppLocalizations(Locale(supported ? languageCode : 'en'));
}

/// Localizations in the language the person picked in Settings, for code
/// with neither a BuildContext nor a ref: policy decisions, venue
/// availability answers and the typed errors services throw. Reads the
/// persisted setting (written before the settings state changes), so it
/// always matches the app's own locale; before settings exist it follows
/// the device like first boot does.
AppLocalizations appL10n() {
  String? stored;
  try {
    if (Hive.isBoxOpen('settings')) {
      stored = Hive.box('settings').get('language') as String?;
    }
  } catch (_) {/* device language */}
  return l10nForLanguage(
      stored ?? PlatformDispatcher.instance.locale.languageCode);
}
