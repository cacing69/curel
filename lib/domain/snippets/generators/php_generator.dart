import 'package:curel/domain/snippets/snippet_generator.dart';

class PhpGenerator implements SnippetGenerator {
  @override
  String get id => 'php';
  @override
  String get name => 'PHP (cURL)';
  @override
  String get language => 'php';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();

    buf.writeln('<?php');
    buf.writeln('');
    buf.writeln('\$ch = curl_init();');
    buf.writeln('');
    buf.writeln("curl_setopt(\$ch, CURLOPT_URL, '$url');");
    buf.writeln("curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);");

    if (method != 'GET') {
      buf.writeln("curl_setopt(\$ch, CURLOPT_CUSTOMREQUEST, '$method');");
    }

    if (request.basicAuth != null) {
      buf.writeln("curl_setopt(\$ch, CURLOPT_USERPWD, '${_esc(request.basicAuth!)}');");
    }

    final allHeaders = <String, String>{};
    if (request.contentType != null) {
      allHeaders['content-type'] = request.contentType!;
    }
    if (request.cookie != null && request.cookie!.isNotEmpty) {
      allHeaders['cookie'] = request.cookie!;
    }
    if (request.userAgent != null) {
      allHeaders['user-agent'] = request.userAgent!;
    }
    if (request.referer != null) {
      allHeaders['referer'] = request.referer!;
    }
    allHeaders.addAll(request.headers);

    if (allHeaders.isNotEmpty) {
      buf.writeln('');
      buf.writeln('\$headers = [');
      for (final e in allHeaders.entries) {
        buf.writeln("  '${e.key}: ${_esc(e.value)}',");
      }
      buf.writeln('];');
      buf.writeln("curl_setopt(\$ch, CURLOPT_HTTPHEADER, \$headers);");
    }

    if (request.formData != null && request.formData!.isNotEmpty) {
      buf.writeln('');
      buf.writeln('\$postData = [');
      for (final f in request.formData!) {
        if (f.isFile) {
          buf.writeln("  '${f.name}' => new CURLFile('${_esc(f.value)}'),");
        } else {
          buf.writeln("  '${f.name}' => '${_esc(f.value)}',");
        }
      }
      buf.writeln('];');
      buf.writeln("curl_setopt(\$ch, CURLOPT_POSTFIELDS, \$postData);");
    } else if (request.body != null && request.body!.isNotEmpty) {
      buf.writeln('');
      buf.writeln("curl_setopt(\$ch, CURLOPT_POSTFIELDS, '${_esc(request.body!)}');");
    }

    buf.writeln('');
    buf.writeln('\$response = curl_exec(\$ch);');
    buf.writeln('\$statusCode = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);');
    buf.writeln('');
    buf.writeln('if (curl_errno(\$ch)) {');
    buf.writeln("  echo 'error: ' . curl_error(\$ch);");
    buf.writeln('} else {');
    buf.writeln("  echo 'status: ' . \$statusCode . PHP_EOL;");
    buf.writeln("  echo \$response;");
    buf.writeln('}');
    buf.writeln('');
    buf.writeln('curl_close(\$ch);');

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll("'", "\\'");
}
