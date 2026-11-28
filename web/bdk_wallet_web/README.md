Vendored from npm @bitcoindevkit/bdk-wallet-web@0.4.0 (sha512
psfpI8/97L5pJw2pkFLp0MyI9d2pQ5vbu30/bpmeXh0pMnioR+CSHIKlr2JOVsIHPZb5gYTKKOJZqw7PEJqmaw==),
MIT OR Apache-2.0, https://github.com/bitcoindevkit/bdk-wasm. Files copied
unchanged: bitcoindevkit_bg.js, bitcoindevkit_bg.wasm, bitcoindevkit.d.ts
and both licenses. The package's bundler entry (bitcoindevkit.js) is left
out: loader.js (ours) instantiates the wasm with the same glue instead.

Used only by the web build: index.html loads it into globalThis.kuteBdk and
lib/services/onchain/web/ answers the com.kutewallet.app/onchain channel
with it. iOS and Android keep the native BDK bindings.

Refresh: npm pack @bitcoindevkit/bdk-wallet-web@<version>, copy the same
files, update the version and hash here.
