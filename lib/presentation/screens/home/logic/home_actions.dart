import 'dart:convert';
import 'package:curel/data/models/curl_response.dart';
import 'package:curel/domain/models/history_model.dart';
import 'package:curel/domain/models/request_model.dart';
import 'package:curel/domain/providers/app_state.dart';
import 'package:curel/domain/providers/services.dart';
import 'package:curel/domain/services/curl_parser_service.dart';
import 'package:curel/presentation/screens/home_page.dart';
import 'package:curel/presentation/theme/terminal_theme.dart';
import 'package:curel/presentation/widgets/response_viewer.dart';
import 'package:dio/dio.dart';
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
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError:
          return 'error: connection failed — host unreachable';
        case DioExceptionType.connectionTimeout:
          return 'error: connection timed out';
        case DioExceptionType.receiveTimeout:
          return 'error: response timed out';
        case DioExceptionType.unknown:
          return 'error: ${e.error}';
        default:
          return 'error: request failed (${e.type.name})';
      }
    }
    final msg = e.toString().replaceFirst(
      RegExp(r'^(Exception|FormatException|TypeError):\s*'),
      '',
    );
    return 'error: $msg';
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
            clearError: true,
            showHtmlPreview: false,
          ),
        );

    final es = ref.read(editorStateProvider);
    if (es.isFullscreen) exitFullscreen(unfocus: false);

    await Future<void>.delayed(Duration.zero);

    final sw = Stopwatch()..start();
    try {
      final projectId = ref.read(activeProjectProvider)?.id;
      final shouldResolve = text.contains('<<');
      final resolved = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .resolve(text, projectId: projectId)
          : text;

      final undefined = shouldResolve
          ? await ref
                .read(envServiceProvider)
                .findUndefinedVars(text, projectId: projectId)
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

      final parsed = parseCurl(resolved);
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
          ? await ref
                .read(httpClientProvider)
                .executeBinary(
                  parsed.curl,
                  verbose: parsed.verbose,
                  followRedirects: parsed.followRedirects,
                  trace: parsed.traceEnabled,
                  traceAscii: parsed.traceAscii,
                  connectTimeout: effectiveConnectTimeout,
                  maxTime: effectiveMaxTime,
                  insecure: parsed.insecure,
                  httpVersion: parsed.httpVersion,
                )
          : await ref
                .read(httpClientProvider)
                .execute(
                  parsed.curl,
                  verbose: parsed.verbose,
                  followRedirects: parsed.followRedirects,
                  trace: parsed.traceEnabled,
                  traceAscii: parsed.traceAscii,
                  connectTimeout: effectiveConnectTimeout,
                  maxTime: effectiveMaxTime,
                  insecure: parsed.insecure,
                  httpVersion: parsed.httpVersion,
                );

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
}
