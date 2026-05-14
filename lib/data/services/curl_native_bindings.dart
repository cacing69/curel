import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// ── C types ──────────────────────────────────────────────────

typedef CURL = Pointer<Void>;

typedef CURLcode = Int32;
const int CURLE_OK = 0;
const int CURLE_UNSUPPORTED_PROTOCOL = 1;
const int CURLE_URL_MALFORMAT = 3;
const int CURLE_SSL_CONNECT_ERROR = 35;
const int CURLE_SSL_PINNEDPUBKEYNOTMATCH = 90;

typedef CURLoption = Int32;
typedef CURLINFO = Int32;

// ── Native function signatures ──────────────────────────────

typedef CurlEasyInitNative = CURL Function();
typedef CurlEasyInitDart = CURL Function();

typedef CurlEasySetoptNative = CURLcode Function(CURL, CURLoption, Pointer<NativeType>);
typedef CurlEasySetoptDart = int Function(Pointer<Void>, int, Pointer<NativeType>);

typedef CurlEasyPerformNative = CURLcode Function(CURL);
typedef CurlEasyPerformDart = int Function(Pointer<Void>);

typedef CurlEasyCleanupNative = Void Function(CURL);
typedef CurlEasyCleanupDart = void Function(Pointer<Void>);

typedef CurlEasyStrerrorNative = Pointer<Utf8> Function(CURLcode);
typedef CurlEasyStrerrorDart = Pointer<Utf8> Function(int);

typedef CurlEasyGetinfoNative = CURLcode Function(CURL, CURLINFO, Pointer<NativeType>);
typedef CurlEasyGetinfoDart = int Function(Pointer<Void>, int, Pointer<NativeType>);

typedef CurlSlistAppendNative = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>);
typedef CurlSlistAppendDart = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>);

typedef CurlSlistFreeAllNative = Void Function(Pointer<Void>);
typedef CurlSlistFreeAllDart = void Function(Pointer<Void>);

// ── Callback types for write/header functions ────────────────

typedef CurlWriteCallbackNative = UintPtr Function(
  Pointer<Uint8> data,
  UintPtr size,
  UintPtr nmemb,
  Pointer<Void> userdata,
);

typedef CurlWriteCallbackVoid = Void Function(
  Pointer<Uint8> data,
  UintPtr size,
  UintPtr nmemb,
  Pointer<Void> userdata,
);
typedef CurlWriteCallbackDart = int Function(
  Pointer<Uint8>,
  int,
  int,
  Pointer<Void>,
);

typedef CurlDebugCallbackNative = Int32 Function(
  Pointer<Void> handle,
  Int32 type,
  Pointer<Uint8> data,
  UintPtr size,
  Pointer<Void> userdata,
);
typedef CurlDebugCallbackDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Uint8>,
  int,
  Pointer<Void>,
);

// ── CURLOPT constants ────────────────────────────────────────
// Values from curl/curl.h

const int CURLOPT_URL = 10002;
const int CURLOPT_CUSTOMREQUEST = 10036;
const int CURLOPT_HTTPHEADER = 10023;
const int CURLOPT_POSTFIELDS = 10015;
const int CURLOPT_POSTFIELDSIZE = 60;
const int CURLOPT_WRITEFUNCTION = 20011;
const int CURLOPT_WRITEDATA = 10001;
const int CURLOPT_HEADERFUNCTION = 20079;
const int CURLOPT_HEADERDATA = 10029;
const int CURLOPT_SSL_VERIFYPEER = 64;
const int CURLOPT_SSL_VERIFYHOST = 81;
const int CURLOPT_VERBOSE = 41;
const int CURLOPT_DEBUGFUNCTION = 20094;
const int CURLOPT_DEBUGDATA = 10095;
const int CURLOPT_FOLLOWLOCATION = 52;
const int CURLOPT_TIMEOUT_MS = 155;
const int CURLOPT_CONNECTTIMEOUT_MS = 156;
const int CURLOPT_USERAGENT = 10018;
const int CURLOPT_USERNAME = 10173;
const int CURLOPT_PASSWORD = 10174;
const int CURLOPT_PINNEDPUBLICKEY = 10206;
const int CURLOPT_CAINFO = 10065;
const int CURLOPT_REFERER = 10016;
const int CURLOPT_COOKIE = 10022;
const int CURLOPT_ACCEPT_ENCODING = 24;

// ── CURLINFO constants ────────────────────────────────────────

const int CURLINFO_RESPONSE_CODE = 2097154;
const int CURLINFO_TOTAL_TIME = 3145731;
const int CURLINFO_SIZE_UPLOAD = 3145741;
const int CURLINFO_SIZE_DOWNLOAD = 3145736;

// ── Library loader ───────────────────────────────────────────

class CurlLibrary {
  static CurlLibrary? _instance;
  late final DynamicLibrary _lib;
  bool _loaded = false;

  factory CurlLibrary() {
    _instance ??= CurlLibrary._();
    return _instance!;
  }

  CurlLibrary._();

  bool get isLoaded => _loaded;

  void load() {
    if (_loaded) return;

    String libPath;
    if (Platform.isAndroid) {
      libPath = 'libcurl.so';
    } else if (Platform.isIOS) {
      libPath = 'libcurl.dylib';
    } else if (Platform.isMacOS) {
      libPath = '/usr/lib/libcurl.dylib';
    } else if (Platform.isLinux) {
      libPath = 'libcurl.so.4';
    } else if (Platform.isWindows) {
      libPath = 'libcurl.dll';
    } else {
      throw UnsupportedError('Unsupported platform');
    }

    _lib = DynamicLibrary.open(libPath);
    _loaded = true;
  }

  // ── Method references ───────────────────────────────────────

  late final CurlEasyInitDart easyInit =
      _lib.lookupFunction<CurlEasyInitNative, CurlEasyInitDart>('curl_easy_init');

  late final CurlEasySetoptDart easySetopt = _lib
      .lookupFunction<CurlEasySetoptNative, CurlEasySetoptDart>('curl_easy_setopt');

  late final CurlEasyPerformDart easyPerform = _lib
      .lookupFunction<CurlEasyPerformNative, CurlEasyPerformDart>('curl_easy_perform');

  late final CurlEasyCleanupDart easyCleanup =
      _lib.lookupFunction<CurlEasyCleanupNative, CurlEasyCleanupDart>('curl_easy_cleanup');

  late final CurlEasyStrerrorDart easyStrerror =
      _lib.lookupFunction<CurlEasyStrerrorNative, CurlEasyStrerrorDart>(
          'curl_easy_strerror');

  late final CurlEasyGetinfoDart easyGetinfo =
      _lib.lookupFunction<CurlEasyGetinfoNative, CurlEasyGetinfoDart>(
          'curl_easy_getinfo');

  late final CurlSlistAppendDart slistAppend =
      _lib.lookupFunction<CurlSlistAppendNative, CurlSlistAppendDart>(
          'curl_slist_append');

  late final CurlSlistFreeAllDart slistFreeAll =
      _lib.lookupFunction<CurlSlistFreeAllNative, CurlSlistFreeAllDart>(
          'curl_slist_free_all');
}
