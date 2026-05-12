import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/env_switch.dart';
import 'package:curel/presentation/widgets/git_connect_dialog.dart';
import 'package:curel/presentation/widgets/diff_viewer_dialog.dart';
import 'package:curel/presentation/widgets/conflict_dialog.dart';
import 'package:curel/presentation/widgets/branch_picker_dialog.dart';
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
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: TColors.surface,
        border: Border(bottom: BorderSide(color: TColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          _GitSyncButton(activeProject: activeProject),
          SizedBox(width: 8),
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
                  SizedBox(width: 6),
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
                    Text(
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
            SizedBox(width: 6),
            if (selectedPath != null || hasCurlText)
              GestureDetector(
                onTap: onCloseRequest,
                child: Icon(Icons.close, size: 14, color: TColors.mutedText),
              ),
            SizedBox(width: 6),
            GestureDetector(
              onTap: onCloseProject,
              child: Icon(Icons.folder_off, size: 14, color: TColors.mutedText),
            ),
            ...[
              if (selectedPath != null) ...[
                SizedBox(width: 6),
                GestureDetector(
                  onTap: onSaveRequest,
                  child: Icon(Icons.save, size: 14, color: TColors.green),
                ),
              ],
              SizedBox(width: 6),
              GestureDetector(
                onTap: onSaveRequestAs,
                child: Icon(Icons.save_as, size: 14, color: TColors.mutedText),
              ),
            ],
          ],
          SizedBox(width: 6),
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
          _showLog('git sync\n${result.message}', result.affectedFiles);
        } else if (result.hasConflict) {
          if (mounted) {
            final changes = await ref.read(gitSyncServiceProvider).computePendingChanges(project);
            if (changes.isEmpty) {
              showTerminalToast(context, 'conflict detected but no changes found');
              return;
            }

            final resolutions = await showDialog<Map<String, String>>(
              context: context,
              builder: (_) => ConflictDialog(changes: changes),
            );

            if (resolutions == null || !mounted) return;

            // Apply resolutions: pull remote-kept files, then push local-kept files
            final pullRes = await ref.read(gitSyncServiceProvider).pullWithResolution(project, resolutions);
            if (pullRes.success) {
              await _updateProject(
                project,
                syncSha: pullRes.newSyncSha,
                originId: pullRes.data is String ? pullRes.data as String : null,
              );
            } else if (mounted) {
              _showLog('conflict resolution\nerror: ${pullRes.message}');
              return;
            }

            final pushRes = await ref.read(gitSyncServiceProvider).pushWithResolution(project, resolutions);
            if (pushRes.success && mounted) {
              await _updateProject(
                project,
                syncSha: pushRes.newSyncSha,
                originId: project.remoteOriginId ?? project.id,
              );
              await ref.read(syncControllerProvider).syncAndRefresh();
              _showLog('conflict resolved\n${pushRes.message}', [
                ...pullRes.affectedFiles,
                ...pushRes.affectedFiles,
              ]);
            } else if (mounted) {
              _showLog('conflict resolution\nerror: ${pushRes.message}');
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

  void _showLog(String message, [List<String> files = const []]) {
    final fullMessage = files.isEmpty
        ? message
        : '$message\n${files.map((f) => '  $f').join('\n')}';
    ref.read(responseStateProvider.notifier).update((s) => s.copyWith(
      clearResponse: true, log: fullMessage,
    ));
    showTerminalToast(context, message.split('\n').last);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeProject == null) {
      return Icon(Icons.terminal, size: 12, color: TColors.green);
    }

    final isGit = widget.activeProject!.mode == 'git';

    if (_isSyncing) {
      return const TerminalLoader(compact: true);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
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
        ),
        if (isGit && widget.activeProject!.branch != null) ...[
          SizedBox(width: 4),
          GestureDetector(
            onTap: _openBranchPicker,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.activeProject!.branch!,
                    style: TextStyle(
                      color: TColors.cyan,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, size: 10, color: TColors.cyan),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openBranchPicker() async {
    final project = widget.activeProject;
    if (project == null) return;

    final selectedBranch = await showDialog<String>(
      context: context,
      builder: (_) => BranchPickerDialog(
        currentBranch: project.branch ?? 'main',
        projectId: project.id,
      ),
    );

    if (selectedBranch == null || !mounted || selectedBranch == project.branch) return;

    // Switch branch
    final updated = project.copyWith(branch: selectedBranch, lastSyncSha: null);
    await ref.read(projectServiceProvider).update(updated);
    ref.read(activeProjectProvider.notifier).set(updated);

    // Pull from new branch
    final res = await ref.read(gitSyncServiceProvider).pull(updated, force: true);
    if (res.success) {
      final synced = updated.copyWith(lastSyncSha: res.newSyncSha);
      await ref.read(projectServiceProvider).update(synced);
      ref.read(activeProjectProvider.notifier).set(synced);
      await ref.read(syncControllerProvider).syncAndRefresh();
      if (mounted) showTerminalToast(context, 'switched to "$selectedBranch"');
    } else if (mounted) {
      showTerminalToast(context, 'switched to "$selectedBranch" (pull failed: ${res.message})');
    }
  }

  Future<void> _showDisconnectDialog() async {
    final project = widget.activeProject;
    if (project == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'disconnect git',
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
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
            child: Text('cancel',
                style: TextStyle(color: TColors.mutedText, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('disconnect',
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
