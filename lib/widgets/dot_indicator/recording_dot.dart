import 'package:flutter/material.dart';
import 'package:open_vibrance/widgets/constants.dart';

class RecordingDot extends StatelessWidget {
  final double scale;
  final BoxDecoration decoration;

  const RecordingDot({
    super.key,
    required this.scale,
    required this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final size = kDotSize;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      width: size * scale,
      height: size * scale,
      decoration: decoration,
    );
  }
}
