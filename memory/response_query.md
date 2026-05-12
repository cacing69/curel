---
name: Response query and transformation
description: JSON response query/transformation feature — extract, reshape, and chain response data. Stored as sidecar files, integrates with env system.
type: project
originSessionId: 02e30dfc-0db1-4dd3-b96f-395082eb5227
---
## Response Query & Transformation

Fitur untuk query dan transform JSON response agar bisa di-extract, di-reshape, dan di-chain ke request berikutnya.

### Query Convention

**Decision: jq-like syntax (subset) — confirmed 2026-05-12**
- jq dipilih karena paling powerful — pipelining, recursion, composability sulit ditandingi alternatif (JS expression, JSONPath, dot-path, GraphQL-like)
- Developer curl-oriented sudah familiar dengan jq
- Tidak perlu implement full jq — cukup subset yang cover 80% use case
- Alternatif yang sudah dipertimbangkan dan ditolak: JS expression (less powerful), JSONPath (less readable), dot-path simplified (terlalu terbatas), GraphQL-like (butuh custom parser)

**Query capabilities yang dibutuhkan (jq subset):**
1. **Path extraction** — `.data.user.name`, `.items[0].id`
2. **Array operations** — `.items[] | .name`, `.items | length`
3. **Object construction** — `{name: .user.name, email: .user.email}`
4. **Filtering** — `.items[] | select(.active == true)`
5. **String operations** — `.token | split(".") | .[0]`
6. **Variable binding** — extract value → bind to env var

### File Storage (filesystem-first)

Sidecar file per request, mengikuti pattern `.curl` + `.meta.json` yang sudah ada:

```
requests/
  login.curl              # curl command
  login.meta.json         # request metadata
  login.query.json        # query/transformation definitions ← NEW
  auth/
    login.query.json      # subfolder support (sama seperti .curl)
```

**Format `*.query.json`:**
```json
{
  "version": 1,
  "queries": [
    {
      "id": "extract_token",
      "expression": ".data.access_token",
      "target": "env:ACCESS_TOKEN",
      "enabled": true
    },
    {
      "id": "user_info",
      "expression": "{name: .data.user.name, role: .data.user.role}",
      "target": "display",
      "enabled": true
    }
  ]
}
```

### Target Types
- `env:VAR_NAME` — write extracted value to environment variable
- `display` — show transformed result in response viewer (tab baru: "transformed")
- `clipboard` — copy to clipboard
- `chain:REQUEST_PATH` — pass value to next request (Phase 5b scripting prerequisite)

### Query Engine Architecture

```
ResponseQueryEngine (abstract)
├── JqQueryEngine          ← subset of jq, primary engine
├── JsonPathEngine         ← JSONPath fallback, simpler
└── Future: Custom DSL     ← if needed
```

**Implementation notes:**
- Parse query expression → apply to JSON response → return result
- Jq subset: path access, array iteration, select/filter, pipe, object construction
- Error handling: invalid expression → show clear error, highlight syntax issue
- Validation: test query against current response before saving

### UI Integration

1. **Response viewer** — tab baru "query" di sebelah "body" / "headers" / "verbose"
2. **Query editor** — text field dengan syntax highlighting untuk jq expression
3. **Query result panel** — preview hasil query secara live
4. **Save query** — simpan ke `.query.json` sidecar file
5. **Manage queries** — list saved queries per request, enable/disable toggle

### Integration Points
- **Env system**: `target: "env:VAR_NAME"` writes to current environment (reuses `<<VAR>>` syntax)
- **Response viewer**: tab baru menampilkan transformed output
- **History**: query result juga disimpan di history entry (optional)
- **Git sync**: `.query.json` files ikut di-sync karena plain JSON text files

### Phasing

**Phase 5a — Response Query (precursor to scripting):**
1. Core query engine (jq subset parser)
2. `.query.json` sidecar file format + CRUD
3. Query tab in response viewer + live preview
4. Env variable binding (`target: env:VAR_NAME`)

**Phase 5b — Advanced Transform (after 5a):**
5. Object construction + array filtering
6. Chain target (pass to next request)
7. Multi-query execution order
8. Import/export query definitions

**Why:** Response query adalah fitur yang paling sering diminta di API client (extract token, get specific field). Ini juga jadi fondasi untuk Phase 5b scripting — query engine bisa di-reuse sebagai expression evaluator di pre/post-request scripts. Filesystem-first approach memastikan queries ikut ter-sync via git dan bisa di-review di version control.
**How to apply:** Query engine harus separate package atau clean abstract class agar bisa di-extend ke scripting engine nanti. `.query.json` format harus backward-compatible (version field untuk migration).
