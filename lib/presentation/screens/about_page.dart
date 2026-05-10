import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/screens/feedback_page.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  String _version = '';
  String _fingerprint = '';

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    final deviceId = await ref.read(deviceServiceProvider).getFingerprint();
    if (mounted) {
      setState(() {
        _version = info.version;
        _fingerprint = deviceId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Container(height: 1, color: TColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Image.asset('logo.png', width: 80, height: 80),
                    const SizedBox(height: 20),
                    const Text(
                      'Curel',
                      style: TextStyle(
                        color: TColors.green,
                        fontSize: 28,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_version.isNotEmpty)
                      Text(
                        'v$_version',
                        style: const TextStyle(
                          color: TColors.mutedText,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    const SizedBox(height: 20),
                    const Text(
                      'a git-native, local-first curl workspace.\n'
                      'organize requests into projects, manage '
                      'environments with layered variables, and '
                      'collaborate via github.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TColors.foreground,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TermButton(
                      icon: Icons.code,
                      label: 'repository',
                      onTap: () => launchUrl(
                        Uri.parse('https://github.com/cacing69/curel'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TermButton(
                      icon: Icons.chat_bubble_outline,
                      label: 'feedback',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FeedbackPage()),
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (_fingerprint.isNotEmpty) _buildFingerprintSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFingerprintSection() {
    return Column(
      children: [
        const Text(
          'device fingerprint',
          style: TextStyle(
            color: TColors.mutedText,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _fingerprint));
            showTerminalToast(context, 'fingerprint copied');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: TColors.surface,
              border: Border.all(color: TColors.border, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fingerprint,
                  style: const TextStyle(
                    color: TColors.cyan,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.copy, size: 12, color: TColors.mutedText),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
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
            'about',
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
