class CapturedRequest {
  final String method;
  final String url;
  final String host;
  final String headers;
  final String body;
  final String sourceIp;
  final DateTime timestamp;

  const CapturedRequest({
    required this.method,
    required this.url,
    required this.host,
    required this.headers,
    required this.body,
    required this.sourceIp,
    required this.timestamp,
  });

  factory CapturedRequest.fromMap(Map<String, dynamic> map) {
    return CapturedRequest(
      method: map['method'] as String? ?? 'GET',
      url: map['url'] as String? ?? '',
      host: map['host'] as String? ?? '',
      headers: map['headers'] as String? ?? '',
      body: map['body'] as String? ?? '',
      sourceIp: map['sourceIp'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
        'method': method,
        'url': url,
        'host': host,
        'headers': headers,
        'body': body,
        'sourceIp': sourceIp,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  String get endpoint {
    try {
      final uri = Uri.parse(url);
      return uri.path.isNotEmpty ? uri.path : '/';
    } catch (_) {
      return url;
    }
  }

  String toCurl() {
    final buf = StringBuffer("curl -X $method");
    if (headers.isNotEmpty) {
      for (final line in headers.split('\n')) {
        if (line.trim().isNotEmpty) {
          buf.write(" \\\n  -H '${line.trim()}'");
        }
      }
    }
    if (body.isNotEmpty) {
      buf.write(" \\\n  -d '$body'");
    }
    buf.write(" \\\n  '$url'");
    return buf.toString();
  }
}
