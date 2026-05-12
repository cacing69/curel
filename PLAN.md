# Curel — Product Architecture Plan

## Core Philosophy

- Filesystem-first
- Local-first
- Git-friendly
- Raw curl-based
- Developer-oriented

## Cross-platform Targets

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

### Phase 2 (COMPLETE)

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
- Bitbucket excluded due to API limitations

### Phase 3: Maturity & Pluginable Growth (Ongoing)

- [x] **Pluginable Collection Engine** (Adapter Pattern)
- [x] **Curel Data Convention** (ImportedCollection)
- [x] **Internal Adapters** (Curel Native implemented)
- [x] **Smarter sync** (Incremental diff with `diff_match_patch`)
- [x] **Diff Viewer UI** (Visual line-by-line comparison)
- [x] **Conflict UI & Partial Sync** (Selective file sync)
- [x] **Branch Management** (Git branch switching)
- [x] **Environment Protection** (Sensitive variables masking)
- [x] **Postman Import** (Postman v2.1 collection adapter)
- [x] **Collection Export** (Postman/Insomnia/Hoppscotch/Curel Native export adapters)
- [x] **Insomnia Import** (Insomnia v4 adapter)
- [x] **OAuth Device Flow for GitHub** (token-less auth via device flow) — requires registered OAuth App client_id
- [ ] **Bruno Import/Export** — adapter for `.bru` format (open-source local-first API client)
- [ ] **VS Code REST Client Import** — adapter for `.http`/`.rest` files
- [x] **Code Snippet Generation** — 7 languages: cURL, Python, JS fetch, Go, Dart http, PHP, Java OkHttp
- [x] **Save Sample Response** — save response bodies categorized by status code group (`2xx`, `4xx`, etc.) into `samples/` folder alongside `.curl` file, with user-provided names, `.meta.json` sidecars, and import/export support
- [ ] **Cookie Jar Management** — persistent cookie storage mimicking real curl `--cookie-jar`

### Phase 5: Response Comparison / Query / Scripting (ACTIVE)

#### Phase 5a: Response Comparison (Part 1 — Core Diff Engine)

- [ ] `ResponseDiffEngine` abstract class + `JsonDiffEngine` impl
- [ ] `DiffEntry` model — path, valueA, valueB, DiffType enum (added/removed/changed/unchanged)
- [ ] `DiffView` widget — inline card-based diff view, color-coded
- [ ] Compare button in response viewer toolbar
- [ ] CompareSourceDialog — URL input mode, fetch target, show diff
- [ ] Field ignore / masking — auto-detect volatile fields (timestamp, uuid, etc.)

**Phase 5a — Part 2 (after Part 1):**
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

#### Phase 5b: Response Query & Transformation (after 5a)

- JSON response query engine — jq-like syntax (subset: path access, array iteration, filter, pipe, object construction)
- `.query.json` sidecar file per request — query definitions as filesystem files, git-syncable
- Query tab in response viewer — live preview with syntax highlighting
- Env variable binding — `target: "env:VAR_NAME"` writes extracted value to current environment
- Target types: `env:VAR` (write to env), `display` (show in viewer), `clipboard` (copy), `chain:PATH` (pass to next request)
- Query engine as clean abstract class — reusable as expression evaluator in scripting

#### Phase 5c: Pre/Post-request Scripts

#### Phase 5b: Pre/Post-request Scripts

- Pre-request scripts — run before each request (set env vars, modify headers, generate tokens, compute signatures)
- Post-response scripts — run after each response (extract values into env vars, assert status codes, chain requests)
- Script format: `.js` sidecar file per request or project-level scripts, executed in sandboxed JS runtime
- Use cases: auto-refresh OAuth tokens, sign AWS requests, extract session IDs, run test assertions
- Integration with env system — scripts can read/write env variables dynamically

#### Phase 5c: Tooling & Interoperability

- [ ] **HAR Import/Export** — HTTP Archive format for browser dev tools interop
- [ ] **SSL/TLS Certificate Management** — self-signed cert, mTLS client certificates

#### Phase 5d: AI Integration (BYOK)

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
        samples/               # saved response samples
          2xx/
            login-success.json       # response body
            login-success.meta.json  # metadata (status, headers, contentType, timestamp)
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
- 3-layer safety: optimistic lock -> delete propagation -> fast-forward check
- Merge pull: local files preserved if different from remote
