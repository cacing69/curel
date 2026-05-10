import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/services/bookmark_service.dart';
import 'package:curel/domain/services/clipboard_service.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/history_service.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/domain/services/workspace_service.dart';
import 'package:curel/application/sync_controller.dart';
import 'package:curel/domain/services/git_provider_service.dart';
import 'package:curel/domain/services/git_sync_service.dart';

final fileSystemProvider = Provider<FileSystemService>(
  (ref) => LocalFileSystemService(),
);

final settingsProvider = Provider<SettingsService>(
  (ref) => PreferencesSettingsService(),
);

final httpClientProvider = Provider<CurlHttpClient>(
  (ref) => DioCurlHttpClient(),
);

final envServiceProvider = Provider<EnvService>(
  (ref) => FileSystemEnvService(ref.read(fileSystemProvider)),
);

final projectServiceProvider = Provider<ProjectService>(
  (ref) => FilesystemProjectService(ref.read(fileSystemProvider)),
);

final requestServiceProvider = Provider<RequestService>(
  (ref) => FilesystemRequestService(ref.read(fileSystemProvider)),
);

final historyServiceProvider = Provider<HistoryService>(
  (ref) => HistoryService(),
);

final bookmarkServiceProvider = Provider<BookmarkService>(
  (ref) => BookmarkService(),
);

final clipboardServiceProvider = Provider<ClipboardService>(
  (ref) => FlutterClipboardService(),
);

final workspaceServiceProvider = Provider<WorkspaceService>(
  (ref) => WorkspaceServiceImpl(
    envService: ref.read(envServiceProvider),
    projectService: ref.read(projectServiceProvider),
    requestService: ref.read(requestServiceProvider),
  ),
);

final syncControllerProvider = Provider<SyncController>(
  (ref) => SyncController(ref),
);

final gitProviderServiceProvider = Provider<GitProviderService>(
  (ref) => FileSystemGitProviderService(ref.read(fileSystemProvider)),
);

final gitSyncServiceProvider = Provider<GitSyncService>(
  (ref) => GitSyncService(
    ref.read(gitProviderServiceProvider),
    ref.read(fileSystemProvider),
  ),
);

