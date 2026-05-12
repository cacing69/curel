import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight;

class ChunkedTextViewer extends StatefulWidget {
  final String text;
  final String? language;
  final TextStyle style;
  final bool showLineNumbers;
  final VoidCallback? onRefresh;

  ChunkedTextViewer({
    required this.text,
    this.language,
    TextStyle? style,
    this.showLineNumbers = false,
    this.onRefresh,
    super.key,
  }) : style = style ?? TextStyle(
         fontFamily: 'monospace',
         fontSize: 12,
         color: TColors.text,
       );

  @override
  State<ChunkedTextViewer> createState() => _ChunkedTextViewerState();
}

class _ChunkedTextViewerState extends State<ChunkedTextViewer> {
  List<List<TextSpan>> _lines = [];

  @override
  void initState() {
    super.initState();
    _lines = _parseLines();
  }

  @override
  void didUpdateWidget(covariant ChunkedTextViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text || widget.language != oldWidget.language) {
      _lines = _parseLines();
    }
  }

  List<List<TextSpan>> _parseLines() {
    if (widget.language != null) {
      try {
        final result = highlight.parse(widget.text, language: widget.language!);
        final flatSpans = _buildFlatSpans(result.nodes);
        return _splitSpansByNewlines(flatSpans);
      } catch (_) {
        // fall through to plain
      }
    }
    return widget.text.split('\n').map((line) => [TextSpan(text: line)]).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: widget.onRefresh != null
          ? AlwaysScrollableScrollPhysics()
          : null,
      padding: EdgeInsets.all(8),
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showLineNumbers) ...[
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
                TextSpan(style: widget.style, children: _lines[index]),
              ),
            ),
          ],
        );
      },
    );

    if (widget.onRefresh == null) return list;

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh!(),
      backgroundColor: TColors.surface,
      color: TColors.green,
      child: list,
    );
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
