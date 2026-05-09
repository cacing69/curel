import 'dart:convert';

class Project {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String mode;
  final String? remoteUrl;

  const Project({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.mode = 'local',
    this.remoteUrl,
  });

  Project copyWith({
    String? name,
    String? description,
    DateTime? updatedAt,
    String? mode,
    String? remoteUrl,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
      remoteUrl: remoteUrl ?? this.remoteUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'mode': mode,
        'remote_url': remoteUrl,
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        mode: json['mode'] as String? ?? 'local',
        remoteUrl: json['remote_url'] as String?,
      );

  static String encodeList(List<Project> projects) =>
      jsonEncode(projects.map((p) => p.toJson()).toList());

  static List<Project> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((p) => Project.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  String get curelJsonName => 'curel.json';
}
