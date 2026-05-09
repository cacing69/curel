import 'package:curel/domain/models/bookmark_model.dart';
import 'package:curel/domain/models/history_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BookmarkService {
  static const _key = 'bookmark_items_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<List<BookmarkItem>> getAll({String? projectId}) async {
    final prefs = await _instance;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final items = BookmarkItem.decodeList(raw);
    final filtered = projectId == null
        ? items
        : items.where((e) => e.projectId == projectId).toList();
    filtered.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return filtered;
  }

  Future<BookmarkItem?> getByOriginHistoryId(int historyId) async {
    final items = await getAll();
    for (final b in items) {
      if (b.originHistoryId == historyId) return b;
    }
    return null;
  }

  Future<bool> isBookmarkedHistory(int historyId) async {
    return (await getByOriginHistoryId(historyId)) != null;
  }

  Future<BookmarkItem> addFromHistory(
    HistoryItem item, {
    String? projectName,
  }) async {
    final prefs = await _instance;
    final raw = prefs.getString(_key);
    final items = (raw == null || raw.isEmpty)
        ? <BookmarkItem>[]
        : BookmarkItem.decodeList(raw);

    final existingIndex =
        items.indexWhere((e) => e.originHistoryId == item.id);
    if (existingIndex >= 0) {
      return items[existingIndex];
    }

    final now = DateTime.now();
    final bookmark = BookmarkItem(
      id: now.microsecondsSinceEpoch.toString(),
      savedAt: now,
      curlCommand: item.curlCommand,
      source: 'history',
      projectId: item.projectId,
      projectName: projectName,
      statusCode: item.statusCode,
      method: item.method,
      url: item.url,
      originHistoryId: item.id,
      originTimestamp: item.timestamp,
    );
    items.insert(0, bookmark);
    await prefs.setString(_key, BookmarkItem.encodeList(items));
    return bookmark;
  }

  Future<void> removeById(String id) async {
    final prefs = await _instance;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    final items = BookmarkItem.decodeList(raw);
    items.removeWhere((e) => e.id == id);
    await prefs.setString(_key, BookmarkItem.encodeList(items));
  }

  Future<bool> removeByOriginHistoryId(int historyId) async {
    final prefs = await _instance;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return false;
    final items = BookmarkItem.decodeList(raw);
    final before = items.length;
    items.removeWhere((e) => e.originHistoryId == historyId);
    if (items.length == before) return false;
    await prefs.setString(_key, BookmarkItem.encodeList(items));
    return true;
  }

  Future<bool> toggleFromHistory(
    HistoryItem item, {
    String? projectName,
  }) async {
    final removed = await removeByOriginHistoryId(item.id);
    if (removed) return false;
    await addFromHistory(item, projectName: projectName);
    return true;
  }

  Future<void> clear() async {
    final prefs = await _instance;
    await prefs.remove(_key);
  }
}

