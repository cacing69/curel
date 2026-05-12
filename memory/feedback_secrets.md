---
name: Secrets and security patterns
description: How to handle sensitive values (webhook URLs, API keys) in client app
type: project
originSessionId: 0ec7ffc0-f04f-4052-b391-a0dc6cfa3f7a
---

## Client-side secret handling

### Webhook URL obfuscation
- Discord webhook URL in `feedback_page.dart` is obfuscated via char code arrays split into 6 parts
- `_obfuscated()` reassembles at runtime via `String.fromCharCodes([...a, ...b, ...c, ...d, ...e, ...f])`
- Not truly secure (client code is always extractable), but raises the bar against casual reverse engineering
- String like `discord.com` or `webhook` does NOT appear as plain text in compiled binary

### Future improvement options
- Backend proxy (most secure): app sends to your API, API forwards to Discord
- Runtime fetch from remote config: URL stored on server, fetched at app launch

### Reset app
- `_resetApp()` in settings clears: SharedPreferences, FlutterSecureStorage, workspace directory, Isar database files
- Calls `exit(0)` to force fresh restart
- App recreates default project on next launch via `ensureDefaultProject()`

### Why this matters
**Why:** Client apps can never truly hide secrets. Obfuscation is a practical compromise for non-critical webhooks.
**How to apply:** Never store API keys as plain string literals. Use char code splitting or similar obfuscation. For truly sensitive operations, route through a backend.
