/// The browser's user agent string on the web; null on the phones.
library;

import 'browser_agent_native.dart'
    if (dart.library.js_interop) 'browser_agent_web.dart' as impl;

String? browserUserAgent() => impl.userAgent();
