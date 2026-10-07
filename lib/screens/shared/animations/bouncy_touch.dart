import 'package:flutter/material.dart';

class BouncyTouch extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleTo;
  final Duration duration;

  const BouncyTouch({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleTo = 0.96,
    this.duration = const Duration(milliseconds: 100),
  });

  @override
  State<BouncyTouch> createState() => _BouncyTouchState();
}

class _BouncyTouchState extends State<BouncyTouch> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnim = Tween<double>(begin: 1.0, end: widget.scaleTo).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTapDown: (_) {
        if (!reduceMotion) _controller.forward();
      },
      onTapUp: (_) {
        if (!reduceMotion) _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        if (!reduceMotion) _controller.reverse();
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(scale: _scaleAnim.value, child: widget.child),
      ),
    );
  }
}
