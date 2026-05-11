import 'dart:convert';

import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';

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
              schema.contains('schema.postman.com'))) {
        return true;
      }
      // Fallback: has info.name and item array, looks like Postman
      return data['info']?['name'] != null && data['item'] is List;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ImportedCollection> convert(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    final info = data['info'] as Map<String, dynamic>;

    final name = info['name'] as String? ?? 'imported collection';
    final description = _extractDescription(info['description']);

    final variables = _extractVariables(data['variable'] as List?);
    final envs = <ImportedEnv>[];
    if (variables.isNotEmpty) {
      envs.add(ImportedEnv(
        name: 'postman vars',
        variables: variables,
        isActive: true,
      ));
    }

    final requests = <ImportedRequest>[];
    _flattenItems(data['item'] as List, '', requests);

    return ImportedCollection(
      name: name,
      description: description,
      environments: envs,
      requests: requests,
    );
  }

  void _flattenItems(
    List items,
    String parentPath,
    List<ImportedRequest> result,
  ) {
    for (final item in items) {
      final itemMap = item as Map<String, dynamic>;
      final itemName = _sanitize((itemMap['name'] as String?) ?? 'unnamed');

      if (itemMap.containsKey('request')) {
        // Leaf item — a request
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
        // Folder — recurse
        final folderPath =
            parentPath.isEmpty ? itemName : '$parentPath/$itemName';
        _flattenItems(itemMap['item'] as List, folderPath, result);
      }
    }
  }

  String _buildCurl(Map<String, dynamic> item) {
    final req = item['request'];
    if (req == null) return 'curl';

    // request can be string (URL only, GET assumed) or object
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

    // Headers
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

    // Body
    final body = reqMap['body'] as Map<String, dynamic>?;
    if (body != null) {
      final mode = body['mode'] as String?;
      switch (mode) {
        case 'raw':
          final raw = (body['raw'] as String?) ?? '';
          parts.add("-d '${_esc(_convertVars(raw))}'");
          // Add Content-Type if not already set
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
      }
    }

    parts.add("'${_esc(_convertVars(url))}'");
    return parts.join(' \\\n  ');
  }

  String _extractUrl(dynamic urlData) {
    if (urlData is String) return urlData;
    if (urlData is Map<String, dynamic>) {
      // Use raw if available
      final raw = urlData['raw'] as String?;
      if (raw != null && raw.isNotEmpty) return raw;

      // Reconstruct from parts
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
