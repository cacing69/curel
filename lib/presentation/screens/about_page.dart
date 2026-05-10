import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/screens/feedback_page.dart';
import 'package:curel/presentation/widgets/term_button.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
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
