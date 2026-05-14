import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'package:curel/data/services/curl_native_bindings.dart';

final _bufs = <int, List<int>>{};

int _writeCallback(Pointer<Uint8> data, int size, int nmemb, Pointer<Void> userdata) {
  final total = size * nmemb;
  final id = userdata.address;
  _bufs.putIfAbsent(id, () => []).addAll(data.asTypedList(total));
  return total;
}

int _debugCallback(Pointer<Void> handle, int type, Pointer<Uint8> data, int size, Pointer<Void> userdata) {
  final ctx = userdata.address;
  final verboseId = ctx >> 32;
  final traceId = ctx & 0xFFFFFFFF;
  final bytes = data.asTypedList(size);
  _bufs.putIfAbsent(traceId, () => []).addAll(bytes);
  if (type <= 2) {
    _bufs.putIfAbsent(verboseId, () => []).addAll(bytes);
  }
  return 0;
}

String _formatHex(List<int> bytes) {
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i += 16) {
    final hex = <String>[];
    final ascii = StringBuffer();
    for (var j = 0; j < 16 && i + j < bytes.length; j++) {
      final b = bytes[i + j];
      hex.add(b.toRadixString(16).padLeft(2, '0'));
      ascii.write(b >= 32 && b <= 126 ? String.fromCharCode(b) : '.');
    }
    buf.write(i.toRadixString(16).padLeft(4, '0'));
    buf.write(': ');
    buf.write(hex.join(' ').padRight(48));
    buf.write('  ');
    buf.writeln(ascii.toString());
  }
  return buf.toString();
}

void _setoptInt(CurlLibrary curl, CURL easy, int option, int value) {
  final ptr = calloc<Int32>()..value = value;
  curl.easySetopt(easy, option, ptr.cast<NativeType>());
  calloc.free(ptr);
}

class CurlIsolateResult {
  final int? statusCode;
  final String? statusMessage;
  final Map<String, List<String>> headers;
  final String? body;
  final String? verboseLog;
  final String? traceLog;
  final int elapsedMs;
  final String? error;

  CurlIsolateResult({
    this.statusCode,
    this.statusMessage,
    this.headers = const {},
    this.body,
    this.verboseLog,
    this.traceLog,
    this.elapsedMs = 0,
    this.error,
  });
}

class CurlIsolateArgs {
  final String url;
  final String method;
  final Map<String, String> headers;
  final String? data;
  final String? caBundlePath;
  final bool verbose;
  final bool trace;
  final bool followRedirects;
  final int? connectTimeoutMs;
  final int? maxTimeMs;
  final bool insecure;
  final String? userAgent;
  final String? pinnedpubkey;

  CurlIsolateArgs({
    required this.url,
    required this.method,
    this.headers = const {},
    this.data,
    this.caBundlePath,
    this.verbose = false,
    this.trace = false,
    this.followRedirects = false,
    this.connectTimeoutMs,
    this.maxTimeMs,
    this.insecure = false,
    this.userAgent,
    this.pinnedpubkey,
  });
}

Future<CurlIsolateResult> runCurlInIsolate(CurlIsolateArgs args) {
  return Isolate.run(() => _isolateEntry(args));
}

