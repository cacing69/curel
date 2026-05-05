import 'dart:convert';

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
    return 'Text';
  }

  bool get isHtml => contentType?.toLowerCase().contains('html') ?? false;

  String? get highlightLanguage {
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.contains('json')) return 'json';
    if (ct.contains('xml')) return 'xml';
    if (ct.contains('html')) return 'xml';
    return null;
  }

  String get bodyText {
    final raw = body?.toString() ?? '';
    if (highlightLanguage == 'json') {
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
        buffer.writeln('$key: ${values.join(", ")}');
      });
    }

    return buffer.toString();
  }
}
