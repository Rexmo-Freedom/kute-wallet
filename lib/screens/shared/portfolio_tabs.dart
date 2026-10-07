import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';

/// The Portfolio's tabs as both the spending wallet and the Ledger show
/// them: Open, Orders, Activity, Statistics.
const kPortfolioTabKeys = ['open', 'orders', 'activity', 'statistics'];

/// Portfolio views use the same pills as the Home Balance / Price strip and
/// the category rows ([KutePillTabs]). Stays in sync with the enclosing
/// [DefaultTabController].
class PortfolioTabs extends StatelessWidget {
  const PortfolioTabs({super.key, required this.tabs, this.keys = kPortfolioTabKeys});

  final List<(String, IconData)> tabs;

  /// The analytics value of each tab, in [tabs] order. Fixed English keys,
  /// so a tab reads the same in PostHog in every app language.
  final List<String> keys;

  static double height(BuildContext context) => 44.h;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SizedBox(
        height: height(context),
        child: Center(
          child: KutePillTabs(
            items: [
              for (final (label, icon) in tabs)
                KutePillItem(label: label, icon: icon),
            ],
            selectedIndex: controller.index,
            onTap: (i) {
              if (i != controller.index && i < tabs.length) {
                TrackingService.track('portfolio_tab_changed',
                    params: {'tab': i < keys.length ? keys[i] : 'tab_$i'});
              }
              controller.animateTo(i);
            },
          ),
        ),
      ),
    );
  }
}

/// [PortfolioTabs] as a PINNED sliver header.
///
/// The portfolio screens put the strip in a [NestedScrollView]'s header,
/// where it scrolled away with the balance: once a list was a screen
/// deep there was no way to change tab without scrolling all the way
/// back, and the shared outer offset carried over to the next tab, which
/// is what made the scrolling read as broken. Pinned, the strip stays
/// put and each tab keeps its own offset.
class PortfolioTabsSliver extends StatelessWidget {
  const PortfolioTabsSliver({super.key, required this.tabs});

  final List<(String, IconData)> tabs;

  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
        pinned: true,
        delegate: _PortfolioTabsDelegate(
          tabs: tabs,
          extent: PortfolioTabs.height(context) + 12.h,
          background: Theme.of(context).scaffoldBackgroundColor,
        ),
      );
}

class _PortfolioTabsDelegate extends SliverPersistentHeaderDelegate {
  _PortfolioTabsDelegate(
      {required this.tabs, required this.extent, required this.background});

  final List<(String, IconData)> tabs;
  final double extent;
  final Color background;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        color: background,
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
        child: PortfolioTabs(tabs: tabs),
      );

  @override
  bool shouldRebuild(_PortfolioTabsDelegate old) =>
      old.extent != extent ||
      old.background != background ||
      old.tabs.length != tabs.length ||
      !_sameLabels(old.tabs, tabs);

  static bool _sameLabels(
      List<(String, IconData)> a, List<(String, IconData)> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].$1 != b[i].$1) return false;
    }
    return true;
  }
}