CurlIsolateResult _isolateEntry(CurlIsolateArgs args) {
  final curl = CurlLibrary();
  curl.load();
  final easy = curl.easyInit();
  if (easy == nullptr) return CurlIsolateResult(error: 'curl_easy_init() failed');

  final bodyId = 1;
  final headerId = 2;
  final verboseId = 3;
  final traceId = 4;
  _bufs[bodyId] = [];
  _bufs[headerId] = [];
  _bufs[verboseId] = [];
  _bufs[traceId] = [];

  int statusCode = 0;
  int totalMs = 0;

  try {
    final urlStr = args.url.toNativeUtf8();
    curl.easySetopt(easy, CURLOPT_URL, urlStr.cast());

    if (args.method != 'GET') {
      final m = args.method.toNativeUtf8();
      curl.easySetopt(easy, CURLOPT_CUSTOMREQUEST, m.cast());
    }

    final hdrs = <String, dynamic>{...args.headers};
    if (args.userAgent != null && args.userAgent!.isNotEmpty &&
        !hdrs.containsKey('User-Agent')) {
      hdrs['User-Agent'] = args.userAgent;
    }
    Pointer<Void> hdrList = nullptr;
    for (final e in hdrs.entries) {
      final h = '${e.key}: ${e.value}'.toNativeUtf8();
      hdrList = curl.slistAppend(hdrList, h);
    }
    if (hdrList != nullptr) {
      curl.easySetopt(easy, CURLOPT_HTTPHEADER, hdrList.cast<NativeType>());
    }

    if (args.data != null && args.data!.isNotEmpty) {
      final bytes = utf8.encode(args.data!);
      final ptr = calloc<Uint8>(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      curl.easySetopt(easy, CURLOPT_POSTFIELDS, ptr.cast<NativeType>());
      _setoptInt(curl, easy, CURLOPT_POSTFIELDSIZE, bytes.length);
    }

    if (args.caBundlePath != null) {
      final caPath = args.caBundlePath!.toNativeUtf8();
      curl.easySetopt(easy, CURLOPT_CAINFO, caPath.cast<NativeType>());
    }
    if (args.insecure) {
      _setoptInt(curl, easy, CURLOPT_SSL_VERIFYPEER, 0);
      _setoptInt(curl, easy, CURLOPT_SSL_VERIFYHOST, 0);
    }
    if (args.pinnedpubkey != null && args.pinnedpubkey!.isNotEmpty) {
      final pk = args.pinnedpubkey!.toNativeUtf8();
      curl.easySetopt(easy, CURLOPT_PINNEDPUBLICKEY, pk.cast<NativeType>());
    }

    if (args.followRedirects) _setoptInt(curl, easy, CURLOPT_FOLLOWLOCATION, 1);
    if (args.connectTimeoutMs != null) {
      _setoptInt(curl, easy, CURLOPT_CONNECTTIMEOUT_MS, args.connectTimeoutMs!);
    }
    if (args.maxTimeMs != null) {
      _setoptInt(curl, easy, CURLOPT_TIMEOUT_MS, args.maxTimeMs!);
    }

    if (args.verbose || args.trace) {
      _setoptInt(curl, easy, CURLOPT_VERBOSE, 1);
      final debugCtx = (verboseId << 32) | traceId;
      final debugPtr = Pointer.fromFunction<CurlDebugCallbackNative>(_debugCallback, 0);
      curl.easySetopt(easy, CURLOPT_DEBUGFUNCTION, debugPtr.cast<NativeType>());
      curl.easySetopt(easy, CURLOPT_DEBUGDATA, Pointer<Void>.fromAddress(debugCtx).cast());
    }

    final writePtr = Pointer.fromFunction<CurlWriteCallbackNative>(_writeCallback, 0);
    curl.easySetopt(easy, CURLOPT_WRITEFUNCTION, writePtr.cast<NativeType>());
    curl.easySetopt(easy, CURLOPT_WRITEDATA, Pointer<Void>.fromAddress(bodyId).cast());
    final headerPtr = Pointer.fromFunction<CurlWriteCallbackNative>(_writeCallback, 0);
    curl.easySetopt(easy, CURLOPT_HEADERFUNCTION, headerPtr.cast());
    curl.easySetopt(easy, CURLOPT_HEADERDATA, Pointer<Void>.fromAddress(headerId).cast());

    final sw = Stopwatch()..start();
    final code = curl.easyPerform(easy);
    sw.stop();

    final statusPtr = calloc<Int64>();
    curl.easyGetinfo(easy, CURLINFO_RESPONSE_CODE, statusPtr.cast<NativeType>());
    statusCode = statusPtr.value;
    final timePtr = calloc<Double>();
    curl.easyGetinfo(easy, CURLINFO_TOTAL_TIME, timePtr.cast<NativeType>());
    totalMs = (timePtr.value * 1000).round();

    final headerText = utf8.decode(_bufs[headerId] ?? [], allowMalformed: true);
    final responseHeaders = <String, List<String>>{};
    for (final line in headerText.split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        responseHeaders.putIfAbsent(line.substring(0, colon).trim(),
            () => []).add(line.substring(colon + 1).trim());
      }
    }

    final bodyStr = utf8.decode(_bufs[bodyId] ?? [], allowMalformed: true);
    final ok = code == CURLE_OK;
    final elapsedMs = ok ? totalMs : sw.elapsedMilliseconds;
    final verboseLogStr = args.verbose && _bufs[verboseId]!.isNotEmpty
        ? utf8.decode(_bufs[verboseId]!, allowMalformed: true)
        : null;
    final traceLogStr = args.trace && _bufs[traceId]!.isNotEmpty
        ? _formatHex(_bufs[traceId]!)
        : null;

    return CurlIsolateResult(
      statusCode: ok ? statusCode : 0,
      statusMessage: ok ? 'OK' : curl.easyStrerror(code).toDartString(),
      headers: responseHeaders,
      body: bodyStr.isNotEmpty ? bodyStr : null,
      verboseLog: verboseLogStr,
      traceLog: traceLogStr,
      elapsedMs: elapsedMs,
    );
  } catch (e) {
    return CurlIsolateResult(error: e.toString());
  } finally {
    curl.easyCleanup(easy);
    _bufs.remove(bodyId);
    _bufs.remove(headerId);
    _bufs.remove(verboseId);
    _bufs.remove(traceId);
  }
}
