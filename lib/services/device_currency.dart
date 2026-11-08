// lib/services/device_currency.dart
//
// THE SETTINGS CURRENCY A NEW INSTALL STARTS ON.
//
// A new install starts on its device's region, for Bitcoin's conversion
// line (dollar-side money always reads in dollars). The region, never the
// language: Portuguese in Brazil is BRL and in Portugal EUR, English in
// Germany is EUR and in the UK GBP. A country outside the Settings list, or
// a device with no region, is USD.
//
// Who counts as new: the settings box file did not exist before this boot.
// Every build ever shipped opens that box at start, so the file is on disk
// from an install's first launch on, empty or not; an existing install that
// never touched the setting (no stored 'currency', reads USD) always has it
// and stays on USD. Secure storage cannot tell them apart, because the iOS
// keychain outlives an uninstall. Asking the box after opening it cannot
// either, because opening creates the file.
//
// The choice is written once, into 'currency', the same key the Settings
// picker writes, so nothing here runs again: moving country never changes it
// and the person's own pick overwrites it.
//
//  * A wallet restored on a new phone is a new install on that device: it
//    defaults from the region.
//  * An iPhone restored from its own backup or moved with Quick Start brings
//    the settings file along: an existing install, whatever it stored.
//  * The device wipe (lib/services/hive_wipe.dart) deletes the file, so the
//    next open is a new install, as the wipe intends.

import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:hive_ce/hive.dart';

/// The key in the settings box, shared with `SettingsModel.setCurrency` and
/// `initialSettingsProvider`.
const String kSettingsCurrencyKey = 'currency';

/// The currency when the region says nothing better.
const String kFallbackCurrency = 'USD';

const MethodChannel _regionChannel = MethodChannel('kute/device_region');

/// Country (ISO 3166-1 alpha-2) to the Settings list's currency. The United
/// States needs no row: it and everything unlisted fall to [kFallbackCurrency].
const Map<String, String> kCountryCurrency = {
  // Eurozone, Bulgaria since January 2026.
  'AT': 'EUR', 'BE': 'EUR', 'BG': 'EUR', 'CY': 'EUR', 'DE': 'EUR',
  'EE': 'EUR', 'ES': 'EUR', 'FI': 'EUR', 'FR': 'EUR', 'GR': 'EUR',
  'HR': 'EUR', 'IE': 'EUR', 'IT': 'EUR', 'LT': 'EUR', 'LU': 'EUR',
  'LV': 'EUR', 'MT': 'EUR', 'NL': 'EUR', 'PT': 'EUR', 'SI': 'EUR',
  'SK': 'EUR',
  // Their territories with a region code of their own.
  'AX': 'EUR', 'BL': 'EUR', 'EA': 'EUR', 'GF': 'EUR', 'GP': 'EUR',
  'IC': 'EUR', 'MF': 'EUR', 'MQ': 'EUR', 'PM': 'EUR', 'RE': 'EUR',
  'YT': 'EUR',
  // Outside the eurozone, the euro as their money.
  'AD': 'EUR', 'ME': 'EUR', 'MC': 'EUR', 'SM': 'EUR', 'VA': 'EUR',
  'XK': 'EUR',
  'GB': 'GBP', 'GG': 'GBP', 'IM': 'GBP', 'JE': 'GBP',
  'CH': 'CHF', 'LI': 'CHF',
  'BR': 'BRL',
  'SE': 'SEK',
  'NO': 'NOK', 'SJ': 'NOK',
  'DK': 'DKK', 'FO': 'DKK', 'GL': 'DKK',
  'PL': 'PLN',
  'CZ': 'CZK',
  'HU': 'HUF',
  'RO': 'RON',
};

/// The Settings currency for [country]; null, empty or unlisted is USD.
String currencyForCountry(String? country) =>
    kCountryCurrency[country?.trim().toUpperCase()] ?? kFallbackCurrency;

/// The device's region. iOS keeps it apart from the language, and neither
/// Flutter's locale list nor `Platform.localeName` carries it: both come from
/// the language list, so English (US) on an iPhone set to Germany reads
/// "en_US". iOS asks the system over a channel (DeviceRegionPlugin.swift),
/// bounded because this runs in the boot, and a missing answer falls to the
/// locale. On Android the locale's own country is the region the device has.
Future<String?> deviceRegion() async {
  if (Platform.isIOS) {
    try {
      final region = await _regionChannel
          .invokeMethod<String>('region')
          .timeout(const Duration(seconds: 1));
      if (region != null && region.isNotEmpty) return region;
    } catch (_) {/* the locale's country below */}
  }
  return PlatformDispatcher.instance.locale.countryCode;
}

/// Whether the settings box has never been on this device. Asked before the
/// box opens; a failed check counts as an existing install, which stays on
/// USD, the wrong answer that costs least.
Future<bool> isFirstSettingsOpen() async {
  try {
    return !await Hive.boxExists('settings');
  } catch (_) {
    return false;
  }
}

/// Writes the region's currency into a box a new install has just opened.
/// A value already there always wins.
Future<void> seedCurrencyOnNewInstall(Box<dynamic> settings,
    {required bool isNewInstall,
    Future<String?> Function() region = deviceRegion}) async {
  if (!isNewInstall || settings.containsKey(kSettingsCurrencyKey)) return;
  await settings.put(kSettingsCurrencyKey, currencyForCountry(await region()));
}
