import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

class GiteaClient implements GitClient {
  final http.Client _client = http.Client();
  final String _apiBase;

  GiteaClient({String? baseUrl})
      : _apiBase = (baseUrl != null && baseUrl.isNotEmpty)
            ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1'
            : 'https://gitea.com/api/v1';

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception('authentication failed: token is invalid or expired. check your git provider settings.');
    }
    if (response.statusCode == 403) {
      throw Exception('forbidden: insufficient permissions. check your token scopes.');
    }
  }

  @override
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final refUrl = '$_apiBase/repos/$owner/$repo/git/refs/heads/$branch';
    final response = await _client.get(Uri.parse(refUrl), headers: _headers(token));

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['object']['sha'];
    }
    _checkResponse(response);
    return null;
  }

  @override
  Future<List<GitFile>> fetchFiles(String remoteUrl, String branch, String token) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) throw Exception('Invalid Gitea URL');

    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees/$branch?recursive=true';
    final response = await _client.get(Uri.parse(treeUrl), headers: _headers(token));

    if (response.statusCode == 404 || response.statusCode == 409) return [];
    if (response.statusCode != 200) {
      _checkResponse(response);
      throw Exception(_parseError(response.body));
    }

    final treeData = jsonDecode(response.body);
    final List tree = treeData['tree'] ?? [];

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
        i + batchSize > relevantItems.length ? relevantItems.length : i + batchSize,
      );

      final results = await Future.wait(
        batch.map((item) async {
          final path = item['path'] as String;
          final encodedPath = Uri.encodeComponent(path);
          final fileUrl = '$_apiBase/repos/$owner/$repo/raw/$encodedPath?ref=$branch';
          
          final fileRes = await _client.get(Uri.parse(fileUrl), headers: _headers(token));

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
  Future<List<String>> listRemotePaths(String remoteUrl, String branch, String token) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return [];

    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees/$branch?recursive=true';
    final response = await _client.get(Uri.parse(treeUrl), headers: _headers(token));

    if (response.statusCode != 200) return [];

    final treeData = jsonDecode(response.body);
    final List tree = treeData['tree'] ?? [];

    return tree
        .where((item) => item['type'] == 'blob')
        .map((item) => item['path'] as String)
        .toList();
  }

  @override
  Future<String> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) throw Exception('Invalid Gitea URL');
    
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');
    final headers = {
      ..._headers(token),
      'Content-Type': 'application/json',
    };

    // Gitea supports the same tree/commit/ref flow as GitHub
    // 1. Get latest commit
    final refUrl = '$_apiBase/repos/$owner/$repo/git/refs/heads/$branch';
    final refRes = await _client.get(Uri.parse(refUrl), headers: headers);
    
    String? baseTreeSha;
    String? latestCommitSha;

    if (refRes.statusCode == 200) {
      latestCommitSha = jsonDecode(refRes.body)['object']['sha'];
      final commitUrl = '$_apiBase/repos/$owner/$repo/git/commits/$latestCommitSha';
      final commitRes = await _client.get(Uri.parse(commitUrl), headers: headers);
      if (commitRes.statusCode == 200) {
        baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'];
      }
    }

    // 2. Create tree
    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees';
    final treeBody = {
      if (baseTreeSha != null) 'base_tree': baseTreeSha,
      'tree': files.map((f) {
        return {
          'path': f.path,
          'mode': '100644',
          'type': 'blob',
          'content': f.deletion ? null : f.content,
          if (f.deletion) 'sha': null,
        };
      }).toList(),
    };

    final treeRes = await _client.post(
      Uri.parse(treeUrl),
      headers: headers,
      body: jsonEncode(treeBody),
    );

    if (treeRes.statusCode != 201) {
      _checkResponse(treeRes);
      throw Exception(_parseError(treeRes.body));
    }
    final newTreeSha = jsonDecode(treeRes.body)['sha'];

    // 3. Create commit
    final commitsUrl = '$_apiBase/repos/$owner/$repo/git/commits';
    final commitBody = {
      'message': message,
      'tree': newTreeSha,
      if (latestCommitSha != null) 'parents': [latestCommitSha],
    };

    final commitRes = await _client.post(
      Uri.parse(commitsUrl),
      headers: headers,
      body: jsonEncode(commitBody),
    );

    if (commitRes.statusCode != 201) {
      _checkResponse(commitRes);
      throw Exception(_parseError(commitRes.body));
    }
    final newCommitSha = jsonDecode(commitRes.body)['sha'];

    // 4. Update ref
    final updateRefUrl = '$_apiBase/repos/$owner/$repo/git/refs/heads/$branch';
    final updateRes = await _client.patch(
      Uri.parse(updateRefUrl),
      headers: headers,
      body: jsonEncode({'sha': newCommitSha, 'force': false}),
    );

    if (updateRes.statusCode != 200) {
      // If patch fails (e.g. branch doesn't exist), try to create it
      final createRefUrl = '$_apiBase/repos/$owner/$repo/git/refs';
      final createRes = await _client.post(
        Uri.parse(createRefUrl),
        headers: headers,
        body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': newCommitSha}),
      );
      if (createRes.statusCode != 201) {
        _checkResponse(createRes);
        throw Exception(_parseError(createRes.body));
      }
    }

    return newCommitSha;
  }

  @override
  Future<String?> validateToken(String token, {String? baseUrl}) async {
    try {
      final apiUrl = baseUrl != null && baseUrl.isNotEmpty
          ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/user'
          : 'https://gitea.com/api/v1/user';
      final response = await _client.get(
        Uri.parse(apiUrl),
        headers: {
          ..._headers(token),
          'User-Agent': 'curel-app',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['username'] as String?;
      }
    } catch (_) {}
    return null;
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data.containsKey('message')) return data['message'];
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return body;
    }
  }
}
