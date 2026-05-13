---
name: Phase 3 Expansion — New Items
description: New Phase 3 items added 2026-05-13 based on codebase gap analysis and product philosophy alignment
type: project
---

## Added Items (2026-05-13)

Six new items added to Phase 3 (Maturity & Pluginable Growth) after codebase exploration:

### Bruno Import/Export Adapter

**Why:** Bruno is a local-first, open-source API client with a `.bru` file format. Its philosophy (filesystem-first, git-friendly) aligns perfectly with Curel's. The adapter architecture is already in place — this is a pure pluginable growth item.

### VS Code REST Client Import Adapter

**Why:** `.http`/`.rest` files are widely used by developers in VS Code. Since the format is essentially curl commands with metadata, implementation is straightforward. Fits the filesystem-first philosophy and expands Curel's reach to VS Code users.

### Code Snippet Generation

**Why:** Standard feature in professional API clients (Postman, Insomnia, Hoppscotch all have it). Each target language acts as an "adapter" — clean extension point. Developer-oriented, matches Curel's target audience.

### Cookie Jar Management

**Why:** Real curl has `--cookie-jar` for persistent cookie storage. Curel currently only sends manual cookies via builder tab. Adding a persistent cookie jar mimics real curl behavior and is a maturity milestone. Cookies stored as filesystem sidecar (`.cookiejar.json`) per project.

### ~~HAR Import/Export~~ (moved to Phase 5c)

### ~~SSL/TLS Certificate Management~~ (moved to Phase 5c)

## Philosophy Alignment

All six items follow Curel's core philosophy:

- **Filesystem-first** — `.bru`, `.http`, `.cookiejar.json`, `.har` are all filesystem artifacts
- **Local-first** — no cloud dependency for any of these features
- **Git-friendly** — all formats are text-based and git-syncable
- **Pluginable** — adapters, snippet generators, and cookie storage all follow clean interface patterns
- **Developer-oriented** — every item solves a real developer workflow problem

## Priority Order

1. ✅ Code snippet generation (DONE — implemented 2026-05-13)
2. Bruno adapter (lowest effort, highest philosophy alignment)
3. Cookie jar management (mimics real curl behavior)
4. VS Code REST Client adapter (straightforward implementation)
5. ~~HAR import/export~~ → moved to Phase 5c
6. ~~SSL/TLS certificate management~~ → moved to Phase 5c

## Added Items (2026-05-13 — Wave 2)

Eight new items added after gap analysis of curl fidelity, filesystem DNA, and developer workflow gaps.

### Batch curl Import

**Why:** Entry point pertama user ke Curel — developer punya curl commands, paste ke app, mulai kerja. Semua kompetitor memaksa import via format koleksi. Curel bisa langsung terima raw curl text, auto-split jadi multiple `.curl` files.

**How to apply:** Multi-line paste detection di import flow — parse each line starting with `curl` as separate request. Reuse `CurlParserService` per command. Show preview before creating files.

### Simple Response Assertions

**Why:** Postman punya test assertions tapi butuh scripting. Versi sederhana tanpa JS runtime cukup cover 80% use case (status range, body contains, header exists, json path check, response time). Visual pass/fail badge di response viewer. Foundation untuk scripting assertions di Phase 5b.

**How to apply:** Assertions disimpan di `.meta.json` sebagai array. Type enum: `status_range`, `body_contains`, `header_exists`, `json_path`, `response_time`. Run after each response execution. Green/red badge per assertion + summary.

### Request Notes (`.notes.md` sidecar)

**Why:** Developer butuh catatan per request — dokumentasi API, TODO, known issues. `RequestMeta.description` hanya satu string pendek. Markdown file = git-diffable, bisa di-review di PR, bisa di-edit di text editor mana pun.

**How to apply:** Sidecar file mengikuti pattern `.curl` + `.meta.json`. `.notes.md` per request. Editable dari UI (markdown editor sederhana) atau langsung di filesystem. Render markdown di viewer.

### curl Config Support (`.curlrc`)

**Why:** curl punya `~/.curlrc` untuk default flags. Per-project `.curlrc` = default headers, proxy, insecure flag, user-agent yang otomatis apply ke semua request di project. Fitur ini **tidak ada di Postman/Insomnia/Bruno** tapi sangat natural untuk curl user. Filesystem artifact, git-syncable, zero UI needed.

**How to apply:** `.curlrc` di root folder `requests/`. Parse sebagai curl flags (reuse `CurlParserService`). Merge dengan per-request flags (request wins on conflict). Apply di `_executeCurl` sebelum execute.

### Proxy Configuration

**Why:** curl punya `--proxy`, `--proxy-header`, `--noproxy`. Developer butuh proxy untuk testing dari region berbeda, corporate network, atau intercept via Burp/Charles/mitmproxy. Curl fidelity murni.

**How to apply:** Set di `.curlrc` (project-level) atau per-request flags. Di `CurlHttpClient` set `dio.options.proxy` dan `dio.httpClientAdapter` dengan `IOHttpClientAdapter` yang punya proxy config. Support SOCKS5, HTTP proxy.

### Folder-level Environment Override

**Why:** Env sekarang hanya global + per-project. Workflow nyata: folder `auth/` butuh credentials berbeda dari folder `admin/`. Layered resolution yang sudah ada (global → project) natural di-extend ke (global → project → folder → subfolder). Fitur ini **tidak ada di kompetitor** dan sangat selaras dengan filesystem philosophy.

**How to apply:** `.env.json` per folder di `requests/`. Extend env resolution chain di `EnvService`: load global → project → walk folder path → merge. Folder env override pada key collision, sama seperti project env override global.

### Network Throttle Presets

**Why:** Developer mobile selalu perlu test slow network. Fitur ada di Chrome DevTools tapi **tidak ada di API client manapun** (Postman/Insomnia/Bruna tidak punya). Bisa jadi unique differentiator.

**How to apply:** Preset visual di request builder: slow 3G (1.6 Mbps, 300ms), fast 3G (1.6 Mbps, 100ms), offline (instant timeout), custom throttle. Implement via Dio interceptors yang delay response stream. Simulate bandwidth limit.

### Duplicate Request with Env Switch

**Why:** Workflow "satu request, multiple environment" sekarang harus manual. Shortcut yang menghubungkan request management dengan env system yang sudah matang.

**How to apply:** Clone request ke folder yang sama, auto-bind ke env berbeda via `targetEnv` di `.meta.json`. Rename otomatis (`login.curl` → `login-staging.curl`). 1-tap dari request drawer context menu.

## Philosophy Alignment (Wave 2)

- **Filesystem-first** — `.curlrc`, `.notes.md`, `.env.json` per folder semua filesystem artifacts
- **Local-first** — semua fitur tanpa cloud dependency
- **Git-friendly** — semua format text-based, git-diffable, git-syncable
- **Raw curl-based** — `.curlrc`, proxy, throttle semua memperdalam curl fidelity
- **Developer-oriented** — batch import (onboarding), assertions (testing), notes (docs), throttle (mobile dev)
