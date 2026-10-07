// lib/helpers/scanned_address.dart
//
// The Scan button on a typed-recipient field. Every such field opens the
// same smart scanner the bitcoin send uses (camera, Gallery and Paste,
// with its own camera-permission handling) in return-value mode, and
// reduces what comes back to the bare address the field validates.
//
// Nothing scanned is ever sent to analytics from here: the payload is
// an address, and addresses never leave the device in an event.

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/helpers/common_operation_methods.dart'
    show stripBitcoinAddress;

/// Open the smart scanner in return-value mode and hand back the raw
/// scanned (or gallery-decoded, or pasted) string, trimmed. Null when the
/// person closed the scanner without a code.
Future<String?> scanRecipientRaw(BuildContext context) async {
  final result = await context.pushNamed<String>(
    'smartScanner',
    extra: const {'returnRaw': true},
  );
  final scanned = result?.trim() ?? '';
  return scanned.isEmpty ? null : scanned;
}

/// URI schemes whose path is the recipient address itself. `bitcoin:` is
/// handled by [stripBitcoinAddress], the same reduction the bitcoin send
/// applies; `lightning:` is deliberately absent, because an invoice is
/// not an address and must stay whole so a field that takes addresses
/// refuses it.
const Set<String> _kAddressSchemes = {
  'spark',
  'ethereum',
  'solana',
  'tron',
  'litecoin',
  'zcash',
  'xrp',
  'xrpl',
  'ripple',
  'ton',
};

final RegExp _scheme =
    RegExp(r'^([a-z][a-z0-9+.-]*):(//)?', caseSensitive: false);

/// Reduce a scanned or pasted payment URI to the bare address, the way
/// the bitcoin send reduces `bitcoin:bc1…?amount=…`:
///
///  * `bitcoin:` — [stripBitcoinAddress] (scheme and BIP21 query).
///  * `spark:`, `solana:`, `tron:`, `litecoin:`, `zcash:`, XRP and TON
///    schemes — the scheme and any `?query` go, the address stays.
///  * `ethereum:` (EIP-681) — the `pay-` prefix, `@chainId` and query go.
///    An ERC-20 `…/transfer?address=0x…` request names the TOKEN CONTRACT
///    as its target, so the recipient is the `address` parameter, never
///    the target; a transfer without one, or any other function call, is
///    returned whole so the field's validation refuses it.
///
/// Anything else (a bare address, an invoice, an unknown scheme) comes
/// back trimmed and otherwise untouched: the field's own chain check is
/// the gate, and a wrong-network code fails it exactly as a paste would.
String bareRecipientAddress(String raw) {
  final input = raw.trim();
  if (input.toLowerCase().startsWith('bitcoin:')) {
    return stripBitcoinAddress(input);
  }
  final match = _scheme.firstMatch(input);
  if (match == null) return input;
  final scheme = match.group(1)!.toLowerCase();
  if (!_kAddressSchemes.contains(scheme)) return input;

  var rest = input.substring(match.end);
  String? query;
  final q = rest.indexOf('?');
  if (q != -1) {
    query = rest.substring(q + 1);
    rest = rest.substring(0, q);
  }

  if (scheme == 'ton') {
    // ton://transfer/<address>?amount=…
    if (rest.toLowerCase().startsWith('transfer/')) {
      rest = rest.substring('transfer/'.length);
    }
    return rest.trim();
  }

  if (scheme == 'ethereum') {
    if (rest.toLowerCase().startsWith('pay-')) rest = rest.substring(4);
    String? function;
    final slash = rest.indexOf('/');
    if (slash != -1) {
      function = rest.substring(slash + 1);
      rest = rest.substring(0, slash);
    }
    final at = rest.indexOf('@');
    if (at != -1) rest = rest.substring(0, at);
    if (function != null) {
      if (function.toLowerCase() != 'transfer' || query == null) return input;
      final Map<String, String> params;
      try {
        params = Uri.splitQueryString(query);
      } on FormatException {
        return input;
      }
      final to = params['address']?.trim() ?? '';
      return to.isEmpty ? input : to;
    }
    return rest.trim();
  }

  return rest.trim();
}

/// For the bitcoin send (`ConfirmSend`), whose bitcoin, Lightning and
/// Spark parsing must not change: only a cross-chain payment URI
/// (`ethereum:`, `solana:`, `tron:`, `litecoin:`, `zcash:`, XRP, TON) is
/// reduced with [bareRecipientAddress]. Everything else, including a
/// `bitcoin:` BIP21 with its amount and `lightning=` rail, a `spark:`
/// payload, a `lightning:` invoice and any bare address or invoice, is
/// returned exactly as given (trimmed) for the send's own parser.
String bareCrossChainRecipient(String raw) {
  final input = raw.trim();
  final match = _scheme.firstMatch(input);
  if (match == null) return input;
  final scheme = match.group(1)!.toLowerCase();
  if (scheme == 'spark' || !_kAddressSchemes.contains(scheme)) return input;
  return bareRecipientAddress(input);
}

/// EIP-155 chain ids of the EVM networks a payment request may name,
/// mapped to the Orchestra chain slugs the send tables key on. Only ids
/// this table knows can steer a send; an id it does not know is a network
/// the app cannot route to, never "any EVM chain".
const Map<int, String> kEvmChainIdSlugs = {
  1: 'ethereum',
  10: 'optimism',
  56: 'bsc',
  137: 'polygon',
  143: 'monad',
  999: 'hyperevm',
  1329: 'sei',
  8453: 'base',
  9745: 'plasma',
  42161: 'arbitrum',
  43114: 'avalanche',
};

/// The EIP-155 chain id an `ethereum:` payment request names with
/// `@chainId` (decimal or `0x` hex), or null when [raw] is not such a
/// request or names none.
///
/// `ethereum:0xabc…@8453` and `ethereum:pay-0xUSDC…@42161/transfer?address=…`
/// both carry one; a bare address carries none.
int? evmPaymentChainId(String raw) {
  final input = raw.trim();
  final match = _scheme.firstMatch(input);
  if (match == null || match.group(1)!.toLowerCase() != 'ethereum') {
    return null;
  }
  var rest = input.substring(match.end);
  for (final stop in const ['/', '?']) {
    final i = rest.indexOf(stop);
    if (i != -1) rest = rest.substring(0, i);
  }
  final at = rest.indexOf('@');
  if (at == -1) return null;
  final id = rest.substring(at + 1).trim();
  if (id.isEmpty) return null;
  if (id.toLowerCase().startsWith('0x')) {
    return int.tryParse(id.substring(2), radix: 16);
  }
  return int.tryParse(id);
}
