import 'package:curel/domain/snippets/snippet_generator.dart';

class PythonRequestsGenerator implements SnippetGenerator {
  @override
  String get id => 'python_requests';
  @override
  String get name => 'Python (requests)';
  @override
  String get language => 'python';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();
    final hasBody = request.hasBody;

    buf.writeln("import requests");
    buf.writeln("");

    if (request.headers.isNotEmpty ||
        request.contentType != null ||
        request.cookie != null ||
        request.userAgent != null ||
        request.referer != null) {
      buf.writeln("headers = {");

      if (request.contentType != null) {
        buf.writeln("    'content-type': '${_esc(request.contentType!)}',");
      }

      for (final e in request.headers.entries) {
        buf.writeln("    '${_esc(e.key)}': '${_esc(e.value)}',");
      }

      if (request.cookie != null && request.cookie!.isNotEmpty) {
        buf.writeln("    'cookie': '${_esc(request.cookie!)}',");
      }

      if (request.userAgent != null) {
        buf.writeln("    'user-agent': '${_esc(request.userAgent!)}',");
      }

      if (request.referer != null) {
        buf.writeln("    'referer': '${_esc(request.referer!)}',");
      }

      buf.writeln("}");
    }

    if (request.basicAuth != null) {
      buf.writeln("");
      final parts = request.basicAuth!.split(':');
      final user = parts.isNotEmpty ? parts[0] : '';
      final pass = parts.length > 1 ? parts[1] : '';
      buf.writeln("auth = ('${_esc(user)}', '${_esc(pass)}')");
    }

    if (request.formData != null && request.formData!.isNotEmpty) {
      buf.writeln("");
      buf.writeln("files = {");
      for (final f in request.formData!) {
        if (f.isFile) {
          buf.writeln("    '${_esc(f.name)}': open('${_esc(f.value)}', 'rb'),");
        } else {
          buf.writeln("    '${_esc(f.name)}': (None, '${_esc(f.value)}'),");
        }
      }
      buf.writeln("}");
    }

    buf.writeln("");

    if (method == 'GET' && !hasBody) {
      buf.write("response = requests.get('$url'");
    } else if (method == 'POST' && hasBody) {
      buf.write("response = requests.post('$url'");
    } else if (method == 'PUT' && hasBody) {
      buf.write("response = requests.put('$url'");
    } else if (method == 'DELETE') {
      buf.write("response = requests.delete('$url'");
    } else if (method == 'PATCH' && hasBody) {
      buf.write("response = requests.patch('$url'");
    } else if (method == 'HEAD') {
      buf.write("response = requests.head('$url'");
    } else if (method == 'OPTIONS') {
      buf.write("response = requests.options('$url'");
    } else {
      buf.write("response = requests.request('$method', '$url'");
    }

    if (request.headers.isNotEmpty ||
        request.contentType != null ||
        request.cookie != null ||
        request.userAgent != null ||
        request.referer != null) {
      buf.write(", headers=headers");
    }

    if (request.basicAuth != null) {
      buf.write(", auth=auth");
    }

    if (request.formData != null && request.formData!.isNotEmpty) {
      buf.write(", files=files");
    } else if (request.body != null && request.body!.isNotEmpty) {
      buf.write(", data='''${request.body}'''");
    }

    buf.writeln(")");
    buf.writeln("");
    buf.writeln("print(response.status_code)");
    buf.writeln("print(response.text)");

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll("'", "\\'");
}
