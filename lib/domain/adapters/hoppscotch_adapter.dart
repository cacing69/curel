import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';

class HoppscotchAdapter implements CollectionAdapter {
  @override
  String get id => 'hoppscotch_v12';

  @override
  String get name => 'Hoppscotch';

  @override
  String get icon => 'code';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      final v = data['v'];
      return (v is int || v is String) &&
          data.containsKey('name') &&
          data['folders'] is List;
    } catch (_) {
      return false;
    }
  }

  // ── Import ──────────────────────────────────────────────────────

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;

    final rootAuth = data['auth'] as Map<String, dynamic>?;

    final requests = <ImportedRequest>[];
    _traverseFolders(
      data['folders'] as List? ?? [],
      '',
      rootAuth,
      requests,
    );
    _processRequests(
      data['requests'] as List? ?? [],
      '',
      rootAuth,
      requests,
    );

    if (requests.isEmpty) {
      throw FormatException('hoppscotch collection has no requests');
    }

    return ImportedCollection(
      name: data['name'] as String? ?? 'Hoppscotch Collection',
      description: data['description'] as String?,
      environments: _extractEnvs(data),
      requests: requests,
    );
  }

  void _traverseFolders(
    List folders,
    String parentPath,
    Map<String, dynamic>? inheritedAuth,
    List<ImportedRequest> result,
  ) {
    for (final folder in folders) {
      if (folder is! Map<String, dynamic>) continue;
      final name = _sanitize(folder['name'] as String? ?? 'unnamed');
      final path = parentPath.isEmpty ? name : '$parentPath/$name';
      final folderAuth =
          _resolveAuth(folder['auth'] as Map<String, dynamic>?, inheritedAuth);

      _processRequests(
        folder['requests'] as List? ?? [],
        path,
        folderAuth,
        result,
      );
      _traverseFolders(
        folder['folders'] as List? ?? [],
        path,
        folderAuth,
        result,
      );
    }
  }

  void _processRequests(
    List requests,
    String folderPath,
    Map<String, dynamic>? inheritedAuth,
    List<ImportedRequest> result,
  ) {
    for (final r in requests) {
      if (r is! Map<String, dynamic>) continue;
      final name = _sanitize(r['name'] as String? ?? 'unnamed');
      final requestPath = folderPath.isEmpty ? name : '$folderPath/$name';
      final effectiveAuth =
          _resolveAuth(r['auth'] as Map<String, dynamic>?, inheritedAuth);
      result.add(ImportedRequest(
        path: requestPath,
        curlContent: _buildCurl(r, effectiveAuth),
        meta: RequestMeta(displayName: r['name'] as String?),
      ));
    }
  }

  // ── Auth resolution ──────────────────────────────────────────────

  Map<String, dynamic>? _resolveAuth(
    Map<String, dynamic>? auth,
    Map<String, dynamic>? inherited,
  ) {
    if (auth == null) return inherited;
    final type = auth['authType'] as String?;
    if (type == 'inherit') return inherited;
    if (type == 'none') return null;
    return auth;
  }

  List<MapEntry<String, String>> _authToHeaders(Map<String, dynamic> auth) {
    if (auth['authActive'] != true) return [];
    final type = auth['authType'] as String?;
    switch (type) {
      case 'bearer':
        final token = auth['token'] as String? ?? '';
        if (token.isEmpty) return [];
        return [MapEntry('Authorization', 'Bearer $token')];
      case 'api-key':
        final key = auth['key'] as String? ?? '';
        final value = auth['value'] as String? ?? '';
        final addTo = auth['addTo'] as String? ?? 'HEADERS';
        if (addTo != 'HEADERS') return [];
        return [MapEntry(key, value)];
      default:
        return [];
    }
  }

  // ── Curl builder ─────────────────────────────────────────────────

  String _buildCurl(Map<String, dynamic> r, Map<String, dynamic>? auth) {
    final method = (r['method'] as String?)?.toUpperCase() ?? 'GET';
    var url = r['endpoint'] as String? ?? '';
    final parts = <String>['curl'];

    if (method != 'GET') parts.add('-X $method');

    // Headers from request
    final existingHeaders = <String, String>{};
    for (final h in (r['headers'] as List? ?? [])) {
      final map = h as Map<String, dynamic>;
      if (map['active'] == false) continue;
      final key = map['key'] as String? ?? '';
      final value = map['value'] as String? ?? '';
      parts.add("-H '${_esc(key)}: ${_esc(value)}'");
      existingHeaders[key.toLowerCase()] = value;
    }

    // Auth headers
    final authHeaders = _authToHeaders(auth ?? {});
    for (final h in authHeaders) {
      parts.add("-H '${_esc(h.key)}: ${_esc(h.value)}'");
      existingHeaders[h.key.toLowerCase()] = h.value;
    }

    // Body
    final body = r['body'];
    if (body is Map<String, dynamic>) {
      final contentType = body['contentType'] as String?;
      final bodyContent = body['body'];

      if (contentType == 'multipart/form-data' && bodyContent is List) {
        for (final field in bodyContent) {
          final f = field as Map<String, dynamic>;
          if (f['active'] == false) continue;
          final key = f['key'] as String? ?? '';
          final value = f['value'] as String? ?? '';
          if (f['isFile'] == true) {
            parts.add("-F '${_esc(key)}=@${_esc(value)}'");
          } else {
            parts.add("-F '${_esc(key)}=${_esc(value)}'");
          }
        }
      } else if (bodyContent is String && bodyContent.isNotEmpty) {
        parts.add("-d '${_esc(bodyContent)}'");
        if (!existingHeaders.containsKey('content-type') &&
            contentType != null) {
          parts.add("-H 'Content-Type: $contentType'");
        }
      }
    }

    // Query params
    final params = r['params'] as List? ?? [];
    final activeParams =
        params.where((p) => (p as Map<String, dynamic>)['active'] != false);
    if (activeParams.isNotEmpty) {
      final query = activeParams.map((p) {
        final map = p as Map<String, dynamic>;
        final k = Uri.encodeQueryComponent(map['key'] as String? ?? '');
        final v = Uri.encodeQueryComponent(map['value'] as String? ?? '');
        return '$k=$v';
      }).join('&');
      url = url.contains('?') ? '$url&$query' : '$url?$query';
    }

    parts.add("'${_esc(url)}'");
    return parts.join(' \\\n  ');
  }

  // ── Environment extraction ───────────────────────────────────────

  List<ImportedEnv> _extractEnvs(Map<String, dynamic> data) {
    // Hoppscotch uses <<var>> same syntax as Curel — extract from variable fields
    final vars = <EnvVariable>[];

    final rootVars = data['variables'] as List? ?? [];
    for (final v in rootVars) {
      final map = v as Map<String, dynamic>;
      final key = map['key'] as String? ?? '';
      if (key.isNotEmpty) {
        vars.add(EnvVariable(key: key, sensitive: false));
      }
    }

    if (vars.isEmpty) return [];
    return [
      ImportedEnv(
        name: data['name'] as String? ?? 'hoppscotch_env',
        variables: vars,
        isActive: true,
      ),
    ];
  }

  // ── Export ──────────────────────────────────────────────────────

  @override
  Future<String> export(ExportedProject project) async {
    final folders = _buildFolderTree(project.requests);

    final result = <String, dynamic>{
      'v': 12,
      'id': _generateId(),
      'name': project.name,
      'folders': folders,
      'requests': <Map<String, dynamic>>[],
      'auth': {'authType': 'inherit', 'authActive': true},
      'headers': <Map<String, dynamic>>[],
      'variables': <Map<String, dynamic>>[],
    };

    if (project.description != null && project.description!.isNotEmpty) {
      result['description'] = project.description;
    }

    if (project.environments.isNotEmpty) {
      final env = project.environments.first;
      result['variables'] = env.variables.map((v) {
        return {'key': v.key, 'value': ''};
      }).toList();
    }

    return const JsonEncoder.withIndent('  ').convert(result);
  }

  List<Map<String, dynamic>> _buildFolderTree(List<ExportedRequest> requests) {
    final folders = <String, Map<String, dynamic>>{};
    final orphans = <Map<String, dynamic>>[];

    for (final req in requests) {
      final item = _curlToHoppscotchRequest(req);
      if (item == null) continue;

      if (req.folderPath.isEmpty) {
        orphans.add(item);
      } else {
        final parts = req.folderPath.split('/');
        final folderName = parts.first;
        folders.putIfAbsent(folderName, () => {
          'v': 12,
          'id': _generateId(),
          'name': folderName,
          'folders': <Map<String, dynamic>>[],
          'requests': <Map<String, dynamic>>[],
          'auth': {'authType': 'inherit', 'authActive': true},
          'headers': <Map<String, dynamic>>[],
        });
        (folders[folderName]!['requests'] as List).add(item);
      }
    }

    return [...folders.values, ...orphans.map((r) => _wrapFolder([r]))];
  }

  Map<String, dynamic> _wrapFolder(List<Map<String, dynamic>> requests) {
    return {
      'v': 12,
      'id': _generateId(),
      'name': requests.first['name'],
      'folders': <Map<String, dynamic>>[],
      'requests': requests,
      'auth': {'authType': 'inherit', 'authActive': true},
      'headers': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic>? _curlToHoppscotchRequest(ExportedRequest req) {
    final parsed = _safeParse(req.curlContent);
    if (parsed == null) return null;

    final curl = parsed.curl;
    final headers = <Map<String, dynamic>>[];
    curl.headers?.forEach((key, value) {
      headers.add({
        'key': key,
        'value': value,
        'active': true,
      });
    });

    Map<String, dynamic>? body;
    if (curl.data != null) {
      final contentType = headers.firstWhere(
            (h) => (h['key'] as String).toLowerCase() == 'content-type',
            orElse: () => {'value': 'application/json'},
          )['value'] as String;
      body = {
        'contentType': contentType,
        'body': curl.data,
      };
    }

    return {
      'v': '17',
      'name': req.displayName,
      'method': curl.method,
      'endpoint': curl.uri.toString(),
      'params': <Map<String, dynamic>>[],
      'headers': headers,
      'preRequestScript': '',
      'testScript': '',
      'auth': {'authType': 'inherit', 'authActive': true},
      'body': body,
      'requestVariables': <Map<String, dynamic>>[],
    };
  }

  ParsedCurl? _safeParse(String curlContent) {
    try {
      return parseCurl(curlContent);
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  String _esc(String input) => input.replaceAll("'", "'\\''");

  String _sanitize(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = List.generate(12, (_) => _idChars[DateTime.now().microsecond % _idChars.length]).join();
    return '${ts}x$rand';
  }
}

const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
