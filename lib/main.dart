import 'package:Curel/data/services/curl_http_client.dart';
import 'package:Curel/domain/services/clipboard_service.dart';
import 'package:Curel/presentation/screens/home_page.dart';
import 'package:Curel/presentation/theme/terminal_colors.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

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
        httpClient: DioCurlHttpClient(),
        clipboardService: FlutterClipboardService(),
      ),
    );
  }
}
