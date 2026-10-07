// lib/screens/shared/kute_taglines.dart
//
// Kute's brand-voice taglines — shown on empty states (the home "No
// activity yet" panel, the search prompt, …). The tone is deliberately
// HOPEFUL and builder-minded: it nods to a money system that wasn't built
// for the user, then pivots hard to "the future is yours, and we made the
// money part simple." Past was rigged; future is bright; we build it
// together. (This replaced an earlier, more cynical/doom set.)
//
// [RotatingTagline] is the reusable fade-rotating Text used wherever these
// lines appear, so every surface cycles them the same way.

import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';

/// Positive, aspirational one-liners. Light on Bitcoin-specific lingo —
/// the throughline is "the future is bright, down with the old, these are
/// the financial tools of the new." Empowerment over outrage. Keep each
/// line SHORT (one clause, two at most) and in plain natural English —
/// the earlier three-clause versions read as clunky/translated.
const int kKuteTaglineCount = 12;

/// The [kKuteTaglineCount] taglines in [l10n]'s language, in a fixed order.
List<String> kuteTaglines(AppLocalizations l10n) => [
      l10n.kuteTagline01,
      l10n.kuteTagline02,
      l10n.kuteTagline03,
      l10n.kuteTagline04,
      l10n.kuteTagline05,
      l10n.kuteTagline06,
      l10n.kuteTagline07,
      l10n.kuteTagline08,
      l10n.kuteTagline09,
      l10n.kuteTagline10,
      l10n.kuteTagline11,
      l10n.kuteTagline12,
    ];

/// A fade-rotating tagline line. Cycles [messages] every [interval], cross-
/// fading over [fadeDuration]. Used on empty states so the same gentle
/// rotation appears on home + search + anywhere else.
class RotatingTagline extends StatefulWidget {
  /// Null shows the Kute taglines in the app language.
  final List<String>? messages;
  final TextStyle style;
  final TextAlign textAlign;
  final Duration interval;
  final Duration fadeDuration;

  /// Fixed slot height so rotating between 1- and 2-line messages doesn't
  /// reflow the layout around it. Null lets it size to content.
  final double? height;

  const RotatingTagline({
    super.key,
    required this.style,
    this.messages,
    this.textAlign = TextAlign.center,
    this.interval = const Duration(seconds: 6),
    this.fadeDuration = const Duration(milliseconds: 600),
    this.height,
  });

  @override
  State<RotatingTagline> createState() => _RotatingTaglineState();
}

class _RotatingTaglineState extends State<RotatingTagline>
    with SingleTickerProviderStateMixin {
  int get _count => widget.messages?.length ?? kKuteTaglineCount;
  late final AnimationController _fade;
  late final Animation<double> _anim;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Random-ish start so each open feels different.
    if (_count > 0) {
      _index = DateTime.now().millisecondsSinceEpoch % _count;
    }
    _fade = AnimationController(vsync: this, duration: widget.fadeDuration)
      ..value = 1.0;
    _anim = CurvedAnimation(parent: _fade, curve: Curves.easeInOut);
    _scheduleRotation();
  }

  void _scheduleRotation() {
    if (_count < 2) return;
    Future.delayed(widget.interval, () {
      if (!mounted) return;
      _fade.reverse().then((_) {
        if (!mounted) return;
        setState(
            () => _index = (_index + 1) % _count);
        _fade.forward();
      });
      _scheduleRotation();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final messages = widget.messages ?? kuteTaglines(context.l10n);
    final text = FadeTransition(
      opacity: _anim,
      child: Text(
        messages[_index],
        key: ValueKey(_index),
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
    return widget.height != null
        ? SizedBox(height: widget.height, child: text)
        : text;
  }
}
