import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/curl_highlight_controller.dart';
import 'package:flutter/material.dart';

class ResolvedPreviewDialog extends StatelessWidget {
  final Future<String> future;

  ResolvedPreviewDialog({required this.future, super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: TColors.background,
      insetPadding: EdgeInsets.zero,
      alignment: Alignment.centerLeft,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              color: TColors.surface,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'resolved command',
                    style: TextStyle(
                      color: TColors.purple,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
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
            Expanded(
              child: FutureBuilder<String>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: TerminalLoader());
                  }
                  final text = snapshot.data ?? '';
                  final lines = _splitToHighlightLines(text);
                  return ListView.builder(
                    padding: EdgeInsets.all(12),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      return Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.5,
                          ),
                          children: lines[index],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<List<TextSpan>> _splitToHighlightLines(String text) {
    final allSpans = <TextSpan>[];
    for (final m in CurlHighlightController.tokenRegex.allMatches(text)) {
      if (m.group(1) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(color: TColors.purple),
          ),
        );
      } else if (m.group(2) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(2),
            style: TextStyle(
              color: TColors.cyan,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (m.group(3) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(color: TColors.orange),
          ),
        );
      } else if (m.group(5) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(5),
            style: TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(6) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(6),
            style: TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(7) != null) {
        allSpans.add(
          TextSpan(
            text: m.group(7),
            style: TextStyle(color: TColors.green),
          ),
        );
      } else if (m.group(8) != null) {
        final word = m.group(8)!;
        if (CurlHighlightController.methods.contains(word.toUpperCase())) {
          allSpans.add(
            TextSpan(
              text: word,
              style: TextStyle(
                color: TColors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else {
          allSpans.add(TextSpan(text: word));
        }
      } else if (m.group(9) != null) {
        allSpans.add(TextSpan(text: m.group(9)));
      }
    }

    final lines = <List<TextSpan>>[[]];
    for (final span in allSpans) {
      final spanText = span.text ?? '';
      if (!spanText.contains('\n')) {
        lines.last.add(span);
        continue;
      }
      final parts = spanText.split('\n');
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
