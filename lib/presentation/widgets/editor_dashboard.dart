import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class EditorDashboard extends StatelessWidget {
  final Widget envBar;
  final Widget actionBar;

  const EditorDashboard({required this.envBar, required this.actionBar, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: TColors.background,
        border: Border(
          top: BorderSide(color: TColors.border, width: 1),
          bottom: BorderSide(color: TColors.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [envBar, actionBar],
      ),
    );
  }
}

class CompactIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const CompactIconButton({required this.icon, this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      color: TColors.mutedText,
      padding: EdgeInsets.all(8),
      constraints: const BoxConstraints(),
      splashRadius: 20,
    );
  }
}
