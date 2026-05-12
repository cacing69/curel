import 'dart:io';

import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/screens/file_preview_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class WorkspaceExplorerPage extends ConsumerStatefulWidget {
  const WorkspaceExplorerPage({super.key});

  @override
  ConsumerState<WorkspaceExplorerPage> createState() => _WorkspaceExplorerPageState();
}

class _WorkspaceExplorerPageState extends ConsumerState<WorkspaceExplorerPage> {
  String _currentPath = '';
  String _rootPath = '';
  List<_FsEntry> _entries = [];
  bool _loading = true;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    final root = await ref.read(fileSystemProvider).getWorkspaceRoot();
    _rootPath = root;
    _navigate(root);
  }

  Future<void> _navigate(String path, {bool addToHistory = true}) async {
    if (path.isEmpty) return;
    final fs = ref.read(fileSystemProvider);
    final entities = await fs.listFiles(path);
    final entries = <_FsEntry>[];
    for (final e in entities) {
      final name = p.basename(e.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      final isDir = e is Directory;
      final size = isDir ? null : _formatSize(File(e.path));
      entries.add(_FsEntry(name: name, path: e.path, isDir: isDir, size: size));
    }
    entries.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    if (mounted) {
      setState(() {
        if (addToHistory && _currentPath.isNotEmpty && _currentPath != path) {
          _history.add(_currentPath);
        }
        _currentPath = path;
        _entries = entries;
        _loading = false;
      });
    }
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      final prev = _history.removeLast();
      setState(() => _loading = true);
      _navigate(prev, addToHistory: false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Container(height: 1, color: TColors.border),
            _buildBreadcrumb(),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : _buildList(),
            ),
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
            onTap: _goBack,
            child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          SizedBox(width: 8),
          Text(
            'workspace',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          Text(
            '${_entries.length}',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final relative = _rootPath.isNotEmpty && _currentPath.startsWith(_rootPath)
        ? _currentPath.substring(_rootPath.length)
        : _currentPath;
    final segments = relative.split('/').where((s) => s.isNotEmpty).toList();
    return Container(
      color: TColors.surface,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (_currentPath != _rootPath) {
                  setState(() => _loading = true);
                  _navigate(_rootPath);
                }
              },
              child: Text(
                '~',
                style: TextStyle(
                  color: TColors.green,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (int i = 0; i < segments.length; i++) ...[
              Text(
                '/',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
              GestureDetector(
                onTap: () {
                  final targetSegments = segments.sublist(0, i + 1);
                  final targetPath = '$_rootPath/${targetSegments.join('/')}';
                  if (targetPath != _currentPath) {
                    setState(() => _loading = true);
                    _navigate(targetPath);
                  }
                },
                child: Text(
                  segments[i],
                  style: TextStyle(
                    color: i == segments.length - 1
                        ? TColors.foreground
                        : TColors.green,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          'empty',
          style: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (_, i) => _buildEntryRow(_entries[i]),
    );
  }

  Widget _buildEntryRow(_FsEntry entry) {
    return GestureDetector(
      onTap: entry.isDir
          ? () { setState(() => _loading = true); _navigate(entry.path); }
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FilePreviewPage(
                  path: entry.path,
                  name: entry.name,
                  relativePath: _rootPath.isNotEmpty && entry.path.startsWith(_rootPath)
                      ? '~${entry.path.substring(_rootPath.length)}'
                      : null,
                ),
              ),
            ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: TColors.border.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            Icon(
              entry.isDir ? Icons.folder : _fileIcon(entry.name),
              size: 12,
              color: entry.isDir ? TColors.orange : TColors.mutedText,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.name,
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.size != null)
              Text(
                entry.size!,
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 9,
                ),
              ),
            if (entry.isDir)
              Icon(Icons.chevron_right, size: 12, color: TColors.mutedText),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.curl' => Icons.description,
      '.json' => Icons.data_object,
      '.env' => Icons.lock,
      _ => Icons.insert_drive_file,
    };
  }

  String? _formatSize(File file) {
    try {
      if (!file.existsSync()) return null;
      final bytes = file.lengthSync();
      if (bytes < 1024) return '${bytes}b';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}k';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}m';
    } catch (_) {
      return null;
    }
  }
}

class _FsEntry {
  final String name;
  final String path;
  final bool isDir;
  final String? size;

  _FsEntry({required this.name, required this.path, required this.isDir, this.size});
}
