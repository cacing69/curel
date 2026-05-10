import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class CurlHighlightController extends TextEditingController {
  static const methods = {
    'GET',
    'POST',
    'PUT',
    'DELETE',
    'PATCH',
    'HEAD',
    'OPTIONS',
  };

  static final tokenRegex = RegExp(
    r'(<<[A-Za-z_][A-Za-z0-9_]*>>)'
    r'''|(curl)\b'''
    r'|(-(-?[A-Za-z][\w-]*))'
    r"""|('[^']*')"""
    r'''|("[^"]*")'''
    r'''|(https?://[^\s'"]+)'''
    r'|(\S+)'
    r'|(\s+)',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.isEmpty) {
      return TextSpan(style: style, text: '');
    }

    final spans = <TextSpan>[];

    for (final m in tokenRegex.allMatches(text)) {
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(color: TColors.purple),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(
              color: TColors.cyan,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (m.group(3) != null) {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: const TextStyle(color: TColors.orange),
          ),
        );
      } else if (m.group(5) != null) {
        spans.add(
          TextSpan(
            text: m.group(5),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(6) != null) {
        spans.add(
          TextSpan(
            text: m.group(6),
            style: const TextStyle(color: TColors.yellow),
          ),
        );
      } else if (m.group(7) != null) {
        spans.add(
          TextSpan(
            text: m.group(7),
            style: const TextStyle(color: TColors.green),
          ),
        );
      } else if (m.group(8) != null) {
        final word = m.group(8)!;
        if (methods.contains(word.toUpperCase())) {
          spans.add(
            TextSpan(
              text: word,
              style: const TextStyle(
                color: TColors.purple,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        } else {
          spans.add(TextSpan(text: word));
        }
      } else if (m.group(9) != null) {
        spans.add(TextSpan(text: m.group(9)));
      }
    }

    return TextSpan(style: style, children: spans);
  }
}
