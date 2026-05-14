import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/data/services/dio_http_client.dart';
import 'package:curel/data/services/libcurl_http_client.dart';
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
import 'package:curel/domain/services/device_service.dart';
import 'package:curel/domain/services/diff_service.dart';
import 'package:curel/domain/services/crash_log_service.dart';
import 'package:curel/domain/services/cookie_jar_service.dart';
import 'package:curel/domain/services/traffic_capture_service.dart';
import 'package:curel/domain/services/sample_service.dart';
import 'package:curel/domain/adapters/adapter_registry.dart';

final fileSystemProvider = Provider<FileSystemService>(
  (ref) => LocalFileSystemService(),
);

final settingsProvider = Provider<SettingsService>(
  (ref) => PreferencesSettingsService(),
);

final useCurlEngineProvider = StateProvider<bool>((ref) => false);

final curlClientProvider = Provider<CurlHttpClient>(
  (ref) {
    final useCurl = ref.watch(useCurlEngineProvider);
    if (useCurl && Platform.isAndroid) {
      return LibcurlHttpClient();
    }
    return DioHttpClient();
  },
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

final sampleServiceProvider = Provider<SampleService>(
  (ref) => FileSystemSampleService(ref.read(fileSystemProvider)),
);

final workspaceServiceProvider = Provider<WorkspaceService>(
  (ref) => WorkspaceServiceImpl(
    envService: ref.read(envServiceProvider),
    projectService: ref.read(projectServiceProvider),
    requestService: ref.read(requestServiceProvider),
    sampleService: ref.read(sampleServiceProvider),
    adapterRegistry: ref.read(adapterRegistryProvider),
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
    ref,
    ref.read(gitProviderServiceProvider),
    ref.read(fileSystemProvider),
    ref.read(deviceServiceProvider),
    ref.read(diffServiceProvider),
  ),
);

final deviceServiceProvider = Provider<DeviceService>(
  (ref) => DeviceService(),
);

final diffServiceProvider = Provider<DiffService>(
  (ref) => DiffService(),
);

final crashLogServiceProvider = Provider<CrashLogService>(
  (ref) => CrashLogService(),
);

final cookieJarServiceProvider = Provider<CookieJarService>(
  (ref) => FilesystemCookieJarService(ref.read(fileSystemProvider)),
);

final trafficCaptureServiceProvider = Provider<TrafficCaptureService>(
  (ref) => TrafficCaptureService(),
);

