import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:curel/domain/services/git_client.dart';

class GitHubClient implements GitClient {
  final http.Client _client = http.Client();

  @override
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token) async {
    final parts = remoteUrl.replaceAll('https://github.com/', '').split('/');
    if (parts.length < 2) return null;
    final owner = parts[0];
    final repo = parts[1].replaceAll('.git', '');

    final refUrl = 'https://api.github.com/repos/$owner/$repo/git/refs/heads/$branch';
    final response = await _client.get(
      Uri.parse(refUrl),
      headers: {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body)['object']['sha'];
    }
    return null;
  }

  Future<List<GitFile>> fetchFiles(String remoteUrl, String branch, String token) async {
    // Parse owner and repo from URL (e.g., https://github.com/owner/repo)
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception('Invalid GitHub URL');
    
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');
    
    // 1. Get the tree recursively
    final treeUrl = 'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1';
    final response = await _client.get(
      Uri.parse(treeUrl),
      headers: {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );

    if (response.statusCode == 409) {
      // GitHub returns 409 if the repository is empty (no commits)
      return [];
    }

    if (response.statusCode != 200) {
      throw Exception(_parseError(response.body));
    }

    final treeData = jsonDecode(response.body);
    final List tree = treeData['tree'];
    
    // 2. Filter only relevant files (.curl, .meta.json, curel.json)
    final List<GitFile> gitFiles = [];
    for (final item in tree) {
      final path = item['path'] as String;
      if (item['type'] == 'blob' && 
          (path.endsWith('.curl') || path.endsWith('.meta.json') || path == 'curel.json')) {
        
        // Fetch content
        final blobUrl = item['url'] as String;
        final blobRes = await _client.get(
          Uri.parse(blobUrl),
          headers: {
            'Authorization': 'token $token',
            'Accept': 'application/vnd.github.v3.raw', // Get raw content directly
          },
        );

        if (blobRes.statusCode == 200) {
          gitFiles.add(GitFile(path: path, content: blobRes.body));
        }
      }
    }

    return gitFiles;
  }

  @override
  Future<void> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message) async {
    final uri = Uri.parse(remoteUrl);
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception('Invalid GitHub URL');
    
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');
    final headers = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.v3+json',
      'Content-Type': 'application/json',
    };

    // 1. Get the latest commit SHA from the branch
    final refUrl = 'https://api.github.com/repos/$owner/$repo/git/refs/heads/$branch';
    final refRes = await _client.get(Uri.parse(refUrl), headers: headers);
    
    String? baseTreeSha;
    String? latestCommitSha;

    if (refRes.statusCode == 200) {
      latestCommitSha = jsonDecode(refRes.body)['object']['sha'];
      // Get the tree SHA from that commit
      final commitUrl = 'https://api.github.com/repos/$owner/$repo/git/commits/$latestCommitSha';
      final commitRes = await _client.get(Uri.parse(commitUrl), headers: headers);
      baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'];
    } else if (refRes.statusCode == 404 || refRes.statusCode == 409) {
      // Branch doesn't exist or repo is empty.
      // TRICK: Perform an initial commit of curel.json using Content API to "wake up" the repo
      final curelFile = files.firstWhere((f) => f.path == 'curel.json', orElse: () => files.first);
      final initUrl = 'https://api.github.com/repos/$owner/$repo/contents/${curelFile.path}';
      
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
        throw Exception(_parseError(initRes.body));
      }

      // Now that the repo is initialized, we can proceed with a normal tree sync for the rest of the files
      // or just return if it was the only file.
      if (files.length <= 1) return;

      // Re-fetch the ref now that it exists
      final refResRetry = await _client.get(Uri.parse(refUrl), headers: headers);
      if (refResRetry.statusCode == 200) {
        latestCommitSha = jsonDecode(refResRetry.body)['object']['sha'];
        final commitUrl = 'https://api.github.com/repos/$owner/$repo/git/commits/$latestCommitSha';
        final commitRes = await _client.get(Uri.parse(commitUrl), headers: headers);
        baseTreeSha = jsonDecode(commitRes.body)['tree']['sha'];
      }
    }

    // 2. Create a new Tree
    final treeUrl = 'https://api.github.com/repos/$owner/$repo/git/trees';
    final treeBody = {
      if (baseTreeSha != null) 'base_tree': baseTreeSha,
      'tree': files.map((f) => {
        'path': f.path,
        'mode': '100644', // normal file
        'type': 'blob',
        'content': f.content,
      }).toList(),
    };

    final treeRes = await _client.post(
      Uri.parse(treeUrl),
      headers: headers,
      body: jsonEncode(treeBody),
    );

    if (treeRes.statusCode != 201) {
      throw Exception(_parseError(treeRes.body));
    }
    final newTreeSha = jsonDecode(treeRes.body)['sha'];

    // 3. Create a Commit
    final commitsUrl = 'https://api.github.com/repos/$owner/$repo/git/commits';
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
      throw Exception(_parseError(commitRes.body));
    }
    final newCommitSha = jsonDecode(commitRes.body)['sha'];

    // 4. Update the Reference (Push)
    if (latestCommitSha != null) {
      final updateRefUrl = 'https://api.github.com/repos/$owner/$repo/git/refs/heads/$branch';
      final updateRes = await _client.patch(
        Uri.parse(updateRefUrl),
        headers: headers,
        body: jsonEncode({'sha': newCommitSha, 'force': true}),
      );
      if (updateRes.statusCode != 200) {
        throw Exception(_parseError(updateRes.body));
      }
    } else {
      // Create new ref if it didn't exist
      final createRefUrl = 'https://api.github.com/repos/$owner/$repo/git/refs';
      final createRes = await _client.post(
        Uri.parse(createRefUrl),
        headers: headers,
        body: jsonEncode({'ref': 'refs/heads/$branch', 'sha': newCommitSha}),
      );
      if (createRes.statusCode != 201) {
        throw Exception(_parseError(createRes.body));
      }
    }
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
