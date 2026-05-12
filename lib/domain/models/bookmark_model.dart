import 'dart:convert';

class BookmarkItem {
  final String id;
  final DateTime savedAt;
  final String curlCommand;
  final String source;
  final String? projectId;
  final String? projectName;
  final int? statusCode;
  final String? method;
  final String? url;
  final int? originHistoryId;
  final DateTime? originTimestamp;

  const BookmarkItem({
    required this.id,
    required this.savedAt,
    required this.curlCommand,
    required this.source,
    this.projectId,
    this.projectName,
    this.statusCode,
    this.method,
    this.url,
    this.originHistoryId,
    this.originTimestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'saved_at': savedAt.toIso8601String(),
        'curl': curlCommand,
        'source': source,
        'project_id': projectId,
        'project_name': projectName,
        'status_code': statusCode,
        'method': method,
        'url': url,
        'origin_history_id': originHistoryId,
        'origin_timestamp': originTimestamp?.toIso8601String(),
      };

  static BookmarkItem fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      id: json['id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      curlCommand: json['curl'] as String,
      source: (json['source'] as String?) ?? 'history',
      projectId: json['project_id'] as String?,
      projectName: json['project_name'] as String?,
      statusCode: json['status_code'] as int?,
      method: json['method'] as String?,
      url: json['url'] as String?,
      originHistoryId: json['origin_history_id'] as int?,
      originTimestamp: (json['origin_timestamp'] as String?) != null
          ? DateTime.parse(json['origin_timestamp'] as String)
          : null,
    );
  }

  static List<BookmarkItem> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => BookmarkItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<BookmarkItem> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }
}

