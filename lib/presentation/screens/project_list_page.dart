import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class ProjectListPage extends StatefulWidget {
  final ProjectService projectService;
  final RequestService requestService;

  const ProjectListPage({
    required this.projectService,
    required this.requestService,
    super.key,
  });

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
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
    final projects = await widget.projectService.getAll();
    final activeId = await widget.projectService.getActiveProjectId();
    final counts = <String, int>{};
    for (final p in projects) {
      final requests = await widget.requestService.listRequests(p.id);
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
    await widget.projectService.create(name.trim());
    await _load();
  }

  Future<void> _renameProject(Project project) async {
    final name = await _showNameDialog('rename', initial: project.name);
    if (name == null || name.trim().isEmpty) return;
    await widget.projectService.update(project.copyWith(name: name.trim()));
    await _load();
  }

  Future<void> _deleteProject(Project project) async {
    final confirmed = await _showConfirmDialog(
      'delete "${project.name}"?',
      'this will remove all requests and environments in this project.',
    );
    if (confirmed != true) return;
    await widget.projectService.delete(project.id);
    await _load();
  }

  Future<void> _selectProject(Project project) async {
    await widget.projectService.setActiveProject(project.id);
    if (mounted) Navigator.of(context).pop(project.id);
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: TColors.green,
                        strokeWidth: 2,
                      ),
                    )
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          const SizedBox(width: 8),
          const Text(
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
          const SizedBox(height: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.folder_open : Icons.folder,
              size: 16,
              color: isActive ? TColors.green : TColors.mutedText,
            ),
            const SizedBox(width: 8),
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
                      style: const TextStyle(
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
              style: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
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
          shape: const RoundedRectangleBorder(),
          items: [
            PopupMenuItem(value: 0, height: 36, child: _menuItem(Icons.edit, 'rename')),
            PopupMenuItem(value: 1, height: 36, child: _menuItem(Icons.delete, 'delete')),
          ],
        ).then((value) {
          if (value == 0) _renameProject(project);
          if (value == 1) _deleteProject(project);
        });
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        color: TColors.surface,
        child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: TColors.mutedText),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          TermButton(icon: Icons.add, label: 'new project', onTap: _createProject, accent: true),
          const Spacer(),
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
        backgroundColor: TColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          action,
          style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          cursorColor: TColors.green,
          style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'name',
            hintStyle: TextStyle(color: TColors.mutedText, fontFamily: 'monospace'),
            border: InputBorder.none,
            filled: true,
            fillColor: TColors.background,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        backgroundColor: TColors.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
