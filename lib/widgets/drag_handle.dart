import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:window_manager/window_manager.dart';

const double _handleSize = kDotSize;
const Duration _hideDelay = Duration(milliseconds: 150);
const Duration _hideDuration = Duration(milliseconds: 200);

class DragHandle extends StatefulWidget {
  final bool dragging;
  final bool showWindowContent;

  const DragHandle({
    super.key,
    required this.dragging,
    required this.showWindowContent,
  });

  @override
  State<DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<DragHandle> {
  bool _hovering = false;
  bool _shown = false;
  Timer? _hideTimer;

  bool get _shouldBeVisible => widget.dragging || widget.showWindowContent;

  @override
  void initState() {
    super.initState();
    _shown = _shouldBeVisible;
  }

  @override
  void didUpdateWidget(DragHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBeVisible) {
      _hideTimer?.cancel();
      _hideTimer = null;
      if (!_shown) setState(() => _shown = true);
    } else if (_shown && _hideTimer == null) {
      _hideTimer = Timer(_hideDelay, () {
        if (mounted) setState(() => _shown = false);
        _hideTimer = null;
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHandleActive = _hovering || widget.dragging;

    return AnimatedScale(
      scale: _shown ? 1.0 : 0.0,
      duration: _shown ? kHoverDuration : _hideDuration,
      curve: _shown ? Curves.easeOut : Curves.easeIn,
      child: GestureDetector(
        onPanStart: (details) => windowManager.startDragging(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedScale(
            scale: isHandleActive ? 1.1 : 1.0,
            duration: kHoverDuration,
            curve: kHoverCurve,
            child: AnimatedContainer(
              duration: kHoverDuration,
              curve: kHoverCurve,
              width: _handleSize,
              height: _handleSize,
              decoration: BoxDecoration(
                color: isHandleActive ? colors.border : colors.surfaceElevated,
                borderRadius: BorderRadius.circular(kRadiusMd),
                border: Border.all(
                  color: colors.borderHover,
                  width: 2,
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: kHoverDuration,
                  curve: kHoverCurve,
                  width: isHandleActive ? 10.0 : 5.0,
                  height: isHandleActive ? 10.0 : 5.0,
                  decoration: BoxDecoration(
                    color: isHandleActive
                        ? Colors.transparent
                        : colors.textOnPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.textOnPrimary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
