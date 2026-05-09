import 'package:curl_parser/curl_parser.dart';

/// Strips unsupported curl flags/arguments from [input] so that
/// curl_parser's ArgParser won't throw FormatException.
///
/// We take a token-based approach: split into shell-style tokens,
/// remove the ones we don't support, then rejoin.
/// Quotes are preserved so that `shlex.split` inside curl_parser
/// can re-parse the rejoined string correctly.
String _stripUnsupportedFlags(String input) {
  final tokens = _tokenize(input);
  final result = <String>[];

  // Short flags we silently strip (no value after them)
  const stripShort = {'s', 'S', 'v', 'L', 'O', 'k'};
  // Long flags we silently strip (no value after them)
  const stripLong = {
    'silent',
    'show-error',
    'verbose',
    'compressed',
    'globoff',
    'fail',
    'fail-early',
    'progress-bar',
    'path-as-is',
    'location',
    'remote-name',
    'insecure',
    'http2',
    'http2-prior-knowledge',
    'http1.0',
    'http1.1',
    'http3',
    'http3-only',
  };
  // Flags that consume the next token as their value
  const stripWithValueShort = {'o', 'w', 'm'};
  const stripWithValueLong = {
    'output',
    'write-out',
    'trace',
    'trace-ascii',
    'connect-timeout',
    'max-time',
    'retry',
    'retry-delay',
  };

  int i = 0;
  while (i < tokens.length) {
    final tok = tokens[i];

    // --long-flag  or --long-flag=value
    if (tok.startsWith('--')) {
      var body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;

      // Normalize --data-raw → --data (same semantics, just no @-file)
      if (name == 'data-raw') {
        if (eq >= 0) {
          result.add('--data=${body.substring(eq + 1)}');
        } else {
          result.add('--data');
        }
        i++;
        continue;
      }

      if (stripLong.contains(name)) {
        i++;
        continue;
      }
      if (stripWithValueLong.contains(name)) {
        // --flag=value consumes 1 token; --flag value consumes 2
        // But skip consuming the value if it looks like a URL
        if (eq < 0 && i + 1 < tokens.length) {
          final next = _unquote(tokens[i + 1]);
          if (!_isUrlLike(next) && !_isFlagLike(next)) {
            i++;
          }
        }
        i++;
        continue;
      }
    }

    // -X  (single short flag)
    if (tok.length == 2 && tok.startsWith('-') && !tok.startsWith('--')) {
      final ch = tok[1];
      if (stripShort.contains(ch)) {
        i++;
        continue;
      }
      if (stripWithValueShort.contains(ch)) {
        if (i + 1 < tokens.length) {
          final next = _unquote(tokens[i + 1]);
          if (!_isUrlLike(next) && !_isFlagLike(next)) {
            i++;
          }
        }
        i++;
        continue;
      }
    }

    // Combined short flags like -sS, -sSv, etc.
    if (tok.length > 2 && tok.startsWith('-') && !tok.startsWith('--')) {
      final letters = tok.substring(1);
      final allStrippable =
          letters.split('').every((c) => stripShort.contains(c));
      if (allStrippable) {
        i++;
        continue;
      }
      // If some letters are strippable and some aren't, keep only the
      // supported ones so that -sSX becomes -X.
      final kept = letters
          .split('')
          .where((c) => !stripShort.contains(c))
          .join();
      if (kept.isEmpty) {
        i++;
        continue;
      }
      result.add('-$kept');
      i++;
      continue;
    }

    result.add(tok);
    i++;
  }

  return result.join(' ');
}

