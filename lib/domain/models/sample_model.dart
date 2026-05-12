import 'dart:convert';

class SampleMeta {
  final String name;
  final int statusCode;
  final String statusCodeGroup;
  final Map<String, List<String>> headers;
  final String? contentType;
  final DateTime savedAt;

  SampleMeta({
    required this.name,
    required this.statusCode,
    required this.statusCodeGroup,
    this.headers = const {},
    this.contentType,
    DateTime? savedAt,
  }) : savedAt = savedAt ?? DateTime.now();

  SampleMeta copyWith({
    String? name,
    int? statusCode,
    String? statusCodeGroup,
    Map<String, List<String>>? headers,
    String? contentType,
    DateTime? savedAt,
  }) {
    return SampleMeta(
      name: name ?? this.name,
      statusCode: statusCode ?? this.statusCode,
      statusCodeGroup: statusCodeGroup ?? this.statusCodeGroup,
      headers: headers ?? this.headers,
      contentType: contentType ?? this.contentType,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'status_code': statusCode,
    'status_code_group': statusCodeGroup,
    'headers': headers.map((k, v) => MapEntry(k, v)),
    if (contentType != null) 'content_type': contentType,
    'saved_at': savedAt.toIso8601String(),
  };

  factory SampleMeta.fromJson(Map<String, dynamic> json) => SampleMeta(
    name: json['name'] as String,
    statusCode: json['status_code'] as int,
    statusCodeGroup: json['status_code_group'] as String,
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, List<String>.from(v as List)),
    ) ?? {},
    contentType: json['content_type'] as String?,
    savedAt: json['saved_at'] != null
        ? DateTime.parse(json['saved_at'] as String)
        : null,
  );

  static String encode(SampleMeta meta) =>
      const JsonEncoder.withIndent('  ').convert(meta.toJson());

  static SampleMeta decode(String json) =>
      SampleMeta.fromJson(jsonDecode(json) as Map<String, dynamic>);

  static String groupFor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return '2xx';
    if (statusCode >= 300 && statusCode < 400) return '3xx';
    if (statusCode >= 400 && statusCode < 500) return '4xx';
    if (statusCode >= 500) return '5xx';
    return 'other';
  }
}

class SampleItem {
  final String name;
  final String relativePath;
  final SampleMeta meta;

  const SampleItem({
    required this.name,
    required this.relativePath,
    required this.meta,
  });
}
