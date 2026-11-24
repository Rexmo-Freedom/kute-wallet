// lib/screens/shared/kute_wide_page_parts.dart
//
// Small parts the wallet and referral pages share on EXPANDED (round
// three; founder, 25 November 2026: "it must be all occupying full screen
// when we can"): the width two readable columns take, and the AppBar's
// back button on the page's left gutter (Settings' own way, settings.dart).
// Off EXPANDED none of this applies: the pages build as before.

import 'package:flutter/material.dart';
import 'package:kute/platform/kute_wide_frames.dart';

/// Two columns of rows or cards side by side at their readable widest
/// ([kuteWideColumnMax] each, [kuteWideGap] between): a detail page, a
/// form beside its help.
const double kuteWideTwoColumns = 2 * kuteWideColumnMax + kuteWideGap;

/// An AppBar's leading [back] button on the page's left gutter ([gutter]:
/// the left padding of the page's content), with `leadingWidth:
/// gutter + 40`, `centerTitle: false` and `titleSpacing: 8` beside it.
Widget kuteWideLeading(double gutter, Widget back) => Padding(
      padding: EdgeInsets.only(left: gutter - 2),
      child: Align(alignment: Alignment.centerLeft, child: back),
    );
