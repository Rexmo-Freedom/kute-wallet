/// Asks the browser to keep this site's storage (`navigator.storage
/// .persist()`), so a wallet held in IndexedDB is not evicted under storage
/// pressure. Safari may still clear script-written storage for a site not
/// visited for a while; the passkey or the backed-up words are the way back.
/// Resolves to whether the browser granted it; false off the web.
library;

import 'storage_persist_native.dart'
    if (dart.library.js_interop) 'storage_persist_web.dart' as impl;

Future<bool> requestPersistentStorage() => impl.requestPersistentStorage();
