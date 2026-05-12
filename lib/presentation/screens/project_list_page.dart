import 'dart:convert';
import 'dart:io';

import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/presentation/widgets/import_preview_dialog.dart';
import 'package:curel/domain/adapters/adapter_registry.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/git_connect_dialog.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectListPage extends ConsumerStatefulWidget {
  ProjectListPage({
    super.key,
  });

  @override
  ConsumerState<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends ConsumerState<ProjectListPage> {
  List<Project> _projects = [];
  String? _activeProjectId;
  bool _loading = true;
  final Map<String, int> _requestCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await ref.read(projectServiceProvider).getAll();
    final activeId = await ref.read(projectServiceProvider).getActiveProjectId();
    final counts = <String, int>{};
    for (final p in projects) {
      final requests = await ref.read(requestServiceProvider).listRequests(p.id);
      counts[p.id] = requests.length;
    }
    if (mounted) {
      setState(() {
        _projects = projects;
        _activeProjectId = activeId;
        _requestCounts
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    }
  }

  Future<void> _createProject() async {
    final name = await _showNameDialog('new project');
    if (name == null || name.trim().isEmpty) return;
    await ref.read(projectServiceProvider).create(name.trim());
    await _load();
  }

  Future<void> _renameProject(Project project) async {
    final name = await _showNameDialog('rename', initial: project.name);
    if (name == null || name.trim().isEmpty) return;
    await ref.read(projectServiceProvider).update(project.copyWith(name: name.trim()));
    await _load();
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await _showConfirmDialog(
      'delete "${project.name}"?',
      'this will remove all requests and environments in this project.',
    );
    if (confirmed != true) return;
    await ref.read(projectServiceProvider).delete(project.id);
    await _load();
  }

  Future<void> _selectProject(Project project) async {
    await ref.read(projectServiceProvider).setActiveProject(project.id);
    if (mounted) Navigator.of(context).pop(project.id);
  }

  Future<void> _exportProject(Project project) async {
    final adapters = ref.read(adapterRegistryProvider).availableAdapters;

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height,
      offset.dx + size.width,
      0,
    );

    final selected = await showMenu<(String, String)>(
      context: context,
      elevation: 0,
      position: position,
      color: TColors.surface,
      items: adapters.map((a) => PopupMenuItem<(String, String)>(
        height: 36,
        value: (a.id, a.name),
        child: _menuItem(_iconFor(a.id), a.name),
      )).toList(),
    );

    if (selected == null || !mounted) return;
    await _doExport(project, selected.$1, selected.$2);
  }

  Future<void> _doExport(Project project, String adapterId, String formatName) async {
    try {
      final json = await ref.read(workspaceServiceProvider).exportProjectAs(project.id, adapterId);
      final ext = _extFor(adapterId);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'export as $formatName',
        fileName: '${project.name}$ext',
        bytes: utf8.encode(json),
      );
      if (path != null && mounted) showTerminalToast(context, 'exported as $formatName');
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  IconData _iconFor(String id) => switch (id) {
    'postman_v2' => Icons.cloud_upload,
    'insomnia_v4' => Icons.code,
    'hoppscotch_v1' => Icons.code,
    _ => Icons.archive,
  };

  String _extFor(String id) => switch (id) {
    'postman_v2' => '.postman_collection.json',
    'insomnia_v4' => '.insomnia.json',
    'hoppscotch_v1' => '.hoppscotch.json',
    _ => '.json',
  };

  Future<void> _importProject() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final json = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();

      final preview = await ref.read(workspaceServiceProvider).previewImport(json);
      if (preview == null) {
        if (mounted) showTerminalToast(context, 'error: unsupported file format');
        return;
      }

      if (!mounted) return;
      final importResult = await showDialog<ImportResult>(
        context: context,
        builder: (_) => ImportPreviewDialog(
          preview: preview,
          projects: _projects,
        ),
      );
      if (importResult == null || !mounted) return;

      final counts = importResult.projectId == null
          ? await ref.read(workspaceServiceProvider).importProject(
                json, customName: importResult.customName)
          : await ref.read(workspaceServiceProvider).importIntoProject(
                json, importResult.projectId!);
      await _load();
      if (mounted) {
        showTerminalToast(
          context,
          'imported ${counts.requests} requests, ${counts.envs} envs',
        );
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : _projects.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
            Container(height: 1, color: TColors.border),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          SizedBox(width: 8),
          Text(
            'projects',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'no projects yet',
            style: TextStyle(
              color: TColors.mutedText.withValues(alpha: 0.5),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: 8),
          Text(
            'create one to start organizing requests',
            style: TextStyle(
              color: TColors.mutedText.withValues(alpha: 0.3),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _projects.length,
      separatorBuilder: (_, _) => Container(height: 1, color: TColors.border),
      itemBuilder: (_, i) => _buildProjectTile(_projects[i]),
    );
  }

  Widget _buildProjectTile(Project project) {
    final isActive = project.id == _activeProjectId;
    final count = _requestCounts[project.id] ?? 0;

    return GestureDetector(
      onTap: () => _selectProject(project),
      child: Container(
        color: isActive ? TColors.surface : Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.folder_open : Icons.folder,
              size: 16,
              color: isActive ? TColors.green : TColors.mutedText,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: TextStyle(
                      color: isActive ? TColors.green : TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (project.description != null && project.description!.isNotEmpty)
                    Text(
                      project.description!,
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            if (project.provider != null) ...[
              SizedBox(width: 8),
              Tooltip(
                message: project.lastSyncSha != null
                    ? 'synced'
                    : 'not synced yet',
                preferBelow: false,
                child: Icon(
                  Icons.cloud,
                  size: 11,
                  color: project.lastSyncSha != null
                      ? (isActive ? TColors.green : TColors.cyan)
                      : TColors.orange,
                ),
              ),
            ],
            SizedBox(width: 8),
            _popupMenu(project),
          ],
        ),
      ),
    );
  }

  Widget _popupMenu(Project project) {
    return GestureDetector(
      onTapDown: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final offset = renderBox.localToGlobal(Offset.zero);
        showMenu<int>(
          context: context,
          elevation: 0,
          position: RelativeRect.fromLTRB(
            offset.dx,
            details.globalPosition.dy,
            offset.dx + renderBox.size.width,
            0,
          ),
          color: TColors.surface,
          items: [
            PopupMenuItem(value: 0, height: 36, child: _menuItem(Icons.edit, 'rename')),
            if (project.provider == null)
              PopupMenuItem(value: 4, height: 36, child: _menuItem(Icons.cloud, 'connect to git')),
            if (project.provider != null)
              PopupMenuItem(value: 3, height: 36, child: _menuItem(Icons.cloud_off, 'disconnect git')),
            PopupMenuItem(value: 1, height: 36, child: _menuItem(Icons.download, 'export')),
            PopupMenuItem(value: 2, height: 36, child: _menuItem(Icons.delete, 'delete')),
          ],
        ).then((value) {
          if (value == 0) _renameProject(project);
          if (value == 1) _exportProject(project);
          if (value == 2) _deleteProject(project);
          if (value == 3) _disconnectGit(project);
          if (value == 4) _connectGit(project);
        });
      },
      child: Container(
        height: 28,
        padding: EdgeInsets.symmetric(horizontal: 6),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }

  Future<void> _connectGit(Project project) async {
    final updated = await showDialog(
      context: context,
      builder: (_) => GitConnectDialog(project: project),
    );
    if (updated != null && mounted) {
      await ref.read(projectServiceProvider).update(updated);
      final activeId = await ref.read(projectServiceProvider).getActiveProjectId();
      if (activeId == project.id) {
        ref.read(activeProjectProvider.notifier).set(updated);
      }
      showTerminalToast(context, 'project connected to remote');
      await _load();
    }
  }

  Future<void> _disconnectGit(Project project) async {
    final confirmed = await _showConfirmDialog(
      'disconnect git?',
      'stop syncing "${project.name}" with remote repository? local files will be kept.',
    );
    if (confirmed != true) return;

    final finalProject = Project(
      id: project.id,
      name: project.name,
      description: project.description,
      createdAt: project.createdAt,
      updatedAt: project.updatedAt,
      mode: 'local',
      provider: null,
      remoteUrl: null,
      branch: null,
      lastSyncSha: null,
    );

    await ref.read(projectServiceProvider).update(finalProject);

    // If this is the active project, update the active project state too
    final activeId = await ref.read(projectServiceProvider).getActiveProjectId();
    if (activeId == project.id) {
      ref.read(activeProjectProvider.notifier).set(finalProject);
    }

    showTerminalToast(context, 'disconnected from git');
    await _load();
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: TColors.mutedText),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: TColors.foreground,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TermButton(icon: Icons.add, label: 'new project', onTap: _createProject, accent: true),
          Spacer(),
          TermButton(icon: Icons.upload_file, label: 'import', onTap: _importProject),
          SizedBox(width: 6),
          TermButton(icon: Icons.refresh, label: 'refresh', onTap: _load),
        ],
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────

  Future<String?> _showNameDialog(String action, {String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          action,
          style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14),
        ),
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: TColors.green,
            style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              hintText: 'name',
              hintStyle: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 13),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel', style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('ok', style: TextStyle(color: TColors.green, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(
          title,
          style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14),
        ),
        content: Text(
          message,
          style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel', style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('delete', style: TextStyle(color: TColors.red, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
