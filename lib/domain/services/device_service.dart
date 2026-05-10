import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceService {
  static const _salt = "curel-salt-2026";
  String? _cachedFingerprint;

  Future<String> getFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final deviceInfo = DeviceInfoPlugin();
    String rawId = 'unknown';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        rawId = iosInfo.identifierForVendor ?? 'ios-unknown';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        rawId = macInfo.systemGUID ?? 'macos-unknown';
      }
    } catch (_) {
      rawId = 'unknown';
    }

    // Hash the ID to make it anonymous but consistent (like a git commit SHA)
    final bytes = utf8.encode(rawId + _salt);
    final digest = sha256.convert(bytes);
    
    _cachedFingerprint = digest.toString().substring(0, 7);
    return _cachedFingerprint!;
  }
}
