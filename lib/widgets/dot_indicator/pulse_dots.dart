import 'package:flutter/material.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'dart:math' as math;

class PulseDots extends StatefulWidget {
  final int count;

  final double dotFraction;

  final double spacing;

  final Duration duration;

  /// Stagger interval between each dot's animation start.
  final double staggerInterval;

  final Curve curve;

  const PulseDots({
    super.key,
    this.count = 3,
    this.dotFraction = 0.3,
    this.spacing = 2.0,
    this.duration = const Duration(milliseconds: 800),
    this.staggerInterval = 0.2,
    this.curve = Curves.easeInOut,
  });

  @override
  _PulseDotsState createState() => _PulseDotsState();
}

class _PulseDotsState extends State<PulseDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _dotAnimations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);

    _dotAnimations = List.generate(widget.count, (i) {
      final start = i * widget.staggerInterval;
      final end = math.min(start + (1 - widget.staggerInterval), 1.0);
      return Tween<double>(begin: 0.7, end: 1.3).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end, curve: widget.curve),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(widget.count, (i) {
            final dotSize = kDotSize * widget.dotFraction;
            return Transform.scale(
              scale: _dotAnimations[i].value,
              child: Container(
                width: dotSize,
                height: dotSize,
                margin: EdgeInsets.symmetric(horizontal: widget.spacing),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
