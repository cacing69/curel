import 'package:curel/domain/snippets/snippet_generator.dart';

class GoGenerator implements SnippetGenerator {
  @override
  String get id => 'go';
  @override
  String get name => 'Go (net/http)';
  @override
  String get language => 'go';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();

    buf.writeln('package main');
    buf.writeln('');
    buf.writeln('import (');
    buf.writeln('  "fmt"');
    buf.writeln('  "io"');
    buf.writeln('  "net/http"');
    buf.writeln('  "strings"');
    buf.writeln(')');
    buf.writeln('');
    buf.writeln('func main() {');
    buf.writeln("  url := \"$url\"");

    if (request.hasBody) {
      buf.writeln('  body := strings.NewReader(`${
        request.formData != null && request.formData!.isNotEmpty
            ? _buildFormBody(request.formData!)
            : (request.body ?? '')
      }`)');
    }

    buf.writeln('  req, err := http.NewRequest("$method", url, ${
      request.hasBody ? 'body' : 'nil'
    })');
    buf.writeln('  if err != nil {');
    buf.writeln('    fmt.Println("error:", err)');
    buf.writeln('    return');
    buf.writeln('  }');

    if (request.basicAuth != null) {
      final parts = request.basicAuth!.split(':');
      final user = parts.isNotEmpty ? parts[0] : '';
      final pass = parts.length > 1 ? parts[1] : '';
      buf.writeln('  req.SetBasicAuth("${_esc(user)}", "${_esc(pass)}")');
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

    for (final e in allHeaders.entries) {
      buf.writeln('  req.Header.Set("${e.key}", "${_esc(e.value)}")');
    }

    buf.writeln('');
    buf.writeln('  client := &http.Client{}');
    buf.writeln('  resp, err := client.Do(req)');
    buf.writeln('  if err != nil {');
    buf.writeln('    fmt.Println("error:", err)');
    buf.writeln('    return');
    buf.writeln('  }');
    buf.writeln('  defer resp.Body.Close()');
    buf.writeln('');
    buf.writeln('  fmt.Println("status:", resp.StatusCode)');
    buf.writeln('  bodyBytes, _ := io.ReadAll(resp.Body)');
    buf.writeln('  fmt.Println(string(bodyBytes))');
    buf.writeln('}');

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll('"', '\\"');

  String _buildFormBody(List<SnippetFormField> fields) {
    return fields.map((f) => '${f.name}=${f.value}').join('&');
  }
}
