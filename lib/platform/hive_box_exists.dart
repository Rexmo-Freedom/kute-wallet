/// Whether a Hive box is stored on this device, without holding it open.
///
/// On the web `Hive.boxExists` opens the box's IndexedDB database to look
/// and never closes that connection. A database with an open connection
/// cannot be deleted: `indexedDB.deleteDatabase` waits until the
/// connection closes, which for a leaked one is never. The boot's
/// first-install check on `settings` did exactly that, so the device wipe
/// (Forgot PIN, the sixth wrong PIN) waited for good on the `settings`
/// box: the keys were gone, the wallet list stayed, and the next start
/// asked to restore wallets that had no keys. The web check here closes
/// what it opens. On the phones this is `Hive.boxExists`, unchanged.
library;

import 'hive_box_exists_native.dart'
    if (dart.library.js_interop) 'hive_box_exists_web.dart' as impl;

Future<bool> hiveBoxExists(String name) => impl.boxExists(name);
