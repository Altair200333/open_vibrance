import 'package:flutter/material.dart';

class HoverableIcon extends StatefulWidget {
  final IconData iconData;
  final VoidCallback onTap;
  final Color color;
  final Color? hoverColor;

  const HoverableIcon({
    super.key,
    required this.iconData,
    required this.onTap,
    this.color = Colors.white,
    this.hoverColor,
  });

  @override
  State<HoverableIcon> createState() => _HoverableIconState();
}

class _HoverableIconState extends State<HoverableIcon> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _isHovering ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          widget.iconData,
          color: _isHovering && widget.hoverColor != null
              ? widget.hoverColor
              : widget.color,
          size: 20,
        ),
      ),
    );
  }
}
