import 'request_model.dart';

class RequestItem {
  final String name;
  final String relativePath;
  final RequestMeta meta;

  const RequestItem({
    required this.name,
    required this.relativePath,
    this.meta = RequestMeta.empty,
  });

  String get displayName => meta.displayName ?? name;

  int? get lastStatusCode => meta.lastStatusCode;
}