/// Checks if a string looks like a URL (starts with http:// or https://).
bool _isUrlLike(String s) {
  final lower = s.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

/// Checks if a string looks like a flag (starts with -).
bool _isFlagLike(String s) {
  return s.startsWith('-');
}

/// Shell-style tokenizer that respects single/double quotes and
/// backslash line-continuations.
///
/// Unlike a typical tokenizer, this one **preserves** quotes so that
/// the rejoined string can be fed back into `shlex.split`.
List<String> _tokenize(String input) {
  final tokens = <String>[];
  final buf = StringBuffer();
  int i = 0;

  void pushToken() {
    if (buf.isNotEmpty) {
      tokens.add(buf.toString());
      buf.clear();
    }
  }

  while (i < input.length) {
    final ch = input[i];

    if (ch == "'") {
      buf.write("'");
      i++;
      while (i < input.length && input[i] != "'") {
        buf.write(input[i]);
        i++;
      }
      if (i < input.length) {
        buf.write("'");
        i++;
      }
      continue;
    }

    if (ch == '"') {
      buf.write('"');
      i++;
      while (i < input.length && input[i] != '"') {
        buf.write(input[i]);
        i++;
      }
      if (i < input.length) {
        buf.write('"');
        i++;
      }
      continue;
    }

    if (ch == '\\') {
      i++;
      if (i < input.length && input[i] != '\n') {
        buf.write('\\');
        buf.write(input[i]);
      }
      i++;
      continue;
    }

    if (ch == ' ' || ch == '\t' || ch == '\n') {
      pushToken();
      i++;
      continue;
    }

    buf.write(ch);
    i++;
  }

  pushToken();
  return tokens;
}

/// Result of parsing a curl command, including any output filename
/// extracted from the `-o` / `--output` flag.
class ParsedCurl {
  final Curl curl;
  final String? outputFileName;
  final bool verbose;
  final bool followRedirects;
  final String? traceFileName;
  final bool traceAscii;
  final bool traceEnabled;
  final Duration? connectTimeout;
  final Duration? maxTime;
  final bool insecure;
  final String? httpVersion;

  const ParsedCurl({
    required this.curl,
    this.outputFileName,
    this.verbose = false,
    this.followRedirects = false,
    this.traceFileName,
    this.traceAscii = false,
    this.traceEnabled = false,
    this.connectTimeout,
    this.maxTime,
    this.insecure = false,
    this.httpVersion,
  });
}

/// Extracts the trace filename from `--trace` or `--trace-ascii` flag in [input].
/// Returns null if the next token looks like a URL or a flag.
String? _extractTraceFile(String input) {
  final tokens = _tokenize(input);
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok == '--trace' && i + 1 < tokens.length) {
      final value = _unquote(tokens[i + 1]);
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      return value;
    }
    if (tok.startsWith('--trace=')) {
      final value = _unquote(tok.substring(8));
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      return value;
    }
    if (tok == '--trace-ascii' && i + 1 < tokens.length) {
      final value = _unquote(tokens[i + 1]);
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      return value;
    }
    if (tok.startsWith('--trace-ascii=')) {
      final value = _unquote(tok.substring(14));
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      return value;
    }
  }
  return null;
}

/// Extracts the output filename from `-o` / `--output` flags in [input].
String? _extractOutputFile(String input) {
  final tokens = _tokenize(input);
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok.startsWith('--')) {
      final body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;
      if (name == 'output') {
        if (eq >= 0) return _unquote(body.substring(eq + 1));
        if (i + 1 < tokens.length) return _unquote(tokens[i + 1]);
      }
    }
    if (tok == '-o' && i + 1 < tokens.length) {
      return _unquote(tokens[i + 1]);
    }
    // Handle combined flags like -vo file
    if (tok.length > 2 && tok.startsWith('-') && !tok.startsWith('--')) {
      final letters = tok.substring(1);
      final oIndex = letters.indexOf('o');
      if (oIndex >= 0 && oIndex == letters.length - 1 && i + 1 < tokens.length) {
        return _unquote(tokens[i + 1]);
      }
    }
  }
  return null;
}

String _unquote(String s) {
  if ((s.startsWith("'") && s.endsWith("'")) ||
      (s.startsWith('"') && s.endsWith('"'))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

/// Checks if the input contains `--verbose` or `-v` flag.
bool _hasVerbose(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--verbose') return true;
    if (tok.startsWith('-') && !tok.startsWith('--')) {
      if (tok.contains('v')) return true;
    }
  }
  return false;
}

/// Extracts timeout in seconds from `--connect-timeout` or `--max-time`.
Duration? _extractSeconds(String input, String flagName, [String? shortFlag]) {
  final tokens = _tokenize(input);
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok == '--$flagName' && i + 1 < tokens.length) {
      final value = _unquote(tokens[i + 1]);
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      final seconds = double.tryParse(value);
      if (seconds == null) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    }
    if (tok.startsWith('--$flagName=')) {
      final value = _unquote(tok.substring(flagName.length + 3));
      final seconds = double.tryParse(value);
      if (seconds == null) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    }
    if (shortFlag != null && tok == '-$shortFlag' && i + 1 < tokens.length) {
      final value = _unquote(tokens[i + 1]);
      if (_isUrlLike(value) || _isFlagLike(value)) return null;
      final seconds = double.tryParse(value);
      if (seconds == null) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    }
  }
  return null;
}

