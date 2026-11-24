/// Native: there is no browser to class; the apps keep the PIN (see
/// unlock_secret.dart). Never reached off the web.
library;

import 'unlock_secret.dart' show BrowserSignals;

BrowserSignals? readBrowserSignals() => null;
