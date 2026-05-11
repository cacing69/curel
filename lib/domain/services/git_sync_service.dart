import 'dart:convert';
import 'dart:io';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/models/project_model.dart';
import 'package:curel/domain/models/git_provider_model.dart';
import 'package:curel/domain/services/git_client.dart';
import 'package:curel/domain/services/git_provider_service.dart';
import 'package:curel/domain/services/device_service.dart';
import 'package:curel/domain/services/diff_service.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

class GitSyncService {
  final Ref _ref;
  final GitProviderService _providerService;
  final FileSystemService _fs;
  final DeviceService _device;
  final DiffService _diff;

  GitSyncService(this._ref, this._providerService, this._fs, this._device, this._diff);

  Future<GitSyncResult> pull(Project project, {bool force = false}) async {
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

      final client = GitClient.create(provider.type, baseUrl: provider.baseUrl);
      return _pullImpl(project, provider, token, client, force: force);
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  Future<Map<String, String>> _getLocalFiles(String projectId) async {
    final projectDir = await _fs.getProjectDir(projectId);
    final Map<String, String> localFiles = {};
    final dir = Directory(projectDir);

    if (!await dir.exists()) return localFiles;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relPath = p.relative(entity.path, from: projectDir);
        if (relPath.endsWith('.curl') ||
            relPath.endsWith('.meta.json') ||
            relPath == 'curel.json') {
          localFiles[relPath] = await entity.readAsString();
        }
      }
    }
    return localFiles;
  }

  Future<GitSyncResult> _pullImpl(
    Project project,
    GitProviderModel _,
    String token,
    GitClient client, {
    bool force = false,
  }) async {
    try {
      // 1. Get Remote SHA
      final remoteSha = await client.getLatestCommitSha(
        project.remoteUrl!,
        project.branch!,
        token,
      );

      // 2. Fetch Remote Files
      final remoteFilesList = await client.fetchFiles(
        project.remoteUrl!,
        project.branch!,
        token,
      );
      final remoteFiles = {for (var f in remoteFilesList) f.path: f.content};

      // 3. Validate Remote Signature
      final remoteCurelJson = remoteFiles['curel.json'];
      String? remoteOriginId;
      if (remoteCurelJson != null) {
        try {
          final json = jsonDecode(remoteCurelJson);
          remoteOriginId = json['remote_origin_id'] ?? json['id'];
        } catch (_) {}
      }

      // 4. SAFETY CHECK
      final localRequests = await _ref.read(requestServiceProvider).listRequests(project.id);
      final isNewConnection = project.remoteOriginId == null;

      if (!force && isNewConnection && remoteFiles.isNotEmpty && localRequests.isNotEmpty) {
        return GitSyncResult(
          success: false,
          hasConflict: true,
          message: 'conflict: both local and remote have data',
          data: remoteOriginId,
        );
      }

      if (remoteFiles.isNotEmpty && remoteCurelJson == null) {
        return GitSyncResult(
          success: false,
          message: 'safety check failed: remote repository is not a curel project',
        );
      }

      if (project.remoteOriginId != null && 
          remoteOriginId != null && 
          project.remoteOriginId != remoteOriginId) {
        return GitSyncResult(
          success: false,
          message: 'critical mismatch: this repo belongs to a different project ($remoteOriginId)',
        );
      }

      // 5. INCREMENTAL DIFF
      final localFiles = await _getLocalFiles(project.id);
      final changes = _diff.computeChanges(localFiles, remoteFiles);

      if (changes.isEmpty) {
        return GitSyncResult(
          success: true,
          message: 'local is up to date with cloud',
          filesCount: 0,
          newSyncSha: remoteSha,
        );
      }

      // 6. Save to Filesystem (Only changed files)
      final projectDir = await _fs.getProjectDir(project.id);
      int written = 0;
      int deleted = 0;

      for (final change in changes) {
        final fullPath = p.join(projectDir, change.path);
        
        if (change.type == ChangeType.deleted) {
          final file = File(fullPath);
          if (await file.exists()) await file.delete();
          deleted++;
          continue;
        }

        var content = change.newContent!;

        // Special handling for curel.json to preserve local context
        if (change.path == 'curel.json') {
          try {
            final json = jsonDecode(content) as Map<String, dynamic>;
            json['id'] = project.id;
            json['remote_origin_id'] = project.remoteOriginId ?? remoteOriginId;
            json['remote_url'] = project.remoteUrl;
            json['provider'] = project.provider;
            json['branch'] = project.branch;
            json['mode'] = 'git';
            content = JsonEncoder.withIndent('  ').convert(json);
          } catch (_) {}
        }

        final dir = Directory(p.dirname(fullPath));
        if (!await dir.exists()) await dir.create(recursive: true);
        await File(fullPath).writeAsString(content);
        written++;
      }

      return GitSyncResult(
        success: true,
        message: 'incremental pull: $written updated, $deleted deleted',
        filesCount: written + deleted,
        newSyncSha: remoteSha,
        data: remoteOriginId,
      );
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  Future<GitSyncResult> push(Project project, {bool force = false}) async {
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

      final client = GitClient.create(provider.type, baseUrl: provider.baseUrl);
      return _pushImpl(project, provider, token, client, force: force);
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  Future<GitSyncResult> _pushImpl(
    Project project,
    GitProviderModel _,
    String token,
    GitClient client, {
    bool force = false,
  }) async {
    try {
      // 1. Optimistic locking: reject push if remote changed since last sync
      final remoteSha = await client.getLatestCommitSha(
        project.remoteUrl!, project.branch!, token,
      );

      if (!force && project.lastSyncSha != null) {
        if (remoteSha != null && remoteSha != project.lastSyncSha) {
          return GitSyncResult(
            success: false,
            hasConflict: true,
            message: 'remote changed since last sync. pull first.',
          );
        }
      }

      // 2. Fetch Remote Files (for diffing)
      final remoteFilesList = await client.fetchFiles(
        project.remoteUrl!,
        project.branch!,
        token,
      );
      final remoteFiles = {for (var f in remoteFilesList) f.path: f.content};

      // 3. Gather local files and compute changes
      final localFiles = await _getLocalFiles(project.id);
      
      // Inject .gitignore manually if not present
      if (!localFiles.containsKey('.gitignore')) {
        localFiles['.gitignore'] = '# Curel ignore file\nenvironments/\n.env\n*.local\n';
      }

      final changes = _diff.computeChanges(remoteFiles, localFiles); // old=remote, new=local
      
      if (changes.isEmpty) {
        return GitSyncResult(
          success: true,
          message: 'everything is up to date',
          filesCount: 0,
          newSyncSha: remoteSha,
        );
      }

      // 4. Prepare files for GitClient (only changed ones)
      final List<GitFile> filesToPush = [];
      for (final change in changes) {
        var content = change.newContent ?? '';
        
        // Inject remote_origin_id into curel.json before pushing
        if (change.path == 'curel.json') {
          try {
            final json = jsonDecode(content) as Map<String, dynamic>;
            json['remote_origin_id'] = project.remoteOriginId ?? project.id;
            content = JsonEncoder.withIndent('  ').convert(json);
          } catch (_) {}
        }

        filesToPush.add(GitFile(
          path: change.path, 
          content: content, 
          deletion: change.type == ChangeType.deleted,
        ));
      }

      // 5. Prepare Commit Message
      final now = DateTime.now();
      final date = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final time = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      final fingerprint = await _device.getFingerprint();

      final commitMessage = 'curel v$version ($fingerprint) $date $time';

      // 6. Push to Remote
      final newSha = await client.pushFiles(
        project.remoteUrl!,
        project.branch!,
        token,
        filesToPush,
        commitMessage,
      );

      return GitSyncResult(
        success: true,
        message: 'pushed ${filesToPush.length} changes successfully',
        filesCount: filesToPush.length,
        newSyncSha: newSha,
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

      final client = GitClient.create(provider.type, baseUrl: provider.baseUrl);

      // 1. SMART CHECK: Fetch latest SHA from Remote
      final remoteSha = await client.getLatestCommitSha(
          project.remoteUrl!, project.branch!, token);

      GitSyncResult pullRes;
      if (remoteSha != null && remoteSha == project.lastSyncSha) {
        // No changes in remote, skip Pull
        pullRes = GitSyncResult(
            success: true,
            message: 'cloud is up to date, skipping pull',
            filesCount: 0);
      } else {
        // Remote has changes or first sync, perform Pull
        pullRes = await _pullImpl(project, provider, token, client);
        if (!pullRes.success) return pullRes;
      }

      // 2. Push local changes (skip optimistic lock — we just pulled)
      final syncedProject = pullRes.newSyncSha != null
          ? project.copyWith(lastSyncSha: pullRes.newSyncSha)
          : project;
      final pushRes = await _pushImpl(syncedProject, provider, token, client);
      if (!pushRes.success) return pushRes;

      return GitSyncResult(
        success: true,
        message: pullRes.filesCount == 0 && pullRes.success
            ? 'synced: local changes pushed (cloud was up to date)'
            : 'sync complete (pulled: ${pullRes.filesCount}, pushed: ${pushRes.filesCount})',
        filesCount: pushRes.filesCount,
        newSyncSha: pushRes.newSyncSha,
        data: pullRes.data,
      );
    } catch (e) {
      return GitSyncResult(success: false, message: _cleanError(e));
    }
  }

  /// Get a list of changes between local and remote without applying them
  Future<List<FileChange>> computePendingChanges(Project project) async {
    if (project.remoteUrl == null || project.provider == null || project.branch == null) {
      return [];
    }

    try {
      final provider = await _providerService.getById(project.provider!);
      if (provider == null) return [];

      final token = await _providerService.getToken(provider.id);
      if (token == null) return [];

      final client = GitClient.create(provider.type, baseUrl: provider.baseUrl);
      
      // Fetch remote state
      final remoteFilesList = await client.fetchFiles(
        project.remoteUrl!,
        project.branch!,
        token,
      );
      final remoteFiles = {for (var f in remoteFilesList) f.path: f.content};

      // Fetch local state
      final localFiles = await _getLocalFiles(project.id);

      return _diff.computeChanges(localFiles, remoteFiles);
    } catch (_) {
      return [];
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
