import 'package:isar_community/isar.dart';

part 'history_model.g.dart';

@collection
class HistoryItem {
  Id id = Isar.autoIncrement;

  @Index()
  late DateTime timestamp;

  late String curlCommand;

  String? projectId;

  int? statusCode;

  String? method;

  String? url;

  HistoryItem({
    required this.timestamp,
    required this.curlCommand,
    this.projectId,
    this.statusCode,
    this.method,
    this.url,
  });
}
