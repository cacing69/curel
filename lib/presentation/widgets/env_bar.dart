import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/env_switch.dart';
import 'package:curel/presentation/widgets/git_connect_dialog.dart';
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
          _GitSyncButton(activeProject: activeProject),
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

class _GitSyncButton extends ConsumerStatefulWidget {
  final Project? activeProject;

  const _GitSyncButton({required this.activeProject});

  @override
  ConsumerState<_GitSyncButton> createState() => _GitSyncButtonState();
}

class _GitSyncButtonState extends ConsumerState<_GitSyncButton> {
  bool _isSyncing = false;

  Future<void> _connect() async {
    final project = widget.activeProject;
    if (project == null) return;

    final updated = await showDialog(
      context: context,
      builder: (_) => GitConnectDialog(project: project),
    );

    if (updated != null && mounted) {
      await ref.read(projectServiceProvider).update(updated);
      ref.read(activeProjectProvider.notifier).set(updated);
      showTerminalToast(context, 'project connected to remote');
    }
  }

  Future<void> _sync() async {
    final project = widget.activeProject;
    if (project == null) return;

    setState(() => _isSyncing = true);
    try {
      final result = await ref.read(gitSyncServiceProvider).sync(project);
      if (mounted) {
        if (result.success) {
          // If sync returned a remoteOriginId, update the project
          if (result.data is String && project.remoteOriginId == null) {
            final updatedProject = project.copyWith(remoteOriginId: result.data as String);
            await ref.read(projectServiceProvider).update(updatedProject);
            ref.read(activeProjectProvider.notifier).set(updatedProject);
          }
          
          // Robust re-sync of everything after Sync
          await ref.read(syncControllerProvider).syncAndRefresh();
          showTerminalToast(context, result.message);
        } else if (result.hasConflict) {
          if (mounted) {
            final choice = await _showConflictDialog();
            if (choice == 'pull') {
              // Forced Pull: simply call pull() - our current pull already overwrites
              final res = await ref.read(gitSyncServiceProvider).pull(project);
              if (res.success && mounted) {
                final updatedProject = project.copyWith(remoteOriginId: res.data as String);
                await ref.read(projectServiceProvider).update(updatedProject);
                ref.read(activeProjectProvider.notifier).set(updatedProject);
                await ref.read(syncControllerProvider).syncAndRefresh();
                showTerminalToast(context, 'pulled and overwrote local data');
              }
            } else if (choice == 'push') {
              // Forced Push: simply call push() - it will overwrite remote
              final res = await ref.read(gitSyncServiceProvider).push(project);
              if (res.success && mounted) {
                // If it was the first push, we might need to set the originId
                if (project.remoteOriginId == null) {
                   final updatedProject = project.copyWith(remoteOriginId: project.id);
                   await ref.read(projectServiceProvider).update(updatedProject);
                   ref.read(activeProjectProvider.notifier).set(updatedProject);
                }
                showTerminalToast(context, 'pushed and overwrote remote data');
              }
            }
          }
        } else {
          // Show in terminal response area with terminal-style formatting
          final terminalError = 'git sync\nerror: ${result.message}';
          ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
                clearResponse: true,
                error: terminalError,
              ));
          showTerminalToast(context, 'sync failed (see terminal)');
        }
      }
    } catch (e) {
      if (mounted) {
        final terminalError = 'git sync\ncritical error: $e';
        ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
              clearResponse: true,
              error: terminalError,
            ));
        showTerminalToast(context, 'sync error');
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<String?> _showConflictDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'sync conflict detected',
          style: TextStyle(
            color: TColors.orange,
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'both local and remote have existing data. choose how to resolve this conflict:',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('cancel',
                style: TextStyle(color: TColors.mutedText, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'pull'),
            child: const Text('pull & overwrite local',
                style: TextStyle(color: TColors.cyan, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'push'),
            child: const Text('push & overwrite remote',
                style: TextStyle(color: TColors.green, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeProject == null) {
      return const Icon(Icons.terminal, size: 12, color: TColors.green);
    }

    final isGit = widget.activeProject!.mode == 'git';

    if (_isSyncing) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          color: TColors.green,
          strokeWidth: 1.2,
        ),
      );
    }

    return GestureDetector(
      onTap: isGit ? _sync : _connect,
      onLongPress: isGit ? _showDisconnectDialog : null,
      child: Icon(
        isGit ? Icons.sync : Icons.cloud_off,
        size: 14,
        color: isGit ? TColors.green : TColors.mutedText,
      ),
    );
  }

  Future<void> _showDisconnectDialog() async {
    final project = widget.activeProject;
    if (project == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'disconnect git',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'stop syncing this project with remote repository? local files will be kept.',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('cancel',
                style: TextStyle(color: TColors.mutedText, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('disconnect',
                style: TextStyle(color: TColors.red, fontSize: 12)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final disconnectedProject = project.copyWith(
        mode: 'local',
        // We set these to null but .copyWith needs to handle nulls
        // Project model uses null as "no value"
      );

      // Explicitly clear git fields
      final finalProject = Project(
        id: disconnectedProject.id,
        name: disconnectedProject.name,
        description: disconnectedProject.description,
        createdAt: disconnectedProject.createdAt,
        updatedAt: disconnectedProject.updatedAt,
        mode: 'local',
        provider: null,
        remoteUrl: null,
        branch: null,
        lastSyncSha: null,
      );

      await ref.read(projectServiceProvider).update(finalProject);
      ref.read(activeProjectProvider.notifier).set(finalProject);
      showTerminalToast(context, 'project disconnected from git');
    }
  }
}
