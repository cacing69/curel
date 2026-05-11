import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';

class HoppscotchAdapter implements CollectionAdapter {
  @override
  String get id => 'hoppscotch_v1';

  @override
  String get name => 'Hoppscotch';

  @override
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

  // ── Import ──────────────────────────────────────────────────────

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    final List<dynamic> items = data['items'] as List<dynamic>? ?? [];
    final List<ImportedRequest> requests = [];

    void traverse(List<dynamic> list, String parentPath) {
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
          traverse(item['items'] as List<dynamic>, currentPath);
        }
      }
    }

    traverse(items, '');

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

  // ── Export ──────────────────────────────────────────────────────

  @override
  Future<String> export(ExportedProject project) async {
    final items = _buildItemsTree(project.requests);

    final result = <String, dynamic>{
      '_type': 'collection',
      'name': project.name,
      if (project.description != null && project.description!.isNotEmpty)
        'description': project.description,
      'items': items,
    };

    // Environment
    if (project.environments.isNotEmpty) {
      final env = project.environments.first;
      result['environment'] = {
        'name': env.name,
        'variables': env.variables.map((v) {
          return {'key': v.key, 'value': ''};
        }).toList(),
      };
    }

    return const JsonEncoder.withIndent('  ').convert(result);
  }

  List<Map<String, dynamic>> _buildItemsTree(List<ExportedRequest> requests) {
    final folders = <String, Map<String, dynamic>>{};
    final orphans = <Map<String, dynamic>>[];

    for (final req in requests) {
      final item = _curlToHoppscotchItem(req);
      if (item == null) continue;

      if (req.folderPath.isEmpty) {
        orphans.add(item);
      } else {
        final parts = req.folderPath.split('/');
        final folderName = parts.first;
        folders.putIfAbsent(folderName, () => {
          'name': folderName,
          'type': 'folder',
          'items': <Map<String, dynamic>>[],
        });
        (folders[folderName]!['items'] as List).add(item);
      }
    }

    return [...folders.values, ...orphans];
  }

  Map<String, dynamic>? _curlToHoppscotchItem(ExportedRequest req) {
    final parsed = _safeParse(req.curlContent);
    if (parsed == null) return null;

    final curl = parsed.curl;
    final headers = <Map<String, dynamic>>[];
    curl.headers?.forEach((key, value) {
      headers.add({'key': key, 'value': value});
    });

    return {
      'name': req.displayName,
      'type': 'request',
      'method': curl.method,
      'url': curl.uri.toString(),
      'headers': headers,
      if (curl.data != null) 'body': curl.data,
    };
  }

  ParsedCurl? _safeParse(String curlContent) {
    try {
      return parseCurl(curlContent);
    } catch (_) {
      return null;
    }
  }

  // ── Shared helpers ──────────────────────────────────────────────

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
