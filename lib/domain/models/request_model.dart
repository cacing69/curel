import 'dart:convert';

class RequestMeta {
  final String? displayName;
  final String? description;
  final String? folder;
  final DateTime? lastRunAt;
  final int? lastStatusCode;
  final Map<String, dynamic>? tags;
  final String? targetEnv;

  const RequestMeta({
    this.displayName,
    this.description,
    this.folder,
    this.lastRunAt,
    this.lastStatusCode,
    this.tags,
    this.targetEnv,
  });

  RequestMeta copyWith({
    String? displayName,
    String? description,
    String? folder,
    DateTime? lastRunAt,
    int? lastStatusCode,
    Map<String, dynamic>? tags,
    String? targetEnv,
  }) {
    return RequestMeta(
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      folder: folder ?? this.folder,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastStatusCode: lastStatusCode ?? this.lastStatusCode,
      tags: tags ?? this.tags,
      targetEnv: targetEnv ?? this.targetEnv,
    );
  }

  Map<String, dynamic> toJson() => {
        if (displayName != null) 'display_name': displayName,
        if (description != null) 'description': description,
        if (folder != null) 'folder': folder,
        if (lastRunAt != null) 'last_run_at': lastRunAt!.toIso8601String(),
        if (lastStatusCode != null) 'last_status_code': lastStatusCode,
        if (tags != null && tags!.isNotEmpty) 'tags': tags,
        if (targetEnv != null) 'target_env': targetEnv,
      };

  factory RequestMeta.fromJson(Map<String, dynamic> json) => RequestMeta(
        displayName: json['display_name'] as String?,
        description: json['description'] as String?,
        folder: json['folder'] as String?,
        lastRunAt: json['last_run_at'] != null
            ? DateTime.parse(json['last_run_at'] as String)
            : null,
        lastStatusCode: json['last_status_code'] as int?,
        tags: json['tags'] != null
            ? Map<String, dynamic>.from(json['tags'] as Map)
            : null,
        targetEnv: json['target_env'] as String?,
      );

  static String encode(RequestMeta meta) =>
      const JsonEncoder.withIndent('  ').convert(meta.toJson());

  static RequestMeta decode(String json) =>
      RequestMeta.fromJson(jsonDecode(json) as Map<String, dynamic>);

  static const empty = RequestMeta();
}