/// Checks if the input contains `-k` or `--insecure` flag.
bool _hasInsecure(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--insecure') return true;
    if (tok.startsWith('-') && !tok.startsWith('--')) {
      if (tok.contains('k')) return true;
    }
  }
  return false;
}

/// Checks if the input contains `-O` or `--remote-name` flag.
bool _hasRemoteName(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--remote-name') return true;
    if (tok.startsWith('-') && !tok.startsWith('--') && tok.length == 2) {
      if (tok[1] == 'O') return true;
    }
  }
  return false;
}

/// Extracts filename from URL path for `-O` / `--remote-name`.
String? _remoteNameFromUrl(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    final unquoted = _unquote(tok);
    if (_isUrlLike(unquoted)) {
      final path = Uri.tryParse(unquoted)?.pathSegments;
      if (path != null && path.isNotEmpty) return path.last;
    }
  }
  return null;
}

/// Checks if the input contains `--location` or `-L` flag.
bool _hasLocation(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--location') return true;
    if (tok.startsWith('-') && !tok.startsWith('--')) {
      if (tok.contains('L')) return true;
    }
  }
  return false;
}

/// Checks if the input contains `--trace-ascii` flag.
bool _hasTraceAscii(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--trace-ascii') return true;
    if (tok.startsWith('--trace-ascii=')) return true;
  }
  return false;
}

/// Checks if the input contains `--trace` or `--trace-ascii` flag.
bool _hasTraceFlag(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--trace' || tok.startsWith('--trace=')) return true;
    if (tok == '--trace-ascii' || tok.startsWith('--trace-ascii=')) return true;
  }
  return false;
}

/// Detects HTTP version flags from curl input.
/// Returns '3', '3-only', '2', '2-prior-knowledge', '1.1', '1.0', or null.
String? _extractHttpVersion(String input) {
  final tokens = _tokenize(input);
  for (final tok in tokens) {
    if (tok == '--http3-only') return '3-only';
    if (tok == '--http3') return '3';
    if (tok == '--http2-prior-knowledge') return '2-prior-knowledge';
    if (tok == '--http2') return '2';
    if (tok == '--http1.1') return '1.1';
    if (tok == '--http1.0') return '1.0';
  }
  return null;
}

/// Pre-processes a curl command string to strip unsupported flags,
/// then parses it into a [ParsedCurl] object with optional output filename.
ParsedCurl parseCurl(String input) {
  var outputFile = _extractOutputFile(input);
  final verbose = _hasVerbose(input);
  final followRedirects = _hasLocation(input);
  final traceFile = _extractTraceFile(input);
  final traceAscii = _hasTraceAscii(input);
  final traceEnabled = _hasTraceFlag(input);
  final connectTimeout = _extractSeconds(input, 'connect-timeout');
  final maxTime = _extractSeconds(input, 'max-time');
  final insecure = _hasInsecure(input);
  final httpVersion = _extractHttpVersion(input);
  if (outputFile == null && _hasRemoteName(input)) {
    outputFile = _remoteNameFromUrl(input);
  }

  // Extract headers manually to avoid curl_parser's buggy split on `://`
  final rawHeaders = _extractHeaders(input);
  // Strip -H/--header from input before passing to curl_parser
  final cleaned = _stripHeaders(_stripUnsupportedFlags(input));

  try {
    final curl = Curl.parse(cleaned);
    return ParsedCurl(
      curl: _curlWithHeaders(curl, rawHeaders),
      outputFileName: outputFile,
      verbose: verbose,
      followRedirects: followRedirects,
      traceFileName: traceFile,
      traceAscii: traceAscii,
      traceEnabled: traceEnabled,
      connectTimeout: connectTimeout,
      maxTime: maxTime,
      insecure: insecure,
      httpVersion: httpVersion,
    );
  } on FormatException {
    final curl = Curl.parse(_stripAllUnknownFlags(cleaned));
    return ParsedCurl(
      curl: _curlWithHeaders(curl, rawHeaders),
      outputFileName: outputFile,
      verbose: verbose,
      followRedirects: followRedirects,
      traceFileName: traceFile,
      traceAscii: traceAscii,
      traceEnabled: traceEnabled,
      connectTimeout: connectTimeout,
      maxTime: maxTime,
      insecure: insecure,
      httpVersion: httpVersion,
    );
  }
}

