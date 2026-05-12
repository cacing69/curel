---
name: Response comparison and diff
description: Response diff feature — compare responses between two URLs with mobile-friendly inline diff view, triggered from response preview tab
type: project
originSessionId: f2561953-7a22-4f2f-853f-fb1800133f90
---
## Response Comparison & Diff

Fitur untuk membandingkan response dari request yang sudah berhasil dengan response dari URL lain, menampilkan diff yang mobile-friendly dengan semua perbedaan di-highlight.

### User Flow

```
Request → Response Preview → [compare trigger] → Pilih URL → Fetch → Show Diff (highlighted)
```

1. User menjalankan request → melihat response di tab preview
2. Di response viewer ada trigger/button "compare"
3. User memasukkan URL target (atau pilih dari saved requests)
4. App mengeksekusi request ke URL target
5. Diff view muncul dengan semua perbedaan di-highlight

### Comparison Source Options

User bisa membandingkan dengan:
1. **Custom URL** — masukkan URL manual (method + headers dari request asli, URL baru)
2. **Saved request** — pilih dari request yang sudah disimpan di project
3. **History entry** — pilih dari response history yang sudah ada
4. **Same URL, different env** — bandingkan response yang sama antara env (dev vs staging vs prod)

### Diff Display Strategy (Mobile-Friendly)

Side-by-side diff terlalu cramped di mobile. Gunakan **inline diff** approach:

#### JSON Response Diff
- **Card-based field diff** — setiap field yang berbeda ditampilkan sebagai card
- Format: `field_path` → value_A vs value_B
- Color coding:
  - Green bg (`+`): field hanya ada di response B (added)
  - Red bg (`-`): field hanya ada di response A (removed)
  - Yellow/amber bg (`~`): field value berubah (changed)
  - Gray: field sama (collapsed by default, expandable)
- Nested JSON → flatten dengan dot-path notation untuk diff view
- Tap card → expand to see full context

#### Text/HTML Response Diff
- Unified diff format (simplified)
- Additions: green bg
- Deletions: red bg
- Modifications: shown as deletion + addition pair
- Swipeable untuk navigate antar changes

#### Status/Headers Diff
- Section terpisah di atas diff view:
  - Status code comparison (200 vs 404, dll)
  - Response time comparison
  - Content-length comparison
  - Headers diff (added/removed/changed headers)

### Diff Engine Architecture

```
ResponseDiffEngine
├── JsonDiffEngine           ← primary: JSON deep comparison
│   ├── flatten json → map of path → value
│   ├── compare two flattened maps
│   └── output: list of DiffEntry
├── TextDiffEngine           ← fallback: text line-by-line diff (Myers diff algorithm)
│   └── output: list of DiffLine
└── HeaderDiffEngine         ← header key-value comparison
    └── output: list of HeaderDiffEntry
```

**DiffEntry model:**
```dart
enum DiffType { added, removed, changed, unchanged }

class DiffEntry {
  final String path;          // dot-path: "data.user.name"
  final dynamic valueA;       // value from first response
  final dynamic valueB;       // value from second response
  final DiffType type;
  final List<DiffEntry>? children; // for nested objects
}
```

### UI Components

1. **CompareButton** — di response viewer header, muncul setelah successful response
2. **CompareSourceDialog** — dialog untuk pilih sumber comparison (URL, saved request, history, cross-env)
3. **DiffView** — main diff display widget
   - Summary bar: "5 added, 2 removed, 3 changed"
   - Filter chips: show all / changes only / added / removed
   - Scrollable diff content
4. **DiffCard** — single field diff display (path, values, color-coded)
5. **DiffSummary** — header section with status/time/size comparison

### Integration Points

- **Response viewer**: tab atau button di header — triggers comparison flow
- **History**: diff result bisa disimpan sebagai history metadata (optional)
- **Environment system**: cross-env comparison reuses `<<VAR>>` resolution
- **CurlHttpClient**: second request menggunakan engine yang sama (DioCurlHttpClient)
- **Query engine (Phase 5a)**: optional pre-processing — apply jq query ke kedua responses sebelum compare

### Baseline Snapshot

Selain compare dengan URL lain, ada mode **"set as baseline"**:
- Simpan response saat ini sebagai snapshot (disimpan di sidecar file `.baseline.json`)
- Future responses bisa di-compare langsung melalui baseline tanpa perlu re-fetch
- Berguna untuk regression testing — response berubah setelah deploy?
- Baseline bisa di-update kapan saja (re-save)
- Format: sama seperti response body, plus metadata (timestamp, env name)

