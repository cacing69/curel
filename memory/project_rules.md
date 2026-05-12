---
name: Project rules
description: Core project rules, conventions, dependencies, and app identity
type: feedback
originSessionId: 2af1b075-62f0-401f-be91-e2928d72dfab
---
## App Identity

Curel is a cross-platform (Android, iOS, macOS, Windows, Linux, Web) curl client built with Flutter. It impersonates and mimics the behavior of the real `curl` CLI tool, but with a UI optimized for mobile. Every feature decision should stay true to curl's behavior and flags. Fully developed with AI assistance.

## Environment Variables

- Syntax: `<<VAR>>` (no conflict with curl syntax)
- Regex: `<<([A-Za-z_][A-Za-z0-9_]*)>>`
- **Storage**: metadata in filesystem JSON files, **values** in `flutter_secure_storage` (keyed by `env_{envId}_{varKey}`)
- **Layered resolution**: global env loaded first, project env overrides on key collision
- **Global scope**: flat variable list (single auto-created "default" environment, no naming step)
- **Project scope**: named environments (dev/staging/prod) with expansion tiles, radio button switch
- Resolution happens before curl parse in `_executeCurl`
- Features: CRUD vars, duplicate env, import/export JSON, quick switch from action bar, undefined var warning toast, `<<VAR>>` syntax highlighting (purple)
- Key files: `env_model.dart`, `env_service.dart`, `env_page.dart`

## Export/Import System

3 levels of export/import with type validation:
- **Workspace** (settings page): bundles all projects + global env + project envs + requests into single JSON
- **Project** (project list page): single project + its envs + requests
- **Env** (env page): env definitions + values per scope
- Each export has `type` field (`"workspace"`, `"project"`, `"env"`) validated on import to prevent wrong file type
- `WorkspaceService` orchestrates all three levels, reuses `envService.exportToJson()`/`importFromJson()`
- Import always generates new project IDs to avoid conflicts with existing data
- Key file: `lib/domain/services/workspace_service.dart`

## Workspace Architecture

- Default path: `getApplicationSupportDirectory()/curel/` (NOT `getApplicationDocumentsDirectory` which has `app_flutter` in path)
- Custom workspace: user picks folder via file_picker, stored in SharedPreferences
- `ProjectService.syncFromFilesystem()`: scans `projects/*/curel.json` and rebuilds project list in SharedPreferences — called on startup and after workspace switch
- Workspace switch triggers `ValueKey` increment on `HomePage` → full rebuild (destroy + recreate with fresh `initState`)
- Directory structure: `{root}/projects/{id}/requests/`, `{root}/projects/{id}/environments/`, `{root}/projects/.global/environments/`

## Catat setiap perubahan

Selalu catat setiap perubahan ke NOTES.txt setiap ada changes, dalam bentuk plain text list (`- description`).

### **UI Design System**
- **Theme**: Dracula-inspired (Dark).
- **Style**: Flat Design (No shadows, no elevation, no rounded corners unless specified).
- **Radius**: All `borderRadius: BorderRadius.zero` — handled globally via `ThemeData` in `main.dart`.
- **Header Standard**: custom container at top of `Column`, `TColors.surface` bg, padding `h:12 v:8`, monospace 11 bold, back icon 18, separator `Container(height: 1, color: TColors.border)`.
- **Buttons**: `TermButton` height 28px, padding h:10px, icons 14px. Icons are mandatory for buttons (from Lucide/Material).
- **Typography**: ALWAYS `lowercase` for UI labels, titles, and messages. NO EXCEPTIONS for new UI (Maintain "terminal-native" aesthetics).
- **Iconography Standards**:
    - **Cloud/Git Sync Indicator**: `Icons.cloud` (right-aligned in project tiles).
    - **Git Provider Settings**: `Icons.schema` or `Icons.public`.
    - **Refresh/Sync Action**: `Icons.sync` (preferred over `Icons.refresh` for data sync).
- **Text Input**: curl editor uses `autocorrect: false`, `enableSuggestions: false`, `textCapitalization: TextCapitalization.none`

### **Technical Conventions**
- **Modularization**: Large screens like `HomePage` MUST be refactored into modular components (`logic/` mixins, `widgets/` sub-files) when exceeding 500 lines.
- **Fingerprinting**: `DeviceService` provides a consistent 7-char SHA hash of the device ID for Git commit logs.
- **Notification**: Use `showTerminalToast` (from `terminal_theme.dart`) for all UI notifications to maintain consistency.
- **Error Handling**: strip `Exception:`, `FormatException:` prefixes — show clean messages only.
- **Loading Indicator**: ALWAYS use `TerminalLoader` (from `terminal_theme.dart`) for all loading states — full-page, dialog, drawer. NEVER use `CircularProgressIndicator` as a replacement for full loading states. Exception: tiny inline button spinners (10–14px replacing an icon) may still use `CircularProgressIndicator` with small `strokeWidth`.

### **Git Synchronization Rules**
- **Origin Locking**: Once a project is connected to a remote URL, the URL is locked. Changing the URL requires an explicit `disconnect` action (long-press on Sync button or Project menu).
- **Signature Validation**: Use `curel.json` with `remote_origin_id` to verify repository ownership and prevent cross-project collisions.
- **Conflict Resolution**: If both local and remote have data during the first connection, the system must prompt for 'Pull & Overwrite' or 'Push & Overwrite'.
- **Safety**: Never overwrite local data without a `remote_origin_id` match or explicit user confirmation.
- **Identity**: Push commit messages follow the format: `sync from curel v{version} ({device_hash}) {timestamp}`.

## State Management

- **flutter_riverpod** — no code gen (conflicts with isar_community_generator)
- All pages: `ConsumerStatefulWidget` with `ref.read()` for services
- Service providers in `lib/domain/providers/services.dart`

## Dependencies

- State management: `flutter_riverpod`
- Storage: `shared_preferences` (active state) + `flutter_secure_storage` (env values) + `Filesystem` (projects, requests, envs)
- Database: `isar_community` (history)
- HTTP: `dio` via `CurlHttpClient`
- UUID: `uuid` for environment/project IDs
- Sharing: `share_plus`
- Image compression: `flutter_image_compress` (quality 80%, maxWidth 720 before feedback submit)
- Removed: `encrypt` (replaced by flutter_secure_storage), `riverpod_generator` (conflicts with isar)

## Memory Structure

- `memory/` di project root (gitignored) — visible copy memory
- `~/.claude/projects/.../memory/` — actual Claude memory system
- `CLAUDE.md` — auto-loaded rules, can be regenerated from memory
