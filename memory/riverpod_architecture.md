---
name: Riverpod architecture
description: State management using Riverpod, provider structure, dependency injection pattern
type: project
originSessionId: 2af1b075-62f0-401f-be91-e2928d72dfab
---
## State Management: Riverpod

Migrated from `setState` + constructor prop drilling to **flutter_riverpod** (manual providers, no code gen).

### Why no riverpod_generator
`riverpod_generator` conflicts with `isar_community_generator` — both depend on incompatible `build` package versions. Solution: manual Riverpod providers, no code generation.

### Provider structure

**Service providers** (`lib/domain/providers/services.dart`):
- All services wrapped as `Provider` (singleton, keepAlive by nature)
- Services access via `ref.read(providerName)` — not `ref.watch()` since services don't change
- Current providers: `fileSystemProvider`, `settingsProvider`, `httpClientProvider`, `envServiceProvider`, `projectServiceProvider`, `requestServiceProvider`, `historyServiceProvider`, `bookmarkServiceProvider`, `clipboardServiceProvider`, `workspaceServiceProvider`

### Dependency injection pattern
- Before: `main.dart` creates services → passes via constructor to `HomePage` → deep prop drilling
- After: `ProviderScope` in `main.dart` → all pages use `ConsumerStatefulWidget` + `ref.read()`
- Pages no longer accept service params in constructors, only callbacks and IDs

### All pages converted
- `HomePage`, `EnvPage`, `SettingsPage`, `HistoryPage`, `RequestBuilderPage`, `ProjectListPage`
- `RequestDrawer` widget, `_EnvSwitch` widget

### Workspace switching
- `main.dart` uses `ValueKey(_workspaceKey)` on `HomePage` to force full rebuild
- `_onWorkspaceChanged()` calls `projectService.syncFromFilesystem()` then increments key
- On startup, `_loadSettings()` also calls `syncFromFilesystem()` to detect manual file copies

### Key files
- `lib/domain/providers/services.dart` — service providers
- `lib/main.dart` — ProviderScope wrapper, workspace key management

### Why this matters
**Why:** Phase 2 (GitHub sync) needs shared state across pages. Riverpod enables reactive state sharing.
**How to apply:** New pages extend `ConsumerStatefulWidget`. Access services via `ref.read()`. For reactive state across widgets, create a `Notifier`.
