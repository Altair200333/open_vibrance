import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/widgets/constants.dart';

enum IndicatorState { idle, hovered, recording, transcribing, expanded }

/// A circular indicator widget that changes appearance based on [IndicatorState].
class DotIndicator extends StatelessWidget {
  final IndicatorState state;
  final VoidCallback onTap;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
  final PointerHoverEventListener onHover;

  const DotIndicator({
    Key? key,
    required this.state,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
    required this.onHover,
  }) : super(key: key);

  double get _indicatorDotWidth {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.transcribing:
      case IndicatorState.expanded:
        return kDotSize;
      case IndicatorState.hovered:
        return kDotSize * 2.5;
      case IndicatorState.idle:
      default:
        return kDotSize * 2;
    }
  }

  double get _indicatorDotHeight {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.transcribing:
      case IndicatorState.expanded:
      case IndicatorState.hovered:
        return kDotSize;
      case IndicatorState.idle:
      default:
        return kDotSize * 0.5;
    }
  }

  BoxDecoration get _indicatorDotDecoration {
    switch (state) {
      case IndicatorState.recording:
        return BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: Colors.white, width: 2),
        );
      case IndicatorState.transcribing:
        return BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: Colors.blue, width: 2),
        );
      case IndicatorState.expanded:
        return BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: Colors.white, width: 2),
        );
      case IndicatorState.hovered:
        return BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(5),
        );
      case IndicatorState.idle:
      default:
        return BoxDecoration(
          color: Colors.grey.withAlpha(120),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white70, width: 1.5),
        );
    }
  }

  Widget? get _indicatorDotContent {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.transcribing:
        return null;
      case IndicatorState.expanded:
        return Icon(Icons.close, color: Colors.white, size: kDotSize * 0.65);
      case IndicatorState.hovered:
      case IndicatorState.idle:
      default:
        return AnimatedOpacity(
          opacity: state == IndicatorState.hovered ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const count = 3;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 4,
                children: List.generate(count, (index) {
                  final size =
                      state == IndicatorState.hovered
                          ? kDotSize * 0.25
                          : kDotSize * 0.1;
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: onEnter,
        onExit: onExit,
        onHover: onHover,
        child: SizedBox(
          width: kDotSize * 2.5,
          height: kDotSize,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOutCubic,
              width: _indicatorDotWidth,
              height: _indicatorDotHeight,
              decoration: _indicatorDotDecoration,
              child: _indicatorDotContent,
            ),
          ),
        ),
      ),
    );
  }
}
