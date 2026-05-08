import 'dart:convert';

import 'package:curel/domain/models/env_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _keyEnvList = 'env_list';
const _keyEnvActive = 'env_active';

final _envRegex = RegExp(r'<<([A-Za-z_][A-Za-z0-9_]*)>>');

abstract class EnvService {
  Future<List<Environment>> getAll();
  Future<Environment?> getActive();
  Future<void> setActive(String id);
  Future<Environment> create(String name);
  Future<void> save(Environment env);
  Future<void> delete(String id);
  Environment duplicate(Environment source);
  Future<String> resolve(String curlCommand);
  Future<Set<String>> findUndefinedVars(String curlCommand);
  Future<String> exportToJson();
  Future<void> importFromJson(String json);
  Future<String?> getValue(Environment env, String varKey);
  Future<void> setValue(Environment env, String varKey, String value);
}

class PreferencesEnvService implements EnvService {
  SharedPreferences? _prefs;
  final _secureStorage = const FlutterSecureStorage();

  Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<Environment>> getAll() async {
    final prefs = await _instance;
    final raw = prefs.getString(_keyEnvList);
    if (raw == null) return [];
    return Environment.decodeList(raw);
  }

  @override
  Future<Environment?> getActive() async {
    final prefs = await _instance;
    final activeId = prefs.getString(_keyEnvActive);
    if (activeId == null) return null;
    final all = await getAll();
    return all.where((e) => e.id == activeId).firstOrNull;
  }

  @override
  Future<void> setActive(String id) async {
    final prefs = await _instance;
    await prefs.setString(_keyEnvActive, id);
  }

  @override
  Future<Environment> create(String name) async {
    final env = Environment(
      id: const Uuid().v4(),
      name: name,
      variables: [],
      updatedAt: DateTime.now(),
    );
    final all = await getAll();
    all.add(env);
    await _saveAll(all);
    return env;
  }

  @override
  Future<void> save(Environment env) async {
    final all = await getAll();
    final idx = all.indexWhere((e) => e.id == env.id);
    if (idx >= 0) {
      all[idx] = env;
    } else {
      all.add(env);
    }
    await _saveAll(all);
  }

  @override
  Future<void> delete(String id) async {
    // Remove all secure values for this env
    final all = await getAll();
    final env = all.where((e) => e.id == id).firstOrNull;
    if (env != null) {
      for (final v in env.variables) {
        await _secureStorage.delete(key: env.storageKey(v.key));
      }
    }
    all.removeWhere((e) => e.id == id);
    await _saveAll(all);
    final prefs = await _instance;
    if (prefs.getString(_keyEnvActive) == id) {
      await prefs.remove(_keyEnvActive);
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
  Future<String> resolve(String curlCommand) async {
    final active = await getActive();
    if (active == null) return curlCommand;

    final varMap = <String, String>{};
    for (final v in active.variables) {
      final value = await _secureStorage.read(key: active.storageKey(v.key));
      if (value != null) varMap[v.key] = value;
    }

    return curlCommand.replaceAllMapped(_envRegex, (match) {
      final key = match.group(1)!;
      return varMap[key] ?? match.group(0)!;
    });
  }

  @override
  Future<Set<String>> findUndefinedVars(String curlCommand) async {
    final active = await getActive();
    final defined = active?.variables.map((v) => v.key).toSet() ?? {};
    final used = <String>{};
    for (final m in _envRegex.allMatches(curlCommand)) {
      used.add(m.group(1)!);
    }
    return used.difference(defined);
  }

  @override
  Future<String> exportToJson() async {
    final all = await getAll();
    final active = await getActive();
    final exportData = <Map<String, dynamic>>[];
    for (final env in all) {
      final vars = <Map<String, dynamic>>[];
      for (final v in env.variables) {
        final value = await _secureStorage.read(key: env.storageKey(v.key));
        vars.add({'key': v.key, 'value': value ?? '', 'sensitive': v.sensitive});
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
  Future<void> importFromJson(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final envList = <Environment>[];
    for (final envData in (data['environments'] as List)) {
      final e = envData as Map<String, dynamic>;
      final vars = <EnvVariable>[];
      final envId = e['id'] as String;
      for (final vData in (e['variables'] as List)) {
        final v = vData as Map<String, dynamic>;
        vars.add(EnvVariable(
          key: v['key'] as String,
          sensitive: v['sensitive'] as bool? ?? false,
        ));
        final value = v['value'] as String? ?? '';
        final storageKey = 'env_${envId}_${v['key']}';
        await _secureStorage.write(key: storageKey, value: value);
      }
      envList.add(Environment(
        id: envId,
        name: e['name'] as String,
        variables: vars,
        updatedAt: DateTime.parse(e['updated_at'] as String),
      ));
    }
    await _saveAll(envList);
    final activeId = data['active'] as String?;
    if (activeId != null) {
      await setActive(activeId);
    }
  }

  Future<void> _saveAll(List<Environment> envs) async {
    final prefs = await _instance;
    await prefs.setString(_keyEnvList, Environment.encodeList(envs));
  }
}
