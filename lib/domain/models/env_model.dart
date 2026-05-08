import 'dart:convert';

class EnvVariable {
  final String key;
  final bool sensitive;

  const EnvVariable({
    required this.key,
    this.sensitive = false,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'sensitive': sensitive,
      };

  factory EnvVariable.fromJson(Map<String, dynamic> json) => EnvVariable(
        key: json['key'] as String,
        sensitive: json['sensitive'] as bool? ?? false,
      );
}

class Environment {
  final String id;
  final String name;
  final List<EnvVariable> variables;
  final DateTime updatedAt;

  const Environment({
    required this.id,
    required this.name,
    required this.variables,
    required this.updatedAt,
  });

  Environment copyWith({
    String? name,
    List<EnvVariable>? variables,
  }) {
    return Environment(
      id: id,
      name: name ?? this.name,
      variables: variables ?? this.variables,
      updatedAt: DateTime.now(),
    );
  }

  String storageKey(String varKey) => 'env_${id}_$varKey';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'variables': variables.map((v) => v.toJson()).toList(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Environment.fromJson(Map<String, dynamic> json) => Environment(
        id: json['id'] as String,
        name: json['name'] as String,
        variables: (json['variables'] as List)
            .map((v) => EnvVariable.fromJson(v as Map<String, dynamic>))
            .toList(),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  static String encodeList(List<Environment> envs) =>
      jsonEncode(envs.map((e) => e.toJson()).toList());

  static List<Environment> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((e) => Environment.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
