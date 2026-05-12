import 'package:curel/domain/snippets/snippet_generator.dart';

class JsFetchGenerator implements SnippetGenerator {
  @override
  String get id => 'js_fetch';
  @override
  String get name => 'JavaScript (fetch)';
  @override
  String get language => 'javascript';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();
    final hasBody = request.hasBody;

    final headers = <String, String>{};

    if (request.contentType != null) {
      headers['content-type'] = request.contentType!;
    }

    if (request.cookie != null && request.cookie!.isNotEmpty) {
      headers['cookie'] = request.cookie!;
    }

    if (request.userAgent != null) {
      headers['user-agent'] = request.userAgent!;
    }

    if (request.referer != null) {
      headers['referer'] = request.referer!;
    }

    headers.addAll(request.headers);

    buf.writeln("const url = '$url';");
    buf.writeln("");

    buf.writeln("const options = {");
    buf.writeln("  method: '$method',");

    if (request.basicAuth != null) {
      buf.writeln("  headers: {");
      for (final e in headers.entries) {
        buf.writeln("    '${e.key}': '${_esc(e.value)}',");
      }
      buf.writeln("    'authorization': 'basic ${_btoa(request.basicAuth!)}',");
      buf.writeln("  },");
    } else if (headers.isNotEmpty) {
      buf.writeln("  headers: {");
      for (final e in headers.entries) {
        buf.writeln("    '${e.key}': '${_esc(e.value)}',");
      }
      buf.writeln("  },");
    }

    if (request.formData != null && request.formData!.isNotEmpty) {
      buf.writeln("  body: new FormData();");
      for (final f in request.formData!) {
        if (f.isFile) {
          buf.writeln("  formData.append('${f.name}', fileInput.files[0]);");
        } else {
          buf.writeln("  formData.append('${f.name}', '${_esc(f.value)}');");
        }
      }
    } else if (hasBody && request.body != null) {
      buf.writeln("  body: `${request.body}`,");
    }

    buf.writeln("};");
    buf.writeln("");
    buf.writeln("try {");
    buf.writeln("  const response = await fetch(url, options);");
    buf.writeln("  const data = await response.text();");
    buf.writeln("  console.log(response.status, data);");
    buf.writeln("} catch (error) {");
    buf.writeln("  console.error('fetch failed:', error);");
    buf.writeln("}");

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll("'", "\\'");

  String _btoa(String s) {
    final bytes = s.codeUnits;
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    final result = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b1 = bytes[i];
      final b2 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b3 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      final triple = (b1 << 16) | (b2 << 8) | b3;
      result.write(chars[(triple >> 18) & 0x3f]);
      result.write(chars[(triple >> 12) & 0x3f]);
      result.write(i + 1 < bytes.length ? chars[(triple >> 6) & 0x3f] : '=');
      result.write(i + 2 < bytes.length ? chars[triple & 0x3f] : '=');
    }
    return result.toString();
  }
}
