import 'package:isar_community/isar.dart';

part 'crash_log_model.g.dart';

@collection
class CrashLog {
  Id id = Isar.autoIncrement;

  @Index()
  late DateTime timestamp;

  @Index()
  late int severity;

  @Index(composite: [CompositeIndex('timestamp')])
  late String context;

  late String message;

  String? stackTrace;

  CrashLog({
    required this.timestamp,
    required this.severity,
    required this.context,
    required this.message,
    this.stackTrace,
  });
}

abstract class Severity {
  static const int critical = 0;
  static const int error = 1;
  static const int warning = 2;
  static const int info = 3;
}
