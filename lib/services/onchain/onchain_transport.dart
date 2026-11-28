/// How NativeOnchainService reaches BDK: the com.kutewallet.app/onchain
/// MethodChannel to native BDK on iOS and Android; on the web, where no
/// native side exists, the same contract answered in Dart over bdk-wasm
/// (web/web_onchain_plugin.dart).
library;

export 'onchain_transport_native.dart'
    if (dart.library.js_interop) 'web/web_onchain_plugin.dart'
    show platformOnchainTransport;
