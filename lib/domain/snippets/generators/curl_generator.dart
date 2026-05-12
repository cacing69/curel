import 'package:curel/domain/snippets/snippet_generator.dart';

class CurlSnippetGenerator implements SnippetGenerator {
  @override
  String get id => 'curl';
  @override
  String get name => 'cURL';
  @override
  String get language => 'bash';
  @override
  String get icon => 'terminal';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer('curl -X ${request.method}');

    buf.write(" '${request.uri.toString()}'");

    if (request.basicAuth != null) {
      buf.write(" \\\n  -u '${
        request.basicAuth!.replaceAll("'", "'\\''")
      }'");
    }

    for (final e in request.headers.entries) {
      if (e.key.toLowerCase() == 'content-type' && e.value == request.contentType) {
        continue;
      }
      buf.write(" \\\n  -H '${e.key}: ${e.value.replaceAll("'", "'\\''")}'");
    }

    if (request.contentType != null) {
      buf.write(" \\\n  -H 'content-type: ${request.contentType}'");
    }

    if (request.cookie != null && request.cookie!.isNotEmpty) {
      buf.write(" \\\n  -b '${request.cookie!.replaceAll("'", "'\\''")}'");
    }

    if (request.userAgent != null) {
      buf.write(" \\\n  -A '${request.userAgent!.replaceAll("'", "'\\''")}'");
    }

    if (request.referer != null) {
      buf.write(" \\\n  -e '${request.referer!.replaceAll("'", "'\\''")}'");
    }

    if (request.formData != null && request.formData!.isNotEmpty) {
      for (final f in request.formData!) {
        if (f.isFile) {
          buf.write(" \\\n  -F '${f.name}=@${f.value}'");
        } else {
          buf.write(" \\\n  -F '${f.name}=${f.value}'");
        }
      }
    } else if (request.body != null && request.body!.isNotEmpty) {
      final escaped = request.body!.replaceAll("'", "'\\''");
      buf.write(" \\\n  -d '$escaped'");
    }

    return Snippet(code: buf.toString(), language: language);
  }
}
