import 'dart:convert';

import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class CurlResponse {
  final int? statusCode;
  final String statusMessage;
  final Map<String, List<String>> headers;
  final dynamic body;

  const CurlResponse({
    this.statusCode,
    this.statusMessage = '',
    this.headers = const {},
    this.body,
  });

  String? get contentType => headers['content-type']?.firstOrNull;

  String get contentTypeLabel {
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.contains('json')) return 'JSON';
    if (ct.contains('xml')) return 'XML';
    if (ct.contains('html')) return 'HTML';
    if (ct.contains('javascript')) return 'JS';
    if (ct.contains('css')) return 'CSS';
    if (ct.contains('yaml')) return 'YAML';
    if (ct.contains('markdown')) return 'MD';
    if (ct.contains('graphql')) return 'GQL';
    return 'Text';
  }

  bool get isHtml => contentType?.toLowerCase().contains('html') ?? false;

  static const _prettifyLimit = 500 * 1024;

  String? get highlightLanguage {
    if (_rawBodyLength > _prettifyLimit) return null;
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.contains('json')) return 'json';
    if (ct.contains('xml')) return 'xml';
    if (ct.contains('html')) return 'xml';
    if (ct.contains('javascript')) return 'javascript';
    if (ct.contains('css')) return 'css';
    if (ct.contains('yaml')) return 'yaml';
    if (ct.contains('markdown')) return 'markdown';
    if (ct.contains('graphql')) return 'graphql';
    if (ct.contains('text/plain')) return 'plaintext';
    return null;
  }

  int get _rawBodyLength => (body?.toString() ?? '').length;

  bool get isLargeResponse => _rawBodyLength > _prettifyLimit;

  String get bodyText {
    final raw = body?.toString() ?? '';
    if (highlightLanguage == 'json' && raw.length <= _prettifyLimit) {
      try {
        final decoded = json.decode(raw);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {}
    }
    return raw;
  }

  String formatHeaders() {
    final buffer = StringBuffer()
      ..writeln('Status: $statusCode $statusMessage')
      ..writeln();

    if (headers.isNotEmpty) {
      headers.forEach((key, values) {
        buffer.writeln('  $key: ${values.join(", ")}');
      });
    }

    return buffer.toString();
  }

  TextSpan formatHeadersSpan() {
    final children = <TextSpan>[];

    children.add(TextSpan(
      text: 'Status: ',
      style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
    ));
    final code = statusCode ?? 0;
    children.add(TextSpan(
      text: '$statusCode $statusMessage',
      style: TextStyle(
        color: code >= 200 && code < 300 ? TColors.green : TColors.red,
        fontFamily: 'monospace',
        fontSize: 12,
      ),
    ));
    children.add(const TextSpan(text: '\n\n'));

    if (headers.isNotEmpty) {
      headers.forEach((key, values) {
        children.add(TextSpan(
          text: '  $key',
          style: const TextStyle(color: TColors.cyan, fontFamily: 'monospace', fontSize: 12),
        ));
        children.add(TextSpan(
          text: ': ${values.join(", ")}\n',
          style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
        ));
      });
    }

    return TextSpan(children: children);
  }
}
