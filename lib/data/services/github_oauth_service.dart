import 'dart:async';

import 'package:dio/dio.dart';

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
  final Dio _client = Dio();
  final String clientId;

  GitHubOAuthService({required this.clientId});

  Future<DeviceFlowResponse> startDeviceFlow() async {
    final response = await _client.post(
      'https://github.com/login/device/code',
      options: Options(headers: {'Accept': 'application/json'}),
      data: {
        'client_id': clientId,
        'scope': 'repo',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('failed to start device flow: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
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

      final response = await _client.post(
        'https://github.com/login/oauth/access_token',
        options: Options(headers: {'Accept': 'application/json'}),
        data: {
          'client_id': clientId,
          'device_code': deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('token polling failed: ${response.statusCode}');
      }

      final data = response.data as Map<String, dynamic>;

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
    }

    return OAuthTokenResponse(
      error: 'timeout',
      errorDescription: 'authorization timed out. please try again.',
    );
  }

  Future<OAuthTokenResponse> refreshToken(String refreshToken) async {
    final response = await _client.post(
      'https://github.com/login/oauth/access_token',
      options: Options(headers: {'Accept': 'application/json'}),
      data: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('token refresh failed: ${response.statusCode}');
    }

    final data = response.data as Map<String, dynamic>;
    return OAuthTokenResponse(
      accessToken: data['access_token'],
      refreshToken: data['refresh_token'],
      expiresIn: data['expires_in'],
      scope: data['scope'],
    );
  }
}
