import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/models/bookmark_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _HistoryView { history, bookmark }

class HistoryPage extends ConsumerStatefulWidget {
  final String? currentProjectId;
  final String? currentProjectName;
  final ValueChanged<String> onSelect;

  HistoryPage({
    this.currentProjectId,
    this.currentProjectName,
    required this.onSelect,
    super.key,
  });

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  var _view = _HistoryView.history;
  List<HistoryItem> _historyItems = [];
  List<BookmarkItem> _bookmarkItems = [];
  Set<int> _bookmarkedHistoryIds = {};
  bool _loading = true;
  bool _showOnlyCurrentProject = false;

  @override
  void initState() {
    super.initState();
    _showOnlyCurrentProject = widget.currentProjectId != null;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final allBookmarks = await ref.read(bookmarkServiceProvider).getAll();
    final bookmarkedIds = <int>{};
    for (final b in allBookmarks) {
      final id = b.originHistoryId;
      if (id != null) bookmarkedIds.add(id);
    }

    final projectFilter = _showOnlyCurrentProject
        ? widget.currentProjectId
        : null;
    List<HistoryItem> historyItems = [];
    List<BookmarkItem> bookmarkItems = [];

    if (_view == _HistoryView.history) {
      historyItems = await ref.read(historyServiceProvider).getAll(
        projectId: projectFilter,
      );
    } else {
      bookmarkItems = await ref.read(bookmarkServiceProvider).getAll(
        projectId: projectFilter,
      );
    }

    if (mounted) {
      setState(() {
        _historyItems = historyItems;
        _bookmarkItems = bookmarkItems;
        _bookmarkedHistoryIds = bookmarkedIds;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsEmpty = _view == _HistoryView.history
        ? _historyItems.isEmpty
        : _bookmarkItems.isEmpty;
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: TerminalLoader())
                  : itemsEmpty
                  ? Center(
                      child: Text(
                        'empty',
                        style: TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _view == _HistoryView.history
                          ? _historyItems.length
                          : _bookmarkItems.length,
                      separatorBuilder: (_, index) =>
                          Container(height: 1, color: TColors.border),
                      itemBuilder: (context, index) {
                        if (_view == _HistoryView.history) {
                          final item = _historyItems[index];
                          return _buildHistoryItem(item);
                        }
                        final item = _bookmarkItems[index];
                        return _buildBookmarkItem(item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          SizedBox(width: 8),
          Text(
            _view == _HistoryView.history ? 'history' : 'bookmark',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 12),
          FlatTab(
            label: 'history',
            selected: _view == _HistoryView.history,
            onTap: () {
              if (_view == _HistoryView.history) return;
              setState(() => _view = _HistoryView.history);
              _load();
            },
          ),
          SizedBox(width: 6),
          FlatTab(
            label: 'bookmark',
            selected: _view == _HistoryView.bookmark,
            onTap: () {
              if (_view == _HistoryView.bookmark) return;
              setState(() => _view = _HistoryView.bookmark);
              _load();
            },
          ),
          Spacer(),
          if (widget.currentProjectId != null) ...[
            GestureDetector(
              onTap: () {
                setState(
                  () => _showOnlyCurrentProject = !_showOnlyCurrentProject,
                );
                _load();
              },
              child: Row(
                children: [
                  Icon(
                    _showOnlyCurrentProject
                        ? Icons.filter_alt
                        : Icons.filter_alt_off,
                    size: 14,
                    color: _showOnlyCurrentProject
                        ? TColors.green
                        : TColors.mutedText,
                  ),
                  SizedBox(width: 4),
                  Text(
                    _showOnlyCurrentProject
                        ? (widget.currentProjectName ?? 'project')
                        : 'all',
                    style: TextStyle(
                      color: _showOnlyCurrentProject
                          ? TColors.green
                          : TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
          ],
          GestureDetector(
            onTap: () async {
              if (_view == _HistoryView.bookmark) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: TColors.background,
                    title: Text(
                      'clear bookmark?',
                      style: TextStyle(
                        color: TColors.foreground,
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'cancel',
                          style: TextStyle(color: TColors.mutedText),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'clear',
                          style: TextStyle(color: TColors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(bookmarkServiceProvider).clear();
                  _load();
                }
                return;
              }

              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: TColors.background,
                  title: Text(
                    'clear history?',
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 14,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        'cancel',
                        style: TextStyle(color: TColors.mutedText),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        'clear',
                        style: TextStyle(color: TColors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(historyServiceProvider).clear();
                _load();
              }
            },
            child: Icon(Icons.delete_sweep, size: 18, color: TColors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBookmark(HistoryItem item) async {
    final projectName =
        item.projectId != null && item.projectId == widget.currentProjectId
        ? widget.currentProjectName
        : null;
    final saved = await ref.read(bookmarkServiceProvider).toggleFromHistory(
      item,
      projectName: projectName,
    );
    if (!mounted) return;
    setState(() {
      if (saved) {
        _bookmarkedHistoryIds.add(item.id);
      } else {
        _bookmarkedHistoryIds.remove(item.id);
      }
      if (_view == _HistoryView.bookmark) {
        _bookmarkItems.removeWhere((b) => b.originHistoryId == item.id);
      }
    });
    showTerminalToast(context, saved ? 'bookmarked' : 'bookmark removed');
  }

  Widget _buildHistoryItem(HistoryItem item) {
    final time = DateFormat('yyyy-MM-dd HH:mm').format(item.timestamp);
    final code = item.statusCode;
    final isBookmarked = _bookmarkedHistoryIds.contains(item.id);

    return InkWell(
      onTap: () {
        widget.onSelect(item.curlCommand);
        Navigator.pop(context);
      },
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.method ?? 'CURL',
                  style: TextStyle(
                    color: TColors.purple,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                if (code != null)
                  Text(
                    '$code',
                    style: TextStyle(
                      color: code >= 200 && code < 300
                          ? TColors.green
                          : TColors.red,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                Spacer(),
                GestureDetector(
                  onTap: () => _toggleBookmark(item),
                  child: Icon(
                    isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                    size: 16,
                    color: isBookmarked ? TColors.green : TColors.mutedText,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  time,
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              item.url ?? item.curlCommand,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.projectId != null) ...[
              SizedBox(height: 4),
              Text(
                'src: history • project: ${item.projectId}',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: 4),
            Text(
              item.curlCommand,
              style: TextStyle(
                color: TColors.mutedText.withValues(alpha: 0.7),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookmarkItem(BookmarkItem item) {
    final time = DateFormat('yyyy-MM-dd HH:mm').format(item.savedAt);
    final code = item.statusCode;

    return InkWell(
      onTap: () {
        widget.onSelect(item.curlCommand);
        Navigator.pop(context);
      },
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.method ?? 'CURL',
                  style: TextStyle(
                    color: TColors.purple,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                if (code != null)
                  Text(
                    '$code',
                    style: TextStyle(
                      color: code >= 200 && code < 300
                          ? TColors.green
                          : TColors.red,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                Spacer(),
                GestureDetector(
                  onTap: () async {
                    await ref.read(bookmarkServiceProvider).removeById(item.id);
                    if (!mounted) return;
                    setState(() {
                      _bookmarkItems.removeWhere((e) => e.id == item.id);
                      final originId = item.originHistoryId;
                      if (originId != null) {
                        _bookmarkedHistoryIds.remove(originId);
                      }
                    });
                    showTerminalToast(context, 'bookmark removed');
                  },
                  child: Icon(
                    Icons.bookmark,
                    size: 16,
                    color: TColors.green,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  time,
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              item.url ?? item.curlCommand,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              'src: ${item.source} • project: ${item.projectName ?? item.projectId ?? '-'}',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              item.curlCommand,
              style: TextStyle(
                color: TColors.mutedText.withValues(alpha: 0.7),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
