---
name: Product roadmap and architecture plan
description: Long-term architecture plan — filesystem-first, git-native curl workspace, phase progress
type: project
originSessionId: dfc18d5f-a402-4c85-816f-6e9a0da6c4e5
---
## Product Direction

Curel is evolving from a simple curl client into a **Git-native local-first curl workspace**. NOT a cloud-first Postman clone.

### Core philosophy
- Filesystem-first
- Local-first
- Git-friendly
- Raw curl-based
- Developer-oriented

### Cross-platform targets
Android, iOS, macOS, Windows, Linux, Web

## Phases

### Phase 1 (COMPLETE)
- Local projects with filesystem storage
- `.curl` file format + `.meta.json` sidecar
- Environments: filesystem JSON + FlutterSecureStorage for values
- Global env + project env with layered resolution
- Filesystem workspace with custom location support
- Workspace/project/env import/export with type validation
- History via Isar database
- Image compression for feedback
- Riverpod state management (all pages migrated)

### Phase 2 (COMPLETE — Finalized)
- Multi-provider git sync: GitHub, GitLab, Gitea (self-hosted supported for all)
- Centralized `GitClient.create()` factory — single dispatch point for all providers
- Pull, push, sync with 3-layer safety (optimistic lock, delete propagation, fast-forward check)
- Merge pull strategy (local wins on conflict, filesystem always wins)
- `.gitignore` auto-injection on push
- `remote_origin_id` for cross-device project identity
- Device fingerprint in commit messages
- Conflict detection and resolution (pull overwrite / push overwrite) with force bypass
- Token validation on provider save
- Parallel blob fetch (batches of 10)
- Centralized 401/403/rate-limit error handling
- Sync status indicators (env_bar + project list)
- Connect/disconnect git from project list and env_bar
- Robust `copyWith` with sentinel pattern for nullable field clearing
- Bitbucket excluded due to API limitations (10-item pagination, multipart push, no clean deletion)

### Phase 3: Maturity & Pluginable Growth (Ongoing)
- [x] Pluginable Collection Engine (Adapter Pattern)
- [x] Curel Data Convention (ImportedCollection)
- [x] Internal Adapters (Curel Native implemented)
- [x] Smarter sync (Incremental diff with `diff_match_patch`)
- [x] Diff Viewer UI (Visual line-by-line comparison)
- [x] Conflict UI & Partial Sync (Selective file sync)
- [x] Branch Management (Git branch switching)
- [x] Environment Protection (Sensitive variables masking)
- [x] Postman Import (Postman v2.1 collection adapter)
- [x] Collection Export (Postman/Insomnia/Hoppscotch/Curel Native export adapters)
- [x] Insomnia Import (Insomnia v4 adapter)
- [ ] OAuth Device Flow for GitHub (token-less auth)
- [ ] **Bruno Import/Export** — adapter for `.bru` format (open-source local-first API client)
- [ ] **VS Code REST Client Import** — adapter for `.http`/`.rest` files
- [x] **Code Snippet Generation** — 7 languages: cURL, Python, JS fetch, Go, Dart http, PHP, Java OkHttp
- [ ] **Cookie Jar Management** — persistent cookie storage mimicking real curl `--cookie-jar`

### Phase 5: Response Comparison / Query / Scripting (ACTIVE)

**Phase 5a — Response Comparison (Part 1 — Core Diff Engine)**
- [ ] `ResponseDiffEngine` abstract class + `JsonDiffEngine` impl
- [ ] `DiffEntry` model — path, valueA, valueB, DiffType enum (added/removed/changed/unchanged)
- [ ] `DiffView` widget — inline card-based diff view, color-coded
- [ ] Compare button in response viewer toolbar
- [ ] CompareSourceDialog — URL input mode, fetch target, show diff
- [ ] Field ignore / masking — auto-detect volatile fields (timestamp, uuid, etc.)
- Detail: `memory/response_compare.md`

**Phase 5a — Part 2 (after Part 1)**
- [ ] TextDiffEngine (Myers algorithm) for non-JSON
- [ ] Saved request as comparison source
- [ ] History entry as comparison source
- [ ] Cross-env comparison
- [ ] Persist comparison pair in `.meta.json`
- [ ] Baseline snapshot — `.baseline.json` sidecar
- [ ] Diff summary — status code, response time, content-length
- [ ] Filter chips — show all / changes only / added / removed
- [ ] Non-JSON handling (image, HTML, binary)
- [ ] Auto-compare on env switch

