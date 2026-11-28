/// Native: no `<img>` element. Never reached (every call site asks kIsWeb
/// first); answers "not here".
library;

import 'package:flutter/widgets.dart';

import 'web_image.dart' show WebImageLoad;

Future<WebImageLoad?> loadImage(String url, Duration timeout) =>
    Future.value(null);

Widget imgView(String url, BoxFit fit, BorderRadius? radius) =>
    const SizedBox.shrink();
