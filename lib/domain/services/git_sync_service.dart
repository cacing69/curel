import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/data/services/github_client.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/git_client.dart';
import 'package:curel/domain/services/git_provider_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class GitSyncService {
  final GitProviderService _providerService;
  final FileSystemService _fs;

  GitSyncService(this._providerService, this._fs);

  GitClient _getClient(String type) {
    switch (type) {
      case 'github':
        return GitHubClient();
      default:
        throw Exception('Provider $type not supported yet');
    }
  }

  Future<GitSyncResult> pull(Project project) async {
    if (project.remoteUrl == null ||
        project.provider == null ||
        project.branch == null) {
      return GitSyncResult(
        success: false,
        message: 'project not connected to remote',
      );
    }

    try {
      // 1. Get Provider and Token
      final provider = await _providerService.getById(project.provider!);
      if (provider == null)
        return GitSyncResult(success: false, message: 'git provider not found');

      final token = await _providerService.getToken(provider.id);
      if (token == null)
        return GitSyncResult(
          success: false,
          message: 'token missing for provider',
        );

      // 2. Select Client
      final client = _getClient(provider.type);

      // 3. Fetch Files
      final remoteFiles = await client.fetchFiles(
        project.remoteUrl!,
        project.branch!,
        token,
      );

      // 4. Save to Filesystem
      final projectDir = await _fs.getProjectDir(project.id);

      for (final file in remoteFiles) {
        final fullPath = p.join(projectDir, file.path);
        // Ensure subdirectories exist (e.g., requests/folder/file.curl)
        final dir = Directory(p.dirname(fullPath));
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        var content = file.content;

        // CRITICAL: If this is curel.json, we must ensure it keeps the LOCAL project ID
        // to prevent duplication in ProjectService re-indexing.
        if (file.path == 'curel.json') {
          try {
            final json = jsonDecode(content) as Map<String, dynamic>;
            json['id'] = project.id; // Force local ID
            // Also preserve the current git connection info just in case
            json['remote_url'] = project.remoteUrl;
            json['provider'] = project.provider;
            json['branch'] = project.branch;
            json['mode'] = 'git';
            content = JsonEncoder.withIndent('  ').convert(json);
          } catch (_) {
            // If JSON is malformed, skip ID injection
          }
        }

        await File(fullPath).writeAsString(content);
      }

      return GitSyncResult(
        success: true,
        message: remoteFiles.isEmpty
            ? 'cloud is empty. ready for initial push.'
            : 'pulled ${remoteFiles.length} files successfully',
        filesCount: remoteFiles.length,
      );
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  Future<GitSyncResult> push(Project project) async {
    if (project.remoteUrl == null ||
        project.provider == null ||
        project.branch == null) {
      return GitSyncResult(
        success: false,
        message: 'project not connected to remote',
      );
    }

    try {
      final provider = await _providerService.getById(project.provider!);
      if (provider == null)
        return GitSyncResult(success: false, message: 'git provider not found');

      final token = await _providerService.getToken(provider.id);
      if (token == null)
        return GitSyncResult(
          success: false,
          message: 'token missing for provider',
        );

      final client = _getClient(provider.type);
      final projectDir = await _fs.getProjectDir(project.id);

      // 1. Gather local files (.curl, .meta.json, curel.json)
      final List<GitFile> localFiles = [];
      final dir = Directory(projectDir);

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final relPath = p.relative(entity.path, from: projectDir);
          // Only sync relevant files
          if (relPath.endsWith('.curl') ||
              relPath.endsWith('.meta.json') ||
              relPath == 'curel.json') {
            final content = await entity.readAsString();
            localFiles.add(GitFile(path: relPath, content: content));
          }
        }
      }

      // 2. Prepare Commit Message
      final now = DateTime.now();
      final timestamp =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final fingerprint = await _getDeviceFingerprint();

      final commitMessage =
          'sync from curel v$version ($fingerprint) $timestamp';

      // 3. Push to Remote
      await client.pushFiles(
        project.remoteUrl!,
        project.branch!,
        token,
        localFiles,
        commitMessage,
      );

      return GitSyncResult(
        success: true,
        message: 'pushed ${localFiles.length} files successfully',
        filesCount: localFiles.length,
      );
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  /// Combined Smart Sync (Pull then Push)
  Future<GitSyncResult> sync(Project project) async {
    if (project.remoteUrl == null ||
        project.provider == null ||
        project.branch == null) {
      return GitSyncResult(
          success: false, message: 'project not connected to remote');
    }

    try {
      final provider = await _providerService.getById(project.provider!);
      if (provider == null)
        return GitSyncResult(success: false, message: 'git provider not found');

      final token = await _providerService.getToken(provider.id);
      if (token == null)
        return GitSyncResult(
            success: false, message: 'token missing for provider');

      final client = _getClient(provider.type);

      // 1. SMART CHECK: Fetch latest SHA from Remote
      final remoteSha = await client.getLatestCommitSha(
          project.remoteUrl!, project.branch!, token);

      GitSyncResult? pullRes;
      if (remoteSha != null && remoteSha == project.lastSyncSha) {
        // No changes in remote, skip Pull
        pullRes = GitSyncResult(
            success: true,
            message: 'cloud is up to date, skipping pull',
            filesCount: 0);
      } else {
        // Remote has changes or first sync, perform Pull
        pullRes = await pull(project);
        if (!pullRes.success) return pullRes;
      }

      // 2. Push local changes
      final pushRes = await push(project);
      if (!pushRes.success) return pushRes;

      return GitSyncResult(
        success: true,
        message: pullRes.filesCount == 0 && pullRes.success
            ? 'synced: local changes pushed (cloud was up to date)'
            : 'sync complete (pulled: ${pullRes.filesCount}, pushed: ${pushRes.filesCount})',
        filesCount: pushRes.filesCount,
      );
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  String _cleanError(Object e) {
    final msg = e.toString();
    if (msg.startsWith('Exception: ')) {
      return msg.substring(11);
    }
    return msg;
  }

  Future<String> _getDeviceFingerprint() async {
    final deviceInfo = DeviceInfoPlugin();
    String rawId = 'unknown';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id; // stable ID
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        rawId = iosInfo.identifierForVendor ?? 'ios-unknown';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        rawId = macInfo.systemGUID ?? 'macos-unknown';
      }
    } catch (_) {
      rawId = 'error-fetching-id';
    }

    // Hash the ID to make it anonymous but consistent
    final bytes = utf8.encode(
      rawId + "curel-salt",
    ); // Add salt for extra privacy
    final digest = sha256.convert(bytes);

    // Take first 7 chars
    return digest.toString().substring(0, 7);
  }
}
