import 'package:curel/data/services/curl_http_client.dart';
import 'package:curel/domain/services/clipboard_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final ua = await _settingsService.getUserAgent();
    _httpClient.setUserAgent(ua);
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
        onUserAgentChanged: (ua) => _httpClient.setUserAgent(ua),
      ),
    );
  }
}
