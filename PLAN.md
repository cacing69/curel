# Curel — Product Architecture Plan

## Core Philosophy

- Filesystem-first
- Local-first
- Git-friendly
- Raw curl-based
- Developer-oriented

## Cross-platform Targets

Android (primary), iOS, macOS, Windows, Linux, Web

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

- [x] **Native libcurl Integration** — Replaced Dio HTTP client with native libcurl via `dart:ffi`. Full `CurlHttpClient` interface implementation with write/header callbacks, `CURLOPT_CAINFO` (Mozilla CA bundle bundled in `assets/cacert.pem`), `--pinnedpubkey` support via `CURLOPT_PINNEDPUBLICKEY`, and `executeRaw()` for unsupported flags. Builds `libcurl.so` via `scripts/build_curl_android.sh` for arm64-v8a (6MB), armeabi-v7a (4.3MB), x86_64 (6.4MB) with OpenSSL 3.5.0, zlib. Removed all Dio dependencies from pubspec.yaml and all source files.

- [x] **Dialog Control Bar Refactor** — Unified all dialog action buttons to use `TermButton` with `bordered` variant (compare/sync/conflict/import/save dialogs). Removed local `_ActionButton`, `_footerButton`, `_btn` definitions. Added `bordered` and `color` parameters to `TermButton`. Conflict dialog: fixed layout crash (Spacer inside horizontal scroll), redesigned to vertical preview (local top/remote bottom), moved bulk actions to sidebar header, reduced sidebar width 180→130.

- [x] **Pluginable Collection Engine** (Adapter Pattern)
- [x] **Curel Data Convention** (ImportedCollection)
- [x] **Internal Adapters** (Curel Native implemented)
- [x] **Smarter sync** (Incremental diff with `diff_match_patch`)
- [x] **Diff Viewer UI** (Visual line-by-line comparison) — Checkbox size reduced (24→16px) with `Transform.scale(0.7)`, `shrinkWrap`, `VisualDensity.compact` for compact file list sidebar.
- [x] **Conflict UI & Partial Sync** (Selective file sync) — Vertical stacked preview (local top/remote bottom), sidebar reduced 180→130px, `[all L]`/`[all R]` bulk chips in sidebar header, footer simplified to cancel+resolve, fixed `Spacer`+horizontal scroll crash.
- [x] **Branch Management** (Git branch switching)
- [x] **Environment Protection** (Sensitive variables masking)
- [x] **Postman Import** (Postman v2.1 collection adapter)
- [x] **Collection Export** (Postman/Insomnia/Hoppscotch/Curel Native export adapters)
- [x] **Insomnia Import** (Insomnia v4 adapter)
- [x] **OAuth Device Flow for GitHub** (token-less auth via device flow) — requires registered OAuth App client_id
- [x] **Crash Log Service Fix** — Fixed `CrashLogService` eager `_init()` (called before `runApp`) → changed to `late final` lazy init pattern. Added 5s timeout guard in `crash_log_page.dart` `_load()` to prevent infinite spinner on Isar open failure.
- [x] **Default Project Persistence** — Project "default" is now undeletable: menu option hidden in `project_list_page.dart`, `ProjectService.delete()` blocks by name, `ensureDefaultProject()` auto-deduplicates legacy duplicates from disk + SharedPreferences, `create()` prevents duplicate "default" naming.
- [x] **Bruno Import/Export** — adapter for `.bru` format (open-source local-first API client)
- [x] **VS Code REST Client Import** — adapter for `.http`/`.rest` files
- [x] **Code Snippet Generation** — 7 languages: cURL, Python, JS fetch, Go, Dart http, PHP, Java OkHttp
- [x] **Save Sample Response** — save response bodies categorized by status code group (`2xx`, `4xx`, etc.) into `samples/` folder alongside `.curl` file, with user-provided names, `.meta.json` sidecars, and import/export support
- [x] **Cookie Jar Management** — named cookie jars per project (`.cookiejar/` dir), Netscape format import, auto-inject `-b` flag, auto-capture `Set-Cookie`, RFC 6265 domain/path matching
- [x] **Batch curl Import** — paste multiple curl commands at once, auto-split into separate `.curl` files (entry point feature for onboarding)
- [ ] **Simple Response Assertions** — visual pass/fail assertions per request without scripting (status range, body contains, header exists, json path, response time)
- [x] **Request Notes** — `.notes.md` sidecar file per request for developer documentation, git-diffable markdown
- [x] **curl Config Support** — per-project `.curlrc` for default curl flags (headers, proxy, insecure, user-agent)
- [x] **curl Parser Robustness** — Fixed `--pinnedpubkey` and other TLS flags crash (value `sha256//...` parsed as URL). Added `_protectNonUrlValues()` to shield non-HTTP values from parser. Added `_nativeOnlyFlags` detection + `needsNativeCurl` auto-fallback for 30+ unsupported flags. Native curl fallback via `Process.run` on desktop, libcurl FFI on mobile.
- [ ] **Proxy Configuration** — `--proxy`, `--proxy-header`, `--noproxy` support for corporate networks and interception tools (Burp/Charles/mitmproxy)

