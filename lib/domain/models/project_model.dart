import 'dart:convert';

class Project {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String mode;
  final String? lastSyncSha;
  final String? remoteUrl;
  final String? provider;
  final String? branch;
  final String? remoteOriginId;

  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.mode = 'local',
    this.lastSyncSha,
    this.remoteUrl,
    this.provider,
    this.branch,
    this.remoteOriginId,
  });

  Project copyWith({
    String? name,
    String? description,
    DateTime? updatedAt,
    String? mode,
    String? lastSyncSha,
    String? remoteUrl,
    String? provider,
    String? branch,
    String? remoteOriginId,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
      lastSyncSha: lastSyncSha ?? this.lastSyncSha,
      remoteUrl: remoteUrl ?? this.remoteUrl,
      provider: provider ?? this.provider,
      branch: branch ?? this.branch,
      remoteOriginId: remoteOriginId ?? this.remoteOriginId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'mode': mode,
        'last_sync_sha': lastSyncSha,
        'remote_url': remoteUrl,
        'provider': provider,
        'branch': branch,
        'remote_origin_id': remoteOriginId,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        mode: json['mode'] as String? ?? 'local',
        lastSyncSha: json['last_sync_sha'] as String?,
        remoteUrl: json['remote_url'] as String?,
        provider: json['provider'] as String?,
        branch: json['branch'] as String?,
        remoteOriginId: json['remote_origin_id'] as String?,
      );

  static String encodeList(List<Project> projects) =>
      const JsonEncoder.withIndent('  ').convert(projects.map((p) => p.toJson()).toList());

  static List<Project> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((p) => Project.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  String get curelJsonName => 'curel.json';
}
