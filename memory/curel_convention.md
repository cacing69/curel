# Curel Data Convention (v1)

This document defines the formalized specification for Curel's filesystem structure and data format. This is the "Ground Truth" for anyone building importers/exporters (adapters) for Curel.

## 1. Directory Structure

A Curel workspace is a directory containing projects. Each project is a self-contained folder.

```
{project-id}/
  curel.json              # Project metadata
  environments/
    {env-name}.json       # Environment variables (metadata only)
  requests/
    {folder}/
      {request-name}.curl      # Raw curl command
      {request-name}.meta.json # Request metadata (headers, settings)
```

## 2. File Specifications

### 2.1 `curel.json` (Project Metadata)
Essential fields for identifying a project.
- `id`: Unique identifier (UUID recommended).
- `name`: Human-readable name.
- `remote_origin_id`: (Optional) For git synchronization.

### 2.2 `.curl` files
Raw text files containing the `curl` command. Curel parses these using a custom parser that supports environment variables in `<<VAR>>` syntax.

### 2.3 `.meta.json` files
Accompanying metadata for each `.curl` file.
- `id`: Unique identifier.
- `name`: Display name.
- `method`: HTTP method.
- `url`: Target URL.

### 2.4 Environment JSON
- `id`: Unique identifier.
- `name`: Environment name (e.g., "Production").
- `variables`: List of `{ "key": "...", "sensitive": true/false }`.
*Note: Values are NOT stored in these files for security. They are stored in the device's secure storage.*

## 3. Implementation via CollectionAdapter

To contribute a new format (e.g., Postman), implement the `CollectionAdapter` interface:

1. **Detection**: `canHandle(content)` should reliably identify the format.
2. **Conversion**: Map the external JSON/YAML into the `ImportedCollection` object.
3. **Paths**: Ensure nested folders in the source format are mapped to the `path` field in `ImportedRequest` (e.g., `"Auth/Login"`).

---
*Status: Draft — Version 1.0.0*
