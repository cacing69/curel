import 'dart:convert';
import 'dart:io' as dart_io;

import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/cookie_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const _keyActivePrefix = 'cookiejar_active_';

abstract class CookieJarService {
  Future<List<CookieJar>> listJars(String projectId);
  Future<CookieJar?> getActiveJar(String projectId);
  Future<void> setActiveJar(String projectId, String jarName);
  Future<CookieJar> createJar(String projectId, String name);
  Future<void> saveJar(String projectId, CookieJar jar);
  Future<void> deleteJar(String projectId, String jarName);
  Future<void> addCookie(String projectId, CookieEntry cookie);
  Future<void> removeCookie(String projectId, String cookieName);
  Future<void> importNetscape(String projectId, String content);
  String buildCookieHeader(CookieJar jar, Uri targetUri);
  CookieJar captureSetCookies(
    Map<String, List<String>> responseHeaders,
    Uri requestUri,
    CookieJar currentJar,
  );
}

class FilesystemCookieJarService implements CookieJarService {
  final FileSystemService _fs;

  FilesystemCookieJarService(this._fs);

  // ── Jar CRUD ──────────────────────────────────────────────────────

  @override
  Future<List<CookieJar>> listJars(String projectId) async {
    final jarDir = await _fs.getCookieJarDir(projectId);
    if (!await _fs.exists(jarDir)) return [];

    final entities = await _fs.listFiles(jarDir);
    final jars = <CookieJar>[];
    for (final entity in entities) {
      if (entity is! dart_io.File || !entity.path.endsWith('.cookiejar.json')) continue;
      try {
        final content = await _fs.readFile(entity.path);
        final json = jsonDecode(content) as Map<String, dynamic>;
        jars.add(CookieJar.fromJson(json));
      } catch (_) {}
    }
    return jars;
  }

  @override
  Future<CookieJar?> getActiveJar(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final activeName = prefs.getString('$_keyActivePrefix$projectId');
    if (activeName == null) return null;

    final jarDir = await _fs.getCookieJarDir(projectId);
    final filePath = p.join(jarDir, '$activeName.cookiejar.json');
    if (!await _fs.exists(filePath)) return null;

    try {
      final content = await _fs.readFile(filePath);
      return CookieJar.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setActiveJar(String projectId, String jarName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_keyActivePrefix$projectId', jarName);
  }

  @override
  Future<CookieJar> createJar(String projectId, String name) async {
    final jar = CookieJar(name: name);
    await saveJar(projectId, jar);
    return jar;
  }

  @override
  Future<void> saveJar(String projectId, CookieJar jar) async {
    final jarDir = await _fs.getCookieJarDir(projectId);
    await _fs.ensureDir(jarDir);
    final filePath = p.join(jarDir, '${_sanitizeName(jar.name)}.cookiejar.json');
    await _fs.writeFile(filePath, const JsonEncoder.withIndent('  ').convert(jar.toJson()));
  }

  @override
  Future<void> deleteJar(String projectId, String jarName) async {
    final jarDir = await _fs.getCookieJarDir(projectId);
    final filePath = p.join(jarDir, '${_sanitizeName(jarName)}.cookiejar.json');
    if (await _fs.exists(filePath)) {
      await _fs.deleteFile(filePath);
    }

    // Clear active if it was this jar
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('$_keyActivePrefix$projectId') == jarName) {
      await prefs.remove('$_keyActivePrefix$projectId');
    }
  }

  // ── Cookie operations ─────────────────────────────────────────────

  @override
  Future<void> addCookie(String projectId, CookieEntry cookie) async {
    final jar = await getActiveJar(projectId);
    if (jar == null) return;

    final existing = jar.cookies.indexWhere((c) => c.name == cookie.name && c.domain == cookie.domain);
    final updatedCookies = List<CookieEntry>.from(jar.cookies);
    if (existing >= 0) {
      updatedCookies[existing] = cookie;
    } else {
      updatedCookies.add(cookie);
    }

    await saveJar(projectId, jar.copyWith(cookies: updatedCookies));
  }

  @override
  Future<void> removeCookie(String projectId, String cookieName) async {
    final jar = await getActiveJar(projectId);
    if (jar == null) return;

    final updatedCookies = jar.cookies.where((c) => c.name != cookieName).toList();
    await saveJar(projectId, jar.copyWith(cookies: updatedCookies));
  }

  // ── Netscape import ───────────────────────────────────────────────

  @override
  Future<void> importNetscape(String projectId, String content) async {
    final cookies = <CookieEntry>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      var httpOnly = false;
      var domainLine = trimmed;

      if (domainLine.startsWith('#HttpOnly_')) {
        httpOnly = true;
        domainLine = domainLine.substring(10);
      }
      if (domainLine.startsWith('#')) continue;

      final fields = domainLine.split('\t');
      if (fields.length < 7) continue;

      final domain = fields[0];
      final path = fields[2];
      final secure = fields[3].toUpperCase() == 'TRUE';
      final expiresRaw = int.tryParse(fields[4]) ?? 0;
      final expires = expiresRaw > 0 ? DateTime.fromMillisecondsSinceEpoch(expiresRaw * 1000) : null;
      final name = fields[5];
      final value = fields[6];

      cookies.add(CookieEntry(
        name: name,
        value: value,
        domain: domain,
        path: path,
        secure: secure,
        httpOnly: httpOnly,
        expires: expires,
      ));
    }

    if (cookies.isEmpty) return;

    final jar = await getActiveJar(projectId);
    if (jar == null) return;

    final updatedCookies = List<CookieEntry>.from(jar.cookies);
    for (final cookie in cookies) {
      final idx = updatedCookies.indexWhere(
        (c) => c.name == cookie.name && c.domain == cookie.domain,
      );
      if (idx >= 0) {
        updatedCookies[idx] = cookie;
      } else {
        updatedCookies.add(cookie);
      }
    }

    await saveJar(projectId, jar.copyWith(cookies: updatedCookies));
  }

