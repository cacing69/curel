import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';

class BrunoAdapter implements CollectionAdapter {
  @override
  String get id => 'bruno';

  @override
  String get name => 'Bruno';

  @override
  String get icon => 'folder';

  @override
  bool canHandle(String content) {
    final trimmed = content.trim();
    if (!trimmed.contains('meta {') && !trimmed.contains('meta{')) return false;
    if (!trimmed.contains('name:')) return false;
    final methods = ['get {', 'post {', 'put {', 'delete {', 'patch {', 'head {', 'options {'];
    return methods.any((m) => trimmed.contains(m));
  }

  @override
  Future<ImportedCollection> convert(String content) async {
    final requests = <ImportedRequest>[];
    final allVars = <EnvVariable>[];

    final blocks = _BruParser.parse(content);
    final meta = blocks['meta'] as Map<String, String>? ?? {};
    final name = meta['name'] ?? 'bruno import';

    final method = _extractMethod(blocks);
    if (method == null) {
      throw FormatException('no HTTP method block found in .bru file');
    }

    final url = _extractUrl(blocks, method);
    final curl = _buildCurl(method, url, blocks);
    final displayName = meta['name'] ?? 'unnamed';
    final path = _sanitize(displayName);

    final vars = _extractVars(blocks);
    allVars.addAll(vars);

    requests.add(ImportedRequest(
      path: path,
      curlContent: curl,
      meta: RequestMeta(displayName: displayName),
    ));

    final envs = <ImportedEnv>[];
    if (allVars.isNotEmpty) {
      envs.add(ImportedEnv(
        name: name,
        variables: allVars,
        isActive: true,
      ));
    }

    return ImportedCollection(
      name: name,
      requests: requests,
      environments: envs,
    );
  }

