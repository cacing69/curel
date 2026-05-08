import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/presentation/screens/env_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final EnvService envService;
  final void Function(String userAgent) onUserAgentChanged;

  const SettingsPage({
    required this.settingsService,
    required this.envService,
    required this.onUserAgentChanged,
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
    if (mounted) {
      _defaultUA = defaultUA;
      _uaController.text = ua == defaultUA ? '' : ua;
      _connectTimeoutController.text =
          connectTimeout == defaultConnectTimeout ? '' : connectTimeout.toString();
      _maxTimeController.text =
          maxTime == defaultMaxTime ? '' : maxTime.toString();
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
                            label: 'User-Agent',
                            description:
                                'Appended to every request as the User-Agent header. '
                                'Leave empty to use default.',
                            hint: _defaultUA,
                            controller: _uaController,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            label: 'Connect Timeout',
                            description:
                                'Max seconds to wait for a connection. '
                                'Leave empty to use default ($defaultConnectTimeout).',
                            hint: '$defaultConnectTimeout',
                            controller: _connectTimeoutController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          _buildSection(
                            label: 'Max Time',
                            description:
                                'Max seconds for the entire request. '
                                'Leave empty for no limit.',
                            hint: '$defaultMaxTime (no limit)',
                            controller: _maxTimeController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EnvPage(envService: widget.envService),
                              ),
                            ),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              color: TColors.surface,
                              child: Row(
                                children: [
                                  Icon(Icons.language, size: 14, color: TColors.cyan),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'environments',
                                    style: TextStyle(
                                      color: TColors.cyan,
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  Icon(Icons.chevron_right, size: 14, color: TColors.mutedText),
                                ],
                              ),
                            ),
                          ),
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
                                label: 'reset',
                                onTap: () {
                                  _uaController.clear();
                                  _connectTimeoutController.clear();
                                  _maxTimeController.clear();
                                },
                              ),
                            ],
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
