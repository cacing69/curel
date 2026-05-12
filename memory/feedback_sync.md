---
name: Plan-memory sync enforcement
description: MANDATORY — PLAN.md and memory/*.md must be edited together in the same batch. No drift allowed.
type: feedback
originSessionId: f2561953-7a22-4f2f-853f-fb1800133f90
---
## PLAN.md ↔ memory/*.md Sync Rule

**RULE: Always edit PLAN.md and memory/product_roadmap.md TOGETHER in the same response.** Never update one without the other.

When ANY of these changes happen, BOTH files must be edited:
- Phase status changes (started, completed, blocked)
- New feature added to any phase
- Feature removed or moved between phases
- Workspace structure changes (new file format, new folder)
- Priority or ordering changes

**Why:** PLAN.md and memory/product_roadmap.md drifted apart over multiple conversations — Phase 3 was marked "(Ongoing)" with 11/12 checkbox items in PLAN.md but still showed as "(next)" with pending items in memory. This caused agents to work from stale information.

**How to apply:**
1. When editing phase content, make BOTH Edit calls in the same message (parallel tool calls)
2. After editing, verify: if you touched PLAN.md phases, did you also touch memory/product_roadmap.md? And vice versa.
3. Workspace structure in both files must match — same sidecar files listed in both
4. Phase labels must match — same title, same status tag

### Quick verification checklist (run mentally after ANY phase edit):

- [ ] PLAN.md phase section changed → memory/product_roadmap.md same section also changed?
- [ ] New sidecar file mentioned → workspace structure in BOTH files updated?
- [ ] Phase status label changed (COMPLETE/Ongoing/NEXT) → same label in both?
- [ ] New memory spec file created → SYNC.md mapping table updated?
