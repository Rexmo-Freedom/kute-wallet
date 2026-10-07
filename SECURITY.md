# Security

## Reporting a vulnerability

Report vulnerabilities privately, either through GitHub private vulnerability
reporting on this repository or by email to joao@rexmo.io. Do not open a
public issue.

Include the affected version or commit, steps to reproduce and the impact you
expect. We aim to send a first response within 3 business days.

**Scope:** this repository covers the Kute app. Kute's backend is a separate
service; report backend issues the same way.

**Safe harbour:** we will not pursue legal action against good-faith research
that avoids privacy violations, data destruction and service disruption, uses
only your own wallets and funds, and gives us reasonable time to fix the issue
before disclosure.

## Verifying Android releases

Kute's Android releases are signed by maintainers with one long-lived key.
Print the signing certificate fingerprint of an APK with `apksigner` from the
Android SDK build-tools:

```sh
apksigner verify --print-certs kute-*.apk
```

The `Signer #1 certificate SHA-256 digest` line must read:

```
d03a3f52e431670117d21137b2aa25b58dde5645740c1356a7d034fcfd2bb340
```

If it differs, do not install the APK and report it as above. Builds from
Google Play are re-signed by Play App Signing and show Google's certificate
instead; App Store builds are signed by Apple.
