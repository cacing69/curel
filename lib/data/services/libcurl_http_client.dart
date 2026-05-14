import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:curel/data/models/curl_response.dart';
import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/data/services/curl_isolate.dart';
import 'package:curel/data/services/curl_native_bindings.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curl_parser/curl_parser.dart' as cp;

// ── Global callback registry (must be top-level for FFI) ────

final _bufs = HashMap<int, List<int>>();
int _nextId = 1;

int _writeCallback(Pointer<Uint8> data, int size, int nmemb, Pointer<Void> userdata) {
  final total = size * nmemb;
  final id = userdata.address;
  _bufs.putIfAbsent(id, () => []).addAll(data.asTypedList(total));
  return total;
}

int _debugCallback(
    Pointer<Void> handle, int type, Pointer<Uint8> data, int size, Pointer<Void> userdata) {
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

// ── Client ───────────────────────────────────────────────────

class LibcurlHttpClient implements CurlHttpClient {
  final CurlLibrary _curl = CurlLibrary();
  var _userAgent = '';

  static String? caBundlePath;

  @override
  void setUserAgent(String value) => _userAgent = value;

  void ensureLoaded() {
    if (!_curl.isLoaded) _curl.load();
  }

  @override
  Future<CurlResponse> execute(
    cp.Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(curl,
      verbose: verbose, followRedirects: followRedirects,
      trace: trace, traceAscii: traceAscii,
      connectTimeout: connectTimeout, maxTime: maxTime,
      insecure: insecure, pinnedpubkey: null);

  @override
  Future<CurlResponse> executeBinary(
    cp.Curl curl, {
    bool verbose = false,
    bool followRedirects = false,
    bool trace = false,
    bool traceAscii = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? httpVersion,
  }) => _doRequest(curl,
      verbose: verbose, followRedirects: followRedirects,
      trace: trace, traceAscii: traceAscii,
      connectTimeout: connectTimeout, maxTime: maxTime,
      insecure: insecure, pinnedpubkey: null);

  @override
  Future<CurlResponse?> executeRaw(String curlCommand, {
    bool verbose = false,
    bool trace = false,
    bool traceAscii = false,
  }) async {
    final parsed = parseCurl(curlCommand);
    final flags = _extractFlagValues(curlCommand);
    return _doRequest(parsed.curl,
        verbose: verbose || parsed.verbose,
        trace: trace || parsed.traceEnabled,
        traceAscii: traceAscii || parsed.traceAscii,
        followRedirects: parsed.followRedirects,
        connectTimeout: parsed.connectTimeout,
        maxTime: parsed.maxTime,
        insecure: parsed.insecure,
        pinnedpubkey: flags['pinnedpubkey']);
  }

  Future<CurlResponse> _doRequest(
    cp.Curl curl, {
    bool verbose = false,
    bool trace = false,
    bool traceAscii = false,
    bool followRedirects = false,
    Duration? connectTimeout,
    Duration? maxTime,
    bool insecure = false,
    String? pinnedpubkey,
  }) async {
    ensureLoaded();

    final useIsolate = true;
    if (useIsolate) {
      try {
        final result = await runCurlInIsolate(CurlIsolateArgs(
          url: curl.uri.toString(),
          method: curl.method,
          headers: curl.headers != null
              ? curl.headers!.map((k, v) => MapEntry(k, v.toString()))
              : {},
          data: curl.data,
          caBundlePath: caBundlePath,
          verbose: verbose,
          trace: trace,
          followRedirects: followRedirects,
          connectTimeoutMs: connectTimeout?.inMilliseconds,
          maxTimeMs: maxTime?.inMilliseconds,
          insecure: insecure,
          userAgent: _userAgent.isNotEmpty ? _userAgent : null,
          pinnedpubkey: pinnedpubkey,
        ));

        if (result.error == null) {
          return CurlResponse(
            statusCode: result.statusCode ?? 0,
            statusMessage: result.statusMessage ?? '',
            headers: result.headers,
            body: result.body,
            verboseLog: result.verboseLog,
            traceLog: result.traceLog,
            executionTime: Duration(milliseconds: result.elapsedMs),
          );
        }
      } catch (_) {
        // isolate failed, fall through to synchronous path
      }
    }

    final easy = _curl.easyInit();
    if (easy == nullptr) throw Exception('curl_easy_init() failed');

    final bodyId = _nextId++;
    final headerId = _nextId++;
    final verboseId = _nextId++;
    final traceId = _nextId++;
    _bufs[bodyId] = [];
    _bufs[headerId] = [];
    _bufs[verboseId] = [];
    _bufs[traceId] = [];

    try {
      // URL
      final urlStr = curl.uri.toString().toNativeUtf8();
      _curl.easySetopt(easy, CURLOPT_URL, urlStr.cast());

      // Method
      if (curl.method != 'GET') {
        final m = curl.method.toNativeUtf8();
        _curl.easySetopt(easy, CURLOPT_CUSTOMREQUEST, m.cast());
      }

      // Headers
      final headers = <String, dynamic>{...?curl.headers};
      if (!headers.containsKey('User-Agent') && _userAgent.isNotEmpty) {
        headers['User-Agent'] = _userAgent;
      }
      Pointer<Void> hdrList = nullptr;
      for (final e in headers.entries) {
        final h = '${e.key}: ${e.value}'.toNativeUtf8();
        hdrList = _curl.slistAppend(hdrList, h);
      }
      if (hdrList != nullptr) {
        _curl.easySetopt(easy, CURLOPT_HTTPHEADER, hdrList.cast<NativeType>());
      }

      // Body
      final data = curl.data;
      if (data != null && data.isNotEmpty) {
        final bytes = utf8.encode(data);
        final ptr = calloc<Uint8>(bytes.length);
        for (var i = 0; i < bytes.length; i++) {
          ptr[i] = bytes[i];
        }
        _curl.easySetopt(easy, CURLOPT_POSTFIELDS, ptr.cast<NativeType>());
        _setoptInt(easy, CURLOPT_POSTFIELDSIZE, bytes.length);
      }

      // TLS
      if (caBundlePath != null) {
        final caPath = caBundlePath!.toNativeUtf8();
        _curl.easySetopt(easy, CURLOPT_CAINFO, caPath.cast<NativeType>());
      }
      if (insecure) {
        _setoptInt(easy, CURLOPT_SSL_VERIFYPEER, 0);
        _setoptInt(easy, CURLOPT_SSL_VERIFYHOST, 0);
      }
      if (pinnedpubkey != null && pinnedpubkey.isNotEmpty) {
        final pk = pinnedpubkey.toNativeUtf8();
        _curl.easySetopt(easy, CURLOPT_PINNEDPUBLICKEY, pk.cast<NativeType>());
      }

      // Follow redirects
      if (followRedirects) _setoptInt(easy, CURLOPT_FOLLOWLOCATION, 1);

      // Timeouts
      if (connectTimeout != null) {
        _setoptInt(easy, CURLOPT_CONNECTTIMEOUT_MS, connectTimeout.inMilliseconds);
      }
      if (maxTime != null) {
        _setoptInt(easy, CURLOPT_TIMEOUT_MS, maxTime.inMilliseconds);
      }

      // Verbose
      if (verbose || trace) {
        _setoptInt(easy, CURLOPT_VERBOSE, 1);
        final debugCtx = (verboseId << 32) | traceId;
        final debugPtr = Pointer.fromFunction<CurlDebugCallbackNative>(_debugCallback, 0);
        _curl.easySetopt(easy, CURLOPT_DEBUGFUNCTION, debugPtr.cast<NativeType>());
        _curl.easySetopt(easy, CURLOPT_DEBUGDATA, Pointer<Void>.fromAddress(debugCtx).cast());
      }

      // Write callback (body)
      final writePtr = Pointer.fromFunction<CurlWriteCallbackNative>(_writeCallback, 0);
      _curl.easySetopt(easy, CURLOPT_WRITEFUNCTION, writePtr.cast<NativeType>());
      _curl.easySetopt(easy, CURLOPT_WRITEDATA, Pointer<Void>.fromAddress(bodyId).cast());
      // Header callback
      final headerPtr = Pointer.fromFunction<CurlWriteCallbackNative>(_writeCallback, 0);
      _curl.easySetopt(easy, CURLOPT_HEADERFUNCTION, headerPtr.cast());
      _curl.easySetopt(easy, CURLOPT_HEADERDATA, Pointer<Void>.fromAddress(headerId).cast());

      // Execute
      final sw = Stopwatch()..start();
      final code = _curl.easyPerform(easy);
      sw.stop();

      // Status code
      final statusPtr = calloc<Int64>();
      _curl.easyGetinfo(easy, CURLINFO_RESPONSE_CODE, statusPtr.cast<NativeType>());
      final statusCode = statusPtr.value;
      calloc.free(statusPtr);

      // Time
      final timePtr = calloc<Double>();
      _curl.easyGetinfo(easy, CURLINFO_TOTAL_TIME, timePtr.cast<NativeType>());
      final totalMs = (timePtr.value * 1000).round();
      calloc.free(timePtr);

      // Parse headers
      final headerText = utf8.decode(_bufs[headerId]!, allowMalformed: true);
      final responseHeaders = <String, List<String>>{};
      for (final line in headerText.split('\r\n')) {
        final colon = line.indexOf(':');
        if (colon > 0) {
          responseHeaders.putIfAbsent(line.substring(0, colon).trim(),
              () => []).add(line.substring(colon + 1).trim());
        }
      }

      final bodyStr = utf8.decode(_bufs[bodyId]!, allowMalformed: true);
      final ok = code == CURLE_OK;
      final verboseLog = verbose && _bufs[verboseId]!.isNotEmpty
          ? utf8.decode(_bufs[verboseId]!, allowMalformed: true)
          : null;
      final traceLogStr = trace && _bufs[traceId]!.isNotEmpty
          ? _formatTraceHex(_bufs[traceId]!)
          : null;

      return CurlResponse(
        statusCode: ok ? statusCode : 0,
        statusMessage: ok ? 'OK' : _curl.easyStrerror(code).toDartString(),
        headers: responseHeaders,
        body: bodyStr.isNotEmpty ? bodyStr : null,
        verboseLog: verboseLog,
        traceLog: traceLogStr,
        executionTime: ok ? Duration(milliseconds: totalMs) : sw.elapsed,
      );
    } finally {
      _curl.easyCleanup(easy);
      _bufs.remove(bodyId);
      _bufs.remove(headerId);
      _bufs.remove(verboseId);
      _bufs.remove(traceId);
    }
  }

  static String _formatTraceHex(List<int> bytes) {
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

  void _setoptInt(CURL easy, int option, int value) {
    final ptr = calloc<Int32>()..value = value;
    _curl.easySetopt(easy, option, ptr.cast<NativeType>());
    calloc.free(ptr);
  }

  // ── Flag extraction ─────────────────────────────────────────

  Map<String, String> _extractFlagValues(String command) {
    final result = <String, String>{};
    final tokens = _tokenizeRaw(command);
    for (var i = 0; i < tokens.length; i++) {
      final tok = tokens[i];
      if (tok.startsWith('--')) {
        final body = tok.substring(2);
        final eq = body.indexOf('=');
        if (eq >= 0) {
          result[body.substring(0, eq)] = _unquote(body.substring(eq + 1));
        } else if (i + 1 < tokens.length) {
          final next = tokens[i + 1];
          if (!next.startsWith('-') && !next.startsWith('http://') && !next.startsWith('https://')) {
            result[body] = _unquote(next);
          }
        }
      }
    }
    return result;
  }

  List<String> _tokenizeRaw(String command) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inS = false, inD = false;
    for (var i = 0; i < command.length; i++) {
      final ch = command[i];
      if (ch == "'" && !inD) { inS = !inS; continue; }
      if (ch == '"' && !inS) { inD = !inD; continue; }
      if (ch == '\\' && i + 1 < command.length) {
        i++;
        if (command[i] == '\n') continue;
        buf.write(command[i]); continue;
      }
      if ((ch == ' ' || ch == '\t' || ch == '\n') && !inS && !inD) {
        if (buf.isNotEmpty) { tokens.add(buf.toString()); buf.clear(); }
        continue;
      }
      buf.write(ch);
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }

  String _unquote(String s) {
    if ((s.startsWith("'") && s.endsWith("'")) || (s.startsWith('"') && s.endsWith('"'))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }
}
