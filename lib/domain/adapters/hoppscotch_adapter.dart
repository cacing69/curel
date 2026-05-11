import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

/// Adapter for Hoppscotch export format (v1 JSON).
/// Detects via "_type": "collection" and a top‑level "name" field.
class HoppscotchAdapter implements CollectionAdapter {
  @override
  String get id => 'hoppscotch_v1';

  @override
  String get name => 'Hoppscotch';

  @override
  // Lucide does not have a dedicated icon; use generic "code".
  String get icon => 'code';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data['_type'] == 'collection' && data.containsKey('name');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    final List<dynamic> items = data['items'] as List<dynamic>? ?? [];
    final List<ImportedRequest> requests = [];

    void _traverse(List<dynamic> list, String parentPath) {
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final type = item['type'];
        final name = (item['name'] as String?)?.replaceAll(' ', '_') ?? 'unnamed';
        final currentPath = parentPath.isEmpty ? name : '$parentPath/$name';
        if (type == 'request') {
          final method = (item['method'] as String?)?.toUpperCase() ?? 'GET';
          final url = item['url'] as String? ?? '';
          final headers = item['headers'] as List<dynamic>?;
          final body = item['body'];
          final curl = _buildCurl(method, url, headers, body);
          requests.add(ImportedRequest(
            path: currentPath,
            curlContent: curl,
            meta: RequestMeta(displayName: item['name'] as String?),
          ));
        } else if (type == 'folder' && item['items'] is List) {
          _traverse(item['items'] as List<dynamic>, currentPath);
        }
      }
    }

    _traverse(items, '');

    // Hoppscotch can contain environment variables under "environment" key.
    final List<ImportedEnv> envs = [];
    if (data['environment'] is Map<String, dynamic>) {
      final envMap = data['environment'] as Map<String, dynamic>;
      final vars = (envMap['variables'] as List<dynamic>? ?? []);
      final variables = vars.map((v) {
        final map = v as Map<String, dynamic>;
        return EnvVariable(
          key: map['key'] as String? ?? '',
          sensitive: false,
        );
      }).toList();
      envs.add(ImportedEnv(name: envMap['name'] as String? ?? 'hoppscotch_env', variables: variables, isActive: true));
    }

    return ImportedCollection(
      name: data['name'] as String? ?? 'Hoppscotch Collection',
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
        final key = map['key'] as String? ?? '';
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
