/// The Breez SDK's browser databases for one storage directory.
///
/// On iOS and Android the SDK keeps a wallet's data in the folder
/// `breez_<walletId>` in the app's documents, and removing the wallet
/// deletes that folder. In a browser the same name is only a prefix: the
/// SDK opens IndexedDB databases named from it (its own storage and a
/// `-tree` store). [deleteBreezWebStorage] deletes exactly those, for one
/// storage directory, and nothing else.
///
/// Native never calls this: it is a no-op there and call sites ask
/// `kIsWeb` first. Callers make sure no SDK handle on that directory is
/// running before they call it.
library;

import 'breez_web_storage_native.dart'
    if (dart.library.js_interop) 'breez_web_storage_web.dart' as impl;

/// Whether the IndexedDB database [name] belongs to [storageDir]: the
/// directory name itself, or the directory name followed by a separator
/// (`/` for the SDK's sub-paths, `-` for its tree store). Another
/// wallet's directory never matches: its id differs before the separator.
bool isBreezDatabaseFor(String name, String storageDir) {
  if (storageDir.isEmpty) return false;
  if (name == storageDir) return true;
  if (!name.startsWith(storageDir)) return false;
  final next = name[storageDir.length];
  return next == '/' || name.startsWith('$storageDir-tree');
}

/// Deletes the SDK's browser databases for [storageDir]. Returns how many
/// were deleted; never throws.
Future<int> deleteBreezWebStorage(String storageDir) =>
    impl.deleteBreezWebStorage(storageDir);
