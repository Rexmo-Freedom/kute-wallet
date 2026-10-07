import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kute/services/secure/keychain_local.dart';

/// Clipboard access used by [SeedClipboard], replaceable in tests.
abstract class ClipboardAccess {
  Future<void> write(String text);

  /// Writes a secret (a recovery phrase or a private key) marked as
  /// sensitive where the platform supports it: iOS keeps it off Universal
  /// Clipboard and expires it, Android hides it from clipboard previews.
  /// Falls back to [write] when the platform cannot.
  Future<void> writeSensitive(String text);

  Future<String?> read();

  /// A counter that changes whenever anything is copied, read without
  /// touching the clipboard content. Null when the platform has none.
  Future<int?> changeCount();
}

class SystemClipboardAccess implements ClipboardAccess {
  const SystemClipboardAccess({this.platform});

  final TargetPlatform? platform;

  /// How long iOS keeps a sensitive copy before removing it itself,
  /// matching [SeedClipboard.clearAfter]'s default.
  static const int sensitiveExpirySeconds = 60;

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  /// iOS: `UIPasteboard.setItems` with `.localOnly` and an
  /// `.expirationDate` [sensitiveExpirySeconds] out. Android:
  /// `ClipDescription.EXTRA_IS_SENSITIVE`. Both over the security channel;
  /// any failure (an older native build, an unsupported platform) copies
  /// the plain way so the person can still paste their phrase.
  @override
  Future<void> writeSensitive(String text) async {
    final p = platform ?? defaultTargetPlatform;
    if (p == TargetPlatform.iOS || p == TargetPlatform.android) {
      try {
        await KeychainLocal.channel.invokeMethod<void>('copySensitive', {
          'text': text,
          'expirySeconds': sensitiveExpirySeconds,
        });
        return;
      } catch (_) {
        // Fall through to the plain copy.
      }
    }
    await write(text);
  }

  @override
  Future<String?> read() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  /// iOS only: `UIPasteboard.changeCount`. Reading the pasteboard content
  /// after another app copied would show the iOS paste permission prompt.
  @override
  Future<int?> changeCount() async {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return null;
    try {
      return await KeychainLocal.channel.invokeMethod<int>(
        'pasteboardChangeCount',
      );
    } catch (_) {
      return null;
    }
  }
}

/// Copies a recovery phrase and later clears the clipboard only if it still
/// holds that phrase, so anything the user copied afterwards survives.
///
/// The check runs [clearAfter] the copy and when the owner is disposed. While
/// Kute is not in the foreground it waits for the next resume, because
/// Android does not let a background app read the clipboard.
class SeedClipboard {
  SeedClipboard({
    ClipboardAccess? access,
    this.clearAfter = const Duration(seconds: 60),
  }) : _access = access ?? const SystemClipboardAccess();

  final ClipboardAccess _access;
  final Duration clearAfter;

  String? _copied;
  int? _changeCount;
  Timer? _timer;
  AppLifecycleListener? _resumeListener;
  bool _disposed = false;
  Future<void> _copyTail = Future<void>.value();

  bool get hasPendingCopy => _copied != null;

  Future<void> copy(String value) {
    final operation = _copyTail.then((_) async {
      if (_disposed) return;
      _reset();
      await _access.writeSensitive(value);
      final count = await _access.changeCount();
      _copied = value;
      _changeCount = count;
      // The native write may finish after the screen has gone away. It
      // still needs clearing immediately (or on the next foreground resume).
      if (_disposed) {
        _scheduleClear();
      } else {
        _timer = Timer(clearAfter, _scheduleClear);
      }
    });
    // Serialize copies so an older native completion cannot replace a
    // newer copy's cleanup state. A failed write must not poison the queue.
    _copyTail = operation.catchError((Object _) {});
    return operation;
  }

  /// Reads the clipboard once for a recovery phrase paste and returns its
  /// text. The text is then held like a copy, so [clearIfUnchanged] (or
  /// [dispose]) removes it only while the clipboard still holds it, guarded
  /// by the same change counter.
  Future<String?> takePaste() async {
    final operation = _copyTail.then((_) async {
      if (_disposed) return null;
      _reset();
      final String? text;
      final int? count;
      try {
        text = await _access.read();
        count = await _access.changeCount();
      } catch (_) {
        return null;
      }
      if (text == null || text.trim().isEmpty) return null;
      _copied = text;
      _changeCount = count;
      return text;
    });
    _copyTail = operation.then((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Drops a pasted text that turned out not to be a recovery phrase, so
  /// nothing later clears what the user copied.
  void forget() => _reset();

  /// Stops the timer and clears a pending copy that is still on the
  /// clipboard. Never reads the clipboard when nothing was copied.
  void dispose() {
    _disposed = true;
    if (_copied == null) {
      _reset();
      return;
    }
    _scheduleClear();
  }

  /// Clears the clipboard when it still holds the copied phrase. Returns
  /// true when it cleared.
  Future<bool> clearIfUnchanged() async {
    final copied = _copied;
    final expectedCount = _changeCount;
    _reset();
    if (copied == null) return false;
    try {
      if (expectedCount != null) {
        final count = await _access.changeCount();
        if (count != null) {
          if (count != expectedCount) return false;
          await _access.write('');
          return true;
        }
      }
      if (await _access.read() != copied) return false;
      await _access.write('');
      return true;
    } catch (_) {
      return false;
    }
  }

  void _scheduleClear() {
    _timer?.cancel();
    _timer = null;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) {
      unawaited(clearIfUnchanged());
      return;
    }
    _resumeListener?.dispose();
    _resumeListener = AppLifecycleListener(
      onResume: () => unawaited(clearIfUnchanged()),
    );
  }

  void _reset() {
    _timer?.cancel();
    _timer = null;
    _resumeListener?.dispose();
    _resumeListener = null;
    _copied = null;
    _changeCount = null;
  }
}
