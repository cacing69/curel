import 'package:curel/domain/snippets/snippet_generator.dart';

class JavaOkHttpGenerator implements SnippetGenerator {
  @override
  String get id => 'java_okhttp';
  @override
  String get name => 'Java (OkHttp)';
  @override
  String get language => 'java';
  @override
  String get icon => 'code';

  @override
  Snippet generate(SnippetRequest request) {
    final buf = StringBuffer();
    final method = request.method.toUpperCase();
    final url = request.uri.toString();

    buf.writeln('import java.io.IOException;');
    buf.writeln('');
    buf.writeln('import okhttp3.MediaType;');
    buf.writeln('import okhttp3.OkHttpClient;');
    buf.writeln('import okhttp3.Request;');
    buf.writeln('import okhttp3.RequestBody;');
    buf.writeln('import okhttp3.Response;');
    buf.writeln('');

    if (request.basicAuth != null) {
      buf.writeln('import okhttp3.Credentials;');
      buf.writeln('');
    }

    buf.writeln('public class Main {');
    buf.writeln('  public static void main(String[] args) throws IOException {');

    buf.writeln('    OkHttpClient client = new OkHttpClient();');

    if (request.formData != null && request.formData!.isNotEmpty) {
      buf.writeln('');
      buf.writeln('    okhttp3.MultipartBody.Builder bodyBuilder =');
      buf.writeln('        new okhttp3.MultipartBody.Builder()');
      buf.writeln('            .setType(okhttp3.MultipartBody.FORM);');
      for (final f in request.formData!) {
        if (f.isFile) {
          buf.writeln("    bodyBuilder.addFormDataPart(\"${_esc(f.name)}\", \"${_esc(f.value)}\",");
          buf.writeln("        okhttp3.RequestBody.create(null, new java.io.File(\"${_esc(f.value)}\")));");
        } else {
          buf.writeln("    bodyBuilder.addFormDataPart(\"${_esc(f.name)}\", \"${_esc(f.value)}\");");
        }
      }
      buf.writeln('    RequestBody body = bodyBuilder.build();');
    } else if (request.body != null && request.body!.isNotEmpty) {
      final mediaType = request.contentType ?? 'application/octet-stream';
      buf.writeln("    MediaType mediaType = MediaType.parse(\"${_esc(mediaType)}\");");
      buf.writeln("    RequestBody body = RequestBody.create(mediaType, \"${_esc(request.body!)}\");");
    }

    buf.writeln('');
    buf.writeln('    Request.Builder builder = new Request.Builder()');
    buf.writeln("      .url(\"${_esc(url)}\")");

    if (request.hasBody) {
      buf.writeln('      .method("$method", body)');
    } else if (method != 'GET') {
      buf.writeln('      .method("$method", null)');
    }

    if (request.basicAuth != null) {
      buf.writeln("      .addHeader(\"Authorization\", Credentials.basic(\"${_esc(request.basicAuth!)}\"))");
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
      buf.writeln("      .addHeader(\"${e.key}\", \"${_esc(e.value)}\")");
    }

    buf.writeln('      .build();');
    buf.writeln('');
    buf.writeln('    try (Response response = client.newCall(request).execute()) {');
    buf.writeln('      System.out.println("status: " + response.code());');
    buf.writeln('      System.out.println(response.body().string());');
    buf.writeln('    }');
    buf.writeln('  }');
    buf.writeln('}');

    return Snippet(code: buf.toString(), language: language);
  }

  String _esc(String s) => s.replaceAll('"', '\\"');
}
