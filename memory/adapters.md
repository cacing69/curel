# Curel — Collection Adapter System

## Overview

Pluginable import/export engine for collection formats. Each format is an adapter that implements one interface.

---

## CollectionAdapter Interface

`lib/domain/adapters/collection_adapter.dart`

```dart
abstract class CollectionAdapter {
  String get id;       // unique identifier, e.g. 'postman_v2'
  String get name;     // display name, e.g. 'Postman'
  String get icon;     // Material Icons name

  bool canHandle(String content);               // auto-detection
  Future<ImportedCollection> convert(String content);  // import: external → curel
  Future<String> export(ExportedProject project);      // export: curel → external (JSON string)
}
```

---

## Curel Data Convention (ImportedCollection / ExportedProject)

These are the "pivot" data structures. All adapters convert to/from these.

### Import side
```dart
ImportedCollection {
  String name
  String? description
  List<ImportedEnv> environments   // each env has name + List<EnvVariable>
  List<ImportedRequest> requests   // each request has path + curlContent + meta
}

ImportedRequest {
  String path           // relative path incl. folders, e.g. 'auth/login'
  String curlContent    // raw curl command
  RequestMeta? meta     // displayName, etc.
}
```

### Export side
```dart
ExportedProject {
  String name
  String? description
  List<ExportedEnv> environments
  List<ExportedRequest> requests
}

ExportedRequest {
  String displayName    // human-readable name
  String folderPath     // folder hierarchy, e.g. 'auth' or 'api/v2'
  String curlContent    // raw curl command
}
```

---

## AdapterRegistry

`lib/domain/adapters/adapter_registry.dart`

```dart
class AdapterRegistry {
  CollectionAdapter? findAdapter(String content)   // auto-detect by canHandle()
  CollectionAdapter? findById(String id)           // explicit lookup
  List<CollectionAdapter> get availableAdapters    // all registered adapters
}

final adapterRegistryProvider = Provider((ref) => AdapterRegistry());
```

### Registered Adapters (in order)
1. `CurelNativeAdapter` — id: `'curel_native'`
2. `PostmanAdapter` — id: `'postman_v2'`
3. `InsomniaAdapter` — id: `'insomnia_v4'`
4. `HoppscotchAdapter` — id: `'hoppscotch_v1'`

---

## Adapter Details

### CurelNativeAdapter
- **Import**: Reads `type: 'project'` JSON with `project`, `environments`, `requests` keys.
- **Export**: Writes same structure. `requests[].path` is sanitized (spaces → `_`).
- **canHandle**: `data['type'] == 'project'` OR (`data['project'] != null && data['requests'] != null`)

### PostmanAdapter
- **Import**: Handles Postman Collection v2 & v2.1. Flattens folder tree. Converts `{{var}}` → `<<var>>`. Supports all body modes: `raw`, `urlencoded`, `formdata`, `graphql`.
- **Export**: Rebuilds Postman folder tree from `folderPath`. Converts `<<var>>` → `{{var}}`. Generates `url` object with parsed URI components.
- **canHandle**: Looks for `info.schema` containing `getpostman.com` or `postman.com`.

### InsomniaAdapter
- **Import**: Reads Insomnia v4 export (`_type: 'export'`). Processes `request` resources (skips `request_group`, `workspace`). Reads `environment` resources.
- **Export**: Generates full Insomnia v4 structure with `workspace`, `environment`, `request_group` (from `folderPath`), and `request` resources. Assigns sequential `_id`s.
- **canHandle**: `data['_type'] == 'export'` AND `data.containsKey('resources')`.

### HoppscotchAdapter
- **Import**: Reads `_type: 'collection'` with `items` array. Supports nested `folder` types. Reads `environment.variables`.
- **Export**: Builds items tree with `folder` nodes. Only exports first environment.
- **canHandle**: `data['_type'] == 'collection'` AND `data.containsKey('name')`.

---

## Variable Conversion

Curel uses `<<VAR_NAME>>` syntax. Other tools use `{{VAR_NAME}}`.

| Direction | Transformation |
|---|---|
| Import (any → curel) | `{{VAR}}` → `<<VAR>>` |
| Export (curel → any) | `<<VAR>>` → `{{VAR}}` |

Each adapter handles its own conversion in `_convertVars()` / `_toPostmanVar()` / `_toExternalVar()`.

---

## WorkspaceService Integration

`lib/domain/services/workspace_service.dart`

```
exportProjectAs(projectId, adapterId)
  → _buildExportedEnvs()    reads all envs from EnvService
  → _buildExportedRequests() reads all .curl files from RequestService
  → adapter.export(ExportedProject)
  → returns JSON string

importProject(json)
  → adapterRegistry.findAdapter(json)    auto-detect format
  → adapter.convert(json)               → ImportedCollection
  → _saveImportedCollection()           creates project + envs + requests on disk
```

---

## Adding a New Adapter

1. Create `lib/domain/adapters/my_adapter.dart` implementing `CollectionAdapter`
2. Register in `AdapterRegistry._register()` constructor
3. Add icon/extension mapping in `project_list_page.dart` (`_iconFor`, `_extFor`)
4. That's it — import auto-detection and export menu update automatically
