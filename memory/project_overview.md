---
name: Project Overview
description: Comprehensive information about the Curel Flutter HTTP client application architecture and rules
type: project
---

## App Identity & Purpose
Curel is a cross-platform curl client built with Flutter that mimics real `curl` CLI behavior with mobile-optimized UI. Every feature decision must stay true to curl's behavior and flags. Fully developed with AI assistance.

## Architecture Overview
**Pattern:** Clean Architecture (Domain-Data-Presentation)
**State Management:** Riverpod (manual providers, no code gen due to isar conflicts)
**Database:** Isar for history and local cache
**HTTP:** Dio-based (not real curl binary)
**Storage:** Filesystem-first + SharedPreferences + Flutter Secure Storage
**Identity:** Device fingerprinting using SHA-256 (7 chars) for unique hardware identification.

## Git Sync & Roadmap
- **Phase 1: Foundation** — (Completed) Workspace management and local project indexing.
- **Phase 2: Sync Functionality** — (Completed) GitHub REST API integration, Pull/Push logic, and Sync indicators.
- **Phase 3: Maturity & Pluginable Growth** — (Mostly Done) CollectionAdapter system, DiffService, DiffViewerDialog, ConflictDialog, PostmanAdapter, InsomniaAdapter, HoppscotchAdapter, CurelNativeAdapter, Branch Management. **Remaining: OAuth Device Flow for GitHub.**
- **Phase 4: Advanced Git & Engines** — (Planned) Intelligent merging, libgit2 migration, and support for other providers (GitLab/Gitea maturity).

## Key Technical Details

### Environment Variables System
- **Syntax:** `<<VAR>>` (matches Postman/Hoppscotch behavior)
- **Storage:** Metadata in SharedPreferences, values in flutter_secure_storage
- **Resolution:** Layered (project > global > undefined with warnings)
- **Features:** CRUD operations, import/export JSON, syntax highlighting (purple)

### State Management (Riverpod)
- **Migration:** From setState + constructor prop drilling
- **No Code Gen:** riverpod_generator conflicts with isar_community_generator
- **Provider Structure:**
  - Service providers in `lib/domain/providers/services.dart` (9 services as singletons)
  - State providers in `lib/domain/providers/app_state.dart` (ActiveProjectNotifier, ResponseStateNotifier, etc.)
- **Pattern:** ConsumerStatefulWidget with ref.read() for services

### HTTP Execution Architecture
- **NOT real curl binary** - uses Dio via dart:io HttpClient
- **HTTP/1.1:** Fully supported
- **HTTP/2:** NOT supported (Dart limitation)
- **HTTP/3:** NOT supported (Dart VM has no QUIC stack)
- **Strategy Pattern:** Ready for future HTTP/3 implementations (DioCurlHttpClient, CronetCurlHttpClient, ProcessCurlHttpClient)

### UI Design System
- **Theme:** Dracula-inspired (Dark)
- **Style:** Flat Design (No shadows, no elevation, no rounded corners)
- **Typography:** All UI text lowercase (strict rule for terminal aesthetics)
- **Iconography:** Standardized icons (Sync = `Icons.sync`, Cloud = `Icons.cloud` at right-side of tiles, Git = `Icons.schema`)
- **Header:** Custom container, monospace font 11px, bold
- **Buttons:** TermButton height 28px, padding 10px horizontal, icons mandatory
- **Modularization:** Monolithic screens (e.g., HomePage) are split into `logic/` mixins and `widgets/` sub-files for better maintainability.

## Dependencies & Removed Packages
**Core:** flutter_riverpod ^2.6.1, shared_preferences, flutter_secure_storage, isar_community
**HTTP:** dio ^5.4.0, curl_parser ^0.1.2
**Removed:** encrypt (replaced by flutter_secure_storage), riverpod_generator (conflicts with isar)

## Memory Structure
- **Dual Memory System:**
  - `~/.qwen/projects/.../memory/` (Qwen system)
  - `/Users/ibnulmutaki/Development/github/curel/memory/` (Project visible copy)
- **CLAUDE.md:** Auto-loaded rules, can be regenerated from memory
- **NOTES.txt:** Session changelog tracking

**Why:** Comprehensive understanding of project architecture, constraints, and conventions is essential for providing accurate, context-aware assistance.

**How to apply:** Respect all established patterns, UI rules, and technical constraints. Use ref.read() for services, follow Dracula theme rules, and be aware of HTTP limitations. Always update NOTES.txt for code changes.