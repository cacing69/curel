# SYNC.md — Plan ↔ Memory Alignment Guide

File ini menjelaskan hubungan antara `PLAN.md` (repo root) dan `memory/*.md` (Claude memory system).
Agent yang membaca file ini akan memahami: apa yang sedang dikerjakan, dimana mencari informasi, dan bagaimana menjaga kedua sistem tetap sinkron.

## Sumber Informasi

| Sumber | Lokasi | Isi | Kapan dibaca |
|--------|--------|-----|-------------|
| `PLAN.md` | repo root | Product roadmap, phase status, workspace structure, sync philosophy | Saat mulai kerja, cek phase aktif |
| `memory/MEMORY.md` | Claude memory | Index semua memory files | SELALU — ini entry point |
| `memory/*.md` | Claude memory | Detailed specs, decisions, rationale, architecture notes | Saat task relevan dengan topik memory |

## Perbedaan Peran

**`PLAN.md`** = **APA** (what)
- Phase definitions, completion status
- Workspace structure, file format specs
- High-level feature list
- Dibaca oleh semua agent dan developer

**`memory/*.md`** = **APA + KENAPA** (what + why)
- Semua yang ada di PLAN.md, PLUS:
- Decision rationale (kenapa jq over JS expression)
- Implementation details dan architecture
- User preferences dan feedback
- Error history dan lessons learned
- Hanya dibaca oleh Claude agent

## Mapping: PLAN.md ↔ memory/*.md

Setiap section di PLAN.md punya memory file yang bisa dijadikan referensi detail:

```
PLAN.md Section          →  memory file
─────────────────────────────────────────────
Phase 1                  →  (selesai, tidak ada active memory)
Phase 2                  →  git_sync_maturity.md, riverpod_architecture.md
Phase 3                  →  project_rules.md (collection engine, import/export)
Phase 4                  →  (belum dimulai)
Phase 3 (new items)      →  phase3_expansion.md
Phase 5a                 →  response_query.md, response_compare.md
Phase 5c                 →  (HAR, SSL/TLS — moved from Phase 3)
Phase 5b                 →  response_query.md (phasing section)
Workspace Structure      →  project_rules.md (workspace architecture)
Identity                 →  git_sync_maturity.md (remote_origin_id)
Sync Philosophy          →  git_sync_maturity.md (3-layer safety)
─
Cross-cutting concerns   →  memory file
─────────────────────────────────────────────
HTTP execution           →  http_architecture.md
UI/Theme                 →  dialog_ui_pattern.md, project_rules.md (UI Design System)
State management         →  riverpod_architecture.md
Security                 →  feedback_secrets.md
Text styling             →  text_style_rules.md
Change logging           →  feedback_notes.md
```

## Sync Rules

### MANDATORY: Dual-Edit Rule

**Setiap kali phase content di-edit, PLAN.md DAN memory/product_roadmap.md HARUS di-edit dalam batch yang sama.**

Ini bukan optional — drift antara kedua file menyebabkan agent bekerja dari informasi yang salah. Lihat `memory/feedback_sync.md` untuk detail lengkap.

| Kalau kamu edit... | Juga edit... |
|---|---|
| Phase status/label di PLAN.md | Phase yang sama di memory/product_roadmap.md |
| Feature list di PLAN.md | Feature list yang sama di memory/product_roadmap.md |
| Workspace structure di PLAN.md | Workspace structure di memory/product_roadmap.md |
| memory/product_roadmap.md phases | Section yang sama di PLAN.md |
| memory spec file baru (e.g. response_compare.md) | SYNC.md mapping table |

### Kapan update PLAN.md:
- Phase status berubah (started, completed, blocked)
- Fitur baru ditambahkan ke phase manapun
- Workspace structure berubah (file format baru, folder baru)
- Decision yang mempengaruhi product direction

### Kapan update memory/*.md:
- Setiap ada decision dengan reasoning (kenapa X, bukan Y)
- Architecture deep-dive atau implementation detail
- User feedback, preference, correction
- Bug, incident, lesson learned
- Fitur spec yang lebih detail dari PLAN.md

### Kapan update KEDUANYA:
- **Phase completion** — PLAN.md checklist di-check, memory phase status di-update
- **Fitur baru masuk phase** — PLAN.md dapat entry baru, memory dapat spec file baru
- **Prioritas berubah** — PLAN.md dan MEMORY.md index di-update

### Prioritas saat konflik:
1. Kode yang berjalan saat ini (source of truth tertinggi)
2. PLAN.md (product direction)
3. memory/*.md (context dan history)

## Current State (2026-05-12)

### Phase aktif:
- **Phase 3** — ongoing, 13/16 items done (remaining: OAuth Device Flow, Bruno adapter, VS Code REST Client, cookie jar)
- **Phase 5c** — new sub-phase for tooling & interop (HAR, SSL/TLS moved from Phase 3)
- **Phase 4** — belum dimulai (libgit2 migration, next after Phase 3)
- **Phase 5a** — planned, belum dimulai (response query & transformation)

### Next priority:
1. Selesaikan Phase 3 (prioritas: OAuth Device Flow + Bruno adapter + code snippets)
2. Mulai Phase 5a — Response Query & Transformation + Response Comparison & Diff
   - Query engine: jq subset syntax
   - File format: `.query.json` sidecar per request
   - UI: tab "query" di response viewer
   - Response diff: compare responses across URLs, mobile-friendly inline diff
   - Detail lengkap: `memory/response_query.md`, `memory/response_compare.md`

### Decisions yang sudah di-lock:
- Query convention: **jq-like syntax** (dipilih 2026-05-12, alternatif ditolak: JS expression, JSONPath, dot-path, GraphQL-like)
- File storage: **sidecar files** `.query.json` (mengikuti pattern `.curl` + `.meta.json`)
- Phase 5 dipecah: **5a** (query engine) → **5b** (scripting engine, reuses query engine)

## Checklist untuk Agent Baru

Sebelum mulai bekerja, agent harus:

- [ ] Baca `memory/MEMORY.md` — pahami index dan context yang tersedia
- [ ] Baca `PLAN.md` — pahami phase aktif dan arah product
- [ ] Cek "Current State" section di file ini untuk status terbaru
- [ ] Baca memory file yang relevan dengan task yang akan dikerjakan
- [ ] Setelah selesai: update NOTES.txt, update memory jika ada decision baru, update PLAN.md jika phase status berubah
