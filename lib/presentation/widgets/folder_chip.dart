import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class FolderChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const FolderChip({required this.label, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: TColors.background,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder, size: 10, color: TColors.orange),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: TColors.orange,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
