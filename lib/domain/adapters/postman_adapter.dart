import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curl_parser/curl_parser.dart';

class PostmanAdapter implements CollectionAdapter {
  @override
  String get id => 'postman_v2';

  @override
  String get name => 'Postman';

  @override
  String get icon => 'cloud_upload';

  @override
  bool canHandle(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      final schema = data['info']?['schema'];
      if (schema is String &&
          (schema.contains('schema.getpostman.com') ||
              schema.contains('schema.postman.com') ||
              schema.contains('collection/v2'))) {
        return true;
      }
      return data['info']?['name'] != null && data['item'] is List;
    } catch (_) {
      return false;
    }
  }

  // ── Import ──────────────────────────────────────────────────────

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;

    final info = data['info'];
    if (info is! Map<String, dynamic>) {
      throw FormatException('invalid postman collection: missing info block');
    }

    final name = info['name'] as String? ?? 'imported collection';
    final description = _extractDescription(info['description']);

    final variables = _extractVariables(data['variable'] as List?);
    final envs = <ImportedEnv>[];
    if (variables.isNotEmpty) {
      envs.add(ImportedEnv(
        name: name,
        variables: variables,
        isActive: true,
      ));
    }

    final items = data['item'];
    if (items is! List || items.isEmpty) {
      throw FormatException(
          'invalid postman collection: no requests found');
    }

    final requests = <ImportedRequest>[];
    _flattenItems(items, '', requests);

    if (requests.isEmpty) {
      throw FormatException(
          'postman collection has no enabled requests');
    }

    return ImportedCollection(
      name: name,
      description: description,
      environments: envs,
      requests: requests,
    );
  }

  // ── Export ──────────────────────────────────────────────────────

  @override
  Future<String> export(ExportedProject project) async {
    final items = _buildFolderTree(project.requests);

    final variables = <Map<String, dynamic>>[];
    for (final env in project.environments) {
      for (final v in env.variables) {
        variables.add({
          'key': _toPostmanVar(v.key),
          'value': '',
          'type': 'string',
        });
      }
    }

    final collection = <String, dynamic>{
      'info': {
        'name': project.name,
        if (project.description != null && project.description!.isNotEmpty)
          'description': project.description,
        'schema':
            'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
      },
      'item': items,
      if (variables.isNotEmpty) 'variable': variables,
    };

    return const JsonEncoder.withIndent('  ').convert(collection);
  }

  List<Map<String, dynamic>> _buildFolderTree(List<ExportedRequest> requests) {
    final root = <String, Map<String, dynamic>>{};
    final orphans = <Map<String, dynamic>>[];

    for (final req in requests) {
      final item = _curlToPostmanItem(req);
      if (item == null) continue;

      if (req.folderPath.isEmpty) {
        orphans.add(item);
      } else {
        final parts = req.folderPath.split('/');
        final folderName = parts.first;
        root.putIfAbsent(folderName, () => {
          'name': folderName,
          'item': <Map<String, dynamic>>[],
        });
        (root[folderName]!['item'] as List).add(item);
      }
    }

    return [...root.values, ...orphans];
  }

  Map<String, dynamic>? _curlToPostmanItem(ExportedRequest req) {
    final parsed = _safeParse(req.curlContent);
    if (parsed == null) return null;

    final curl = parsed.curl;
    final url = curl.uri.toString();
    final method = curl.method;

    final headers = <Map<String, dynamic>>[];
    curl.headers?.forEach((key, value) {
      headers.add({'key': key, 'value': _toPostmanVar(value), 'type': 'text'});
    });

    final body = _buildPostmanBody(curl);

    final request = <String, dynamic>{
      'method': method,
      'header': headers,
      'url': _buildPostmanUrl(url),
      if (body != null) 'body': body,
    };

    return {
      'name': req.displayName,
      'request': request,
    };
  }

  Map<String, dynamic>? _buildPostmanBody(Curl curl) {
    if (curl.data != null) {
      final data = _toPostmanVar(curl.data!);
      String? language;
      try {
        jsonDecode(data);
        language = 'json';
      } catch (_) {
        language = 'text';
      }
      return {
        'mode': 'raw',
        'raw': data,
        'options': {'raw': {'language': language}},
      };
    }

    if (curl.formData != null && curl.formData!.isNotEmpty) {
      return {
        'mode': 'formdata',
        'formdata': curl.formData!.map((f) {
          return {
            'key': f.name,
            'value': _toPostmanVar(f.value),
            'type': f.value.startsWith('@') ? 'file' : 'text',
          };
        }).toList(),
      };
    }

    return null;
  }

  Map<String, dynamic> _buildPostmanUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return {'raw': rawUrl};

    return {
      'raw': rawUrl,
      'protocol': uri.scheme,
      'host': uri.host.split('.'),
      if (uri.port > 0) 'port': uri.port.toString(),
      if (uri.pathSegments.isNotEmpty) 'path': uri.pathSegments,
      if (uri.queryParameters.isNotEmpty)
        'query': uri.queryParameters.entries
            .map((e) => {'key': e.key, 'value': e.value})
            .toList(),
    };
  }

  ParsedCurl? _safeParse(String curlContent) {
    try {
      return parseCurl(curlContent);
    } catch (_) {
      return null;
    }
  }

  String _toPostmanVar(String input) {
    return input.replaceAllMapped(
      RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>'),
      (m) => '{{${m.group(1)}}}',
    );
  }

  // ── Shared helpers ──────────────────────────────────────────────

  void _flattenItems(
    List items,
    String parentPath,
    List<ImportedRequest> result,
  ) {
    for (final item in items) {
      final itemMap = item as Map<String, dynamic>;
      if (itemMap['disabled'] == true) continue;

      final itemName = _sanitize((itemMap['name'] as String?) ?? 'unnamed');

      if (itemMap.containsKey('request')) {
        final path = parentPath.isEmpty ? itemName : '$parentPath/$itemName';
        final curl = _buildCurl(itemMap);
        result.add(ImportedRequest(
          path: path,
          curlContent: curl,
          meta: RequestMeta(
            displayName: itemMap['name'] as String?,
          ),
        ));
      } else if (itemMap['item'] is List) {
        final folderPath =
            parentPath.isEmpty ? itemName : '$parentPath/$itemName';
        _flattenItems(itemMap['item'] as List, folderPath, result);
      }
    }
  }

  String _buildCurl(Map<String, dynamic> item) {
    final req = item['request'];
    if (req == null) return 'curl';

    if (req is String) {
      return 'curl $_convertVars(req)';
    }

    final reqMap = req as Map<String, dynamic>;
    final method =
        (reqMap['method'] as String?)?.toUpperCase() ?? 'GET';
    final url = _extractUrl(reqMap['url']);
    final parts = <String>['curl'];

    if (method != 'GET') {
      parts.add('-X $method');
    }

    final headers = reqMap['header'] as List?;
    if (headers != null) {
      for (final h in headers) {
        final hMap = h as Map<String, dynamic>;
        if (hMap['disabled'] == true) continue;
        final key = hMap['key'] as String? ?? '';
        final value = hMap['value'] as String? ?? '';
        parts.add("-H '${_esc(key)}: ${_esc(value)}'");
      }
    }

    final body = reqMap['body'] as Map<String, dynamic>?;
    if (body != null) {
      final mode = body['mode'] as String?;
      switch (mode) {
        case 'raw':
          final raw = (body['raw'] as String?) ?? '';
          parts.add("-d '${_esc(_convertVars(raw))}'");
          final hasContentType = headers?.any((h) {
                final hMap = h as Map<String, dynamic>;
                if (hMap['disabled'] == true) return false;
                return (hMap['key'] as String?)?.toLowerCase() ==
                    'content-type';
              }) ??
              false;
          if (!hasContentType) {
            final lang = body['options']?['raw']?['language'] as String?;
            final contentType = switch (lang) {
              'json' => 'application/json',
              'xml' => 'application/xml',
              'html' => 'text/html',
              'text' => 'text/plain',
              _ => null,
            };
            if (contentType != null) {
              parts.add("-H 'Content-Type: $contentType'");
            }
          }
        case 'urlencoded':
          final encoded = (body['urlencoded'] as List?)
                  ?.where((e) =>
                      (e as Map<String, dynamic>)['disabled'] != true)
                  .map((e) {
                    final eMap = e as Map<String, dynamic>;
                    final k = Uri.encodeQueryComponent(
                        eMap['key'] as String? ?? '');
                    final v = Uri.encodeQueryComponent(
                        eMap['value'] as String? ?? '');
                    return '$k=$v';
                  })
                  .join('&') ??
              '';
          if (encoded.isNotEmpty) {
            parts.add("-d '${_esc(_convertVars(encoded))}'");
            final hasContentType = headers?.any((h) {
                  final hMap = h as Map<String, dynamic>;
                  if (hMap['disabled'] == true) return false;
                  return (hMap['key'] as String?)?.toLowerCase() ==
                      'content-type';
                }) ??
                false;
            if (!hasContentType) {
              parts.add(
                  "-H 'Content-Type: application/x-www-form-urlencoded'");
            }
          }
        case 'formdata':
          final entries = (body['formdata'] as List?)
                  ?.where((e) =>
                      (e as Map<String, dynamic>)['disabled'] != true)
                  .map((e) {
                    final eMap = e as Map<String, dynamic>;
                    final k = _esc(eMap['key'] as String? ?? '');
                    final v = _esc(_convertVars(eMap['value'] as String? ?? ''));
                    return "-F '$k=$v'";
                  })
                  .join(' ') ??
              '';
          if (entries.isNotEmpty) {
            parts.add(entries);
          }
        case 'graphql':
          final gql = body['graphql'] as Map<String, dynamic>?;
          if (gql != null) {
            final payload = <String, dynamic>{};
            final query = gql['query'] as String?;
            if (query != null) payload['query'] = query;
            final vars = gql['variables'] as Map<String, dynamic>?;
            if (vars != null) payload['variables'] = vars;
            if (payload.isNotEmpty) {
              final raw = const JsonEncoder().convert(payload);
              parts.add("-d '${_esc(_convertVars(raw))}'");
              parts.add("-H 'Content-Type: application/json'");
            }
          }
      }
    }

    parts.add("'${_esc(_convertVars(url))}'");
    return parts.join(' \\\n  ');
  }

  String _extractUrl(dynamic urlData) {
    if (urlData is String) return urlData;
    if (urlData is Map<String, dynamic>) {
      final raw = urlData['raw'] as String?;
      if (raw != null && raw.isNotEmpty) return raw;

      final protocol = urlData['protocol'] as String? ?? 'https';
      final host = _joinHost(urlData['host']);
      final port = urlData['port'] as String?;
      final path = _joinPath(urlData['path']);
      final query = _buildQuery(urlData['query'] as List?);

      var result = '$protocol://$host';
      if (port != null && port.isNotEmpty) result = '$result:$port';
      if (path.isNotEmpty) result = '$result/$path';
      if (query.isNotEmpty) result = '$result?$query';
      return result;
    }
    return '';
  }

  String _joinHost(dynamic host) {
    if (host is String) return host;
    if (host is List) return host.join('.');
    return '';
  }

  String _joinPath(dynamic path) {
    if (path is String) return path;
    if (path is List) {
      return path
          .map((p) {
            if (p is String) return p;
            if (p is Map) return p['value'] as String? ?? '';
            return '';
          })
          .where((p) => p.isNotEmpty)
          .join('/');
    }
    return '';
  }

  String _buildQuery(List? params) {
    if (params == null) return '';
    return params
        .where((p) =>
            (p as Map<String, dynamic>)['disabled'] != true)
        .map((p) {
          final pMap = p as Map<String, dynamic>;
          final k = Uri.encodeQueryComponent(pMap['key'] as String? ?? '');
          final v = Uri.encodeQueryComponent(pMap['value'] as String? ?? '');
          return '$k=$v';
        })
        .join('&');
  }

  String _extractDescription(dynamic desc) {
    if (desc is String) return desc;
    if (desc is Map<String, dynamic>) return desc['content'] as String? ?? '';
    return '';
  }

  List<EnvVariable> _extractVariables(List? vars) {
    if (vars == null) return [];
    return vars
        .where((v) => (v as Map<String, dynamic>)['disabled'] != true)
        .map((v) {
          final vMap = v as Map<String, dynamic>;
          return EnvVariable(
            key: _convertVars(vMap['key'] as String? ?? ''),
            sensitive: false,
          );
        })
        .toList();
  }

  String _convertVars(String input) {
    return input.replaceAllMapped(
      RegExp(r'\{\{([^}]+)\}\}'),
      (m) => '<<${m.group(1)?.trim()}>>',
    );
  }

  String _esc(String input) {
    return input.replaceAll("'", "'\\''");
  }

  String _sanitize(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
