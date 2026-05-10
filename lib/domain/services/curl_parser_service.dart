import 'package:curl_parser/curl_parser.dart';

/// Checks if a string looks like a URL (starts with http:// or https://).
bool _isUrlLike(String s) {
  final lower = s.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://') || _looksLikeHost(lower);
}

bool _looksLikeHost(String s) {
  if (s.startsWith('-') || s.startsWith("'") || s.startsWith('"')) return false;
  if (!s.contains('.')) return false;
  final match = RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?').firstMatch(s);
  return match != null && match.end == s.length;
}

List<String> _ensureScheme(List<String> tokens) {
  return tokens.map((t) {
    final unquoted = _unquote(t);
    
    // If it's the first non-flag token after 'curl', it's likely the URL
    if (_isUrlLike(unquoted) &&
        !unquoted.startsWith('http://') &&
        !unquoted.startsWith('https://')) {
      // Re-quote if it was quoted
      final prefix = t.startsWith("'") ? "'" : (t.startsWith('"') ? '"' : '');
      final suffix = t.endsWith("'") ? "'" : (t.endsWith('"') ? '"' : '');
      return '${prefix}http://$unquoted$suffix';
    }
    return t;
  }).toList();
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

String _unquote(String s) {
  if ((s.startsWith("'") && s.endsWith("'")) ||
      (s.startsWith('"') && s.endsWith('"'))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

/// Pre-processes a curl command string to strip unsupported flags,
/// then parses it into a [ParsedCurl] object with optional output filename.
ParsedCurl parseCurl(String input) {
  final tokens = _tokenize(input);

  String? outputFile;
  var verbose = false;
  var followRedirects = false;
  String? traceFile;
  var traceAscii = false;
  var traceEnabled = false;
  Duration? connectTimeout;
  Duration? maxTime;
  var insecure = false;
  String? httpVersion;
  var remoteName = false;
  String? remoteNameFromUrl;
  final rawHeaders = <String, String>{};

  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];

    if (tok == '--verbose') verbose = true;
    if (tok == '--location') followRedirects = true;
    if (tok == '--insecure') insecure = true;
    if (tok == '--remote-name') remoteName = true;

    if (tok.startsWith('-') && !tok.startsWith('--')) {
      if (tok.contains('v')) verbose = true;
      if (tok.contains('L')) followRedirects = true;
      if (tok.contains('k')) insecure = true;
      if (tok.length == 2 && tok[1] == 'O') remoteName = true;
      if (outputFile == null) {
        final letters = tok.substring(1);
        final oIndex = letters.indexOf('o');
        if (oIndex >= 0 &&
            oIndex == letters.length - 1 &&
            i + 1 < tokens.length) {
          outputFile = _unquote(tokens[i + 1]);
        }
      }
    }

    if (tok.startsWith('--')) {
      final body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;

      if (outputFile == null && name == 'output') {
        if (eq >= 0) {
          outputFile = _unquote(body.substring(eq + 1));
        } else if (i + 1 < tokens.length) {
          outputFile = _unquote(tokens[i + 1]);
        }
      }

      if (name == 'connect-timeout') {
        final value = eq >= 0
            ? _unquote(body.substring(eq + 1))
            : (i + 1 < tokens.length ? _unquote(tokens[i + 1]) : '');
        if (value.isNotEmpty && !_isUrlLike(value) && !_isFlagLike(value)) {
          final seconds = double.tryParse(value);
          if (seconds != null) {
            connectTimeout = Duration(milliseconds: (seconds * 1000).round());
          }
        }
      }

      if (name == 'max-time') {
        final value = eq >= 0
            ? _unquote(body.substring(eq + 1))
            : (i + 1 < tokens.length ? _unquote(tokens[i + 1]) : '');
        if (value.isNotEmpty && !_isUrlLike(value) && !_isFlagLike(value)) {
          final seconds = double.tryParse(value);
          if (seconds != null) {
            maxTime = Duration(milliseconds: (seconds * 1000).round());
          }
        }
      }

      if (name == 'trace') {
        traceEnabled = true;
        final value = eq >= 0
            ? _unquote(body.substring(eq + 1))
            : (i + 1 < tokens.length ? _unquote(tokens[i + 1]) : '');
        if (value.isNotEmpty && !_isUrlLike(value) && !_isFlagLike(value)) {
          traceFile ??= value;
        }
      }

      if (name == 'trace-ascii') {
        traceEnabled = true;
        traceAscii = true;
        final value = eq >= 0
            ? _unquote(body.substring(eq + 1))
            : (i + 1 < tokens.length ? _unquote(tokens[i + 1]) : '');
        if (value.isNotEmpty && !_isUrlLike(value) && !_isFlagLike(value)) {
          traceFile ??= value;
        }
      }
    }

    if (tok == '-o' && i + 1 < tokens.length) {
      outputFile ??= _unquote(tokens[i + 1]);
    }

    if (tok == '-H' && i + 1 < tokens.length) {
      final headerValue = _unquote(tokens[i + 1]);
      final colonIndex = headerValue.indexOf(':');
      if (colonIndex > 0) {
        final name = headerValue.substring(0, colonIndex).trim();
        final value = headerValue.substring(colonIndex + 1).trim();
        rawHeaders[name] = value;
      }
    } else if (tok == '--header' && i + 1 < tokens.length) {
      final headerValue = _unquote(tokens[i + 1]);
      final colonIndex = headerValue.indexOf(':');
      if (colonIndex > 0) {
        final name = headerValue.substring(0, colonIndex).trim();
        final value = headerValue.substring(colonIndex + 1).trim();
        rawHeaders[name] = value;
      }
    } else if (tok.startsWith('--header=')) {
      final headerValue = _unquote(tok.substring(9));
      final colonIndex = headerValue.indexOf(':');
      if (colonIndex > 0) {
        final name = headerValue.substring(0, colonIndex).trim();
        final value = headerValue.substring(colonIndex + 1).trim();
        rawHeaders[name] = value;
      }
    }

    if (httpVersion == null) {
      if (tok == '--http3-only') httpVersion = '3-only';
      if (tok == '--http3') httpVersion = '3';
      if (tok == '--http2-prior-knowledge') httpVersion = '2-prior-knowledge';
      if (tok == '--http2') httpVersion = '2';
      if (tok == '--http1.1') httpVersion = '1.1';
      if (tok == '--http1.0') httpVersion = '1.0';
    }

    if (remoteNameFromUrl == null) {
      final unquoted = _unquote(tok);
      if (_isUrlLike(unquoted)) {
        final path = Uri.tryParse(unquoted)?.pathSegments;
        if (path != null && path.isNotEmpty) {
          remoteNameFromUrl = path.last;
        }
      }
    }
  }

  if (outputFile == null && remoteName) {
    outputFile = remoteNameFromUrl;
  }

  const stripShort = {'s', 'S', 'v', 'L', 'O', 'k'};
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
  const stripWithValueShort = {'o', 'w', 'm'};
  const stripWithValueLong = {
    'output',
    'write-out',
    'max-time',
    'connect-timeout',
    'trace',
    'trace-ascii',
  };

  final cleanedTokens = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];

    if (tok == '-H' || tok == '--header') {
      i++;
      continue;
    }
    if (tok.startsWith('--header=')) continue;

    if (tok.startsWith('--')) {
      final body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;

      if (name == 'data-raw' || name == 'data-binary') {
        if (eq >= 0) {
          cleanedTokens.add('--data=${body.substring(eq + 1)}');
        } else {
          cleanedTokens.add('--data');
        }
        continue;
      }

      if (stripLong.contains(name)) continue;
      if (stripWithValueLong.contains(name)) {
        if (eq < 0) i++;
        continue;
      }
      cleanedTokens.add(tok);
      continue;
    }

    if (tok.startsWith('-') && tok.length > 1) {
      if (tok.startsWith('--')) {
        cleanedTokens.add(tok);
        continue;
      }
      if (tok.length == 2 && stripShort.contains(tok[1])) continue;
      if (tok.length == 2 && stripWithValueShort.contains(tok[1])) {
        i++;
        continue;
      }

      if (tok.length > 2) {
        final letters = tok.substring(1);
        final kept = <String>[];
        var consumeValue = false;
        for (var j = 0; j < letters.length; j++) {
          final ch = letters[j];
          if (stripShort.contains(ch)) continue;
          if (stripWithValueShort.contains(ch) && j == letters.length - 1) {
            consumeValue = true;
            continue;
          }
          kept.add(ch);
        }
        if (consumeValue) i++;
        if (kept.isEmpty) continue;
        cleanedTokens.add('-${kept.join()}');
        continue;
      }
    }

    cleanedTokens.add(tok);
  }

  final cleaned = _ensureScheme(cleanedTokens).join(' ');

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

/// Aggressive fallback: only keep tokens that curl_parser natively supports.
/// This ensures any unknown flag is stripped rather than causing a crash.
String _stripAllUnknownFlags(String input) {
  const supportedLong = {
    'url',
    'request',
    'header',
    'data',
    'cookie',
    'user',
    'referer',
    'user-agent',
    'head',
    'form',
    'insecure',
    'location',
  };
  const supportedShort = {
    'X',
    'H',
    'd',
    'b',
    'u',
    'e',
    'A',
    'I',
    'F',
    'k',
    'L',
  };
  const valueFlags = {'X', 'H', 'd', 'b', 'u', 'e', 'A', 'F'};
  const valueFlagsLong = {
    'request',
    'header',
    'data',
    'cookie',
    'user',
    'referer',
    'user-agent',
    'form',
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
      final kept = tok
          .substring(1)
          .split('')
          .where((c) => supportedShort.contains(c))
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
