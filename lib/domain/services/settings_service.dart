import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _keyUserAgent = 'user_agent';
const _keyConnectTimeout = 'connect_timeout';
const _keyMaxTime = 'max_time';
const _keyWorkspacePath = 'workspace_path';

const defaultConnectTimeout = 30;
const defaultMaxTime = 0;

abstract class SettingsService {
  Future<String> getUserAgent();
  Future<String> getDefaultUserAgent();
  Future<void> setUserAgent(String value);
  Future<int> getConnectTimeout();
  Future<void> setConnectTimeout(int? value);
  Future<int> getMaxTime();
  Future<void> setMaxTime(int? value);
  Future<String?> getWorkspacePath();
  Future<String> getEffectiveWorkspacePath();
  Future<void> setWorkspacePath(String? value);
  Future<void> clearWorkspacePath();
}

class PreferencesSettingsService implements SettingsService {
  SharedPreferences? _prefs;
  final _secure = const FlutterSecureStorage();

  Future<SharedPreferences> get _instance async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String> getDefaultUserAgent() async {
    final info = await PackageInfo.fromPlatform();
    return 'Curel/${info.version}';
  }

  @override
  Future<String> getUserAgent() async {
    final prefs = await _instance;
    final custom = prefs.getString(_keyUserAgent);
    if (custom != null && custom.isNotEmpty) return custom;
    return getDefaultUserAgent();
  }

  @override
  Future<void> setUserAgent(String value) async {
    final prefs = await _instance;
    if (value.isEmpty) {
      await prefs.remove(_keyUserAgent);
    } else {
      await prefs.setString(_keyUserAgent, value);
    }
  }

  @override
  Future<int> getConnectTimeout() async {
    final prefs = await _instance;
    return prefs.getInt(_keyConnectTimeout) ?? defaultConnectTimeout;
  }

  @override
  Future<void> setConnectTimeout(int? value) async {
    final prefs = await _instance;
    if (value == null || value <= 0) {
      await prefs.remove(_keyConnectTimeout);
    } else {
      await prefs.setInt(_keyConnectTimeout, value);
    }
  }

  @override
  Future<int> getMaxTime() async {
    final prefs = await _instance;
    return prefs.getInt(_keyMaxTime) ?? defaultMaxTime;
  }

  @override
  Future<void> setMaxTime(int? value) async {
    final prefs = await _instance;
    if (value == null || value <= 0) {
      await prefs.remove(_keyMaxTime);
    } else {
      await prefs.setInt(_keyMaxTime, value);
    }
  }

  @override
  Future<String?> getWorkspacePath() async {
    final prefs = await _instance;
    return prefs.getString(_keyWorkspacePath);
  }

  @override
  Future<String> getEffectiveWorkspacePath() async {
    final custom = await getWorkspacePath();
    if (custom != null && custom.isNotEmpty) return custom;
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'curel');
  }

  @override
  Future<void> setWorkspacePath(String? value) async {
    final prefs = await _instance;
    if (value == null || value.isEmpty) {
      await prefs.remove(_keyWorkspacePath);
    } else {
      await prefs.setString(_keyWorkspacePath, value);
    }
  }

  @override
  Future<void> clearWorkspacePath() async {
    final prefs = await _instance;
    await prefs.remove(_keyWorkspacePath);
  }
}
