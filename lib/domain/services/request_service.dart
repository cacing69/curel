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
  Future<String?> readNotes(String projectId, String relativePath);
  Future<void> writeNotes(String projectId, String relativePath, String content);
  Future<String?> readCurlrc(String projectId);
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

    await _fs.deleteFile(curlPath);
    for (final sidecar in _sidecarPathsFor(requestsDir, relativePath)) {
      if (await _fs.exists(sidecar)) {
        await _fs.deleteFile(sidecar);
      }
    }
  }

  @override
  Future<String> duplicateRequest(String projectId, String relativePath, {String? newName}) async {
    final content = await readCurl(projectId, relativePath);
    if (content == null) throw Exception('source request not found');
    final requestsDir = await _fs.getRequestsDir(projectId);
    final posix = relativePath.replaceAll('\\', '/');
    final slash = posix.lastIndexOf('/');
    final folder = slash >= 0 ? posix.substring(0, slash + 1) : '';
    final newPath = await createRequest(
      projectId,
      newName != null ? '$folder$newName' : _autoDuplicateName(relativePath),
      content,
    );
    for (final sidecar in _sidecarPathsFor(requestsDir, relativePath)) {
      if (await _fs.exists(sidecar)) {
        final newBase = p.withoutExtension(newPath);
        final ext = p.extension(sidecar);
        final newSidecar = p.join(requestsDir, '$newBase$ext');
        final sidecarContent = await _fs.readFile(sidecar);
        await _fs.writeFile(newSidecar, sidecarContent);
      }
    }
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
    final newRelativePath = '${_sanitizeName(newName)}.curl';
    final newCurlPath = p.join(requestsDir, newRelativePath);

    final content = await _fs.readFile(oldCurlPath);
    await _fs.writeFile(newCurlPath, content);
    await _fs.deleteFile(oldCurlPath);

    for (final oldSidecar in _sidecarPathsFor(requestsDir, oldRelativePath)) {
      if (await _fs.exists(oldSidecar)) {
        final newBase = p.withoutExtension(newRelativePath);
        final ext = p.extension(oldSidecar);
        final newSidecar = p.join(requestsDir, '$newBase$ext');
        final sidecarContent = await _fs.readFile(oldSidecar);
        await _fs.writeFile(newSidecar, sidecarContent);
        await _fs.deleteFile(oldSidecar);
      }
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

  List<String> _sidecarPathsFor(String requestsDir, String curlRelativePath) {
    final basePath = p.withoutExtension(curlRelativePath);
    return [
      p.join(requestsDir, '$basePath.meta.json'),
      p.join(requestsDir, '$basePath.notes.md'),
    ];
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

  @override
  Future<String?> readNotes(String projectId, String relativePath) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final basePath = p.withoutExtension(relativePath);
    final notesPath = p.join(requestsDir, '$basePath.notes.md');
    if (!await _fs.exists(notesPath)) return null;
    return _fs.readFile(notesPath);
  }

  @override
  Future<void> writeNotes(String projectId, String relativePath, String content) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final basePath = p.withoutExtension(relativePath);
    final notesPath = p.join(requestsDir, '$basePath.notes.md');
    await _fs.writeFile(notesPath, content);
  }

  @override
  Future<String?> readCurlrc(String projectId) async {
    final requestsDir = await _fs.getRequestsDir(projectId);
    final curlrcPath = p.join(requestsDir, '.curlrc');
    if (!await _fs.exists(curlrcPath)) return null;
    return _fs.readFile(curlrcPath);
  }
}
