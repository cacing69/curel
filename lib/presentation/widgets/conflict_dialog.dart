import 'package:curel/domain/services/diff_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

class ConflictDialog extends StatefulWidget {
  final List<FileChange> changes;

  const ConflictDialog({super.key, required this.changes});

  @override
  State<ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<ConflictDialog> {
  int _selectedIndex = 0;
  final Map<String, String> _resolutions = {};

  @override
  void initState() {
    super.initState();
    for (final c in widget.changes) {
      _resolutions[c.path] = 'local';
    }
  }

  void _setAll(String choice) {
    setState(() {
      for (final c in widget.changes) {
        _resolutions[c.path] = choice;
      }
    });
  }

  int get _resolvedCount => _resolutions.length;

  @override
  Widget build(BuildContext context) {
    if (widget.changes.isEmpty) return const SizedBox.shrink();

    final currentChange = widget.changes[_selectedIndex];

    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: TColors.border)),
        child: Column(
          children: [
            _buildHeader(),
            Divider(height: 1, color: TColors.border),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSidebar(),
                  Expanded(child: _buildSideBySide(currentChange)),
                ],
              ),
            ),
            Divider(height: 1, color: TColors.border),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: TColors.surface,
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: TColors.orange),
          const SizedBox(width: 8),
          Text(
            'sync conflict detected',
            style: TextStyle(
              color: TColors.orange,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: TColors.foreground),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 130,
      child: Container(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: TColors.border)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  _actionChip('all L', TColors.cyan, () => _setAll('local')),
                  const SizedBox(width: 4),
                  _actionChip('all R', TColors.green, () => _setAll('remote')),
                ],
              ),
            ),
            Divider(height: 1, color: TColors.border),
            Expanded(
              child: ListView.builder(
                itemCount: widget.changes.length,
                itemBuilder: (context, index) {
                  final change = widget.changes[index];
                  final isSelected = _selectedIndex == index;
                  final resolution = _resolutions[change.path] ?? 'local';

                  return InkWell(
                    onTap: () => setState(() => _selectedIndex = index),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      color: isSelected ? TColors.surface : Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            change.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected ? TColors.foreground : TColors.comment,
                              fontFamily: 'monospace',
                              fontSize: 9,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              _changeIcon(change.type),
                              const SizedBox(width: 4),
                              _resolutionChip('L', resolution == 'local', () {
                                setState(() => _resolutions[change.path] = 'local');
                              }),
                              const SizedBox(width: 3),
                              _resolutionChip('R', resolution == 'remote', () {
                                setState(() => _resolutions[change.path] = 'remote');
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolutionChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? (label == 'L' ? TColors.cyan.withValues(alpha: 0.3) : TColors.green.withValues(alpha: 0.3))
              : Colors.transparent,
          border: Border.all(
            color: active
                ? (label == 'L' ? TColors.cyan : TColors.green)
                : TColors.comment,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? (label == 'L' ? TColors.cyan : TColors.green)
                : TColors.comment,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _actionChip(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _changeIcon(ChangeType type) {
    return switch (type) {
      ChangeType.added => Icon(Icons.add, size: 12, color: TColors.green),
      ChangeType.deleted => Icon(Icons.remove, size: 12, color: TColors.red),
      ChangeType.modified => Icon(Icons.edit, size: 12, color: TColors.yellow),
      ChangeType.unchanged => Icon(Icons.check, size: 12, color: TColors.comment),
    };
  }

  Widget _buildSideBySide(FileChange change) {
    final localLines = (change.oldContent ?? '').split('\n');
    final remoteLines = (change.newContent ?? '').split('\n');

    if (change.type == ChangeType.added) {
      return _buildTwoPanes(
        left: _buildPaneContent('local', const [], TColors.comment),
        right: _buildPaneContent('remote', remoteLines, TColors.green, highlight: true),
      );
    }

    if (change.type == ChangeType.deleted) {
      return _buildTwoPanes(
        left: _buildPaneContent('local', localLines, TColors.red, highlight: true),
        right: _buildPaneContent('remote', const [], TColors.comment),
      );
    }

    // Modified: compute line-level diff
    final dmp = DiffMatchPatch();
    final diffs = dmp.diff(change.oldContent ?? '', change.newContent ?? '');

    final leftLines = <_DiffLine>[];
    final rightLines = <_DiffLine>[];

    for (final diff in diffs) {
      final lines = diff.text.split('\n');
      // Remove trailing empty from split if text ends with \n
      if (diff.text.endsWith('\n') && lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }

      for (final line in lines) {
        if (diff.operation == DIFF_DELETE) {
          leftLines.add(_DiffLine(line, DiffType.removed));
        } else if (diff.operation == DIFF_INSERT) {
          rightLines.add(_DiffLine(line, DiffType.added));
        } else {
          leftLines.add(_DiffLine(line, DiffType.equal));
          rightLines.add(_DiffLine(line, DiffType.equal));
        }
      }
    }

    return _buildTwoPanes(
      left: _buildDiffPane('local', leftLines),
      right: _buildDiffPane('remote', rightLines),
    );
  }

  Widget _buildTwoPanes({required Widget left, required Widget right}) {
    return Column(
      children: [
        _paneHeader('local', TColors.cyan),
        Expanded(child: left),
        Divider(height: 1, color: TColors.border),
        _paneHeader('remote', TColors.green),
        Expanded(child: right),
      ],
    );
  }

  Widget _paneHeader(String label, Color color) {
    return Container(
      height: 20,
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDiffPane(String title, List<_DiffLine> lines) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        Color? bg;
        Color fg = TColors.foreground;
        String prefix = ' ';

        switch (line.type) {
          case DiffType.removed:
            bg = TColors.red.withValues(alpha: 0.15);
            fg = TColors.red;
            prefix = '-';
          case DiffType.added:
            bg = TColors.green.withValues(alpha: 0.15);
            fg = TColors.green;
            prefix = '+';
          case DiffType.equal:
            fg = TColors.comment;
        }

        return Container(
          color: bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  prefix,
                  style: TextStyle(
                    color: fg,
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  line.text,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaneContent(String title, List<String> lines, Color color, {bool highlight = false}) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: lines.isEmpty ? 1 : lines.length,
      itemBuilder: (context, index) {
        if (lines.isEmpty) {
          return Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              title == 'local' ? 'file does not exist locally' : 'file does not exist remotely',
              style: TextStyle(
                color: TColors.comment,
                fontFamily: 'monospace',
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Container(
          color: highlight ? color.withValues(alpha: 0.1) : null,
          child: Text(
            lines[index],
            style: TextStyle(
              color: highlight ? color : TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.all(12),
      color: TColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TermButton(
            label: 'cancel',
            onTap: () => Navigator.pop(context),
            color: TColors.comment,
            bordered: true,
          ),
          const SizedBox(width: 12),
          TermButton(
            label: 'resolve $_resolvedCount files',
            onTap: _resolvedCount == 0
                ? null
                : () => Navigator.pop(context, _resolutions),
            color: TColors.green,
            icon: Icons.check,
            bordered: true,
          ),
        ],
      ),
    );
  }
}

enum DiffType { equal, added, removed }

class _DiffLine {
  final String text;
  final DiffType type;
  const _DiffLine(this.text, this.type);
}
