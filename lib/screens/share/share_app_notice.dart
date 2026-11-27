// lib/screens/share/share_app_notice.dart
//
// The notice over a shared market's guest page (share_guest_screen.dart).
// Filled in by the "Open in the app" step; a plain pass-through until then.

import 'package:flutter/widgets.dart';

class ShareAppNoticeHost extends StatelessWidget {
  const ShareAppNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
