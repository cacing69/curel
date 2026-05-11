import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

/// Standardized data structure for a collection being imported into Curel.
/// This acts as the "Curel Data Convention" for all adapters.
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
  final String path; // relative path, e.g. "auth/login"
  final String curlContent;
  final RequestMeta? meta;

  ImportedRequest({
    required this.path,
    required this.curlContent,
    this.meta,
  });
}

/// Interface for all collection adapters (Postman, Insomnia, etc.)
abstract class CollectionAdapter {
  String get id;
  String get name;
  String get icon; // Optional: icon name from Lucide/Material

  /// Check if this adapter can handle the given content
  bool canHandle(String content);

  /// Convert external format to Curel's standardized collection format
  Future<ImportedCollection> convert(String content);
}