**`.baseline.json` format:**
```json
{
  "version": 1,
  "savedAt": "2026-05-12T10:30:00Z",
  "env": "development",
  "statusCode": 200,
  "headers": { "content-type": "application/json" },
  "body": { ... }
}
```

### Field Ignore / Masking

Beberapa field selalu beda antara responses (`timestamp`, `request_id`, `uuid`, `nonce`, `etag`).
Tanpa ignore, diff akan "noisy" — terlalu banyak false positives.

**Implementation:**
- Di diff view, ada toggle "ignore volatile fields"
- Auto-detect volatile fields: regex pattern match (`timestamp`, `.*_at`, `.*_id`, `uuid`, `nonce`, `etag`, `request_id`, `trace_id`)
- Manual ignore: user bisa tap field → "ignore in diff" → saved to `.meta.json` as `compareIgnore: ["field.path"]`
- Ignored fields tetap ditampilkan tapi di-strikethrough/dimmed, bukan dihitung sebagai diff
- Pattern list bisa di-configure per-project (disimpan di `curel.json`)

### Persist Comparison Pair

Daripada setiap kali harus pilih URL, bisa save "comparison pair":
- Di `.meta.json`: `compareWith: "auth/login-prod.curl"` — relative path ke request lain
- Bisa juga: `compareWith: { "url": "https://api.prod.example.com/login" }` untuk custom URL
- Saved pair muncul sebagai quick-action di compare button (1-tap compare)
- Multiple pairs supported — array of compare targets

### Auto-compare on Env Switch

Kalau user punya request yang sama di dev vs prod env:
- Saat user switch env → re-execute request → auto-compare dengan response sebelumnya
- Toggle per-request: `autoCompareOnEnvSwitch: true` di `.meta.json`
- Diff muncul otomatis sebagai overlay/bottom sheet
- User bisa dismiss atau save diff

### Non-JSON Response Handling

Untuk response yang bukan JSON (image, binary, HTML, XML):
- **Body diff**: skip (tidak meaningful)
- **Metadata diff**: fokus ke status code, headers, content-length, content-type
- **Image**: show both images sebagai toggle/tabs, plus metadata diff
- **HTML**: text diff dengan simplified line-by-line comparison
- **XML**: bisa di-parse sebagai tree atau treat sebagai text diff
- **Binary**: hanya metadata diff (size, type, status)

### Phasing within Phase 5a

**Part 1 — Core Diff Engine + JSON Diff (ACTIVE):**
1. `ResponseDiffEngine` abstract + `JsonDiffEngine`
2. `DiffEntry` model + serialization
3. `DiffView` widget with inline card-based diff
4. Compare button in response viewer
5. CompareSourceDialog (URL input mode)
6. Field ignore / masking — auto-detect volatile fields + manual ignore per-request

**Part 2 — Extended Sources + Text Diff (after Part 1):**
7. `TextDiffEngine` (Myers algorithm)
8. Saved request as comparison source
9. History entry as comparison source
10. Cross-env comparison
11. Persist comparison pair in `.meta.json` (quick-action 1-tap compare)
12. Baseline snapshot — `.baseline.json` sidecar, "set as baseline" mode

**Part 3 — Polish + Advanced (after Part 2):**
13. Filter chips (show all / changes only / added / removed)
14. Diff summary (status, timing, size)
15. Non-JSON response handling (image toggle, HTML text diff, binary metadata-only)
16. Auto-compare on env switch (toggle per-request)
17. Save diff result to history
18. Share diff output

### Why Phase 5a

- Response comparison adalah response viewer enhancement, sama seperti response query
- Query engine bisa di-reuse untuk pre-process responses sebelum compare (e.g., extract `.data` dulu baru compare)
- Phase 3 diff viewer adalah untuk git file sync — berbeda konteks tapi bisa share diff rendering component nanti
- User flow: query → compare adalah natural progression dalam response analysis workflow

**Why:** API developers sering perlu compare responses antara staging vs production, atau sebelum/sesudah code change. Mobile-friendly inline diff lebih usable daripada side-by-side di mobile screen. Card-based approach memungkinkan tap-to-expand untuk detail tanpa overwhelming.
**How to apply:** Diff engine harus pure Dart, testable, dengan clean input (two JSON maps) dan output (List<DiffEntry>). UI harus reusable — bisa dipakai untuk git file diff nanti (Phase 3 diff viewer bisa reuse DiffView widget). Prioritaskan JSON diff karena mayoritas API response adalah JSON.
