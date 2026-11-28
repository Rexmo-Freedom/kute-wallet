// BDK (wasm build, vendored from npm @bitcoindevkit/bdk-wallet-web in
// bdk_wallet_web/): the on-chain Bitcoin wallet on the web. Starts loading
// before the app; lib/services/onchain/web/ awaits globalThis.kuteBdkReady,
// then calls globalThis.kuteBdk. A file, not an inline script, so the
// Content-Security-Policy allows no inline JS.
import loadBdk from './bdk_wallet_web/loader.js';

globalThis.kuteBdkReady = loadBdk().then((bdk) => {
  globalThis.kuteBdk = bdk;
  return bdk;
}, (e) => {
  delete globalThis.kuteBdkReady;
  throw e;
});