/// Extracts -H/--header values from raw input, correctly handling values with `://`.
Map<String, String> _extractHeaders(String input) {
  final tokens = _tokenize(input);
  final headers = <String, String>{};
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    String? headerValue;
    if (tok == '-H' && i + 1 < tokens.length) {
      headerValue = _unquote(tokens[i + 1]);
    } else if (tok.startsWith('--header=')) {
      headerValue = _unquote(tok.substring(9));
    } else if (tok == '--header' && i + 1 < tokens.length) {
      headerValue = _unquote(tokens[i + 1]);
    }
    if (headerValue != null) {
      final colonIndex = headerValue.indexOf(':');
      if (colonIndex > 0) {
        final name = headerValue.substring(0, colonIndex).trim();
        final value = headerValue.substring(colonIndex + 1).trim();
        headers[name] = value;
      }
    }
  }
  return headers;
}

Curl _curlWithHeaders(Curl curl, Map<String, String> headers) {
  return Curl(
    method: curl.method,
    uri: curl.uri,
    headers: headers.isEmpty ? null : headers,
    data: curl.data,
    cookie: curl.cookie,
    user: curl.user,
    referer: curl.referer,
    userAgent: curl.userAgent,
    form: curl.form,
    formData: curl.formData,
    insecure: curl.insecure,
    location: curl.location,
  );
}

/// Strips all -H/--header flags from input so curl_parser doesn't try to parse them.
String _stripHeaders(String input) {
  final tokens = _tokenize(input);
  final result = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok == '-H' || tok == '--header') {
      i++; // skip value
      continue;
    }
    if (tok.startsWith('--header=')) {
      continue;
    }
    result.add(tok);
  }
  return result.join(' ');
}

/// Aggressive fallback: only keep tokens that curl_parser natively supports.
/// This ensures any unknown flag is stripped rather than causing a crash.
String _stripAllUnknownFlags(String input) {
  const supportedLong = {
    'url', 'request', 'header', 'data', 'cookie', 'user',
    'referer', 'user-agent', 'head', 'form', 'insecure', 'location',
  };
  const supportedShort = {'X', 'H', 'd', 'b', 'u', 'e', 'A', 'I', 'F', 'k', 'L'};
  const valueFlags = {'X', 'H', 'd', 'b', 'u', 'e', 'A', 'F'};
  const valueFlagsLong = {
    'request', 'header', 'data', 'cookie', 'user', 'referer', 'user-agent', 'form',
  };

  final tokens = _tokenize(input);
  final result = <String>[];

  int i = 0;
  while (i < tokens.length) {
    final tok = tokens[i];

    if (tok.startsWith('--')) {
      final body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;
      if (!supportedLong.contains(name)) {
        // Skip value token if this flag takes one and it's not --flag=value form
        if (valueFlagsLong.contains(name) && eq < 0 && i + 1 < tokens.length) {
          final next = _unquote(tokens[i + 1]);
          if (!_isUrlLike(next) && !_isFlagLike(next)) i++;
        }
        i++;
        continue;
      }
      result.add(tok);
      i++;
      continue;
    }

    if (tok.length == 2 && tok.startsWith('-')) {
      final ch = tok[1];
      if (!supportedShort.contains(ch)) {
        if (valueFlags.contains(ch) && i + 1 < tokens.length) {
          final next = _unquote(tokens[i + 1]);
          if (!_isUrlLike(next) && !_isFlagLike(next)) i++;
        }
        i++;
        continue;
      }
      result.add(tok);
      i++;
      continue;
    }

    // Combined short flags like -sSvL
    if (tok.length > 2 && tok.startsWith('-') && !tok.startsWith('--')) {
      final kept = tok.substring(1).split('').where((c) => supportedShort.contains(c)).join();
      if (kept.isEmpty) { i++; continue; }
      result.add('-$kept');
      i++;
      continue;
    }

    result.add(tok);
    i++;
  }

  return result.join(' ');
}
