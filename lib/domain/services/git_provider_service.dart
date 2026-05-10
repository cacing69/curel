import 'dart:io';

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/git_provider_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

abstract class GitProviderService {
  Future<List<GitProviderModel>> getAll();
  Future<GitProviderModel?> getById(String id);
  Future<GitProviderModel> create({
    required String name,
    required String type,
    String? baseUrl,
    required String token,
  });
  Future<void> update(GitProviderModel provider, {String? newToken});
  Future<void> delete(String id);
  Future<String?> getToken(String id);
}

class FileSystemGitProviderService implements GitProviderService {
  final FileSystemService _fs;
  final _secure = const FlutterSecureStorage();

  FileSystemGitProviderService(this._fs);

  Future<File> _getConfigFile() async {
    final root = await _fs.getWorkspaceRoot();
    final file = File(p.join(root, 'git_providers.json'));
    return file;
  }

  @override
  Future<List<GitProviderModel>> getAll() async {
    final file = await _getConfigFile();
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      return GitProviderModel.decodeList(content);
    } catch (_) {
      return [];
    }
  }

  @override
  Future<GitProviderModel?> getById(String id) async {
    final all = await getAll();
    return all.where((p) => p.id == id).firstOrNull;
  }

  @override
  Future<GitProviderModel> create({
    required String name,
    required String type,
    String? baseUrl,
    required String token,
  }) async {
    final provider = GitProviderModel(
      id: const Uuid().v4(),
      name: name,
      type: type,
      baseUrl: baseUrl,
    );

    final all = await getAll();
    all.add(provider);

    final file = await _getConfigFile();
    await file.writeAsString(GitProviderModel.encodeList(all));

    await _secure.write(key: 'git_provider_${provider.id}_token', value: token);

    return provider;
  }

  @override
  Future<void> update(GitProviderModel provider, {String? newToken}) async {
    final all = await getAll();
    final index = all.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      all[index] = provider;
      final file = await _getConfigFile();
      await file.writeAsString(GitProviderModel.encodeList(all));

      if (newToken != null && newToken.isNotEmpty) {
        await _secure.write(
            key: 'git_provider_${provider.id}_token', value: newToken);
      }
    }
  }

  @override
  Future<void> delete(String id) async {
    final all = await getAll();
    final before = all.length;
    all.removeWhere((p) => p.id == id);

    if (all.length < before) {
      final file = await _getConfigFile();
      await file.writeAsString(GitProviderModel.encodeList(all));
      await _secure.delete(key: 'git_provider_${id}_token');
    }
  }

  @override
  Future<String?> getToken(String id) async {
    return _secure.read(key: 'git_provider_${id}_token');
  }
}
