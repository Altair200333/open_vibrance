import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/widgets/dot_indicator/recording_dot.dart';
import 'package:open_vibrance/widgets/dot_indicator/pulse_dots.dart';
import 'package:open_vibrance/widgets/dot_indicator/idle_dots.dart';
import 'package:open_vibrance/widgets/dot_indicator/error_shake.dart';

enum IndicatorState { idle, recording, transcribing, error, expanded }

const double kDotIndicatorMinScale = 0.4;
const double kDotIndicatorMaxScale = 1;
const double kMinVolumeDb = -60.0;
const double kMaxVolumeDb = 0.0;

/// A circular indicator widget that changes appearance based on [IndicatorState].
class DotIndicator extends StatefulWidget {
  final IndicatorState state;
  final VoidCallback onTap;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
  final PointerHoverEventListener onHover;
  final double volume;
  final bool isHovered;

  const DotIndicator({
    super.key,
    required this.state,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
    required this.onHover,
    required this.volume,
    required this.isHovered,
  });

  @override
  _DotIndicatorState createState() => _DotIndicatorState();

  double _getNormalizedVolume() {
    final normalized = (volume - kMinVolumeDb) / (kMaxVolumeDb - kMinVolumeDb);
    return normalized.clamp(0.0, 1.0);
  }

  double get _indicatorDotWidth {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.expanded:
        return kDotSize;
      case IndicatorState.transcribing:
      case IndicatorState.error:
        return kDotSize * 2.5;
      case IndicatorState.idle:
        return isHovered ? kDotSize * 2.5 : kDotSize * 2;
      default:
        return kDotSize * 2;
    }
  }

  double get _indicatorDotHeight {
    switch (state) {
      case IndicatorState.recording:
      case IndicatorState.expanded:
        return kDotSize;
      case IndicatorState.transcribing:
      case IndicatorState.error:
        return kDotSize;
      case IndicatorState.idle:
        return isHovered ? kDotSize : kDotSize * 0.5;
      default:
        return kDotSize * 0.5;
    }
  }

  BoxDecoration _indicatorDotDecoration(AppColorTheme colors) {
    final shadow = [BoxShadow(color: colors.shadow, blurRadius: 6, spreadRadius: 1)];

    switch (state) {
      case IndicatorState.recording:
        var borderW = 1 + _getNormalizedVolume() * 2;
        return BoxDecoration(
          color: colors.errorBg,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: colors.textOnPrimary, width: borderW),
          boxShadow: shadow,
        );
      case IndicatorState.transcribing:
        return BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colors.textOnPrimary, width: 2),
          boxShadow: shadow,
        );
      case IndicatorState.error:
        return BoxDecoration(
          color: colors.errorBg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colors.textOnPrimary, width: 2),
          boxShadow: shadow,
        );
      case IndicatorState.expanded:
        return BoxDecoration(
          color: isHovered ? colors.border : colors.surfaceElevated,
          borderRadius: BorderRadius.circular(kDotSize),
          border: Border.all(color: colors.textOnPrimary, width: 2),
          boxShadow: shadow,
        );
      case IndicatorState.idle:
        return BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(isHovered ? 5 : 10),
          border: Border.all(color: colors.textOnPrimary, width: 2),
          boxShadow: shadow,
        );
      default:
        return BoxDecoration(
          color: colors.border,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.textOnPrimary.withAlpha(180), width: 1.5),
        );
    }
  }
}

class _DotIndicatorState extends State<DotIndicator> {
  Widget? _indicatorDotContent(AppColorTheme colors) {
    switch (widget.state) {
      case IndicatorState.recording:
        return null;
      case IndicatorState.transcribing:
        return const PulseDots();
      case IndicatorState.error:
        return Icon(Icons.close, color: colors.textOnPrimary, size: kDotSize * 0.55);
      case IndicatorState.expanded:
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(
            end: widget.isHovered ? colors.textOnPrimary : colors.textSecondary,
          ),
          duration: kHoverDuration,
          curve: kHoverCurve,
          builder: (context, color, _) =>
              Icon(Icons.close, color: color, size: kDotSize * 0.55),
        );
      case IndicatorState.idle:
        return IdleDots(isHovered: widget.isHovered);
      default:
        return null;
    }
  }

  Widget _buildIndicator(double width, double height, AppColorTheme colors) {
    if (widget.state == IndicatorState.recording) {
      // normalize volume to 0.0-1.0 based on dB range
      final normalized = widget._getNormalizedVolume();

      // map normalized to scale range
      final sizeScale =
          kDotIndicatorMinScale +
          normalized * (kDotIndicatorMaxScale - kDotIndicatorMinScale);

      return RecordingDot(
        scale: sizeScale,
        decoration: widget._indicatorDotDecoration(colors),
      );
    }
    final container = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOutCubic,
      width: width,
      height: height,
      decoration: widget._indicatorDotDecoration(colors),
      child: _indicatorDotContent(colors),
    );
    if (widget.state == IndicatorState.error) {
      return ErrorShake(child: container);
    }
    return container;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          height: kDotSize * 1.5,
          child: Center(child: _buildIndicator(width, height, colors)),
        ),
      ),
    );
  }
}
