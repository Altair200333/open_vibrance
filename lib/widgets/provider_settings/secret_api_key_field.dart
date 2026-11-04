import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/hoverable_icon.dart';

/// API key input that is always masked by default. The eye button reveals the
/// key only until the field is rebuilt from scratch (e.g. settings reopened).
class SecretApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const SecretApiKeyField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hintText = 'Enter your API key',
  });

  @override
  State<SecretApiKeyField> createState() => _SecretApiKeyFieldState();
}

class _SecretApiKeyFieldState extends State<SecretApiKeyField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        hintText: widget.hintText,
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: HoverableIcon(
            iconData: _obscured ? LucideIcons.eye : LucideIcons.eyeOff,
            tooltip: _obscured ? 'Show key' : 'Hide key',
            size: 18,
            hoverColor: colors.iconHover,
            onTap: () => setState(() => _obscured = !_obscured),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
      ),
      style: TextStyle(color: colors.textPrimary),
      onChanged: widget.onChanged,
    );
  }
}
