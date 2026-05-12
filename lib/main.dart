import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/app_theme.dart';
import 'package:curel/presentation/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  int _workspaceKey = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsProvider);
    final fs = ref.read(fileSystemProvider);
    final httpClient = ref.read(httpClientProvider);
    final ua = await settings.getUserAgent();
    httpClient.setUserAgent(ua);
    final workspace = await settings.getEffectiveWorkspacePath();
    await fs.setWorkspaceRoot(workspace);

    // Load saved theme
    final themeId = await settings.getTheme();
    setAppTheme(themeId);

    await ref.read(syncControllerProvider).syncAndRefresh();
    if (mounted) setState(() {});
  }

  void _onWorkspaceChanged() async {
    await ref.read(syncControllerProvider).syncAndRefresh();
    if (mounted) setState(() => _workspaceKey++);
  }

  void _onUserAgentChanged(String ua) {
    ref.read(httpClientProvider).setUserAgent(ua);
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
