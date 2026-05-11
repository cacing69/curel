import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class MoreMenu extends StatelessWidget {
  final VoidCallback onAbout;
  final VoidCallback onFeedback;
  final VoidCallback onHelp;
  final VoidCallback onSettings;
  final VoidCallback onHistory;
  final VoidCallback? onImportCollection;

  const MoreMenu({
    required this.onAbout,
    required this.onFeedback,
    required this.onHelp,
    required this.onSettings,
    required this.onHistory,
    this.onImportCollection,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<int>(
          context: context,
          elevation: 0,
          position: RelativeRect.fromLTRB(
            offset.dx,
            offset.dy + renderBox.size.height,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            if (onImportCollection != null)
              PopupMenuItem<int>(
                value: 5,
                height: 36,
                child: Row(
                  children: [
                    const Icon(Icons.cloud_download, size: 14, color: TColors.mutedText),
                    const SizedBox(width: 8),
                    const Text(
                      'import collection',
                      style: TextStyle(
                        color: TColors.foreground,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            PopupMenuItem<int>(
              value: 3,
              height: 36,
              child: Row(
                children: [
                  const Icon(Icons.history, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  const Text(
                    'history',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 4,
              height: 36,
              child: Row(
                children: [
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'feedback',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 0,
              height: 36,
              child: Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'settings',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 1,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'about',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<int>(
              value: 2,
              height: 36,
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 14, color: TColors.mutedText),
                  const SizedBox(width: 8),
                  Text(
                    'help',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ).then((value) {
          if (value == 0) onSettings();
          if (value == 1) onAbout();
          if (value == 2) onHelp();
          if (value == 3) onHistory();
          if (value == 4) onFeedback();
          if (value == 5 && onImportCollection != null) onImportCollection!();
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }
}
