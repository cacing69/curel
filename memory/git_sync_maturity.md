---
name: Git sync architecture and maturity
description: Phase 2 git sync — multi-provider (GitHub + GitLab), sync layers, conflict resolution, data flow
type: project
---

## Phase 2 Status: Feature Complete (MVP)

All core git sync features implemented for GitHub and GitLab. Self-hosted supported for both.

## Multi-Provider Architecture

### Client implementations
- `GitHubClient(baseUrl)` — GitHub.com + GitHub Enterprise
- `GitLabClient(baseUrl)` — gitlab.com + self-hosted GitLab
- Both implement `GitClient` abstract class

### Provider differences

| | GitHub | GitLab |
|---|---|---|
| auth header | `Authorization: token` | `PRIVATE-TOKEN` |
| project ID | `owner/repo` from URL | resolved numeric ID (cached) |
| push flow | 4-step: ref → tree → commit → update ref | 1-step: single `POST /commits` |
| delete | `sha: null` in tree entry | `"action": "delete"` in commit |
| self-hosted API | `{baseUrl}/api/v3` | `{baseUrl}/api/v4` |
| token validation | `GET /user` | `GET /api/v4/user` |

### GitLab project ID resolution
- URL path encoded: `company/team/api` → `company%2Fteam%2Fapi`
- Resolved to numeric ID via `GET /api/v4/projects/:encoded_path`
- Cached per session (`_cachedProjectId`) — only 1 resolve call per sync session
- Robust: ID survives project rename/group transfer

### _getClient dispatch
All clients dispatched via centralized factory in `git_client.dart`:
```dart
GitClient.create(type, baseUrl: baseUrl)
// 'github' → GitHubClient, 'gitlab' → GitLabClient, 'gitea' → GiteaClient
```
**Never** instantiate client classes directly. Gitea (`GiteaClient`) added in Phase 3.

> **Gitea quirk**: `GET /git/refs/heads/{branch}` can return inconsistent null values for `object.sha` on some instances. Always use `GET /branches/{branch}` → `commit.id` for reliable SHA lookup in `getLatestCommitSha` and `pushFiles`.

## Sync Architecture

### Service layers
- `GitClient` (abstract) → `GitHubClient` / `GitLabClient` — pure API wrapper
- `GitSyncService` — business logic (pull, push, sync, conflict detection)
- `SyncController` — orchestrates filesystem re-sync after sync operations
- `DeviceService` — anonymized device fingerprint (SHA-256 truncated to 7 chars)

### Data flow
```
env_bar (UI) → GitSyncService.sync() → pull() + push()
                                        ↓           ↓
                                   merge local   optimistic lock
                                   + overwrite    + delete propagation
                                        ↓           ↓
                                   client.pushFiles() → returns new commit SHA
```

## Safety Layers (3-layer protection)

1. **Service-level optimistic lock** — `push()` compares remote SHA with `lastSyncSha`, rejects if different
2. **Service-level delete propagation** — `push()` compares remote tree with local, sends deletion entries
3. **API-level fast-forward check** — GitHub `force: false` in ref update / GitLab single commit

## Pull Strategy (merge, not overwrite)

- `curel.json` — always overwritten (metadata: local ID injection, connection info)
- New remote files — created locally
- Identical files — safe overwrite
- Local files that differ from remote — **kept** (filesystem wins), conflict count reported
- Local-only files — preserved (never deleted by pull)

## Push Features

- `.gitignore` injected as repo infrastructure on every push
- `remote_origin_id` injected into `curel.json` for cross-device identity
- Device fingerprint in commit message: `sync from curel v1.x (abc1234) 2026-05-10 14:30:00`
- `lastSyncSha` updated after every successful push/sync (carried via `GitSyncResult.newSyncSha`)

## Conflict Resolution

- **New connection + both sides have data** → `hasConflict: true`, user picks pull overwrite or push overwrite
- **Origin ID mismatch** — rejected ("repo belongs to a different project")
- **Not a curel repo** — rejected (no `curel.json` found)
- **Force push path** — `push(project, force: true)` skips optimistic lock (conflict resolution only)

## Error Handling

- **401** — "authentication failed: token is invalid or expired"
- **403 rate limit** — "rate limited: resets at HH:MM" (parses `X-RateLimit-Reset`)
- **403 forbidden** — "forbidden: insufficient permissions"
- Toast shows actual error; terminal area keeps full error for debug/copy-paste

## UI Feedback

- Sync button: green = synced, orange = not synced yet, spinner = syncing
- Tooltip on sync button with status info
- Toast shows actual error message (terminal keeps full error)
- Project list: cloud icon color-coded by sync status

## Key files
- `lib/domain/services/git_client.dart` — abstract contract, GitFile, GitSyncResult, factory
- `lib/data/services/github_client.dart` — GitHub API (constructor accepts baseUrl)
- `lib/data/services/gitlab_client.dart` — GitLab API (project ID resolution with cache)
- `lib/data/services/gitea_client.dart` — Gitea/Forgejo API
- `lib/domain/services/git_sync_service.dart` — sync business logic
- `lib/domain/services/diff_service.dart` — diff_match_patch wrapper (computeChanges, compare, isDifferent)
- `lib/application/sync_controller.dart` — post-sync filesystem re-index
- `lib/presentation/widgets/env_bar.dart` — sync UI button, conflict dialogs, branch chip
- `lib/presentation/widgets/branch_picker_dialog.dart` — list/switch/create branches
- `lib/presentation/widgets/conflict_dialog.dart` — per-file L/R conflict resolution
- `lib/presentation/widgets/diff_viewer_dialog.dart` — visual line-by-line diff before sync
- `lib/presentation/widgets/git_connect_dialog.dart` — connect project to git
- `lib/presentation/screens/git_providers_page.dart` — provider CRUD with token validation

## Phase 3 Additions (on top of Phase 2)

### DiffService + Incremental Sync
- `DiffService.computeChanges(localFiles, remoteFiles)` — computes `List<FileChange>` (added/deleted/modified)
- `GitSyncService.computePendingChanges(project)` — no writes, returns diff for UI preview
- `sync(project, selectedPaths: [...])` — partial sync: only sync user-selected files

### Conflict Resolution UI Flow
```
sync() returns hasConflict: true
  → computePendingChanges() → List<FileChange>
  → ConflictDialog (side-by-side, per-file L/R toggle)
  → pullWithResolution(resolutions) — apply remote-kept files
  → pushWithResolution(resolutions) — push resolved state
```

### Branch Management
- `GitClient.listBranches(remoteUrl, token)` — implemented in all providers
- `GitClient.createBranch(remoteUrl, branch, fromBranch, token)` — REST-only, no local changes
- `GitSyncService.listBranches(project)` / `createBranch(project, name, from)`
- UI: branch chip in `env_bar.dart` → `BranchPickerDialog`
- Switch branch flow: `copyWith(branch: selected, lastSyncSha: null)` → `pull(force: true)` → `syncAndRefresh()`

**Why:** Phase 2 supports multiple git providers with clean abstraction. Adding new providers only needs a new client class + `GitClient.create()` case.
**How to apply:** New providers implement `GitClient`. Register in `GitClient.create()` factory. No other registration needed.
