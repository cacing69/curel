import 'package:curel/domain/providers/services.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
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
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero),
        ),
        snackBarTheme: SnackBarThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      home: HomePage(
        key: ValueKey(_workspaceKey),
        onUserAgentChanged: _onUserAgentChanged,
        onWorkspaceChanged: _onWorkspaceChanged,
      ),
    );
  }
}
