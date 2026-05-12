import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

// ── Import direction (external → curel) ──────────────────────────

class ImportedCollection {
  final String name;
  final String? description;
  final List<ImportedEnv> environments;
  final List<ImportedRequest> requests;

  ImportedCollection({
    required this.name,
    this.description,
    this.environments = const [],
    this.requests = const [],
  });
}

class ImportedEnv {
  final String name;
  final List<EnvVariable> variables;
  final bool isActive;

  ImportedEnv({
    required this.name,
    required this.variables,
    this.isActive = false,
  });
}

class ImportedRequest {
  final String path;
  final String curlContent;
  final RequestMeta? meta;

  ImportedRequest({
    required this.path,
    required this.curlContent,
    this.meta,
  });
}

// ── Export direction (curel → external) ──────────────────────────

class ExportedProject {
  final String name;
  final String? description;
  final List<ExportedEnv> environments;
  final List<ExportedRequest> requests;

  const ExportedProject({
    required this.name,
    this.description,
    this.environments = const [],
    this.requests = const [],
  });
}

class ExportedEnv {
  final String name;
  final List<EnvVariable> variables;
  final bool isActive;

  const ExportedEnv({
    required this.name,
    required this.variables,
    this.isActive = false,
  });
}

class ExportedRequest {
  final String displayName;
  final String folderPath;
  final String curlContent;

  const ExportedRequest({
    required this.displayName,
    this.folderPath = '',
    required this.curlContent,
  });
}

// ── Adapter interface ────────────────────────────────────────────

abstract class CollectionAdapter {
  String get id;
  String get name;
  String get icon;

  bool canHandle(String content);

  /// External format → curel
  Future<ImportedCollection> convert(String content);

  /// Curel → external format (JSON string)
  Future<String> export(ExportedProject project);
}
