import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/domain/snippets/snippet_generator.dart';

SnippetRequest snippetRequestFromParsedCurl(ParsedCurl parsed) {
  final curl = parsed.curl;
  final headers = <String, String>{};
  if (curl.headers != null) headers.addAll(curl.headers!);

  String? contentType;
  final contentTypeKey = headers.keys.toList().where(
    (k) => k.toLowerCase() == 'content-type',
  );
  if (contentTypeKey.isNotEmpty) {
    contentType = headers.remove(contentTypeKey.first);
  }

  List<SnippetFormField>? formData;
  if (curl.form && curl.formData != null && curl.formData!.isNotEmpty) {
    formData = curl.formData!.map((f) => SnippetFormField(
      name: f.name,
      value: f.value,
      isFile: f.type.name == 'file',
    )).toList();
  }

  return SnippetRequest(
    method: curl.method,
    uri: curl.uri,
    headers: headers,
    body: curl.data,
    contentType: contentType,
    basicAuth: curl.user,
    formData: formData,
    cookie: curl.cookie,
    userAgent: curl.userAgent,
    referer: curl.referer,
  );
}

SnippetRequest? snippetRequestFromCurlString(String curlString) {
  try {
    final parsed = parseCurl(curlString);
    return snippetRequestFromParsedCurl(parsed);
  } catch (_) {
    return null;
  }
}
