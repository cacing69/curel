import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyUserAgent = 'user_agent';

abstract class SettingsService {
  Future<String> getUserAgent();
  Future<String> getDefaultUserAgent();
  Future<void> setUserAgent(String value);
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
}
