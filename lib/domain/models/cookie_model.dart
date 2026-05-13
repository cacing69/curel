class CookieEntry {
  final String name;
  final String value;
  final String? domain;
  final String? path;
  final bool secure;
  final bool httpOnly;
  final DateTime? expires;

  const CookieEntry({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.secure = false,
    this.httpOnly = false,
    this.expires,
  });

  CookieEntry copyWith({
    String? name,
    String? value,
    String? domain,
    String? path,
    bool? secure,
    bool? httpOnly,
    DateTime? expires,
  }) {
    return CookieEntry(
      name: name ?? this.name,
      value: value ?? this.value,
      domain: domain ?? this.domain,
      path: path ?? this.path,
      secure: secure ?? this.secure,
      httpOnly: httpOnly ?? this.httpOnly,
      expires: expires ?? this.expires,
    );
  }

  bool isExpired() {
    if (expires == null) return false;
    return DateTime.now().isAfter(expires!);
  }

  bool matches(Uri uri) {
    if (isExpired()) return false;

    final host = uri.host;
    final reqPath = uri.path.isEmpty ? '/' : uri.path;

    // Domain matching
    if (domain != null) {
      final d = domain!.toLowerCase();
      final h = host.toLowerCase();
      if (d.startsWith('.')) {
        // .example.com matches example.com and sub.example.com
        if (h != d.substring(1) && !h.endsWith(d)) return false;
      } else {
        if (h != d && !h.endsWith('.$d')) return false;
      }
    }

    // Secure flag — only send over HTTPS
    if (secure && uri.scheme != 'https') return false;

    // Path matching
    if (path != null && path!.isNotEmpty && path != '/') {
      if (!reqPath.startsWith(path!)) return false;
    }

    return true;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        if (domain != null) 'domain': domain,
        if (path != null) 'path': path,
        'secure': secure,
        'httpOnly': httpOnly,
        if (expires != null) 'expires': expires!.toIso8601String(),
      };

  factory CookieEntry.fromJson(Map<String, dynamic> json) => CookieEntry(
        name: json['name'] as String,
        value: json['value'] as String,
        domain: json['domain'] as String?,
        path: json['path'] as String?,
        secure: json['secure'] as bool? ?? false,
        httpOnly: json['httpOnly'] as bool? ?? false,
        expires: json['expires'] != null
            ? DateTime.parse(json['expires'] as String)
            : null,
      );
}

class CookieJar {
  final String name;
  final List<CookieEntry> cookies;

  const CookieJar({
    required this.name,
    this.cookies = const [],
  });

  CookieJar copyWith({String? name, List<CookieEntry>? cookies}) {
    return CookieJar(
      name: name ?? this.name,
      cookies: cookies ?? this.cookies,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'cookies': cookies.map((c) => c.toJson()).toList(),
      };

  factory CookieJar.fromJson(Map<String, dynamic> json) => CookieJar(
        name: json['name'] as String,
        cookies: (json['cookies'] as List)
            .map((c) => CookieEntry.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
