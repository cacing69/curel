import 'dart:io';

import 'package:curel/data/app_config.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/data/services/github_oauth_service.dart';
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
    String? refreshToken,
    DateTime? expiresAt,
  });
  Future<void> update(GitProviderModel provider, {String? newToken});
  Future<void> delete(String id);
  Future<String?> getToken(String id);
  Future<bool> hasToken(String id);
  Future<DateTime?> getTokenExpiresAt(String id);
}

class FileSystemGitProviderService implements GitProviderService {
  final FileSystemService _fs;
  final _secure = const FlutterSecureStorage();
  final _refreshFutures = <String, Future<String?>>{};

  FileSystemGitProviderService(this._fs);

  String _tokenKey(String id) => 'git_provider_${id}_token';
  String _refreshKey(String id) => 'git_provider_${id}_refresh_token';
  String _expiresKey(String id) => 'git_provider_${id}_expires_at';

  Future<File> _getConfigFile() async {
    final root = await _fs.getWorkspaceRoot();
    final file = File(p.join(root, 'git_providers.json'));
    return file;
  }

  Future<GitProviderModel?> _findProvider(String id) async {
    final all = await getAll();
    return all.where((p) => p.id == id).firstOrNull;
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
    return _findProvider(id);
  }

  @override
  Future<GitProviderModel> create({
    required String name,
    required String type,
    String? baseUrl,
    required String token,
    String? refreshToken,
    DateTime? expiresAt,
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

    await _writeToken(provider.id, token,
        refreshToken: refreshToken, expiresAt: expiresAt);

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
        await _writeToken(provider.id, newToken);
      }
    }
  }

  @override
  Future<void> delete(String id) async {
    final provider = await _findProvider(id);
    if (provider == null) return;

    if (provider.type == 'github') {
      final token = await getToken(id);
      if (token != null) {
        final oauth = GitHubOAuthService(
          clientId: curelGitHubClientId,
          clientSecret:
              curelGitHubClientSecret.isNotEmpty ? curelGitHubClientSecret : null,
        );
        await oauth.revokeToken(token);
      }
    }

    final all = await getAll();
    all.removeWhere((p) => p.id == id);

    final file = await _getConfigFile();
    await file.writeAsString(GitProviderModel.encodeList(all));
    await _secure.delete(key: _tokenKey(id));
    await _secure.delete(key: _refreshKey(id));
    await _secure.delete(key: _expiresKey(id));
  }

  @override
  Future<String?> getToken(String id) async {
    final accessToken = await _secure.read(key: _tokenKey(id));
    if (accessToken == null) return null;

    final refreshToken = await _secure.read(key: _refreshKey(id));
    final expiresAtStr = await _secure.read(key: _expiresKey(id));

    if (refreshToken != null && expiresAtStr != null) {
      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        return _refresh(id, refreshToken);
      }
    }

    return accessToken;
  }

  Future<String?> _refresh(String id, String refreshToken) async {
    final existing = _refreshFutures[id];
    if (existing != null) return existing;

    final future = _doRefresh(id, refreshToken);
    _refreshFutures[id] = future;

    try {
      return await future;
    } finally {
      _refreshFutures.remove(id);
    }
  }

  Future<String?> _doRefresh(String id, String refreshToken) async {
    final provider = await _findProvider(id);
    if (provider == null) return null;

    if (provider.type == 'github') {
      try {
        final oauth = GitHubOAuthService(clientId: curelGitHubClientId);
        final result = await oauth.refreshToken(refreshToken);
        if (!result.isError && result.accessToken != null) {
          await _writeToken(id, result.accessToken!,
              refreshToken: result.refreshToken,
              expiresAt: result.expiresIn != null
                  ? DateTime.now().add(Duration(seconds: result.expiresIn!))
                  : null);
          return result.accessToken;
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  @override
  Future<bool> hasToken(String id) async {
    return _secure.containsKey(key: _tokenKey(id));
  }

  @override
  Future<DateTime?> getTokenExpiresAt(String id) async {
    final str = await _secure.read(key: _expiresKey(id));
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> _writeToken(String id, String token,
      {String? refreshToken, DateTime? expiresAt}) async {
    await _secure.write(key: _tokenKey(id), value: token);
    if (refreshToken != null) {
      await _secure.write(key: _refreshKey(id), value: refreshToken);
    }
    if (expiresAt != null) {
      await _secure.write(
          key: _expiresKey(id), value: expiresAt.toIso8601String());
    }
  }
}
