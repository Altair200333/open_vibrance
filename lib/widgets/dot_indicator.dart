import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/widgets/constants.dart';

enum IndicatorState { idle, hovered, recording, transcribing, expanded }

const double kDotIndicatorMinScale = 0.4;
const double kDotIndicatorMaxScale = 1;
const double kDotIndicatorMinVolumeDb = -60.0;
const double kDotIndicatorMaxVolumeDb = 0.0;

/// A circular indicator widget that changes appearance based on [IndicatorState].
class DotIndicator extends StatefulWidget {
  final IndicatorState state;
  final VoidCallback onTap;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
  final PointerHoverEventListener onHover;
  final double volume;

  const DotIndicator({
    super.key,
    required this.state,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
    required this.onHover,
    required this.volume,
  });

  @override
  _DotIndicatorState createState() => _DotIndicatorState();

  double _getNormalizedVolume() {
    final normalized =
        (volume - kDotIndicatorMinVolumeDb) /
        (kDotIndicatorMaxVolumeDb - kDotIndicatorMinVolumeDb);
    return normalized.clamp(0.0, 1.0);
  }

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
        return kDotSize;
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
        var borderW = 1 + _getNormalizedVolume() * 2;
        return BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: Colors.white, width: borderW),
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
      default:
        return null;
    }
  }
}

class _DotIndicatorState extends State<DotIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _colorAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.white,
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    if (widget.state == IndicatorState.transcribing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DotIndicator old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      if (widget.state == IndicatorState.transcribing) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildIndicator(double width, double height) {
    if (widget.state == IndicatorState.transcribing) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: _colorAnimation.value,
                borderRadius: BorderRadius.circular(kDotSize),
                border: Border.all(color: Colors.blue, width: 2),
              ),
            ),
          );
        },
      );
    } else if (widget.state == IndicatorState.recording) {
      // normalize volume to 0.0-1.0 based on dB range
      final normalized = widget._getNormalizedVolume();

      // map normalized to scale range
      final sizeScale =
          kDotIndicatorMinScale +
          normalized * (kDotIndicatorMaxScale - kDotIndicatorMinScale);

      print('sizeScale: $sizeScale, width: $width, height: $height');
      return AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        width: width * sizeScale,
        height: height * sizeScale,
        decoration: widget._indicatorDotDecoration,
      );
    } else {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOutCubic,
        width: width,
        height: height,
        decoration: widget._indicatorDotDecoration,
        child: widget._indicatorDotContent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = widget._indicatorDotWidth;
    final height = widget._indicatorDotHeight;
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: widget.onEnter,
        onExit: widget.onExit,
        onHover: widget.onHover,
        child: SizedBox(
          width: kDotSize * 2.5,
          height: kDotSize,
          child: Center(child: _buildIndicator(width, height)),
        ),
      ),
    );
  }
}
