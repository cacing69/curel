import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitConnectDialog extends ConsumerStatefulWidget {
  final Project project;

  const GitConnectDialog({required this.project, super.key});

  @override
  ConsumerState<GitConnectDialog> createState() => _GitConnectDialogState();
}

class _GitConnectDialogState extends ConsumerState<GitConnectDialog> {
  final _urlController = TextEditingController();
  final _branchController = TextEditingController(text: 'main');
  List<GitProviderModel> _providers = [];
  String? _selectedProviderId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.project.remoteUrl ?? '';
    _branchController.text = widget.project.branch ?? 'main';
    _selectedProviderId = widget.project.provider;
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final ps = await ref.read(gitProviderServiceProvider).getAll();
    if (mounted) {
      setState(() {
        _providers = ps;
        if (_selectedProviderId == null && ps.isNotEmpty) {
          _selectedProviderId = ps.first.id;
        }
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      title: const Text(
        'connect to remote git',
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
      content: _loading
          ? const SizedBox(
              height: 100,
              child: Center(
                  child: CircularProgressIndicator(
                      color: TColors.green, strokeWidth: 2)))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('select git provider',
                      style: TextStyle(
                          color: TColors.cyan,
                          fontFamily: 'monospace',
                          fontSize: 12)),
                  const SizedBox(height: 6),
                  if (_providers.isEmpty)
                    const Text('no providers configured. go to settings first.',
                        style: TextStyle(color: TColors.red, fontSize: 11))
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: TColors.background,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedProviderId,
                          dropdownColor: TColors.surface,
                          isExpanded: true,
                          style: const TextStyle(
                              color: TColors.foreground,
                              fontFamily: 'monospace',
                              fontSize: 13),
                          items: _providers
                              .map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedProviderId = v),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildField(
                    'repository url',
                    'https://github.com/user/repo',
                    _urlController,
                    enabled: widget.project.remoteUrl == null,
                  ),
                  if (widget.project.remoteUrl != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'disconnect git first to change repository',
                        style: TextStyle(color: TColors.orange, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildField('branch', 'main', _branchController),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('cancel',
              style: TextStyle(
                  color: TColors.mutedText, fontFamily: 'monospace')),
        ),
        TextButton(
          onPressed: _providers.isEmpty
              ? null
              : () {
                  final url = _urlController.text.trim();
                  final branch = _branchController.text.trim();
                  if (url.isEmpty || branch.isEmpty) return;
                  final updated = widget.project.copyWith(
                    remoteUrl: url,
                    provider: _selectedProviderId,
                    branch: branch,
                    mode: 'git',
                  );
                  Navigator.of(context).pop(updated);
                },
          child: const Text('connect',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _buildField(
      String label, String hint, TextEditingController controller,
      {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: enabled ? TColors.cyan : TColors.mutedText.withValues(alpha: 0.5),
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            enabled: enabled,
            cursorColor: TColors.green,
            style: TextStyle(
                color: enabled ? TColors.foreground : TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
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
      ],
    );
  }
}
