import 'dart:convert';
import 'dart:io';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/presentation/screens/env_page.dart';
import 'package:curel/presentation/screens/git_providers_page.dart';
import 'package:curel/presentation/screens/crash_log_page.dart';
import 'package:curel/presentation/screens/workspace_explorer_page.dart';
import 'package:curel/presentation/widgets/import_preview_dialog.dart';
import 'package:curel/presentation/theme/app_tokens.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final void Function(String userAgent) onUserAgentChanged;
  final void Function() onWorkspaceChanged;
  final void Function()? onThemeChanged;
  final String? projectId;

  SettingsPage({
    required this.onUserAgentChanged,
    required this.onWorkspaceChanged,
    this.onThemeChanged,
    this.projectId,
    super.key,
  });

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _uaController = TextEditingController();
  final _connectTimeoutController = TextEditingController();
  final _maxTimeController = TextEditingController();
  var _loading = true;
  var _moreThemesExpanded = false;
  var _useCurlEngine = false;
  String _defaultUA = '';
  String _workspaceDisplay = '';
  String _selectedThemeId = 'dracula';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _uaController.dispose();
    _connectTimeoutController.dispose();
    _maxTimeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final ua = await ref.read(settingsProvider).getUserAgent();
    final defaultUA = await ref.read(settingsProvider).getDefaultUserAgent();
    final connectTimeout = await ref.read(settingsProvider).getConnectTimeout();
    final maxTime = await ref.read(settingsProvider).getMaxTime();
    final workspace = await ref
        .read(settingsProvider)
        .getEffectiveWorkspacePath();
    final themeId = await ref.read(settingsProvider).getTheme();
    final useCurl = await ref.read(settingsProvider).getUseCurlEngine();
    if (mounted) {
      _defaultUA = defaultUA;
      _selectedThemeId = themeId;
      _useCurlEngine = useCurl;
      _uaController.text = ua == defaultUA ? '' : ua;
      _connectTimeoutController.text = connectTimeout == defaultConnectTimeout
          ? ''
          : connectTimeout.toString();
      _maxTimeController.text = maxTime == defaultMaxTime
          ? ''
          : maxTime.toString();
      _workspaceDisplay = workspace;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    await ref.read(settingsProvider).setUserAgent(_uaController.text.trim());
    final ct = int.tryParse(_connectTimeoutController.text.trim());
    await ref.read(settingsProvider).setConnectTimeout(ct);
    final mt = int.tryParse(_maxTimeController.text.trim());
    await ref.read(settingsProvider).setMaxTime(mt);
    final ua = await ref.read(settingsProvider).getUserAgent();
    widget.onUserAgentChanged(ua);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickWorkspace() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'select workspace folder',
    );
    if (result == null) return;
    try {
      await ref.read(settingsProvider).setWorkspacePath(result);
      await ref.read(fileSystemProvider).setWorkspaceRoot(result);
      if (mounted) Navigator.of(context).pop();
      widget.onWorkspaceChanged();
    } catch (e) {
      if (mounted) showTerminalToast(context, 'failed to set workspace: $e');
    }
  }

  Future<void> _resetWorkspace() async {
    await ref.read(settingsProvider).clearWorkspacePath();
    final effective = await ref
        .read(settingsProvider)
        .getEffectiveWorkspacePath();
    await ref.read(fileSystemProvider).setWorkspaceRoot(effective);
    if (mounted) Navigator.of(context).pop();
    widget.onWorkspaceChanged();
  }

  Future<void> _exportWorkspace() async {
    try {
      final json = await ref.read(workspaceServiceProvider).exportWorkspace();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'export workspace',
        fileName: 'curel-workspace.json',
        bytes: utf8.encode(json),
      );
      if (path != null && mounted)
        showTerminalToast(context, 'workspace exported');
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  Future<void> _importWorkspace() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final json = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();

      final preview = await ref
          .read(workspaceServiceProvider)
          .previewImport(json);
      if (preview == null) {
        if (mounted)
          showTerminalToast(context, 'error: unsupported file format');
        return;
      }

      if (!mounted) return;
      final importResult = await showDialog<ImportResult>(
        context: context,
        builder: (_) => ImportPreviewDialog(preview: preview),
      );
      if (importResult == null || !mounted) return;

      final counts = await ref
          .read(workspaceServiceProvider)
          .importWorkspace(json);
      widget.onWorkspaceChanged();
      if (mounted) {
        showTerminalToast(
          context,
          'imported ${counts.projects} projects, ${counts.requests} requests, ${counts.envs} envs',
        );
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  Future<void> _resetApp() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'reset app',
          style: TextStyle(
            color: TColors.red,
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
        content: Text(
          'this will delete all projects, environments, and settings. '
          'the app will restart fresh. this cannot be undone.',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'cancel',
              style: TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('reset'),
            child: Text(
              'reset',
              style: TextStyle(color: TColors.red, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != 'reset') return;

    try {
      await ref.read(historyServiceProvider).clear();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}

    try {
      final secure = FlutterSecureStorage();
      await secure.deleteAll();
    } catch (_) {}

    try {
      final fs = LocalFileSystemService();
      final root = await fs.getWorkspaceRoot();
      final dir = Directory(root);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}

    if (mounted) {
      showTerminalToast(context, 'app data cleared — closing...');
    }
    await Future.delayed(Duration(milliseconds: 800));
    exit(0);
  }

  Future<void> _applyTheme(String themeId) async {
    setAppTheme(themeId);
    await ref.read(settingsProvider).setTheme(themeId);
    widget.onThemeChanged?.call();
    if (mounted) setState(() => _selectedThemeId = themeId);
  }

  // ── Build ────────────────────────────────────────────────────────

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
                  ? const Center(child: TerminalLoader())
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── request ─────────────────────────────
                          _sectionLabel('request'),
                          if (Platform.isAndroid) ...[
                            _buildCurlEngineToggle(),
                            _itemDivider(),
                          ],
                          _buildUserAgentBlock(),
                          _itemDivider(),
                          _buildInlineRow(
                            label: 'connect timeout',
                            hint: '${defaultConnectTimeout}s',
                            controller: _connectTimeoutController,
                            keyboardType: TextInputType.number,
                          ),
                          _itemDivider(),
                          _buildInlineRow(
                            label: 'max time',
                            hint: '0 = no limit',
                            controller: _maxTimeController,
                            keyboardType: TextInputType.number,
                          ),

                          // ── appearance ──────────────────────────
                          _sectionLabel('appearance'),
                          _buildThemeBlock(),

                          // ── workspace ───────────────────────────
                          _sectionLabel('workspace'),
                          _buildWorkspaceBlock(),

                          // ── navigate ────────────────────────────
                          _sectionLabel('navigate'),
                          _buildNavRow(
                            Icons.data_object,
                            'env',
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EnvPage(projectId: widget.projectId),
                              ),
                            ),
                          ),
                          _itemDivider(),
                          _buildNavRow(
                            Icons.cloud,
                            'git providers',
                            () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GitProvidersPage(),
                              ),
                            ),
                          ),
                          _itemDivider(),
                          _buildNavRow(
                            Icons.bug_report,
                            'crash log',
                            () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CrashLogPage()),
                            ),
                          ),

                          // ── danger zone ─────────────────────────
                          SizedBox(height: 24),
                          Container(
                            height: 1,
                            color: TColors.red.withValues(alpha: 0.3),
                          ),
                          SizedBox(height: 12),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: TermButton(
                              icon: Icons.delete_forever,
                              label: 'reset app',
                              onTap: _resetApp,
                            ),
                          ),
                          SizedBox(height: 8),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '⚠ danger zone — this action is irreversible. '
                              'all projects, environments, settings, and git provider tokens '
                              'will be permanently deleted.',
                              style: TextStyle(
                                color: TColors.red.withValues(alpha: 0.8),
                                fontFamily: 'monospace',
                                fontSize: 10,
                                height: 1.5,
                              ),
                            ),
                          ),
                          SizedBox(height: 24),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Layout helpers ────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back, size: 18, color: TColors.mutedText),
          ),
          SizedBox(width: 8),
          Text(
            'settings',
            style: TextStyle(
              color: TColors.foreground,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          TermButton(
            icon: Icons.check,
            label: 'save',
            onTap: _save,
            accent: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        '// $label',
        style: TextStyle(
          color: TColors.comment,
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _itemDivider() => Container(height: 1, color: TColors.background);

  // ── Section blocks ────────────────────────────────────────────────

  Widget _buildCurlEngineToggle() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: TColors.surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'curl engine',
                  style: TextStyle(
                    color: TColors.foreground,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  _useCurlEngine
                      ? 'native libcurl (verbose, trace)'
                      : 'dio (async, cross-platform)',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              final next = !_useCurlEngine;
              await ref.read(settingsProvider).setUseCurlEngine(next);
              ref.read(useCurlEngineProvider.notifier).state = next;
              setState(() => _useCurlEngine = next);
            },
            child: Container(
              width: 36,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: _useCurlEngine
                    ? TColors.green
                    : TColors.mutedText.withValues(alpha: 0.3),
              ),
              child: Align(
                alignment: _useCurlEngine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  margin: EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: TColors.background,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserAgentBlock() {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'user-agent',
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              Spacer(),
              Text(
                'empty = default',
                style: TextStyle(
                  color: TColors.mutedText,
                  fontFamily: 'monospace',
                  fontSize: 10,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          TextField(
            controller: _uaController,
            maxLines: 2,
            minLines: 1,
            cursorColor: TColors.green,
            style: TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: _defaultUA,
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
        ],
      ),
    );
  }

  Widget _buildInlineRow({
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.right,
              cursorColor: TColors.green,
              style: TextStyle(
                color: TColors.foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: InputDecoration(
                hintText: hint,
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
        ],
      ),
    );
  }

  Widget _buildThemeBlock() {
    final featured = allThemes.values.take(4).toList();
    final more = allThemes.values.skip(4).toList();
    return Column(
      children: [
        for (final theme in featured) _buildThemeRow(theme),
        if (more.isNotEmpty) _buildMoreThemes(more),
      ],
    );
  }

  Widget _buildThemeRow(AppThemeTokens theme) {
    final isActive = _selectedThemeId == theme.id;
    return GestureDetector(
      onTap: () => _applyTheme(theme.id),
      child: Container(
        padding: EdgeInsets.fromLTRB(12, 6, 12, isActive ? 8 : 6),
        decoration: BoxDecoration(
          color: theme.background,
          border: Border.all(
            color: isActive ? TColors.green : TColors.border,
            width: isActive ? 1.5 : 0.5,
          ),
        ),
        margin: EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mini terminal header bar
            Container(
              height: 14,
              color: theme.surface,
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _dot(theme.red),
                  SizedBox(width: 2),
                  _dot(theme.yellow),
                  SizedBox(width: 2),
                  _dot(theme.green),
                  Spacer(),
                  Text(
                    theme.name.toLowerCase(),
                    style: TextStyle(
                      color: theme.mutedText,
                      fontFamily: 'monospace',
                      fontSize: 7,
                    ),
                  ),
                  if (isActive) ...[
                    SizedBox(width: 4),
                    Text(
                      '●',
                      style: TextStyle(color: theme.green, fontSize: 7),
                    ),
                  ],
                ],
              ),
            ),
            // Simulated request lines
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'GET ',
                        style: TextStyle(
                          color: theme.green,
                          fontFamily: 'monospace',
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '/users',
                        style: TextStyle(
                          color: theme.foreground,
                          fontFamily: 'monospace',
                          fontSize: 8,
                        ),
                      ),
                      Spacer(),
                      Text(
                        '200',
                        style: TextStyle(
                          color: theme.green,
                          fontFamily: 'monospace',
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 1),
                  Row(
                    children: [
                      Text(
                        'POST',
                        style: TextStyle(
                          color: theme.cyan,
                          fontFamily: 'monospace',
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ' /login',
                        style: TextStyle(
                          color: theme.foreground,
                          fontFamily: 'monospace',
                          fontSize: 8,
                        ),
                      ),
                      Spacer(),
                      Text(
                        '201',
                        style: TextStyle(
                          color: theme.green,
                          fontFamily: 'monospace',
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isActive)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'active',
                  style: TextStyle(
                    color: TColors.green,
                    fontFamily: 'monospace',
                    fontSize: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 4,
    height: 4,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _buildMoreThemes(List<AppThemeTokens> themes) {
    return Column(
      children: [
        GestureDetector(
          onTap: () =>
              setState(() => _moreThemesExpanded = !_moreThemesExpanded),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 20),
                Text(
                  'more themes',
                  style: TextStyle(
                    color: TColors.mutedText,
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
                Spacer(),
                Icon(
                  _moreThemesExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: TColors.mutedText,
                ),
              ],
            ),
          ),
        ),
        if (_moreThemesExpanded)
          for (final theme in themes) _buildThemeRow(theme),
      ],
    );
  }

  Widget _buildWorkspaceBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: TColors.surface,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            _workspaceDisplay,
            style: TextStyle(
              color: TColors.mutedText,
              fontFamily: 'monospace',
              fontSize: 10,
              height: 1.4,
            ),
          ),
        ),
        SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TermButton(
                icon: Icons.folder_open,
                label: 'change',
                onTap: _pickWorkspace,
                accent: true,
              ),
              TermButton(
                icon: Icons.refresh,
                label: 'reset',
                onTap: _resetWorkspace,
              ),
              TermButton(
                icon: Icons.upload_file,
                label: 'import',
                onTap: _importWorkspace,
              ),
              TermButton(
                icon: Icons.download,
                label: 'export',
                onTap: _exportWorkspace,
              ),
              TermButton(
                icon: Icons.folder_open,
                label: 'explore',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => WorkspaceExplorerPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavRow(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: TColors.surface,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 13, color: TColors.mutedText),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: TColors.foreground,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 14, color: TColors.mutedText),
          ],
        ),
      ),
    );
  }
}
