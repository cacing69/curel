Untuk kebutuhan curel, kita perlu line-by-line diff (bukan character-level) untuk membandingkan isi file .curl atau .meta.json antara lokal vs remote. diff_match_patch support diff_lineMode yang lebih efisien untuk text panjang. Package diff lebih simple tapi cukup untuk side-by-side viewer.
─────────────────────────────────────────────────

Rekomendasi: diff_match_patch — karena kita butuh bukan hanya diff viewer, tapi juga kemampuan patch (apply changes) untuk incremental sync nanti. Satu package untuk dua kebutuhan Phase 3.
