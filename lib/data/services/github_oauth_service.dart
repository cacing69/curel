import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DeviceFlowResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  DeviceFlowResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
}

class OAuthTokenResponse {
  final String? accessToken;
  final String? refreshToken;
  final int? expiresIn;
  final String? scope;
  final String? error;
  final String? errorDescription;

  OAuthTokenResponse({
    this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.scope,
    this.error,
    this.errorDescription,
  });

  bool get isError => error != null;
}

class GitHubOAuthService {
  final HttpClient _client = HttpClient();
  final String clientId;
  final String? clientSecret;

  GitHubOAuthService({required this.clientId, this.clientSecret}) {
    _client.connectionTimeout = Duration(seconds: 10);
  }

  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> data, {Map<String, String>? headers}) async {
    final uri = Uri.parse(url);
    final req = await _client.postUrl(uri);
    req.headers.set('Accept', 'application/json');
    req.headers.set('Content-Type', 'application/json');
    if (headers != null) headers.forEach((k, v) => req.headers.set(k, v));
    req.write(jsonEncode(data));
    final resp = await req.close().timeout(Duration(seconds: 15));
    final body = await resp.transform(utf8.decoder).join();
    return _parseJsonMap(body);
  }

  Future<Map<String, dynamic>> _delete(String url, Map<String, dynamic> data, {Map<String, String>? headers}) async {
    final uri = Uri.parse(url);
    final req = await _client.deleteUrl(uri);
    req.headers.set('Accept', 'application/json');
    req.headers.set('Content-Type', 'application/json');
    if (headers != null) headers.forEach((k, v) => req.headers.set(k, v));
    req.write(jsonEncode(data));
    final resp = await req.close().timeout(Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    return _parseJsonMap(body);
  }

  Future<DeviceFlowResponse> startDeviceFlow() async {
    final data = await _post('https://github.com/login/device/code', {
      'client_id': clientId,
      'scope': 'repo',
    });

    return DeviceFlowResponse(
      deviceCode: data['device_code'],
      userCode: data['user_code'],
      verificationUri: data['verification_uri'] ?? 'https://github.com/login/device',
      expiresIn: data['expires_in'] ?? 900,
      interval: data['interval'] ?? 5,
    );
  }

  Future<OAuthTokenResponse> pollForToken(
    String deviceCode, {
    required int interval,
    required int expiresIn,
  }) async {
    final endTime = DateTime.now().add(Duration(seconds: expiresIn));

    while (DateTime.now().isBefore(endTime)) {
      await Future.delayed(Duration(seconds: interval));

      try {
        final data = await _post('https://github.com/login/oauth/access_token', {
          'client_id': clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        });

        if (data.containsKey('access_token')) {
          return OAuthTokenResponse(
            accessToken: data['access_token'],
            refreshToken: data['refresh_token'],
            expiresIn: data['expires_in'],
            scope: data['scope'],
          );
        }

        final error = data['error'] as String?;

        switch (error) {
          case 'authorization_pending':
            break;
          case 'slow_down':
            interval += 5;
            break;
          case 'expired_token':
            return OAuthTokenResponse(
              error: error,
              errorDescription: 'device code expired. please try again.',
            );
          case 'access_denied':
            return OAuthTokenResponse(
              error: error,
              errorDescription: 'authorization cancelled.',
            );
          case null:
            break;
          default:
            return OAuthTokenResponse(
              error: error,
              errorDescription: data['error_description'],
            );
        }
      } catch (_) {
        interval = (interval * 1.5).round().clamp(5, 60);
      }
    }

    return OAuthTokenResponse(
      error: 'timeout',
      errorDescription: 'authorization timed out. please try again.',
    );
  }

  Future<bool> revokeToken(String accessToken) async {
    if (clientSecret == null || clientSecret!.isEmpty) return false;

    try {
      final credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));
      final resp = await _client.deleteUrl(Uri.parse(
          'https://api.github.com/applications/$clientId/token'));
      resp.headers.set('Authorization', 'Basic $credentials');
      resp.headers.set('Accept', 'application/json');
      resp.headers.set('Content-Type', 'application/json');
      resp.write(jsonEncode({'access_token': accessToken}));
      final response = await resp.close().timeout(Duration(seconds: 10));
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<OAuthTokenResponse> refreshToken(String refreshToken) async {
    try {
      final data = await _post('https://github.com/login/oauth/access_token', {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      });

      return OAuthTokenResponse(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
        expiresIn: data['expires_in'],
        scope: data['scope'],
      );
    } catch (e) {
      return OAuthTokenResponse(
        error: 'refresh_error',
        errorDescription: '$e',
      );
    }
  }

  Map<String, dynamic> _parseJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return {};
  }
}
