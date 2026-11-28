// Kute's loader for the vendored bdk-wasm build (not part of the npm
// package). The package is built for bundlers: its entry file imports the
// .wasm as an ES module, which browsers cannot do. This instantiates the
// same module with the same glue (bitcoindevkit_bg.js) by hand.
import * as bdk from './bitcoindevkit_bg.js';

export default async function loadBdk() {
  const url = new URL('./bitcoindevkit_bg.wasm', import.meta.url);
  const imports = { './bitcoindevkit_bg.js': bdk };
  let instance;
  if (typeof WebAssembly.instantiateStreaming === 'function') {
    try {
      ({ instance } = await WebAssembly.instantiateStreaming(fetch(url), imports));
    } catch (_) {
      // A server without the application/wasm type: compile from bytes.
    }
  }
  if (!instance) {
    const response = await fetch(url);
    if (!response.ok) throw new Error('bdk wasm unavailable');
    ({ instance } = await WebAssembly.instantiate(await response.arrayBuffer(), imports));
  }
  bdk.__wbg_set_wasm(instance.exports);
  return bdk;
}
