---
name: HTTP execution architecture
description: How Curel executes HTTP requests, Dio limitations, HTTP/3 strategy, curl parser quirks
type: project
---

## HTTP Execution Model

Curel does NOT call the real `curl` binary. It parses curl command syntax then sends requests via **Dio** (Dart HTTP client using `dart:io` HttpClient).

### Current capabilities
- HTTP/1.1 — fully supported (Dio native)
- HTTP/2 — NOT supported (Dart HttpClient limitation)
- HTTP/3 (QUIC) — NOT supported (Dart VM has no QUIC stack)

### Verbose output behavior
- Verbose log is manually generated, not from real curl — lines like `> GET /path HTTP/1.1` are hardcoded
- `--http3`, `--http2`, `--http1.1` flags are stripped by parser but extracted as `httpVersion` in `ParsedCurl`
- When unsupported version is requested, verbose shows honest warning: `* warning: --http3 requested but not supported, using HTTP/1.1`

### Architecture (strategy pattern — ready for HTTP/3)
```
CurlHttpClient (abstract)          ← contract
├── DioCurlHttpClient              ← current: HTTP/1.1 via Dio
├── CronetCurlHttpClient           ← future: HTTP/3 via Chromium Cronet
└── ProcessCurlHttpClient          ← future: call real curl binary
```

### HTTP/3 options for Dart/Flutter
| Option | Maturity | Portability | Notes |
|--------|----------|-------------|-------|
| `cronet` package | mature | Android only | Chromium network stack |
| `http3` package | experimental | cross-platform | Pure Dart QUIC |
| Process-based (`curl` binary) | production | Desktop only | macOS/Linux/Windows |
| Wait for `dart:io` native QUIC | unknown | cross-platform | No timeline |

### curl_parser package quirks
- `curl_parser` package (v0.1.2) has limitations:
  - `split('=')` on form data breaks JSON values → throws Exception
  - URL assertion requires `http://` or `https://` scheme
  - No support for complex `-F` values
- Our `_stripUnsupportedFlags()` strips flags curl_parser can't handle
- `_ensureScheme()` auto-adds `http://` to bare hostnames (matches real curl behavior)
- Form data (`-F`) not yet fully supported — crashes on complex values, Dio doesn't use `curl.formData`

### Error formatting
- `_formatError()` strips `Exception:`, `FormatException:` prefixes from error messages
- Shows clean messages like `error: curlString doesn't start with 'curl '` instead of `error: Exception: curlString...`

### Key files
- `lib/data/services/curl_http_client.dart` — abstract contract + Dio implementation
- `lib/domain/services/curl_parser_service.dart` — parses curl, extracts httpVersion flag, ensures URL scheme
- `lib/data/models/curl_response.dart` — response model with verbose/trace formatting

### Why this matters
**Why:** Any feature that depends on real curl behavior (HTTP/3, HTTP/2, certain flags) needs awareness of this limitation. Future HTTP/3 support should follow the strategy pattern.
**How to apply:** When adding curl flags, check if Dio can actually support the behavior. If not, extract the flag and add honest verbose/trace warnings. Do not pretend to support what the engine cannot do.