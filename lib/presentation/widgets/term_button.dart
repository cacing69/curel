import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class TermButton extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final bool accent;

  const TermButton({
    this.icon,
    this.label,
    this.onTap,
    this.accent = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final accentColor = enabled ? TColors.green : TColors.mutedText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: accent
            ? (enabled
                  ? TColors.green.withValues(alpha: 0.15)
                  : TColors.surface)
            : TColors.surface,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: accent ? accentColor : (enabled ? TColors.foreground : TColors.mutedText),
              ),
              if (label != null && label!.isNotEmpty)
                const SizedBox(width: 4),
            ],
            if (label != null && label!.isNotEmpty)
              Text(
                label!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: accent ? accentColor : (enabled ? TColors.foreground : TColors.mutedText),
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
        padding: const EdgeInsets.only(bottom: 2),
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