import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';

class InsomniaAdapter implements CollectionAdapter {
  @override
  String get id => 'insomnia_v4';

  @override
  String get name => 'Insomnia';

  @override
  String get icon => 'code';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data.containsKey('resources') && data['_type'] == 'export';
    } catch (_) {
      return false;
    }
  }

  // ── Import ──────────────────────────────────────────────────────

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    final List<dynamic> resources = data['resources'] as List<dynamic>? ?? [];

    // Build id → resource map
    final byId = <String, Map<String, dynamic>>{};
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      final id = r['_id'] as String?;
      if (id != null) byId[id] = r;
    }

    // Resolve parentId chains for folder paths
    final folderPaths = <String, String>{};
    String resolveFolderPath(String id) {
      if (folderPaths.containsKey(id)) return folderPaths[id]!;
      final res = byId[id];
      if (res == null || res['_type'] != 'request_group') return '';
      final name = _sanitize(res['name'] as String? ?? 'unnamed');
      final parentId = res['parentId'] as String?;
      if (parentId == null || !byId.containsKey(parentId) || byId[parentId]!['_type'] == 'workspace') {
        folderPaths[id] = name;
      } else {
        final parentPath = resolveFolderPath(parentId);
        folderPaths[id] = parentPath.isEmpty ? name : '$parentPath/$name';
      }
      return folderPaths[id]!;
    }
    for (final entry in byId.entries) {
      if (entry.value['_type'] == 'request_group') {
        resolveFolderPath(entry.key);
      }
    }

    // Build requests with resolved paths
    final List<ImportedRequest> requests = [];
    for (final r in resources) {
      if (r is! Map<String, dynamic>) continue;
      if (r['_type'] != 'request') continue;
      final name = r['name'] as String? ?? 'unnamed';
      final method = (r['method'] as String?)?.toUpperCase() ?? 'GET';
      final url = r['url'] as String? ?? '';
      final curl = _buildCurl(method, url, r['headers'] as List<dynamic>?, r['body']);
      final parentId = r['parentId'] as String?;
      final folderPath = parentId != null ? folderPaths[parentId] : null;
      final sanitized = _sanitize(name);
      final path = folderPath != null && folderPath.isNotEmpty
          ? '$folderPath/$sanitized'
          : sanitized;
      requests.add(ImportedRequest(
        path: path,
        curlContent: curl,
        meta: RequestMeta(displayName: name),
      ));
    }

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

  // ── Export ──────────────────────────────────────────────────────

  @override
  Future<String> export(ExportedProject project) async {
    final resources = <Map<String, dynamic>>[];
    var counter = 0;

    String genId(String prefix) => '${prefix}_${counter++}';

    // Workspace resource
    final workspaceId = genId('wrk');
    resources.add({
      '_id': workspaceId,
      '_type': 'workspace',
      'name': project.name,
      'description': project.description ?? '',
    });

    // Environment resources
    for (final env in project.environments) {
      final envId = genId('env');
      resources.add({
        '_id': envId,
        '_type': 'environment',
        'name': env.name,
        'data': env.variables.map((v) {
          return {'key': _toExternalVar(v.key), 'value': ''};
        }).toList(),
        'dataPropertyOrder': List.generate(env.variables.length, (_) => ''),
        'parentId': workspaceId,
      });
    }

    // Folder groups (from folderPath)
    final folderIds = <String, String>{};
    final allFolders = <String>{};
    for (final req in project.requests) {
      if (req.folderPath.isEmpty) continue;
      final parts = req.folderPath.split('/');
      var accumulated = '';
      for (final part in parts) {
        accumulated = accumulated.isEmpty ? part : '$accumulated/$part';
        allFolders.add(accumulated);
      }
    }

    // Create folders sorted by depth (shallow first for parentId)
    final sortedFolders = allFolders.toList()
      ..sort((a, b) => a.split('/').length.compareTo(b.split('/').length));

    for (final folderPath in sortedFolders) {
      final parts = folderPath.split('/');
      final name = parts.last;
      final parentPath = parts.sublist(0, parts.length - 1).join('/');
      final parentId = parentPath.isEmpty ? workspaceId : (folderIds[parentPath] ?? workspaceId);
      final groupId = genId('grp');
      folderIds[folderPath] = groupId;
      resources.add({
        '_id': groupId,
        '_type': 'request_group',
        'name': name,
        'parentId': parentId,
      });
    }

    // Request resources
    for (final req in project.requests) {
      final parsed = _safeParse(req.curlContent);
      if (parsed == null) continue;

      final curl = parsed.curl;
      final parentId = req.folderPath.isEmpty
          ? workspaceId
          : (folderIds[req.folderPath] ?? workspaceId);

      final headers = <Map<String, dynamic>>[];
      curl.headers?.forEach((key, value) {
        headers.add({'name': key, 'value': _toExternalVar(value)});
      });

      resources.add({
        '_id': genId('req'),
        '_type': 'request',
        'name': req.displayName,
        'method': curl.method,
        'url': _toExternalVar(curl.uri.toString()),
        'headers': headers,
        if (curl.data != null) 'body': _toExternalVar(curl.data!),
        'parentId': parentId,
      });
    }

    return const JsonEncoder.withIndent('  ').convert({
      '_type': 'export',
      '__export_format': 4,
      '__export_date': DateTime.now().toUtc().toIso8601String(),
      'resources': resources,
    });
  }

  ParsedCurl? _safeParse(String curlContent) {
    try {
      return parseCurl(curlContent);
    } catch (_) {
      return null;
    }
  }

  String _toExternalVar(String input) {
    return input.replaceAllMapped(
      RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>'),
      (m) => '{{${m.group(1)}}}',
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────

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

  String _sanitize(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
