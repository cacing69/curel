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
  const stripShort = {'s', 'S', 'v'};
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
  };
  // Flags that consume the next token as their value
  const stripWithValueShort = {'o', 'w', 'm'};
  const stripWithValueLong = {
    'output',
    'write-out',
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
      final body = tok.substring(2);
      final eq = body.indexOf('=');
      final name = eq >= 0 ? body.substring(0, eq) : body;

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

/// Pre-processes a curl command string to strip unsupported flags,
/// then parses it into a [Curl] object.
Curl parseCurl(String input) {
  final cleaned = _stripUnsupportedFlags(input);
  return Curl.parse(cleaned);
}
