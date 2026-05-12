import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/git_client.dart';
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
  bool _loadingRepos = false;

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

  Future<void> _browseRepos() async {
    if (_selectedProviderId == null) return;
    final provider =
        _providers.firstWhere((p) => p.id == _selectedProviderId);

    setState(() => _loadingRepos = true);
    try {
      final token = await ref.read(gitProviderServiceProvider).getToken(provider.id);
      if (token == null || token.isEmpty) {
        if (mounted) showTerminalToast(context, 'no token for this provider');
        return;
      }

      final client = GitClient.create(provider.type, baseUrl: provider.baseUrl);
      final repos = await client.listUserRepos(token);

      if (!mounted) return;

      final selected = await showDialog<GitRepo>(
        context: context,
        builder: (ctx) => _RepoPickerDialog(
          repos: repos,
          providerType: provider.type,
        ),
      );

      if (selected != null && mounted) {
        _urlController.text = selected.cloneUrl;
        if (selected.defaultBranch != null) {
          _branchController.text = selected.defaultBranch!;
        }
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'failed to load repos: $e');
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      title: Text(
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
              child: Center(child: TerminalLoader()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('select git provider',
                      style: TextStyle(
                          color: TColors.cyan,
                          fontFamily: 'monospace',
                          fontSize: 12)),
                  SizedBox(height: 6),
                  if (_providers.isEmpty)
                    Text('no providers configured. go to settings first.',
                        style: TextStyle(color: TColors.red, fontSize: 11))
                  else
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      color: TColors.background,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedProviderId,
                          dropdownColor: TColors.surface,
                          isExpanded: true,
                          style: TextStyle(
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
                  SizedBox(height: 16),
                  _buildUrlField(),
                  if (widget.project.remoteUrl != null)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'disconnect git first to change repository',
                        style: TextStyle(color: TColors.orange, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  SizedBox(height: 16),
                  SizedBox(height: 16),
                  _buildField('branch', 'main', _branchController),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel',
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
          child: Text('connect',
              style: TextStyle(color: TColors.green, fontFamily: 'monospace')),
        ),
      ],
    );
  }

  Widget _buildUrlField() {
    final enabled = widget.project.remoteUrl == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('repository url',
            style: TextStyle(
                color: enabled ? TColors.cyan : TColors.mutedText.withValues(alpha: 0.5),
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold)),
        SizedBox(height: 6),
        Container(
          color: TColors.surface,
          padding: EdgeInsets.only(left: 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: enabled,
                  cursorColor: TColors.green,
                  style: TextStyle(
                      color: enabled ? TColors.foreground : TColors.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://github.com/user/repo',
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
              if (enabled)
                GestureDetector(
                  onTap: _loadingRepos ? null : _browseRepos,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: _loadingRepos
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: TColors.green),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search, size: 12, color: TColors.cyan),
                              SizedBox(width: 3),
                              Text(
                                'repos',
                                style: TextStyle(
                                  color: TColors.cyan,
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          ),
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
        SizedBox(height: 6),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      ],
    );
  }
}

class _RepoPickerDialog extends StatefulWidget {
  final List<GitRepo> repos;
  final String providerType;

  const _RepoPickerDialog({
    required this.repos,
    required this.providerType,
  });

  @override
  State<_RepoPickerDialog> createState() => _RepoPickerDialogState();
}

class _RepoPickerDialogState extends State<_RepoPickerDialog> {
  late List<GitRepo> _filtered;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.repos;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filtered = widget.repos;
      } else {
        final q = query.toLowerCase();
        _filtered = widget.repos
            .where((r) =>
                r.fullName.toLowerCase().contains(q) ||
                r.name.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: TColors.background,
      title: Text(
        'select repository',
        style: TextStyle(
          color: TColors.foreground,
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8),
              color: TColors.surface,
              child: TextField(
                controller: _searchCtrl,
                onChanged: _filter,
                cursorColor: TColors.green,
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  hintText: 'search repos...',
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
                ),
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'no repos found',
                        style: TextStyle(
                          color: TColors.mutedText,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _buildRepoRow(_filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepoRow(GitRepo repo) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(repo),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              repo.isPrivate ? Icons.lock : Icons.public,
              size: 13,
              color: TColors.mutedText,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo.fullName,
                    style: TextStyle(
                      color: TColors.foreground,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  if (repo.defaultBranch != null)
                    Text(
                      repo.defaultBranch!,
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: TColors.mutedText,
            ),
          ],
        ),
      ),
    );
  }
}
