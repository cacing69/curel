import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/services/history_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HistoryPage extends StatefulWidget {
  final HistoryService historyService;
  final String? currentProjectId;
  final String? currentProjectName;
  final ValueChanged<String> onSelect;

  const HistoryPage({
    required this.historyService,
    this.currentProjectId,
    this.currentProjectName,
    required this.onSelect,
    super.key,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryItem> _items = [];
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
    final items = await widget.historyService.getAll(
      projectId: _showOnlyCurrentProject ? widget.currentProjectId : null,
    );
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: TColors.green))
                  : _items.isEmpty
                      ? const Center(
                          child: Text(
                            'no history yet',
                            style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => Container(height: 1, color: TColors.border),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _buildItem(item);
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'history',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.currentProjectId != null) ...[
            GestureDetector(
              onTap: () {
                setState(() => _showOnlyCurrentProject = !_showOnlyCurrentProject);
                _load();
              },
              child: Row(
                children: [
                  Icon(
                    _showOnlyCurrentProject ? Icons.filter_alt : Icons.filter_alt_off,
                    size: 14,
                    color: _showOnlyCurrentProject ? TColors.green : TColors.mutedText,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showOnlyCurrentProject ? (widget.currentProjectName ?? 'project') : 'all',
                    style: TextStyle(
                      color: _showOnlyCurrentProject ? TColors.green : TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          GestureDetector(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: TColors.surface,
                  shape: const RoundedRectangleBorder(),
                  title: const Text('clear history?',
                      style: TextStyle(
                          color: TColors.foreground,
                          fontFamily: 'monospace',
                          fontSize: 14)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('cancel',
                            style: TextStyle(color: TColors.mutedText))),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('clear',
                            style: TextStyle(color: TColors.red))),
                  ],
                ),
              );
              if (confirm == true) {
                await widget.historyService.clear();
                _load();
              }
            },
            child: const Icon(Icons.delete_sweep, size: 18, color: TColors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(HistoryItem item) {
    final time = DateFormat('yyyy-MM-dd HH:mm').format(item.timestamp);
    final code = item.statusCode;

    return InkWell(
      onTap: () {
        widget.onSelect(item.curlCommand);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.method ?? 'CURL',
                  style: const TextStyle(
                    color: TColors.purple,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (code != null)
                  Text(
                    '$code',
                    style: TextStyle(
                      color: code >= 200 && code < 300 ? TColors.green : TColors.red,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                const Spacer(),
                Text(
                  time,
                  style: const TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.url ?? item.curlCommand,
              style: const TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
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
