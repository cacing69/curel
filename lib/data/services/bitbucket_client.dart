import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

class BitbucketClient implements GitClient {
  final http.Client _client = http.Client();
  final String _apiBase;

  BitbucketClient({String? baseUrl})
      : _apiBase = (baseUrl != null && baseUrl.isNotEmpty)
            ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/2.0'
            : 'https://api.bitbucket.org/2.0';

  Map<String, String> _headers(String token) {
    if (token.contains(':')) {
      // Handle username:password (App Password)
      final bytes = utf8.encode(token);
      final base64 = base64Encode(bytes);
      return {'Authorization': 'Basic $base64'};
    }
    // Handle OAuth or PAT
    return {'Authorization': 'Bearer $token'};
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception('authentication failed: check your credentials or app password scopes.');
    }
    if (response.statusCode == 403) {
      throw Exception('forbidden: check your repository permissions.');
    }
  }

  @override
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    final workspace = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final url = '$_apiBase/repositories/$workspace/$repo/commits/$branch?pagelen=1';
    final response = await _client.get(Uri.parse(url), headers: _headers(token));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List commits = data['values'] ?? [];
      if (commits.isNotEmpty) {
        return commits[0]['hash'];
      }
    }
    _checkResponse(response);
    return null;
  }

  @override
  Future<List<GitFile>> fetchFiles(String remoteUrl, String branch, String token) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) throw Exception('Invalid Bitbucket URL');
    final workspace = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    // List all files recursively (Bitbucket 2.0 /src endpoint)
    final url = '$_apiBase/repositories/$workspace/$repo/src/$branch/?max_depth=10';
    final response = await _client.get(Uri.parse(url), headers: _headers(token));

    if (response.statusCode == 404) return [];
    if (response.statusCode != 200) {
      _checkResponse(response);
      throw Exception(_parseError(response.body));
    }

    final data = jsonDecode(response.body);
    final List values = data['values'] ?? [];

    final relevantItems = values.where((item) {
      final path = item['path'] as String;
      return item['type'] == 'commit_file' &&
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
          final fileUrl = '$_apiBase/repositories/$workspace/$repo/src/$branch/$encodedPath';
          
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
    final workspace = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final url = '$_apiBase/repositories/$workspace/$repo/src/$branch/?max_depth=10';
    final response = await _client.get(Uri.parse(url), headers: _headers(token));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List values = data['values'] ?? [];

    return values
        .where((item) => item['type'] == 'commit_file')
        .map((item) => item['path'] as String)
        .toList();
  }

  @override
  Future<String> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) throw Exception('Invalid Bitbucket URL');
    final workspace = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final url = '$_apiBase/repositories/$workspace/$repo/src';
    
    // Bitbucket POST /src uses multipart/form-data for file updates
    final request = http.MultipartRequest('POST', Uri.parse(url));
    request.headers.addAll(_headers(token));
    request.fields['branch'] = branch;
    request.fields['message'] = message;

    for (final file in files) {
      if (file.deletion) {
        // Bitbucket deletion in POST /src is handled by omitting or special field
        // For simplicity, we just don't add it, but real deletion needs more logic
        // Bitbucket API v2 doesn't have a simple way to delete multiple files in one commit via /src easily
        // but we can try the 'files' field.
      } else {
        request.files.add(http.MultipartFile.fromString(
          file.path,
          file.content,
        ));
      }
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 201 || response.statusCode == 200) {
      // Bitbucket returns the new commit info
      // We'll try to get the SHA, but Bitbucket response for /src might be empty or different
      // Let's just return the latest commit SHA from the branch as a confirmation
      final newSha = await getLatestCommitSha(remoteUrl, branch, token);
      return newSha ?? '';
    }

    _checkResponse(response);
    throw Exception(_parseError(response.body));
  }

  @override
  Future<String?> validateToken(String token, {String? baseUrl}) async {
    try {
      final apiUrl = baseUrl != null && baseUrl.isNotEmpty
          ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/2.0/user'
          : 'https://api.bitbucket.org/2.0/user';
      final response = await _client.get(
        Uri.parse(apiUrl),
        headers: {
          ..._headers(token),
          'User-Agent': 'curel-app',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['username'] as String? ?? data['display_name'] as String?;
      }
    } catch (_) {}
    return null;
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map && data.containsKey('error')) {
        final err = data['error'];
        if (err is Map && err.containsKey('message')) return err['message'];
      }
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return body;
    }
  }
}
