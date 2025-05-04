import 'package:flutter/material.dart';
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
    final handleActive = _hovering || widget.dragging;
    const iconSize = 7.0;

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
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: handleActive ? Colors.blue : Colors.grey.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    Icons.keyboard_arrow_left,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.keyboard_arrow_right,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
