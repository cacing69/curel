import 'dart:io';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/presentation/screens/env_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final EnvService envService;
  final FileSystemService fsService;
  final void Function(String userAgent) onUserAgentChanged;
  final void Function() onWorkspaceChanged;
  final String? projectId;

  const SettingsPage({
    required this.settingsService,
    required this.envService,
    required this.fsService,
    required this.onUserAgentChanged,
    required this.onWorkspaceChanged,
    this.projectId,
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _uaController = TextEditingController();
  final _connectTimeoutController = TextEditingController();
  final _maxTimeController = TextEditingController();
  var _loading = true;
  String _defaultUA = '';
  String _workspaceDisplay = '';

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
    final ua = await widget.settingsService.getUserAgent();
    final defaultUA = await widget.settingsService.getDefaultUserAgent();
    final connectTimeout = await widget.settingsService.getConnectTimeout();
    final maxTime = await widget.settingsService.getMaxTime();
    final workspace = await widget.settingsService.getEffectiveWorkspacePath();
    if (mounted) {
      _defaultUA = defaultUA;
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
    await widget.settingsService.setUserAgent(_uaController.text.trim());
    final ct = int.tryParse(_connectTimeoutController.text.trim());
    await widget.settingsService.setConnectTimeout(ct);
    final mt = int.tryParse(_maxTimeController.text.trim());
    await widget.settingsService.setMaxTime(mt);
    final ua = await widget.settingsService.getUserAgent();
    widget.onUserAgentChanged(ua);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickWorkspace() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'select workspace folder',
    );
    if (result == null) return;

    try {
      await widget.settingsService.setWorkspacePath(result);
      await widget.fsService.setWorkspaceRoot(result);
      widget.onWorkspaceChanged();
      if (mounted) {
        setState(() => _workspaceDisplay = result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'failed to set workspace: $e',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            backgroundColor: TColors.error,
          ),
        );
      }
    }
  }

  Future<void> _resetWorkspace() async {
    await widget.settingsService.clearWorkspacePath();
    final effective = await widget.settingsService.getEffectiveWorkspacePath();
    await widget.fsService.setWorkspaceRoot(effective);
    widget.onWorkspaceChanged();
    if (mounted) {
      setState(() => _workspaceDisplay = effective);
    }
  }

  Future<void> _resetApp() async {
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    const secure = FlutterSecureStorage();
    await secure.deleteAll();

    final fs = LocalFileSystemService();
    final root = await fs.getWorkspaceRoot();
    final dir = Directory(root);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    exit(0);
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
                        color: TColors.green,
                        strokeWidth: 2,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSection(
                            label: 'user-agent',
                            description:
                                'appended to every request as the User-Agent header. '
                                'leave empty to use default.',
                            hint: _defaultUA,
                            controller: _uaController,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            label: 'connect timeout',
                            description:
                                'max seconds to wait for a connection. '
                                'leave empty to use default ($defaultConnectTimeout).',
                            hint: '$defaultConnectTimeout',
                            controller: _connectTimeoutController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            label: 'max time',
                            description:
                                'max seconds for the entire request. '
                                'leave empty for no limit.',
                            hint: '$defaultMaxTime (no limit)',
                            controller: _maxTimeController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EnvPage(
                                  envService: widget.envService,
                                  projectId: widget.projectId,
                                ),
                              ),
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              color: TColors.surface,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.data_object,
                                    size: 14,
                                    color: TColors.cyan,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'env',
                                    style: TextStyle(
                                      color: TColors.cyan,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 14,
                                    color: TColors.mutedText,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildWorkspaceSection(),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              TermButton(
                                icon: Icons.check,
                                label: 'save',
                                onTap: _save,
                                accent: true,
                              ),
                              const SizedBox(width: 8),
                              TermButton(
                                icon: Icons.refresh,
                                label: 'reset fields',
                                onTap: () {
                                  _uaController.clear();
                                  _connectTimeoutController.clear();
                                  _maxTimeController.clear();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          Container(height: 1, color: TColors.border),
                          const SizedBox(height: 20),
                          const Text(
                            'danger zone',
                            style: TextStyle(
                              color: TColors.red,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'erase all data and restore the app to a fresh install state.',
                            style: TextStyle(
                              color: TColors.mutedText,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TermButton(
                            icon: Icons.delete_forever,
                            label: 'reset app',
                            onTap: _resetApp,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String label,
    required String description,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: const TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            cursorColor: TColors.green,
            keyboardType: keyboardType,
            style: const TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: TColors.mutedText,
                fontFamily: 'monospace',
                fontSize: 13,
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
    );
  }

  Widget _buildWorkspaceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'workspace',
          style: TextStyle(
            color: TColors.cyan,
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'where projects and requests are stored. '
          'choose a folder visible in your file manager for easy access.',
          style: TextStyle(
            color: TColors.mutedText,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: TColors.surface,
          child: Text(
            _workspaceDisplay,
            style: const TextStyle(
              color: TColors.foreground,
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TermButton(
              icon: Icons.folder_open,
              label: 'change',
              onTap: _pickWorkspace,
              accent: true,
            ),
            const SizedBox(width: 8),
            TermButton(
              icon: Icons.refresh,
              label: 'default',
              onTap: _resetWorkspace,
            ),
          ],
        ),
      ],
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
            child: const Icon(
              Icons.arrow_back,
              size: 18,
              color: TColors.mutedText,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'settings',
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
}
