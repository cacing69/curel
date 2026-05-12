import 'dart:convert';

enum DiffType { added, removed, changed, unchanged }

class DiffEntry {
  final String path;
  final dynamic valueA;
  final dynamic valueB;
  final DiffType type;

  const DiffEntry({
    required this.path,
    this.valueA,
    this.valueB,
    required this.type,
  });

  String get formattedValueA => _formatValue(valueA);
  String get formattedValueB => _formatValue(valueB);

  static String _formatValue(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    return const JsonEncoder.withIndent('  ').convert(v);
  }
}
