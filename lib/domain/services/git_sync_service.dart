import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/data/services/github_client.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/services/git_client.dart';
import 'package:curel/domain/services/git_provider_service.dart';
import 'package:curel/domain/services/device_service.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class GitSyncService {
  final Ref _ref;
  final GitProviderService _providerService;
  final FileSystemService _fs;
  final DeviceService _device;

  GitSyncService(this._ref, this._providerService, this._fs, this._device);

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

      // 4. Validate Remote Signature (curel.json)
      final remoteCurelJson = remoteFiles.firstWhere(
        (f) => f.path == 'curel.json',
        orElse: () => GitFile(path: '', content: ''),
      );

      String? remoteOriginId;
      if (remoteCurelJson.path.isNotEmpty) {
        try {
          final json = jsonDecode(remoteCurelJson.content);
          remoteOriginId = json['remote_origin_id'] ?? json['id'];
        } catch (_) {}
      }

      // 5. SAFETY CHECK: Conflict Detection
      // If remote has files AND local has files (requests) AND they haven't been linked yet
      final localRequests = await _ref.read(requestServiceProvider).listRequests(project.id);
      final isNewConnection = project.remoteOriginId == null;

      if (isNewConnection && remoteFiles.isNotEmpty && localRequests.isNotEmpty) {
        // We have data on both sides! Need resolution.
        return GitSyncResult(
          success: false,
          hasConflict: true,
          message: 'conflict: both local and remote have data',
          data: remoteOriginId,
        );
      }

      // GUARD: If remote has files but NO curel.json, it's NOT a curel project
      if (remoteFiles.isNotEmpty && remoteCurelJson.path.isEmpty) {
        return GitSyncResult(
          success: false,
          message: 'safety check failed: remote repository is not a curel project',
        );
      }

      // GUARD: Origin ID Mismatch (Only if already linked)
      if (project.remoteOriginId != null && 
          remoteOriginId != null && 
          project.remoteOriginId != remoteOriginId) {
        return GitSyncResult(
          success: false,
          message: 'critical mismatch: this repo belongs to a different project ($remoteOriginId)',
        );
      }

      // 5. Save to Filesystem
      final projectDir = await _fs.getProjectDir(project.id);
      
      // Update local remoteOriginId if this is the first pull
      String? effectiveOriginId = project.remoteOriginId ?? remoteOriginId;

      for (final file in remoteFiles) {
        final fullPath = p.join(projectDir, file.path);
        final dir = Directory(p.dirname(fullPath));
        if (!await dir.exists()) await dir.create(recursive: true);

        var content = file.content;

        if (file.path == 'curel.json') {
          try {
            final json = jsonDecode(content) as Map<String, dynamic>;
            json['id'] = project.id; // Keep local ID for indexing
            json['remote_origin_id'] = effectiveOriginId; // Store actual origin
            
            // Preserve connection info
            json['remote_url'] = project.remoteUrl;
            json['provider'] = project.provider;
            json['branch'] = project.branch;
            json['mode'] = 'git';
            content = JsonEncoder.withIndent('  ').convert(json);
          } catch (_) {}
        }

        await File(fullPath).writeAsString(content);
      }

      return GitSyncResult(
        success: true,
        message: remoteFiles.isEmpty
            ? 'cloud is empty. ready for initial push.'
            : 'pulled ${remoteFiles.length} files successfully',
        filesCount: remoteFiles.length,
        // Carry the origin ID back to update the model
        data: effectiveOriginId,
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
            var content = await entity.readAsString();
            
            // Inject remote_origin_id into curel.json before pushing
            if (relPath == 'curel.json') {
              try {
                final json = jsonDecode(content) as Map<String, dynamic>;
                json['remote_origin_id'] = project.remoteOriginId ?? project.id;
                content = JsonEncoder.withIndent('  ').convert(json);
              } catch (_) {}
            }
            
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
      final fingerprint = await _device.getFingerprint();

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
}
