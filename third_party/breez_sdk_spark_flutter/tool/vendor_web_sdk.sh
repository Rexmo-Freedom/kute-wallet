#!/bin/sh
# Copies the browser build of the Breez SDK (npm @breeztech/breez-sdk-spark,
# its `web/` directory) into a Flutter web folder, e.g.
#   tool/vendor_web_sdk.sh example/web/breez_sdk_spark
# The package version must match this Flutter package (pubspec.yaml).
set -eu
DEST=${1:?usage: vendor_web_sdk.sh <dest-dir> [version]}
VERSION=${2:-$(sed -n 's/^version: //p' "$(dirname "$0")/../pubspec.yaml")}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
(cd "$TMP" && npm pack --silent "@breeztech/breez-sdk-spark@$VERSION" >/dev/null && tar xzf ./*.tgz)
rm -rf "$DEST"
mkdir -p "$DEST"
for f in index.js breez_sdk_spark_wasm.js breez_sdk_spark_wasm_bg.wasm storage tree-store passkey-prf-provider; do
  cp -R "$TMP/package/web/$f" "$DEST/"
done
find "$DEST" -name '*.d.ts' -delete
cat > "$DEST/README.md" <<NOTE
Vendored from npm @breeztech/breez-sdk-spark@$VERSION (directory web/), MIT
licensed, https://github.com/breez/spark-sdk. Loaded by the Breez SDK Flutter
web bindings (breez_sdk_spark_flutter, lib/src/web). Refresh with
tool/vendor_web_sdk.sh from that package.
NOTE
echo "vendored @breeztech/breez-sdk-spark@$VERSION into $DEST"
