class SnippetRequest {
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final String? contentType;
  final String? basicAuth;
  final List<SnippetFormField>? formData;
  final String? cookie;
  final String? userAgent;
  final String? referer;

  const SnippetRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
    this.contentType,
    this.basicAuth,
    this.formData,
    this.cookie,
    this.userAgent,
    this.referer,
  });

  bool get hasBody => body != null || (formData != null && formData!.isNotEmpty);
}

class SnippetFormField {
  final String name;
  final String value;
  final bool isFile;

  const SnippetFormField({
    required this.name,
    required this.value,
    this.isFile = false,
  });
}

class Snippet {
  final String code;
  final String language;

  const Snippet({required this.code, required this.language});
}

abstract class SnippetGenerator {
  String get id;
  String get name;
  String get language;
  String get icon;
  Snippet generate(SnippetRequest request);
}
