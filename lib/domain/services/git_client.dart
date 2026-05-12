import 'package:curel/data/services/github_client.dart';
import 'package:curel/data/services/gitlab_client.dart';
import 'package:curel/data/services/gitea_client.dart';

abstract class GitClient {
  /// Get the latest commit SHA from a branch
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token);

  /// Fetch all files from a remote repository branch
  Future<List<GitFile>> fetchFiles(String remoteUrl, String branch, String token);

  /// List only file paths from remote tree (no content fetch)
  Future<List<String>> listRemotePaths(String remoteUrl, String branch, String token);

  /// Push local changes to the remote repository. Returns the new commit SHA.
  Future<String> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message);

  /// Validate token by testing authentication. Returns username on success, null on failure.
  Future<String?> validateToken(String token, {String? baseUrl});

  /// List all branch names in the remote repository
  Future<List<String>> listBranches(String remoteUrl, String token);

  /// Create a new branch from an existing branch
  Future<void> createBranch(String remoteUrl, String branch, String fromBranch, String token);

  /// List user's repositories. Returns list of repos the authenticated user has access to.
  Future<List<GitRepo>> listUserRepos(String token, {String? baseUrl});

  /// Single factory — add new providers here only
  static GitClient create(String type, {String? baseUrl}) {
    switch (type) {
      case 'github':
        return GitHubClient(baseUrl: baseUrl);
      case 'gitlab':
        return GitLabClient(baseUrl: baseUrl);
      case 'gitea':
        return GiteaClient(baseUrl: baseUrl);
      default:
        throw Exception('provider "$type" not supported');
    }
  }
}

class GitFile {
  final String path;
  final String content;
  final bool deletion;

  GitFile({required this.path, required this.content, this.deletion = false});
}

class GitSyncResult {
  final bool success;
  final String message;
  final int filesCount;
  final bool hasConflict;
  final String? newSyncSha;
  final dynamic data;
  /// File paths affected by this operation, prefixed with operation symbol:
  /// `+ path` = added/updated, `- path` = deleted, `↑ path` = pushed
  final List<String> affectedFiles;

  GitSyncResult({
    required this.success,
    required this.message,
    this.filesCount = 0,
    this.hasConflict = false,
    this.newSyncSha,
    this.data,
    this.affectedFiles = const [],
  });
}

class GitRepo {
  final String name;
  final String owner;
  final String fullName;
  final String cloneUrl;
  final String? defaultBranch;
  final bool isPrivate;

  GitRepo({
    required this.name,
    required this.owner,
    required this.fullName,
    required this.cloneUrl,
    this.defaultBranch,
    this.isPrivate = false,
  });
}
