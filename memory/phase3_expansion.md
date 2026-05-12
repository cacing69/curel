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