  @override
  Future<String> export(ExportedProject project) async {
    final buffer = StringBuffer();

    for (final req in project.requests) {
      buffer.writeln(_exportRequest(req));
      buffer.writeln();
    }

    if (project.environments.isNotEmpty) {
      for (final env in project.environments) {
        buffer.writeln(_exportEnv(env));
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  // ── Import helpers ────────────────────────────────────────────────

  String? _extractMethod(Map<String, dynamic> blocks) {
    const methods = ['get', 'post', 'put', 'delete', 'patch', 'head', 'options'];
    for (final m in methods) {
      if (blocks.containsKey(m)) return m;
    }
    return null;
  }

  String _extractUrl(Map<String, dynamic> blocks, String method) {
    final methodBlock = blocks[method];
    if (methodBlock is Map<String, String>) {
      return _convertVars(methodBlock['url'] ?? '');
    }
    if (methodBlock is String) {
      final match = RegExp(r'url:\s*(.+)').firstMatch(methodBlock);
      if (match != null) return _convertVars(match.group(1)!.trim());
    }
    return '';
  }

  String _buildCurl(String method, String url, Map<String, dynamic> blocks) {
    final parts = <String>['curl'];

    if (method != 'get') {
      parts.add('-X ${method.toUpperCase()}');
    }

    final headers = _extractDictBlock(blocks, 'headers');
    for (final entry in headers.entries) {
      parts.add("-H '${_esc(entry.key)}: ${_esc(_convertVars(entry.value))}'");
    }

    final query = _extractDictBlock(blocks, 'params:query');
    if (query.isNotEmpty) {
      final qs = query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(_convertVars(e.value))}').join('&');
      if (url.contains('?')) {
        url = '$url&$qs';
      } else {
        url = '$url?$qs';
      }
    }

    final body = _extractBody(blocks);
    if (body != null) {
      parts.add("-d '${_esc(_convertVars(body))}'");
      if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        parts.add("-H 'Content-Type: application/json'");
      }
    }

    parts.add("'${_esc(url)}'");
    return parts.join(' \\\n  ');
  }

  String? _extractBody(Map<String, dynamic> blocks) {
    final bodyTags = [
      'body',
      'body:json',
      'body:text',
      'body:xml',
      'body:graphql',
    ];
    for (final tag in bodyTags) {
      final body = blocks[tag];
      if (body is String && body.trim().isNotEmpty) return body;
    }

    final formUrlencoded = _extractDictBlock(blocks, 'body:form-urlencoded');
    if (formUrlencoded.isNotEmpty) {
      return formUrlencoded.entries.map((e) => '"${e.key}": "${e.value}"').join(', ');
    }

    return null;
  }

  Map<String, String> _extractDictBlock(Map<String, dynamic> blocks, String tag) {
    final block = blocks[tag];
    if (block is Map<String, String>) {
      return Map.fromEntries(
        block.entries.where((e) => !e.key.startsWith('~')),
      );
    }
    return {};
  }

  List<EnvVariable> _extractVars(Map<String, dynamic> blocks) {
    final vars = <EnvVariable>[];
    for (final key in blocks.keys) {
      if (key.startsWith('vars')) {
        final block = blocks[key];
        if (block is List<String>) {
          for (final v in block) {
            final clean = v.startsWith('~') ? v.substring(1) : v;
            if (clean.trim().isNotEmpty) {
              vars.add(EnvVariable(key: clean.trim(), sensitive: key.contains('secret')));
            }
          }
        }
      }
    }
    return vars;
  }

  // ── Export helpers ────────────────────────────────────────────────

  String _exportRequest(ExportedRequest req) {
    final parsed = _safeParse(req.curlContent);
    final method = parsed?.curl.method.toUpperCase() ?? 'GET';
    final url = parsed?.curl.uri.toString() ?? '';
    final methodLower = method.toLowerCase();

    final sb = StringBuffer();
    sb.writeln('meta {');
    sb.writeln('  name: ${req.displayName}');
    sb.writeln('  type: http');
    sb.writeln('  seq: 1');
    sb.writeln('}');

    sb.writeln();
    sb.writeln('$methodLower {');
    sb.writeln('  url: ${_toBruVar(url)}');
    sb.writeln('}');

    if (parsed != null) {
      final headers = parsed.curl.headers;
      if (headers != null && headers.isNotEmpty) {
        sb.writeln();
        sb.writeln('headers {');
        headers.forEach((key, value) {
          sb.writeln('  $key: ${_toBruVar(value)}');
        });
        sb.writeln('}');
      }

      if (parsed.curl.data != null) {
        sb.writeln();
        sb.writeln('body {');
        sb.writeln('  ${_toBruVar(parsed.curl.data!)}');
        sb.writeln('}');
      }
    }

    return sb.toString();
  }

  String _exportEnv(ExportedEnv env) {
    final sb = StringBuffer();
    sb.writeln('vars {');
    for (final v in env.variables) {
      sb.writeln('  ${v.key}: ${v.sensitive ? "{{${v.key}}}" : v.key}');
    }
    sb.writeln('}');
    return sb.toString();
  }

  // ── Shared helpers ────────────────────────────────────────────────

  ParsedCurl? _safeParse(String curlContent) {
    try {
      return parseCurl(curlContent);
    } catch (_) {
      return null;
    }
  }

  String _convertVars(String input) {
    return input.replaceAllMapped(
      RegExp(r'\{\{([^}]+)\}\}'),
      (m) => '<<${m.group(1)?.trim()}>>',
    );
  }

  String _toBruVar(String input) {
    return input.replaceAllMapped(
      RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>'),
      (m) => '{{${m.group(1)}}}',
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

// ── .bru Parser ──────────────────────────────────────────────────────

class _BruParser {
  static Map<String, dynamic> parse(String content) {
    final blocks = <String, dynamic>{};
    final lines = content.split('\n');

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();

      if (line.isEmpty || line.startsWith('#')) {
        i++;
        continue;
      }

      final blockStart = RegExp(r'^(\w[\w:]*-[\w:]*)\s*\{$').firstMatch(line) ??
          RegExp(r'^(\w[\w:]*)\s*\{$').firstMatch(line);

      final arrayStart = RegExp(r'^(\w[\w:]*-[\w:]*)\s*\[$').firstMatch(line) ??
          RegExp(r'^(\w[\w:]*)\s*\[$').firstMatch(line);

      if (blockStart != null) {
        final tag = blockStart.group(1)!;
        final result = _readDictOrTextBlock(lines, i + 1);
        blocks[tag] = result.data;
        i = result.endLine;
      } else if (arrayStart != null) {
        final tag = arrayStart.group(1)!;
        final result = _readArrayBlock(lines, i + 1);
        blocks[tag] = result.data;
        i = result.endLine;
      } else {
        i++;
      }
    }

    return blocks;
  }

  static ({dynamic data, int endLine}) _readDictOrTextBlock(List<String> lines, int start) {
    final pairs = <String, String>{};
    final textBuf = StringBuffer();
    var isDict = true;
    var depth = 1;
    int i = start;

    while (i < lines.length && depth > 0) {
      final line = lines[i];

      if (line.trim() == '}') {
        depth--;
        if (depth == 0) break;
      }

      if (line.trim().startsWith('}') && depth <= 1) {
        break;
      }

      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (!isDict) textBuf.writeln(line);
        i++;
        continue;
      }

      if (trimmed.startsWith('#')) {
        i++;
        continue;
      }

      // Check if it looks like a key-value pair
      final kvMatch = RegExp(r'^~?\s*([^:]+):\s*(.*)$').firstMatch(trimmed);
      if (isDict && kvMatch != null && !trimmed.startsWith('{') && !trimmed.startsWith('<')) {
        var key = kvMatch.group(1)!.trim();
        final value = kvMatch.group(2)!.trim();
        pairs[key] = value;
      } else {
        isDict = false;
        textBuf.writeln(line);
      }

      i++;
    }

    if (isDict) {
      return (data: pairs, endLine: i + 1);
    }
    return (data: textBuf.toString().trimRight(), endLine: i + 1);
  }

  static ({List<String> data, int endLine}) _readArrayBlock(List<String> lines, int start) {
    final items = <String>[];
    int i = start;

    while (i < lines.length) {
      final line = lines[i].trim();
      if (line == ']' || line == '}') break;
      if (line.isEmpty || line.startsWith('#')) {
        i++;
        continue;
      }

      for (final item in line.split(',')) {
        final clean = item.trim();
        if (clean.isNotEmpty) {
          items.add(clean);
        }
      }
      i++;
    }

    return (data: items, endLine: i + 1);
  }
}
