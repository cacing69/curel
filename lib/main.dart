import 'package:Curel/data/services/curl_http_client.dart';
import 'package:Curel/domain/services/clipboard_service.dart';
import 'package:Curel/presentation/screens/home_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

void main() {
  runApp(const Application());
}

class Application extends StatelessWidget {
  const Application({super.key});

  @override
  Widget build(BuildContext context) {
    final theme =
        const <TargetPlatform>{
          .android,
          .iOS,
          .fuchsia,
        }.contains(defaultTargetPlatform)
        ? FThemes.neutral.dark.touch
        : FThemes.neutral.dark.desktop;

    return MaterialApp(
      supportedLocales: FLocalizations.supportedLocales,
      localizationsDelegates: const [...FLocalizations.localizationsDelegates],
      theme: theme.toApproximateMaterialTheme(),
      builder: (_, child) => FTheme(
        data: FThemes.neutral.light.touch,
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
      home: FScaffold(
        child: HomePage(
          httpClient: DioCurlHttpClient(),
          clipboardService: FlutterClipboardService(),
        ),
      ),
    );
  }
}
