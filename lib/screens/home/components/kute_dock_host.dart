import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_blur.dart';

/// Home's dock mount, shared by every screen that floats a
/// [KuteBottomActionBar] over scrolling content.
///
/// The dock is a bottom-pinned sibling of [body] inside a Stack. A short
/// frosted band (dock height + 12.h, sigma 4 blur, same in light and dark,
/// no gradient scrim) is painted behind it so content frosts as it passes
/// underneath. Both are omitted while the keyboard is up.
///
/// [body] sees `MediaQuery.padding.bottom` equal to the measured dock
/// clearance (dock + 12.h), so list padding written as
/// `x.h + MediaQuery.paddingOf(context).bottom` clears the dock the same
/// way it did under a `Scaffold.bottomNavigationBar` mount.
///
/// Put that clearance INSIDE the scroll view ([kuteDockScrollClearance]),
/// never as padding around it: a body padded short of the dock stops
/// above the band, nothing passes under it, and the dock reads as an
/// opaque bar instead of glass.
class KuteDockHost extends StatefulWidget {
  final Widget body;

  /// Builds the dock. The callback must be forwarded to the dock's
  /// `onHeightChanged` so the frost band and clearance track its real size.
  final Widget Function(ValueChanged<double> onHeightChanged) dockBuilder;

  const KuteDockHost({
    super.key,
    required this.body,
    required this.dockBuilder,
  });

  @override
  State<KuteDockHost> createState() => _KuteDockHostState();
}

class _KuteDockHostState extends State<KuteDockHost> {
  double _dockHeight = 0;

  void _onDockHeightChanged(double height) {
    if (mounted && (_dockHeight - height).abs() > 0.5) {
      setState(() => _dockHeight = height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboardUp = mq.viewInsets.bottom > 0;
    final band = _dockHeight + 12.h;

    return Stack(
      alignment: Alignment.bottomCenter,
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding
                .copyWith(bottom: keyboardUp ? mq.padding.bottom : band),
          ),
          child: widget.body,
        ),
        if (!keyboardUp) ...[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: band,
            child: IgnorePointer(
              child: ClipRect(
                child: KuteBlur(
                  sigmaX: 4.0,
                  sigmaY: 4.0,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: widget.dockBuilder(_onDockHeightChanged),
          ),
        ],
      ],
    );
  }
}

/// Bottom padding for a scroll view inside a [KuteDockHost]'s body: the
/// host's dock clearance (dock + 12.h, reported as the bottom padding)
/// plus Home's 12.h. The scroll view itself runs to the bottom of the
/// screen, so its rows pass under the frost band and the dock; only its
/// last row stops clear of them. Outside a host it is the safe area plus
/// 12.h.
double kuteDockScrollClearance(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom + 12.h;

/// A view that does not scroll (an empty state, a centred note) inside a
/// [KuteDockHost]'s body, kept clear of the dock so it centres in what is
/// visible above it.
class KuteDockClearance extends StatelessWidget {
  final Widget child;

  const KuteDockClearance({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: kuteDockScrollClearance(context)),
        child: child,
      );
}
