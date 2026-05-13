import 'package:curel/domain/adapters/collection_adapter.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curl_parser/curl_parser.dart';

class VscodeRestAdapter implements CollectionAdapter {
  @override
  String get id => 'vscode_rest';

  @override
  String get name => 'VS Code REST Client';

  @override
  String get icon => 'code';

  @override
  bool canHandle(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;

    final methods = [
      'GET ', 'POST ', 'PUT ', 'DELETE ', 'PATCH ', 'HEAD ', 'OPTIONS ',
    ];
    final hasMethod = methods.any((m) => trimmed.toUpperCase().startsWith(m));
    if (!hasMethod) return false;

    // Distinguish from raw curl — REST Client files don't start with 'curl'
    if (trimmed.startsWith('curl ')) return false;

    // Must contain a URL-like string
    return trimmed.contains('http://') || trimmed.contains('https://');
  }

  @override
  Future<ImportedCollection> convert(String content) async {
    final requests = <ImportedRequest>[];
    final allVars = <EnvVariable>[];

    // Extract @variable declarations
    final varPattern = RegExp(r'^@(\w+)\s*=\s*(.+)$', multiLine: true);
    for (final match in varPattern.allMatches(content)) {
      allVars.add(EnvVariable(
        key: match.group(1)!.trim(),
        sensitive: false,
      ));
    }

    // Split by ### separator
    final segments = content.split(RegExp(r'^###\s*$', multiLine: true));

    var seq = 0;
    for (final segment in segments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('@') && !trimmed.toUpperCase().startsWith('@')) continue;

      final request = _parseRequest(trimmed, seq);
      if (request != null) {
        requests.add(request);
        seq++;
      }
    }

    if (requests.isEmpty) {
      throw FormatException('no valid requests found in REST Client file');
    }

    final envs = <ImportedEnv>[];
    if (allVars.isNotEmpty) {
      envs.add(ImportedEnv(
        name: 'imported',
        variables: allVars,
        isActive: true,
      ));
    }

    return ImportedCollection(
      name: 'REST Client Import',
      requests: requests,
      environments: envs,
    );
  }

  @override
  Future<String> export(ExportedProject project) async {
    final sb = StringBuffer();

    for (final env in project.environments) {
      for (final v in env.variables) {
        sb.writeln('@${v.key} = {{${v.key}}}');
      }
    }

    if (project.environments.isNotEmpty) sb.writeln();

    for (final req in project.requests) {
      sb.writeln(_exportRequest(req));
      sb.writeln('###');
      sb.writeln();
    }

    return sb.toString();
  }

  // ── Import helpers ────────────────────────────────────────────────

  ImportedRequest? _parseRequest(String segment, int seq) {
    final lines = segment.split('\n');
    if (lines.isEmpty) return null;

    // First non-empty, non-comment line should be the request line
    String? requestLine;
    String? displayName;
    var startIdx = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Check for comment name: # @name requestName
      final nameMatch = RegExp(r'#\s*@name\s+(\S+)').firstMatch(line);
      if (nameMatch == null) {
        final commentNameMatch = RegExp(r'^//\s*@name\s+(\S+)').firstMatch(line);
        if (commentNameMatch != null) {
          displayName = commentNameMatch.group(1);
          continue;
        }
      } else {
        displayName = nameMatch.group(1);
        continue;
      }

      requestLine = line;
      startIdx = i + 1;
      break;
    }

    if (requestLine == null) return null;

    final rlParts = requestLine.split(RegExp(r'\s+'));
    if (rlParts.isEmpty) return null;

    final method = rlParts[0].toUpperCase();
    if (!['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'].contains(method)) {
      return null;
    }

    var url = rlParts.length > 1 ? rlParts[1] : '';
    url = _convertVars(url);

    final headers = <String, String>{};
    var bodyStart = -1;

    for (var i = startIdx; i < lines.length; i++) {
      final line = lines[i];

      // Empty line marks end of headers
      if (line.trim().isEmpty) {
        bodyStart = i + 1;
        break;
      }

      // Comment lines
      if (line.trim().startsWith('#') || line.trim().startsWith('//')) continue;

      // Header: Key: Value
      final headerMatch = RegExp(r'^([^:]+):\s*(.*)$').firstMatch(line);
      if (headerMatch != null) {
        headers[headerMatch.group(1)!.trim()] = _convertVars(headerMatch.group(2)!.trim());
      }
    }

    String? body;
    if (bodyStart >= 0 && bodyStart < lines.length) {
      final bodyLines = lines.sublist(bodyStart);
      final bodyText = bodyLines.join('\n').trim();
      if (bodyText.isNotEmpty && !bodyText.startsWith('#')) {
        body = _convertVars(bodyText);
      }
    }

    final curl = _buildCurl(method, url, headers, body);
    displayName ??= _inferName(method, url);

    return ImportedRequest(
      path: _sanitize(displayName),
      curlContent: curl,
      meta: RequestMeta(displayName: displayName),
    );
  }

  String _buildCurl(
    String method,
    String url,
    Map<String, String> headers,
    String? body,
  ) {
    final parts = <String>['curl'];

    if (method != 'GET') {
      parts.add('-X $method');
    }

    for (final entry in headers.entries) {
      parts.add("-H '${_esc(entry.key)}: ${_esc(entry.value)}'");
    }

    if (body != null && body.isNotEmpty) {
      parts.add("-d '${_esc(body)}'");
      if (!headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
        parts.add("-H 'Content-Type: application/json'");
      }
    }

    parts.add("'${_esc(url)}'");
    return parts.join(' \\\n  ');
  }

  // ── Export helpers ────────────────────────────────────────────────

  String _exportRequest(ExportedRequest req) {
    final parsed = _safeParse(req.curlContent);
    final method = parsed?.curl.method.toUpperCase() ?? 'GET';
    final url = parsed?.curl.uri.toString() ?? '';

    final sb = StringBuffer();

    sb.writeln('# @name ${req.displayName}');
    sb.writeln();

    sb.write('$method ${_toRestVar(url)}');

    // REST Client format: method URL HTTP/1.1
    sb.writeln(' HTTP/1.1');

    if (parsed != null) {
      final headers = parsed.curl.headers;
      if (headers != null && headers.isNotEmpty) {
        headers.forEach((key, value) {
          sb.writeln('$key: ${_toRestVar(value)}');
        });
      }

      if (parsed.curl.data != null) {
        sb.writeln();
        sb.writeln(_toRestVar(parsed.curl.data!));
      }
    }

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

  String _toRestVar(String input) {
    return input.replaceAllMapped(
      RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>'),
      (m) => '{{${m.group(1)}}}',
    );
  }

  String _esc(String input) {
    return input.replaceAll("'", "'\\''");
  }

  String _inferName(String method, String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        return '$method ${segments.last}';
      }
    }
    return '$method request';
  }

  String _sanitize(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
