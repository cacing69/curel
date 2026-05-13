import 'dart:async';

import 'package:curel/domain/models/captured_request.dart';
import 'package:flutter/services.dart';

class TrafficCaptureService {
  static const _channel = MethodChannel('curel/traffic_capture');

  final _controller = StreamController<List<CapturedRequest>>.broadcast();
  bool _listening = false;

  Stream<List<CapturedRequest>> get requests => _controller.stream;

  TrafficCaptureService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onCapturedRequests':
        final batches = call.arguments as List<dynamic>;
        final requests = <CapturedRequest>[];
        for (final batch in batches) {
          for (final item in batch as List<dynamic>) {
            requests.add(CapturedRequest.fromMap(
                Map<String, dynamic>.from(item as Map)));
          }
        }
        if (requests.isNotEmpty) {
          _controller.add(requests);
        }
        return null;
      default:
        throw MissingPluginException();
    }
  }

  Future<bool> startCapture() async {
    final result = await _channel.invokeMethod('startCapture');
    if (result == 'preparing') {
      return false;
    }
    _listening = true;
    return true;
  }

  Future<void> stopCapture() async {
    await _channel.invokeMethod('stopCapture');
    _listening = false;
  }

  Future<bool> isCapturing() async {
    return await _channel.invokeMethod<bool>('isCapturing') ?? false;
  }

  Future<bool> installRootCa() async {
    try {
      final result = await _channel.invokeMethod<String>('installRootCa');
      return result != null && result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<String?> installRootCaResult() async {
    try {
      return await _channel.invokeMethod<String>('installRootCa');
    } catch (e) {
      return 'error: $e';
    }
  }

  Future<bool> isCertReady() async {
    return await _channel.invokeMethod<bool>('isCertReady') ?? false;
  }

  void dispose() {
    _controller.close();
  }
}
