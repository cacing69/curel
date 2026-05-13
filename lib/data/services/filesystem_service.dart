import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

abstract class FileSystemService {
  Future<String> getWorkspaceRoot();
  Future<String> getProjectDir(String projectId);
  Future<String> getRequestsDir(String projectId);
  Future<String> getEnvironmentsDir(String projectId);
  Future<String> getCookieJarDir(String projectId);
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<void> deleteFile(String path);
  Future<void> deleteDir(String path);
  Future<List<FileSystemEntity>> listFiles(String dirPath);
  Future<bool> exists(String path);
  Future<void> ensureDir(String path);
  Future<void> renameFile(String oldPath, String newPath);
  Future<String> createProjectStructure(String projectId);
  Future<void> deleteProjectDir(String projectId);
  Future<void> setWorkspaceRoot(String path);
}

class LocalFileSystemService implements FileSystemService {
  String? _customRoot;

  @override
  Future<String> getWorkspaceRoot() async {
    if (_customRoot != null) return _customRoot!;
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'curel');
  }

  @override
  Future<void> setWorkspaceRoot(String path) async {
    _customRoot = path;
    await ensureDir(path);
  }

  @override
  Future<String> getProjectDir(String projectId) async {
    final root = await getWorkspaceRoot();
    return p.join(root, 'projects', projectId);
  }

  @override
  Future<String> getRequestsDir(String projectId) async {
    final projectDir = await getProjectDir(projectId);
    return p.join(projectDir, 'requests');
  }

  @override
  Future<String> getEnvironmentsDir(String projectId) async {
    final projectDir = await getProjectDir(projectId);
    return p.join(projectDir, 'environments');
  }

  @override
  Future<String> getCookieJarDir(String projectId) async {
    final requestsDir = await getRequestsDir(projectId);
    return p.join(requestsDir, '.cookiejar');
  }

  @override
  Future<String> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('File not found', path);
    }
    return file.readAsString();
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await ensureDir(p.dirname(path));
    final file = File(path);
    await file.writeAsString(content);
  }

  @override
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> deleteDir(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<List<FileSystemEntity>> listFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    return dir.list().toList();
  }

  @override
  Future<bool> exists(String path) async {
    return await File(path).exists() || await Directory(path).exists();
  }

  @override
  Future<void> ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    final src = File(oldPath);
    if (!await src.exists()) {
      throw FileSystemException('File not found', oldPath);
    }

    await ensureDir(p.dirname(newPath));

    final dst = File(newPath);
    if (await dst.exists()) {
      throw FileSystemException('Target already exists', newPath);
    }

    await src.rename(newPath);
  }

  @override
  Future<String> createProjectStructure(String projectId) async {
    final projectDir = await getProjectDir(projectId);
    await ensureDir(projectDir);
    await ensureDir(p.join(projectDir, 'requests'));
    await ensureDir(p.join(projectDir, 'environments'));

    final curelJson = p.join(projectDir, 'curel.json');
    final meta = jsonEncode({
      'id': projectId,
      'created_at': DateTime.now().toIso8601String(),
    });
    await writeFile(curelJson, meta);

    return projectDir;
  }

  @override
  Future<void> deleteProjectDir(String projectId) async {
    final projectDir = await getProjectDir(projectId);
    await deleteDir(projectDir);
  }
}
