// lib/screens/hyperliquid/components/hl_tick_price.dart
//
// A live price that FLASHES the up / down colour when a tick moves it and
// settles back to its own colour. The market detail header used to hold
// the last tick's colour until the next tick, so a quiet market could sit
// red beside a green 24h change (or the other way round) and read as a
// contradiction. The flash keeps the "it just moved" cue; the resting
// price is the primary text colour and the 24h change alone carries the
// up / down colour.

import 'package:flutter/material.dart';

import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

class HlTickPrice extends StatefulWidget {
  /// The price the flash follows; a change of it is a tick.
  final double price;

  /// The formatted price ([formatHlPrice]).
  final String text;

  /// The resting style; its colour is what the flash returns to.
  final TextStyle style;

  const HlTickPrice({
    super.key,
    required this.price,
    required this.text,
    required this.style,
  });

  /// How long a tick's colour takes to fade back to the resting colour.
  static const flashDuration = Duration(milliseconds: 900);

  @override
  State<HlTickPrice> createState() => _HlTickPriceState();
}

class _HlTickPriceState extends State<HlTickPrice>
    with SingleTickerProviderStateMixin {
  // 0 = the flash colour, 1 = settled on the resting colour.
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: HlTickPrice.flashDuration,
    value: 1,
  );
  Color? _flash;

  @override
  void didUpdateWidget(covariant HlTickPrice old) {
    super.didUpdateWidget(old);
    // Only a move between two real prices is a tick: the first price to
    // arrive has nothing to be up or down from.
    if (old.price > 0 && widget.price > 0 && widget.price != old.price) {
      _flash = widget.price > old.price
          ? AppColors.marketUp
          : AppColors.marketDown;
      // The flash is a transition: under Reduce Motion (and on a screen a
      // slip covers, see KuteStillWhenCovered) the price is drawn in its
      // resting colour at once, like the digits' roll.
      if (kuteReduceMotion(context)) {
        _settle.value = 1;
      } else {
        _settle.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settle,
      builder: (context, _) {
        final flash = _flash;
        final color = flash == null || _settle.isCompleted
            ? widget.style.color
            // Hold the colour for the first half, then fade it out.
            : Color.lerp(flash, widget.style.color,
                Curves.easeOut.transform(((_settle.value - 0.5) * 2).clamp(0.0, 1.0)));
        return RollingNumberText(
          text: widget.text,
          style: widget.style.copyWith(color: color),
        );
      },
    );
  }
}
