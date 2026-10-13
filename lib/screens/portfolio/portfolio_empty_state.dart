import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance;
import 'package:kute/screens/shared/no_activity_state.dart';

/// An empty Portfolio tab (Open, Orders, Activity, Statistics): the app's
/// empty state ([NoActivityState], Sal over the headline and a rotating
/// tagline, as Home's "No activity yet") with the tab's own headline,
/// centred clear of the dock. Informational only: browsing stays on the
/// product pages. Sal settles after a few cycles, as on every surface a
/// person may leave open.
class PortfolioEmptyState extends StatelessWidget {
  const PortfolioEmptyState(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => KuteDockClearance(
        child: Center(
          child: SingleChildScrollView(
            child: NoActivityState(title: title, cycles: 3),
          ),
        ),
      );
}
