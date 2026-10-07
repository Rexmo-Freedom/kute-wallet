// lib/screens/bank/bank_screen.dart
//
// The Bank tab — a real shell branch (side-swipeable like Home / Trading,
// persistent top nav above it), deliberately empty while banking ships:
// just "Coming soon" centered. The tab exists so the destination is
// discoverable now and the swipe order settles before the feature lands.

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class BankScreen extends StatefulWidget {
  const BankScreen({super.key});

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  @override
  void initState() {
    super.initState();
    TrackingService.screenView('bank_coming_soon');
    // Coming-soon funnel entry (same event every coming-soon surface
    // uses). Once per mount: the branch builds lazily on first visit.
    TrackingService.comingSoonViewed(feature: 'bank');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Same page ground the other shell branches paint — a flat
        // c.background here read as a hole in the tab row on dark.
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Center(
            child: Text(
              context.l10n.comingSoon2,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
