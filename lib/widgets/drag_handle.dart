import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_colors.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:window_manager/window_manager.dart';

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
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: kDotSize,
            height: kDotSize,
            decoration: BoxDecoration(
              color:
                  isHandleActive
                      ? AppColors.blue500
                      : Colors.grey.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_up,
                  activeAlignment: Alignment.topCenter,
                  inactiveAlignment: Alignment(0, -0.7),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_down,
                  activeAlignment: Alignment.bottomCenter,
                  inactiveAlignment: Alignment(0, 0.7),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_left,
                  activeAlignment: Alignment.centerLeft,
                  inactiveAlignment: Alignment(-0.7, 0),
                ),
                _DragArrow(
                  isHandleActive: isHandleActive,
                  icon: Icons.keyboard_arrow_right,
                  activeAlignment: Alignment.centerRight,
                  inactiveAlignment: Alignment(0.7, 0),
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
    super.key,
    required this.isHandleActive,
    required this.icon,
    required this.activeAlignment,
    required this.inactiveAlignment,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      duration: const Duration(milliseconds: 120),
      alignment: isHandleActive ? activeAlignment : inactiveAlignment,
      child: Icon(
        icon,
        size: isHandleActive ? 8.0 : 6.0,
        color: isHandleActive ? Colors.white : Colors.black,
      ),
    );
  }
}
