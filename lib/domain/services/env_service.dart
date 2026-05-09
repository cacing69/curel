import 'dart:convert';
import 'dart:io' as dart_io;

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/env_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _keyEnvList = 'env_list';
const _keyEnvActive = 'env_active';
const _keyProjectEnvActivePrefix = 'env_active_project_';

final _envRegex = RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>');

abstract class EnvService {
  Future<List<Environment>> getAll(String? projectId);
  Future<Environment?> getActive(String? projectId);
  Future<void> setActive(String? projectId, String id);
  Future<Environment> create(String? projectId, String name);
  Future<void> save(String? projectId, Environment env);
  Future<void> delete(String? projectId, String id);
  Environment duplicate(Environment source);
  Future<String> resolve(String curlCommand, {String? projectId});
  Future<Set<String>> findUndefinedVars(
    String curlCommand, {
    String? projectId,
  });
  Future<String> exportToJson(String? projectId);
  Future<void> importFromJson(String? projectId, String json);
  Future<String?> getValue(Environment env, String varKey);
  Future<void> setValue(Environment env, String varKey, String value);
}

class FileSystemEnvService implements EnvService {
  final FileSystemService _fs;
  final _secureStorage = const FlutterSecureStorage();
  final SharedPreferences? _prefs; // Keep for migration and active ID

  FileSystemEnvService(this._fs, {SharedPreferences? prefs}) : _prefs = prefs {
    _migrateFromPrefs();
  }

