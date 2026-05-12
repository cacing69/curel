import 'dart:convert';

class GitProviderModel {
  final String id;
  final String name;
  final String type; // e.g., 'github', 'gitlab'
  final String? baseUrl;

  const GitProviderModel({
    required this.id,
    required this.name,
    required this.type,
    this.baseUrl,
  });

  GitProviderModel copyWith({
    String? name,
    String? type,
    String? baseUrl,
  }) {
    return GitProviderModel(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'base_url': baseUrl,
      };

  factory GitProviderModel.fromJson(Map<String, dynamic> json) =>
      GitProviderModel(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        baseUrl: json['base_url'] as String?,
      );

  static String encodeList(List<GitProviderModel> providers) =>
      const JsonEncoder.withIndent('  ')
          .convert(providers.map((p) => p.toJson()).toList());

  static List<GitProviderModel> decodeList(String json) {
    final list = jsonDecode(json) as List;
    return list
        .map((p) => GitProviderModel.fromJson(p as Map<String, dynamic>))
        .toList();
  }
}
