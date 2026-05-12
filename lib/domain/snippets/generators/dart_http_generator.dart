import 'package:curel/domain/snippets/snippet_generator.dart';

class DartHttpGenerator implements SnippetGenerator {
  @override
  String get id => 'dart_http';
  @override
  String get name => 'Dart (http)';
  @override
  String get language => 'dart';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();

    buf.writeln("import 'dart:convert';");
    buf.writeln("import 'package:http/http.dart' as http;");
    buf.writeln("");

    buf.writeln("final uri = Uri.parse('$url');");

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

    if (request.basicAuth != null) {
      final encoded = _base64encode(request.basicAuth!.codeUnits);
      allHeaders['authorization'] = 'basic $encoded';
    }

    if (allHeaders.isNotEmpty) {
      buf.writeln("");
      buf.writeln("final headers = <String, String>{");
      for (final e in allHeaders.entries) {
        buf.writeln("  '${e.key}': '${_esc(e.value)}',");
      }
      buf.writeln("};");
    }

    if (request.hasBody) {
      buf.writeln("");
      if (request.formData != null && request.formData!.isNotEmpty) {
        buf.writeln("final body = ${_formDataMap(request.formData!)};");
      } else if (request.body != null) {
        buf.writeln("final body = '''${request.body}''';");
      }
    }

    buf.writeln("");

    if (method == 'GET' && !request.hasBody) {
      buf.write("final response = await http.get(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      buf.writeln(");");
    } else if (method == 'POST') {
      buf.write("final response = await http.post(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      if (request.hasBody) buf.write(", body: body");
      buf.writeln(");");
    } else if (method == 'PUT') {
      buf.write("final response = await http.put(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      if (request.hasBody) buf.write(", body: body");
      buf.writeln(");");
    } else if (method == 'PATCH') {
      buf.write("final response = await http.patch(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      if (request.hasBody) buf.write(", body: body");
      buf.writeln(");");
    } else if (method == 'DELETE') {
      buf.write("final response = await http.delete(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      if (request.hasBody) buf.write(", body: body");
      buf.writeln(");");
    } else if (method == 'HEAD') {
      buf.write("final response = await http.head(uri");
      if (allHeaders.isNotEmpty) buf.write(", headers: headers");
      buf.writeln(");");
    } else {
      buf.writeln("final request = http.Request('$method', uri);");
      if (allHeaders.isNotEmpty) buf.writeln("request.headers.addAll(headers);");
      if (request.hasBody) buf.writeln("request.body = body;");
      buf.writeln("final streamed = await http.Client().send(request);");
      buf.writeln("final response = await http.Response.fromStream(streamed);");
    }

    buf.writeln("");
    buf.writeln("print('status: \${response.statusCode}');");
    buf.writeln("print('body: \${response.body}');");

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll("'", "\\'");

  String _formDataMap(List<SnippetFormField> fields) {
    return fields.map((f) => "'${f.name}': '${_esc(f.value)}'").join(',\n  ');
  }

  String _base64encode(List<int> bytes) {
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
