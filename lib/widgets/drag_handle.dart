import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:window_manager/window_manager.dart';

const double _handleSize = kDotSize * 1.3;

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

  @override
  Widget build(BuildContext context) {
    final isVisible = widget.dragging || widget.showWindowContent;
    final isHandleActive = _hovering || widget.dragging;

    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 120),
      child: GestureDetector(
        onPanStart: (details) => windowManager.startDragging(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedContainer(
            duration: kHoverDuration,
            curve: kHoverCurve,
            width: _handleSize,
            height: _handleSize,
            decoration: BoxDecoration(
              color: isHandleActive ? AppColors.border : AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(kRadiusMd),
              border: Border.all(
                color: isHandleActive ? AppColors.borderHover : AppColors.zinc600,
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_up,
                  activeAlignment: Alignment.topCenter,
                  inactiveAlignment: const Alignment(0, -0.7),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_down,
                  activeAlignment: Alignment.bottomCenter,
                  inactiveAlignment: const Alignment(0, 0.7),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_left,
                  activeAlignment: Alignment.centerLeft,
                  inactiveAlignment: const Alignment(-0.7, 0),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_right,
                  activeAlignment: Alignment.centerRight,
                  inactiveAlignment: const Alignment(0.7, 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragArrow extends StatelessWidget {
  final bool isHandleActive;
  final IconData icon;
  final Alignment activeAlignment;
  final Alignment inactiveAlignment;

  const _DragArrow({
    required this.isHandleActive,
    required this.icon,
    required this.activeAlignment,
    required this.inactiveAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      duration: kHoverDuration,
      curve: kHoverCurve,
      alignment: isHandleActive ? activeAlignment : inactiveAlignment,
      child: Icon(
        icon,
        size: isHandleActive ? 10.0 : 8.0,
        color: AppColors.textOnPrimary,
      ),
    );
  }
}
