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

class _DragHandleState extends State<DragHandle>
    with SingleTickerProviderStateMixin {
  bool _hovering = false;
  Timer? _hideTimer;
  late final AnimationController _showController;
  late final Animation<double> _curved;

  bool get _shouldBeVisible => widget.dragging || widget.showWindowContent;

  @override
  void initState() {
    super.initState();
    _showController = AnimationController(
      vsync: this,
      duration: kHoverDuration,
      reverseDuration: _hideDuration,
      value: _shouldBeVisible ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _showController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void didUpdateWidget(DragHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_shouldBeVisible) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _showController.forward();
    } else if (_hideTimer == null && _showController.value > 0) {
      _hideTimer = Timer(_hideDelay, () {
        _showController.reverse();
        _hideTimer = null;
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _showController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHandleActive = _hovering || widget.dragging;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ScaleTransition(
        scale: _curved,
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
                  color: isHandleActive
                      ? colors.border
                      : colors.surfaceElevated,
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
      ),
    );
  }
}