- [ ] **Folder-level Environment Override** — `.env.json` per folder extending layered env resolution (global → project → folder → subfolder)
- [ ] **Network Throttle Presets** — simulate slow 3G / fast 3G / offline, visual presets in request builder (unique differentiator)
- [x] **Duplicate Request with Env Switch** — clone request auto-bound to different environment target

### Phase 4: Network Traffic Interception (HTTPCanary-style)

System-wide HTTP/HTTPS traffic capture via local VPN. Android-first, iOS deferred. Captured traffic auto-converted to `.curl` files in `_intercept/` project. Major differentiator feature — no other API client does this.

**Requires:** Native platform code (Kotlin/Java for Android VpnService) + Dart FFI/platform channels bridge.

#### Phase 4a: Android HTTP-only Interception (MVP)

- [x] **Android VpnService Tunnel** — `CurelVpnService.kt`: VpnService with packet capture loop, TCP/UDP forwarding, `protect()` socket, foreground notification
- [x] **HTTP Request/Response Parser** — `TcpFlow.kt`: TCP stream reassembly, HTTP request detection (method, URL, headers, body), SNI extraction for HTTPS
- [x] **Flutter Platform Bridge** — `VpnFlutterBridge.kt` + `MainActivity.kt`: MethodChannel `curel/traffic_capture`, batch-delivery every 200ms, VPN permission via `startActivityForResult`
- [x] **Traffic Log Viewer** — `TrafficLogPage`: real-time captured request list, method/URL badge, expandable headers/body, tap-to-copy curl
- [x] **Auto-export to `.curl`** — `CapturedRequest.toCurl()` converter, copy to clipboard
- [x] **Foreground Service** — Notification channel + ongoing notification with stop action

#### Phase 4b: HTTPS Interception (TLS MITM)

- [x] **Local CA Certificate Generator** — `CertManager.kt`: 2048-bit RSA root CA (PKCS12 keystore), per-hostname cert via SNI (BouncyCastle `bcpkix-jdk18on`), KeyChain API for one-tap install
- [x] **TLS MITM Engine** — `TlsMitmEngine.kt`: SSLEngine-based byte-level TLS termination, ClientHello SNI extraction, dynamic cert per hostname, HTTP request capture from decrypted stream
- [x] **HTTPS Capture** — `TcpFlow.kt` port 443 routing to MITM engine, TLS handshake + forward to real server
- [ ] **SSL Pinning Bypass (best-effort)** — some apps pin certificates; document limitation

#### Phase 4c: iOS (later)

- [ ] **iOS Local Proxy Mode** — user manually sets proxy in WiFi settings; curel runs local HTTP proxy server (no VPN requirement); limited to WiFi, no cellular
- [ ] **iOS VPN (if feasible)** — explore `NEPacketTunnelProvider`; likely App Store rejection risk → document tradeoffs

### Phase 5: Response Comparison / Query / Scripting (ACTIVE)

#### Phase 5a: Response Comparison (Part 1 — Core Diff Engine) ✅

- [x] `ResponseDiffEngine` abstract class + `JsonDiffEngine` impl
- [x] `DiffEntry` model — path, valueA, valueB, DiffType enum (added/removed/changed/unchanged)
- [x] `DiffView` widget — unified diff view (git-diff style), color-coded
- [x] Compare button in response viewer toolbar (home + fullscreen)
- [x] CompareSourceDialog — editable curl editor with syntax highlighting (CurlHighlightController), saved request loader with search filter, 80% dialog sizing
- [x] Field ignore / masking — auto-detect volatile fields (timestamp, uuid, etc.)
- [x] Terminal-style loading (no spinners)

**Phase 5a — Part 2 (next):**
- [ ] TextDiffEngine (Myers algorithm) for non-JSON
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

- Pre-request scripts — run before each request (set env vars, modify headers, generate tokens, compute signatures)
- Post-response scripts — run after each response (extract values into env vars, assert status codes, chain requests)
- Script format: `.js` sidecar file per request or project-level scripts, executed in sandboxed JS runtime
- Use cases: auto-refresh OAuth tokens, sign AWS requests, extract session IDs, run test assertions
- Integration with env system — scripts can read/write env variables dynamically

#### Phase 5d: Tooling & Interoperability

- [ ] **HAR Import/Export** — HTTP Archive format for browser dev tools interop
- [ ] **SSL/TLS Certificate Management** — self-signed cert, mTLS client certificates

#### Phase 5e: AI Integration (BYOK)

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
        .curlrc                # project-level default curl flags
        .cookiejar/            # named cookie jars
          default.cookiejar.json
        login.curl            # curl commands
        login.meta.json       # request metadata
        login.query.json      # response query/transformation definitions
        login.baseline.json   # response baseline snapshot for diff comparison
        login.notes.md        # developer notes per request
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
