import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BranchPickerDialog extends ConsumerStatefulWidget {
  final String currentBranch;
  final String projectId;

  BranchPickerDialog({
    super.key,
    required this.currentBranch,
    required this.projectId,
  });

  @override
  ConsumerState<BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends ConsumerState<BranchPickerDialog> {
  List<String> _branches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ps = ref.read(projectServiceProvider);
      final project = await ps.getById(widget.projectId);
      if (project == null) throw Exception('project not found');

      final branches = await ref.read(gitSyncServiceProvider).listBranches(project);
      if (mounted) {
        setState(() {
          _branches = branches..sort((a, b) {
            if (a == widget.currentBranch) return -1;
            if (b == widget.currentBranch) return 1;
            return a.compareTo(b);
          });
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _createBranch() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _CreateBranchDialog(fromBranch: widget.currentBranch),
    );

    if (name == null || !mounted) return;

    try {
      final ps = ref.read(projectServiceProvider);
      final project = await ps.getById(widget.projectId);
      if (project == null) return;

      await ref.read(gitSyncServiceProvider).createBranch(project, name, widget.currentBranch);
      await _loadBranches();
      if (mounted) showTerminalToast(context, 'branch "$name" created');
    } catch (e) {
      if (mounted) {
        showTerminalToast(context, 'error: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Row(
        children: [
          Icon(Icons.call_split, size: 16, color: TColors.cyan),
          SizedBox(width: 8),
          Text(
            'branches',
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 280,
        height: 320,
        child: _loading
            ? const Center(child: TerminalLoader())
            : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      style: TextStyle(color: TColors.red, fontFamily: 'monospace', fontSize: 11),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: _branches.length,
                          itemBuilder: (context, index) {
                            final branch = _branches[index];
                            final isCurrent = branch == widget.currentBranch;

                            return InkWell(
                              onTap: isCurrent ? null : () => Navigator.pop(context, branch),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: TColors.border.withValues(alpha: 0.3))),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      child: isCurrent
                                          ? Text('●', style: TextStyle(color: TColors.cyan, fontSize: 10))
                                          : null,
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        branch,
                                        style: TextStyle(
                                          color: isCurrent ? TColors.cyan : TColors.foreground,
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    if (isCurrent)
                                      Text(
                                        'current',
                                        style: TextStyle(
                                          color: TColors.comment,
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Divider(height: 1, color: TColors.border),
                      InkWell(
                        onTap: _createBranch,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 14, color: TColors.green),
                              SizedBox(width: 8),
                              Text(
                                'new branch',
                                style: TextStyle(
                                  color: TColors.green,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel',
              style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace')),
        ),
      ],
    );
  }
}

class _CreateBranchDialog extends StatefulWidget {
  final String fromBranch;

  _CreateBranchDialog({required this.fromBranch});

  @override
  State<_CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<_CreateBranchDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      title: Text(
        'new branch',
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'branch name',
            style: TextStyle(
              color: TColors.cyan,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: TColors.surface,
            child: TextField(
              controller: _controller,
              autofocus: true,
              cursorColor: TColors.green,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'feature/name',
                hintStyle: TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
              },
            ),
          ),
          SizedBox(height: 8),
          Text(
            'from: ${widget.fromBranch}',
            style: TextStyle(
              color: TColors.comment,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('cancel',
              style: TextStyle(color: TColors.mutedText, fontFamily: 'monospace')),
        ),
        TextButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
          child: Text('create',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace')),
        ),
      ],
    );
  }
}
