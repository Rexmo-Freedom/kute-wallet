// Breez SDK (wasm build, vendored from npm @breeztech/breez-sdk-spark in
// breez_sdk_spark/): starts downloading before the app; the Dart bindings
// await globalThis.breezSdkSpark in BreezSdkSparkLib.init(). A file, not
// an inline script, so the Content-Security-Policy allows no inline JS.
import init, * as breez from './breez_sdk_spark/index.js';

globalThis.breezSdkSpark = init().then(() => breez, (e) => {
  delete globalThis.breezSdkSpark;
  throw e;
});
