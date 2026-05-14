import 'dart:async';
import 'dart:io';

import 'package:curel/data/services/libcurl_http_client.dart';
import 'package:curel/domain/models/crash_log_model.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/crash_log_service.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/app_theme.dart';
import 'package:curel/presentation/theme/app_tokens.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    final crashLog = CrashLogService();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      crashLog.log(
        Severity.critical,
        'flutter',
        details.exceptionAsString(),
        stackTrace: details.stack?.toString(),
      );
    };
    runApp(ProviderScope(
      overrides: [crashLogServiceProvider.overrideWithValue(crashLog)],
      child: const App(),
    ));
  }, (error, stack) {
    debugPrint('unhandled: $error');
  });
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  int _workspaceKey = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _initCaBundle() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final caFile = File('${dir.path}/cacert.pem');
      if (!await caFile.exists()) {
        final data = await rootBundle.load('assets/cacert.pem');
        await caFile.writeAsBytes(data.buffer.asUint8List());
      }
      LibcurlHttpClient.caBundlePath = caFile.path;
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsProvider);
    final fs = ref.read(fileSystemProvider);
    final ua = await settings.getUserAgent();
    final useCurl = await settings.getUseCurlEngine();
    ref.read(useCurlEngineProvider.notifier).state = useCurl;

    final httpClient = ref.read(curlClientProvider);
    httpClient.setUserAgent(ua);

    if (httpClient is LibcurlHttpClient) {
      await _initCaBundle();
      httpClient.ensureLoaded();
    }

    final workspace = await settings.getEffectiveWorkspacePath();
    await fs.setWorkspaceRoot(workspace);

    final themeId = await settings.getTheme();
    setAppTheme(themeId);

    await ref.read(syncControllerProvider).syncAndRefresh();
    if (mounted) setState(() => _ready = true);
  }

  void _onWorkspaceChanged() async {
    await ref.read(syncControllerProvider).syncAndRefresh();
    if (mounted) setState(() => _workspaceKey++);
  }

  void _onUserAgentChanged(String ua) {
    ref.read(curlClientProvider).setUserAgent(ua);
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildThemeData(),
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A1A),
          body: Center(
            child: TerminalLoader(),
          ),
        ),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildThemeData(),
      home: HomePage(
        key: ValueKey(_workspaceKey),
        onUserAgentChanged: _onUserAgentChanged,
        onWorkspaceChanged: _onWorkspaceChanged,
        onThemeChanged: _onThemeChanged,
      ),
    );
  }
}
