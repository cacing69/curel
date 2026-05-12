# Curel — Git Sync System

## Overview

Git sync is built on a **pure REST API layer** — no `git` binary, no `libgit2`. All operations (fetch, push, diff, branch) are done via provider REST APIs.

---

## GitClient — Abstract Interface

`lib/domain/services/git_client.dart`

```
abstract class GitClient {
  Future<String?> getLatestCommitSha(remoteUrl, branch, token)
  Future<List<GitFile>> fetchFiles(remoteUrl, branch, token)
  Future<List<String>> listRemotePaths(remoteUrl, branch, token)
  Future<String> pushFiles(remoteUrl, branch, token, files, message)
  Future<String?> validateToken(token, {baseUrl})
  Future<List<String>> listBranches(remoteUrl, token)
  Future<void> createBranch(remoteUrl, branch, fromBranch, token)

  static GitClient create(String type, {String? baseUrl})  // factory
}
```

### Supported Providers
| type | Class | Notes |
|---|---|---|
| `'github'` | `GitHubClient` | REST API, supports self-hosted via `baseUrl` |
| `'gitlab'` | `GitLabClient` | REST API, supports self-hosted via `baseUrl` |
| `'gitea'` | `GiteaClient` | REST API, Gitea/Forgejo |

**Bitbucket excluded** — API limitations (no tree fetch).

Single dispatch: **always use `GitClient.create(type, baseUrl: ...)`**, never instantiate client classes directly.

---

## GitSyncService

`lib/domain/services/git_sync_service.dart`

### Core Operations

#### `pull(project, {force, selectedPaths})`
1. Fetch latest SHA from remote
2. Fast-forward check: if remote SHA == local `lastSyncSha` → already up-to-date
3. Fetch all remote files (parallel batch of 10)
4. Compute diff (local vs remote)
5. Write remote files to disk (merge strategy: local wins on conflict unless `force: true`)
6. Return `GitSyncResult` with new SHA

#### `push(project, {selectedPaths})`
1. Get latest remote SHA (optimistic lock check)
2. Read all local files
3. Compute additions/modifications/deletions vs remote
4. Push via `pushFiles()` with device fingerprint in commit message
5. Return `GitSyncResult` with new SHA

#### `sync(project, {selectedPaths})`
Wraps pull-then-push. Detects if conflict occurred during pull (returns `hasConflict: true`).

#### `computePendingChanges(project)`
Compares local filesystem vs remote (no writes). Returns `List<FileChange>` for the diff viewer.

#### `pullWithResolution(project, resolutions)`
Used after conflict dialog. `resolutions` is a `Map<path, 'local'|'remote'>`. For each file:
- `'remote'` → overwrite local with remote content
- `'local'` → keep local (skip remote file)

#### `pushWithResolution(project, resolutions)`
After `pullWithResolution`, push the resolved state to remote.

#### `listBranches(project)` / `createBranch(project, newBranch, fromBranch)`
Delegates to `GitClient`. Used by `BranchPickerDialog`.

---

## 3-Layer Safety

1. **Optimistic lock** — Check remote SHA before push. If remote has moved, abort.
2. **Delete propagation** — Track deleted files and send deletion markers in push.
3. **Fast-forward check** — If local `lastSyncSha` == remote SHA, skip pull (already in sync).

---

## DiffService

`lib/domain/services/diff_service.dart` — wraps `diff_match_patch` package.

```
computeChanges(localFiles, remoteFiles) → List<FileChange>
compare(oldText, newText) → List<Diff>   // line-level diffs
isDifferent(oldText, newText) → bool
```

`FileChange.type` enum: `added | deleted | modified | unchanged`

---

## Conflict Flow (UI)

```
sync() → hasConflict: true
  ↓
computePendingChanges() → List<FileChange>
  ↓
ConflictDialog (side-by-side diff viewer, per-file L/R toggle)
  ↓  resolutions: Map<path, 'local'|'remote'>
pullWithResolution() → apply remote-kept files
pushWithResolution() → push resolved state
```

---

## Branch Management

`BranchPickerDialog` — shows all remote branches, allows switching and creating.

Switch branch flow:
1. `project.copyWith(branch: selected, lastSyncSha: null)` — reset sync state
2. `gitSyncService.pull(updated, force: true)` — pull from new branch
3. `syncController.syncAndRefresh()` — rebuild UI from disk

Create branch:
- `gitSyncService.createBranch(project, name, fromBranch)` — REST call only, no local changes

---

## `remote_origin_id`

Cross-device project identity. Set on first successful sync (from remote `curel.json`). Used to match the same project across different devices even if local `project_id` differs.

---

## `.gitignore` Auto-Injection

On push, Curel auto-injects `.gitignore` with:
```
environments/
.env
*.local
```
This ensures sensitive env values never get committed.

---

## Commit Message Format

```
curel sync · {deviceName} · {appVersion}
```

Device name comes from `DeviceService` (device_info_plus).

---

## GitProviderModel

`lib/domain/models/git_provider_model.dart`

```dart
class GitProviderModel {
  final String id;
  final String name;
  final String type;    // 'github' | 'gitlab' | 'gitea'
  final String? baseUrl;
}
```

Tokens are **never stored in `providers.json`** — they go to `FlutterSecureStorage` keyed by `provider.id`.
