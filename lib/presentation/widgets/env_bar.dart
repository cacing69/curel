import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/env_switch.dart';
import 'package:curel/presentation/widgets/git_connect_dialog.dart';
import 'package:curel/presentation/widgets/diff_viewer_dialog.dart';
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
      if (mounted) {
        ref.read(activeProjectProvider.notifier).set(updated);
        showTerminalToast(context, 'project connected to remote');
      }
    }
  }

  Future<void> _updateProject(Project project, {String? syncSha, String? originId}) async {
    var updated = project;
    if (syncSha != null) {
      updated = updated.copyWith(lastSyncSha: syncSha);
    }
    if (originId != null && updated.remoteOriginId == null) {
      updated = updated.copyWith(remoteOriginId: originId);
    }
    await ref.read(projectServiceProvider).update(updated);
    ref.read(activeProjectProvider.notifier).set(updated);
  }

  Future<void> _sync() async {
    final project = widget.activeProject;
    if (project == null || _isSyncing) return;

    setState(() => _isSyncing = true);
    ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
      clearResponse: true, clearError: true, clearLog: true,
    ));
    try {
      // 1. Check for pending changes
      final changes = await ref.read(gitSyncServiceProvider).computePendingChanges(project);
      
      List<String>? selectedPaths;
      if (mounted && changes.isNotEmpty) {
        selectedPaths = await showDialog<List<String>>(
          context: context,
          builder: (context) => DiffViewerDialog(changes: changes),
        );
        
        if (selectedPaths == null || selectedPaths.isEmpty) {
          setState(() => _isSyncing = false);
          return;
        }
      }

      final result = await ref.read(gitSyncServiceProvider).sync(project, selectedPaths: selectedPaths);
      if (mounted) {
        if (result.success) {
          await _updateProject(
            project,
            syncSha: result.newSyncSha,
            originId: result.data is String ? result.data as String : null,
          );

          await ref.read(syncControllerProvider).syncAndRefresh();
          _showLog('git sync\n${result.message}');
        } else if (result.hasConflict) {
          if (mounted) {
            final choice = await _showConflictDialog();
            if (choice == 'pull') {
              final res = await ref.read(gitSyncServiceProvider).pull(project, force: true);
              if (res.success && mounted) {
                await _updateProject(
                  project,
                  syncSha: res.newSyncSha,
                  originId: res.data is String ? res.data as String : null,
                );
                await ref.read(syncControllerProvider).syncAndRefresh();
                _showLog('git sync (pull overwrite)\n${res.message}');
              } else if (mounted) {
                _showLog('git sync (pull overwrite)\nerror: ${res.message}');
              }
            } else if (choice == 'push') {
              final res = await ref.read(gitSyncServiceProvider).push(project, force: true);
              if (res.success && mounted) {
                await _updateProject(
                  project,
                  syncSha: res.newSyncSha,
                  originId: project.remoteOriginId ?? project.id,
                );
                _showLog('git sync (push overwrite)\n${res.message}');
              } else if (mounted) {
                _showLog('git sync (push overwrite)\nerror: ${res.message}');
              }
            }
          }
        } else {
          ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
                clearResponse: true,
                error: 'git sync\nerror: ${result.message}',
              ));
          showTerminalToast(context, result.message);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
              clearResponse: true,
              error: 'git sync\nerror: $msg',
            ));
        showTerminalToast(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showLog(String message) {
    ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
      clearResponse: true, log: message,
    ));
    showTerminalToast(context, message.split('\n').last);
  }

  Future<String?> _showConflictDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TColors.background,
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

    return Tooltip(
      message: isGit
          ? widget.activeProject!.lastSyncSha != null
              ? 'tap to sync · long press to disconnect'
              : 'not synced yet · tap to sync'
          : 'tap to connect git',
      preferBelow: false,
      child: GestureDetector(
        onTap: isGit ? _sync : _connect,
        onLongPress: isGit ? _showDisconnectDialog : null,
        child: Icon(
          isGit ? Icons.sync : Icons.cloud_off,
          size: 14,
          color: isGit
              ? (widget.activeProject!.lastSyncSha != null
                  ? TColors.green
                  : TColors.orange)
              : TColors.mutedText,
        ),
      ),
    );
  }

  Future<void> _showDisconnectDialog() async {
    final project = widget.activeProject;
    if (project == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TColors.background,
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
        lastSyncSha: null,
        remoteUrl: null,
        provider: null,
        branch: null,
        remoteOriginId: null,
      );

      await ref.read(projectServiceProvider).update(disconnectedProject);
      ref.read(activeProjectProvider.notifier).set(disconnectedProject);
      showTerminalToast(context, 'project disconnected from git');
    }
  }
}
