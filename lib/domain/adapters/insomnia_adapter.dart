import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

/// Adapter for Insomnia v4 collection format.
/// Detects via presence of "_type": "export" or "resources" keys.
class InsomniaAdapter implements CollectionAdapter {
  @override
  String get id => 'insomnia_v4';

  @override
  String get name => 'Insomnia';

  @override
  // Lucide does not have an Insomnia icon; using generic "code".
  String get icon => 'code';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      // Insomnia export includes a "resources" list and an "__export_source" field.
      return data.containsKey('resources') && data['_type'] == 'export';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    // Basic extraction – map Insomnia items to ImportedRequest.
    final List<dynamic> resources = data['resources'] as List<dynamic>? ?? [];
    final List<ImportedRequest> requests = [];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      final type = r['_type'];
      if (type != 'request') continue;
      final name = r['name'] as String? ?? 'unnamed';
      final method = (r['method'] as String?)?.toUpperCase() ?? 'GET';
      final url = r['url'] as String? ?? '';
      // Build a simple curl command.
      final curl = _buildCurl(method, url, r['headers'] as List<dynamic>?, r['body']);
      // Use the hierarchy in "parentId" to build a path (simplified).
      final path = name.replaceAll(' ', '_');
      requests.add(ImportedRequest(
        path: path,
        curlContent: curl,
        meta: RequestMeta(displayName: name),
      ));
    }
    // Insomnia can export environment variables under "resources" with type "environment".
    final List<ImportedEnv> envs = [];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      if (r['_type'] != 'environment') continue;
      final name = r['name'] as String? ?? 'insomnia_env';
      final List<dynamic> vars = r['data'] as List<dynamic>? ?? [];
      final variables = vars.map((v) {
        final map = v as Map<String, dynamic>;
        return EnvVariable(
          key: map['key'] as String? ?? '',
          sensitive: false,
        );
      }).toList();
      envs.add(ImportedEnv(name: name, variables: variables, isActive: true));
    }

    return ImportedCollection(
      name: data['name'] as String? ?? 'Insomnia Collection',
      description: data['description'] as String?,
      environments: envs,
      requests: requests,
    );
  }

  String _buildCurl(String method, String url, List<dynamic>? headers, dynamic body) {
    final parts = <String>['curl'];
    if (method != 'GET') parts.add('-X $method');
    if (headers != null) {
      for (final h in headers) {
        final map = h as Map<String, dynamic>;
        final key = map['name'] as String? ?? '';
        final value = map['value'] as String? ?? '';
        parts.add("-H '${_esc(key)}: ${_esc(value)}'");
      }
    }
    if (body != null && body is String && body.isNotEmpty) {
      parts.add("-d '${_esc(body)}'");
    }
    parts.add("'${_esc(url)}'");
    return parts.join(' ');
  }

  String _esc(String input) => input.replaceAll("'", "'\\\\''");
}
