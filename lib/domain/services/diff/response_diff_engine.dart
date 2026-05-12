import 'package:curel/domain/models/diff_entry.dart';

abstract class ResponseDiffEngine {
  List<DiffEntry> diff(dynamic a, dynamic b, {Set<String> ignorePaths = const {}});
}

class JsonDiffEngine implements ResponseDiffEngine {
  static final _volatilePatterns = RegExp(
    r'^(timestamp|.*_at|.*_id|uuid|nonce|etag|request_id|trace_id|.*_token|.*_hash|nonce|signature|created_at|updated_at|deleted_at)$',
    caseSensitive: false,
  );

  static bool isVolatileField(String path) {
    final segments = path.split('.');
    return segments.any((s) => _volatilePatterns.hasMatch(s));
  }

  @override
  List<DiffEntry> diff(dynamic a, dynamic b, {Set<String> ignorePaths = const {}}) {
    final flatA = _flatten(a, '');
    final flatB = _flatten(b, '');
    final allKeys = <String>{...flatA.keys, ...flatB.keys};
    final entries = <DiffEntry>[];

    for (final key in allKeys) {
      if (ignorePaths.contains(key)) continue;
      if (isVolatileField(key)) continue;

      final hasA = flatA.containsKey(key);
      final hasB = flatB.containsKey(key);

      if (!hasA && hasB) {
        entries.add(DiffEntry(path: key, valueB: flatB[key], type: DiffType.added));
      } else if (hasA && !hasB) {
        entries.add(DiffEntry(path: key, valueA: flatA[key], type: DiffType.removed));
      } else {
        final va = flatA[key];
        final vb = flatB[key];
        if (!_deepEquals(va, vb)) {
          entries.add(DiffEntry(path: key, valueA: va, valueB: vb, type: DiffType.changed));
        }
      }
    }

    entries.sort((a, b) => a.path.compareTo(b.path));
    return entries;
  }

  Map<String, dynamic> _flatten(dynamic obj, String prefix) {
    final result = <String, dynamic>{};
    if (obj == null) return result;

    if (obj is Map) {
      for (final entry in obj.entries) {
        final key = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
        if (entry.value is Map || entry.value is List) {
          result.addAll(_flatten(entry.value, key));
        } else {
          result[key] = entry.value;
        }
      }
    } else if (obj is List) {
      for (var i = 0; i < obj.length; i++) {
        final key = '$prefix[$i]';
        if (obj[i] is Map || obj[i] is List) {
          result.addAll(_flatten(obj[i], key));
        } else {
          result[key] = obj[i];
        }
      }
    }
    return result;
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static List<DiffEntry> applyIgnores(
    List<DiffEntry> entries,
    Set<String> manualIgnores,
  ) {
    return entries.where((e) => !manualIgnores.contains(e.path)).toList();
  }

  static List<DiffEntry> filterByType(List<DiffEntry> entries, DiffType? type) {
    if (type == null) return entries;
    return entries.where((e) => e.type == type).toList();
  }
}
