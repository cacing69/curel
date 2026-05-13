import 'package:curel/domain/models/request_item_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

class RequestDrawer extends ConsumerStatefulWidget {
  final String projectId;
  final ValueChanged<String> onRequestSelected;
  final VoidCallback? onNewRequest;
  final String? selectedPath;

  RequestDrawer({
    required this.projectId,
    required this.onRequestSelected,
    this.onNewRequest,
    this.selectedPath,
    super.key,
  });

  @override
  ConsumerState<RequestDrawer> createState() => _RequestDrawerState();
}

class _RequestDrawerState extends ConsumerState<RequestDrawer> {
  List<RequestItem> _requests = [];
  bool _loading = true;
  String _searchQuery = '';
  Set<String> _expandedFolders = {};
  bool _selectionMode = false;
  Set<String> _selectedPaths = {};

  String get _prefsKey => 'drawer_expanded_${widget.projectId}';

  @override
  void initState() {
    super.initState();
    _loadExpanded();
    _load();
  }

  Future<void> _loadExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    if (saved != null && mounted) {
      setState(() => _expandedFolders = saved.toSet());
    }
  }

  Future<void> _saveExpanded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _expandedFolders.toList());
  }

  Future<void> _load() async {
    final requests =
        await ref.read(requestServiceProvider).listRequestsFast(widget.projectId);
    if (mounted) {
      setState(() {
        _requests = requests;
        _loading = false;
      });
    }
  }

  List<RequestItem> get _filtered {
    if (_searchQuery.isEmpty) return _requests;
    final q = _searchQuery.toLowerCase();
    return _requests.where((r) {
      return r.displayName.toLowerCase().contains(q) ||
          r.method.toLowerCase().contains(q) ||
          r.relativePath.toLowerCase().contains(q);
    }).toList();
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Container(height: 1, color: TColors.border),
          if (!_selectionMode) _buildSearch(),
          if (!_selectionMode) Container(height: 1, color: TColors.border),
          Expanded(child: _loading ? _buildLoading() : _buildList()),
          Container(height: 1, color: TColors.border),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (_selectionMode) {
      return Container(
        color: TColors.surface,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            GestureDetector(
              onTap: _exitSelectionMode,
              child: Icon(Icons.close, size: 14, color: TColors.mutedText),
            ),
            SizedBox(width: 8),
            Text(
              '${_selectedPaths.length} selected',
              style: TextStyle(
                color: TColors.orange,
                fontSize: 11,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
            Spacer(),
            TermButton(
              icon: Icons.delete,
              label: 'delete',
              onTap: _selectedPaths.isNotEmpty ? _batchDelete : null,
            ),
          ],
        ),
      );
    }

    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            'requests',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 8),
          Text(
            '${_requests.length}',
            style: TextStyle(
              color: TColors.mutedText,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.close, size: 14, color: TColors.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        style: TextStyle(
          color: TColors.text,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        cursorColor: TColors.green,
        decoration: InputDecoration(
          hintText: 'search...',
          hintStyle: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          prefixIcon: Icon(Icons.search, size: 14, color: TColors.mutedText),
          prefixIconConstraints: BoxConstraints(minWidth: 20, minHeight: 14),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(child: TerminalLoader());
  }

  // ── Collapsible folder tree ────────────────────────────────────────

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'no match' : 'no requests yet',
          style: TextStyle(
            color: TColors.mutedText.withValues(alpha: 0.5),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    final tree = _buildTree(items);
    return ListView(children: _renderTree(tree, 0));
  }

  Map<String, _FolderNode> _buildTree(List<RequestItem> items) {
    final root = <String, _FolderNode>{};
    for (final item in items) {
      final posix = item.relativePath.replaceAll('\\', '/');
      final slash = posix.lastIndexOf('/');
      final folderPath = slash >= 0 ? posix.substring(0, slash) : '';
      if (folderPath.isEmpty) {
        root.putIfAbsent('', () => _FolderNode(name: '', fullPath: ''));
        root['']!.requests.add(item);
      } else {
        _insertIntoTree(root, folderPath, item);
      }
    }
    return root;
  }

  void _insertIntoTree(
    Map<String, _FolderNode> nodes,
    String folderPath,
    RequestItem item,
  ) {
    final parts = folderPath.split('/');
    var current = nodes;
    var builtPath = '';
    for (final part in parts) {
      builtPath = builtPath.isEmpty ? part : '$builtPath/$part';
      current.putIfAbsent(part, () => _FolderNode(
        name: part,
        fullPath: builtPath,
      ));
      final node = current[part]!;
      if (part == parts.last) {
        node.requests.add(item);
      } else {
        current = node.children;
      }
    }
  }

  List<Widget> _renderTree(Map<String, _FolderNode> nodes, int depth) {
    final widgets = <Widget>[];

    final rootNode = nodes[''];
    if (rootNode != null) {
      for (final item in rootNode.requests) {
        widgets.add(_buildItem(item));
      }
    }

    final folderKeys = nodes.keys.where((k) => k.isNotEmpty).toList()..sort();
    for (final key in folderKeys) {
      final node = nodes[key]!;
      final expanded = _searchQuery.isNotEmpty ||
          _expandedFolders.contains(node.fullPath);
      final count = _countAll(node);

      widgets.add(_buildFolderHeader(node, count, expanded, depth));

      if (expanded) {
        if (node.children.isNotEmpty) {
          widgets.addAll(_renderTree(node.children, depth + 1));
        }
        for (final item in node.requests) {
          widgets.add(_buildItem(item, indent: depth + 1));
        }
      }

      widgets.add(Container(height: 1, color: TColors.border));
    }

    return widgets;
  }

  int _countAll(_FolderNode node) {
    var count = node.requests.length;
    for (final child in node.children.values) {
      count += _countAll(child);
    }
    return count;
  }

  Widget _buildFolderHeader(_FolderNode node, int count, bool expanded, int depth) {
    final indent = 12.0 + (depth * 12);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (expanded) {
            _expandedFolders.remove(node.fullPath);
          } else {
            _expandedFolders.add(node.fullPath);
          }
        });
        _saveExpanded();
      },
      child: Container(
        padding: EdgeInsets.fromLTRB(indent, 7, 12, 7),
        color: TColors.surface,
        child: Row(
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 12,
              color: TColors.orange,
            ),
            SizedBox(width: 4),
            Icon(Icons.folder, size: 11, color: TColors.orange),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                node.name,
                style: TextStyle(
                  color: TColors.orange,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Request item row ────────────────────────────────────────────────

  Widget _buildItem(RequestItem item, {int indent = 0}) {
    final selected = item.relativePath == widget.selectedPath;
    final isSelected = _selectedPaths.contains(item.relativePath);
    final leftPad = 12.0 + (indent * 12);

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          setState(() {
            if (isSelected) {
              _selectedPaths.remove(item.relativePath);
              if (_selectedPaths.isEmpty) _selectionMode = false;
            } else {
              _selectedPaths.add(item.relativePath);
            }
          });
          return;
        }
        widget.onRequestSelected(item.relativePath);
      },
      onLongPress: () {
        if (!_selectionMode) {
          setState(() {
            _selectionMode = true;
            _selectedPaths.add(item.relativePath);
          });
        }
      },
      child: Container(
        color: isSelected
            ? TColors.orange.withValues(alpha: 0.1)
            : selected
                ? TColors.surface
                : Colors.transparent,
        padding: EdgeInsets.fromLTRB(leftPad, 7, 12, 7),
        child: Row(
          children: [
            if (_selectionMode)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  isSelected
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 14,
                  color: isSelected ? TColors.orange : TColors.mutedText,
                ),
              ),
            _methodLabel(item.method),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                item.displayName,
                style: TextStyle(
                  color: selected ? TColors.green : TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_selectionMode) ...[
              SizedBox(width: 4),
              GestureDetector(
                onTapDown: (details) =>
                    _showContextMenu(context, item, details),
                child:
                    Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _methodLabel(String method) {
    final color = _methodColor(method);
    return SizedBox(
      width: 42,
      child: Text(
        method.padRight(6).substring(0, 6).toUpperCase(),
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _methodColor(String method) {
    return switch (method) {
      'GET' => TColors.green,
      'POST' => TColors.cyan,
      'PUT' => TColors.orange,
      'PATCH' => TColors.yellow,
      'DELETE' => TColors.red,
      'HEAD' => TColors.mutedText,
      'OPTIONS' => TColors.mutedText,
      _ => TColors.foreground,
    };
  }

  // ── Context menu ────────────────────────────────────────────────────

  void _showContextMenu(
      BuildContext context, RequestItem item, TapDownDetails details) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    showMenu<String>(
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
        PopupMenuItem(
            value: 'duplicate',
            height: 36,
            child: _menuItem(Icons.content_copy, 'duplicate')),
        PopupMenuItem(
            value: 'duplicate_env',
            height: 36,
            child: _menuItem(Icons.sync_alt, 'duplicate to env')),
        PopupMenuItem(
            value: 'notes', height: 36, child: _menuItem(Icons.notes, 'notes')),
        PopupMenuItem(
            value: 'share', height: 36, child: _menuItem(Icons.share, 'share')),
        PopupMenuItem(
            value: 'rename', height: 36, child: _menuItem(Icons.edit, 'rename')),
        PopupMenuItem(
            value: 'delete', height: 36, child: _menuItem(Icons.delete, 'delete')),
      ],
    ).then((value) async {
      if (value == 'duplicate') {
        final posix = item.relativePath.replaceAll('\\', '/');
        final slash = posix.lastIndexOf('/');
        final baseName = slash >= 0 ? posix.substring(slash + 1) : posix;
        final nameWithoutExt = baseName.replaceAll('.curl', '');
        final suggested = '${nameWithoutExt}_copy';
        final newName = await _showNameDialog(suggested, title: 'duplicate as');
        if (newName != null && newName.trim().isNotEmpty && newName.trim() != suggested) {
          await ref.read(requestServiceProvider).duplicateRequest(
            widget.projectId,
            item.relativePath,
            newName: newName.trim(),
          );
          _load();
        }
      } else if (value == 'duplicate_env') {
        await _duplicateToEnv(item);
      } else if (value == 'notes') {
        await _showNotesDialog(item);
      } else if (value == 'share') {
        final content = await ref.read(requestServiceProvider).readCurl(
              widget.projectId,
              item.relativePath,
            );
        if (content != null && mounted) {
          Share.share(content);
        }
      } else if (value == 'rename') {
        final name = await _showNameDialog(item.displayName);
        if (name != null && name.trim().isNotEmpty) {
          await ref.read(requestServiceProvider).renameRequest(
            widget.projectId,
            item.relativePath,
            name.trim(),
          );
          _load();
        }
      } else if (value == 'delete') {
        await ref.read(requestServiceProvider).deleteRequest(
          widget.projectId,
          item.relativePath,
        );
        _load();
      }
    });
  }

  Future<void> _showNotesDialog(RequestItem item) async {
    final service = ref.read(requestServiceProvider);
    final existing = await service.readNotes(widget.projectId, item.relativePath) ?? '';
    if (!mounted) return;

    final controller = TextEditingController(text: existing);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Row(
          children: [
            Icon(Icons.notes, size: 14, color: TColors.cyan),
            SizedBox(width: 8),
            Text('notes',
                style: TextStyle(
                    color: TColors.foreground,
                    fontFamily: 'monospace',
                    fontSize: 14)),
            Spacer(),
            Text(item.displayName,
                style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10)),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(maxHeight: 400),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: TColors.green,
            maxLines: null,
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12),
            decoration: InputDecoration(
              hintText: 'write notes here (markdown)...',
              hintStyle: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 12),
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel',
                style: TextStyle(
                    color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('save',
                style:
                    TextStyle(color: TColors.green, fontFamily: 'monospace')),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final content = controller.text.trim();
      if (content.isEmpty) return;
      await service.writeNotes(
        widget.projectId,
        item.relativePath,
        content,
      );
    }
  }

  Future<void> _duplicateToEnv(RequestItem item) async {
    final envs = await ref.read(envServiceProvider).getAll(widget.projectId);
    if (envs.isEmpty) {
      if (!mounted) return;
      showTerminalToast(context, 'no environments found — create one first');
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text('duplicate to env',
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: envs.length,
            itemBuilder: (ctx, i) {
              final env = envs[i];
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(env.name),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  color: TColors.surface,
                  margin: EdgeInsets.only(bottom: 4),
                  child: Text(
                    env.name.toLowerCase(),
                    style: TextStyle(
                      color: TColors.cyan,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel',
                style: TextStyle(
                    color: TColors.mutedText, fontFamily: 'monospace')),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;

    final sanitized = selected.trim().toLowerCase().replaceAll(RegExp(r'[^\w]'), '-');
    final posix = item.relativePath.replaceAll('\\', '/');
    final slash = posix.lastIndexOf('/');
    final baseName = slash >= 0 ? posix.substring(slash + 1) : posix;
    final nameWithoutExt = baseName.replaceAll('.curl', '');
    final newName = '$nameWithoutExt-$sanitized';

    final newPath = await ref.read(requestServiceProvider).duplicateRequest(
      widget.projectId,
      item.relativePath,
      newName: newName,
    );

    final meta = await ref.read(requestServiceProvider).readMeta(
      widget.projectId,
      newPath,
    );
    await ref.read(requestServiceProvider).updateMeta(
      widget.projectId,
      newPath,
      meta.copyWith(targetEnv: selected),
    );

    _load();
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

  Future<String?> _showNameDialog(String initial, {String title = 'rename'}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text(title,
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 14)),
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: TColors.green,
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 13),
            decoration: InputDecoration(
              hintText: 'name',
              hintStyle: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 13),
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
            child: Text('cancel',
                style: TextStyle(
                    color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('ok',
                style:
                    TextStyle(color: TColors.green, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ── Batch delete ────────────────────────────────────────────────────

  Future<void> _batchDelete() async {
    final count = _selectedPaths.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text('delete $count requests?',
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 14)),
        content: Text('this cannot be undone.',
            style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('cancel',
                style: TextStyle(
                    color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('delete',
                style:
                    TextStyle(color: TColors.red, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final path in _selectedPaths.toList()) {
      await ref.read(requestServiceProvider).deleteRequest(
        widget.projectId,
        path,
      );
    }
    if (mounted) {
      _exitSelectionMode();
      _load();
    }
  }

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          TermButton(
            icon: Icons.add,
            label: 'new',
            onTap: widget.onNewRequest,
            accent: true,
          ),
          Spacer(),
          TermButton(icon: Icons.sync, label: 'sync', onTap: _load),
        ],
      ),
    );
  }
}

class _FolderNode {
  final String name;
  final String fullPath;
  final Map<String, _FolderNode> children = {};
  final List<RequestItem> requests = [];

  _FolderNode({required this.name, required this.fullPath});
}
