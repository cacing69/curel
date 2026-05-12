import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

/// Gitea / Forgejo REST client.
///
/// Key differences from GitHub:
/// - Branches API (`/branches/{branch}`) is used for SHA lookups — more
///   reliable than `/git/refs` which can return inconsistent structures.
/// - Push uses the **Contents API** (`PUT/POST/DELETE /contents/{path}`)
///   because Gitea does NOT expose `POST /git/trees` or `POST /git/commits`
///   (those are GitHub-only Git Data API endpoints).
/// - Tree fetches require a real tree SHA (obtained via commit object), not a
///   branch name, on some Gitea versions.
class GiteaClient implements GitClient {
  final http.Client _client = http.Client();
  final String _apiBase;

  GiteaClient({String? baseUrl})
      : _apiBase = (baseUrl != null && baseUrl.isNotEmpty)
            ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1'
            : 'https://gitea.com/api/v1';

  // ── Auth headers ────────────────────────────────────────────────

  Map<String, String> _h(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Map<String, String> _jh(String token) => {
        ..._h(token),
        'Content-Type': 'application/json',
      };

  // ── Error helpers ────────────────────────────────────────────────

  void _checkResponse(http.Response res) {
    if (res.statusCode == 401) {
      throw Exception(
          'authentication failed: token is invalid or expired. check your git provider settings.');
    }
    if (res.statusCode == 403) {
      throw Exception(
          'forbidden: insufficient permissions. check your token scopes.');
    }
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data.containsKey('message')) return data['message'] as String;
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return body;
    }
  }

  // ── URL parser ───────────────────────────────────────────────────

  /// Returns (owner, repo) or (null, null) if URL is invalid.
  (String?, String?) _parseUrl(String remoteUrl) {
    final segments = Uri.parse(remoteUrl)
        .pathSegments
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.length < 2) return (null, null);
    return (segments[0], segments[1].replaceAll('.git', ''));
  }

  /// Encode each path segment but preserve slashes for the Contents API.
  String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  // ── Core interface ───────────────────────────────────────────────

  @override
  Future<String?> getLatestCommitSha(
      String remoteUrl, String branch, String token) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) return null;

    final res = await _client.get(
        Uri.parse('$_apiBase/repos/$owner/$repo/branches/$branch'),
        headers: _h(token));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      return (data?['commit'] as Map<String, dynamic>?)?['id'] as String?;
    }
    _checkResponse(res);
    return null;
  }

  @override
  Future<List<GitFile>> fetchFiles(
      String remoteUrl, String branch, String token) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) throw Exception('invalid Gitea URL');

    // Gitea's /git/trees/{sha} needs a real tree SHA, not a branch name.
    // Resolve: branch → commit SHA → tree SHA.
    final treeSha = await _resolveBranchTreeSha(owner, repo, branch, token);
    if (treeSha == null) return [];

    final treeUrl =
        '$_apiBase/repos/$owner/$repo/git/trees/$treeSha?recursive=true';
    final res =
        await _client.get(Uri.parse(treeUrl), headers: _h(token));

    if (res.statusCode == 404 || res.statusCode == 409) return [];
    if (res.statusCode != 200) {
      _checkResponse(res);
      throw Exception(_parseError(res.body));
    }

    final List tree =
        (jsonDecode(res.body) as Map<String, dynamic>?)?['tree'] ?? [];

    final relevant = tree.where((item) {
      final path = item['path'] as String;
      return item['type'] == 'blob' &&
          (path.endsWith('.curl') ||
              path.endsWith('.meta.json') ||
              path == 'curel.json' ||
              path == '.gitignore');
    }).toList();

    const batchSize = 10;
    final files = <GitFile>[];
    for (var i = 0; i < relevant.length; i += batchSize) {
      final batch = relevant.sublist(
          i, (i + batchSize).clamp(0, relevant.length));
      final results = await Future.wait(batch.map((item) async {
        final path = item['path'] as String;
        final fileRes = await _client.get(
            Uri.parse(
                '$_apiBase/repos/$owner/$repo/raw/${_encodePath(path)}?ref=$branch'),
            headers: _h(token));
        return fileRes.statusCode == 200
            ? GitFile(path: path, content: fileRes.body)
            : null;
      }));
      files.addAll(results.whereType<GitFile>());
    }
    return files;
  }

  @override
  Future<List<String>> listRemotePaths(
      String remoteUrl, String branch, String token) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) return [];

    final treeSha = await _resolveBranchTreeSha(owner, repo, branch, token);
    if (treeSha == null) return [];

    final res = await _client.get(
        Uri.parse(
            '$_apiBase/repos/$owner/$repo/git/trees/$treeSha?recursive=true'),
        headers: _h(token));
    if (res.statusCode != 200) return [];

    final List tree =
        (jsonDecode(res.body) as Map<String, dynamic>?)?['tree'] ?? [];
    return tree
        .where((item) => item['type'] == 'blob')
        .map((item) => item['path'] as String)
        .toList();
  }

  /// Gitea does NOT have `POST /git/trees` or `POST /git/commits`.
  /// Push is implemented using the **Contents API** — one request per file.
  @override
  Future<String> pushFiles(
    String remoteUrl,
    String branch,
    String token,
    List<GitFile> files,
    String message,
  ) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) throw Exception('invalid Gitea URL');

    // Fetch blob SHAs for all affected files in parallel.
    // Required for update (PUT) and delete (DELETE) via the Contents API.
    final shaEntries = await Future.wait(files.map((f) async =>
        MapEntry(f.path, await _getFileSha(owner, repo, f.path, branch, token))));
    final shaMap = Map<String, String?>.fromEntries(shaEntries);

    // Apply each change via the Contents API.
    for (final file in files) {
      final sha = shaMap[file.path];
      if (file.deletion) {
        if (sha != null) {
          await _deleteContents(
              owner, repo, file.path, sha, branch, message, token);
        }
      } else {
        await _upsertContents(
            owner, repo, file.path, file.content, sha, branch, message, token);
      }
    }

    // Return the new HEAD commit SHA.
    return await getLatestCommitSha(remoteUrl, branch, token) ?? '';
  }

  @override
  Future<String?> validateToken(String token, {String? baseUrl}) async {
    try {
      final apiUrl = (baseUrl != null && baseUrl.isNotEmpty)
          ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/user'
          : 'https://gitea.com/api/v1/user';
      final res = await _client
          .get(Uri.parse(apiUrl),
              headers: {..._h(token), 'User-Agent': 'curel-app'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return (jsonDecode(res.body) as Map<String, dynamic>?)?['username']
            as String?;
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<List<String>> listBranches(String remoteUrl, String token) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) return [];
    final res = await _client.get(
        Uri.parse('$_apiBase/repos/$owner/$repo/branches'),
        headers: _h(token));
    if (res.statusCode != 200) return [];
    final List data = jsonDecode(res.body);
    return data.map((b) => b['name'] as String).toList();
  }

  @override
  Future<void> createBranch(
      String remoteUrl, String branch, String fromBranch, String token) async {
    final (owner, repo) = _parseUrl(remoteUrl);
    if (owner == null || repo == null) throw Exception('invalid Gitea URL');
    final res = await _client.post(
      Uri.parse('$_apiBase/repos/$owner/$repo/branches'),
      headers: _jh(token),
      body: jsonEncode(
          {'new_branch_name': branch, 'old_branch_name': fromBranch}),
    );
    if (res.statusCode != 201) {
      _checkResponse(res);
      throw Exception(_parseError(res.body));
    }
  }

  // ── Private helpers ──────────────────────────────────────────────

  /// Resolves a branch name to its root tree SHA:
  /// branch → commit.id → commit.tree.sha
  Future<String?> _resolveBranchTreeSha(
      String owner, String repo, String branch, String token) async {
    final res = await _client.get(
        Uri.parse('$_apiBase/repos/$owner/$repo/branches/$branch'),
        headers: _h(token));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    final commitSha =
        (data?['commit'] as Map<String, dynamic>?)?['id'] as String?;
    if (commitSha == null) return null;
    return _getCommitTreeSha(owner, repo, commitSha, token);
  }

  Future<String?> _getCommitTreeSha(
      String owner, String repo, String commitSha, String token) async {
    final res = await _client.get(
        Uri.parse('$_apiBase/repos/$owner/$repo/git/commits/$commitSha'),
        headers: _h(token));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>?;
    return (data?['tree'] as Map<String, dynamic>?)?['sha'] as String?;
  }

  /// Fetch the blob SHA of a file (needed for Contents API update/delete).
  Future<String?> _getFileSha(
      String owner, String repo, String path, String branch, String token) async {
    try {
      final res = await _client.get(
          Uri.parse(
              '$_apiBase/repos/$owner/$repo/contents/${_encodePath(path)}?ref=$branch'),
          headers: _h(token));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map<String, dynamic>?)?['sha'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Create (POST) or update (PUT) a file via the Contents API.
  Future<void> _upsertContents(
    String owner,
    String repo,
    String path,
    String content,
    String? existingSha,
    String branch,
    String message,
    String token,
  ) async {
    final url =
        '$_apiBase/repos/$owner/$repo/contents/${_encodePath(path)}';
    final body = jsonEncode({
      'message': message,
      'content': base64Encode(utf8.encode(content)),
      'branch': branch,
      if (existingSha != null) 'sha': existingSha,
    });

    final http.Response res = existingSha != null
        ? await _client.put(Uri.parse(url), headers: _jh(token), body: body)
        : await _client.post(Uri.parse(url), headers: _jh(token), body: body);

    if (res.statusCode != 200 && res.statusCode != 201) {
      _checkResponse(res);
      throw Exception(_parseError(res.body));
    }
  }

  /// Delete a file via the Contents API.
  /// Requires the current blob SHA.
  Future<void> _deleteContents(
    String owner,
    String repo,
    String path,
    String sha,
    String branch,
    String message,
    String token,
  ) async {
    final url =
        '$_apiBase/repos/$owner/$repo/contents/${_encodePath(path)}';
    final request = http.Request('DELETE', Uri.parse(url));
    request.headers.addAll(_jh(token));
    request.body =
        jsonEncode({'message': message, 'sha': sha, 'branch': branch});
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 204) {
      _checkResponse(res);
      throw Exception(_parseError(res.body));
    }
  }
}
