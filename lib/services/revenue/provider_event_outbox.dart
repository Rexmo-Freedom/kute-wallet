import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';

enum ProviderEventDelivery { delivered, retryLater, rejected }

/// Accounting delivery is independent of optional product analytics. Entries
/// are bound to the spending identity, including events from its Ledger accounts.
/// No secrets or bearer tokens are persisted here.
class ProviderEventOutbox {
  static Future<Box<String>> _box() =>
      Hive.openBox<String>('provider_event_outbox_v1');
  static bool _flushing = false;

  static Future<bool> enqueue(
      String identity, Map<String, dynamic> body) async {
    try {
      final key = sha256
          .convert(utf8.encode(jsonEncode([
            identity,
            body['provider'],
            body['provider_order_id'],
            body['status'],
            body['source_amount'],
            body['destination_amount'],
          ])))
          .toString();
      final box = await _box();
      await box.put(key, jsonEncode({'identity': identity, 'body': body}));
      await box.flush();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> flush({
    required String identity,
    required Future<ProviderEventDelivery> Function(Map<String, dynamic>) send,
  }) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final box = await _box();
      var count = 0;
      for (final key in box.keys.toList()) {
        final raw = box.get(key);
        if (raw == null) continue;
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        if (entry['identity'] != identity) continue;
        if (++count > 50) break;
        final result =
            await send(Map<String, dynamic>.from(entry['body'] as Map));
        if (result == ProviderEventDelivery.retryLater) break;
        // Keep rejected data for diagnosis/retry without blocking other events.
        if (result == ProviderEventDelivery.rejected) continue;
        // Do not delete a newer value queued while this request was in flight.
        if (box.get(key) == raw) await box.delete(key);
      }
      await box.flush();
    } catch (_) {
      // Retry at the next event, registration, or periodic flush.
    } finally {
      _flushing = false;
    }
  }
}
