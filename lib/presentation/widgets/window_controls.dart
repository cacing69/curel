import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  const HelpButton({required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: TColors.mutedText, width: 1),
        ),
        child: const Center(
          child: Text(
            '?',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class WindowDot extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  const WindowDot({required this.color, this.icon, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: icon != null
            ? Icon(icon, size: 8, color: TColors.background)
            : null,
      ),
    );
  }
}
