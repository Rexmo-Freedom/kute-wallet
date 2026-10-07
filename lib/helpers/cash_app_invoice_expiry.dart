/// Read-only BOLT11 metadata for displaying an old purchase's payment window.
/// This does not verify a payment or decide whether funds settled. Only the
/// provider's order status may complete, fail or refund an order.
DateTime? cashAppInvoiceExpiry(String invoice) {
  var value = invoice
      .trim()
      .replaceFirst(RegExp(r'^lightning:', caseSensitive: false), '');
  if (value.length > 12000 ||
      (value != value.toLowerCase() && value != value.toUpperCase())) {
    return null;
  }
  value = value.toLowerCase();
  final split = value.lastIndexOf('1');
  if (split < 4) return null;
  final hrp = value.substring(0, split);
  if (!RegExp(r'^ln(bc|tb|tbs|bcrt)[0-9]*[munp]?$').hasMatch(hrp)) return null;
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final data =
      value.substring(split + 1).split('').map(alphabet.indexOf).toList();
  if (data.length < 7 + 104 + 6 || data.any((word) => word < 0)) return null;
  var checksum = 1;
  const generators = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3
  ];
  for (final word in [
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
    ...data,
  ]) {
    final top = checksum >> 25;
    checksum = ((checksum & 0x1ffffff) << 5) ^ word;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) != 0) checksum ^= generators[i];
    }
  }
  if (checksum != 1) return null;
  int number(Iterable<int> words) => words.fold(0, (n, word) => n * 32 + word);
  final created = number(data.take(7));
  var expiry = 3600; // BOLT11 default when the x tag is absent.
  var seenExpiry = false;
  final end = data.length - 104 - 6;
  for (var i = 7; i < end;) {
    if (i + 3 > end) return null;
    final tag = data[i];
    final length = data[i + 1] * 32 + data[i + 2];
    i += 3;
    if (i + length > end) return null;
    if (tag == 6) {
      if (seenExpiry || length > 7) return null;
      seenExpiry = true;
      expiry = number(data.sublist(i, i + length));
    }
    i += length;
  }
  return DateTime.fromMillisecondsSinceEpoch((created + expiry) * 1000,
      isUtc: true);
}
