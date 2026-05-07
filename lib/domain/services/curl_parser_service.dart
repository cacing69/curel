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
  const stripShort = {'s', 'S', 'v', 'L'};
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
        if (eq < 0 && i + 1 < tokens.length) i++;
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
        // skip the value token too
        if (i + 1 < tokens.length) i++;
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

  const ParsedCurl({
    required this.curl,
    this.outputFileName,
    this.verbose = false,
    this.followRedirects = false,
    this.traceFileName,
    this.traceAscii = false,
  });
}

/// Extracts the trace filename from `--trace` or `--trace-ascii` flag in [input].
String? _extractTraceFile(String input) {
  final tokens = _tokenize(input);
  for (var i = 0; i < tokens.length; i++) {
    final tok = tokens[i];
    if (tok == '--trace' && i + 1 < tokens.length) {
      return _unquote(tokens[i + 1]);
    }
    if (tok.startsWith('--trace=')) {
      return _unquote(tok.substring(8));
    }
    if (tok == '--trace-ascii' && i + 1 < tokens.length) {
      return _unquote(tokens[i + 1]);
    }
    if (tok.startsWith('--trace-ascii=')) {
      return _unquote(tok.substring(14));
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

/// Pre-processes a curl command string to strip unsupported flags,
/// then parses it into a [ParsedCurl] object with optional output filename.
ParsedCurl parseCurl(String input) {
  final outputFile = _extractOutputFile(input);
  final verbose = _hasVerbose(input);
  final followRedirects = _hasLocation(input);
  final traceFile = _extractTraceFile(input);
  final traceAscii = _hasTraceAscii(input);
  final cleaned = _stripUnsupportedFlags(input);
  return ParsedCurl(
    curl: Curl.parse(cleaned),
    outputFileName: outputFile,
    verbose: verbose,
    followRedirects: followRedirects,
    traceFileName: traceFile,
    traceAscii: traceAscii,
  );
}