  Future<void> _migrateFromPrefs() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyEnvList);
    if (raw != null) {
      try {
        final envs = Environment.decodeList(raw);
        for (final env in envs) {
          await save(null, env);
        }
        await prefs.remove(_keyEnvList);
      } catch (_) {}
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<String> _getGlobalEnvDir() async {
    final docDir = await _fs.getEnvironmentsDir('.global');
    return docDir;
  }

  // ── Public API ────────────────────────────────────────────────────

  @override
  Future<List<Environment>> getAll(String? projectId) async {
    final envDir = projectId != null
        ? await _fs.getEnvironmentsDir(projectId)
        : await _getGlobalEnvDir();

    if (!await _fs.exists(envDir)) return [];

    final entities = await _fs.listFiles(envDir);
    final envs = <Environment>[];
    for (final entity in entities) {
      if (entity is! dart_io.File || !entity.path.endsWith('.json')) continue;
      try {
        final content = await _fs.readFile(entity.path);
        final json = jsonDecode(content) as Map<String, dynamic>;
        envs.add(_envFromProjectJson(json));
      } catch (_) {}
    }
    return envs;
  }

  Environment _envFromProjectJson(Map<String, dynamic> json) {
    final vars = <EnvVariable>[];
    for (final v in (json['variables'] as List)) {
      final vMap = v as Map<String, dynamic>;
      vars.add(
        EnvVariable(
          key: vMap['key'] as String,
          sensitive: vMap['sensitive'] as bool? ?? false,
        ),
      );
    }
    return Environment(
      id: json['id'] as String,
      name: json['name'] as String,
      variables: vars,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  @override
  Future<Environment?> getActive(String? projectId) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final key = projectId != null
        ? '$_keyProjectEnvActivePrefix$projectId'
        : _keyEnvActive;
    final activeId = prefs.getString(key);
    if (activeId == null) return null;
    final all = await getAll(projectId);
    return all.where((e) => e.id == activeId).firstOrNull;
  }

  @override
  Future<void> setActive(String? projectId, String id) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final key = projectId != null
        ? '$_keyProjectEnvActivePrefix$projectId'
        : _keyEnvActive;
    await prefs.setString(key, id);
  }

  @override
  Future<Environment> create(String? projectId, String name) async {
    final env = Environment(
      id: const Uuid().v4(),
      name: name,
      variables: [],
      updatedAt: DateTime.now(),
    );
    await save(projectId, env);
    return env;
  }

  @override
  Future<void> save(String? projectId, Environment env) async {
    final envDir = projectId != null
        ? await _fs.getEnvironmentsDir(projectId)
        : await _getGlobalEnvDir();

    final fileName = '${_sanitizeName(env.name)}.json';
    final filePath = p.join(envDir, fileName);

    final vars = <Map<String, dynamic>>[];
    for (final v in env.variables) {
      final value = await _secureStorage.read(key: env.storageKey(v.key));
      vars.add({'key': v.key, 'value': value ?? '', 'sensitive': v.sensitive});
    }

    final json = jsonEncode({
      'id': env.id,
      'name': env.name,
      'variables': vars,
      'updated_at': env.updatedAt.toIso8601String(),
    });
    await _fs.writeFile(filePath, json);
  }

  @override
  Future<void> delete(String? projectId, String id) async {
    final all = await getAll(projectId);
    final env = all.where((e) => e.id == id).firstOrNull;
    if (env != null) {
      for (final v in env.variables) {
        await _secureStorage.delete(key: env.storageKey(v.key));
      }

      final envDir = projectId != null
          ? await _fs.getEnvironmentsDir(projectId)
          : await _getGlobalEnvDir();
      final envFile = p.join(envDir, '${_sanitizeName(env.name)}.json');
      if (await _fs.exists(envFile)) {
        await _fs.deleteFile(envFile);
      }
    }

    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final key = projectId != null
        ? '$_keyProjectEnvActivePrefix$projectId'
        : _keyEnvActive;
    if (prefs.getString(key) == id) {
      await prefs.remove(key);
    }
  }

  @override
  Environment duplicate(Environment source) {
    return Environment(
      id: const Uuid().v4(),
      name: '${source.name} (copy)',
      variables: List.from(source.variables),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<String?> getValue(Environment env, String varKey) async {
    return _secureStorage.read(key: env.storageKey(varKey));
  }

  @override
  Future<void> setValue(Environment env, String varKey, String value) async {
    await _secureStorage.write(key: env.storageKey(varKey), value: value);
  }

  @override
  Future<String> resolve(String curlCommand, {String? projectId}) async {
    final varMap = <String, String>{};

    // Layer 1: global env
    final globalActive = await getActive(null);
    if (globalActive != null) {
      for (final v in globalActive.variables) {
        final value = await _secureStorage.read(
          key: globalActive.storageKey(v.key),
        );
        if (value != null) varMap[v.key] = value;
      }
    }

    // Layer 2: project env overrides global
    if (projectId != null) {
      final projectActive = await getActive(projectId);
      if (projectActive != null) {
        for (final v in projectActive.variables) {
          final value = await _secureStorage.read(
            key: projectActive.storageKey(v.key),
          );
          if (value != null) varMap[v.key] = value;
        }
      }
    }

    return curlCommand.replaceAllMapped(_envRegex, (match) {
      final key = match.group(1)!;
      return varMap[key] ?? match.group(0)!;
    });
  }

  @override
  Future<Set<String>> findUndefinedVars(
    String curlCommand, {
    String? projectId,
  }) async {
    final defined = <String>{};

    // Global env keys
    final globalActive = await getActive(null);
    if (globalActive != null) {
      defined.addAll(globalActive.variables.map((v) => v.key));
    }

    // Project env keys
    if (projectId != null) {
      final projectActive = await getActive(projectId);
      if (projectActive != null) {
        defined.addAll(projectActive.variables.map((v) => v.key));
      }
    }

    final used = <String>{};
    for (final m in _envRegex.allMatches(curlCommand)) {
      used.add(m.group(1)!);
    }
    return used.difference(defined);
  }

  @override
  Future<String> exportToJson(String? projectId) async {
    final all = await getAll(projectId);
    final active = await getActive(projectId);
    final exportData = <Map<String, dynamic>>[];
    for (final env in all) {
      final vars = <Map<String, dynamic>>[];
      for (final v in env.variables) {
        final value = await _secureStorage.read(key: env.storageKey(v.key));
        vars.add({
          'key': v.key,
          'value': value ?? '',
          'sensitive': v.sensitive,
        });
      }
      exportData.add({
        'id': env.id,
        'name': env.name,
        'variables': vars,
        'updated_at': env.updatedAt.toIso8601String(),
      });
    }
    return jsonEncode({
      'version': 2,
      'active': active?.id,
      'environments': exportData,
    });
  }

  @override
  Future<void> importFromJson(String? projectId, String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final envList = <Environment>[];
    for (final envData in (data['environments'] as List)) {
      final e = envData as Map<String, dynamic>;
      final vars = <EnvVariable>[];
      final envId = e['id'] as String;
      for (final vData in (e['variables'] as List)) {
        final v = vData as Map<String, dynamic>;
        vars.add(
          EnvVariable(
            key: v['key'] as String,
            sensitive: v['sensitive'] as bool? ?? false,
          ),
        );
        final value = v['value'] as String? ?? '';
        final storageKey = 'env_${envId}_${v['key']}';
        await _secureStorage.write(key: storageKey, value: value);
      }
      envList.add(
        Environment(
          id: envId,
          name: e['name'] as String,
          variables: vars,
          updatedAt: DateTime.parse(e['updated_at'] as String),
        ),
      );
    }

    for (final env in envList) {
      await save(projectId, env);
    }

    final activeId = data['active'] as String?;
    if (activeId != null) {
      await setActive(projectId, activeId);
    }
  }

  String _sanitizeName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
