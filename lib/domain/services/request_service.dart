import 'dart:io';
import 'dart:isolate';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/request_item_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:path/path.dart' as p;


abstract class RequestService {
  Future<List<RequestItem>> listRequests(String projectId);
  Future<List<RequestItem>> listRequestsFast(String projectId);
  Future<String?> readCurl(String projectId, String relativePath);
  Future<void> writeCurl(String projectId, String relativePath, String content);
  Future<String> createRequest(
    String projectId,
    String name,
    String curlContent,
  );
  Future<void> deleteRequest(String projectId, String relativePath);
  Future<void> renameRequest(String projectId, String oldPath, String newName);
  Future<String> duplicateRequest(String projectId, String relativePath, {String? newName});
  Future<RequestMeta> readMeta(String projectId, String relativePath);
  Future<void> updateMeta(
    String projectId,
    String relativePath,
    RequestMeta meta,
  );
  Future<bool> requestExists(String projectId, String name);
  String resolvePath(String name);
}

class FilesystemRequestService implements RequestService {
  final FileSystemService _fs;

  FilesystemRequestService(this._fs);

  @override
  Future<List<RequestItem>> listRequests(String projectId) async {
    return listRequestsFast(projectId);
  }

  @override
  Future<List<RequestItem>> listRequestsFast(String projectId) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final dir = Directory(requestsDir);
    if (!await dir.exists()) return [];

    return Isolate.run(() => _scanFastSync(dir.path));
  }

  static List<RequestItem> _scanFastSync(String rootPath) {
    final rootDir = Directory(rootPath);
    if (!rootDir.existsSync()) return [];
    final items = <RequestItem>[];
    _scanDirFastSync(rootDir, rootPath, items);
    return items;
  }

  static void _scanDirFastSync(
    Directory dir,
    String rootDir,
    List<RequestItem> items,
  ) {
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.curl')) {
        final relativePath = p.relative(entity.path, from: rootDir);
        final name = p.basenameWithoutExtension(entity.path);
        String method = 'GET';
        try {
          final bytes = File(entity.path).readAsBytesSync();
          final head = String.fromCharCodes(bytes.take(80));
          final m = RegExp(r'curl\s+(?:\\\s+)?(?:-X\s+)?(\w+)')
              .firstMatch(head);
          if (m != null) {
            final candidate = m.group(1)!.toUpperCase();
            if (!const ['H', 'D', 'F', 'A', 'CURLOPT'].contains(candidate)) {
              method = candidate;
            }
          }
        } catch (_) {}
        items.add(RequestItem(
          name: name,
          relativePath: relativePath,
          method: method,
        ));
      } else if (entity is Directory) {
        _scanDirFastSync(entity, rootDir, items);
      }
    }
  }

  @override
  Future<String?> readCurl(String projectId, String relativePath) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final filePath = p.join(requestsDir, relativePath);
    if (!await _fs.exists(filePath)) return null;
    return _fs.readFile(filePath);
  }

  @override
  Future<void> writeCurl(
    String projectId,
    String relativePath,
    String content,
  ) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final filePath = p.join(requestsDir, relativePath);
    await _fs.writeFile(filePath, content);
  }

  @override
  Future<String> createRequest(
    String projectId,
    String name,
    String curlContent,
  ) async {
    final sanitized = _sanitizePath(name);
    final requestsDir = await _fs.getRequestsDir(projectId);
    final relativePath = '$sanitized.curl';
    final filePath = p.join(requestsDir, relativePath);

    var counter = 1;
    var finalRelativePath = relativePath;
    var finalFilePath = filePath;
    while (await _fs.exists(finalFilePath)) {
      finalRelativePath = '${sanitized}_$counter.curl';
      finalFilePath = p.join(requestsDir, finalRelativePath);
      counter++;
    }

    await _fs.writeFile(finalFilePath, curlContent);
    return finalRelativePath;
  }

  @override
  Future<void> deleteRequest(String projectId, String relativePath) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final curlPath = p.join(requestsDir, relativePath);
    final metaPath = _metaPathFor(requestsDir, relativePath);

    await _fs.deleteFile(curlPath);
    if (await _fs.exists(metaPath)) {
      await _fs.deleteFile(metaPath);
    }
  }

  @override
  Future<String> duplicateRequest(String projectId, String relativePath, {String? newName}) async {
    final content = await readCurl(projectId, relativePath);
    if (content == null) throw Exception('source request not found');
    final posix = relativePath.replaceAll('\\', '/');
    final slash = posix.lastIndexOf('/');
    final folder = slash >= 0 ? posix.substring(0, slash + 1) : '';
    final newPath = await createRequest(
      projectId,
      newName != null ? '$folder$newName' : _autoDuplicateName(relativePath),
      content,
    );
    try {
      final meta = await readMeta(projectId, relativePath);
      await updateMeta(projectId, newPath, meta);
    } catch (_) {}
    return newPath;
  }

  String _autoDuplicateName(String relativePath) {
    final posix = relativePath.replaceAll('\\', '/');
    final slash = posix.lastIndexOf('/');
    final baseName = slash >= 0 ? posix.substring(slash + 1) : posix;
    final nameWithoutExt = baseName.replaceAll('.curl', '');
    final folder = slash >= 0 ? posix.substring(0, slash + 1) : '';
    return '${folder}${nameWithoutExt}_copy';
  }

  @override
  Future<void> renameRequest(
    String projectId,
    String oldRelativePath,
    String newName,
  ) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final oldCurlPath = p.join(requestsDir, oldRelativePath);
    final oldMetaPath = _metaPathFor(requestsDir, oldRelativePath);
    final newRelativePath = '${_sanitizeName(newName)}.curl';
    final newCurlPath = p.join(requestsDir, newRelativePath);
    final newMetaPath = _metaPathFor(requestsDir, newRelativePath);

    final content = await _fs.readFile(oldCurlPath);
    await _fs.writeFile(newCurlPath, content);
    await _fs.deleteFile(oldCurlPath);

    if (await _fs.exists(oldMetaPath)) {
      final metaContent = await _fs.readFile(oldMetaPath);
      await _fs.writeFile(newMetaPath, metaContent);
      await _fs.deleteFile(oldMetaPath);
    }
  }

  @override
  Future<RequestMeta> readMeta(String projectId, String relativePath) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final metaPath = _metaPathFor(requestsDir, relativePath);
    if (!await _fs.exists(metaPath)) return const RequestMeta();
    final content = await _fs.readFile(metaPath);
    return RequestMeta.decode(content);
  }

  @override
  Future<void> updateMeta(
    String projectId,
    String relativePath,
    RequestMeta meta,
  ) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final metaPath = _metaPathFor(requestsDir, relativePath);
    await _fs.writeFile(metaPath, RequestMeta.encode(meta));
  }

  String _metaPathFor(String requestsDir, String curlRelativePath) {
    final basePath = p.withoutExtension(curlRelativePath);
    return p.join(requestsDir, '$basePath.meta.json');
  }

  String _sanitizeName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _sanitizePath(String name) {
    final parts = name.split('/');
    return parts.map(_sanitizeName).join('/');
  }

  @override
  Future<bool> requestExists(String projectId, String name) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final relativePath = '${_sanitizePath(name)}.curl';
    final filePath = p.join(requestsDir, relativePath);
    return _fs.exists(filePath);
  }

  @override
  String resolvePath(String name) => '${_sanitizePath(name)}.curl';
}