**Phase 5b — Response Query & Transformation (after 5a)**
- JSON response query engine — jq-like syntax (subset: path access, array ops, filter, pipe, object construction)
- `.query.json` sidecar file per request — query definitions stored as filesystem files
- Query tab in response viewer — live preview, syntax highlighting
- Env variable binding — `target: "env:VAR_NAME"` writes extracted value to current environment
- Target types: env var, display, clipboard, chain (pass to next request)
- Query engine as clean abstract class — reusable foundation for scripting engine

**Phase 5c — Pre/Post-request Scripts**
- Pre-request scripts — run before each request (set env vars, modify headers, generate tokens, compute signatures)
- Post-response scripts — run after each response (extract values into env vars, assert status codes, chain requests)
- Script format: `.js` sidecar file per request or project-level scripts, executed in sandboxed JS runtime
- Use cases: auto-refresh OAuth tokens, sign AWS requests, extract session IDs, run test assertions
- Integration with env system — scripts can read/write env variables dynamically

**Phase 5d — Tooling & Interoperability**
- [ ] **HAR Import/Export** — HTTP Archive format for browser dev tools interop
- [ ] **SSL/TLS Certificate Management** — self-signed cert, mTLS client certificates

**Phase 5e — AI Integration (BYOK)**
- [ ] **BYOK Provider System** — abstract AI provider interface supporting OpenAI, Anthropic, etc.; users configure their own API key per provider; key stored in FlutterSecureStorage
- [ ] **Response Summarizer** — "summarize" button in response viewer that sends JSON response to AI for concise summary; configurable prompt template
- [ ] **Curl Generator** — natural language to curl command: user describes what they want (e.g. "POST login with email and password"), AI generates the curl command and fills the editor
- [ ] **Prompt Template System** — user-editable prompt templates stored as filesystem files, shareable/git-syncable
- [ ] **AI Chat Panel** — conversational interface alongside the editor for iterative request building, response analysis, and troubleshooting

## Workspace Structure
```
{supportDir}/curel/
  projects/
    .global/
      environments/
        default.json          # global env (flat vars)
    {project-id}/
      curel.json              # project metadata (id, remote_origin_id, connection info)
      .gitignore              # auto-injected (environments/, .env, *.local)
      environments/
        development.json      # project env
      requests/
        login.curl            # curl commands
        login.meta.json       # request metadata
        login.query.json      # response query/transformation definitions
        login.baseline.json   # response baseline snapshot for diff comparison
        auth/
          login.curl          # subfolder support
```

## Identity
- Primary: `project_id + relative_path`
- Path-based: git-friendly, filesystem-native, human-readable
- `remote_origin_id`: cross-device identity (set on first sync, preserved across devices)

## Sync Philosophy
- **Filesystem always wins**: filesystem > database
- Manual sync first (Pull/Push/Sync buttons)
- 3-layer safety: optimistic lock → delete propagation → fast-forward check
- Merge pull: local files preserved if different from remote

**Why:** Phase 3 remaining: OAuth Device Flow, Bruno adapter, VS Code REST Client, cookie jar. HAR and SSL/TLS moved to Phase 5c. Phase 5a (response query + response comparison) is next priority after Phase 3 — extract/transform JSON responses with jq-like syntax, stored as `.query.json` sidecar files, plus compare responses across URLs with mobile-friendly diff. Both enhance the response viewer. Bridges to Phase 5b scripting.
**How to apply:** Query engine must be separate abstract class for reuse in scripting. Diff engine must be pure Dart, testable, with DiffView widget reusable for git file diffs later. `.query.json` follows existing sidecar pattern (`.curl` + `.meta.json`). Env integration reuses `<<VAR>>` system. For new Phase 3 items: each new format adapter follows `CollectionAdapter` interface in `adapter_registry.dart`; code snippet generators implement `SnippetGenerator` abstract class at `lib/domain/snippets/` and register in `SnippetRegistry`; cookie jar stored as filesystem sidecar per project.
