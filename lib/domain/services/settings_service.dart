import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyUserAgent = 'user_agent';
const _keyConnectTimeout = 'connect_timeout';
const _keyMaxTime = 'max_time';

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
}

class PreferencesSettingsService implements SettingsService {
  SharedPreferences? _prefs;

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
}
