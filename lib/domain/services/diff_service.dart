import 'package:diff_match_patch/diff_match_patch.dart';

enum ChangeType { added, deleted, modified, unchanged }

class FileChange {
  final String path;
  final ChangeType type;
  final String? oldContent;
  final String? newContent;
  final List<Diff>? diffs;

  FileChange({
    required this.path,
    required this.type,
    this.oldContent,
    this.newContent,
    this.diffs,
  });

  bool get hasChanges => type != ChangeType.unchanged;
}

class DiffService {
  final _dmp = DiffMatchPatch();

  /// Compare two strings and return the diffs
  List<Diff> compare(String oldText, String newText) {
    return _dmp.diff(oldText, newText);
  }

  /// Check if two strings are different
  bool isDifferent(String oldText, String newText) {
    if (oldText == newText) return false;
    // For large files, we could use a fast hash, but for .curl files string comparison is fine
    return true;
  }

  /// Generate a summary of changes between local and remote file sets
  List<FileChange> computeChanges(
    Map<String, String> localFiles,
    Map<String, String> remoteFiles,
  ) {
    final allPaths = {...localFiles.keys, ...remoteFiles.keys};
    final changes = <FileChange>[];

    for (final path in allPaths) {
      final local = localFiles[path];
      final remote = remoteFiles[path];

      if (local == null && remote != null) {
        changes.add(FileChange(
          path: path,
          type: ChangeType.added,
          newContent: remote,
        ));
      } else if (local != null && remote == null) {
        changes.add(FileChange(
          path: path,
          type: ChangeType.deleted,
          oldContent: local,
        ));
      } else if (local != null && remote != null) {
        if (isDifferent(local, remote)) {
          changes.add(FileChange(
            path: path,
            type: ChangeType.modified,
            oldContent: local,
            newContent: remote,
            diffs: compare(local, remote),
          ));
        }
      }
    }

    return changes;
  }
}
