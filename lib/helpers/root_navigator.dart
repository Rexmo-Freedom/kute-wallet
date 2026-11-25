// lib/helpers/root_navigator.dart
//
// The app's ROOT navigator key, in a file of its own so a layer that draws
// over everything (the Sal toast, sal_toast.dart) or a service with no
// widget of its own (a standing order finishing minutes after its slip
// closed) can reach the root navigator and its overlay without importing
// the router. AppRouter hands this same key to its GoRouter
// (app_router.dart, AppRouter.rootNavigatorKey).

import 'package:flutter/widgets.dart';

/// The root navigator's key (AppRouter.rootNavigatorKey is this key).
final GlobalKey<NavigatorState> kuteRootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// A context under the root navigator to open a sheet from when the
/// caller's own is gone: the root navigator's, else [fallback] when it is
/// still mounted (a test's app without the key), else null.
BuildContext? kuteRootContext([BuildContext? fallback]) {
  final root = kuteRootNavigatorKey.currentContext;
  if (root != null && root.mounted) return root;
  if (fallback != null && fallback.mounted) return fallback;
  return null;
}
