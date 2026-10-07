/// Normalizes provider image URLs without encoding existing percent escapes a
/// second time. Gamma team logos can contain either spaces or `%20` already.
String? polymarketArtworkUrl(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.toString();
}

/// Only provider-supplied artwork is considered. Optimized image objects are
/// present on some Gamma payloads when the ordinary image fields are empty.
String? polymarketArtworkFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  for (final field in ['image', 'icon', 'groupItemImage', 'logo']) {
    final url = polymarketArtworkUrl(json[field]);
    if (url != null) return url;
  }
  for (final field in ['imageOptimized', 'iconOptimized']) {
    final image = json[field];
    if (image is! Map) continue;
    for (final key in ['imageUrlOptimized', 'imageUrlSource']) {
      final url = polymarketArtworkUrl(image[key]);
      if (url != null) return url;
    }
  }
  return null;
}
