import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/data/services/filesystem_service.dart';
import 'package:curel/domain/services/clipboard_service.dart';
import 'package:curel/domain/services/env_service.dart';
import 'package:curel/domain/services/history_service.dart';
import 'package:curel/domain/services/project_service.dart';
import 'package:curel/domain/services/request_service.dart';
import 'package:curel/domain/services/settings_service.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _httpClient = DioCurlHttpClient();
  final _settingsService = PreferencesSettingsService();
  final _fsService = LocalFileSystemService();
  final _historyService = HistoryService();
  late final EnvService _envService;
  late final ProjectService _projectService;
  late final RequestService _requestService;

  @override
  void initState() {
    super.initState();
    _envService = FileSystemEnvService(_fsService);
    _projectService = FilesystemProjectService(_fsService);
    _requestService = FilesystemRequestService(_fsService);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final ua = await _settingsService.getUserAgent();
    _httpClient.setUserAgent(ua);
    final workspace = await _settingsService.getEffectiveWorkspacePath();
    await _fsService.setWorkspaceRoot(workspace);
    if (mounted) setState(() {});
  }

  void _onWorkspaceChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TColors.background,
        colorScheme: const ColorScheme.dark(
          primary: TColors.accentText,
          surface: TColors.surface,
          error: TColors.error,
        ),
        textTheme: const TextTheme(
          bodySmall: TextStyle(fontFamily: 'monospace'),
          bodyMedium: TextStyle(fontFamily: 'monospace'),
          bodyLarge: TextStyle(fontFamily: 'monospace'),
        ),
      ),
      home: HomePage(
        httpClient: _httpClient,
        clipboardService: FlutterClipboardService(),
        settingsService: _settingsService,
        envService: _envService,
        projectService: _projectService,
        requestService: _requestService,
        historyService: _historyService,
        onUserAgentChanged: (ua) => _httpClient.setUserAgent(ua),
        fsService: _fsService,
        onWorkspaceChanged: _onWorkspaceChanged,
      ),
    );
  }
}
