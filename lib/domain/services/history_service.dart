import 'package:curel/domain/models/history_model.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

class HistoryService {
  late Future<Isar> _db;

  HistoryService() {
    _db = _init();
  }

  Future<Isar> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      [HistoryItemSchema],
      directory: dir.path,
      name: 'history',
    );
  }

  Future<void> add(HistoryItem item) async {
    final isar = await _db;
    await isar.writeTxn(() async {
      await isar.historyItems.put(item);
    });
  }

  Future<List<HistoryItem>> getAll({String? projectId}) async {
    final isar = await _db;
    if (projectId != null) {
      return isar.historyItems
          .filter()
          .projectIdEqualTo(projectId)
          .sortByTimestampDesc()
          .findAll();
    }
    return isar.historyItems.where().sortByTimestampDesc().findAll();
  }

  Future<void> clear() async {
    final isar = await _db;
    await isar.writeTxn(() async {
      await isar.historyItems.clear();
    });
  }

  Future<void> delete(Id id) async {
    final isar = await _db;
    await isar.writeTxn(() async {
      await isar.historyItems.delete(id);
    });
  }
}
