import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

class GitLabClient implements GitClient {
  final http.Client _client = http.Client();
  final String _apiBase;

  String? _cachedProjectId;
  String? _cachedUrl;

  GitLabClient({String? baseUrl})
    : _apiBase = (baseUrl != null && baseUrl.isNotEmpty)
          ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v4'
          : 'https://gitlab.com/api/v4';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
      };

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception(
        'authentication failed: token is invalid or expired. check your git provider settings.',
      );
    }
    if (response.statusCode == 403) {
      throw Exception(
        'forbidden: insufficient permissions. check your token scopes.',
      );
    }
  }

  Future<String> _resolveProjectId(String remoteUrl, String token) async {
    if (_cachedProjectId != null && _cachedUrl == remoteUrl) {
      return _cachedProjectId!;
    }

    final uri = Uri.parse(remoteUrl);
    final path = uri.path.substring(1).replaceAll('.git', '');
    final encoded = Uri.encodeComponent(path);

    final url = '$_apiBase/projects/$encoded';
    final response = await _client.get(
      Uri.parse(url),
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      final id = (jsonDecode(response.body)['id'] as int).toString();
      _cachedProjectId = id;
      _cachedUrl = remoteUrl;
      return id;
    }

    _checkResponse(response);
    throw Exception('project not found: $path');
  }

  @override
  Future<String?> getLatestCommitSha(
    String remoteUrl,
    String branch,
    String token,
  ) async {
    final projectId = await _resolveProjectId(remoteUrl, token);
    final url = '$_apiBase/projects/$projectId/repository/branches/$branch';
    final response = await _client.get(
      Uri.parse(url),
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['commit']['id'];
    }
    _checkResponse(response);
    return null;
  }

  @override
  Future<List<GitFile>> fetchFiles(
    String remoteUrl,
    String branch,
    String token,
  ) async {
    final projectId = await _resolveProjectId(remoteUrl, token);

    final treeUrl =
        '$_apiBase/projects/$projectId/repository/tree?recursive=true&ref=$branch&per_page=100';
    final response = await _client.get(
      Uri.parse(treeUrl),
      headers: _headers(token),
    );

    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      _checkResponse(response);
      throw Exception(_parseError(response.body));
    }

    final List tree = jsonDecode(response.body);

    final relevantItems = tree.where((item) {
      final path = item['path'] as String;
      return item['type'] == 'blob' &&
          (path.endsWith('.curl') ||
              path.endsWith('.meta.json') ||
              path == 'curel.json' ||
              path == '.gitignore');
    }).toList();

    const batchSize = 10;
    final List<GitFile> gitFiles = [];

    for (var i = 0; i < relevantItems.length; i += batchSize) {
      final batch = relevantItems.sublist(
        i,
        i + batchSize > relevantItems.length
            ? relevantItems.length
            : i + batchSize,
      );

      final results = await Future.wait(
        batch.map((item) async {
          final path = item['path'] as String;
          final encodedPath = Uri.encodeComponent(path);
          final fileUrl =
              '$_apiBase/projects/$projectId/repository/files/$encodedPath/raw?ref=$branch';
          final fileRes = await _client.get(
            Uri.parse(fileUrl),
            headers: _headers(token),
          );

          if (fileRes.statusCode == 200) {
            return GitFile(path: path, content: fileRes.body);
          }
          return null;
        }),
      );

      gitFiles.addAll(results.whereType<GitFile>());
    }

    return gitFiles;
  }

  @override
  Future<List<String>> listRemotePaths(
    String remoteUrl,
    String branch,
    String token,
  ) async {
    final projectId = await _resolveProjectId(remoteUrl, token);
    final treeUrl =
        '$_apiBase/projects/$projectId/repository/tree?recursive=true&ref=$branch&per_page=100';
    final response = await _client.get(
      Uri.parse(treeUrl),
      headers: _headers(token),
    );

    if (response.statusCode != 200) return [];

    final List tree = jsonDecode(response.body);
    return tree
        .where((item) => item['type'] == 'blob')
        .map((item) => item['path'] as String)
        .toList();
  }

  @override
  Future<String> pushFiles(
    String remoteUrl,
    String branch,
    String token,
    List<GitFile> files,
    String message,
  ) async {
    final projectId = await _resolveProjectId(remoteUrl, token);

    // Determine create vs update for each file
    final remotePaths = await listRemotePaths(remoteUrl, branch, token);
    final remotePathSet = remotePaths.toSet();

    final actions = files.map((f) {
      if (f.deletion) {
        return {'action': 'delete', 'file_path': f.path};
      }
      return {
        'action': remotePathSet.contains(f.path) ? 'update' : 'create',
        'file_path': f.path,
        'content': f.content,
      };
    }).toList();

    final commitUrl = '$_apiBase/projects/$projectId/repository/commits';
    final commitRes = await _client.post(
      Uri.parse(commitUrl),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'branch': branch,
        'commit_message': message,
        'actions': actions,
      }),
    );

    if (commitRes.statusCode != 201) {
      _checkResponse(commitRes);
      throw Exception(_parseError(commitRes.body));
    }

    return jsonDecode(commitRes.body)['id'] as String;
  }

  @override
  Future<String?> validateToken(String token, {String? baseUrl}) async {
    try {
      final apiUrl = baseUrl != null && baseUrl.isNotEmpty
          ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v4/user'
          : 'https://gitlab.com/api/v4/user';
      final response = await _client
          .get(
            Uri.parse(apiUrl),
            headers: {..._headers(token), 'User-Agent': 'Curel/1.3.0'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['username'] as String?;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<String>> listBranches(String remoteUrl, String token) async {
    final projectId = await _resolveProjectId(remoteUrl, token);
    final url = '$_apiBase/projects/$projectId/repository/branches';
    final response = await _client.get(Uri.parse(url), headers: _headers(token));

    if (response.statusCode != 200) return [];

    final List data = jsonDecode(response.body);
    return data.map((b) => b['name'] as String).toList();
  }

  @override
  Future<void> createBranch(String remoteUrl, String branch, String fromBranch, String token) async {
    final projectId = await _resolveProjectId(remoteUrl, token);
    final url = '$_apiBase/projects/$projectId/repository/branches';
    final response = await _client.post(
      Uri.parse(url),
      headers: {..._headers(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'branch': branch, 'ref': fromBranch}),
    );

    if (response.statusCode != 201) {
      _checkResponse(response);
      throw Exception(_parseError(response.body));
    }
  }

  @override
  Future<List<GitRepo>> listUserRepos(String token, {String? baseUrl}) async {
    final apiUrl = baseUrl != null && baseUrl.isNotEmpty
        ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v4'
        : 'https://gitlab.com/api/v4';
    final url = '$apiUrl/projects?membership=true&per_page=100&sort=updated';
    final response = await _client.get(Uri.parse(url), headers: _headers(token));

    if (response.statusCode != 200) {
      _checkResponse(response);
      throw Exception('failed to list projects: ${response.statusCode}');
    }

    final List data = jsonDecode(response.body);
    return data.map((r) {
      return GitRepo(
        name: r['path'] ?? '',
        owner: (r['namespace']?['path'] ?? r['owner']?['username']) ?? '',
        fullName: r['path_with_namespace'] ?? '',
        cloneUrl: r['http_url_to_repo'] ?? '',
        defaultBranch: r['default_branch'],
        isPrivate: r['visibility'] == 'private',
      );
    }).toList();
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        if (data.containsKey('message')) return data['message'].toString();
        if (data.containsKey('error')) return data['error'].toString();
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return body;
    }
  }
}
