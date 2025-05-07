import 'package:flutter/material.dart';
import 'package:open_vibrance/widgets/constants.dart';

/// A row of small fading circles used for the "idle" indicator when hovered.
class IdleDots extends StatelessWidget {
  /// Whether the idle indicator is hovered (controls opacity and dot size).
  final bool isHovered;

  const IdleDots({super.key, required this.isHovered});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isHovered ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const count = 3;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 4,
            children: List.generate(count, (index) {
              final size = isHovered ? kDotSize * 0.25 : kDotSize * 0.1;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: size,
                height: size,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
