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

The **Android draft release** workflow publishes a signed APK together with
`SHA256SUMS` and `release-metadata.json`. The release notes and metadata state
the SHA-256 fingerprint of the APK signing certificate. Release assets are not
GPG-signed.

Check the download against the checksums:

```sh
sha256sum --check --ignore-missing SHA256SUMS   # macOS: shasum -a 256 -c
```

Print the signing certificate fingerprint with `apksigner` from the Android
SDK build-tools:

```sh
apksigner verify --print-certs kute-*.apk
```

The `Signer #1 certificate SHA-256 digest` line must match the fingerprint in
the release notes. The certificate is the same for every release; if it
differs from an earlier release, do not install the APK and report it as
above.
