import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
        return Container(
          color: TColors.background,
          child: Column(
            children: [
              // header bar
              Container(
                color: TColors.surface,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'curl cheat sheet',
                      style: TextStyle(
                        color: TColors.purple,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: TColors.mutedText,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: TColors.border),
              
              // Intro section with link
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                color: TColors.surface.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'for full documentation, visit:',
                      style: TextStyle(
                        color: TColors.mutedText,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => launchUrl(Uri.parse('https://curl.se/')),
                      child: Text(
                        'https://curl.se/',
                        style: TextStyle(
                          color: TColors.cyan,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '# common samples:',
                      style: TextStyle(
                        color: TColors.comment,
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: TColors.border),

              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) =>
                      Container(height: 1, color: TColors.border),
                  itemBuilder: (_, i) => _HelpEntry(
                    entry: _entries[i],
                    onUse: onUse,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CurlEntry {
  final String title;
  final String command;
  const _CurlEntry({required this.title, required this.command});
}

const _entries = [
  _CurlEntry(title: 'GET request', command: 'curl https://httpbin.org/get'),
  _CurlEntry(
    title: 'Custom method',
    command: 'curl -X POST https://httpbin.org/post',
  ),
  _CurlEntry(
    title: 'With headers',
    command:
        "curl -H 'Content-Type: application/json' \\\n     -H 'Authorization: Bearer <token>' \\\n     https://httpbin.org/headers",
  ),
  _CurlEntry(
    title: 'POST JSON body',
    command:
        "curl -X POST \\\n     -H 'Content-Type: application/json' \\\n     -d '{\"name\":\"John\",\"age\":30}' \\\n     https://httpbin.org/post",
  ),
  _CurlEntry(
    title: 'POST form data',
    command:
        "curl -X POST \\\n     -F 'name=John' \\\n     -F 'avatar=@photo.jpg' \\\n     https://httpbin.org/post",
  ),
  _CurlEntry(
    title: 'Basic auth',
    command:
        "curl -u 'user:passwd' \\\n     https://httpbin.org/basic-auth/user/passwd",
  ),
  _CurlEntry(
    title: 'Bearer token',
    command:
        "curl -H 'Authorization: Bearer test-token' \\\n     https://httpbin.org/bearer",
  ),
  _CurlEntry(
    title: 'Query parameters',
    command: "curl 'https://httpbin.org/get?page=1&limit=10'",
  ),
  _CurlEntry(
    title: 'Follow redirects',
    command: 'curl -L https://httpbin.org/redirect/2',
  ),
  _CurlEntry(
    title: 'Trace request (hex dump)',
    command: 'curl --trace trace.log https://httpbin.org/get',
  ),
  _CurlEntry(
    title: 'Trace request (ASCII)',
    command: 'curl --trace-ascii trace.log https://httpbin.org/get',
  ),
  _CurlEntry(
    title: 'Status code',
    command: 'curl https://httpbin.org/status/404',
  ),
];

class _HelpEntry extends StatelessWidget {
  final _CurlEntry entry;
  final void Function(String command) onUse;

  const _HelpEntry({required this.entry, required this.onUse});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: TColors.surface,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.title,
                style: TextStyle(
                  color: TColors.cyan,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => onUse(entry.command),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: TColors.green.withValues(alpha: 0.15),
                  child: Text(
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
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(8),
            color: TColors.background,
            child: SelectableText.rich(_highlightCurl(entry.command)),
          ),
        ],
      ),
    );
  }
}

const _methods = {
  'GET',
  'POST',
  'PUT',
  'DELETE',
  'PATCH',
  'HEAD',
  'OPTIONS',
};

final _tokenRegex = RegExp(
  r'(<<[A-Za-z_][A-Za-z0-9_]*>>)'
  r'''|(curl)\b'''
  r'|(-(-?[A-Za-z][\w-]*))'
  r"""|('[^']*')"""
  r'''|("[^"]*")'''
  r'''|(https?://[^\s'"]+)'''
  r'|(\S+)'
  r'|(\s+)',
);

TextSpan _highlightCurl(String text) {
  final spans = <TextSpan>[];
  for (final m in _tokenRegex.allMatches(text)) {
    if (m.group(1) != null) {
      spans.add(TextSpan(
        text: m.group(1),
        style: TextStyle(color: TColors.purple),
      ));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
        text: m.group(2),
        style: TextStyle(
            color: TColors.cyan, fontWeight: FontWeight.bold),
      ));
    } else if (m.group(3) != null) {
      spans.add(TextSpan(
        text: m.group(3),
        style: TextStyle(color: TColors.orange),
      ));
    } else if (m.group(5) != null) {
      spans.add(TextSpan(
        text: m.group(5),
        style: TextStyle(color: TColors.yellow),
      ));
    } else if (m.group(6) != null) {
      spans.add(TextSpan(
        text: m.group(6),
        style: TextStyle(color: TColors.yellow),
      ));
    } else if (m.group(7) != null) {
      spans.add(TextSpan(
        text: m.group(7),
        style: TextStyle(color: TColors.green),
      ));
    } else if (m.group(8) != null) {
      final word = m.group(8)!;
      if (_methods.contains(word.toUpperCase())) {
        spans.add(TextSpan(
          text: word,
          style: TextStyle(
              color: TColors.purple, fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(text: word));
      }
    } else if (m.group(9) != null) {
      spans.add(TextSpan(text: m.group(9)));
    }
  }
  return TextSpan(
    style: TextStyle(
      color: TColors.text,
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.4,
    ),
    children: spans,
  );
}
