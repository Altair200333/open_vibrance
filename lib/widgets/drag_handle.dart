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
    final handleActive = _hovering || widget.dragging;
    var iconSize = handleActive ? 8.0 : 6.0;

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
                  handleActive ? AppColors.blue500 : Colors.grey.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  alignment:
                      handleActive ? Alignment.topCenter : Alignment(0, -0.7),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  alignment:
                      handleActive ? Alignment.bottomCenter : Alignment(0, 0.7),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  alignment:
                      handleActive ? Alignment.centerLeft : Alignment(-0.7, 0),
                  child: Icon(
                    Icons.keyboard_arrow_left,
                    size: iconSize,
                    color: handleActive ? Colors.white : Colors.black,
                  ),
                ),
                AnimatedAlign(
                  duration: const Duration(milliseconds: 120),
                  alignment:
                      handleActive ? Alignment.centerRight : Alignment(0.7, 0),
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
