import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GitProvidersPage extends ConsumerStatefulWidget {
  const GitProvidersPage({super.key});

  @override
  ConsumerState<GitProvidersPage> createState() => _GitProvidersPageState();
}

class _GitProvidersPageState extends ConsumerState<GitProvidersPage> {
  List<GitProviderModel> _providers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ps = await ref.read(gitProviderServiceProvider).getAll();
    if (mounted) {
      setState(() {
        _providers = ps;
        _loading = false;
      });
    }
  }

  Future<void> _showProviderDialog({GitProviderModel? provider}) async {
    final isEdit = provider != null;
    final nameCtrl = TextEditingController(text: provider?.name ?? '');
    final typeCtrl = TextEditingController(text: provider?.type ?? 'github');
    final baseUrlCtrl = TextEditingController(text: provider?.baseUrl ?? '');
    final tokenCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: TColors.surface,
              title: Text(
                isEdit ? 'edit provider' : 'add provider',
                style: const TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildField('name', 'My GitHub', nameCtrl),
                    const SizedBox(height: 12),
                    const Text('type',
                        style: TextStyle(
                            color: TColors.cyan,
                            fontFamily: 'monospace',
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: TColors.background,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: typeCtrl.text,
                          dropdownColor: TColors.surface,
                          isExpanded: true,
                          style: const TextStyle(
                              color: TColors.foreground,
                              fontFamily: 'monospace',
                              fontSize: 13),
                          items: const [
                            DropdownMenuItem(
                                value: 'github', child: Text('github')),
                            DropdownMenuItem(
                                value: 'gitlab', child: Text('gitlab')),
                            DropdownMenuItem(
                                value: 'gitea', child: Text('gitea')),
                            DropdownMenuItem(
                                value: 'bitbucket', child: Text('bitbucket')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setStateDialog(() => typeCtrl.text = v);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildField('base url (optional)', 'https://gitlab.company.com',
                        baseUrlCtrl),
                    const SizedBox(height: 12),
                    _buildField(
                        isEdit ? 'token (leave empty to keep)' : 'token (pat)',
                        'ghp_xxx...',
                        tokenCtrl,
                        obscure: true),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('cancel',
                      style: TextStyle(
                          color: TColors.mutedText, fontFamily: 'monospace')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('save',
                      style: TextStyle(
                          color: TColors.green, fontFamily: 'monospace')),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final name = nameCtrl.text.trim();
      final type = typeCtrl.text;
      var baseUrl = baseUrlCtrl.text.trim();
      if (baseUrl.isEmpty) baseUrl = '';
      final token = tokenCtrl.text.trim();

      if (name.isEmpty) return;
      if (!isEdit && token.isEmpty) return; // Token required for new

      if (isEdit) {
        await ref.read(gitProviderServiceProvider).update(
              provider.copyWith(name: name, type: type, baseUrl: baseUrl),
              newToken: token.isNotEmpty ? token : null,
            );
      } else {
        await ref.read(gitProviderServiceProvider).create(
              name: name,
              type: type,
              baseUrl: baseUrl,
              token: token,
            );
      }
      await _load();
    }
  }

  Widget _buildField(
      String label, String hint, TextEditingController controller,
      {bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: TColors.cyan,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            cursorColor: TColors.green,
            style: const TextStyle(
                color: TColors.foreground,
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

  Future<void> _deleteProvider(GitProviderModel provider) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
        title: const Text('delete provider?',
            style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 14)),
        content: Text('are you sure you want to delete ${provider.name}?',
            style: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('cancel',
                style: TextStyle(
                    color: TColors.mutedText, fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('delete',
                style:
                    TextStyle(color: TColors.red, fontFamily: 'monospace')),
          ),
        ],
      ),
    );

    if (result == true) {
      await ref.read(gitProviderServiceProvider).delete(provider.id);
      await _load();
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
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: TColors.green, strokeWidth: 2))
                  : _providers.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          itemCount: _providers.length,
                          separatorBuilder: (_, __) =>
                              Container(height: 1, color: TColors.border),
                          itemBuilder: (_, i) => _buildTile(_providers[i]),
                        ),
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
            child: const Icon(Icons.arrow_back,
                size: 18, color: TColors.mutedText),
          ),
          const SizedBox(width: 8),
          const Text(
            'git providers',
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
    return const Center(
      child: Text(
        'no git providers configured.\nadd one to enable remote sync.',
        textAlign: TextAlign.center,
        style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5),
      ),
    );
  }

  Widget _buildTile(GitProviderModel provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.hub, size: 16, color: TColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: const TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'type: ${provider.type}${provider.baseUrl != null && provider.baseUrl!.isNotEmpty ? ' | url: ${provider.baseUrl}' : ''}',
                  style: const TextStyle(
                      color: TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 16, color: TColors.mutedText),
            onPressed: () => _showProviderDialog(provider: provider),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.delete, size: 16, color: TColors.red),
            onPressed: () => _deleteProvider(provider),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      color: TColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          TermButton(
              icon: Icons.add,
              label: 'add provider',
              onTap: () => _showProviderDialog(),
              accent: true),
        ],
      ),
    );
  }
}
