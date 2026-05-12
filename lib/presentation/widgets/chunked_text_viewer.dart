import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight;

class ChunkedTextViewer extends StatelessWidget {
  final String text;
  final String? language;
  final TextStyle style;
  final bool showLineNumbers;

  ChunkedTextViewer({
    required this.text,
    this.language,
    TextStyle? style,
    this.showLineNumbers = false,
    super.key,
  }) : style = style ?? TextStyle(
         fontFamily: 'monospace',
         fontSize: 12,
         color: TColors.text,
       );

  @override
  Widget build(BuildContext context) {
    final lines = _splitLines();
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLineNumbers) ...[
              SizedBox(
                width: 32,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: TColors.mutedText.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(width: 8),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(style: style, children: lines[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  List<List<TextSpan>> _splitLines() {
    if (language != null) {
      try {
        final result = highlight.parse(text, language: language!);
        final flatSpans = _buildFlatSpans(result.nodes);
        return _splitSpansByNewlines(flatSpans);
      } catch (_) {
        // fall through to plain
      }
    }
    return text.split('\n').map((line) => [TextSpan(text: line)]).toList();
  }

  List<TextSpan> _buildFlatSpans(List<dynamic>? nodes) {
    final spans = <TextSpan>[];
    void traverse(dynamic n) {
      final node = n as dynamic;
      if (node.value != null) {
        final className = node.className as String?;
        spans.add(TextSpan(
          text: node.value as String,
          style: className != null && syntaxTheme[className] != null
              ? syntaxTheme[className]
              : null,
        ));
      } else if (node.children != null) {
        final className = node.className as String?;
        final childNodes = node.children as List;
        if (className != null && syntaxTheme[className] != null) {
          spans.add(TextSpan(
            style: syntaxTheme[className],
            children: _buildFlatSpans(childNodes),
          ));
        } else {
          for (final child in childNodes) {
            traverse(child);
          }
        }
      }
    }

    if (nodes != null) {
      for (final node in nodes) {
        traverse(node);
      }
    }
    return spans;
  }

  List<List<TextSpan>> _splitSpansByNewlines(List<TextSpan> spans) {
    final lines = <List<TextSpan>>[[]];
    for (final span in spans) {
      final text = span.text ?? '';
      if (!text.contains('\n')) {
        lines.last.add(span);
        continue;
      }
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add([]);
        if (parts[i].isNotEmpty) {
          lines.last.add(TextSpan(text: parts[i], style: span.style));
        }
      }
    }
    return lines;
  }
}
