import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class HelpSheet extends StatelessWidget {
  final void Function(String command) onUse;

  const HelpSheet({required this.onUse, super.key});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: TColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'curl cheat sheet',
                    style: TextStyle(
                      color: TColors.purple,
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: TColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _HelpSection(
                    title: 'GET request',
                    command: 'curl https://httpbin.org/get',
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Custom method',
                    command: 'curl -X POST https://httpbin.org/post',
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'With headers',
                    command:
                        "curl -H 'Content-Type: application/json' \\\n     -H 'Authorization: Bearer <token>' \\\n     https://httpbin.org/headers",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'POST JSON body',
                    command:
                        "curl -X POST \\\n     -H 'Content-Type: application/json' \\\n     -d '{\"name\":\"John\",\"age\":30}' \\\n     https://httpbin.org/post",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'POST form data',
                    command:
                        "curl -X POST \\\n     -F 'name=John' \\\n     -F 'avatar=@photo.jpg' \\\n     https://httpbin.org/post",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Basic auth',
                    command:
                        "curl -u 'user:passwd' \\\n     https://httpbin.org/basic-auth/user/passwd",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Bearer token',
                    command:
                        "curl -H 'Authorization: Bearer test-token' \\\n     https://httpbin.org/bearer",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Query parameters',
                    command:
                        "curl 'https://httpbin.org/get?page=1&limit=10'",
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Follow redirects',
                    command: 'curl -L https://httpbin.org/redirect/2',
                    onUse: onUse,
                  ),
                  _HelpSection(
                    title: 'Status code',
                    command: 'curl https://httpbin.org/status/404',
                    onUse: onUse,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final String command;
  final void Function(String command) onUse;

  const _HelpSection({
    required this.title,
    required this.command,
    required this.onUse,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => onUse(command),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  color: TColors.green.withValues(alpha: 0.15),
                  child: const Text(
                    'try',
                    style: TextStyle(
                      color: TColors.green,
                      fontFamily: 'monospace',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TColors.background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(
                color: TColors.text,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
