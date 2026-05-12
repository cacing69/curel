import 'dart:convert';

class _Unset {
  const _Unset();
}

const _unset = _Unset();

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
    Object? lastSyncSha = _unset,
    Object? remoteUrl = _unset,
    Object? provider = _unset,
    Object? branch = _unset,
    Object? remoteOriginId = _unset,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
      lastSyncSha: lastSyncSha == _unset ? this.lastSyncSha : lastSyncSha as String?,
      remoteUrl: remoteUrl == _unset ? this.remoteUrl : remoteUrl as String?,
      provider: provider == _unset ? this.provider : provider as String?,
      branch: branch == _unset ? this.branch : branch as String?,
      remoteOriginId: remoteOriginId == _unset ? this.remoteOriginId : remoteOriginId as String?,
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
