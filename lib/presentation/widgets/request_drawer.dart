import 'package:curel/domain/models/request_item_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final requests = await ref.read(requestServiceProvider).listRequests(widget.projectId);
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
    return _requests.where((r) => r.displayName.toLowerCase().contains(q)).toList();
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
          _buildSearch(),
          Container(height: 1, color: TColors.border),
          Expanded(child: _loading ? _buildLoading() : _buildList()),
          Container(height: 1, color: TColors.border),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
    return Center(
      child: CircularProgressIndicator(
        color: TColors.green,
        strokeWidth: 2,
      ),
    );
  }

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

    final grouped = _groupByFolder(items);
    final slivers = <Widget>[];

    for (final entry in grouped.entries) {
      final folder = entry.key;
      final folderItems = entry.value;

      if (folder.isNotEmpty) {
        slivers.add(SliverToBoxAdapter(
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(Icons.folder, size: 12, color: TColors.orange),
                SizedBox(width: 6),
                Text(
                  folder,
                  style: TextStyle(
                    color: TColors.orange,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ));
      }

      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _buildItem(folderItems[i]),
          childCount: folderItems.length,
        ),
      ));

      slivers.add(SliverToBoxAdapter(
        child: Container(height: 1, color: TColors.border),
      ));
    }

    return CustomScrollView(
      slivers: slivers,
    );
  }

  Map<String, List<RequestItem>> _groupByFolder(List<RequestItem> items) {
    final map = <String, List<RequestItem>>{};
    for (final item in items) {
      final posix = item.relativePath.replaceAll('\\', '/');
      final slash = posix.lastIndexOf('/');
      final folder = slash >= 0 ? posix.substring(0, slash) : '';
      map.putIfAbsent(folder, () => []).add(item);
    }
    final sorted = <String, List<RequestItem>>{};
    final folders = map.keys.toList()..sort();
    if (map.containsKey('')) {
      sorted[''] = map['']!;
      folders.remove('');
    }
    for (final f in folders) {
      sorted[f] = map[f]!;
    }
    return sorted;
  }

  Widget _buildItem(RequestItem item) {
    final selected = item.relativePath == widget.selectedPath;
    final code = item.lastStatusCode;

    return GestureDetector(
      onTap: () => widget.onRequestSelected(item.relativePath),
      child: Container(
        color: selected ? TColors.surface : Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            _methodDot(item),
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
            if (code != null) ...[
              Text(
                '$code',
                style: TextStyle(
                  color: code >= 200 && code < 300 ? TColors.green : TColors.red,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
            SizedBox(width: 4),
            GestureDetector(
              onTapDown: (details) => _showContextMenu(context, item, details),
              child: Icon(Icons.more_vert, size: 14, color: TColors.mutedText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _methodDot(RequestItem item) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: TColors.green,
        shape: BoxShape.circle,
      ),
    );
  }

  void _showContextMenu(BuildContext context, RequestItem item, TapDownDetails details) {
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
        PopupMenuItem(value: 'share', height: 36, child: _menuItem(Icons.share, 'share')),
        PopupMenuItem(value: 'rename', height: 36, child: _menuItem(Icons.edit, 'rename')),
        PopupMenuItem(value: 'delete', height: 36, child: _menuItem(Icons.delete, 'delete')),
      ],
    ).then((value) async {
      if (value == 'share') {
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

  Future<String?> _showNameDialog(String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        title: Text('rename', style: TextStyle(color: TColors.foreground, fontFamily: 'monospace', fontSize: 14)),
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
