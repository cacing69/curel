# CURL vs DIO

| Fitur | Native curl (libcurl) | Dio | Keterangan |
|-------|:---:|:---:|-----|
| HTTP methods (GET/POST/PUT...) | ✅ | ✅ | |
| Custom headers | ✅ | ✅ | |
| Request body | ✅ | ✅ | |
| Follow redirects | ✅ | ✅ | |
| Connect / read timeout | ✅ | ✅ | |
| Insecure TLS (skip verify) | ✅ | ✅ | |
| **Verbose (`-v`)** | ✅ SSL + headers | ⚠️ headers only | Dio tidak capture SSL handshake |
| **Trace (`--trace`)** | ✅ hex dump raw bytes | ❌ | Dio data sudah terdekripsi |
| **HTTP/2, HTTP/3** | ✅ native | ❌ | Dio hanya HTTP/1.1 |
| Client certificate (`--cert`) | ✅ | ⚠️ perlu SecurityContext manual | |
| SOCKS proxy | ✅ | ❌ | |
| DNS override (`--resolve`) | ✅ | ❌ | |
| Rate limiting (`--limit-rate`) | ✅ | ❌ | |
| Resume download (`-C`) | ✅ | ❌ | |
| Cookie engine | ✅ | ⚠️ punya sendiri (CookieJarService) | |
| **Async (tidak blocking)** | ❌ FFI blocks main thread | ✅ | Animasi loading tetap jalan |
| **Cross-platform** | ⚠️ Android only | ✅ Android + iOS + desktop | |
| Auto-switch tab verbose | ✅ | ✅ | |
| Auto-switch tab trace | ✅ | ❌ trace selalu kosong | |