import 'dart:convert';

import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

class CurlResponse {
  final int? statusCode;
  final String statusMessage;
  final Map<String, List<String>> headers;
  final dynamic body;
  final String? verboseLog;
  final String? traceLog;

  const CurlResponse({
    this.statusCode,
    this.statusMessage = '',
    this.headers = const {},
    this.body,
    this.verboseLog,
    this.traceLog,
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

  String formatVerboseLog() {
    return verboseLog ?? '';
  }

  TextSpan formatVerboseLogSpan() {
    if (verboseLog == null || verboseLog!.isEmpty) {
      return const TextSpan();
    }
    final children = <TextSpan>[];
    for (final line in verboseLog!.split('\n')) {
      if (line.startsWith('> ')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.cyan, fontFamily: 'monospace', fontSize: 12),
        ));
      } else if (line.startsWith('< ')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.green, fontFamily: 'monospace', fontSize: 12),
        ));
      } else if (line.startsWith('* ')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
        ));
      } else {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.text, fontFamily: 'monospace', fontSize: 12),
        ));
      }
    }
    return TextSpan(children: children);
  }

  String formatTraceLog() {
    return traceLog ?? '';
  }

  List<List<TextSpan>> get traceLogLines {
    if (traceLog == null || traceLog!.isEmpty) return const [];
    final result = <List<TextSpan>>[];
    for (final line in traceLog!.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith('== Info:')) {
        result.add([TextSpan(
          text: line,
          style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
        )]);
      } else if (line.startsWith('=> Send')) {
        result.add([TextSpan(
          text: line,
          style: const TextStyle(color: TColors.cyan, fontFamily: 'monospace', fontSize: 12),
        )]);
      } else if (line.startsWith('<= Recv')) {
        result.add([TextSpan(
          text: line,
          style: const TextStyle(color: TColors.green, fontFamily: 'monospace', fontSize: 12),
        )]);
      } else if (_isHexDumpLine(line)) {
        result.add(_formatHexDumpLineSpans(line));
      } else {
        result.add([TextSpan(
          text: line,
          style: const TextStyle(color: TColors.text, fontFamily: 'monospace', fontSize: 12),
        )]);
      }
    }
    return result;
  }

  TextSpan formatTraceLogSpan() {
    if (traceLog == null || traceLog!.isEmpty) {
      return const TextSpan();
    }
    final children = <TextSpan>[];
    for (final line in traceLog!.split('\n')) {
      if (line.startsWith('== Info:')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
        ));
      } else if (line.startsWith('=> Send')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.cyan, fontFamily: 'monospace', fontSize: 12),
        ));
      } else if (line.startsWith('<= Recv')) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.green, fontFamily: 'monospace', fontSize: 12),
        ));
      } else if (_isHexDumpLine(line)) {
        children.addAll(_formatHexDumpLineSpans(line));
      } else if (line.isNotEmpty) {
        children.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(color: TColors.text, fontFamily: 'monospace', fontSize: 12),
        ));
      }
    }
    return TextSpan(children: children);
  }

  static bool _isHexDumpLine(String line) {
    return line.length > 5 &&
        RegExp(r'^[0-9a-fA-F]{4}:\s').hasMatch(line);
  }

  static List<TextSpan> _formatHexDumpLineSpans(String line) {
    final colonIdx = line.indexOf(': ');
    if (colonIdx < 0) {
      return [TextSpan(text: '$line\n', style: const TextStyle(color: TColors.text, fontFamily: 'monospace', fontSize: 12))];
    }

    final offset = line.substring(0, colonIdx + 2);
    final rest = line.substring(colonIdx + 2);

    // Hex portion is ~49 chars (16 bytes as "HH " with grouping), then ASCII
    final hexEnd = rest.length >= 49 ? 49 : rest.length;
    final hexPart = rest.substring(0, hexEnd);
    final asciiPart = hexEnd < rest.length ? rest.substring(hexEnd) : '';

    return [
      TextSpan(
        text: offset,
        style: const TextStyle(color: TColors.mutedText, fontFamily: 'monospace', fontSize: 12),
      ),
      TextSpan(
        text: hexPart,
        style: const TextStyle(color: TColors.orange, fontFamily: 'monospace', fontSize: 12),
      ),
      TextSpan(
        text: '$asciiPart\n',
        style: const TextStyle(color: TColors.purple, fontFamily: 'monospace', fontSize: 12),
      ),
    ];
  }
}
