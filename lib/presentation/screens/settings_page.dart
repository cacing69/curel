import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final void Function(String userAgent) onUserAgentChanged;

  const SettingsPage({
    required this.settingsService,
    required this.onUserAgentChanged,
    super.key,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _uaController = TextEditingController();
  var _loading = true;
  String _defaultUA = '';

  @override
  void initState() {
    super.initState();
    _loadUserAgent();
  }

  @override
  void dispose() {
    _uaController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAgent() async {
    final ua = await widget.settingsService.getUserAgent();
    final defaultUA = await widget.settingsService.getDefaultUserAgent();
    if (mounted) {
      _defaultUA = defaultUA;
      _uaController.text = ua == defaultUA ? '' : ua;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    await widget.settingsService.setUserAgent(_uaController.text.trim());
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
                        horizontal: 16,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'User-Agent',
                            style: TextStyle(
                              color: TColors.cyan,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Appended to every request as the User-Agent header. '
                            'Leave empty to use default.',
                            style: const TextStyle(
                              color: TColors.mutedText,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            color: TColors.surface,
                            child: TextField(
                              controller: _uaController,
                              maxLines: 3,
                              minLines: 3,
                              cursorColor: TColors.green,
                              style: const TextStyle(
                                color: TColors.foreground,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText: _defaultUA,
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
