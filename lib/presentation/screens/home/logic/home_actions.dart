import 'dart:convert';
import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/response_toolbar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

mixin HomeActions on ConsumerState<HomePage> {
  // These will be provided by HomePage
  TextEditingController get curlController;
  FocusNode get editorFocusNode;

  void exitFullscreen({bool unfocus = true});
  Future<void> loadRequest(String relativePath);

  String formatError(Object e) {
    final msg = e.toString().replaceFirst(
      RegExp(r'^(Exception|FormatException|TypeError):\s*'),
      '',
    );
    return 'error: $msg';
  }

  Future<CurlResponse> _executeRequest(
    WidgetRef ref,
    ParsedCurl parsed,
    Duration connectTimeout,
    Duration? maxTime, {
    required bool binary,
  }) async {
    final client = ref.read(httpClientProvider);

    // Use native libcurl directly for flags that need it
    if (parsed.needsNativeCurl && parsed.curlCommand.isNotEmpty) {
      return (await client.executeRaw(
        parsed.curlCommand,
        verbose: parsed.verbose,
        trace: parsed.traceEnabled,
        traceAscii: parsed.traceAscii,
      ))!;
    }

    final executor = binary ? client.executeBinary : client.execute;
    return executor(
      parsed.curl,
      verbose: parsed.verbose,
      followRedirects: parsed.followRedirects,
      trace: parsed.traceEnabled,
      traceAscii: parsed.traceAscii,
      connectTimeout: connectTimeout,
      maxTime: maxTime,
      insecure: parsed.insecure,
      httpVersion: parsed.httpVersion,
    );
  }

  Future<void> executeCurl() async {
    final text = curlController.text.trim();
    if (text.isEmpty || !text.startsWith('curl')) {
      ref
          .read(responseStateProvider.notifier)
          .update(
            (s) => s.copyWith(
              clearResponse: true,
              error: 'error: command must start with "curl"',
              showHtmlPreview: false,
            ),
          );
      exitFullscreen(unfocus: false);
      return;
    }

    ref
        .read(responseStateProvider.notifier)
        .update(
          (s) => s.copyWith(
            isLoading: true,
            clearResponse: true,
            clearError: true, clearLog: true,
            showHtmlPreview: false,
          ),
        );

    final es = ref.read(editorStateProvider);
    if (es.isFullscreen) exitFullscreen(unfocus: false);

    // auto-save if editing existing file
    final selectedPath = ref.read(selectedRequestPathProvider);
    if (selectedPath != null) {
      final projectId = ref.read(activeProjectProvider)?.id;
      if (projectId != null) {
        await ref
            .read(requestServiceProvider)
            .writeCurl(projectId, selectedPath, text);
        ref.read(editorStateProvider.notifier).update(
              (s) => s.copyWith(baselineCurlText: text),
            );
      }
    }

    await Future<void>.delayed(Duration.zero);

    // Merge .curlrc defaults (project-level curl config)
    final projectId = ref.read(activeProjectProvider)?.id;
    String effectiveText = text;
    if (projectId != null) {
      final curlrc = await ref.read(requestServiceProvider).readCurlrc(projectId);
      if (curlrc != null && curlrc.trim().isNotEmpty) {
        final flags = _parseCurlrcFlags(curlrc);
        if (flags.isNotEmpty) {
          // insert flags after 'curl' and before the rest of the command
          effectiveText = 'curl $flags ${text.substring(4).trim()}';
        }
      }
    }

    // Merge cookies from active cookie jar
    final activeJar = projectId != null
        ? await ref.read(cookieJarServiceProvider).getActiveJar(projectId)
        : null;
    if (activeJar != null && activeJar.cookies.isNotEmpty) {
      // Parse URL early to match cookies by domain
      final urlGuess = _extractUrlFromCurl(effectiveText);
      if (urlGuess != null) {
        final cookieHeader = ref.read(cookieJarServiceProvider).buildCookieHeader(activeJar, urlGuess);
        if (cookieHeader.isNotEmpty) {
          effectiveText = _injectCookieFlag(effectiveText, cookieHeader);
        }
      }
    }

    final sw = Stopwatch()..start();
    try {
      final shouldResolve = effectiveText.contains('<<');
      final resolved = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .resolve(effectiveText, projectId: projectId)
          : effectiveText;

      final undefined = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .findUndefinedVars(effectiveText, projectId: projectId)
          : const <String>{};

      if (undefined.isNotEmpty) {
        if (mounted) {
          showTerminalToast(context, 'undefined vars: ${undefined.join(', ')}');
          ref
              .read(responseStateProvider.notifier)
              .update(
                (s) => s.copyWith(
                  error: 'error: undefined vars: ${undefined.join(', ')}',
                ),
              );
        }
        return;
      }

      ParsedCurl parsed;
      try {
        parsed = parseCurl(resolved);
      } catch (e) {
        // If parsing fails, try ensuring protocol (useful for commands like 'curl example.com')
        try {
          final withProtocol = _ensureProtocol(resolved);
          parsed = parseCurl(withProtocol);
        } catch (_) {
          // If it still fails, throw the original error
          rethrow;
        }
      }
      final hasOutput = parsed.outputFileName != null;

      final effectiveConnectTimeout =
          parsed.connectTimeout ??
          Duration(
            seconds: await ref.read(settingsProvider).getConnectTimeout(),
          );

      final effectiveMaxTime =
          parsed.maxTime ??
          ((await ref.read(settingsProvider).getMaxTime()) > 0
              ? Duration(seconds: await ref.read(settingsProvider).getMaxTime())
              : null);

      final result = hasOutput
          ? await _executeRequest(
              ref, parsed, effectiveConnectTimeout, effectiveMaxTime, binary: true)
          : await _executeRequest(
              ref, parsed, effectiveConnectTimeout, effectiveMaxTime, binary: false);

      final elapsed = sw.elapsedMilliseconds;
      if (elapsed < 500) {
        await Future.delayed(Duration(milliseconds: 500 - elapsed));
      }

      final newTab = (parsed.traceEnabled && result.traceLog != null)
          ? ResponseTab.trace
          : ResponseTab.body;

      if (mounted) {
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(response: result, selectedTab: newTab));

        if (hasOutput) {
          await downloadFile(result, parsed.outputFileName!);
        }

        if (parsed.traceFileName != null &&
            result.traceLog != null &&
            result.traceLog!.isNotEmpty) {
          await downloadFile(
            CurlResponse(
              body: result.traceLog,
              statusCode: 0,
              headers: {},
              statusMessage: '',
            ),
            parsed.traceFileName!,
          );
        }
      }

      // History & Meta updates...
      _updateMetadataAndHistory(text, result, parsed, projectId);

      // Capture Set-Cookie into active jar
      if (projectId != null && activeJar != null) {
        final updatedJar = ref.read(cookieJarServiceProvider).captureSetCookies(
              result.headers,
              parsed.curl.uri,
              activeJar,
            );
        if (!identical(updatedJar.cookies, activeJar.cookies)) {
          await ref.read(cookieJarServiceProvider).saveJar(projectId, updatedJar);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = formatError(e);
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(error: msg));
        showTerminalToast(context, msg);
      }
    } finally {
      if (mounted) {
        ref
            .read(responseStateProvider.notifier)
            .update((s) => s.copyWith(isLoading: false));
      }
    }
  }

  Future<void> _updateMetadataAndHistory(
    String text,
    CurlResponse result,
    ParsedCurl parsed,
    String? projectId,
  ) async {
    final projectId2 = ref.read(activeProjectProvider)?.id;
    final selectedPath = ref.read(selectedRequestPathProvider);
    if (projectId2 != null && selectedPath != null) {
      await ref
          .read(requestServiceProvider)
          .updateMeta(
            projectId2,
            selectedPath,
            RequestMeta(
              lastStatusCode: result.statusCode,
              lastRunAt: DateTime.now(),
            ),
          );
    }

    await ref
        .read(historyServiceProvider)
        .add(
          HistoryItem(
            timestamp: DateTime.now(),
            curlCommand: text,
            projectId: projectId,
            statusCode: result.statusCode,
            method: parsed.curl.method,
            url: parsed.curl.uri.toString(),
          ),
        );
  }

  Future<void> downloadFile(CurlResponse response, String fileName) async {
    try {
      final bytes = response.body is List<int>
          ? response.body as List<int>
          : utf8.encode(response.body?.toString() ?? '');
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'save file',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );
      if (path != null && mounted) {
        showTerminalToast(context, 'saved to $fileName');
      }
    } catch (e) {
      if (mounted) showTerminalToast(context, 'error: $e');
    }
  }

  Future<void> copyToClipboard(String text, String label) async {
    if (text.isEmpty) {
      showTerminalToast(context, '$label empty');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    showTerminalToast(context, '$label copied');
  }

  String _ensureProtocol(String command) {
    // Clean backslashes and newlines first
    final cleanCommand = command.replaceAll("\\\n", " ").replaceAll("\\", " ");
    final tokens = cleanCommand.split(RegExp(r'\s+'));
    final updated = tokens.map((t) {
      final clean = t.replaceAll("'", "").replaceAll('"', "");
      if (clean.isEmpty) return t;

      // DO NOT add protocol to:
      // 1. Flags (-X, -F, etc)
      // 2. Already has protocol (http://)
      // 3. File paths or form data starting with @
      // 4. Variables ($VAR or <<VAR>>)
      // 5. Local paths (/ or ./)
      final isForbidden = clean.startsWith('-') ||
          clean.contains('://') ||
          clean.contains('=') ||
          clean.startsWith('@') ||
          clean.startsWith('\$') ||
          clean.startsWith('<<') ||
          clean.startsWith('/') ||
          clean.startsWith('./');

      if (isForbidden) return t;

      // Only add http:// if it contains a dot (likely a domain)
      if (clean.contains('.')) {
        if (t.startsWith("'") && t.endsWith("'")) return "'http://$clean'";
        if (t.startsWith('"') && t.endsWith('"')) return '"http://$clean"';
        return 'http://$t';
      }
      return t;
    });
    return updated.join(' ');
  }

  String _parseCurlrcFlags(String content) {
    final flags = <String>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      flags.add(trimmed);
    }
    return flags.join(' ');
  }

  Uri? _extractUrlFromCurl(String text) {
    final cleaned = text.replaceAll('\\\n', ' ').replaceAll('\\', ' ');
    final tokens = cleaned.split(RegExp(r'\s+'));
    for (final token in tokens) {
      final unquoted = token.replaceAll("'", '').replaceAll('"', '');
      if (unquoted.startsWith('http://') || unquoted.startsWith('https://')) {
        return Uri.tryParse(unquoted);
      }
    }
    return null;
  }

  String _injectCookieFlag(String text, String cookieHeader) {
    final escaped = cookieHeader.replaceAll("'", "'\\''");
    return 'curl -b \'$escaped\' ${text.substring(4).trim()}';
  }
}
