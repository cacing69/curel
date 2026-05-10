abstract class GitClient {
  /// Get the latest commit SHA from a branch
  Future<String?> getLatestCommitSha(String remoteUrl, String branch, String token);

  /// Fetch all files from a remote repository branch
  Future<List<GitFile>> fetchFiles(String remoteUrl, String branch, String token);
  
  /// Push local changes to the remote repository
  Future<void> pushFiles(String remoteUrl, String branch, String token, List<GitFile> files, String message);
}

class GitFile {
  final String path;
  final String content;

  GitFile({required this.path, required this.content});
}

class GitSyncResult {
  final bool success;
  final String message;
  final int filesCount;
  final bool hasConflict;
  final dynamic data;

  GitSyncResult({
    required this.success,
    required this.message,
    this.filesCount = 0,
    this.hasConflict = false,
    this.data,
  });
}
