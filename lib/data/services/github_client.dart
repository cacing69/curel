import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

class GitHubClient implements GitClient {
  final http.Client _client = http.Client();
  final String _apiBase;

  GitHubClient({String? baseUrl})
      : _apiBase = (baseUrl != null && baseUrl.isNotEmpty)
            ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v3'
            : 'https://api.github.com';

  Map<String, String> _headers(String token) => {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github.v3+json',
      };

  void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      throw Exception('authentication failed: token is invalid or expired. check your git provider settings.');
    }
    if (response.statusCode == 403) {
      final remaining = response.headers['x-ratelimit-remaining'];
      if (remaining == '0') {
        final resetEpoch = int.tryParse(response.headers['x-ratelimit-reset'] ?? '');
        final resetTime = resetEpoch != null
            ? DateTime.fromMillisecondsSinceEpoch(resetEpoch * 1000)
            : null;
        final waitHint = resetTime != null
            ? ' rate limit resets at ${resetTime.hour.toString().padLeft(2, '0')}:${resetTime.minute.toString().padLeft(2, '0')}.'
            : '';
        throw Exception('rate limited:$waitHint try again later.');
      }
      throw Exception('forbidden: ${_parseError(response.body)}');
    }
  }

  @override
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token) async {
    final parts = remoteUrl.replaceAll('https://github.com/', '').split('/');
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1].replaceAll('.git', '');

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
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception('Invalid GitHub URL');

    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    // 1. Get the tree recursively
    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees/$branch?recursive=1';
    final response = await _client.get(Uri.parse(treeUrl), headers: _headers(token));

    if (response.statusCode == 409) return [];
    if (response.statusCode != 200) {
      _checkResponse(response);
      throw Exception(_parseError(response.body));
    }

    final treeData = jsonDecode(response.body);
    final List tree = treeData['tree'];

    // 2. Filter relevant files
    final relevantItems = tree.where((item) {
      final path = item['path'] as String;
      return item['type'] == 'blob' &&
          (path.endsWith('.curl') ||
              path.endsWith('.meta.json') ||
              path == 'curel.json' ||
              path == '.gitignore');
    }).toList();

    // 3. Fetch blobs in parallel batches of 10
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
          final blobUrl = item['url'] as String;
          final blobRes = await _client.get(
            Uri.parse(blobUrl),
            headers: {
              'Authorization': 'token $token',
              'Accept': 'application/vnd.github.v3.raw',
            },
          );
          if (blobRes.statusCode == 200) {
            return GitFile(path: path, content: blobRes.body);
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
    final segments = uri.pathSegments;
    if (segments.length < 2) return [];

    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees/$branch?recursive=1';
    final response = await _client.get(Uri.parse(treeUrl), headers: _headers(token));

    if (response.statusCode == 409) return [];
    if (response.statusCode != 200) return [];

    final treeData = jsonDecode(response.body);
    final List tree = treeData['tree'];

    return tree
        .where((item) => item['type'] == 'blob')
        .map((item) => item['path'] as String)
        .toList();
  }

  @override
  Future<String> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception('Invalid GitHub URL');
    
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');
    final headers = {
      ..._headers(token),
      'Content-Type': 'application/json',
    };

    // 1. Get the latest commit SHA from the branch
    final refUrl = '$_apiBase/repos/$owner/$repo/git/refs/heads/$branch';
    final refRes = await _client.get(Uri.parse(refUrl), headers: headers);
    
    String? baseTreeSha;
    String? latestCommitSha;

    if (refRes.statusCode == 200) {
      latestCommitSha = jsonDecode(refRes.body)['object']['sha'];
      final commitUrl = '$_apiBase/repos/$owner/$repo/git/commits/$latestCommitSha';
      final commitRes = await _client.get(Uri.parse(commitUrl), headers: headers);
      if (commitRes.statusCode != 200) {
        _checkResponse(commitRes);
        throw Exception(_parseError(commitRes.body));
      }
      baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'];
    } else if (refRes.statusCode == 404 || refRes.statusCode == 409) {
      // Branch doesn't exist or repo is empty.
      // TRICK: Perform an initial commit of curel.json using Content API to "wake up" the repo
      final curelFile = files.firstWhere((f) => f.path == 'curel.json', orElse: () => files.first);
      final initUrl = '$_apiBase/repos/$owner/$repo/contents/${curelFile.path}';
      
      final initRes = await _client.put(
        Uri.parse(initUrl),
        headers: headers,
        body: jsonEncode({
          'message': message, // Use the passed detailed message
          'content': base64Encode(utf8.encode(curelFile.content)),
          'branch': branch,
        }),
      );

      if (initRes.statusCode != 201) {
        _checkResponse(initRes);
        throw Exception(_parseError(initRes.body));
      }

      // Now that the repo is initialized, we can proceed with a normal tree sync for the rest of the files
      // or just return if it was the only file.
      if (files.length <= 1) {
        // Return the SHA from the initial commit we just made
        final initCommitRes = await _client.get(
          Uri.parse('$_apiBase/repos/$owner/$repo/git/refs/heads/$branch'),
          headers: headers,
        );
        if (initCommitRes.statusCode == 200) {
          return jsonDecode(initCommitRes.body)['object']['sha'] as String;
        }
        return '';
      }

      // Re-fetch the ref now that it exists
      final refResRetry = await _client.get(Uri.parse(refUrl), headers: headers);
      if (refResRetry.statusCode == 200) {
        latestCommitSha = jsonDecode(refResRetry.body)['object']['sha'];
        final commitUrl = '$_apiBase/repos/$owner/$repo/git/commits/$latestCommitSha';
        final commitRes = await _client.get(Uri.parse(commitUrl), headers: headers);
        baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'];
      }
    }

    // 2. Create a new Tree
    final treeUrl = '$_apiBase/repos/$owner/$repo/git/trees';
    final treeBody = {
      if (baseTreeSha != null) 'base_tree': baseTreeSha,
      'tree': files.map((f) {
        final entry = <String, dynamic>{
          'path': f.path,
          'mode': '100644',
          'type': 'blob',
        };
        if (f.deletion) {
          entry['sha'] = null;
        } else {
          entry['content'] = f.content;
        }
        return entry;
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

    // 3. Create a Commit
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

    // 4. Update the Reference (Push)
    if (latestCommitSha != null) {
      final updateRefUrl = '$_apiBase/repos/$owner/$repo/git/refs/heads/$branch';
      final updateRes = await _client.patch(
        Uri.parse(updateRefUrl),
        headers: headers,
        body: jsonEncode({'sha': newCommitSha, 'force': false}),
      );
      if (updateRes.statusCode != 200) {
        _checkResponse(updateRes);
        throw Exception(_parseError(updateRes.body));
      }
    } else {
      // Create new ref if it didn't exist
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
    final apiUrl = baseUrl != null && baseUrl.isNotEmpty
        ? '$baseUrl/api/v3/user'
        : '$_apiBase/user';
    final response = await _client.get(
      Uri.parse(apiUrl),
      headers: _headers(token),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['login'] as String?;
    }
    return null;
  }

  String _parseError(String body) {
    try {
      final data = jsonDecode(body);
      // If it's a valid JSON, return it prettified
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return body;
    }
  }
}