  // ── Cookie header building ────────────────────────────────────────

  @override
  String buildCookieHeader(CookieJar jar, Uri targetUri) {
    final matching = jar.cookies.where((c) => c.matches(targetUri)).toList();
    if (matching.isEmpty) return '';
    return matching.map((c) => '${c.name}=${c.value}').join('; ');
  }

  // ── Set-Cookie capture ────────────────────────────────────────────

  @override
  CookieJar captureSetCookies(
    Map<String, List<String>> responseHeaders,
    Uri requestUri,
    CookieJar currentJar,
  ) {
    final setCookieHeaders = responseHeaders['set-cookie'];
    if (setCookieHeaders == null || setCookieHeaders.isEmpty) return currentJar;

    final updatedCookies = List<CookieEntry>.from(currentJar.cookies);

    for (final header in setCookieHeaders) {
      final cookie = _parseSetCookie(header, requestUri);
      if (cookie == null) continue;

      final idx = updatedCookies.indexWhere(
        (c) => c.name == cookie.name && c.domain == cookie.domain,
      );
      if (idx >= 0) {
        updatedCookies[idx] = cookie;
      } else {
        updatedCookies.add(cookie);
      }
    }

    return currentJar.copyWith(cookies: updatedCookies);
  }

  CookieEntry? _parseSetCookie(String header, Uri requestUri) {
    // Parse: name=value; Path=/; Domain=.example.com; Secure; HttpOnly; Expires=...
    final parts = header.split(';');
    if (parts.isEmpty) return null;

    final nameValue = parts[0].trim();
    final eqIdx = nameValue.indexOf('=');
    if (eqIdx < 0) return null;

    final name = nameValue.substring(0, eqIdx).trim();
    final value = nameValue.substring(eqIdx + 1).trim();

    if (name.isEmpty) return null;

    String? domain;
    String? path;
    var secure = false;
    var httpOnly = false;
    DateTime? expires;

    for (var i = 1; i < parts.length; i++) {
      final part = parts[i].trim();
      final lower = part.toLowerCase();

      if (lower == 'secure') {
        secure = true;
      } else if (lower == 'httponly') {
        httpOnly = true;
      } else if (lower.startsWith('domain=')) {
        domain = part.substring(7).trim();
      } else if (lower.startsWith('path=')) {
        path = part.substring(5).trim();
      } else if (lower.startsWith('expires=')) {
        final expiresStr = part.substring(8).trim();
        expires = _parseCookieDate(expiresStr);
      } else if (lower.startsWith('max-age=')) {
        final maxAge = int.tryParse(part.substring(8).trim());
        if (maxAge != null) {
          expires = maxAge > 0
              ? DateTime.now().add(Duration(seconds: maxAge))
              : DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
    }

    // Default domain to request host if not specified
    domain ??= requestUri.host;

    return CookieEntry(
      name: name,
      value: value,
      domain: domain,
      path: path ?? '/',
      secure: secure,
      httpOnly: httpOnly,
      expires: expires,
    );
  }

  DateTime? _parseCookieDate(String raw) {
    // Handle common cookie date formats
    final cleaned = raw.replaceAll(',', '');
    return DateTime.tryParse(cleaned);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  String _sanitizeName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'[^\w\-.]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
