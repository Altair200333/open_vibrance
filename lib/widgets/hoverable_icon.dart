import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';

class HoverableIcon extends StatefulWidget {
  final IconData iconData;
  final VoidCallback onTap;
  final Color? color;
  final Color? hoverColor;
  final double size;
  final String? tooltip;

  const HoverableIcon({
    super.key,
    required this.iconData,
    required this.onTap,
    this.color,
    this.hoverColor,
    this.size = 20,
    this.tooltip,
  });

  @override
  State<HoverableIcon> createState() => _HoverableIconState();
}

class _HoverableIconState extends State<HoverableIcon> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.color ?? context.colors.iconDefault;
    final targetColor = _isHovering && widget.hoverColor != null
        ? widget.hoverColor!
        : effectiveColor;

    final minHitArea = math.max(widget.size, 24.0);

    Widget icon = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: targetColor),
      duration: kHoverDuration,
      curve: kHoverCurve,
      builder: (context, color, _) => Icon(
        widget.iconData,
        color: color,
        size: widget.size,
      ),
    );

    if (widget.tooltip != null) {
      icon = Tooltip(message: widget.tooltip!, child: icon);
    }

    return MouseRegion(
      cursor: _isHovering ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: minHitArea,
          height: minHitArea,
          child: Center(child: icon),
        ),
      ),
    );
  }
}
