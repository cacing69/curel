import 'request_model.dart';

class RequestItem {
  final String name;
  final String relativePath;
  final RequestMeta meta;
  final String method;

  const RequestItem({
    required this.name,
    required this.relativePath,
    this.meta = RequestMeta.empty,
    this.method = '',
  });

  String get displayName => meta.displayName ?? name;

  int? get lastStatusCode => meta.lastStatusCode;
}
