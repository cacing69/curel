import 'package:curel/domain/models/crash_log_model.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

class CrashLogService {
  late final Future<Isar> _db = _init();

  Future<Isar> _init() async {
    final dir = await getApplicationSupportDirectory();
    return Isar.open([CrashLogSchema], directory: dir.path, name: 'crash_log');
  }

  Future<void> log(
    int severity,
    String context,
    String message, {
    String? stackTrace,
  }) async {
    final isar = await _db;
    await isar.writeTxn(() async {
      await isar.crashLogs.put(
        CrashLog(
          timestamp: DateTime.now(),
          severity: severity,
          context: context,
          message: message,
          stackTrace: stackTrace,
        ),
      );
    });
    _prune(isar);
  }

  Future<List<CrashLog>> getAll({int? severity, int limit = 500}) async {
    final isar = await _db;
    if (severity != null) {
      return isar.crashLogs
          .filter()
          .severityEqualTo(severity)
          .sortByTimestampDesc()
          .limit(limit)
          .findAll();
    }
    return isar.crashLogs.where().sortByTimestampDesc().limit(limit).findAll();
  }

  Future<Map<int, int>> countBySeverity() async {
    final isar = await _db;
    final all = await isar.crashLogs.where().findAll();
    final counts = <int, int>{};
    for (final log in all) {
      counts[log.severity] = (counts[log.severity] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> clear() async {
    final isar = await _db;
    await isar.writeTxn(() async {
      await isar.crashLogs.clear();
    });
  }

  Future<void> _prune(Isar isar) async {
    final count = await isar.crashLogs.count();
    if (count <= 1000) return;
    final cutoff = DateTime.now().subtract(Duration(days: 7));
    await isar.writeTxn(() async {
      await isar.crashLogs.filter().timestampLessThan(cutoff).deleteAll();
    });
    // If still over limit, delete oldest
    final remaining = await isar.crashLogs.count();
    if (remaining > 1000) {
      final oldest = await isar.crashLogs
          .where()
          .sortByTimestamp()
          .limit(remaining - 1000)
          .findAll();
      await isar.writeTxn(() async {
        for (final log in oldest) {
          await isar.crashLogs.delete(log.id);
        }
      });
    }
  }
}
