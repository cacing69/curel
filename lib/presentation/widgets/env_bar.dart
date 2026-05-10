import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/env_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EnvBar extends ConsumerWidget {
  final String requestDisplayName;
  final bool hasCurlText;
  final VoidCallback onOpenProjects;
  final VoidCallback onOpenRequestDrawer;
  final VoidCallback onCloseRequest;
  final VoidCallback onCloseProject;
  final VoidCallback onSaveRequest;
  final VoidCallback onSaveRequestAs;
  final VoidCallback onEnvChanged;

  const EnvBar({
    required this.requestDisplayName,
    required this.hasCurlText,
    required this.onOpenProjects,
    required this.onOpenRequestDrawer,
    required this.onCloseRequest,
    required this.onCloseProject,
    required this.onSaveRequest,
    required this.onSaveRequestAs,
    required this.onEnvChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProject = ref.watch(activeProjectProvider);
    final selectedPath = ref.watch(selectedRequestPathProvider);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: TColors.surface,
        border: Border(bottom: BorderSide(color: TColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, size: 12, color: TColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onOpenProjects,
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [
                  Icon(
                    activeProject == null ? Icons.folder_open : Icons.folder,
                    size: 14,
                    color: TColors.mutedText,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      activeProject?.name ?? 'no project',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: activeProject == null
                            ? TColors.mutedText
                            : TColors.orange,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: activeProject == null
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                  ),
                  if (activeProject != null) ...[
                    const Text(
                      ' › ',
                      style: TextStyle(color: TColors.mutedText, fontSize: 10),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: onOpenRequestDrawer,
                        child: Text(
                          selectedPath != null
                              ? requestDisplayName
                              : 'no request',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selectedPath != null
                                ? TColors.cyan
                                : TColors.mutedText,
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (activeProject != null) ...[
            const SizedBox(width: 6),
            if (selectedPath != null || hasCurlText)
              GestureDetector(
                onTap: onCloseRequest,
                child: const Icon(Icons.close, size: 14, color: TColors.mutedText),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onCloseProject,
              child: const Icon(Icons.folder_off, size: 14, color: TColors.mutedText),
            ),
            ...[
              if (selectedPath != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onSaveRequest,
                  child: const Icon(Icons.save, size: 14, color: TColors.green),
                ),
              ],
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onSaveRequestAs,
                child: const Icon(Icons.save_as, size: 14, color: TColors.mutedText),
              ),
            ],
          ],
          const SizedBox(width: 6),
          EnvSwitch(
            projectId: ref.read(activeProjectProvider)?.id,
            onChanged: onEnvChanged,
          ),
        ],
      ),
    );
  }
}
