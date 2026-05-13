import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class TermButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final bool accent;
  final bool fullWidth;
  final bool bordered;
  final Color? color;

  const TermButton({
    this.icon,
    this.label,
    this.onTap,
    this.accent = false,
    this.fullWidth = false,
    this.bordered = false,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveColor = color ??
        (accent
            ? TColors.green
            : enabled
                ? TColors.foreground
                : TColors.mutedText);
    final bgColor = bordered
        ? Colors.transparent
        : accent
            ? (enabled
                ? TColors.green.withValues(alpha: 0.15)
                : TColors.surface)
            : TColors.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 14),
        width: fullWidth ? double.infinity : null,
        decoration: bordered
            ? BoxDecoration(border: Border.all(color: effectiveColor))
            : null,
        color: bordered ? null : bgColor,
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment:
              fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: effectiveColor),
              if (label != null && label!.isNotEmpty)
                const SizedBox(width: 4),
            ],
            if (label != null && label!.isNotEmpty)
              Text(
                label!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: effectiveColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FlatTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FlatTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? TColors.green : Colors.transparent,
              width: 1,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: selected ? TColors.foreground : TColors.mutedText,
          ),
        ),
      ),
    );
  }
}
