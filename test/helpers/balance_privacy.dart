// The home headline's privacy cycle (Settings.balancePrivacy) for screens
// that mask their figures with balances hidden. Without it a test reads
// the settings' loading default, which hides balances.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';

/// Settings with [balancePrivacy] (0 shown, 1 headline hidden, 2 all
/// hidden).
Override balancePrivacyOverride([int balancePrivacy = 0]) =>
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        balancePrivacy: balancePrivacy)));
