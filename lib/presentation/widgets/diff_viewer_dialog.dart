import 'package:curel/domain/services/diff_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

class DiffViewerDialog extends StatefulWidget {
  final List<FileChange> changes;
  final String title;

  const DiffViewerDialog({
    super.key,
    required this.changes,
    this.title = 'pending changes',
  });

  @override
  State<DiffViewerDialog> createState() => _DiffViewerDialogState();
}

class _DiffViewerDialogState extends State<DiffViewerDialog> {
  int _selectedIndex = 0;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    // Default to all selected
    _selectedPaths.addAll(widget.changes.map((c) => c.path));
  }

  void _toggleAll(bool select) {
    setState(() {
      if (select) {
        _selectedPaths.addAll(widget.changes.map((c) => c.path));
      } else {
        _selectedPaths.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.changes.isEmpty) return const SizedBox.shrink();
    
    final currentChange = widget.changes[_selectedIndex];

    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: const EdgeInsets.all(20),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: TColors.border),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: TColors.surface,
              child: Row(
                children: [
                  const Icon(Icons.compare_arrows, size: 18, color: TColors.foreground),
                  const SizedBox(width: 8),
                  Text(
                    widget.title.toLowerCase(),
                    style: const TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: TColors.foreground),
                    onPressed: () => Navigator.pop(context, null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: TColors.border),
            
            // Selection Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  _SmallButton(
                    label: 'select all',
                    onPressed: () => _toggleAll(true),
                  ),
                  const SizedBox(width: 8),
                  _SmallButton(
                    label: 'none',
                    onPressed: () => _toggleAll(false),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedPaths.length} of ${widget.changes.length} selected',
                    style: const TextStyle(
                      color: TColors.comment,
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: TColors.border),

            // Content
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Sidebar: File List
                  SizedBox(
                    width: 160,
                    child: Container(
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: TColors.border)),
                      ),
                      child: ListView.builder(
                        itemCount: widget.changes.length,
                        itemBuilder: (context, index) {
                          final change = widget.changes[index];
                          final isSelected = _selectedIndex == index;
                          final isChecked = _selectedPaths.contains(change.path);
                          
                          Color typeColor;
                          String typeSymbol;
                          switch (change.type) {
                            case ChangeType.added:
                              typeColor = TColors.green;
                              typeSymbol = '+';
                              break;
                            case ChangeType.deleted:
                              typeColor = TColors.red;
                              typeSymbol = '-';
                              break;
                            case ChangeType.modified:
                              typeColor = TColors.yellow;
                              typeSymbol = 'M';
                              break;
                            default:
                              typeColor = TColors.comment;
                              typeSymbol = ' ';
                          }

                          return InkWell(
                            onTap: () => setState(() => _selectedIndex = index),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              color: isSelected ? TColors.surface : Colors.transparent,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: isChecked,
                                      activeColor: TColors.green,
                                      checkColor: TColors.background,
                                      side: const BorderSide(color: TColors.comment),
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedPaths.add(change.path);
                                          } else {
                                            _selectedPaths.remove(change.path);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    typeSymbol,
                                    style: TextStyle(
                                      color: typeColor,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      change.path,
                                      style: TextStyle(
                                        color: isSelected ? TColors.foreground : TColors.comment,
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  // Main: Diff View
                  Expanded(
                    child: Container(
                      color: TColors.background,
                      child: _buildDiffContent(currentChange),
                    ),
                  ),
                ],
              ),
            ),
            
            // Footer
            const Divider(height: 1, color: TColors.border),
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionButton(
                    label: 'cancel',
                    onPressed: () => Navigator.pop(context, null),
                    color: TColors.comment,
                  ),
                  const SizedBox(width: 12),
                  _ActionButton(
                    label: 'sync ${_selectedPaths.length} files',
                    onPressed: _selectedPaths.isEmpty ? () {} : () => Navigator.pop(context, _selectedPaths.toList()),
                    color: _selectedPaths.isEmpty ? TColors.comment : TColors.green,
                    icon: Icons.sync,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiffContent(FileChange change) {
    if (change.type == ChangeType.added) {
      return _buildRawView(change.newContent ?? '', TColors.green);
    }
    if (change.type == ChangeType.deleted) {
      return _buildRawView(change.oldContent ?? '', TColors.red);
    }
    
    // Modified: Line by line diff
    final diffs = change.diffs ?? [];
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: diffs.length,
      itemBuilder: (context, index) {
        final diff = diffs[index];
        Color? bgColor;
        Color? textColor;
        String prefix = ' ';
        
        if (diff.operation == DIFF_INSERT) {
          bgColor = TColors.green.withValues(alpha: 0.15);
          textColor = TColors.green;
          prefix = '+';
        } else if (diff.operation == DIFF_DELETE) {
          bgColor = TColors.red.withValues(alpha: 0.15);
          textColor = TColors.red;
          prefix = '-';
        } else {
          textColor = TColors.comment;
        }

        return Container(
          color: bgColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  prefix,
                  style: TextStyle(
                    color: textColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  diff.text,
                  style: TextStyle(
                    color: diff.operation == DIFF_EQUAL ? TColors.foreground : textColor,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRawView(String content, Color color) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Text(
        content,
        style: TextStyle(
          color: color,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SmallButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: TColors.comment)),
        child: Text(
          label.toLowerCase(),
          style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 10),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;
  final IconData? icon;

  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label.toLowerCase(),
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
