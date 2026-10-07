# Kute

Kute is a self-custodial Bitcoin wallet built with Flutter. On-chain savings
wallets use native BDK; Lightning and Spark use the Breez SDK. Wallets can be
backed by a passkey instead of a written 12-word phrase, and Ledger hardware
wallets are supported. Alongside Bitcoin, the app has Dollars (a USD stablecoin
balance), Predictions (Polymarket) and Investing (Hyperliquid). Orchestra
handles transfers between networks and venues, and Cash App purchases are
offered where available. Sal is an optional assistant that explains markets;
no private wallet data is sent to it. Provider availability comes from the
backend's runtime policy.

## Development

Prerequisites:

- Flutter from `.fvmrc`, installed with [fvm](https://fvm.app). A newer global
  Flutter rewrites `pubspec.lock` and `Podfile.lock`.
- For Android: JDK 17, Android SDK platform 37, build-tools 36.0.0,
  NDK 28.2.13676358, and Rust 1.96 with the `aarch64-linux-android`,
  `armv7-linux-androideabi` and `x86_64-linux-android` targets (the Breez SDK
  builds through cargokit).

CI pins these versions in `.github/actions/flutter-setup/action.yml`. Commit
`pubspec.lock`; dependency resolution must not silently change it.

In a fresh checkout without local configuration:

```sh
python3 .github/scripts/configure.py fixture
fvm flutter pub get --enforce-lockfile
fvm flutter gen-l10n
fvm flutter analyze --no-pub --no-fatal-infos
fvm flutter test --no-pub
fvm flutter build apk --debug --no-pub
```

The fixture writes `.env`, `lib/firebase_options.dart` and
`android/app/google-services.json` with placeholder values. It only lets the
project compile and run its tests; it is not a working wallet configuration.
A working app needs Kute's backend (`BACKEND`) and a Breez API key
(`BREEZ_API_KEY`). The fixture does not write `GoogleService-Info.plist`, so
iOS and macOS builds from a fresh checkout also need one in `ios/Runner/` and
`macos/Runner/`. `.env.sample` lists every key the app reads from `.env`.
The helper refuses to overwrite existing files. Keep real configuration and
signing files outside Git.

## Releases

GitHub CI checks pull requests and builds a debug APK. The manual
**Android draft release** workflow builds the production-signed APK only and
creates a draft GitHub Release with `SHA256SUMS`, source metadata and the
signing certificate's SHA-256. It does not publish the draft or upload to an
app store. iOS builds and Google Play bundles are built by maintainers outside
CI. Maintainers run device acceptance checks on every release candidate.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities and verifying
releases.

## Contributing

Issues and pull requests are welcome; CI must pass before a change is merged.
Report security issues as described in SECURITY.md, not in public issues.

## Trademarks

"Kute", the Kute logo and the Sal character are trademarks of Rexmo
Technologies OÜ and are not licensed under the GPL. Forks must use their own
name and branding. Third-party names and logos (Bitcoin, Lightning,
Polymarket, Hyperliquid, Cash App, Ledger, Apple, Google and hardware wallet
brands) belong to their owners and are used only to identify those services.

## License

Kute is licensed under the GNU General Public License v3.0 or later, with
additional permissions under section 7 for distribution through app stores and
for combining with non-GPL platform and vendor SDKs. See [LICENSE](LICENSE).

Kute was originally forked from [Satsails](https://github.com/Satsails/Satsails).
Satsails shipped the GPLv2 text without specifying a version, so under GPLv2
section 9 any version of the GPL may be chosen; Kute is distributed under
GPLv3-or-later. The additional permissions cover only code whose copyright
holders granted them; Satsails-derived code remains under the GPL as received.
Release metadata identifies the corresponding source commit.

Copyright © 2024–2026 Rexmo Technologies OÜ and contributors; portions ©
Satsails contributors.
