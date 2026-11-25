# Vendored: breez_sdk_spark_flutter with web support

This folder is a copy of https://github.com/breez/breez-sdk-spark-flutter at
the v0.26.1 release (commit f5755c4), plus one change of ours on top: web
support, which runs the Breez SDK on Flutter web through Breez's official wasm
build (npm `@breeztech/breez-sdk-spark`, vendored in `web/breez_sdk_spark`).

What our change adds: `lib/src/web/` (the web bindings and loader),
`tool/gen_web_bindings.py` and `tool/vendor_web_sdk.sh` (how the bindings are
generated), and conditional imports in the existing Dart files so iOS and
Android keep the upstream generated FFI bindings unchanged. The `example/`
app is left out.

It lives in the repository so every build, including CI, resolves the same
source. Licence: MIT, see `LICENSE` in this folder.
