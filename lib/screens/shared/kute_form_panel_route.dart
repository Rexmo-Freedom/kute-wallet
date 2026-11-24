// lib/screens/shared/kute_form_panel_route.dart
//
// A SLIP'S ADVANCED PAGE ON A LAPTOP (round three; founder, 25 November
// 2026: "it must be all occupying full screen when we can"). The Advanced
// pages of the tickets (the order ticket, the close, the trailing stop,
// the bet slip, the sell, the Ledger sell) are one phone column of fields
// with nothing beside them to show: on EXPANDED they open as the shared
// panel at a page's height (kute_dialog.dart, [KuteDialogRoute.fill])
// over the dimmed page they came from, the market and its chart still in
// view, their primary button drawn inside the panel's foot, exactly as
// the money flows do ([kuteMoneyFlowRoute]). Escape and a click outside
// go through the page's own PopScope, as its back button does; the page's
// back button is its close, so the panel draws no second X.
//
// Elsewhere the full-screen page it has always been, in a centred column
// from MEDIUM up ([KuteFormColumn]), with the same [RouteSettings] (the
// slips find each other's routes by name).

import 'package:flutter/material.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/kute_dialog.dart';
import 'package:kute/theme/app_theme.dart';

/// The route an Advanced page is pushed with (see the file header).
Route<T> kuteFormPanelRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  if (kuteWindowIsExpanded(context)) {
    return KuteDialogRoute<T>(
      settings: settings,
      fill: true,
      color: context.colors.background,
      builder: (ctx) => Stack(
        fit: StackFit.passthrough,
        children: [
          builder(ctx),
          // The page's own back button closes it: no panel X beside it.
          const KuteDialogCloseMark(child: SizedBox.shrink()),
        ],
      ),
    );
  }
  return MaterialPageRoute<T>(
    fullscreenDialog: true,
    settings: settings,
    // A centred column from MEDIUM up (kute_wide_frames.dart).
    builder: (ctx) => KuteFormColumn(child: builder(ctx)),
  );
}
